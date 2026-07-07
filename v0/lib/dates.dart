/// Plenara v0 — shared annual-date math (birthdays and any "next occurrence of a
/// date's month/day"). Used by the interpreter's next_annual/days_until_annual
/// compute fns AND by the on-open birthday nudges, so both agree exactly.
library;

/// The next calendar occurrence of [d]'s month/day, on or after today (year ignored).
DateTime nextAnnual(DateTime d, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final thisYear = DateTime(now.year, d.month, d.day);
  return thisYear.isBefore(today) ? DateTime(now.year + 1, d.month, d.day) : thisYear;
}

/// Whole days from today to the next annual occurrence of [d] (0 = today).
int daysUntilAnnual(DateTime d, DateTime now) =>
    nextAnnual(d, now).difference(DateTime(now.year, now.month, now.day)).inDays;
