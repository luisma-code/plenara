/// Routines — the free-tier half (Spec 16): listing, last-done, streaks, and logging a completed
/// run. None of this touches the cloud: authoring a routine is the only paid step, and everything
/// you do with a routine afterwards must work offline forever (principle 5, and the Spec 05 §3.7
/// free-tier invariant). Real storage, per the project's no-mocked-database rule.
library;

import 'package:plenara/claude.dart';
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
