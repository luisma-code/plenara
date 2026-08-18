/// Plenara v0 — a minimal 5-field cron evaluator for schedule automations
/// (Spec 01 §4.4 `condition.cronExpression`). Fields: minute hour day-of-month
/// month day-of-week. Each field supports `*`, `N`, `a-b`, `a,b,...`, and `*/n`
/// — and NOTHING else. Anything the evaluator cannot honor — weekday/month
/// names (`MON`, `JAN`), steps on ranges (`1-5/2`), out-of-range values — is
/// rejected with a [FormatException] at parse time, so an unsupported
/// expression can never register as an armed automation that silently never
/// fires (the no-silent-failure rule). Day-of-week is 0..6 with Sunday = 0
/// (7 also accepted as Sunday).
///
/// **Deviation from standard cron, deliberate:** when BOTH day-of-month and
/// day-of-week are restricted, standard cron fires when either matches (OR);
/// this evaluator requires both (AND) — `0 9 13 * 5` is "9am on Friday the
/// 13th", not "9am every Friday and every 13th". Pinned by cron_test.dart.
///
/// Deterministic (no wall clock) — the scheduler drives it, never a model.
library;

/// One parsed field: null = `*` (any); otherwise (from, to, step) specs, any
/// of which matching admits the value ((v - from) % step == 0 within range).
typedef _Field = List<(int, int, int)>?;

class _Parsed {
  final _Field minute, hour, dom, month, dow;
  const _Parsed(this.minute, this.hour, this.dom, this.month, this.dow);
}

_Parsed _parse(String expr) {
  final f = expr.trim().split(RegExp(r'\s+'));
  if (f.length != 5) {
    throw FormatException('cron needs 5 fields, got ${f.length}: "$expr"');
  }
  return _Parsed(
    _parseField(f[0], 0, 59, 'minute'),
    _parseField(f[1], 0, 23, 'hour'),
    _parseField(f[2], 1, 31, 'day-of-month'),
    _parseField(f[3], 1, 12, 'month'),
    _parseField(f[4], 0, 7, 'day-of-week'),
  );
}

_Field _parseField(String field, int min, int max, String name) {
  if (field == '*') return null;
  final specs = <(int, int, int)>[];
  for (final part in field.split(',')) {
    if (part == '*') return null; // '*' anywhere in a list = any
    if (part.startsWith('*/')) {
      final step = int.tryParse(part.substring(2));
      if (step == null || step <= 0) {
        throw FormatException("bad step '$part' in the $name field");
      }
      specs.add((min, max, step));
      continue;
    }
    final dash = part.indexOf('-');
    if (dash > 0) {
      final a = int.tryParse(part.substring(0, dash));
      final b = int.tryParse(part.substring(dash + 1));
      if (a == null || b == null) {
        throw FormatException(
            "unsupported token '$part' in the $name field — only *, N, a-b, "
            'a,b,..., and */n are supported (no names, no steps on ranges)');
      }
      if (a < min || b > max || a > b) {
        throw FormatException(
            "range '$part' outside $min-$max in the $name field");
      }
      specs.add((a, b, 1));
      continue;
    }
    final n = int.tryParse(part);
    if (n == null) {
      throw FormatException(
          "unsupported token '$part' in the $name field — only *, N, a-b, "
          'a,b,..., and */n are supported (names like MON are not)');
    }
    if (n < min || n > max) {
      throw FormatException("value $n outside $min-$max in the $name field");
    }
    specs.add((n, n, 1));
  }
  if (specs.isEmpty) throw FormatException('empty $name field');
  return specs;
}

bool _match(_Field specs, int value) {
  if (specs == null) return true;
  for (final (from, to, step) in specs) {
    if (value >= from && value <= to && (value - from) % step == 0) return true;
  }
  return false;
}

bool _dowMatch(_Field specs, int dartWeekday) {
  // Dart weekday: Mon=1..Sun=7. Cron dow: Sun=0..Sat=6 (7 also = Sunday).
  final cronVal = dartWeekday == 7 ? 0 : dartWeekday;
  if (cronVal == 0) return _match(specs, 0) || _match(specs, 7);
  return _match(specs, cronVal);
}

bool _dayMatches(_Parsed c, DateTime day) =>
    _match(c.dom, day.day) &&
    _match(c.month, day.month) &&
    _dowMatch(c.dow, day.weekday);

/// True iff [expr] fires at the wall-clock minute of [t] (seconds ignored).
/// Throws [FormatException] on any expression the evaluator cannot honor.
bool cronMatches(String expr, DateTime t) {
  final c = _parse(expr);
  return _match(c.minute, t.minute) && _match(c.hour, t.hour) && _dayMatches(c, t);
}

/// The next minute strictly after [after] at which [expr] fires, or null if none
/// within [maxDays] (a safety bound; a well-formed cron fires well inside a year).
///
/// Cost-bounded: days whose date fields can't match are skipped at day
/// granularity, and minutes are only scanned inside candidate days — a yearly
/// cron is ~366 cheap day checks plus one in-day scan, not 527k minute
/// evaluations. Day stepping uses date components (never Duration adds), so a
/// DST transition can't skew the scan; a fire minute that lands in a
/// spring-forward gap normalizes to the following hour (fires late, never lost).
DateTime? nextFire(String expr, DateTime after, {int maxDays = 366}) {
  final c = _parse(expr); // validates up front (throws on malformed)
  final firstFrom = after.hour * 60 + after.minute + 1; // next whole minute
  for (var i = 0; i <= maxDays; i++) {
    final day = DateTime(after.year, after.month, after.day + i);
    if (!_dayMatches(c, day)) continue;
    final from = i == 0 ? firstFrom : 0;
    for (var h = 0; h < 24; h++) {
      if (!_match(c.hour, h) || (h + 1) * 60 <= from) continue;
      for (var m = 0; m < 60; m++) {
        if (!_match(c.minute, m) || h * 60 + m < from) continue;
        return DateTime(day.year, day.month, day.day, h, m);
      }
    }
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
