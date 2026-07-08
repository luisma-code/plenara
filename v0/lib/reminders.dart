/// Plenara v0 — reminders + the OS-notification seam (Spec 04 §3.1 adapter; the
/// F2 retention hook). Two ideas kept deliberately separate:
///
///  1. [NotificationScheduler] — the razor-thin OS shim. `schedule`/`cancel`/
///     `armed` map 1:1 to platform notification APIs. The real Windows impl is a
///     few lines over flutter_local_notifications; everything worth testing lives
///     OUT here, so only that shim needs a one-time human smoke (directive #1).
///  2. The reconciliation LOGIC ([desiredArmed], [dueReminders],
///     [reconcileReminders]) — pure over the record store, so the whole product
///     behaviour (which reminders arm, dedupe on re-open, cancel on undo, past-due
///     nudges) is CI-tested deterministically against [FakeScheduler].
///
/// The armed set is DERIVED from the persisted records, never tracked imperatively.
/// That is what makes undo/delete "just work": the record disappears from the
/// store, so the next reconcile cancels its notification with no special wiring —
/// and re-opening the app re-derives the exact same set (idempotent, no dupes).
library;

/// The type id of a reminder record. Reminder derivation keys on this + a
/// parseable `remindAt` datetime field, so the projection is well-defined and a
/// future `remindAt` on another type could opt in the same way.
const reminderTypeId = 'reminder';

/// A reminder projected from the record store: fire [body] at [at] for record [ref].
class Reminder {
  final String ref; // the backing record id — also the notification handle
  final String body; // human-facing text ("call mom")
  final DateTime at;
  const Reminder(this.ref, this.body, this.at);
}

/// The OS-notification seam. Intentionally tiny: the three members are the entire
/// surface a platform backend must implement. [armed] mirrors the OS's currently
/// scheduled set so reconciliation can diff without re-querying the platform.
abstract interface class NotificationScheduler {
  Future<void> schedule(String ref, DateTime when, String body);
  Future<void> cancel(String ref);
  /// The currently-armed set as ref -> the time it's armed for. The time lets
  /// reconcile detect a RESCHEDULE (same reminder, new time) and re-arm it.
  Map<String, DateTime> armed();
}

/// In-memory scheduler — the test double AND a safe production default (a no-op
/// toast layer until the native impl is smoked). Records calls so product logic
/// can be asserted with no OS and no network.
class FakeScheduler implements NotificationScheduler {
  final Map<String, Reminder> scheduled = {};
  final List<String> canceled = [];
  int scheduleCalls = 0; // total schedule() invocations (to prove dedupe/idempotence)

  @override
  Future<void> schedule(String ref, DateTime when, String body) async {
    scheduleCalls++;
    scheduled[ref] = Reminder(ref, body, when);
  }

  @override
  Future<void> cancel(String ref) async {
    if (scheduled.remove(ref) != null) canceled.add(ref);
  }

  @override
  Map<String, DateTime> armed() => {for (final e in scheduled.entries) e.key: e.value.at};
}

typedef _Store = Map<String, Map<String, dynamic>>;

/// Every not-done reminder record with a parseable `remindAt`, as a [Reminder]. For a
/// RECURRING reminder (`recurrence: "daily"`) the effective time is the NEXT occurrence
/// at or after [now] (regenerate-on-open, Spec 04 §3.13) — so it's always future-dated
/// and never falls into the past-due bucket.
Iterable<Reminder> allReminders(_Store store, DateTime now) sync* {
  for (final r in store.values) {
    if (r['typeId'] != reminderTypeId) continue;
    if (r['done'] == true) continue;
    final base = DateTime.tryParse(r['remindAt']?.toString() ?? '');
    if (base == null) continue;
    final rec = r['recurrence']?.toString();
    final DateTime at;
    if (rec == 'daily') {
      at = _nextDaily(base, now);
    } else if (rec != null && rec.startsWith('weekly:')) {
      at = _nextWeekly(base, rec.substring('weekly:'.length), now);
    } else {
      at = base;
    }
    yield Reminder(r['id'] as String, r['text']?.toString() ?? 'reminder', at);
  }
}

/// The next occurrence of [base]'s time-of-day strictly after [now] (today if still
/// ahead, else tomorrow) — the daily-recurrence fire time.
DateTime _nextDaily(DateTime base, DateTime now) {
  var c = DateTime(now.year, now.month, now.day, base.hour, base.minute, base.second);
  if (!c.isAfter(now)) c = c.add(const Duration(days: 1));
  return c;
}

const _weekdays = {
  'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4, 'friday': 5, 'saturday': 6, 'sunday': 7,
  'mon': 1, 'tue': 2, 'tues': 2, 'wed': 3, 'thu': 4, 'thur': 4, 'thurs': 4, 'fri': 5, 'sat': 6, 'sun': 7,
};

/// The next occurrence of [dayName] at [base]'s time-of-day strictly after [now]. An
/// unrecognized day falls back to a one-off at [base] (graceful, never crashes).
DateTime _nextWeekly(DateTime base, String dayName, DateTime now) {
  final target = _weekdays[dayName.toLowerCase().trim()];
  if (target == null) return base;
  var c = DateTime(now.year, now.month, now.day, base.hour, base.minute, base.second);
  var ahead = (target - c.weekday) % 7;
  if (ahead < 0) ahead += 7;
  c = c.add(Duration(days: ahead));
  if (!c.isAfter(now)) c = c.add(const Duration(days: 7)); // today's slot already passed
  return c;
}

/// Reminders still in the future — the set that should be armed as OS notifications,
/// keyed by record id.
Map<String, Reminder> desiredArmed(_Store store, DateTime now) => {
      for (final rem in allReminders(store, now))
        if (rem.at.isAfter(now)) rem.ref: rem
    };

/// Past-due, not-done reminders — surfaced as on-open nudges (you can't schedule a
/// toast in the past), soonest-missed first. (Recurring reminders are always future.)
List<Reminder> dueReminders(_Store store, DateTime now) => [
      for (final rem in allReminders(store, now))
        if (!rem.at.isAfter(now)) rem
    ]..sort((a, b) => a.at.compareTo(b.at));

/// Reconcile the OS scheduler to match the store: cancel anything armed that is no
/// longer desired (undone/deleted/done/now-past), arm anything desired not yet
/// armed. Idempotent — calling it again with the same store schedules nothing new,
/// so re-opening the app produces no duplicate notifications.
Future<void> reconcileReminders(
    NotificationScheduler sched, _Store store, DateTime now) async {
  final desired = desiredArmed(store, now);
  final armed = sched.armed(); // ref -> armed time (snapshot)
  // Cancel anything armed that is no longer desired OR whose time changed (reschedule).
  for (final e in armed.entries) {
    final want = desired[e.key];
    if (want == null || want.at != e.value) await sched.cancel(e.key);
  }
  // (Re)arm anything desired that isn't already armed at the right time.
  for (final rem in desired.values) {
    if (armed[rem.ref] != rem.at) await sched.schedule(rem.ref, rem.at, rem.body);
  }
}
