/// Plenara v0 walking skeleton — text-first console over the shared turn engine
/// (package:plenara/session.dart). The SAME `Session.handle` the Flutter UI and
/// the test suite drive, so this console runs tested code — no duplicated logic.
///
///   dart run bin/plenara.dart              # interactive REPL
///   dart run bin/plenara.dart --demo       # scripted demo (with seed data)
///   dart run bin/plenara.dart "log a 3k run"   # one-shot
library;

import 'dart:io';

import 'package:plenara/session.dart';

const dataDir = 'data';

const demoUtterances = [
  'add call the plumber to my to-do list',
  'undo that',
  "remember that Mia is allergic to peanuts and she is Sarah Mitchell's daughter",
  'log a 3k run',
  'how many km have I run this week', // reflects the run just logged (write -> read)
  "i'm feeling good",
  'jot down that I need to buy milk', // novel phrasing -> Haiku residual (online) or clarify
];

/// In-memory demo seed (not persisted) so the scripted demo has context to read.
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
    store[r['id'] as String] = r;
  }
}

Future<void> main(List<String> args) async {
  final session = Session(dataDir, clock: DateTime.parse('2026-07-06T09:00:00'));
  await session.init();
  stdout.writeln('loaded ${session.types.length} types + ${session.skills.length} skills '
      '(${session.store.length} persisted records); all pass static validation\n');
  if (args.contains('--demo')) seedForDemo(session.store, session.now);

  Future<void> turn(String u) async {
    stdout.writeln('U: $u');
    stdout.writeln('A: ${await session.handle(u)}\n');
  }

  if (args.contains('--demo')) {
    for (final u in demoUtterances) {
      await turn(u);
    }
  } else if (args.isNotEmpty) {
    await turn(args.join(' '));
  } else {
    stdout.writeln('Plenara v0 — type a request, or "quit". Try: "add X to my list", '
        '"log a 3k run", "remember that NAME FACT", "how many km have I run this week", "undo that".\n');
    while (true) {
      stdout.write('> ');
      final line = stdin.readLineSync();
      if (line == null || const ['quit', 'exit', 'q'].contains(line.trim().toLowerCase())) break;
      if (line.trim().isEmpty) continue;
      await turn(line.trim());
    }
    stdout.writeln('bye.');
  }
}
