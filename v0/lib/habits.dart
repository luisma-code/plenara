library;

typedef _Store = Map<String, Map<String, dynamic>>;

class HabitStatus {
  final String id;
  final String title;
  final int targetPerWeek;
  final int completedThisWeek;
  final bool completedToday;
  final int currentStreakDays;
  final List<bool> lastSevenDays;
  final List<String> lastSevenOutcomes;
  final bool active;
  final bool skippedToday;
  final bool opportunityToday;
  final String reason, cue, normalVersion, minimumVersion;

  const HabitStatus({
    required this.id,
    required this.title,
    required this.targetPerWeek,
    required this.completedThisWeek,
    required this.completedToday,
    required this.currentStreakDays,
    required this.lastSevenDays,
    this.lastSevenOutcomes = const [],
    required this.active,
    this.skippedToday = false,
    this.opportunityToday = true,
    this.reason = '',
    this.cue = '',
    this.normalVersion = '',
    this.minimumVersion = '',
  });

  int get remainingThisWeek =>
      (targetPerWeek - completedThisWeek).clamp(0, targetPerWeek);

  bool get dueToday =>
      active &&
      !completedToday &&
      !skippedToday &&
      opportunityToday &&
      remainingThisWeek > 0;
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

String _dayKey(DateTime value) {
  final day = _day(value);
  return '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

DateTime _weekStart(DateTime value) {
  final day = _day(value);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// One deterministic projection shared by the Habits UI and cross-workflow
/// summaries. A day counts at most once even if old data contains duplicate
/// check-ins; the current streak can still be alive through yesterday.
List<HabitStatus> habitStatuses(_Store store, DateTime now) {
  final today = _day(now);
  final weekStart = _weekStart(today);
  final logsByHabit = <String, Set<String>>{};
  final skipsByHabit = <String, Set<String>>{};
  final outcomesByHabit = <String, Map<String, String>>{};
  for (final record in store.values) {
    if (record['typeId'] != 'habit_checkin') continue;
    final habit = '${record['habit'] ?? ''}';
    final date = DateTime.tryParse('${record['date'] ?? ''}');
    if (habit.isEmpty || date == null || _day(date).isAfter(today)) continue;
    outcomesByHabit.putIfAbsent(habit, () => {})[_dayKey(date)] =
        '${record['outcome'] ?? 'completed'}';
    if (record['outcome'] == 'skipped') {
      skipsByHabit.putIfAbsent(habit, () => <String>{}).add(_dayKey(date));
    } else {
      logsByHabit.putIfAbsent(habit, () => <String>{}).add(_dayKey(date));
    }
  }

  final result = <HabitStatus>[];
  for (final habit in store.values.where((r) => r['typeId'] == 'habit')) {
    final id = '${habit['id']}';
    final dates = logsByHabit[id] ?? const <String>{};
    final target =
        (num.tryParse('${habit['targetPerWeek'] ?? ''}')?.round() ?? 7)
            .clamp(1, 7);
    final completedThisWeek = dates.where((raw) {
      final value = DateTime.tryParse(raw);
      return value != null && !value.isBefore(weekStart);
    }).length;
    final completedToday = dates.contains(_dayKey(today));
    var cursor =
        completedToday ? today : today.subtract(const Duration(days: 1));
    var streak = 0;
    while (dates.contains(_dayKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    result.add(HabitStatus(
      id: id,
      title: '${habit['title'] ?? 'Untitled habit'}',
      targetPerWeek: target,
      completedThisWeek: completedThisWeek,
      completedToday: completedToday,
      currentStreakDays: streak,
      lastSevenDays: [
        for (var offset = 6; offset >= 0; offset--)
          dates.contains(_dayKey(today.subtract(Duration(days: offset)))),
      ],
      lastSevenOutcomes: [
        for (var offset = 6; offset >= 0; offset--)
          outcomesByHabit[id]
                  ?[_dayKey(today.subtract(Duration(days: offset)))] ??
              'unknown'
      ],
      active: '${habit['status'] ?? 'active'}' == 'active',
      skippedToday:
          (skipsByHabit[id] ?? const <String>{}).contains(_dayKey(today)),
      opportunityToday: (() {
        final preferred = '${habit['preferredDays'] ?? ''}'
            .split(',')
            .map(int.tryParse)
            .whereType<int>()
            .where((d) => d >= 1 && d <= 7)
            .toSet();
        final days = preferred.isEmpty
            ? {for (var i = 0; i < target; i++) 1 + (i * 7 / target).floor()}
            : preferred;
        return days.contains(today.weekday);
      })(),
      reason: '${habit['reason'] ?? ''}',
      cue: '${habit['cue'] ?? ''}',
      normalVersion: '${habit['normalVersion'] ?? ''}',
      minimumVersion: '${habit['minimumVersion'] ?? ''}',
    ));
  }
  result.sort((a, b) {
    final active = (a.active ? 0 : 1).compareTo(b.active ? 0 : 1);
    if (active != 0) return active;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return List.unmodifiable(result);
}

List<HabitStatus> habitsDueToday(_Store store, DateTime now) =>
    habitStatuses(store, now).where((habit) => habit.dueToday).toList();
