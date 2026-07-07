/// Reminders + the NotificationScheduler seam (F2). Product-level, hermetic:
/// everything runs against the in-memory [FakeScheduler] and a temp data dir, so
/// the whole behaviour — arming, dedupe on re-open, cancel on undo, past-due
/// nudges, graceful missing-time — is CI-validated with no OS and no network. The
/// only thing NOT covered here is "does Windows actually render the toast", which
/// is the razor-thin real-impl smoke (directive #1).
import 'package:plenara/claude.dart';
import 'package:plenara/reminders.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00'); // a Monday, 09:00
final _thu5pm = DateTime.parse('2026-07-09T17:00:00'); // "thursday at 5pm" from _now

/// Cloud that must never be hit (reminders route via the deterministic corpus).
class _NoCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s) async =>
      throw StateError('cloud hit for "$u" — reminder flows must be pure corpus');
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      throw StateError('cloud authoring hit — unexpected');
}

/// Cloud returning one scripted residual route (to drive the missing-time path).
class _RouteCloud implements CloudClient {
  final Map<String, dynamic>? route;
  _RouteCloud(this.route);
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s) async =>
      CloudOk(route);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      const CloudOk(null);
}

Future<Session> _open(String dir, FakeScheduler fake, {DateTime? clock}) async {
  final s = Session(dir, clock: clock ?? _now, cloud: _NoCloud(), scheduler: fake);
  await s.init(retrieval: false);
  return s;
}

void main() {
  group('pure derivation + reconcile (no Session)', () {
    Map<String, Map<String, dynamic>> store(List<Map<String, dynamic>> recs) =>
        {for (final r in recs) r['id'] as String: r};

    test('desiredArmed keeps future, not-done reminders; dueReminders keeps past ones', () {
      final s = store([
        {'id': 'reminder-a', 'typeId': 'reminder', 'text': 'future', 'remindAt': '2026-07-09T17:00:00'},
        {'id': 'reminder-b', 'typeId': 'reminder', 'text': 'past', 'remindAt': '2026-07-05T08:00:00'},
        {'id': 'reminder-c', 'typeId': 'reminder', 'text': 'done', 'remindAt': '2026-07-09T18:00:00', 'done': true},
        {'id': 'task-x', 'typeId': 'task', 'description': 'not a reminder'},
      ]);
      expect(desiredArmed(s, _now).keys, ['reminder-a']); // future + not done only
      expect(dueReminders(s, _now).map((r) => r.ref), ['reminder-b']); // past + not done
    });

    test('reconcile arms desired then is idempotent (no dupes on a second pass)', () async {
      final s = store([
        {'id': 'reminder-a', 'typeId': 'reminder', 'text': 'call mom', 'remindAt': '2026-07-09T17:00:00'},
      ]);
      final fake = FakeScheduler();
      await reconcileReminders(fake, s, _now);
      await reconcileReminders(fake, s, _now); // re-open / idle tick
      expect(fake.armed().keys.toSet(), {'reminder-a'});
      expect(fake.scheduleCalls, 1); // armed exactly once, never re-armed
    });

    test('reconcile cancels an armed reminder once its record is gone', () async {
      final s = store([
        {'id': 'reminder-a', 'typeId': 'reminder', 'text': 'x', 'remindAt': '2026-07-09T17:00:00'},
      ]);
      final fake = FakeScheduler();
      await reconcileReminders(fake, s, _now);
      s.remove('reminder-a'); // undo/delete removed the record
      await reconcileReminders(fake, s, _now);
      expect(fake.armed(), isEmpty);
      expect(fake.canceled, ['reminder-a']);
    });
  });

  group('Session end-to-end (corpus route + FakeScheduler)', () {
    test('a reminder for Thu 5pm arms exactly one notification', () async {
      final fake = FakeScheduler();
      final s = await _open(makeTempDataDir(), fake);
      final r = await s.handle('remind me to call mom on thursday at 5pm');
      expect(r, contains('call mom'));
      expect(fake.armed().length, 1);
      final armed = fake.scheduled.values.single;
      expect(armed.at, _thu5pm);
      expect(armed.body, contains('call mom'));
    });

    test('undo cancels the armed notification', () async {
      final fake = FakeScheduler();
      final s = await _open(makeTempDataDir(), fake);
      await s.handle('remind me to call mom on thursday at 5pm');
      final ref = fake.armed().keys.single;
      final r = await s.handle('undo');
      expect(r.toLowerCase(), contains('undone'));
      expect(fake.armed(), isEmpty);
      expect(fake.canceled, contains(ref));
    });

    test('re-open re-derives the armed set with no duplicates', () async {
      final dir = makeTempDataDir();
      final first = await _open(dir, FakeScheduler());
      await first.handle('remind me to call mom on thursday at 5pm');

      // fresh process: new Session + new scheduler over the same persisted folder
      final fake2 = FakeScheduler();
      final reopened = await _open(dir, fake2);
      expect(fake2.armed().length, 1, reason: 'reconciled from disk on open');
      expect(fake2.scheduleCalls, 1);

      // an unrelated turn reconciles again and must not re-arm
      await reopened.handle('list my tasks');
      expect(fake2.armed().length, 1);
      expect(fake2.scheduleCalls, 1, reason: 'idempotent — no duplicate toast');
    });

    test('a past-due reminder becomes an on-open nudge, not an armed toast', () async {
      final dir = makeTempDataDir();
      final first = await _open(dir, FakeScheduler());
      await first.handle('remind me to call mom on thursday at 5pm');

      // re-open the day AFTER it was due
      final fake2 = FakeScheduler();
      final later = await _open(dir, fake2, clock: DateTime.parse('2026-07-10T09:00:00'));
      expect(fake2.armed(), isEmpty, reason: "can't schedule the past");
      final nudges = later.pendingNudges();
      expect(nudges.length, 1);
      expect(nudges.single, contains('call mom'));
    });

    test('completing/undoing keeps the armed set derived — no leak after undo of a second reminder', () async {
      final fake = FakeScheduler();
      final s = await _open(makeTempDataDir(), fake);
      await s.handle('remind me to call mom on thursday at 5pm');
      await s.handle('remind me to take medicine at 9am'); // time-only -> tomorrow 09:00
      expect(fake.armed().length, 2);
      await s.handle('undo'); // reverses only the medicine reminder
      expect(fake.armed().length, 1);
      expect(fake.scheduled.values.single.body, contains('call mom'));
    });
  });

  group('reminder management (list / complete / cancel)', () {
    test('completing a reminder cancels its armed toast (reconcile derives it away)', () async {
      final fake = FakeScheduler();
      final s = await _open(makeTempDataDir(), fake);
      await s.handle('remind me to call mom on thursday at 5pm');
      expect(fake.armed().length, 1);
      final r = await s.handle('mark the reminder to call mom done');
      expect(r.toLowerCase(), contains('done'));
      expect(fake.armed(), isEmpty); // done -> no longer desired -> cancelled
    });

    test('cancelling a reminder deletes it and cancels the toast', () async {
      final fake = FakeScheduler();
      final s = await _open(makeTempDataDir(), fake);
      await s.handle('remind me to call mom on thursday at 5pm');
      final r = await s.handle('cancel the reminder to call mom');
      expect(r.toLowerCase(), contains('cancel'));
      expect(fake.armed(), isEmpty);
      expect(s.store.values.where((x) => x['typeId'] == 'reminder'), isEmpty);
    });

    test('list-reminders shows active reminders and excludes completed ones', () async {
      final s = await _open(makeTempDataDir(), FakeScheduler());
      await s.handle('remind me to call mom on thursday at 5pm');
      await s.handle('remind me to book the dentist on friday at 10am');
      await s.handle('mark the reminder to call mom done');
      final r = await s.handle('what are my reminders');
      expect(r, contains('1 reminder'));
      expect(r, contains('book the dentist'));
      expect(r, contains('Friday at 10:00 AM'));
      expect(r.contains('call mom'), isFalse); // completed -> excluded from the list
    });

    test('completing/cancelling an unknown reminder is a clear no-op', () async {
      final s = await _open(makeTempDataDir(), FakeScheduler());
      expect(await s.handle('mark the reminder to walk the dog done'), contains("couldn't find"));
      expect(await s.handle('cancel the reminder to walk the dog'), contains("couldn't find"));
    });
  });

  group('reschedule (snooze) a reminder', () {
    test('moves the reminder and RE-ARMS the toast at the new time', () async {
      final fake = FakeScheduler();
      final s = await _open(makeTempDataDir(), fake);
      await s.handle('remind me to call mom on thursday at 5pm');
      expect(fake.armed().values.single, DateTime.parse('2026-07-09T17:00:00'));
      final r = await s.handle('snooze the reminder to call mom to friday at 9am');
      expect(r.toLowerCase(), contains('moved'));
      expect(fake.armed().length, 1); // still exactly one
      expect(fake.armed().values.single, DateTime.parse('2026-07-10T09:00:00')); // re-armed at the NEW time
    });

    test('rescheduling an unknown reminder is a clear no-op', () async {
      final s = await _open(makeTempDataDir(), FakeScheduler());
      expect(await s.handle('snooze the reminder to walk the dog to friday at 9am'),
          contains("couldn't find"));
    });

    test('undo of a reschedule restores the original time and re-arms there', () async {
      final fake = FakeScheduler();
      final s = await _open(makeTempDataDir(), fake);
      await s.handle('remind me to call mom on thursday at 5pm');
      await s.handle('snooze the reminder to call mom to friday at 9am');
      expect(fake.armed().values.single, DateTime.parse('2026-07-10T09:00:00'));
      await s.handle('undo'); // reverse the reschedule
      expect(fake.armed().length, 1);
      expect(fake.armed().values.single, DateTime.parse('2026-07-09T17:00:00')); // back to Thu 5pm
    });
  });

  group('full reminder lifecycle keeps the armed toast correct', () {
    test('set -> snooze -> complete -> undo-complete re-arms -> cancel', () async {
      final fake = FakeScheduler();
      final s = await _open(makeTempDataDir(), fake);

      await s.handle('remind me to call mom on thursday at 5pm');
      expect(fake.armed().values.single, DateTime.parse('2026-07-09T17:00:00'));

      await s.handle('snooze the reminder to call mom to friday at 9am');
      expect(fake.armed().values.single, DateTime.parse('2026-07-10T09:00:00'));

      await s.handle('mark the reminder to call mom done'); // done -> cancelled
      expect(fake.armed(), isEmpty);

      await s.handle('undo'); // un-complete -> re-armed at the snoozed time
      expect(fake.armed().length, 1);
      expect(fake.armed().values.single, DateTime.parse('2026-07-10T09:00:00'));

      await s.handle('cancel the reminder to call mom'); // deleted -> gone
      expect(fake.armed(), isEmpty);
    });
  });

  group('graceful missing-time (no silent failure)', () {
    test('a reminder intent without a time asks when, writes nothing, arms nothing', () async {
      final fake = FakeScheduler();
      final s = Session(makeTempDataDir(),
          clock: _now,
          cloud: _RouteCloud({
            'skillId': 'set-reminder',
            'slots': <String, dynamic>{'text': 'call the dentist', 'when': null},
            'source': 'cloud',
          }),
          scheduler: fake);
      await s.init(retrieval: false);
      final r = await s.handle("don't let me forget to call the dentist");
      expect(r.toLowerCase(), contains('when')); // clarifies for a time
      expect(s.store.values.where((x) => x['typeId'] == 'reminder'), isEmpty);
      expect(fake.armed(), isEmpty);
    });
  });
}
