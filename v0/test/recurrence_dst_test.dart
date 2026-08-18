/// DST-safe recurrence (reminders.dart). Every day-stepping helper must use
/// date-COMPONENT arithmetic (DateTime(y, m, d + n, hh, mm)) — never absolute
/// Duration adds across days, which drift by an hour (and hence sometimes a
/// day) over a 23/25-hour DST transition day.
///
/// The invariant sweep below holds in ANY host timezone: component stepping can
/// never produce a wrong wall-clock hour or a wrong weekday/ordinal/day, so the
/// assertions are TZ-independent. On a host WITH DST (this repo's macOS host is
/// America/Los_Angeles) the sweep is additionally a genuine regression net: the
/// old Duration-stepping implementation fails it (2nd-Sunday firing Saturday
/// after the November transition, biweekly/daily/weekly hour drift across
/// either transition).
import 'package:plenara/reminders.dart';
import 'package:test/test.dart';

/// Calendar days between two dates, DST-immune by UTC reconstruction.
int _calDays(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
    .difference(DateTime.utc(a.year, a.month, a.day))
    .inDays;

int _lastDayOf(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

Map<String, dynamic> _rec(String id, String recurrence,
        {String remindAt = '2025-01-06T09:00:00'}) =>
    {
      'id': id,
      'typeId': 'reminder',
      'text': id,
      'remindAt': remindAt,
      'createdAt': '2025-01-06T00:00:00',
      'recurrence': recurrence,
    };

void main() {
  test('host DST report (informational)', () {
    final hasDst = DateTime(2026, 3, 8).timeZoneOffset !=
        DateTime(2026, 11, 1).timeZoneOffset;
    // No assertion on hasDst: the sweep below is valid either way. This test
    // only documents whether this run doubled as a DST regression run.
    printOnFailure('host has DST: $hasDst');
    expect(true, isTrue);
  });

  test(
      'every rule variant keeps the requested wall-clock time and day shape for every day of 2025–2027',
      () {
    final store = <String, Map<String, dynamic>>{
      'r-daily': _rec('r-daily', 'daily'),
      'r-weekly': _rec('r-weekly', 'weekly:tuesday'),
      'r-biweekly': _rec('r-biweekly', 'biweekly:tuesday'),
      'r-m2sun': _rec('r-m2sun', 'monthly:2:sunday'),
      'r-mlastsun': _rec('r-mlastsun', 'monthly:-1:sunday'),
      'r-days': _rec('r-days', 'days:1,2,3,4,5'),
      'r-dom31': _rec('r-dom31', 'monthlyday:31'),
      'r-dom15': _rec('r-dom15', 'monthlyday:15'),
      'r-yearly': _rec('r-yearly', 'yearly', remindAt: '1990-03-03T09:00:00'),
    };
    // Phase anchor for biweekly:tuesday created Mon 2025-01-06 → Tue 2025-01-07.
    final anchor = DateTime(2025, 1, 7);

    for (var d = DateTime(2025, 1, 1);
        d.year < 2028;
        d = DateTime(d.year, d.month, d.day + 1)) {
      final now = DateTime(d.year, d.month, d.day, 12, 0); // noon, past 9am
      final at = {for (final r in allReminders(store, now)) r.ref: r.at};
      String why(String ref) => '$ref with now=$now gave ${at[ref]}';

      for (final ref in store.keys) {
        final occ = at[ref]!;
        expect(occ.isAfter(now), isTrue, reason: 'not after now: ${why(ref)}');
        expect(occ.hour, 9, reason: 'wall-clock hour drifted: ${why(ref)}');
        expect(occ.minute, 0, reason: 'wall-clock minute drifted: ${why(ref)}');
      }

      expect(_calDays(now, at['r-daily']!), 1, reason: why('r-daily'));

      expect(at['r-weekly']!.weekday, DateTime.tuesday, reason: why('r-weekly'));
      expect(_calDays(now, at['r-weekly']!), inInclusiveRange(1, 7),
          reason: why('r-weekly'));

      expect(at['r-biweekly']!.weekday, DateTime.tuesday,
          reason: why('r-biweekly'));
      expect(_calDays(anchor, at['r-biweekly']!) % 14, 0,
          reason: 'off the 14-day phase: ${why('r-biweekly')}');
      expect(_calDays(now, at['r-biweekly']!), inInclusiveRange(1, 14),
          reason: why('r-biweekly'));

      expect(at['r-m2sun']!.weekday, DateTime.sunday, reason: why('r-m2sun'));
      expect((at['r-m2sun']!.day - 1) ~/ 7, 1,
          reason: 'not the 2nd week: ${why('r-m2sun')}');

      expect(at['r-mlastsun']!.weekday, DateTime.sunday,
          reason: why('r-mlastsun'));
      expect(at['r-mlastsun']!.day + 7 > _lastDayOf(at['r-mlastsun']!), isTrue,
          reason: 'not the last one: ${why('r-mlastsun')}');

      expect(at['r-days']!.weekday, inInclusiveRange(1, 5),
          reason: why('r-days'));
      expect(_calDays(now, at['r-days']!), inInclusiveRange(1, 3),
          reason: why('r-days'));

      expect(at['r-dom31']!.day,
          31 <= _lastDayOf(at['r-dom31']!) ? 31 : _lastDayOf(at['r-dom31']!),
          reason: why('r-dom31'));
      expect(at['r-dom15']!.day, 15, reason: why('r-dom15'));

      expect(at['r-yearly']!.month, 3, reason: why('r-yearly'));
      expect(at['r-yearly']!.day, 3, reason: why('r-yearly'));
    }
  });

  test('monthlyday:31 clamps to short months, never skips (doc promise)', () {
    final store = <String, Map<String, dynamic>>{
      'r': _rec('r', 'monthlyday:31')
    };
    DateTime at(DateTime now) => allReminders(store, now).single.at;
    expect(at(DateTime(2026, 2, 10, 12)), DateTime(2026, 2, 28, 9)); // common Feb
    expect(at(DateTime(2028, 2, 10, 12)), DateTime(2028, 2, 29, 9)); // leap Feb
    expect(at(DateTime(2026, 4, 5, 12)), DateTime(2026, 4, 30, 9)); // April
    expect(at(DateTime(2026, 4, 30, 12)), DateTime(2026, 5, 31, 9),
        reason: "the 30th's 9am already passed → May 31, not another April day");
  });
}
