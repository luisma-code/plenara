/// Cloud-path tests via the recorded cassette (test/fixtures/cloud.json) — no
/// network. Exercises the REAL Session code (residual routing, learning,
/// authoring) against genuine recorded Haiku outputs, so these also guard
/// against real schema drift in authored capabilities.
import 'dart:io';

import 'package:plenara/fixture_inputs.dart';
import 'package:plenara/interpreter.dart';
import 'package:plenara/replay_cloud.dart';
import 'package:plenara/session.dart';
import 'package:plenara/store.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');
final _skills = loadDefs('data/skills', 'skillId');
final _types = loadDefs('data/types', 'typeId');
ReplayCloud _cloud() => ReplayCloud.load('test/fixtures/cloud.json');

void main() {
  group('replay — residual routing matches recorded Haiku (in-domain)', () {
    residualBySkill.forEach((skillId, utterances) {
      for (final u in utterances) {
        test('"$u" -> $skillId', () async {
          final r = await _cloud().routeResidual(u, _skills);
          expect(r, isNotNull, reason: u);
          expect(r!['skillId'], skillId, reason: u);
          expect(r['source'], 'cloud');
        });
      }
    });
  });

  group('replay — out-of-domain: Haiku abstains (null)', () {
    for (final u in outOfDomainUtterances) {
      test('"$u" -> null (abstain)', () async {
        expect(await _cloud().routeResidual(u, _skills), isNull, reason: u);
      });
    }
  });

  group('replay — authored capabilities pass the static validators (schema-drift guard)', () {
    for (final desc in authoringDescriptions) {
      test('author "$desc" -> a valid type + skill that the gate accepts', () async {
        final a = await _cloud().authorCapability(desc);
        expect(a, isNotNull, reason: desc);
        final type = (a!['type'] as Map).cast<String, dynamic>();
        final skill = (a['skill'] as Map).cast<String, dynamic>();
        expect(type['typeId'], isA<String>());
        expect(skill['skillId'], isA<String>());
        expect(skill['steps']?['main'], isA<List>());
        final t = Map<String, Map<String, dynamic>>.from(_types)
          ..[type['typeId'] as String] = type;
        final interp = Interpreter(t, _now);
        expect(() => interp.validateSkill(skill), returnsNormally,
            reason: '"$desc" authored a skill the validators reject');
      });
    }
  });

  group('replay through Session — cloud route -> execute -> LEARN (§13 ratchet)', () {
    late String dir;
    setUp(() => dir = makeTempDataDir());

    test('novel task phrasing: routes via cloud, creates the task, and learns it', () async {
      final s = Session(dir, clock: _now, cloud: _cloud());
      await s.init(retrieval: false);
      const u = 'jot down that I need to buy milk';
      expect(s.router.route(u), isNull, reason: 'corpus should miss first');
      final resp = await s.handle(u);
      expect(resp.toLowerCase(), contains('buy milk'));
      expect(s.store.values.where((r) => r['typeId'] == 'task').length, 1);
      final learned = s.router.route(u);
      expect(learned, isNotNull, reason: 'phrasing should be learned into the corpus');
      expect(learned!['source'], 'corpus');
    });

    test('every in-domain novel phrasing executes the right downstream write', () async {
      // create-task and log-* variants all flow route->execute with no mis-action
      for (final entry in {
        'create-task': ('make a note to email the accountant', 'task'),
        'log-run': ('went for a 5k this afternoon', 'workout'),
        'log-mood': ('feeling pretty anxious today', 'mood'),
      }.entries) {
        final d = makeTempDataDir();
        final s = Session(d, clock: _now, cloud: _cloud());
        await s.init(retrieval: false);
        await s.handle(entry.value.$1);
        final written = s.store.values.where((r) => r['typeId'] == entry.value.$2).toList();
        expect(written.length, 1, reason: '${entry.key}: ${entry.value.$1}');
      }
    });

    test('log-run cloud path extracts the distance', () async {
      final s = Session(dir, clock: _now, cloud: _cloud());
      await s.init(retrieval: false);
      final resp = await s.handle('I did a 6k jog this morning');
      expect(resp.toLowerCase(), contains('run'));
      final runs = s.store.values.where((r) => r['typeId'] == 'workout').toList();
      expect(runs.length, 1);
      expect(runs.first['distance'].toString(), '6');
    });
  });

  group('replay through Session — authoring registers a working capability', () {
    test('"start tracking my water intake" authors, validates, and registers', () async {
      final dir = makeTempDataDir();
      final s = Session(dir, clock: _now, cloud: _cloud());
      await s.init(retrieval: false);
      final before = s.skills.length;
      final resp = await s.handle('start tracking my water intake');
      expect(resp.toLowerCase(), contains('built'));
      expect(s.skills.length, before + 1);
      expect(s.skills.containsKey('log_water_intake'), isTrue);
      expect(File('$dir/types/water_intake.json').existsSync(), isTrue);
      expect(File('$dir/skills/log_water_intake.json').existsSync(), isTrue);
    });
  });

  group('replay through Session — out-of-domain clarifies (no mis-action)', () {
    for (final u in outOfDomainUtterances) {
      test('"$u" writes nothing and does not confirm an action', () async {
        final dir = makeTempDataDir();
        final s = Session(dir, clock: _now, cloud: _cloud());
        await s.init(retrieval: false);
        final resp = await s.handle(u);
        expect(s.store.isEmpty, isTrue, reason: 'OOD must not write');
        expect(resp.toLowerCase(),
            anyOf(contains('not sure'), contains("didn't catch"), contains("don't have")));
      });
    }
  });
}
