/// Plenara v0 — the turn engine as a reusable service (Spec 04 DispatchOrchestrator).
/// Both the console (bin/plenara.dart) and the Flutter UI drive this. `handle`
/// returns the response text instead of printing, so any front-end can present it.
library;

import 'dart:convert';
import 'dart:io';

import 'claude.dart';
import 'interpreter.dart';
import 'router.dart';
import 'store.dart';

final _undoRe = RegExp(r'^(undo|undo that|no,? take that back|scratch that)\.?$', caseSensitive: false);
final _corrRe = RegExp(r'^(?:no,?|actually,?|nope,?)\s+i meant (?:to |it was )?(.+?)\.?$', caseSensitive: false);
final _defRe = RegExp(
    r'^(?:start tracking|track|i want to track|i want to start tracking|make me a|create a) '
    r'(?:my |a |an )?(.+?)(?: tracker)?\.?$',
    caseSensitive: false);
final _harmfulRe = RegExp(
    r'(track|monitor|spy|surveil|watch).{0,30}(partner|spouse|wife|husband|someone|him|her|them|kid|child)'
    r'|without (their|his|her) (knowledge|consent|permission)|secretly|covert'
    r'|self.?harm|hurt (myself|someone|somebody)|weapon|purg(e|ing)|restrict.{0,10}calorie',
    caseSensitive: false);

class Session {
  final String dataDir;
  final DateTime now;
  late Map<String, Map<String, dynamic>> types;
  late Map<String, Map<String, dynamic>> skills;
  late Map<String, Map<String, dynamic>> store;
  late Interpreter interp;
  late Router router;
  late CloudClient claude;
  late HlcDevice dev;
  final CloudClient? _injectedCloud;
  Map<String, Map<String, dynamic>?>? _lastBefore;

  /// [cloud] lets tests inject a replay/mock client (lib/replay_cloud.dart) so
  /// the residual-routing and authoring paths run offline against recorded
  /// real responses. Production leaves it null -> a live ClaudeClient.
  Session(this.dataDir, {DateTime? clock, CloudClient? cloud})
      : now = clock ?? DateTime.now(),
        _injectedCloud = cloud;

  /// [retrieval] builds the embedding index (needs the embed server). Tests pass
  /// false to stay hermetic — the corpus fast-path and injected cloud need no
  /// embeddings; only the cold-start suggestion on a full miss does.
  Future<void> init({bool retrieval = true}) async {
    types = loadDefs('$dataDir/types', 'typeId');
    skills = loadDefs('$dataDir/skills', 'skillId');
    store = loadRecords('$dataDir/records');
    interp = Interpreter(types, now);
    router = Router.load('$dataDir/corpus.json', now, learnedPath: '$dataDir/corpus-learned.json');
    claude = _injectedCloud ?? ClaudeClient();
    dev = HlcDevice('this-device');
    for (final s in skills.values) {
      interp.validateSkill(s);
    }
    if (retrieval) await router.buildRetrievalIndex(skills);
  }

  void _persistLearned(String skillId, String template) {
    final f = File('$dataDir/corpus-learned.json');
    final list = f.existsSync() ? (jsonDecode(f.readAsStringSync()) as List) : <dynamic>[];
    list.add({'skillId': skillId, 'template': template});
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(list));
  }

  /// Process one utterance; returns the assistant's response text (may be multi-line).
  Future<String> handle(String u) async {
    u = u.trim();
    if (_undoRe.hasMatch(u)) {
      if (_lastBefore == null) return 'Nothing to undo.';
      undoTurn(_lastBefore!, '$dataDir/records', dev, store);
      _lastBefore = null;
      return 'Undone.';
    }

    final corr = _corrRe.firstMatch(u);
    if (corr != null) {
      var pre = '';
      if (_lastBefore != null) {
        undoTurn(_lastBefore!, '$dataDir/records', dev, store);
        _lastBefore = null;
        pre = 'Got it — undid that. ';
      }
      return '$pre${await handle(corr.group(1)!.trim())}';
    }

    final def = _defRe.firstMatch(u);
    if (def != null && router.route(u) == null) {
      final desc = def.group(1)!;
      if (_harmfulRe.hasMatch('$desc $u')) {
        return "I can't build that — it could monitor someone without consent or cause harm, "
            "and I won't create tools for that.";
      }
      String? priorError;
      for (var attempt = 1; attempt <= 2; attempt++) {
        final authored = await claude.authorCapability(desc, priorError: priorError);
        if (authored == null) return "I couldn't build that right now (offline or no key).";
        final type = (authored['type'] as Map).cast<String, dynamic>();
        final skill = (authored['skill'] as Map).cast<String, dynamic>();
        try {
          types[type['typeId'] as String] = type;
          interp.validateSkill(skill);
          skills[skill['skillId'] as String] = skill;
          File('$dataDir/types/${type['typeId']}.json')
              .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(type));
          File('$dataDir/skills/${skill['skillId']}.json')
              .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(skill));
          await router.buildRetrievalIndex(skills);
          final eg = (skill['examplePhrases'] as List?)?.cast<String>();
          return 'Built "${skill['displayName']}" — a new capability, authored and validated.'
              '${eg != null && eg.isNotEmpty ? ' Try: "${eg.first}".' : ''}';
        } on ResolveError catch (e) {
          types.remove(type['typeId']);
          priorError = e.message;
          if (attempt == 2) return 'I drafted that but it failed validation — not registered.';
        }
      }
    }

    var routed = router.route(u);
    routed ??= await claude.routeResidual(u, skills);
    if (routed == null) {
      final sg = await router.retrievalSuggest(u);
      if (sg == null) return "I didn't catch that.";
      final name = skills[sg['skillId']]!['displayName'];
      final s1 = (sg['s1'] as double).toStringAsFixed(2);
      return sg['confident'] == true
          ? 'I don\'t have that phrasing learned — did you mean to "$name"? Say it a known way and I\'ll learn it.'
          : 'I\'m not sure what you meant — closest is "$name" ($s1), below my confidence bar, so I won\'t guess.';
    }
    try {
      final plan = interp.resolve(skills[routed['skillId']]!, routed['slots'], store);
      final before = interp.execute(plan, store);
      for (final w in plan.writes) {
        persist(w, '$dataDir/records', dev);
      }
      if (plan.writes.isNotEmpty) _lastBefore = before;
      if (routed['source'] == 'cloud') {
        final tmpl = router.learn(u, routed['skillId'] as String,
            (routed['slots'] as Map).cast<String, dynamic>());
        if (tmpl != null) _persistLearned(routed['skillId'] as String, tmpl);
      }
      return plan.confirmation ?? 'Done.';
    } on ResolveError catch (e) {
      return "Couldn't do that: ${e.message}";
    }
  }
}
