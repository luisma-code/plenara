/// Plenara v0 — shared annual-date math (birthdays and any "next occurrence of a
/// date's month/day"). THE single authority: the interpreter's next_annual/
/// days_until_annual compute fns, the on-open birthday nudges (people.dart),
/// reminders' yearly recurrence, and the planner's relationship nudge/agenda all
/// route through here, so every surface agrees exactly.
///
/// Two rules live here and nowhere else:
///  1. **Feb-29 dates are observed on Feb 28 in common years** — the
///     conservative "never late for a birthday" choice (not Mar 1, not skipped).
///  2. **Day math is calendar-component arithmetic**, never Duration adds or
///     `.difference().inDays` across local midnights, so a 23/25-hour DST
///     transition day still counts as exactly one day.
library;

/// The annual occurrence of [d]'s month/day in [year]. A Feb-29 date lands on
/// Feb 28 in common years (rule 1 above).
DateTime annualOccurrenceInYear(DateTime d, int year) {
  final lastDay = DateTime(year, d.month + 1, 0).day;
  return DateTime(year, d.month, d.day <= lastDay ? d.day : lastDay);
}

/// The next calendar occurrence of [d]'s month/day, on or after today (year
/// ignored), with the Feb-29 rule applied.
DateTime nextAnnual(DateTime d, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final thisYear = annualOccurrenceInYear(d, now.year);
  return thisYear.isBefore(today)
      ? annualOccurrenceInYear(d, now.year + 1)
      : thisYear;
}

/// Calendar days from [from]'s date to [to]'s date (negative when [to] is
/// earlier). DST-immune by construction: the dates are re-anchored in UTC,
/// where every day is exactly 24h, so the count is pure component arithmetic.
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// Whole days from today to the next annual occurrence of [d] (0 = today).
int daysUntilAnnual(DateTime d, DateTime now) =>
    calendarDaysBetween(now, nextAnnual(d, now));
