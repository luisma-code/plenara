/// Plenara v0 walking skeleton — the turn loop (Spec 04 DispatchOrchestrator,
/// thinned). Text-first console: utterance -> route -> resolve -> execute ->
/// persist -> describe (act-then-describe). The router here is a PLACEHOLDER for
/// the Spec 03 corpus + retrieval design (separately validated); the point of the
/// skeleton is that every layer boundary connects, in real Dart.
library;

import 'dart:io';
import 'package:plenara/interpreter.dart';
import 'package:plenara/router.dart';
import 'package:plenara/store.dart';

const dataDir = 'data';

void seedForDemo(Map<String, Map<String, dynamic>> store, DateTime now) {
  String d(int days) {
    final dt = now.add(Duration(days: days));
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
  final seeds = <Map<String, dynamic>>[
    {'id': 'contact-seed1', 'typeId': 'contact', 'displayName': 'Sarah Mitchell', 'birthday': '1990-11-14'},
    {'id': 'workout-s1', 'typeId': 'workout', 'activity': 'run', 'distance': 5, 'date': d(0)},
    {'id': 'workout-s2', 'typeId': 'workout', 'activity': 'run', 'distance': 3, 'date': d(1)},
    {'id': 'workout-s3', 'typeId': 'workout', 'activity': 'run', 'distance': 10, 'date': d(-8)},
    {'id': 'workout-s4', 'typeId': 'workout', 'activity': 'walk', 'distance': 2, 'date': d(0)},
  ];
  for (final r in seeds) {
    store[r['id']] = r;
  }
}

Future<void> main(List<String> args) async {
  final types = loadDefs('$dataDir/types', 'typeId');
  final skills = loadDefs('$dataDir/skills', 'skillId');
  final store = loadRecords('$dataDir/records');

  final now = DateTime.parse('2026-07-06T09:00:00'); // frozen clock for a reproducible demo
  final interp = Interpreter(types, now);
  final router = Router.load('$dataDir/corpus.json', now);
  final dev = HlcDevice('this-device');

  // authoring-time static gate — every skill must pass before it can run (Spec 02 §6.4)
  for (final s in skills.values) {
    interp.validateSkill(s);
  }
  await router.buildRetrievalIndex(skills); // cold-start candidate index (no-op if embed server down)
  stdout.writeln('loaded ${types.length} types + ${skills.length} skills '
      '(${store.length} persisted records); all skills pass static validation; retrieval index ready\n');

  seedForDemo(store, now); // in-memory seed so the read-side skill has data

  final utterances = args.isNotEmpty
      ? [args.join(' ')]
      : [
          'add call the plumber to my to-do list',
          'undo that',
          "remember that Mia is allergic to peanuts and she is Sarah Mitchell's daughter",
          'log a 3k run',
          'how many km have I run this week', // reflects the run just logged (write -> read)
          "i'm feeling good",
          'jot down that I need to buy milk', // novel phrasing -> retrieval clarify (§13)
        ];

  final undoRe = RegExp(r'^(undo|undo that|no,? take that back|scratch that)\.?$',
      caseSensitive: false);
  Map<String, Map<String, dynamic>?>? lastBefore; // most recent write turn's before-images

  for (final u in utterances) {
    stdout.writeln('U: $u');

    // pre-filter: `undo` is a system command (Spec 03 §2.3), not a skill
    if (undoRe.hasMatch(u.trim())) {
      if (lastBefore == null) {
        stdout.writeln('A: Nothing to undo.\n');
      } else {
        undoTurn(lastBefore, '$dataDir/records', dev, store);
        stdout.writeln('A: Undone.\n');
        lastBefore = null;
      }
      continue;
    }

    final routed = router.route(u);
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
          // §13: retrieval alone is a weak router -> clarify rather than act on a low-confidence guess
          stdout.writeln('A: I\'m not sure what you meant — closest is "$name" ($s1), below my '
              'confidence bar, so I won\'t guess. Could you rephrase? [§13: retrieval is a weak cold-start router]\n');
        }
      }
      continue;
    }
    try {
      final plan = interp.resolve(skills[routed['skillId']]!, routed['slots'], store);
      final before = interp.execute(plan, store);
      for (final w in plan.writes) {
        persist(w, '$dataDir/records', dev);
      }
      if (plan.writes.isNotEmpty) lastBefore = before; // enable undo of this turn
      stdout.writeln('A: ${plan.confirmation}');
      if (plan.writes.isNotEmpty) {
        stdout.writeln('   [wrote ${plan.writes.map((w) => w['typeId']).join(', ')} — persisted with _meta CRDT block]');
      }
      stdout.writeln('');
    } on ResolveError catch (e) {
      stdout.writeln('A: (couldn\'t: $e)\n');
    }
  }
}
