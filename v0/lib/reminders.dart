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

/// A stable OS notification id for a reminder ref — the SAME id across restarts (so re-arming a
/// reminder overwrites rather than duplicating) and across SDK versions (unlike `String.hashCode`,
/// which Dart does not guarantee stable across releases). FNV-1a over the ref's UTF-16 code units,
/// masked to a positive 31-bit int. Shared by every backend so ids never diverge.
int notificationId(String ref) {
  var h = 0x811c9dc5;
  for (final c in ref.codeUnits) {
    h = (h ^ c) * 0x01000193;
  }
  return h & 0x7fffffff;
}

/// The OS-notification seam. Intentionally tiny: [schedule]/[cancel]/[armed] are the whole
/// scheduling surface a platform backend maps 1:1 onto the OS API; [selfTest]/[unavailableReason]
/// let the backend report its own health so a toast that can't fire is never a SILENT failure.
abstract interface class NotificationScheduler {
  /// Arm a notification. Best-effort: a backend may be unable to display (permission denied) or to
  /// recall an already-scheduled one (see [cancel]); it reports that via [unavailableReason].
  Future<void> schedule(String ref, DateTime when, String body);

  /// Cancel a previously-armed notification. Best-effort — some backends can't recall an
  /// already-scheduled notification (e.g. an unpackaged Windows app has no identity to cancel by),
  /// so product logic must never assume cancel is guaranteed; the reconcile loop is the safety net.
  Future<void> cancel(String ref);

  /// The currently-armed set as ref -> the time it's armed for. The time lets reconcile detect a
  /// RESCHEDULE (same reminder, new time) and re-arm it. NOTE: in-memory today (empty at process
  /// start), so a cancel-while-the-app-was-closed can miss; hydrating from the OS's pending set is
  /// a per-backend improvement.
  Map<String, DateTime> armed();

  /// Fire an IMMEDIATE notification to prove display actually works — the "silently doesn't show"
  /// case (unpackaged Windows AUMID, denied macOS permission) is otherwise invisible. A launch
  /// smoke; returns true iff the native call succeeded. Callers may ignore it.
  Future<bool> selfTest();

  /// Null when reminders will actually fire; otherwise a short human-facing reason they WON'T
  /// (permission denied, backend init failed) so the UI can surface an actionable nudge instead of
  /// failing silently (directive #7). Meaningful only after the backend has tried to initialize —
  /// i.e. after the first reconcile.
  String? unavailableReason();
}

/// In-memory scheduler — the test double AND a safe production default (a no-op
/// toast layer until the native impl is smoked). Records calls so product logic
/// can be asserted with no OS and no network.
class FakeScheduler implements NotificationScheduler {
  final Map<String, Reminder> scheduled = {};
  final List<String> canceled = [];
  int scheduleCalls = 0; // total schedule() invocations (to prove dedupe/idempotence)
  bool selfTestCalled = false;

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

  @override
  Future<bool> selfTest() async {
    selfTestCalled = true;
    return true;
  }

  @override
  String? unavailableReason() => null; // the fake always "works" (no OS)
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
    } else if (rec != null && rec.startsWith('biweekly:')) {
      // every-OTHER weekday: phase-anchored to the first matching weekday on/after the
      // record's createdAt, then every 14 days — so "every other Tuesday" is deterministic.
      final createdAt = DateTime.tryParse(r['createdAt']?.toString() ?? '') ?? base;
      final anchor = _nextWeekly(base, rec.substring('biweekly:'.length), createdAt);
      at = _advanceBiweekly(anchor, now);
    } else if (rec != null && rec.startsWith('monthly:')) {
      // Nth weekday of each month — "2nd Tuesday", "last Friday". Format: monthly:<ordinal>:<day>,
      // ordinal 1..4 or -1 (last).
      final parts = rec.substring('monthly:'.length).split(':');
      at = _nextMonthlyOrdinal(base, int.tryParse(parts.first) ?? 1, parts.length > 1 ? parts[1] : '', now);
    } else if (rec != null && rec.startsWith('days:')) {
      // a set of weekdays — "every weekday" (days:1,2,3,4,5), "every weekend" (days:6,7)
      final wanted = rec.substring('days:'.length).split(',').map(int.tryParse).whereType<int>().toSet();
      at = _nextInWeekdaySet(base, wanted, now);
    } else if (rec != null && rec.startsWith('monthlyday:')) {
      at = _nextMonthlyDate(base, int.tryParse(rec.substring('monthlyday:'.length)) ?? 1, now);
    } else if (rec == 'yearly') {
      at = _nextYearly(base, now);
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

/// Weekday name -> ISO number, tolerating a plural ("tuesdays") and surrounding
/// whitespace/case. Returns null for anything unrecognized (callers fall back gracefully).
int? _lookupWeekday(String name) {
  final n = name.toLowerCase().trim();
  return _weekdays[n] ?? (n.endsWith('s') ? _weekdays[n.substring(0, n.length - 1)] : null);
}

/// The next "[ordinal]th [dayName] of the month" at [base]'s time-of-day strictly after [now].
/// [ordinal] is 1..4 (nth) or -1 (last). A month with no such occurrence (e.g. a 5th Tuesday) is
/// skipped. Deterministic date math — the scheduler drives it, never a model.
DateTime _nextMonthlyOrdinal(DateTime base, int ordinal, String dayName, DateTime now) {
  final wd = _lookupWeekday(dayName);
  if (wd == null) return base; // graceful fallback — never crash the schedule
  DateTime? occurrenceIn(int year, int month) {
    if (ordinal == -1) {
      var d = DateTime(year, month + 1, 0); // last day of the month
      while (d.weekday != wd) {
        d = d.subtract(const Duration(days: 1));
      }
      return DateTime(year, month, d.day, base.hour, base.minute);
    }
    var d = DateTime(year, month, 1);
    while (d.weekday != wd) {
      d = d.add(const Duration(days: 1)); // first [wd] of the month
    }
    d = d.add(Duration(days: 7 * (ordinal - 1))); // then the (ordinal-1)th week
    if (d.month != month) return null; // e.g. no 5th Tuesday this month
    return DateTime(year, month, d.day, base.hour, base.minute);
  }

  var y = now.year, m = now.month;
  for (var i = 0; i < 24; i++) {
    final occ = occurrenceIn(y, m);
    if (occ != null && occ.isAfter(now)) return occ;
    m++;
    if (m > 12) {
      m = 1;
      y++;
    }
  }
  return base;
}

/// From a biweekly [anchor] (a specific weekday+time), the next occurrence strictly after
/// [now] stepping 14 days at a time — so it never lands on the off-week.
DateTime _advanceBiweekly(DateTime anchor, DateTime now) {
  var c = anchor;
  if (c.isBefore(now)) {
    final periods = (now.difference(c).inDays / 14).floor(); // jump most of the way
    c = c.add(Duration(days: 14 * periods));
  }
  while (!c.isAfter(now)) {
    c = c.add(const Duration(days: 14));
  }
  return c;
}

/// The next occurrence of [dayName] at [base]'s time-of-day strictly after [now]. An
/// unrecognized day falls back to a one-off at [base] (graceful, never crashes).
DateTime _nextWeekly(DateTime base, String dayName, DateTime now) {
  final target = _lookupWeekday(dayName);
  if (target == null) return base;
  var c = DateTime(now.year, now.month, now.day, base.hour, base.minute, base.second);
  var ahead = (target - c.weekday) % 7;
  if (ahead < 0) ahead += 7;
  c = c.add(Duration(days: ahead));
  if (!c.isAfter(now)) c = c.add(const Duration(days: 7)); // today's slot already passed
  return c;
}

/// The next day whose weekday is in [wanted] (1=Mon..7=Sun) at [base]'s time-of-day
/// strictly after [now] — "every weekday" (1..5), "every weekend" (6,7), or any subset.
/// An empty set falls back to daily (graceful).
DateTime _nextInWeekdaySet(DateTime base, Set<int> wanted, DateTime now) {
  // only real weekdays (1..7) — a stray value (e.g. a bad "days:0") must not create a phantom.
  final valid = wanted.where((d) => d >= 1 && d <= 7).toSet();
  if (valid.isEmpty) return _nextDaily(base, now);
  for (var i = 0; i < 8; i++) {
    // construct each candidate DAY (DST-safe: keeps base's wall-clock time-of-day across a
    // transition, unlike adding absolute 24h Durations).
    final c = DateTime(now.year, now.month, now.day + i, base.hour, base.minute, base.second);
    if (valid.contains(c.weekday) && c.isAfter(now)) return c;
  }
  return _nextDaily(base, now); // unreachable given a non-empty valid set, but never crash
}

/// The next occurrence of day-of-month [dom] at [base]'s time-of-day strictly after [now]
/// — "the 15th of every month". A [dom] past a short month's end is clamped to its last day
/// (so "the 31st" fires on Feb 28), never skipped.
DateTime _nextMonthlyDate(DateTime base, int dom, DateTime now) {
  var y = now.year, m = now.month;
  for (var i = 0; i < 24; i++) {
    final lastDay = DateTime(y, m + 1, 0).day; // day 0 of next month = last of this
    final c = DateTime(y, m, dom.clamp(1, lastDay), base.hour, base.minute, base.second);
    if (c.isAfter(now)) return c;
    m++;
    if (m > 12) {
      m = 1;
      y++;
    }
  }
  return base;
}

/// The next anniversary of [base]'s month+day at [base]'s time-of-day strictly after [now]
/// — "every year on March 3". A Feb-29 base is clamped to Feb-28 in common years.
DateTime _nextYearly(DateTime base, DateTime now) {
  for (var y = now.year; y <= now.year + 2; y++) {
    final lastDay = DateTime(y, base.month + 1, 0).day;
    final c = DateTime(y, base.month, base.day.clamp(1, lastDay), base.hour, base.minute, base.second);
    if (c.isAfter(now)) return c;
  }
  return base;
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
