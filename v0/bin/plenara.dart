/// Plenara v0 walking skeleton — the turn loop (Spec 04 DispatchOrchestrator,
/// thinned). Text-first console: utterance -> route -> resolve -> execute ->
/// persist -> describe (act-then-describe).
///
///   dart run bin/plenara.dart              # interactive REPL
///   dart run bin/plenara.dart --demo       # scripted demo
///   dart run bin/plenara.dart "log a 3k run"   # one-shot
library;

import 'dart:convert';
import 'dart:io';
import 'package:plenara/claude.dart';
import 'package:plenara/interpreter.dart';
import 'package:plenara/router.dart';
import 'package:plenara/store.dart';

const dataDir = 'data';

const demoUtterances = [
  'add call the plumber to my to-do list',
  'undo that',
  "remember that Mia is allergic to peanuts and she is Sarah Mitchell's daughter",
  'log a 3k run',
  'how many km have I run this week', // reflects the run just logged (write -> read)
  "i'm feeling good",
  'jot down that I need to buy milk', // novel phrasing -> retrieval clarify (§13)
];

/// Persist a learned corpus template (§5.2). Per-user data -> data/corpus-learned.json.
void persistLearned(String skillId, String template) {
  final f = File('$dataDir/corpus-learned.json');
  final list = f.existsSync() ? (jsonDecode(f.readAsStringSync()) as List) : <dynamic>[];
  list.add({'skillId': skillId, 'template': template});
  f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(list));
}

void seedForDemo(Map<String, Map<String, dynamic>> store, DateTime now) {
  String d(int days) {
    final dt = now.add(Duration(days: days));
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  for (final r in <Map<String, dynamic>>[
    {'id': 'contact-seed1', 'typeId': 'contact', 'displayName': 'Sarah Mitchell', 'birthday': '1990-11-14'},
    {'id': 'workout-s1', 'typeId': 'workout', 'activity': 'run', 'distance': 5, 'date': d(0)},
    {'id': 'workout-s2', 'typeId': 'workout', 'activity': 'run', 'distance': 3, 'date': d(1)},
    {'id': 'workout-s3', 'typeId': 'workout', 'activity': 'run', 'distance': 10, 'date': d(-8)},
    {'id': 'workout-s4', 'typeId': 'workout', 'activity': 'walk', 'distance': 2, 'date': d(0)},
  ]) {
    store[r['id']] = r;
  }
}

Future<void> main(List<String> args) async {
  final types = loadDefs('$dataDir/types', 'typeId');
  final skills = loadDefs('$dataDir/skills', 'skillId');
  final store = loadRecords('$dataDir/records');

  final now = DateTime.parse('2026-07-06T09:00:00'); // frozen clock for a reproducible demo
  final interp = Interpreter(types, now);
  final router = Router.load('$dataDir/corpus.json', now,
      learnedPath: '$dataDir/corpus-learned.json');
  final claude = ClaudeClient();
  final dev = HlcDevice('this-device');

  for (final s in skills.values) {
    interp.validateSkill(s); // authoring-time static gate (Spec 02 §6.4)
  }
  await router.buildRetrievalIndex(skills); // cold-start candidate index (no-op if embed server down)
  stdout.writeln('loaded ${types.length} types + ${skills.length} skills '
      '(${store.length} persisted records); all skills pass static validation; retrieval index ready\n');

  seedForDemo(store, now);

  final undoRe = RegExp(r'^(undo|undo that|no,? take that back|scratch that)\.?$', caseSensitive: false);
  Map<String, Map<String, dynamic>?>? lastBefore; // most recent write turn's before-images

  Future<void> handle(String u) async {
    stdout.writeln('U: $u');
    if (undoRe.hasMatch(u.trim())) {
      // `undo` is a system command (Spec 03 §2.3), not a skill
      if (lastBefore == null) {
        stdout.writeln('A: Nothing to undo.\n');
      } else {
        undoTurn(lastBefore!, '$dataDir/records', dev, store);
        stdout.writeln('A: Undone.\n');
        lastBefore = null;
      }
      return;
    }

    // correction with a restatement (§5.2, the strong learning signal): "no, I meant to X"
    final corrM = RegExp(r'^(?:no,?|actually,?|nope,?)\s+i meant (?:to |it was )?(.+?)\.?$',
            caseSensitive: false)
        .firstMatch(u.trim());
    if (corrM != null) {
      if (lastBefore != null) {
        undoTurn(lastBefore!, '$dataDir/records', dev, store);
        lastBefore = null;
        stdout.writeln('A: Got it — undoing that. Let me redo:');
      }
      await handle(corrM.group(1)!.trim()); // re-route the corrected request
      return;
    }

    // meta-intent: a "track my X" the app doesn't have -> AUTHOR it (Spec 02 §6, emergent types)
    final defM = RegExp(r'^(?:start tracking|track|i want to track|i want to start tracking|make me a|create a) '
            r'(?:my |a |an )?(.+?)(?: tracker)?\.?$',
            caseSensitive: false)
        .firstMatch(u.trim());
    if (defM != null && router.route(u) == null) {
      final desc = defM.group(1)!;
      // Layer 1 (G-30 / findings §10.3): deterministic app-side policy floor — hard-block
      // known-harmful capability shapes BEFORE any authoring call, regardless of the model.
      if (RegExp(
              r'(track|monitor|spy|surveil|watch).{0,30}(partner|spouse|wife|husband|someone|him|her|them|kid|child)'
              r'|without (their|his|her) (knowledge|consent|permission)|secretly|covert'
              r'|self.?harm|hurt (myself|someone|somebody)|weapon|purg(e|ing)|restrict.{0,10}calorie',
              caseSensitive: false)
          .hasMatch('$desc $u')) {
        stdout.writeln("A: I can't build that — it looks like it could monitor someone without consent or "
            "cause harm, and I won't create tools for that. [G-30 policy floor]\n");
        return;
      }
      stdout.writeln('A: I don\'t have that yet — authoring a capability for "$desc"…');
      final authored = await claude.authorCapability(desc);
      if (authored == null) {
        stdout.writeln('A: I couldn\'t build that right now.\n');
        return;
      }
      try {
        final type = (authored['type'] as Map).cast<String, dynamic>();
        final skill = (authored['skill'] as Map).cast<String, dynamic>();
        types[type['typeId'] as String] = type;      // register type (shared map -> interp sees it)
        interp.validateSkill(skill);                 // deterministic static gate (throws if invalid)
        skills[skill['skillId'] as String] = skill;
        File('$dataDir/types/${type['typeId']}.json')
            .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(type));
        File('$dataDir/skills/${skill['skillId']}.json')
            .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(skill));
        await router.buildRetrievalIndex(skills);    // the new skill joins routing
        final eg = (skill['examplePhrases'] as List?)?.cast<String>();
        stdout.writeln('A: Built "${skill['displayName']}" — a new capability, authored and validated. '
            '${eg != null && eg.isNotEmpty ? 'Try: "${eg.first}".' : ''}\n'
            '   [AI authored -> deterministic validators passed -> registered as data]\n');
      } on ResolveError catch (e) {
        stdout.writeln('A: I drafted that but it failed validation ($e) — not registered.\n');
      }
      return;
    }

    // Spec 03 §7.3 cascade: corpus fast-path -> Haiku residual (online, BYOK) -> clarify
    var routed = router.route(u);
    routed ??= await claude.routeResidual(u, skills);
    if (routed == null) {
      final sg = await router.retrievalSuggest(u);
      if (sg == null) {
        stdout.writeln("A: I didn't catch that (retrieval unavailable).\n");
      } else {
        final name = skills[sg['skillId']]!['displayName'];
        final s1 = (sg['s1'] as double).toStringAsFixed(2);
        if (sg['confident'] == true) {
          stdout.writeln('A: I don\'t have that phrasing learned — did you mean to "$name"? '
              'Say it a known way and I\'ll learn it. [retrieval $s1]\n');
        } else {
          stdout.writeln('A: I\'m not sure what you meant — closest is "$name" ($s1), below my '
              'confidence bar, so I won\'t guess. Could you rephrase? [§13: retrieval is a weak cold-start router]\n');
        }
      }
      return;
    }
    try {
      final plan = interp.resolve(skills[routed['skillId']]!, routed['slots'], store);
      final before = interp.execute(plan, store);
      for (final w in plan.writes) {
        persist(w, '$dataDir/records', dev);
      }
      if (plan.writes.isNotEmpty) lastBefore = before;
      final via = routed['source'] == 'cloud' ? '  [routed via Haiku — residual, §13]' : '';
      stdout.writeln('A: ${plan.confirmation}$via');
      if (plan.writes.isNotEmpty) {
        stdout.writeln('   [wrote ${plan.writes.map((w) => w['typeId']).join(', ')} — persisted with _meta CRDT block]');
      }
      // the "gets better" ratchet (§5.2): a cloud-routed turn learns its phrasing
      if (routed['source'] == 'cloud') {
        final tmpl = router.learn(u, routed['skillId'] as String,
            (routed['slots'] as Map).cast<String, dynamic>());
        if (tmpl != null) {
          persistLearned(routed['skillId'] as String, tmpl);
          stdout.writeln('   [learned: "$tmpl" -> ${routed['skillId']} — next time no cloud call]');
        }
      }
      stdout.writeln('');
    } on ResolveError catch (e) {
      stdout.writeln("A: (couldn't: $e)\n");
    }
  }

  if (args.contains('--demo')) {
    for (final u in demoUtterances) {
      await handle(u);
    }
  } else if (args.isNotEmpty) {
    await handle(args.join(' '));
  } else {
    stdout.writeln('Plenara v0 — type a request, or "quit". Try: "add X to my list", '
        '"log a 3k run", "remember that NAME FACT", "how many km have I run this week", "undo that".\n');
    while (true) {
      stdout.write('> ');
      final line = stdin.readLineSync();
      if (line == null || const ['quit', 'exit', 'q'].contains(line.trim().toLowerCase())) break;
      if (line.trim().isEmpty) continue;
      await handle(line.trim());
    }
    stdout.writeln('bye.');
  }
}
