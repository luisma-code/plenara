/// Purpose-built Today projection. It presents current truth across existing
/// record types without flattening reminders, routines, and relationship dates
/// into fake tasks.
library;

enum PlannerItemKind { task, reminder, routine, relationship }

class PlannerItem {
  final String id;
  final PlannerItemKind kind;
  final String title;
  final String? detail;
  final DateTime? at;
  final bool overdue;
  final bool completable;

  const PlannerItem({
    required this.id,
    required this.kind,
    required this.title,
    this.detail,
    this.at,
    this.overdue = false,
    this.completable = false,
  });
}

class PlannerChange {
  final int executionId;
  final String description;
  final String origin;
  final DateTime at;

  const PlannerChange({
    required this.executionId,
    required this.description,
    required this.origin,
    required this.at,
  });
}

class PlanTaskItem {
  final String id;
  final PlannerItemKind kind;
  final String title;
  final DateTime? scheduledStartAt;
  final DateTime? dueAt;
  final int? estimatedMinutes;
  final String priority;
  final String? energy;
  final List<String> contexts;
  final String? recurrence;
  final bool blocked;
  final String? blockedReason;

  const PlanTaskItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.scheduledStartAt,
    required this.dueAt,
    required this.estimatedMinutes,
    required this.priority,
    this.energy,
    this.contexts = const [],
    this.recurrence,
    required this.blocked,
    this.blockedReason,
  });
}

class PlanDaySummary {
  final DateTime day;
  final int scheduledMinutes;
  final int capacityMinutes;
  final int unknownEstimateCount;
  final int conflictCount;

  const PlanDaySummary({
    required this.day,
    required this.scheduledMinutes,
    required this.capacityMinutes,
    required this.unknownEstimateCount,
    required this.conflictCount,
  });

  bool get overloaded => scheduledMinutes > capacityMinutes;
}

class PlanConflict {
  final DateTime day;
  final List<String> recordIds;
  final String message;

  const PlanConflict({
    required this.day,
    required this.recordIds,
    required this.message,
  });
}

class PlanProjection {
  final DateTime selectedDay;
  final List<PlanDaySummary> days;
  final List<PlanTaskItem> agenda;
  final List<PlanTaskItem> deadlines;
  final List<PlanTaskItem> unscheduled;
  final List<PlanConflict> conflicts;

  const PlanProjection({
    required this.selectedDay,
    required this.days,
    required this.agenda,
    required this.deadlines,
    required this.unscheduled,
    required this.conflicts,
  });
}

class TaskPlanPatch {
  final String id;
  final DateTime? scheduledStartAt;
  final bool clearSchedule;
  final int? estimatedMinutes;
  final String? status;
  final String? description;
  final bool complete;

  const TaskPlanPatch({
    required this.id,
    this.scheduledStartAt,
    this.clearSchedule = false,
    this.estimatedMinutes,
    this.status,
    this.description,
    this.complete = false,
  });
}

class PlannerContext {
  final DateTime? visibleStart;
  final DateTime? visibleEnd;
  final DateTime? selectedDay;
  final List<String> selectedRecordIds;
  final List<String> visibleRecordIds;

  const PlannerContext({
    this.visibleStart,
    this.visibleEnd,
    this.selectedDay,
    this.selectedRecordIds = const [],
    this.visibleRecordIds = const [],
  });
}

class TodayProjection {
  final DateTime day;
  final List<PlannerItem> now;
  final List<PlannerItem> next;
  final List<PlannerItem> later;
  final PlannerItem? relationshipNudge;
  final PlannerChange? latestChange;
  final int inboxCount;

  const TodayProjection({
    required this.day,
    required this.now,
    required this.next,
    required this.later,
    required this.relationshipNudge,
    required this.latestChange,
    required this.inboxCount,
  });

  bool get isEmpty =>
      now.isEmpty &&
      next.isEmpty &&
      later.isEmpty &&
      relationshipNudge == null &&
      latestChange == null;
}

TodayProjection buildTodayProjection(
  Map<String, Map<String, dynamic>> records,
  DateTime now, {
  PlannerChange? latestChange,
}) {
  final start = DateTime(now.year, now.month, now.day);
  final tomorrow = start.add(const Duration(days: 1));
  final weekEnd = start.add(const Duration(days: 7));
  final current = <PlannerItem>[];
  final nextCandidates = <({int rank, DateTime at, PlannerItem item})>[];
  final laterCandidates = <PlannerItem>[];
  var inboxCount = 0;

  for (final record in records.values) {
    switch (record['typeId']) {
      case 'task':
        if (record['completed'] == true || record['status'] == 'done') continue;
        if ((record['status'] ?? 'inbox') == 'inbox') inboxCount++;
        final scheduled = _dateTime(record['scheduledStartAt']);
        final deadline = _dateTime(record['dueAt']);
        final at = scheduled ?? deadline;
        final title = '${record['description'] ?? 'Untitled task'}';
        final overdue = deadline != null && deadline.isBefore(start);
        final item = PlannerItem(
          id: '${record['id']}',
          kind: PlannerItemKind.task,
          title: title,
          detail: _taskDetail(record, scheduled, deadline, now),
          at: at,
          overdue: overdue,
          completable: true,
        );
        if (scheduled != null &&
            scheduled.isBefore(tomorrow) &&
            !scheduled.isAfter(now.add(const Duration(minutes: 30)))) {
          current.add(item);
        } else if (overdue) {
          nextCandidates.add((rank: 0, at: deadline, item: item));
        } else if (_sameDay(scheduled, start) ||
            _sameDay(deadline, start) ||
            record['status'] == 'today') {
          nextCandidates.add((rank: 1, at: at ?? tomorrow, item: item));
        } else if (at != null &&
            !at.isBefore(tomorrow) &&
            at.isBefore(weekEnd)) {
          laterCandidates.add(item);
        } else if (record['priority'] == 'high') {
          nextCandidates.add((rank: 2, at: at ?? weekEnd, item: item));
        }
      case 'reminder':
        if (record['done'] == true) continue;
        final at = _dateTime(record['remindAt']);
        if (at == null) continue;
        final item = PlannerItem(
          id: '${record['id']}',
          kind: PlannerItemKind.reminder,
          title: '${record['text'] ?? 'Reminder'}',
          detail: _timeLabel(at, now),
          at: at,
          overdue: at.isBefore(now),
        );
        if (!at.isAfter(now)) {
          current.add(item);
        } else if (at.isBefore(tomorrow)) {
          nextCandidates.add((rank: 1, at: at, item: item));
        } else if (at.isBefore(weekEnd)) {
          laterCandidates.add(item);
        }
      case 'routine':
        // An active routine is available, not scheduled. Show at most as a
        // low-priority next option; never manufacture a time commitment.
        if (record['status'] == 'active') {
          nextCandidates.add((
            rank: 3,
            at: weekEnd,
            item: PlannerItem(
              id: '${record['id']}',
              kind: PlannerItemKind.routine,
              title: '${record['title'] ?? 'Routine'}',
              detail: 'Ready when you are',
            ),
          ));
        }
    }
  }

  current.sort(_itemOrder);
  nextCandidates.sort((a, b) {
    final rank = a.rank.compareTo(b.rank);
    return rank != 0 ? rank : a.at.compareTo(b.at);
  });
  laterCandidates.sort(_itemOrder);

  return TodayProjection(
    day: start,
    now: List.unmodifiable(current.take(3)),
    next: List.unmodifiable(nextCandidates.take(3).map((entry) => entry.item)),
    later: List.unmodifiable(laterCandidates.take(3)),
    relationshipNudge: _relationshipNudge(records, start, weekEnd),
    latestChange: latestChange,
    inboxCount: inboxCount,
  );
}

PlanProjection buildPlanProjection(
  Map<String, Map<String, dynamic>> records,
  DateTime now, {
  required DateTime selectedDay,
  int dailyCapacityMinutes = 8 * 60,
}) {
  final selected = _day(selectedDay);
  final weekStart = selected.subtract(Duration(days: selected.weekday - 1));
  final activeTasks = records.values
      .where((record) =>
          record['typeId'] == 'task' &&
          record['completed'] != true &&
          record['status'] != 'done')
      .toList();

  PlanTaskItem taskItem(Map<String, dynamic> record) {
    final dependencies = ((record['dependencyRefs'] as List?) ?? const [])
        .map((value) => '$value')
        .toList();
    final unmet = dependencies.where((id) {
      final dependency = records[id];
      return dependency == null ||
          (dependency['completed'] != true && dependency['status'] != 'done');
    }).toList();
    final explicitReason = record['blockedReason']?.toString().trim();
    return PlanTaskItem(
      id: '${record['id']}',
      kind: PlannerItemKind.task,
      title: '${record['description'] ?? 'Untitled task'}',
      scheduledStartAt: _dateTime(record['scheduledStartAt']),
      dueAt: _dateTime(record['dueAt']),
      estimatedMinutes: _positiveMinutes(record['estimatedMinutes']),
      priority: '${record['priority'] ?? 'none'}',
      energy: record['energy']?.toString(),
      contexts: (record['contexts'] as List? ?? const [])
          .map((value) => '$value')
          .toList(growable: false),
      recurrence: record['recurrence']?.toString(),
      blocked: unmet.isNotEmpty || (explicitReason?.isNotEmpty ?? false),
      blockedReason: explicitReason?.isNotEmpty == true
          ? explicitReason
          : unmet.isEmpty
              ? null
              : 'Waiting on ${unmet.length} task${unmet.length == 1 ? '' : 's'}',
    );
  }

  final taskItems = activeTasks.map(taskItem).toList();
  final conflicts = <PlanConflict>[];
  for (var offset = 0; offset < 7; offset++) {
    final day = weekStart.add(Duration(days: offset));
    final scheduled = taskItems
        .where((item) => _sameDay(item.scheduledStartAt, day))
        .where((item) => item.estimatedMinutes != null)
        .toList()
      ..sort((a, b) => a.scheduledStartAt!.compareTo(b.scheduledStartAt!));
    for (var i = 0; i < scheduled.length; i++) {
      final left = scheduled[i];
      final end = left.scheduledStartAt!.add(
        Duration(minutes: left.estimatedMinutes!),
      );
      for (var j = i + 1; j < scheduled.length; j++) {
        final right = scheduled[j];
        if (!right.scheduledStartAt!.isBefore(end)) break;
        conflicts.add(
          PlanConflict(
            day: day,
            recordIds: [left.id, right.id],
            message: '${left.title} overlaps ${right.title}',
          ),
        );
      }
    }
  }

  final agenda = taskItems
      .where((item) => _sameDay(item.scheduledStartAt, selected))
      .toList()
    ..sort((a, b) => a.scheduledStartAt!.compareTo(b.scheduledStartAt!));
  for (final record in records.values) {
    if (record['typeId'] != 'reminder' || record['done'] == true) continue;
    final at = _dateTime(record['remindAt']);
    if (!_sameDay(at, selected)) continue;
    agenda.add(
      PlanTaskItem(
        id: '${record['id']}',
        kind: PlannerItemKind.reminder,
        title: '${record['text'] ?? 'Reminder'}',
        scheduledStartAt: at,
        dueAt: null,
        estimatedMinutes: null,
        priority: 'none',
        blocked: false,
      ),
    );
  }
  agenda.sort((a, b) => a.scheduledStartAt!.compareTo(b.scheduledStartAt!));

  final deadlines = taskItems
      .where((item) => _sameDay(item.dueAt, selected))
      .toList()
    ..sort(_planRiskOrder);
  final unscheduled = taskItems
      .where((item) =>
          item.scheduledStartAt == null && !_sameDay(item.dueAt, selected))
      .toList()
    ..sort(_planRiskOrder);

  final days = <PlanDaySummary>[];
  for (var offset = 0; offset < 7; offset++) {
    final day = weekStart.add(Duration(days: offset));
    final scheduled = taskItems
        .where((item) => _sameDay(item.scheduledStartAt, day))
        .toList();
    days.add(
      PlanDaySummary(
        day: day,
        scheduledMinutes: scheduled.fold(
          0,
          (sum, item) => sum + (item.estimatedMinutes ?? 0),
        ),
        capacityMinutes: dailyCapacityMinutes,
        unknownEstimateCount:
            scheduled.where((item) => item.estimatedMinutes == null).length,
        conflictCount:
            conflicts.where((item) => _sameDay(item.day, day)).length,
      ),
    );
  }

  return PlanProjection(
    selectedDay: selected,
    days: List.unmodifiable(days),
    agenda: List.unmodifiable(agenda),
    deadlines: List.unmodifiable(deadlines),
    unscheduled: List.unmodifiable(unscheduled),
    conflicts: List.unmodifiable(
      conflicts.where((item) => _sameDay(item.day, selected)),
    ),
  );
}

int? _positiveMinutes(Object? value) {
  final parsed = value is num ? value.round() : num.tryParse('$value')?.round();
  return parsed == null || parsed <= 0 ? null : parsed;
}

int _planRiskOrder(PlanTaskItem a, PlanTaskItem b) {
  const priority = {'high': 0, 'medium': 1, 'low': 2, 'none': 3};
  final p = (priority[a.priority] ?? 3).compareTo(priority[b.priority] ?? 3);
  if (p != 0) return p;
  final dueA = a.dueAt ?? DateTime(9999);
  final dueB = b.dueAt ?? DateTime(9999);
  final due = dueA.compareTo(dueB);
  return due != 0 ? due : a.title.compareTo(b.title);
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

PlannerItem? _relationshipNudge(
  Map<String, Map<String, dynamic>> records,
  DateTime start,
  DateTime weekEnd,
) {
  final names = <String, String>{
    for (final record in records.values)
      if (record['typeId'] == 'contact')
        '${record['id']}': '${record['displayName'] ?? 'Someone'}',
  };
  final candidates = <PlannerItem>[];
  for (final record in records.values) {
    String? person;
    Object? rawDate;
    String label = 'birthday';
    if (record['typeId'] == 'contact' && record['birthday'] != null) {
      person = '${record['displayName'] ?? 'Someone'}';
      rawDate = record['birthday'];
    } else if (record['typeId'] == 'contact_date') {
      person = names['${record['subject']}'];
      rawDate = record['date'];
      label = '${record['label'] ?? 'important date'}';
    }
    final date = _dateTime(rawDate);
    if (person == null || date == null) continue;
    var occurrence = DateTime(start.year, date.month, date.day);
    if (occurrence.isBefore(start)) {
      occurrence = DateTime(start.year + 1, date.month, date.day);
    }
    if (!occurrence.isBefore(weekEnd)) continue;
    final days = occurrence.difference(start).inDays;
    candidates.add(PlannerItem(
      id: '${record['id']}',
      kind: PlannerItemKind.relationship,
      title: "$person's $label",
      detail: days == 0
          ? 'Today'
          : days == 1
              ? 'Tomorrow'
              : 'In $days days',
      at: occurrence,
    ));
  }
  candidates.sort(_itemOrder);
  return candidates.firstOrNull;
}

String? _taskDetail(
  Map<String, dynamic> record,
  DateTime? scheduled,
  DateTime? deadline,
  DateTime now,
) {
  final parts = <String>[];
  if (scheduled != null) parts.add('Scheduled ${_timeLabel(scheduled, now)}');
  if (deadline != null) parts.add('Deadline ${_dayLabel(deadline, now)}');
  if (record['estimatedMinutes'] != null) {
    final estimate = num.tryParse('${record['estimatedMinutes']}')?.round();
    if (estimate != null) parts.add('$estimate min');
  }
  if (record['priority'] == 'high') parts.add('High priority');
  return parts.isEmpty ? null : parts.join(' · ');
}

String _timeLabel(DateTime at, DateTime now) {
  if (at.isBefore(now)) return 'Overdue';
  final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final minute =
      at.minute == 0 ? '' : ':${at.minute.toString().padLeft(2, '0')}';
  return '${_dayLabel(at, now)} · $h$minute ${at.hour < 12 ? 'AM' : 'PM'}';
}

String _dayLabel(DateTime at, DateTime now) {
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final delta = day.difference(today).inDays;
  if (delta < 0) return 'overdue';
  if (delta == 0) return 'today';
  if (delta == 1) return 'tomorrow';
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return weekdays[at.weekday - 1];
}

DateTime? _dateTime(Object? value) {
  if (value == null) return null;
  return value is DateTime ? value : DateTime.tryParse('$value');
}

bool _sameDay(DateTime? value, DateTime day) =>
    value != null &&
    value.year == day.year &&
    value.month == day.month &&
    value.day == day.day;

int _itemOrder(PlannerItem left, PlannerItem right) {
  if (left.overdue != right.overdue) return left.overdue ? -1 : 1;
  final at = (left.at ?? DateTime(9999)).compareTo(right.at ?? DateTime(9999));
  return at != 0 ? at : left.title.compareTo(right.title);
}
