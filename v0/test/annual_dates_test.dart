/// The shared annual-date authority (dates.dart) and its one Feb-29 rule:
/// a Feb-29 date is observed on Feb 28 in common years — never late for a
/// birthday. Reminders' yearly recurrence, the people nudges, and the planner
/// (see planner_test.dart) all route through the same functions, so the three
/// surfaces can never disagree again.
import 'package:plenara/dates.dart';
import 'package:plenara/people.dart';
import 'package:plenara/reminders.dart';
import 'package:test/test.dart';

void main() {
  final feb29 = DateTime(2024, 2, 29);

  group('Feb-29 rule: observed Feb 28 in common years', () {
    test('nextAnnual clamps in a common year (not Mar 1)', () {
      expect(nextAnnual(feb29, DateTime(2026, 2, 10)), DateTime(2026, 2, 28));
    });

    test('nextAnnual keeps Feb 29 in a leap year', () {
      expect(nextAnnual(feb29, DateTime(2028, 2, 10)), DateTime(2028, 2, 29));
    });

    test('nextAnnual on the observed day is today', () {
      expect(nextAnnual(feb29, DateTime(2026, 2, 28)), DateTime(2026, 2, 28));
    });

    test('nextAnnual after the observed day rolls to next year, still clamped',
        () {
      expect(nextAnnual(feb29, DateTime(2026, 3, 1)), DateTime(2027, 2, 28));
    });

    test('a Feb-29 yearly reminder fires Feb 28 in a common year', () {
      final store = <String, Map<String, dynamic>>{
        'r': {
          'id': 'r',
          'typeId': 'reminder',
          'text': 'anniversary',
          'remindAt': '2024-02-29T09:00:00',
          'recurrence': 'yearly',
        },
      };
      expect(allReminders(store, DateTime(2026, 2, 10, 12)).single.at,
          DateTime(2026, 2, 28, 9));
      expect(allReminders(store, DateTime(2028, 2, 10, 12)).single.at,
          DateTime(2028, 2, 29, 9), reason: 'leap year keeps the real day');
    });

    test('a Feb-29 birthday nudges on Feb 28 in a common year', () {
      final store = <String, Map<String, dynamic>>{
        'c': {
          'id': 'c',
          'typeId': 'contact',
          'displayName': 'Ada',
          'birthday': '2016-02-29',
        },
      };
      final nudges = upcomingBirthdayNudges(store, DateTime(2026, 2, 27, 9));
      expect(nudges.single, contains('tomorrow'));
    });
  });

  group('calendar-day windows are DST-immune', () {
    test('daysUntilAnnual across the spring-forward night is 1, not 0', () {
      // 2026-03-08 02:00 is the US spring-forward instant; the night is 23h.
      expect(daysUntilAnnual(DateTime(2000, 3, 8), DateTime(2026, 3, 7, 12)), 1);
    });

    test('a 2-day window spanning the transition is 2, not 1', () {
      // Mar 7 → Mar 9 spans the 23h night: 47 elapsed hours, but exactly 2
      // calendar days. `.difference().inDays` truncated this to 1.
      expect(daysUntilAnnual(DateTime(2000, 3, 9), DateTime(2026, 3, 7, 12)), 2);
    });

    test('daysUntilAnnual across the fall-back night', () {
      expect(
          daysUntilAnnual(DateTime(2000, 11, 3), DateTime(2026, 10, 31, 12)), 3);
    });

    test('daysUntilAnnual today is 0', () {
      expect(daysUntilAnnual(DateTime(2000, 7, 6), DateTime(2026, 7, 6, 15)), 0);
    });
  });
}
