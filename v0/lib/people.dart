/// Plenara v0 — people-loop projections over the record store (Fable #3/#4).
/// Pure and derived (like the reminder projections), so on-open birthday nudges
/// are CI-tested deterministically with no UI.
library;

import 'dates.dart';

typedef _Store = Map<String, Map<String, dynamic>>;

/// On-open nudges for contacts whose birthday falls within [withinDays] (soonest
/// first) — "🎂 X's birthday is in N days". Derived from `contact` records, so it
/// updates the moment a birthday is set/changed. Emoji baked in: the caller shows
/// the string as-is (reminder nudges carry their own ⏰).
List<String> upcomingBirthdayNudges(_Store store, DateTime now, {int withinDays = 7}) {
  final hits = <MapEntry<int, String>>[];
  for (final c in store.values) {
    if (c['typeId'] != 'contact') continue;
    final b = DateTime.tryParse(c['birthday']?.toString() ?? '');
    if (b == null) continue;
    final days = daysUntilAnnual(b, now);
    if (days > withinDays) continue;
    final name = c['displayName']?.toString() ?? 'Someone';
    final when = days == 0 ? 'today' : (days == 1 ? 'tomorrow' : 'in $days days');
    hits.add(MapEntry(days, "🎂 $name's birthday is $when"));
  }
  hits.sort((a, b) => a.key.compareTo(b.key));
  return [for (final h in hits) h.value];
}
