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
