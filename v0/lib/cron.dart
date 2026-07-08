/// Plenara v0 — a minimal standard 5-field cron evaluator for schedule automations
/// (Spec 01 §4.4 `condition.cronExpression`). Fields: minute hour day-of-month month
/// day-of-week. Each field supports `*`, `N`, `a-b`, `a,b,...`, and `*/n`. Day-of-week is
/// 0..6 with Sunday = 0 (7 also accepted as Sunday). Deterministic (no wall clock) — the
/// scheduler drives it, never a model.
library;

/// True iff [expr] fires at the wall-clock minute of [t] (seconds ignored).
bool cronMatches(String expr, DateTime t) {
  final f = expr.trim().split(RegExp(r'\s+'));
  if (f.length != 5) throw FormatException('cron needs 5 fields, got ${f.length}: "$expr"');
  return _field(f[0], t.minute, 0, 59) &&
      _field(f[1], t.hour, 0, 23) &&
      _field(f[2], t.day, 1, 31) &&
      _field(f[3], t.month, 1, 12) &&
      _dow(f[4], t.weekday);
}

/// The next minute strictly after [after] at which [expr] fires, or null if none within
/// [maxDays] (a safety bound; a well-formed cron fires well inside a year).
DateTime? nextFire(String expr, DateTime after, {int maxDays = 366}) {
  cronMatches(expr, after); // validate the expression once, up front (throws on malformed)
  var t = DateTime(after.year, after.month, after.day, after.hour, after.minute)
      .add(const Duration(minutes: 1)); // next whole minute
  final limit = after.add(Duration(days: maxDays));
  while (!t.isAfter(limit)) {
    if (cronMatches(expr, t)) return t;
    t = t.add(const Duration(minutes: 1));
  }
  return null;
}

/// If a fire occurred in the half-open window (since, now], returns that fire time (the first
/// after [since]); else null. Used for catch-up on app open — a scheduled automation whose time
/// passed while the app was closed still fires once.
DateTime? dueSince(String expr, DateTime since, DateTime now) {
  final n = nextFire(expr, since);
  return (n != null && !n.isAfter(now)) ? n : null;
}

bool _dow(String field, int dartWeekday) {
  // Dart weekday: Mon=1..Sun=7. Cron dow: Sun=0..Sat=6 (7 also = Sunday).
  final cronVal = dartWeekday == 7 ? 0 : dartWeekday;
  if (cronVal == 0) return _field(field, 0, 0, 7) || _field(field, 7, 0, 7);
  return _field(field, cronVal, 0, 7);
}

bool _field(String field, int value, int min, int max) {
  for (final part in field.split(',')) {
    if (part == '*') return true;
    if (part.startsWith('*/')) {
      final step = int.tryParse(part.substring(2));
      if (step != null && step > 0 && value >= min && (value - min) % step == 0) return true;
      continue;
    }
    final dash = part.indexOf('-');
    if (dash > 0) {
      final a = int.tryParse(part.substring(0, dash)), b = int.tryParse(part.substring(dash + 1));
      if (a != null && b != null && value >= a && value <= b) return true;
      continue;
    }
    if (int.tryParse(part) == value) return true;
  }
  return false;
}
