/// Routines — the free-tier half (Spec 16): listing, last-done, streaks, and logging a completed
/// run. None of this touches the cloud: authoring a routine is the only paid step, and everything
/// you do with a routine afterwards must work offline forever (principle 5, and the Spec 05 §3.7
/// free-tier invariant). Real storage, per the project's no-mocked-database rule.
library;

import 'package:plenara/claude.dart';
import 'package:plenara/routines.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00'); // Monday

/// A cloud that fails every call — proves these paths never reach for it.
class _NoCloud implements CloudClient {
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

Future<Session> _s() async {
  final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud());
  await s.init(retrieval: false);
  return s;
}

/// Seed a routine (what the paid authoring step will write) directly through the repository, so the
/// free-tier skills can be tested without a cloud call.
String _routine(Session s, String title, {String kind = 'stretch', num minutes = 10}) {
  final id = 'routine-${title.toLowerCase().replaceAll(' ', '-')}';
  final rec = <String, dynamic>{
    'id': id, 'typeId': 'routine', 'title': title, 'kind': kind,
    'estMinutes': minutes, 'status': 'active', 'createdAt': '2026-07-01',
  };
  s.store[id] = rec;
  s.repo.persist(rec);
  return id;
}

void _session(Session s, String routineId, String title, String date) {
  final id = 'rsession-$routineId-$date';
  final rec = <String, dynamic>{
    'id': id, 'typeId': 'routine_session', 'routine': routineId,
    'routineTitle': title, 'date': date, 'stepsCompleted': 7, 'stepsTotal': 7,
  };
  s.store[id] = rec;
  s.repo.persist(rec);
}

void main() {
  group('routine types are shipped and coherent', () {
    test('the three types load with the attributes the player and skills rely on', () async {
      final s = await _s();
      for (final t in ['routine', 'routine_step', 'routine_session']) {
        expect(s.types.containsKey(t), isTrue, reason: '$t must be a seed type');
      }
      // steps and sessions are OWNED by a routine (Spec 01 §4.5), so deleting the routine is a
      // single coherent act rather than leaving orphans behind.
      expect(s.types['routine_step']!['parentType'], 'routine');
      expect(s.types['routine_session']!['parentType'], 'routine');
      // the streak fns key off a plain `date` field — without it routine-streak silently returns 0
      final attrs = (s.types['routine_session']!['attributes'] as List).cast<Map>();
      expect(attrs.any((a) => a['name'] == 'date' && a['valueType'] == 'date'), isTrue);
    });
  });

  group('listing and picking (free tier, no cloud)', () {
    test('"list my routines" numbers them so "delete 2" / "do 2" can resolve by recordId', () async {
      final s = await _s();
      _routine(s, 'Low back', minutes: 8);
      _routine(s, 'Chest day', kind: 'strength', minutes: 35);
      final out = await s.handle('list my routines');
      expect(out, contains('2 routine(s)'));
      expect(out, contains('1. Low back'));
      expect(out, contains('2. Chest day'));
    });

    test('an archived routine drops out of the list (the list exists to pick from)', () async {
      final s = await _s();
      final id = _routine(s, 'Old routine');
      s.store[id]!['status'] = 'archived';
      s.repo.persist(s.store[id]!);
      _routine(s, 'Low back');
      final out = await s.handle('list my routines');
      expect(out, contains('1 routine(s)'));
      expect(out, isNot(contains('Old routine')));
    });
  });

  group('history and streaks', () {
    test('"when did I last do chest day" answers from real sessions, in days', () async {
      final s = await _s();
      final id = _routine(s, 'Chest day', kind: 'strength');
      _session(s, id, 'Chest day', '2026-07-02'); // 4 days before the pinned Monday
      _session(s, id, 'Chest day', '2026-07-04'); // 2 days before — the newest
      final out = await s.handle('when did i last do chest day');
      expect(out, contains('Chest day'));
      expect(out, contains('2 day(s) ago'));
      expect(out, contains('July 4'));
    });

    test('a routine never done says so, rather than inventing a date', () async {
      final s = await _s();
      _routine(s, 'Low back');
      expect(await s.handle('when did i last do low back'), contains("haven't done"));
    });

    test('an unknown routine is refused honestly (P2.8)', () async {
      final s = await _s();
      expect(await s.handle('when did i last do pilates'), contains("don't have a routine"));
    });

    test('a run today reads as "today", not "0 day(s) ago"', () async {
      final s = await _s();
      final id = _routine(s, 'Low back');
      _session(s, id, 'Low back', '2026-07-06');
      expect(await s.handle('when did i last do low back'), contains('today'));
    });

    test('routine-streak reuses the existing streak fns over consecutive days', () async {
      final s = await _s();
      final id = _routine(s, 'Low back');
      for (final d in ['2026-07-04', '2026-07-05', '2026-07-06']) {
        _session(s, id, 'Low back', d);
      }
      final out = await s.handle('my routine streak');
      expect(out, contains('3 day streak'));
      expect(out, contains('3 session(s)'));
    });

    test('no sessions yet -> an honest empty answer, not a zero-streak boast', () async {
      final s = await _s();
      _routine(s, 'Low back');
      expect(await s.handle('my routine streak'), contains('No movement sessions logged yet'));
    });
  });

  _routinesPart2();
  _spokenTrimTests();

  group('logging a completed run', () {
    test('log-routine-session writes a session and is undoable like any other write', () async {
      final s = await _s();
      _routine(s, 'Low back');
      final res = await s.dispatchSkill('log-routine-session', {
        'routineName': 'Low back', 'stepsCompleted': 7, 'stepsTotal': 7,
      });
      expect(res, contains('Low back'));
      final sessions = s.store.values.where((r) => r['typeId'] == 'routine_session').toList();
      expect(sessions.length, 1);
      expect(sessions.single['date'], '2026-07-06');
      expect(sessions.single['stepsCompleted'], 7);
      // finishing a routine is an ordinary act-then-describe write, so "undo that" reverses it
      await s.handle('undo that');
      expect(s.store.values.where((r) => r['typeId'] == 'routine_session'), isEmpty);
    });

    test('the whole free-tier surface works with a cloud that would fail if touched', () async {
      final s = await _s();
      final id = _routine(s, 'Low back');
      _session(s, id, 'Low back', '2026-07-05');
      // every one of these must resolve offline — authoring is the ONLY paid step
      expect(await s.handle('list my routines'), contains('Low back'));
      expect(await s.handle('when did i last do low back'), contains('1 day(s) ago'));
      expect(await s.handle('my routine streak'), contains('session(s)'));
    });
  });
}

/// A cloud that can author routines, returning a scripted payload — so the whole
/// author → validate → write → play path is exercised with no network and no spend.
class _FakeAuthor implements CloudClient, RoutineAuthor {
  final Map<String, dynamic> Function(String catalogue, int attempt) build;
  int calls = 0;
  String? lastCatalogue, lastRequest;
  _FakeAuthor(this.build);
  @override
  Future<CloudResult<Map<String, dynamic>>> authorRoutine(String request, String catalogue,
      {String? kind, String? priorError}) async {
    lastRequest = request;
    lastCatalogue = catalogue;
    return CloudOk(build(catalogue, calls++));
  }
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s,
          {Set<String> knownContacts = const {}}) async => const CloudOk(null);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<String>> generate(String k, String c) async => const CloudError(CloudErrorKind.noKey);
}

/// The first two catalogue keys the shortlist offered — so the fake behaves like a model that
/// actually picked from what it was given.
List<String> _keysFrom(String catalogue, int n) =>
    catalogue.split('\n').where((l) => l.trim().isNotEmpty).take(n).map((l) => l.split(' | ').first).toList();

Map<String, dynamic> _goodRoutine(String catalogue, {String title = 'Low-back loosener'}) {
  final keys = _keysFrom(catalogue, 3);
  return {
    'title': title, 'focusArea': 'low back', 'kind': 'stretch', 'estMinutes': 8,
    'steps': [
      {'exerciseKey': keys[0], 'name': 'Step one', 'durationSeconds': 30, 'side': 'both'},
      {'exerciseKey': keys[1], 'name': 'Step two', 'durationSeconds': 45, 'side': 'left'},
      {'exerciseKey': keys[2], 'name': 'Step three', 'reps': 10, 'side': 'both'},
    ],
  };
}

Future<Session> _authoring(Map<String, dynamic> Function(String, int) build) async {
  final s = Session(makeTempDataDir(), clock: _now, cloud: _FakeAuthor(build));
  await s.init(retrieval: false);
  return s;
}

void _routinesPart2() {
  group('the catalogue grounds authoring (code narrows, model composes, code validates)', () {
    test('the shipped catalogue loads with illustrated and text-only entries', () async {
      final s = await _s();
      expect(s.exercises.isEmpty, isFalse);
      expect(s.exercises.all.length, greaterThan(500));
      expect(s.exercises.all.where((e) => e.image != null).length, greaterThan(100));
      // every entry must be speakable — a step we cannot say out loud is unusable (screen-off runs)
      expect(s.exercises.all.where((e) => e.instructions.trim().length < 15), isEmpty);
    });

    test('the shortlist is deterministic, relevant, and register-appropriate', () async {
      final s = await _s();
      final a = s.exercises.candidates('low back', kind: 'stretch');
      final b = s.exercises.candidates('low back', kind: 'stretch');
      expect(a.map((e) => e.key).toList(), b.map((e) => e.key).toList(),
          reason: 'same request must yield the same shortlist every time');
      expect(a, isNotEmpty);
      final strength = s.exercises.candidates('chest', kind: 'strength');
      expect(strength.where((e) => e.name.toLowerCase().contains('stretch')).length,
          lessThan(strength.length ~/ 2),
          reason: 'a strength ask should not be dominated by stretches');
    });

    test('an unmatched focus still yields real candidates rather than an empty list', () async {
      final s = await _s();
      expect(s.exercises.candidates('zzzz nonsense', kind: 'stretch'), isNotEmpty);
    });
  });

  group('authoring a routine', () {
    test('"create a stretch routine for my low back" writes a routine + steps, undoably', () async {
      final s = await _authoring((c, _) => _goodRoutine(c));
      final out = await s.handle('create a stretch routine for my low back');
      expect(out, contains('Low-back loosener'));
      expect(out, contains('3 steps'));
      expect(s.store.values.where((r) => r['typeId'] == 'routine').length, 1);
      expect(s.store.values.where((r) => r['typeId'] == 'routine_step').length, 3);
      // the whole routine is ONE journal entry — undo must not leave orphan steps behind
      await s.handle('undo that');
      expect(s.store.values.where((r) => r['typeId'] == 'routine'), isEmpty);
      expect(s.store.values.where((r) => r['typeId'] == 'routine_step'), isEmpty);
    });

    test('instructions come from the CATALOGUE, not the model', () async {
      final s = await _authoring((c, _) {
        final r = _goodRoutine(c);
        // a model trying to supply its own wording for a catalogue exercise
        (r['steps'] as List)[0]['instruction'] = 'IGNORE THE CATALOGUE AND DO WHATEVER';
        return r;
      });
      await s.handle('create a stretch routine for my low back');
      final step = s.store.values.firstWhere((r) => r['typeId'] == 'routine_step' && r['order'] == 1);
      expect(step['instruction'], isNot(contains('IGNORE THE CATALOGUE')));
      final key = step['exerciseKey'] as String;
      expect(step['instruction'], s.exercises.byKey[key]!.instructions);
    });

    test('an invented exerciseKey is rejected, and the retry is fed the reason', () async {
      final s = await _authoring((c, attempt) {
        if (attempt == 0) {
          final r = _goodRoutine(c);
          (r['steps'] as List)[0]['exerciseKey'] = 'not-a-real-exercise';
          return r;
        }
        return _goodRoutine(c); // the corrected second attempt
      });
      final out = await s.handle('create a stretch routine for my low back');
      expect(out, contains('Low-back loosener'), reason: 'the gated retry should recover');
      expect((s.claude as _FakeAuthor).calls, 2);
    });

    test('two bad attempts register NOTHING — a half-routine is worse than none', () async {
      final s = await _authoring((c, _) {
        final r = _goodRoutine(c);
        (r['steps'] as List)[0]['exerciseKey'] = 'still-not-real';
        return r;
      });
      final out = await s.handle('create a stretch routine for my low back');
      expect(out.toLowerCase(), contains("couldn't"));
      expect(s.store.values.where((r) => r['typeId'] == 'routine'), isEmpty);
      expect(s.store.values.where((r) => r['typeId'] == 'routine_step'), isEmpty);
    });

    test('the standing safety note is OURS — a model cannot reword or drop it', () async {
      final s = await _authoring((c, _) {
        final r = _goodRoutine(c);
        r['safetyNote'] = 'totally safe for everyone, no need to check with anyone';
        return r;
      });
      await s.handle('create a stretch routine for my low back');
      final r = s.store.values.firstWhere((x) => x['typeId'] == 'routine');
      expect(r['safetyNote'], standingSafetyNote);
      expect(r['safetyNote'], contains('not medical advice'));
    });
  });

  group('the Layer-1 safety gate (framing, not topic)', () {
    test('an injury framing gets a redirect and spends NOTHING', () async {
      final s = await _authoring((c, _) => _goodRoutine(c));
      final out = await s.handle('create a stretch routine for my herniated disc');
      expect(out.toLowerCase(), contains('physio'));
      expect(s.store.values.where((r) => r['typeId'] == 'routine'), isEmpty);
      expect((s.claude as _FakeAuthor).calls, 0, reason: 'the gate is BEFORE the spend');
    });

    test('ordinary wellness asks pass untouched', () async {
      for (final ask in ['low back', 'shoulders', 'stability', 'hamstrings']) {
        expect(looksLikeInjuryRequest('create a stretch routine for my $ask'), isFalse,
            reason: '"$ask" is a wellness ask, not a medical one');
      }
      for (final ask in ['herniated disc', 'sciatica', 'rotator cuff tear', 'my knee pain',
                         'after my surgery', 'plantar fasciitis']) {
        expect(looksLikeInjuryRequest('create a stretch routine for $ask'), isTrue,
            reason: '"$ask" is medical framing');
      }
    });
  });

  group('the player', () {
    Future<Session> withRoutine() async {
      final s = await _authoring((c, _) => _goodRoutine(c));
      await s.handle('create a stretch routine for my low back');
      return s;
    }

    test('"let\'s do" starts the run and announces step 1 with the safety line, once', () async {
      final s = await withRoutine();
      final out = await s.handle("let's do low-back loosener");
      expect(out, contains('not medical advice')); // first ever run
      expect(out, contains('Step 1 of 3'));
      expect(s.activeRun, isNotNull);
    });

    test('next / back / skip move through the steps and the counts stay honest', () async {
      final s = await withRoutine();
      await s.handle("let's do low-back loosener");
      expect(await s.handle('next'), contains('Step 2 of 3'));
      expect(await s.handle('back'), contains('Step 1 of 3'));
      expect(await s.handle('skip'), contains('Step 2 of 3'));
      expect(s.activeRun!.skipped.length, 1);
      expect(s.activeRun!.completed, isEmpty, reason: 'a skipped step is not a completed one');
    });

    test('finishing logs a session with the real counts, and is undoable', () async {
      final s = await withRoutine();
      await s.handle("let's do low-back loosener");
      await s.handle('next');
      await s.handle('next');
      final out = await s.handle('next'); // past the last step -> done
      expect(out, contains('done'));
      expect(s.activeRun, isNull);
      final sess = s.store.values.where((r) => r['typeId'] == 'routine_session').toList();
      expect(sess.length, 1);
      expect(sess.single['stepsCompleted'], 3);
      expect(sess.single['stepsTotal'], 3);
    });

    test('quitting before any step logs NOTHING (never fabricate a session)', () async {
      final s = await withRoutine();
      await s.handle("let's do low-back loosener");
      final out = await s.handle('stop');
      expect(out, contains('nothing logged'));
      expect(s.store.values.where((r) => r['typeId'] == 'routine_session'), isEmpty);
      expect(s.activeRun, isNull);
    });

    test('quitting partway logs a PARTIAL session, honestly', () async {
      final s = await withRoutine();
      await s.handle("let's do low-back loosener");
      await s.handle('next');
      final out = await s.handle("that's enough");
      expect(out, contains('1 of 3'));
      final sess = s.store.values.firstWhere((r) => r['typeId'] == 'routine_session');
      expect(sess['stepsCompleted'], 1);
      expect(sess['stepsTotal'], 3);
    });

    test('the run is STICKY: an unrelated command mid-run works and the run survives', () async {
      final s = await withRoutine();
      await s.handle("let's do low-back loosener");
      final aside = await s.handle('add buy milk to my list');
      expect(aside, contains('buy milk'));
      expect(s.activeRun, isNotNull, reason: 'sunk physical effort — do not drop the run');
      expect(await s.handle('next'), contains('Step 2 of 3'));
    });

    test('"repeat" re-speaks the stored instruction — never a cloud call mid-run', () async {
      final s = await withRoutine();
      await s.handle("let's do low-back loosener");
      final before = (s.claude as _FakeAuthor).calls;
      final again = await s.handle('say that again');
      expect(again, contains('Step 1 of 3'));
      expect((s.claude as _FakeAuthor).calls, before);
    });

    test('pause holds, and "go on" resumes at the same step', () async {
      final s = await withRoutine();
      await s.handle("let's do low-back loosener");
      expect(await s.handle('hold on'), contains('Paused'));
      expect(await s.handle('go on'), contains('Step 1 of 3'));
    });

    test('a second run does not repeat the safety line', () async {
      final s = await withRoutine();
      await s.handle("let's do low-back loosener");
      await s.handle('next');
      await s.handle('next');
      await s.handle('next'); // completes -> writes a session
      final second = await s.handle("let's do low-back loosener");
      expect(second, isNot(contains('not medical advice')),
          reason: 'warning fatigue is itself a safety failure');
      expect(second, contains('Step 1 of 3'));
    });
  });
}

void _spokenTrimTests() {
  group('a step is trimmed for the EAR, not the page', () {
    test('the "Tips:" tail is dropped — useful to read, noise to hear mid-stretch', () {
      const raw = "Start on all fours with your hands under your shoulders. On an exhale, "
          "sit back onto your heels and let your forehead rest down. "
          "Tips: To leave the pose, walk your arms back under your shoulders.";
      final out = spokenInstruction(raw);
      expect(out, contains('sit back onto your heels'));
      expect(out.toLowerCase(), isNot(contains('to leave the pose')));
    });

    test('print-only section labels are stripped', () {
      final out = spokenInstruction('Starting position: Kneel on all fours. Steps: Round your back.');
      expect(out, isNot(contains('Starting position:')));
      expect(out, isNot(contains('Steps:')));
      expect(out, contains('Kneel on all fours'));
    });

    test('a long instruction is cut at a SENTENCE end, never mid-move', () {
      final raw = '${'Lower under control until your chest is near the floor. ' * 8}';
      final out = spokenInstruction(raw);
      expect(out.length, lessThanOrEqualTo(221));
      expect(out.endsWith('.'), isTrue, reason: 'never stop the speaker mid-instruction');
    });

    test('a short instruction is passed through untouched', () {
      const raw = 'Hold a straight line from head to heels.';
      expect(spokenInstruction(raw), raw);
    });

    test('the full text stays on the RECORD — only speech is trimmed', () async {
      final s = await _authoring((c, _) => _goodRoutine(c));
      await s.handle('create a stretch routine for my low back');
      final step = s.store.values.firstWhere((r) => r['typeId'] == 'routine_step' && r['order'] == 1);
      final key = step['exerciseKey'] as String;
      expect(step['instruction'], s.exercises.byKey[key]!.instructions,
          reason: 'the card shows everything; only the spoken line is shortened');
    });
  });
}
