/// Plenara v0 — people-loop projections over the record store (Fable #3/#4).
/// Pure and derived (like the reminder projections), so on-open birthday nudges
/// are CI-tested deterministically with no UI.
library;

import 'dates.dart';

typedef _Store = Map<String, Map<String, dynamic>>;

/// Legacy v2 relationship rhythms. Kept only so existing records retain their
/// exact 7/21/60-day behavior until the user assigns a v3 circle.
enum RelationshipGoal { none, close, connected, light }

/// The one closeness/intention axis that drives inherited relationship goals.
/// Role, proximity, and lifecycle remain independent contact attributes.
enum RelationshipCircle { core, close, connected, warm, context }

enum RelationshipEngagement { active, seasonal, paused, archived }

enum ConnectionDepth { quick, meaningful }

enum RelationshipNeed { none, touch, meaningful }

/// Human shortcuts shown by UI and understood by voice. They resolve to the
/// normalized circle + descriptors below; the preset name is not stored.
enum RelationshipPreset {
  closeFamily,
  closeLocalFriend,
  closeRemoteFriend,
  connectedFriend,
  oldRemoteFriend,
  neighbor,
  community,
  secondDegree,
  household,
  contextOnly,
}

const relationshipCircleTouchDays = <RelationshipCircle, int?>{
  RelationshipCircle.core: 7,
  RelationshipCircle.close: 14,
  RelationshipCircle.connected: 30,
  RelationshipCircle.warm: 90,
  RelationshipCircle.context: null,
};

const relationshipCircleMeaningfulDays = <RelationshipCircle, int?>{
  RelationshipCircle.core: 14,
  RelationshipCircle.close: 30,
  RelationshipCircle.connected: 60,
  RelationshipCircle.warm: null,
  RelationshipCircle.context: null,
};

String relationshipCircleLabel(RelationshipCircle circle) => switch (circle) {
      RelationshipCircle.core => 'Core',
      RelationshipCircle.close => 'Close',
      RelationshipCircle.connected => 'Keep connected',
      RelationshipCircle.warm => 'Keep warm',
      RelationshipCircle.context => 'Context only',
    };

String relationshipPresetLabel(RelationshipPreset preset) => switch (preset) {
      RelationshipPreset.closeFamily => 'Close family',
      RelationshipPreset.closeLocalFriend => 'Close local friend',
      RelationshipPreset.closeRemoteFriend => 'Close remote friend',
      RelationshipPreset.connectedFriend => 'Friend to keep connected',
      RelationshipPreset.oldRemoteFriend => 'Old remote friend',
      RelationshipPreset.neighbor => 'Neighbor',
      RelationshipPreset.community => 'Local community',
      RelationshipPreset.secondDegree => 'Second-degree connection',
      RelationshipPreset.household => 'Household',
      RelationshipPreset.contextOnly => 'Context only',
    };

/// One rule-home for what assigning a category changes. Null values deliberately
/// clear per-person overrides and v2 compatibility fields so circle inheritance
/// becomes authoritative after assignment.
Map<String, Object?> relationshipPresetFields(RelationshipPreset preset) {
  final (circle, roles, proximity, touch, meaningful) = switch (preset) {
    RelationshipPreset.closeFamily => (
        RelationshipCircle.core,
        const ['Family'],
        'unknown',
        true,
        true
      ),
    RelationshipPreset.closeLocalFriend => (
        RelationshipCircle.close,
        const ['Friend'],
        'local',
        true,
        true
      ),
    RelationshipPreset.closeRemoteFriend => (
        RelationshipCircle.close,
        const ['Friend'],
        'remote',
        true,
        true
      ),
    RelationshipPreset.connectedFriend => (
        RelationshipCircle.connected,
        const ['Friend'],
        'unknown',
        true,
        true
      ),
    RelationshipPreset.oldRemoteFriend => (
        RelationshipCircle.warm,
        const ['Friend'],
        'remote',
        true,
        false
      ),
    RelationshipPreset.neighbor => (
        RelationshipCircle.context,
        const ['Neighbor'],
        'local',
        false,
        false
      ),
    RelationshipPreset.community => (
        RelationshipCircle.context,
        const ['Community'],
        'local',
        false,
        false
      ),
    RelationshipPreset.secondDegree => (
        RelationshipCircle.context,
        const ['Second-degree'],
        'unknown',
        false,
        false
      ),
    RelationshipPreset.household => (
        RelationshipCircle.core,
        const ['Family'],
        'household',
        false,
        false
      ),
    RelationshipPreset.contextOnly => (
        RelationshipCircle.context,
        const <String>[],
        'unknown',
        false,
        false
      ),
  };
  return {
    'relationshipCircle': circle.name,
    'relationshipRoles': roles,
    'proximity': proximity,
    'relationshipStatus': RelationshipEngagement.active.name,
    'trackTouch': touch,
    'trackMeaningful': meaningful,
    'touchFrequencyDays': null,
    'meaningfulFrequencyDays': null,
    'relationshipGoal': null,
    'contactFrequencyDays': null,
  };
}

Map<String, Object?> relationshipCircleFields(RelationshipCircle circle) => {
      'relationshipCircle': circle.name,
      'relationshipStatus': RelationshipEngagement.active.name,
      'trackTouch': relationshipCircleTouchDays[circle] != null,
      'trackMeaningful': relationshipCircleMeaningfulDays[circle] != null,
      'touchFrequencyDays': null,
      'meaningfulFrequencyDays': null,
      'relationshipGoal': null,
      'contactFrequencyDays': null,
    };

enum RelationshipHealth { untracked, noHistory, onTrack, dueSoon, due, overdue }

class RelationshipStatus {
  final String contactId;
  final String displayName;
  final RelationshipGoal goal;
  final RelationshipCircle circle;
  final RelationshipEngagement engagement;
  final String proximity;
  final int? touchTargetDays;
  final int? meaningfulTargetDays;
  final DateTime? lastTouchAt;
  final DateTime? lastMeaningfulAt;
  final String? lastTouchMedium;
  final String? lastMeaningfulMedium;
  final DateTime? nextTouchAt;
  final DateTime? nextMeaningfulAt;
  final RelationshipHealth touchHealth;
  final RelationshipHealth meaningfulHealth;
  final RelationshipNeed need;
  final RelationshipHealth health;
  final int urgencyDays;

  const RelationshipStatus({
    required this.contactId,
    required this.displayName,
    required this.goal,
    required this.circle,
    required this.engagement,
    required this.proximity,
    required this.touchTargetDays,
    required this.meaningfulTargetDays,
    required this.lastTouchAt,
    required this.lastMeaningfulAt,
    required this.lastTouchMedium,
    required this.lastMeaningfulMedium,
    required this.nextTouchAt,
    required this.nextMeaningfulAt,
    required this.touchHealth,
    required this.meaningfulHealth,
    required this.need,
    required this.health,
    required this.urgencyDays,
  });

  // Compatibility names for callers that only need the latest touch clock.
  int? get targetDays => touchTargetDays;
  DateTime? get lastInteractionAt => lastTouchAt;
  String? get lastMedium => lastTouchMedium;
  DateTime? get nextContactAt => nextTouchAt;

  bool get needsContact =>
      health == RelationshipHealth.noHistory ||
      health == RelationshipHealth.due ||
      health == RelationshipHealth.overdue;
}

RelationshipCircle relationshipCircleOf(Map<String, dynamic> contact) {
  final explicit = RelationshipCircle.values
      .where(
          (circle) => circle.name == '${contact['relationshipCircle'] ?? ''}')
      .firstOrNull;
  if (explicit != null) return explicit;
  return switch ('${contact['relationshipGoal'] ?? 'none'}') {
    'close' => RelationshipCircle.core,
    'connected' => RelationshipCircle.close,
    'light' => RelationshipCircle.warm,
    _ => RelationshipCircle.context,
  };
}

RelationshipEngagement relationshipEngagementOf(Map<String, dynamic> contact) =>
    RelationshipEngagement.values.firstWhere(
      (value) => value.name == '${contact['relationshipStatus'] ?? 'active'}',
      orElse: () => RelationshipEngagement.active,
    );

int? _positiveDays(Object? value) {
  final days = num.tryParse('${value ?? ''}')?.round();
  return days != null && days > 0 ? days : null;
}

int? relationshipTouchTargetDays(Map<String, dynamic> contact) {
  if (relationshipEngagementOf(contact) != RelationshipEngagement.active ||
      contact['trackTouch'] == false) {
    return null;
  }
  final exact = _positiveDays(contact['touchFrequencyDays']);
  if (exact != null) return exact;
  // A v2 record keeps the exact old rhythm until a new circle is assigned.
  if (!contact.containsKey('relationshipCircle')) {
    final legacyExact = _positiveDays(contact['contactFrequencyDays']);
    if (legacyExact != null) return legacyExact;
    return switch ('${contact['relationshipGoal'] ?? 'none'}') {
      'close' => 7,
      'connected' => 21,
      'light' => 60,
      _ => null,
    };
  }
  return relationshipCircleTouchDays[relationshipCircleOf(contact)];
}

int? relationshipMeaningfulTargetDays(Map<String, dynamic> contact) {
  if (relationshipEngagementOf(contact) != RelationshipEngagement.active ||
      contact['trackMeaningful'] == false) {
    return null;
  }
  final exact = _positiveDays(contact['meaningfulFrequencyDays']);
  if (exact != null) return exact;
  // Do not make migrated users newly overdue on a clock they never chose.
  if (!contact.containsKey('relationshipCircle')) return null;
  return relationshipCircleMeaningfulDays[relationshipCircleOf(contact)];
}

int? relationshipTargetDays(Map<String, dynamic> contact) =>
    relationshipTouchTargetDays(contact);

RelationshipGoal _goalOf(Map<String, dynamic> contact) =>
    RelationshipGoal.values.firstWhere(
      (goal) => goal.name == '${contact['relationshipGoal'] ?? 'none'}',
      orElse: () => RelationshipGoal.none,
    );

ConnectionDepth connectionDepthOf(Map<String, dynamic> interaction) {
  if (interaction['connectionDepth'] == 'meaningful') {
    return ConnectionDepth.meaningful;
  }
  if (interaction['connectionDepth'] == 'quick') return ConnectionDepth.quick;
  return const {'in_person', 'facetime', 'phone'}
          .contains('${interaction['medium'] ?? ''}')
      ? ConnectionDepth.meaningful
      : ConnectionDepth.quick;
}

RelationshipHealth _clockHealth(int? target, DateTime? last, DateTime today) {
  if (target == null) return RelationshipHealth.untracked;
  if (last == null) return RelationshipHealth.noHistory;
  final next = DateTime(last.year, last.month, last.day + target);
  final remaining = next.difference(today).inDays;
  if (remaining < 0) return RelationshipHealth.overdue;
  if (remaining == 0) return RelationshipHealth.due;
  if (remaining <= (target / 4).ceil().clamp(1, 7)) {
    return RelationshipHealth.dueSoon;
  }
  return RelationshipHealth.onTrack;
}

bool _needs(RelationshipHealth health) =>
    health == RelationshipHealth.noHistory ||
    health == RelationshipHealth.due ||
    health == RelationshipHealth.overdue;

int _remaining(int? target, DateTime? last, DateTime today) {
  if (target == null) return 1 << 20;
  if (last == null) return -100000;
  return DateTime(last.year, last.month, last.day + target)
      .difference(today)
      .inDays;
}

/// One deterministic relationship-health projection used by People, Today,
/// and planning signals. Only completed interactions count: a plan or a call
/// button tap is not evidence that two people actually connected.
List<RelationshipStatus> relationshipStatuses(_Store store, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final latest = <String, Map<String, dynamic>>{};
  final latestMeaningful = <String, Map<String, dynamic>>{};
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
    if (connectionDepthOf(interaction) == ConnectionDepth.meaningful) {
      final meaningfulPrior = latestMeaningful[subject];
      final meaningfulPriorAt =
          DateTime.tryParse('${meaningfulPrior?['at'] ?? ''}');
      if (meaningfulPriorAt == null || at.isAfter(meaningfulPriorAt)) {
        latestMeaningful[subject] = interaction;
      }
    }
  }

  final statuses = <RelationshipStatus>[];
  for (final contact in store.values.where((r) => r['typeId'] == 'contact')) {
    final touchTarget = relationshipTouchTargetDays(contact);
    final meaningfulTarget = relationshipMeaningfulTargetDays(contact);
    final interaction = latest['${contact['id']}'];
    final meaningfulInteraction = latestMeaningful['${contact['id']}'];
    final lastTouch = DateTime.tryParse('${interaction?['at'] ?? ''}');
    final lastMeaningful =
        DateTime.tryParse('${meaningfulInteraction?['at'] ?? ''}');
    final nextTouch = touchTarget == null || lastTouch == null
        ? null
        : DateTime(
            lastTouch.year, lastTouch.month, lastTouch.day + touchTarget);
    final nextMeaningful = meaningfulTarget == null || lastMeaningful == null
        ? null
        : DateTime(lastMeaningful.year, lastMeaningful.month,
            lastMeaningful.day + meaningfulTarget);
    final touchHealth = _clockHealth(touchTarget, lastTouch, today);
    final meaningfulHealth =
        _clockHealth(meaningfulTarget, lastMeaningful, today);
    final touchRemaining = _remaining(touchTarget, lastTouch, today);
    final meaningfulRemaining =
        _remaining(meaningfulTarget, lastMeaningful, today);
    final meaningfulNeeds = _needs(meaningfulHealth);
    final touchNeeds = _needs(touchHealth);
    final need = meaningfulNeeds && meaningfulRemaining <= touchRemaining
        ? RelationshipNeed.meaningful
        : touchNeeds
            ? RelationshipNeed.touch
            : meaningfulNeeds
                ? RelationshipNeed.meaningful
                : RelationshipNeed.none;
    final health = switch (need) {
      RelationshipNeed.meaningful => meaningfulHealth,
      RelationshipNeed.touch => touchHealth,
      RelationshipNeed.none
          when meaningfulHealth != RelationshipHealth.untracked =>
        meaningfulHealth,
      _ => touchHealth,
    };
    statuses.add(RelationshipStatus(
      contactId: '${contact['id']}',
      displayName: '${contact['displayName'] ?? 'Someone'}',
      goal: _goalOf(contact),
      circle: relationshipCircleOf(contact),
      engagement: relationshipEngagementOf(contact),
      proximity: '${contact['proximity'] ?? 'unknown'}',
      touchTargetDays: touchTarget,
      meaningfulTargetDays: meaningfulTarget,
      lastTouchAt: lastTouch,
      lastMeaningfulAt: lastMeaningful,
      lastTouchMedium: interaction?['medium']?.toString() ??
          interaction?['kind']?.toString(),
      lastMeaningfulMedium: meaningfulInteraction?['medium']?.toString() ??
          meaningfulInteraction?['kind']?.toString(),
      nextTouchAt: nextTouch,
      nextMeaningfulAt: nextMeaningful,
      touchHealth: touchHealth,
      meaningfulHealth: meaningfulHealth,
      need: need,
      health: health,
      urgencyDays: touchRemaining < meaningfulRemaining
          ? touchRemaining
          : meaningfulRemaining,
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
