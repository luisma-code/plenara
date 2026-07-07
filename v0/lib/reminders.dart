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

/// Every not-done reminder record with a parseable `remindAt`, as a [Reminder].
Iterable<Reminder> allReminders(_Store store) sync* {
  for (final r in store.values) {
    if (r['typeId'] != reminderTypeId) continue;
    if (r['done'] == true) continue;
    final at = DateTime.tryParse(r['remindAt']?.toString() ?? '');
    if (at == null) continue;
    yield Reminder(r['id'] as String, r['text']?.toString() ?? 'reminder', at);
  }
}

/// Reminders still in the future — the set that should be armed as OS notifications,
/// keyed by record id.
Map<String, Reminder> desiredArmed(_Store store, DateTime now) => {
      for (final rem in allReminders(store))
        if (rem.at.isAfter(now)) rem.ref: rem
    };

/// Past-due, not-done reminders — surfaced as on-open nudges (you can't schedule a
/// toast in the past), soonest-missed first.
List<Reminder> dueReminders(_Store store, DateTime now) => [
      for (final rem in allReminders(store))
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
