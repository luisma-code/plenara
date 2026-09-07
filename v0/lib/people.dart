/// Plenara v0 — people-loop projections over the record store (Fable #3/#4).
/// Pure and derived (like the reminder projections), so on-open birthday nudges
/// are CI-tested deterministically with no UI.
library;

import 'dates.dart';

typedef _Store = Map<String, Map<String, dynamic>>;

/// The relationship rhythm a person is meant to have in the user's life. The
/// stored enum is deliberately small and human-facing; [contactFrequencyDays]
/// remains the precise override when a preset is not quite right.
enum RelationshipGoal { none, close, connected, light }

enum RelationshipHealth { untracked, noHistory, onTrack, dueSoon, due, overdue }

class RelationshipStatus {
  final String contactId;
  final String displayName;
  final RelationshipGoal goal;
  final int? targetDays;
  final DateTime? lastInteractionAt;
  final String? lastMedium;
  final DateTime? nextContactAt;
  final RelationshipHealth health;
  final int urgencyDays;

  const RelationshipStatus({
    required this.contactId,
    required this.displayName,
    required this.goal,
    required this.targetDays,
    required this.lastInteractionAt,
    required this.lastMedium,
    required this.nextContactAt,
    required this.health,
    required this.urgencyDays,
  });

  bool get needsContact =>
      health == RelationshipHealth.noHistory ||
      health == RelationshipHealth.due ||
      health == RelationshipHealth.overdue;
}

int? relationshipTargetDays(Map<String, dynamic> contact) {
  final exact =
      num.tryParse('${contact['contactFrequencyDays'] ?? ''}')?.round();
  if (exact != null && exact > 0) return exact;
  return switch ('${contact['relationshipGoal'] ?? 'none'}') {
    'close' => 7,
    'connected' => 21,
    'light' => 60,
    _ => null,
  };
}

RelationshipGoal _goalOf(Map<String, dynamic> contact) =>
    RelationshipGoal.values.firstWhere(
      (goal) => goal.name == '${contact['relationshipGoal'] ?? 'none'}',
      orElse: () => RelationshipGoal.none,
    );

/// One deterministic relationship-health projection used by People, Today,
/// and planning signals. Only completed interactions count: a plan or a call
/// button tap is not evidence that two people actually connected.
List<RelationshipStatus> relationshipStatuses(_Store store, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final latest = <String, Map<String, dynamic>>{};
  for (final interaction in store.values) {
    if (interaction['typeId'] != 'interaction' ||
        interaction['planned'] == true) {
      continue;
    }
    final subject = '${interaction['subject'] ?? ''}';
    final at = DateTime.tryParse('${interaction['at'] ?? ''}');
    if (subject.isEmpty || at == null || at.isAfter(now)) continue;
    final prior = latest[subject];
    final priorAt = DateTime.tryParse('${prior?['at'] ?? ''}');
    if (priorAt == null || at.isAfter(priorAt)) latest[subject] = interaction;
  }

  final statuses = <RelationshipStatus>[];
  for (final contact in store.values.where((r) => r['typeId'] == 'contact')) {
    final target = relationshipTargetDays(contact);
    final interaction = latest['${contact['id']}'];
    final last = DateTime.tryParse('${interaction?['at'] ?? ''}');
    final next = target == null || last == null
        ? null
        : DateTime(last.year, last.month, last.day + target);
    final remaining = next == null ? 0 : next.difference(today).inDays;
    final health = target == null
        ? RelationshipHealth.untracked
        : last == null
            ? RelationshipHealth.noHistory
            : remaining < 0
                ? RelationshipHealth.overdue
                : remaining == 0
                    ? RelationshipHealth.due
                    : remaining <= (target / 4).ceil().clamp(1, 7)
                        ? RelationshipHealth.dueSoon
                        : RelationshipHealth.onTrack;
    statuses.add(RelationshipStatus(
      contactId: '${contact['id']}',
      displayName: '${contact['displayName'] ?? 'Someone'}',
      goal: _goalOf(contact),
      targetDays: target,
      lastInteractionAt: last,
      lastMedium: interaction?['medium']?.toString() ??
          interaction?['kind']?.toString(),
      nextContactAt: next,
      health: health,
      // Smaller sorts first. Never-contacted tracked people are the most urgent.
      urgencyDays:
          target == null ? 1 << 20 : (last == null ? -100000 : remaining),
    ));
  }
  statuses.sort((a, b) {
    final urgency = a.urgencyDays.compareTo(b.urgencyDays);
    if (urgency != 0) return urgency;
    final name = a.displayName.compareTo(b.displayName);
    return name != 0 ? name : a.contactId.compareTo(b.contactId);
  });
  return List.unmodifiable(statuses);
}

List<RelationshipStatus> suggestedContacts(_Store store, DateTime now,
        {int limit = 3}) =>
    relationshipStatuses(store, now)
        .where((status) => status.needsContact)
        .take(limit)
        .toList(growable: false);

/// On-open nudges for contacts whose birthday falls within [withinDays] (soonest
/// first) — "🎂 X's birthday is in N days". Derived from `contact` records, so it
/// updates the moment a birthday is set/changed. Emoji baked in: the caller shows
/// the string as-is (reminder nudges carry their own ⏰).
List<String> upcomingBirthdayNudges(_Store store, DateTime now,
    {int withinDays = 7}) {
  final hits = <MapEntry<int, String>>[];
  for (final c in store.values) {
    if (c['typeId'] != 'contact') continue;
    final b = DateTime.tryParse(c['birthday']?.toString() ?? '');
    if (b == null) continue;
    final days = daysUntilAnnual(b, now);
    if (days > withinDays) continue;
    final name = c['displayName']?.toString() ?? 'Someone';
    final when =
        days == 0 ? 'today' : (days == 1 ? 'tomorrow' : 'in $days days');
    hits.add(MapEntry(days, "🎂 $name's birthday is $when"));
  }
  hits.sort((a, b) => a.key.compareTo(b.key));
  return [for (final h in hits) h.value];
}
