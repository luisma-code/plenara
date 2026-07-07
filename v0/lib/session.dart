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
// Layer-1 policy floor (Spec 02 §7.6): key on harmful FRAMING, never merely a
// sensitive topic. "track my kid's mood" (the flagship marquee) is fine; "track
// my kid secretly / without their knowledge" is not. Layers 2/3 (model + review)
// are v2.
final _harmfulRe = RegExp(
    // covert / non-consensual surveillance framing
    r"secretly|covertly|without (?:their|his|her|your) (?:knowledge|consent|permission)"
    r"|behind (?:their|his|her) back|\bspy on\b|\bstalk\b|keep tabs on|\bsnoop\b"
    // self-harm, weapons, disordered-eating framing
    r"|self.?harm|hurt (?:myself|someone|somebody)|make a weapon|build a weapon"
    r"|purge (?:after|my|food|meal)|hide (?:my )?(?:eating|calories)|restrict (?:my )?calories",
    caseSensitive: false);
// authored ids are model output; keep them out of file paths and odd charsets
final _idRe = RegExp(r'^[a-z0-9_-]{1,64}$');

class Session {
  final String dataDir;
  final DateTime? _fixedClock;
  /// The clock, read live per access so a long-open app never freezes at launch
  /// time (Spec 03 §4 wants a per-turn snapshot). Tests/the demo pin it via the
  /// [clock] constructor arg for reproducibility.
  DateTime get now => _fixedClock ?? DateTime.now();
  late Map<String, Map<String, dynamic>> types;
  late Map<String, Map<String, dynamic>> skills;
  late Map<String, Map<String, dynamic>> store;
  late Interpreter interp;
  late Router router;
  late CloudClient claude;
  late HlcDevice dev;
  final CloudClient? _injectedCloud;
  Map<String, Map<String, dynamic>?>? _lastBefore;
  String? _lastActionDesc; // what the last undoable turn did, for a transparent undo

  /// [cloud] lets tests inject a replay/mock client (lib/replay_cloud.dart) so
  /// the residual-routing and authoring paths run offline against recorded
  /// real responses. Production leaves it null -> a live ClaudeClient.
  Session(this.dataDir, {DateTime? clock, CloudClient? cloud})
      : _fixedClock = clock,
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

  /// Public entry: a catch-all boundary so NO exception (ResolveError or a raw
  /// TypeError/RangeError from model-shaped input) ever escapes into the UI or
  /// console. A crash becomes a visible, non-destructive message (no silent
  /// failure, P7) rather than a bricked input box.
  Future<String> handle(String u) async {
    try {
      return await _handle(u.trim());
    } catch (e) {
      return "Sorry — something went wrong handling that, so I didn't do anything. ($e)";
    }
  }

  /// Process one utterance; returns the assistant's response text (may be multi-line).
  Future<String> _handle(String u) async {
    u = u.trim();
    final now = this.now; // one frozen snapshot for the whole turn
    if (_undoRe.hasMatch(u)) {
      if (_lastBefore == null) return 'Nothing to undo.';
      undoTurn(_lastBefore!, '$dataDir/records', dev, store);
      _lastBefore = null;
      final d = _lastActionDesc;
      _lastActionDesc = null;
      // say WHAT was reversed — a silent "Undone." can't be trusted as the safety net
      return d == null ? 'Undone.' : 'Undone — reversed: "$d"';
    }

    final corr = _corrRe.firstMatch(u);
    if (corr != null) {
      var pre = '';
      if (_lastBefore != null) {
        undoTurn(_lastBefore!, '$dataDir/records', dev, store);
        _lastBefore = null;
        _lastActionDesc = null;
        pre = 'Got it — undid that. ';
      }
      return '$pre${await _handle(corr.group(1)!.trim())}';
    }

    final def = _defRe.firstMatch(u);
    if (def != null && router.route(u, clock: now) == null) {
      final desc = def.group(1)!;
      if (_harmfulRe.hasMatch('$desc $u')) {
        return "I can't build that — it could monitor someone without consent or cause harm, "
            "and I won't create tools for that.";
      }
      String? priorError;
      for (var attempt = 1; attempt <= 2; attempt++) {
        final authored = await claude.authorCapability(desc, priorError: priorError);
        if (authored == null) return "I couldn't build that right now (offline or no key).";
        String? addedTypeId; // rollback removes ONLY a type we registered this attempt
        try {
          final type = (authored['type'] as Map).cast<String, dynamic>();
          final skill = (authored['skill'] as Map).cast<String, dynamic>();
          final typeId = type['typeId'], skillId = skill['skillId'];
          if (typeId is! String || skillId is! String) {
            throw ResolveError('authored capability is missing a string typeId/skillId');
          }
          if (!_idRe.hasMatch(typeId) || !_idRe.hasMatch(skillId)) {
            // model-controlled ids must never steer a file path or carry odd chars
            throw ResolveError('authored id must match [a-z0-9_-] (1-64 chars)');
          }
          if (types.containsKey(typeId) || skills.containsKey(skillId)) {
            // never overwrite a built-in / existing capability
            throw ResolveError('a capability like "$skillId" already exists — nothing built');
          }
          interp.validateType(type);
          types[typeId] = type;
          addedTypeId = typeId;
          interp.validateSkill(skill);
          skills[skillId] = skill;
          File('$dataDir/types/$typeId.json')
              .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(type));
          File('$dataDir/skills/$skillId.json')
              .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(skill));
          await router.buildRetrievalIndex(skills);
          final eg = (skill['examplePhrases'] as List?)?.cast<String>();
          return 'Built "${skill['displayName'] ?? skillId}" — a new capability, authored and validated.'
              '${eg != null && eg.isNotEmpty ? ' Try: "${eg.first}".' : ''}';
        } catch (e) {
          if (addedTypeId != null) types.remove(addedTypeId); // safe rollback
          priorError = e is ResolveError ? e.message : e.toString();
          if (attempt == 2) return 'I drafted that but it could not be validated — nothing was registered.';
        }
      }
    }

    var routed = router.route(u, clock: now);
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
    // normalize leaked sentinel slot values from any source before they reach a
    // resolver (a replayed/live "none" for an absent date would otherwise persist
    // as garbage; the crash it once caused is already handled in _asDate).
    (routed['slots'] as Map?)?.updateAll(
        (k, v) => (v is String && const {'none', 'null'}.contains(v.trim().toLowerCase())) ? null : v);
    try {
      final turnInterp = Interpreter(types, now); // per-turn clock (Spec 03 §4)
      final plan = turnInterp.resolve(skills[routed['skillId']]!, routed['slots'], store);
      final before = turnInterp.execute(plan, store);
      for (final w in plan.writes) {
        persist(w, '$dataDir/records', dev);
      }
      for (final id in plan.deletes) {
        tombstone(id, '$dataDir/records', dev);
      }
      if (plan.writes.isNotEmpty || plan.deletes.isNotEmpty) {
        _lastBefore = before;
        _lastActionDesc = plan.confirmation;
      }
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
