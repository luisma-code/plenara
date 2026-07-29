/// Regression tests for the 2026-07-28 Fable review of the routines feature. Each one pins a
/// defect that SHIPPED and was caught by review rather than by the suite — which is precisely why
/// they belong here permanently.
library;

import 'package:plenara/claude.dart';
import 'package:plenara/routines.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');

class _FakeAuthor implements CloudClient, RoutineAuthor {
  final Map<String, dynamic> Function(String catalogue, int attempt) build;
  int calls = 0;
  _FakeAuthor(this.build);
  @override
  Future<CloudResult<Map<String, dynamic>>> authorRoutine(String request, String catalogue,
          {String? kind, String? priorError}) async =>
      CloudOk(build(catalogue, calls++));
  List<Map<String, dynamic>>? figures;
  int figureCalls = 0;
  @override
  Future<CloudResult<Map<String, dynamic>>> authorFigures(List<String> movements) async {
    figureCalls++;
    if (figures == null) return const CloudError(CloudErrorKind.malformed, 'no figures');
    return CloudOk({'figures': figures});
  }
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s,
          {Set<String> knownContacts = const {}}) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<String>> generate(String k, String c) async => const CloudError(CloudErrorKind.noKey);
}

List<String> _keys(String catalogue, int n) => catalogue
    .split('\n')
    .where((l) => l.trim().isNotEmpty)
    .take(n)
    .map((l) => l.split(' | ').first)
    .toList();

Map<String, dynamic> _routine(String catalogue, {String title = 'Low-back loosener'}) {
  final k = _keys(catalogue, 3);
  return {
    'title': title, 'focusArea': 'low back', 'kind': 'stretch', 'estMinutes': 8,
    'steps': [
      {'exerciseKey': k[0], 'name': 'Step one', 'durationSeconds': 30, 'side': 'both'},
      {'exerciseKey': k[1], 'name': 'Step two', 'durationSeconds': 45, 'side': 'left'},
      {'exerciseKey': k[2], 'name': 'Step three', 'reps': 10, 'side': 'both'},
    ],
  };
}

Future<Session> _authoring(Map<String, dynamic> Function(String, int) build) async {
  final s = Session(makeTempDataDir(), clock: _now, cloud: _FakeAuthor(build));
  await s.init(retrieval: false);
  return s;
}

Future<Session> _withRoutine() async {
  final s = await _authoring((c, _) => _routine(c));
  await s.handle('create a stretch routine for my low back');
  return s;
}

void main() {
  group('safety floors run BEFORE routine authoring', () {
    test('a disordered-eating or self-harm framing is refused and spends NOTHING', () async {
      // These reached the routine path entirely ungated: the harm floor only ran on the
      // tracker-authoring branch, and the routine block sat ABOVE the medical floor.
      for (final u in [
        'create a workout for my self-harm recovery',
        'design a workout to help with my anorexia recovery',
        'create a workout for burning off my binge',
        'create a workout to help with my eating disorder',
      ]) {
        final s = await _authoring((c, _) => _routine(c));
        final out = await s.handle(u);
        expect(s.store.values.where((r) => r['typeId'] == 'routine'), isEmpty,
            reason: 'must not author a routine for: $u');
        expect((s.claude as _FakeAuthor).calls, 0, reason: 'must not spend on: $u');
        expect(out.toLowerCase(), anyOf(contains("won't"), contains("can't")), reason: u);
      }
    });

    test('a medical framing hits the medical floor, not the routine path', () async {
      final s = await _authoring((c, _) => _routine(c));
      final out = await s.handle("make me a workout to help with what's wrong with me");
      expect(s.store.values.where((r) => r['typeId'] == 'routine'), isEmpty);
      expect((s.claude as _FakeAuthor).calls, 0);
      expect(out.toLowerCase(), contains('doctor'));
    });
  });

  group('the injury gate is a refuse-gate — its RECALL is the privacy property', () {
    test('common real-world injury phrasings are caught', () {
      for (final p in [
        'my hernia', 'my osteoarthritis', 'my sore lower back', 'a pulled hamstring',
        'shin splints', 'my knee replacement', 'tennis elbow', 'my numb leg',
        'recovering from my accident', 'carpal tunnel', 'my stiff neck', 'postpartum',
        'my dodgy shoulder', 'sciatica', 'my herniated disc',
      ]) {
        expect(looksLikeInjuryRequest('create a stretch routine for $p'), isTrue, reason: p);
      }
    });

    test('PREVENTION and ordinary wellness are not injuries', () {
      for (final p in [
        'injury prevention', 'muscle strain prevention', 'everyday wear and tear',
        'my low back', 'my shoulders', 'stability', 'my hamstrings',
      ]) {
        expect(looksLikeInjuryRequest('create a stretch routine for $p'), isFalse, reason: p);
      }
    });
  });

  group('the player cannot lie about what happened', () {
    test('"ready" while paused RESUMES — it does not complete the held step', () async {
      final s = await _withRoutine();
      await s.handle("let's do low-back loosener");
      await s.handle('hold on');
      final out = await s.handle('ready');
      expect(out, contains('Step 1 of 3'), reason: 'resume, not advance');
      expect(s.activeRun!.completed, isEmpty, reason: 'a paused step was never completed');
      expect(s.activeRun!.paused, isFalse, reason: 'resuming must clear paused');
    });

    test('advancing always clears paused, so the cadence cannot stay dead', () async {
      final s = await _withRoutine();
      await s.handle("let's do low-back loosener");
      await s.handle('pause');
      await s.handle('next');
      expect(s.activeRun!.paused, isFalse);
    });

    test('the completion write resolves by ID, so duplicate titles cannot lose a session', () async {
      final s = await _authoring((c, _) => _routine(c));
      await s.handle('create a stretch routine for my low back');
      await s.handle('create a stretch routine for my low back'); // same title again
      expect(s.store.values.where((r) => r['typeId'] == 'routine').length, 2);
      await s.handle("let's do low-back loosener");
      await s.handle('next');
      await s.handle('next');
      final out = await s.handle('next');
      expect(out, contains('done'));
      expect(s.store.values.where((r) => r['typeId'] == 'routine_session').length, 1,
          reason: 'a duplicate title made read_one ambiguous and silently dropped the session');
    });

    test('two routines created on a PINNED clock do not collide', () async {
      var i = 0;
      final s = await _authoring((c, _) => _routine(c, title: 'Routine ${i++}'));
      await s.handle('create a stretch routine for my low back');
      await s.handle('create a stretch routine for my shoulders');
      final routines = s.store.values.where((r) => r['typeId'] == 'routine').toList();
      expect(routines.length, 2);
      expect(routines.map((r) => r['id']).toSet().length, 2, reason: 'ids must be distinct');
      for (final r in routines) {
        final steps = s.store.values
            .where((x) => x['typeId'] == 'routine_step' && x['routine'] == r['id']);
        expect(steps.length, 3, reason: 'no orphan steps grafted from the other routine');
      }
    });
  });

  group('the validator coerces rather than crashing out of the gated retry', () {
    test('a type-confused numeric field feeds the retry instead of throwing', () async {
      final s = await _authoring((c, attempt) {
        final r = _routine(c);
        if (attempt == 0) (r['steps'] as List)[0]['durationSeconds'] = 'thirty';
        return r;
      });
      final out = await s.handle('create a stretch routine for my low back');
      expect(out, contains('Low-back loosener'));
      expect((s.claude as _FakeAuthor).calls, 2);
    });

    test('an absurd estMinutes is replaced by a computed estimate', () async {
      final s = await _authoring((c, _) {
        final r = _routine(c);
        r['estMinutes'] = 1000000000;
        return r;
      });
      await s.handle('create a stretch routine for my low back');
      final r = s.store.values.firstWhere((x) => x['typeId'] == 'routine');
      expect((r['estMinutes'] as num) < 180, isTrue);
    });

    test('newlines are stripped from model-supplied text (it is spoken and stored)', () async {
      final s = await _authoring((c, _) {
        final r = _routine(c);
        r['title'] = 'Low\nback loosener';
        return r;
      });
      await s.handle('create a stretch routine for my low back');
      final r = s.store.values.firstWhere((x) => x['typeId'] == 'routine');
      expect('${r['title']}'.contains('\n'), isFalse);
    });

    test('an over-long spoken step name is rejected', () async {
      final s = await _authoring((c, _) {
        final r = _routine(c);
        (r['steps'] as List)[0]['name'] = 'x' * 200;
        return r;
      });
      final out = await s.handle('create a stretch routine for my low back');
      expect(out.toLowerCase(), contains("couldn't"));
    });
  });

  group('generated figures are a FALLBACK tier, never a gate on the routine', () {
    const goodA = '<svg viewBox="0 0 100 100"><circle cx="50" cy="20" r="8"/><path d="M50 28 L50 60"/></svg>';
    const goodB = '<svg viewBox="0 0 100 100"><circle cx="50" cy="30" r="8"/><path d="M50 38 L50 70"/></svg>';

    test('steps the catalogue cannot illustrate get a drawn figure', () async {
      final s = await _authoring((c, _) => _routine(c));
      (s.claude as _FakeAuthor).figures = [
        for (final n in ['Step one', 'Step two', 'Step three'])
          {'name': n, 'frameA': goodA, 'frameB': goodB},
      ];
      await s.handle('create a stretch routine for my low back');
      final steps = s.store.values.where((r) => r['typeId'] == 'routine_step').toList();
      // only steps WITHOUT a catalogue image should have been drawn
      for (final st in steps) {
        final key = st['exerciseKey'] as String?;
        final hasCatalogueImage = key != null && s.exercises.byKey[key]?.image != null;
        if (hasCatalogueImage) {
          expect(st['figureA'], isNull, reason: 'never redraw what the catalogue already has');
        } else {
          expect(st['figureA'], goodA);
          expect(st['figureTween'], isTrue);
        }
      }
    });

    test('a figure-call FAILURE leaves the routine intact and the steps text-only', () async {
      final s = await _authoring((c, _) => _routine(c));
      (s.claude as _FakeAuthor).figures = null; // the seam returns an error
      final out = await s.handle('create a stretch routine for my low back');
      expect(out, contains('Low-back loosener'), reason: 'the routine still lands');
      expect(s.store.values.where((r) => r['typeId'] == 'routine_step').length, 3);
      expect(s.store.values.where((r) => r['typeId'] == 'routine_step' && r['figureA'] != null),
          isEmpty);
    });

    test('a HOSTILE figure is dropped; the step keeps working', () async {
      final s = await _authoring((c, _) => _routine(c));
      (s.claude as _FakeAuthor).figures = [
        {'name': 'Step one', 'frameA': '<svg viewBox="0 0 1 1"><script>x()</script></svg>'},
        {'name': 'Step two', 'frameA': goodA, 'frameB': goodB},
      ];
      await s.handle('create a stretch routine for my low back');
      final one = s.store.values.firstWhere((r) => r['typeId'] == 'routine_step' && r['name'] == 'Step one');
      expect(one['figureA'], isNull, reason: 'the script figure must never be stored');
      expect(one['instruction'], isNotEmpty, reason: 'the step itself is unaffected');
    });

    test('figures are drawn ONCE per movement name, not once per step', () async {
      final s = await _authoring((c, _) {
        final r = _routine(c);
        (r['steps'] as List)[2]['name'] = 'Step one'; // a routine that bookends
        return r;
      });
      (s.claude as _FakeAuthor).figures = [{'name': 'Step one', 'frameA': goodA}];
      await s.handle('create a stretch routine for my low back');
      expect((s.claude as _FakeAuthor).figureCalls, 1);
    });
  });

  group('routine-streak answers honestly for an unknown routine', () {
    test('an unknown name says so instead of "No  sessions logged yet"', () async {
      final s = await _authoring((c, _) => _routine(c));
      expect(await s.handle('my pilates streak'), contains("don't have a routine"));
    });
  });
}
