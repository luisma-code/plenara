/// Plenara v0 walking skeleton — the turn loop (Spec 04 DispatchOrchestrator,
/// thinned). Text-first console: utterance -> route -> resolve -> execute ->
/// persist -> describe (act-then-describe). The router here is a PLACEHOLDER for
/// the Spec 03 corpus + retrieval design (separately validated); the point of the
/// skeleton is that every layer boundary connects, in real Dart.
library;

import 'dart:io';
import 'package:plenara/interpreter.dart';
import 'package:plenara/store.dart';

const dataDir = 'data';

/// Placeholder router: maps the demo utterances to (skillId, slots). Stands in
/// for corpus fast-path + retrieval-margin + deterministic slot extractors.
Map<String, dynamic>? route(String u) {
  final s = u.toLowerCase();
  var m = RegExp(r'add (.+?) to my (?:to-?do|list|tasks)').firstMatch(s);
  if (m != null) {
    return {'skillId': 'create-task', 'slots': {'description': m.group(1)}};
  }
  m = RegExp(r"remember that (\w+) (.+?) and (?:she|he|they) (?:is|are) (.+?)'?s (\w+)")
      .firstMatch(u); // keep original case for names
  if (m != null) {
    return {
      'skillId': 'remember-person-fact',
      'slots': {
        'personName': m.group(1),
        'fact': m.group(2),
        'relationTo': m.group(3),
        'relationType': m.group(4),
      }
    };
  }
  if (s.contains('run') && s.contains('week')) {
    return {'skillId': 'count-runs-this-week', 'slots': <String, dynamic>{}};
  }
  return null;
}

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

void main(List<String> args) {
  final types = loadDefs('$dataDir/types', 'typeId');
  final skills = loadDefs('$dataDir/skills', 'skillId');
  final store = loadRecords('$dataDir/records');

  final now = DateTime.parse('2026-07-06T09:00:00'); // frozen clock for a reproducible demo
  final interp = Interpreter(types, now);
  final dev = HlcDevice('this-device');

  // authoring-time static gate — every skill must pass before it can run (Spec 02 §6.4)
  for (final s in skills.values) {
    interp.validateSkill(s);
  }
  stdout.writeln('loaded ${types.length} types + ${skills.length} skills '
      '(${store.length} persisted records); all skills pass static validation\n');

  seedForDemo(store, now); // in-memory seed so the read-side skill has data

  final utterances = args.isNotEmpty
      ? [args.join(' ')]
      : [
          'add call the plumber to my to-do list',
          "remember that Mia is allergic to peanuts and she is Sarah Mitchell's daughter",
          'how many km have I run this week',
        ];

  for (final u in utterances) {
    stdout.writeln('U: $u');
    final routed = route(u);
    if (routed == null) {
      stdout.writeln("A: I didn't understand that yet (v0 placeholder router).\n");
      continue;
    }
    try {
      final plan = interp.resolve(skills[routed['skillId']]!, routed['slots'], store);
      interp.execute(plan, store);
      for (final w in plan.writes) {
        persist(w, '$dataDir/records', dev);
      }
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
