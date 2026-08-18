import 'package:plenara/cron.dart';
import 'package:test/test.dart';

DateTime _dt(String s) => DateTime.parse(s);
// Reference: 2026-07-06 is a Monday -> 07-11 Sat, 07-12 Sun, 07-13 Mon.

void main() {
  group('cronMatches', () {
    test('daily 9:00', () {
      expect(cronMatches('0 9 * * *', _dt('2026-07-08T09:00:00')), isTrue);
      expect(cronMatches('0 9 * * *', _dt('2026-07-08T09:01:00')), isFalse);
      expect(cronMatches('0 9 * * *', _dt('2026-07-08T10:00:00')), isFalse);
    });
    test('Sunday 20:00 accepts dow 0 and 7; rejects Monday', () {
      expect(cronMatches('0 20 * * 0', _dt('2026-07-12T20:00:00')), isTrue);
      expect(cronMatches('0 20 * * 7', _dt('2026-07-12T20:00:00')), isTrue);
      expect(cronMatches('0 20 * * 0', _dt('2026-07-13T20:00:00')), isFalse);
    });
    test('weekdays 8:00 (1-5)', () {
      expect(cronMatches('0 8 * * 1-5', _dt('2026-07-08T08:00:00')), isTrue); // Wed
      expect(cronMatches('0 8 * * 1-5', _dt('2026-07-11T08:00:00')), isFalse); // Sat
    });
    test('every 15 minutes (*/15)', () {
      expect(cronMatches('*/15 * * * *', _dt('2026-07-08T09:15:00')), isTrue);
      expect(cronMatches('*/15 * * * *', _dt('2026-07-08T09:16:00')), isFalse);
    });
    test('list of hours (9,17)', () {
      expect(cronMatches('0 9,17 * * *', _dt('2026-07-08T17:00:00')), isTrue);
      expect(cronMatches('0 9,17 * * *', _dt('2026-07-08T12:00:00')), isFalse);
    });
    test('malformed field count throws', () {
      expect(() => cronMatches('0 9 * *', _dt('2026-07-08T09:00:00')), throwsFormatException);
    });
  });

  group('strict parsing — reject what the evaluator cannot honor (no silent never-fire)', () {
    final t = _dt('2026-07-13T09:00:00'); // a Monday
    test('weekday names are rejected, not silently unmatched', () {
      expect(() => cronMatches('0 9 * * MON', t), throwsFormatException);
    });
    test('steps on ranges are rejected', () {
      expect(() => cronMatches('0 9 * * 1-5/2', t), throwsFormatException);
    });
    test('out-of-range values are rejected', () {
      expect(() => cronMatches('61 * * * *', t), throwsFormatException);
      expect(() => cronMatches('0 25 * * *', t), throwsFormatException);
      expect(() => cronMatches('0 9 32 * *', t), throwsFormatException);
      expect(() => cronMatches('0 9 * 13 *', t), throwsFormatException);
      expect(() => cronMatches('0 9 * * 8', t), throwsFormatException);
      expect(() => cronMatches('0 9 * * x', t), throwsFormatException);
    });
    test('supported grammar still parses', () {
      expect(cronMatches('*/15 0-6 1,15 * 0', _dt('2026-11-01T06:45:00')), isTrue); // Sun the 1st
    });
  });

  group('DOM+DOW are AND (deliberate deviation from standard cron OR)', () {
    test('fires only when both the day-of-month and the weekday match', () {
      // 0 9 13 * 5 = "9am on Friday the 13th" under AND semantics.
      expect(cronMatches('0 9 13 * 5', _dt('2026-02-13T09:00:00')), isTrue); // Fri the 13th
      expect(cronMatches('0 9 13 * 5', _dt('2026-07-13T09:00:00')), isFalse); // Mon the 13th
      expect(cronMatches('0 9 13 * 5', _dt('2026-02-06T09:00:00')), isFalse); // a Friday, not the 13th
    });
  });

  group('nextFire / dueSince', () {
    test('next daily 9am after 10am today = 9am tomorrow', () {
      expect(nextFire('0 9 * * *', _dt('2026-07-08T10:00:00')), _dt('2026-07-09T09:00:00'));
    });
    test('next Sunday 8pm from a Wednesday', () {
      expect(nextFire('0 20 * * 0', _dt('2026-07-08T12:00:00')), _dt('2026-07-12T20:00:00'));
    });
    test('dueSince fires once when a cron time passed in the window (catch-up on open)', () {
      expect(dueSince('0 20 * * 0', _dt('2026-07-11T09:00:00'), _dt('2026-07-13T09:00:00')),
          _dt('2026-07-12T20:00:00'));
    });
    test('dueSince null when no cron time fell in the window', () {
      expect(dueSince('0 20 * * 0', _dt('2026-07-08T09:00:00'), _dt('2026-07-09T09:00:00')), isNull);
    });
    test('a yearly cron resolves months ahead (day-granularity jump, not 527k minutes)', () {
      expect(nextFire('0 9 25 12 *', _dt('2026-07-08T10:00:00')), _dt('2026-12-25T09:00:00'));
    });
    test('nextFire null when nothing fires inside the bound', () {
      // Feb 30 never exists; the scan must terminate at the maxDays bound.
      expect(nextFire('0 9 30 2 *', _dt('2026-07-08T10:00:00')), isNull);
    });
    test('nextFire later the same day starts from the next whole minute', () {
      expect(nextFire('*/15 * * * *', _dt('2026-07-08T09:15:10')), _dt('2026-07-08T09:30:00'));
    });
  });
}
