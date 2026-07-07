/// Cloud-path tests via the recorded cassette (test/fixtures/cloud.json) — no
/// network. Exercises the REAL Session code (residual routing, learning,
/// authoring) against genuine recorded Haiku outputs, so these also guard
/// against real schema drift in authored capabilities.
import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/fixture_inputs.dart';
import 'package:plenara/replay_cloud.dart';
import 'package:plenara/session.dart';
import 'package:plenara/store.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');
final _skills = loadDefs('data/skills', 'skillId');
ReplayCloud _cloud() => ReplayCloud.load('test/fixtures/cloud.json');
// unwrap a replayed result — the cassette holds only genuine (Ok) answers.
Map<String, dynamic>? _ok(CloudResult<Map<String, dynamic>?> r) => (r as CloudOk<Map<String, dynamic>?>).value;

void main() {
  group('replay — residual routing matches recorded Haiku (in-domain)', () {
    residualBySkill.forEach((skillId, utterances) {
      for (final u in utterances) {
        test('"$u" -> $skillId', () async {
          final r = _ok(await _cloud().routeResidual(u, _skills));
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
        expect(_ok(await _cloud().routeResidual(u, _skills)), isNull, reason: u);
      });
    }
  });

  // Schema-drift guard: every authoring description must, through the REAL Session
  // authoring loop (validate → retry-with-priorError → validate), end in a registered
  // capability. Driving the loop (not just the raw first attempt) matches production:
  // a first-attempt out-of-vocab fn is corrected on the recorded retry, so this catches
  // genuine drift without flaking on Haiku's first-shot imperfections.
  group('replay — authoring registers a valid capability for every description', () {
    for (final desc in authoringDescriptions) {
      test('"start tracking $desc" authors, validates, and registers', () async {
        final s = Session(makeTempDataDir(), clock: _now, cloud: _cloud());
        await s.init(retrieval: false);
        final before = s.skills.length;
        final resp = await s.handle('start tracking $desc');
        expect(resp.toLowerCase(), contains('built'), reason: '"$desc": $resp');
        expect(s.skills.length, before + 1);
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
        'create-task': ('put emailing the accountant on my to-do list', 'task'),
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

  group('replay through Session — corpus-learning NEGATIVE half (§5.2)', () {
    test('a correction forgets the learned template that routed the corrected turn', () async {
      final s = Session(makeTempDataDir(), clock: _now, cloud: _cloud());
      await s.init(retrieval: false);
      const t = 'jot down that I need to {description:text}';
      await s.handle('jot down that I need to buy milk'); // cloud routes + learns t
      expect(s.router.isLearned(t), isTrue);
      await s.handle('jot down that I need to sweep'); // corpus routes via the learned t
      await s.handle('no, I meant to log a 3k run'); // correction -> forgets t
      expect(s.router.isLearned(t), isFalse);
      expect(s.router.route('jot down that I need to vacuum'), isNull); // t is gone from routing
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
      // the authored typeId is model-chosen (varies across re-records) — assert the
      // skill's DECLARED write-type was registered + persisted, not a hardcoded name.
      final authoredType = (s.skills['log_water_intake']!['writes'] as List).first as String;
      expect(s.types.containsKey(authoredType), isTrue);
      expect(File('$dir/types/$authoredType.json').existsSync(), isTrue);
      expect(File('$dir/skills/log_water_intake.json').existsSync(), isTrue);
    });
  });

  group('replay through Session — EVERY in-domain fixture routes AND acts', () {
    const expectedWrite = {'create-task': 'task', 'log-run': 'workout', 'log-mood': 'mood'};
    residualBySkill.forEach((skillId, utterances) {
      for (final u in utterances) {
        test('"$u" -> $skillId', () async {
          final s = Session(makeTempDataDir(), clock: _now, cloud: _cloud());
          await s.init(retrieval: false);
          final resp = await s.handle(u);
          expect(resp, isNotEmpty);
          if (expectedWrite.containsKey(skillId)) {
            final w = s.store.values.where((r) => r['typeId'] == expectedWrite[skillId]).toList();
            expect(w.length, 1, reason: '$u should write one ${expectedWrite[skillId]}');
            // every written string slot is real text, never a leaked sentinel
            for (final v in w.single.values) {
              if (v is String) expect(v.toLowerCase(), isNot('none'));
            }
          } else {
            expect(s.store, isEmpty, reason: '$u is a read-only skill and must not write');
          }
        });
      }
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
