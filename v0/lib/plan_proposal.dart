/// Durable, inspectable weekly planning proposals. Preview creation is pure
/// with respect to user records; apply revalidates each captured planning
/// fingerprint before one ExecutionCoordinator mutation is allowed to begin.
library;

import 'dart:convert';
import 'dart:io';

import 'planner.dart';
import 'store.dart' show writeJsonAtomic;

enum PlanProposalState { draft, applied, dismissed, stale }

class PlanProposalItem {
  final String taskId;
  final String title;
  final String baseFingerprint;
  final DateTime proposedStartAt;
  final int estimatedMinutes;
  final String rationale;
  final bool selected;

  const PlanProposalItem({
    required this.taskId,
    required this.title,
    required this.baseFingerprint,
    required this.proposedStartAt,
    required this.estimatedMinutes,
    required this.rationale,
    this.selected = true,
  });

  PlanProposalItem copyWith({
    DateTime? proposedStartAt,
    int? estimatedMinutes,
    bool? selected,
  }) =>
      PlanProposalItem(
        taskId: taskId,
        title: title,
        baseFingerprint: baseFingerprint,
        proposedStartAt: proposedStartAt ?? this.proposedStartAt,
        estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
        rationale: rationale,
        selected: selected ?? this.selected,
      );

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'title': title,
        'baseFingerprint': baseFingerprint,
        'proposedStartAt': proposedStartAt.toIso8601String(),
        'estimatedMinutes': estimatedMinutes,
        'rationale': rationale,
        'selected': selected,
      };

  static PlanProposalItem fromJson(Map<String, dynamic> raw) =>
      PlanProposalItem(
        taskId: raw['taskId'] as String,
        title: raw['title'] as String,
        baseFingerprint: raw['baseFingerprint'] as String,
        proposedStartAt: DateTime.parse(raw['proposedStartAt'] as String),
        estimatedMinutes: raw['estimatedMinutes'] as int,
        rationale: raw['rationale'] as String,
        selected: raw['selected'] as bool? ?? true,
      );
}

class PlanProposal {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final PlanProposalState state;
  final List<PlanProposalItem> items;
  final int scheduledMinutes;
  final int conflictsBefore;
  final int conflictsAfter;
  final List<String> omissions;
  final String? message;

  const PlanProposal({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.state,
    required this.items,
    required this.scheduledMinutes,
    required this.conflictsBefore,
    required this.conflictsAfter,
    this.omissions = const [],
    this.message,
  });

  PlanProposal copyWith({
    DateTime? updatedAt,
    PlanProposalState? state,
    List<PlanProposalItem>? items,
    int? scheduledMinutes,
    int? conflictsAfter,
    String? message,
  }) =>
      PlanProposal(
        id: id,
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        state: state ?? this.state,
        items: items ?? this.items,
        scheduledMinutes: scheduledMinutes ?? this.scheduledMinutes,
        conflictsBefore: conflictsBefore,
        conflictsAfter: conflictsAfter ?? this.conflictsAfter,
        omissions: omissions,
        message: message ?? this.message,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'state': state.name,
        'items': items.map((item) => item.toJson()).toList(),
        'scheduledMinutes': scheduledMinutes,
        'conflictsBefore': conflictsBefore,
        'conflictsAfter': conflictsAfter,
        'omissions': omissions,
        if (message != null) 'message': message,
      };

  static PlanProposal fromJson(Map<String, dynamic> raw) => PlanProposal(
        id: raw['id'] as String,
        title: raw['title'] as String,
        createdAt: DateTime.parse(raw['createdAt'] as String),
        updatedAt: DateTime.parse(raw['updatedAt'] as String),
        state: PlanProposalState.values.byName(raw['state'] as String),
        items: (raw['items'] as List)
            .map((item) => PlanProposalItem.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList(growable: false),
        scheduledMinutes: raw['scheduledMinutes'] as int,
        conflictsBefore: raw['conflictsBefore'] as int,
        conflictsAfter: raw['conflictsAfter'] as int,
        omissions: (raw['omissions'] as List? ?? const []).cast<String>(),
        message: raw['message'] as String?,
      );
}

String taskPlanFingerprint(Map<String, dynamic> record) => jsonEncode({
      'id': record['id'],
      'completed': record['completed'],
      'status': record['status'],
      'scheduledStartAt': record['scheduledStartAt'],
      'estimatedMinutes': record['estimatedMinutes'],
      'dueAt': record['dueAt'],
      'priority': record['priority'],
      'dependencyRefs': record['dependencyRefs'],
      'blockedReason': record['blockedReason'],
    });

PlanProposal buildWeeklyPlanProposal(
  Map<String, Map<String, dynamic>> records,
  DateTime now, {
  int dailyCapacityMinutes = 8 * 60,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final existing = buildPlanProjection(
    records,
    now,
    selectedDay: today,
    dailyCapacityMinutes: dailyCapacityMinutes,
  );
  final used = <DateTime, int>{
    for (final day in existing.days) day.day: day.scheduledMinutes,
  };
  final omissions = <String>[];
  final candidates = records.values.where((record) {
    if (record['typeId'] != 'task' ||
        record['completed'] == true ||
        record['status'] == 'done' ||
        record['scheduledStartAt'] != null) {
      return false;
    }
    final dependencies = (record['dependencyRefs'] as List? ?? const []);
    final unmet = dependencies.any((id) {
      final dependency = records['$id'];
      return dependency == null ||
          (dependency['completed'] != true && dependency['status'] != 'done');
    });
    final title = '${record['description'] ?? 'Untitled task'}';
    if (unmet) {
      omissions.add('$title was left out because a dependency is unfinished.');
      return false;
    }
    final blockedReason = '${record['blockedReason'] ?? ''}'.trim();
    if (blockedReason.isNotEmpty) {
      omissions
          .add('$title was left out because it is blocked: $blockedReason');
      return false;
    }
    return true;
  }).toList()
    ..sort((left, right) {
      final leftDue = DateTime.tryParse('${left['dueAt'] ?? ''}');
      final rightDue = DateTime.tryParse('${right['dueAt'] ?? ''}');
      if (leftDue != null || rightDue != null) {
        if (leftDue == null) return 1;
        if (rightDue == null) return -1;
        final due = leftDue.compareTo(rightDue);
        if (due != 0) return due;
      }
      const rank = {'high': 0, 'medium': 1, 'low': 2, 'none': 3};
      final priority = (rank['${left['priority'] ?? 'none'}'] ?? 3)
          .compareTo(rank['${right['priority'] ?? 'none'}'] ?? 3);
      if (priority != 0) return priority;
      final leftRelationship = taskRelationshipNames(left, records).isNotEmpty;
      final rightRelationship =
          taskRelationshipNames(right, records).isNotEmpty;
      if (leftRelationship != rightRelationship) {
        return leftRelationship ? -1 : 1;
      }
      return '${left['description'] ?? ''}'
          .compareTo('${right['description'] ?? ''}');
    });

  final items = <PlanProposalItem>[];
  for (final task in candidates) {
    final estimate = (task['estimatedMinutes'] as num?)?.round() ?? 30;
    final due = DateTime.tryParse('${task['dueAt'] ?? ''}');
    DateTime? chosenDay;
    for (var offset = 0; offset < 7; offset++) {
      final day = monday.add(Duration(days: offset));
      if (day.isBefore(today)) continue;
      if (due != null && !due.isBefore(today) && day.isAfter(due)) break;
      if ((used[day] ?? 0) + estimate <= dailyCapacityMinutes) {
        chosenDay = day;
        break;
      }
    }
    if (chosenDay == null) {
      omissions.add(
        '${task['description'] ?? 'Untitled task'} was left unscheduled because '
        '${due == null ? 'this week has no remaining capacity' : 'there is no capacity before its ${_dateLabel(due)} deadline'}.',
      );
      continue;
    }
    final start = DateTime(
      chosenDay.year,
      chosenDay.month,
      chosenDay.day,
      9,
    ).add(Duration(minutes: used[chosenDay] ?? 0));
    used[chosenDay] = (used[chosenDay] ?? 0) + estimate;
    final relationshipNames = taskRelationshipNames(task, records);
    items.add(PlanProposalItem(
      taskId: '${task['id']}',
      title: '${task['description'] ?? 'Untitled task'}',
      baseFingerprint: taskPlanFingerprint(task),
      proposedStartAt: start,
      estimatedMinutes: estimate,
      rationale: due != null
          ? due.isBefore(today)
              ? 'Deadline passed; placed in the earliest available capacity.'
              : 'Placed before the ${_dateLabel(due)} deadline.'
          : task['priority'] == 'high'
              ? 'High priority, placed in the earliest available capacity.'
              : relationshipNames.isNotEmpty
                  ? 'A commitment to ${relationshipNames.join(', ')}, placed before generic queue work.'
                  : 'Unscheduled work, placed in the earliest available capacity.',
    ));
  }

  final projected = {
    for (final entry in records.entries)
      entry.key: Map<String, dynamic>.from(entry.value),
  };
  for (final item in items) {
    projected[item.taskId]!
      ..['scheduledStartAt'] = item.proposedStartAt.toIso8601String()
      ..['estimatedMinutes'] = item.estimatedMinutes
      ..['status'] = 'scheduled';
  }
  final after = buildPlanProjection(
    projected,
    now,
    selectedDay: today,
    dailyCapacityMinutes: dailyCapacityMinutes,
  );
  final created = now;
  return PlanProposal(
    id: 'proposal-${created.microsecondsSinceEpoch}',
    title: 'Plan this week',
    createdAt: created,
    updatedAt: created,
    state: PlanProposalState.draft,
    items: List.unmodifiable(items),
    scheduledMinutes: items.fold(0, (sum, item) => sum + item.estimatedMinutes),
    conflictsBefore: existing.conflicts.length,
    conflictsAfter: after.conflicts.length,
    omissions: List.unmodifiable(omissions),
  );
}

String _dateLabel(DateTime value) =>
    '${value.month}/${value.day}/${value.year}';

class PlanProposalStore {
  final String? path;
  final List<String> issues = [];
  PlanProposal? _active;

  PlanProposalStore({this.path}) {
    if (path == null) return;
    final file = File(path!);
    if (!file.existsSync()) return;
    try {
      _active = PlanProposal.fromJson(
        Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map),
      );
    } catch (error) {
      issues.add('Planning proposal could not be read: $error');
    }
  }

  PlanProposal? get active => _active;

  void save(PlanProposal proposal) {
    _active = proposal;
    if (path == null) return;
    final file = File(path!);
    file.parent.createSync(recursive: true);
    writeJsonAtomic(file, proposal.toJson());
  }
}
