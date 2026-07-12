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
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s, {Set<String> knownContacts = const {}}) async =>
      throw StateError('cloud hit for "$u" — reminder flows must be pure corpus');
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      throw StateError('cloud authoring hit — unexpected');
  @override
  Future<CloudResult<String>> generate(String kind, String context) async =>
      throw StateError('cloud generate hit — unexpected');
}

/// Cloud returning one scripted residual route (to drive the missing-time path).
class _RouteCloud implements CloudClient {
  final Map<String, dynamic>? route;
  _RouteCloud(this.route);
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s, {Set<String> knownContacts = const {}}) async =>
      CloudOk(route);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<String>> generate(String kind, String context) async => const CloudError(CloudErrorKind.noKey);
}

Future<Session> _open(String dir, FakeScheduler fake, {DateTime? clock}) async {
  final s = Session(dir, clock: clock ?? _now, cloud: _NoCloud(), scheduler: fake);
  await s.init(retrieval: false);
  return s;
}

/// A backend that reports itself unavailable (e.g. macOS permission denied) — to prove the seam's
/// health signal surfaces to the user instead of failing silently (directive #7).
class _DegradedScheduler implements NotificationScheduler {
  @override
  Future<void> schedule(String ref, DateTime when, String body) async {}
  @override
  Future<void> cancel(String ref) async {}
  @override
  Map<String, DateTime> armed() => {};
  @override
  Future<bool> selfTest() async => false;
  @override
  String? unavailableReason() => "Reminders won't fire — enable notifications.";
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

  group('scheduler seam: health + stable ids (cross-platform, directive #7)', () {
    test('notificationId is stable, positive, and ref-distinct', () {
      expect(notificationId('reminder-a'), notificationId('reminder-a')); // same ref -> same id
      expect(notificationId('reminder-a'), isNot(notificationId('reminder-b')));
      expect(notificationId('reminder-a'), greaterThanOrEqualTo(0)); // 31-bit positive
    });

    test('an unavailable backend surfaces a ⚠️ nudge; a healthy one does not', () async {
      final degraded = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: _DegradedScheduler());
      await degraded.init(retrieval: false);
      expect(degraded.pendingNudges().any((n) => n.startsWith('⚠️')), isTrue);

      final healthy = await _open(makeTempDataDir(), FakeScheduler());
      expect(healthy.pendingNudges().any((n) => n.startsWith('⚠️')), isFalse);
    });

    test('FakeScheduler.selfTest records the call', () async {
      final fake = FakeScheduler();
      expect(await fake.selfTest(), isTrue);
      expect(fake.selfTestCalled, isTrue);
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

    test('correcting a reminder reverses the old one and arms the new (toast reconciles)', () async {
      final fake = FakeScheduler();
      final s = await _open(makeTempDataDir(), fake);
      await s.handle('remind me to call mom on thursday at 5pm');
      await s.handle('no, I meant to remind me to call dad on thursday at 5pm');
      final rems = s.store.values.where((x) => x['typeId'] == 'reminder' && x['done'] != true).toList();
      expect(rems.length, 1); // the mom reminder was reversed
      expect(rems.single['text'], 'call dad');
      expect(fake.armed().length, 1);
      expect(fake.scheduled.values.single.body, contains('call dad')); // mom's toast cancelled, dad's armed
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

  group('daily recurring reminders (F-03 / #8)', () {
    test('arms at the next occurrence of the daily time', () async {
      final fake = FakeScheduler();
      final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: fake);
      await s.init(retrieval: false);
      final r = await s.handle('remind me every day at 5pm to take my meds');
      expect(r, contains('every day'));
      expect(r, contains('take my meds'));
      expect(fake.armed().length, 1);
      expect(fake.armed().values.single, DateTime.parse('2026-07-06T17:00:00')); // today 5pm (now is 9am)
    });

    test('weekly reminder arms at the next occurrence of that weekday', () async {
      final fake = FakeScheduler();
      final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: fake); // Mon 2026-07-06 9am
      await s.init(retrieval: false);
      final r = await s.handle('remind me every tuesday at 9am to water the plants');
      expect(r, contains('every tuesday'));
      expect(fake.armed().values.single, DateTime.parse('2026-07-07T09:00:00')); // next Tue = 07-07
    });

    test('biweekly ("every other tuesday") arms the first occurrence', () async {
      final fake = FakeScheduler();
      final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: fake); // Mon 07-06 9am
      await s.init(retrieval: false);
      final r = await s.handle('remind me every other tuesday at 9am to water the garden');
      expect(r, contains('every other'));
      expect(fake.armed().values.single, DateTime.parse('2026-07-07T09:00:00')); // first Tue
    });
    test('monthly ordinal ("every second tuesday") arms at the 2nd Tuesday (F-03)', () async {
      final fake = FakeScheduler();
      final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: fake); // Mon 2026-07-06
      await s.init(retrieval: false);
      final r = await s.handle('remind me every second tuesday at 9am to take the bins out');
      expect(r.toLowerCase(), contains('second tuesday'));
      // July 2026: 1st Tue = 07-07, 2nd Tue = 07-14 (both after the 07-06 clock)
      expect(fake.armed().values.single, DateTime.parse('2026-07-14T09:00:00'));
    });
    test('monthly ordinal "last friday" arms at the last Friday of the month', () async {
      final fake = FakeScheduler();
      final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: fake);
      await s.init(retrieval: false);
      await s.handle('remind me on the last friday of every month at 5pm to file my report');
      // last Friday of July 2026 is 07-31
      expect(fake.armed().values.single, DateTime.parse('2026-07-31T17:00:00'));
    });
    test('biweekly skips the off-week (07-07 then 07-21, not 07-14)', () async {
      final dir = makeTempDataDir();
      final s1 = Session(dir, clock: _now, cloud: _NoCloud(), scheduler: FakeScheduler());
      await s1.init(retrieval: false);
      await s1.handle('remind me every other tuesday at 9am to water the garden'); // anchor 07-07
      final fake2 = FakeScheduler();
      final s2 = Session(dir, clock: DateTime.parse('2026-07-08T09:00:00'), cloud: _NoCloud(), scheduler: fake2);
      await s2.init(retrieval: false); // reopened after the first fire
      expect(fake2.armed().values.single, DateTime.parse('2026-07-21T09:00:00')); // +14, not +7
    });
    test('after the time passes, reopening re-arms for the NEXT day (regenerate on open)', () async {
      final dir = makeTempDataDir();
      final s1 = Session(dir, clock: _now, cloud: _NoCloud(), scheduler: FakeScheduler());
      await s1.init(retrieval: false);
      await s1.handle('remind me every day at 5pm to take my meds');
      // reopen at 6pm, past today's 5pm fire
      final fake2 = FakeScheduler();
      final s2 = Session(dir, clock: DateTime.parse('2026-07-06T18:00:00'), cloud: _NoCloud(), scheduler: fake2);
      await s2.init(retrieval: false);
      expect(fake2.armed().values.single, DateTime.parse('2026-07-07T17:00:00')); // tomorrow 5pm
    });
  });

  group('weekday-set / monthly-date / yearly recurrence (gaps #46/#48/#49)', () {
    test('"every weekday" arms the next Mon–Fri slot', () async {
      final fake = FakeScheduler();
      final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: fake); // Mon 07-06 9am
      await s.init(retrieval: false);
      final r = await s.handle('remind me every weekday at 5pm to check email');
      expect(r.toLowerCase(), contains('every weekday'));
      expect(fake.armed().values.single, DateTime.parse('2026-07-06T17:00:00')); // today (Mon) 5pm
    });

    test('"every weekday" from a Saturday skips the weekend to Monday', () async {
      final fake = FakeScheduler();
      final sat = DateTime.parse('2026-07-11T09:00:00'); // a Saturday
      final s = Session(makeTempDataDir(), clock: sat, cloud: _NoCloud(), scheduler: fake);
      await s.init(retrieval: false);
      await s.handle('remind me every weekday at 8am to stand up');
      expect(fake.armed().values.single, DateTime.parse('2026-07-13T08:00:00')); // Monday 8am
    });

    test('"every weekend" arms the next Sat/Sun slot', () async {
      final fake = FakeScheduler();
      final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: fake); // Mon 07-06
      await s.init(retrieval: false);
      final r = await s.handle('remind me every weekend at 9am to call grandma');
      expect(r.toLowerCase(), contains('every weekend'));
      expect(fake.armed().values.single, DateTime.parse('2026-07-11T09:00:00')); // Sat 07-11 9am
    });

    test('"the 15th of every month" arms at that day-of-month', () async {
      final fake = FakeScheduler();
      final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: fake); // 07-06
      await s.init(retrieval: false);
      final r = await s.handle('remind me on the 15th of every month at 9am to pay rent');
      expect(r, contains('15th'));
      expect(fake.armed().values.single, DateTime.parse('2026-07-15T09:00:00'));
    });

    test('a monthly day past the current one rolls to next month', () async {
      final fake = FakeScheduler();
      final late = DateTime.parse('2026-07-20T09:00:00');
      final s = Session(makeTempDataDir(), clock: late, cloud: _NoCloud(), scheduler: fake);
      await s.init(retrieval: false);
      await s.handle('remind me on the 3rd of every month at 9am to review the budget');
      expect(fake.armed().values.single, DateTime.parse('2026-08-03T09:00:00')); // Aug 3
    });

    test('"every year on march 3" arms the next anniversary', () async {
      final fake = FakeScheduler();
      final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: fake); // July 2026
      await s.init(retrieval: false);
      final r = await s.handle('remind me every year on march 3 at 9am to wish dad happy birthday');
      expect(r.toLowerCase(), contains('every year'));
      expect(fake.armed().values.single, DateTime.parse('2027-03-03T09:00:00')); // this year's is past
    });

    test('"every monday and thursday" arms the next of those two days', () async {
      final fake = FakeScheduler();
      final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: fake); // Mon 07-06 9am
      await s.init(retrieval: false);
      final r = await s.handle('remind me every monday and thursday at 5pm to water the plants');
      expect(r.toLowerCase(), contains('monday and thursday'));
      expect(fake.armed().values.single, DateTime.parse('2026-07-06T17:00:00')); // today (Mon) 5pm
    });

    test('a three-day set ("monday, wednesday and friday") parses all three', () async {
      final fake = FakeScheduler();
      final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: fake); // Mon 07-06 9am
      await s.init(retrieval: false);
      await s.handle('remind me every monday, wednesday and friday at 9am to journal');
      expect(fake.armed().values.single, DateTime.parse('2026-07-08T09:00:00')); // Wed 07-08 (Mon 9am already now)
    });

    test('a plural weekday ("every tuesdays") still resolves (gap #53)', () async {
      final fake = FakeScheduler();
      final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: fake); // Mon 07-06
      await s.init(retrieval: false);
      await s.handle('remind me every tuesdays at 9am to take the bins out');
      expect(fake.armed().values.single, DateTime.parse('2026-07-07T09:00:00')); // next Tue
    });

    test('postfix "X tomorrow at 5pm" arms on tomorrow at the given time (gap #54)', () async {
      final fake = FakeScheduler();
      final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: fake); // Mon 07-06 9am
      await s.init(retrieval: false);
      final r = await s.handle('remind me to call mom tomorrow at 5pm');
      expect(r, contains('call mom'));
      expect(fake.armed().values.single, DateTime.parse('2026-07-07T17:00:00')); // tomorrow 5pm, day kept
    });
  });

  group('date-filtered reminder listing (gap #50)', () {
    Future<Session> seeded() async {
      final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud(), scheduler: FakeScheduler());
      await s.init(retrieval: false);
      await s.handle('remind me to call mom tomorrow at 5pm'); // 07-07 (this week)
      await s.handle('remind me to see the dentist next monday at 2pm'); // 07-13 (next week)
      return s;
    }

    test('"what reminders do I have tomorrow" filters to that day', () async {
      final r = await (await seeded()).handle('what reminders do i have tomorrow');
      expect(r, contains('1 reminder'));
      expect(r, contains('call mom'));
      expect(r, isNot(contains('dentist')));
    });

    test('"what reminders do I have this week" spans Mon–Sun of the current week', () async {
      final r = await (await seeded()).handle('what reminders do i have this week');
      expect(r, contains('1 reminder')); // call mom is this week; dentist (next Mon) is not
      expect(r, contains('call mom'));
      expect(r, isNot(contains('dentist')));
    });

    test('a day with nothing scheduled says so', () async {
      final r = await (await seeded()).handle('what reminders do i have friday');
      expect(r.toLowerCase(), contains('no reminders'));
    });
  });

  group('ProvideSlot — missing-slot follow-up dialogue (§6.3)', () {
    Session _reminderMissingWhen(FakeScheduler fake) => Session(makeTempDataDir(),
        clock: _now,
        cloud: _RouteCloud({
          'skillId': 'set-reminder',
          'slots': <String, dynamic>{'text': 'call the dentist', 'when': null},
          'source': 'cloud',
        }),
        scheduler: fake);

    test('asks for the missing time, then the NEXT turn completes and arms it', () async {
      final fake = FakeScheduler();
      final s = _reminderMissingWhen(fake);
      await s.init(retrieval: false);
      // turn 1: a corpus-missing phrase -> cloud route with no time -> ask
      final q = await s.handle('can you make sure i ring the dentist');
      expect(q.toLowerCase(), contains('when'));
      expect(s.store.values.where((x) => x['typeId'] == 'reminder'), isEmpty); // nothing yet
      expect(fake.armed(), isEmpty);
      // turn 2: supply the time -> resolved through the datetime type, dispatched, armed
      final done = await s.handle('thursday at 5pm');
      expect(done, contains('call the dentist'));
      expect(fake.armed().length, 1);
      expect(fake.armed().values.single, _thu5pm);
    });

    test('"never mind" abandons the pending fill (nothing written)', () async {
      final s = _reminderMissingWhen(FakeScheduler());
      await s.init(retrieval: false);
      await s.handle('can you make sure i ring the dentist'); // asks
      expect((await s.handle('never mind')).toLowerCase(), contains('never mind'));
      expect(s.store.values.where((x) => x['typeId'] == 'reminder'), isEmpty);
    });

    test('a system command (help) interrupts the fill instead of becoming the slot value', () async {
      final s = _reminderMissingWhen(FakeScheduler());
      await s.init(retrieval: false);
      await s.handle('can you make sure i ring the dentist'); // asks for the time
      final r = await s.handle('what can you do'); // help — NOT a time answer
      expect(r.toLowerCase(), contains('reminder')); // got the help surface
      expect(r.toLowerCase(), isNot(contains('when should i'))); // did not re-ask for the slot
      expect(s.store.values.where((x) => x['typeId'] == 'reminder'), isEmpty); // fill abandoned
    });

    test('a non-parseable time answer re-asks rather than arming garbage', () async {
      final s = _reminderMissingWhen(FakeScheduler());
      await s.init(retrieval: false);
      await s.handle('can you make sure i ring the dentist');
      final again = await s.handle('sometime'); // no clock time -> still missing
      expect(again.toLowerCase(), contains('when'));
      expect(s.store.values.where((x) => x['typeId'] == 'reminder'), isEmpty);
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
