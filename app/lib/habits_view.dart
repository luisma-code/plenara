import 'package:flutter/material.dart';
import 'package:plenara/habits.dart';
import 'package:plenara/session.dart';

import 'plenara_theme.dart';
import 'presence_shell.dart';
import 'undo_feedback.dart';

class HabitsView extends StatefulWidget {
  final Session session;
  final VoidCallback? onVoice;
  final Widget? menuAction;
  final VoidCallback? onOpenRoutines;

  const HabitsView({
    super.key,
    required this.session,
    this.onVoice,
    this.menuAction,
    this.onOpenRoutines,
  });

  @override
  State<HabitsView> createState() => _HabitsViewState();
}

class _HabitsViewState extends State<HabitsView> {
  void _showResult(ManualWrite result) {
    if (!mounted) return;
    setState(() {});
    showUndoableResult(
      context,
      message: result.message,
      onUndo: result.undoId == null
          ? null
          : () async {
              final message = await widget.session.undoById(result.undoId!);
              if (mounted) setState(() {});
              return message;
            },
    );
  }

  Future<void> _addHabit() async {
    final draft = await showDialog<_HabitDraft>(
      context: context,
      builder: (_) => const _HabitEditor(),
    );
    if (draft == null) return;
    final duplicate = widget.session.store.values.any(
      (record) =>
          record['typeId'] == 'habit' &&
          '${record['title']}'.trim().toLowerCase() ==
              draft.title.trim().toLowerCase(),
    );
    if (duplicate) {
      _message('That habit is already being tracked.');
      return;
    }
    _showResult(
      await widget.session.createRecord('habit', {
        'title': draft.title.trim(),
        'targetPerWeek': draft.targetPerWeek,
        'status': 'active',
        ...draft.fields,
        'createdAt': widget.session.now.toIso8601String(),
      }, description: 'started tracking ${draft.title.trim()}'),
    );
  }

  Future<void> _editHabit(HabitStatus status) async {
    final draft = await showDialog<_HabitDraft>(
      context: context,
      builder: (_) => _HabitEditor(
        title: status.title,
        targetPerWeek: status.targetPerWeek,
        fields: widget.session.store[status.id] ?? const {},
      ),
    );
    if (draft == null) return;
    _showResult(
      await widget.session.editFields(status.id, {
        'title': draft.title.trim(),
        'targetPerWeek': draft.targetPerWeek,
        ...draft.fields,
      }),
    );
  }

  Future<void> _setActive(HabitStatus habit, bool active) async {
    _showResult(
      await widget.session.editField(
        habit.id,
        'status',
        active ? 'active' : 'paused',
      ),
    );
  }

  Future<void> _deleteHabit(HabitStatus habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${habit.title}?'),
        content: const Text(
          'This removes the habit and its check-in history. The action can be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove habit'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _showResult(await widget.session.deleteRecord(habit.id));
    }
  }

  Future<void> _startPractice(HabitStatus habit) async {
    final outcome = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(habit.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (habit.reason.isNotEmpty) Text(habit.reason),
              if (habit.cue.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('Start when: ${habit.cue}'),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  habit.normalVersion.isEmpty
                      ? 'Take a moment for this practice.'
                      : habit.normalVersion,
                ),
              ),
              if (habit.minimumVersion.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'A smaller version counts: ${habit.minimumVersion}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'skipped'),
            child: const Text('Skip today'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'minimum'),
            child: const Text('Smaller version done'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'completed'),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (outcome != null) {
      _showResult(
        await widget.session.recordHabitCheckIn(habit.id, outcome: outcome),
      );
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final habits = habitStatuses(widget.session.store, widget.session.now);
    final active = habits.where((habit) => habit.active).toList();
    final paused = habits.where((habit) => !habit.active).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Routines'),
        actions: [
          if (widget.onVoice != null)
            IconButton.filledTonal(
              key: const Key('habits-voice'),
              tooltip: 'Talk to Plena',
              onPressed: widget.onVoice,
              icon: const Icon(Icons.mic_none_rounded),
            ),
          IconButton(
            key: const Key('habits-add'),
            tooltip: 'Add practice',
            onPressed: _addHabit,
            icon: const Icon(Icons.add_rounded),
          ),
          ?widget.menuAction,
        ],
      ),
      body: Stack(
        children: [
          ListView(
            key: const Key('habits-view'),
            padding: const EdgeInsets.fromLTRB(16, 12, 72, 110),
            children: [
              Text(
                'ROUTINES',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: PlenaraTheme.amber,
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Make starting easier',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Practices can fit your week. A smaller version, a rest day, and a fresh start all have a place.',
                style: TextStyle(color: PlenaraTheme.quietInk),
              ),
              const SizedBox(height: 18),
              if (widget.onOpenRoutines != null)
                TextButton.icon(
                  onPressed: widget.onOpenRoutines,
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Guided routines'),
                ),
              if (active.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text(
                          'No active habits yet. Start with a practice you want to notice, not a perfect streak.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const Key('habits-empty-add'),
                          onPressed: _addHabit,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Create a practice'),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                Text('Today', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final habit in active)
                  _HabitCard(
                    habit: habit,
                    today: widget.session.now,
                    onCheckIn: () async {
                      _showResult(
                        await widget.session.recordHabitCheckIn(habit.id),
                      );
                    },
                    onStart: () => _startPractice(habit),
                    onMinimum: () async => _showResult(
                      await widget.session.recordHabitCheckIn(
                        habit.id,
                        outcome: 'minimum',
                      ),
                    ),
                    onSkip: () async => _showResult(
                      await widget.session.recordHabitCheckIn(
                        habit.id,
                        outcome: 'skipped',
                      ),
                    ),
                    onEdit: () => _editHabit(habit),
                    onPause: () => _setActive(habit, false),
                    onDelete: () => _deleteHabit(habit),
                  ),
              ],
              if (paused.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Paused', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final habit in paused)
                  Card(
                    child: ListTile(
                      title: Text(habit.title),
                      subtitle: Text('${habit.targetPerWeek} times a week'),
                      trailing: TextButton(
                        onPressed: () => _setActive(habit, true),
                        child: const Text('Resume'),
                      ),
                    ),
                  ),
              ],
            ],
          ),
          const PlenaEmber(mode: 'Habit tracking.'),
        ],
      ),
    );
  }
}

class _HabitCard extends StatelessWidget {
  final HabitStatus habit;
  final DateTime today;
  final VoidCallback onCheckIn;
  final VoidCallback onStart, onMinimum, onSkip;
  final VoidCallback onEdit;
  final VoidCallback onPause;
  final VoidCallback onDelete;

  const _HabitCard({
    required this.habit,
    required this.today,
    required this.onCheckIn,
    required this.onStart,
    required this.onMinimum,
    required this.onSkip,
    required this.onEdit,
    required this.onPause,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Card(
    key: Key('habit-${habit.id}'),
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  habit.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Manage ${habit.title}',
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'pause') onPause();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Adapt practice')),
                  PopupMenuItem(value: 'pause', child: Text('Pause')),
                  PopupMenuItem(value: 'delete', child: Text('Remove')),
                ],
              ),
            ],
          ),
          Text(
            '${habit.completedThisWeek} of ${habit.targetPerWeek} this week',
            style: const TextStyle(color: PlenaraTheme.quietInk),
          ),
          if (habit.cue.isNotEmpty) Text('When: ${habit.cue}'),
          if (habit.minimumVersion.isNotEmpty)
            Text('Small version: ${habit.minimumVersion}'),
          if (habit.skippedToday) const Text('Rest chosen for today'),
          if (!habit.opportunityToday &&
              !habit.completedToday &&
              !habit.skippedToday)
            const Text('A flexible rest day; you can still choose to practice'),
          Wrap(
            spacing: 8,
            children: [
              TextButton(onPressed: onStart, child: const Text('Start')),
              TextButton(
                onPressed: habit.completedToday || habit.skippedToday
                    ? null
                    : onMinimum,
                child: const Text('Smaller version'),
              ),
              TextButton(
                onPressed: habit.completedToday || habit.skippedToday
                    ? null
                    : onSkip,
                child: const Text('Skip today'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: (habit.completedThisWeek / habit.targetPerWeek).clamp(
              0.0,
              1.0,
            ),
            minHeight: 5,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (index, done) in habit.lastSevenDays.indexed)
                Expanded(
                  child: Tooltip(
                    message:
                        '${_weekday(index, today)}: ${habit.lastSevenOutcomes.isEmpty ? (done ? 'completed' : 'unknown') : habit.lastSevenOutcomes[index]}',
                    child: Column(
                      children: [
                        Icon(
                          habit.lastSevenOutcomes.isNotEmpty &&
                                  habit.lastSevenOutcomes[index] == 'skipped'
                              ? Icons.remove
                              : habit.lastSevenOutcomes.isNotEmpty &&
                                    habit.lastSevenOutcomes[index] == 'minimum'
                              ? Icons.adjust
                              : done
                              ? Icons.circle
                              : Icons.circle_outlined,
                          size: 13,
                          color: done
                              ? PlenaraTheme.amber
                              : PlenaraTheme.quietInk,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _weekday(index, today),
                          style: const TextStyle(
                            color: PlenaraTheme.quietInk,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: Key('habit-check-${habit.id}'),
                onPressed: habit.completedToday ? null : onCheckIn,
                icon: Icon(
                  habit.completedToday
                      ? Icons.check_rounded
                      : Icons.add_rounded,
                ),
                label: Text(habit.completedToday ? 'Done' : 'Check in'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

String _weekday(int index, DateTime today) {
  const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  final day = today.subtract(Duration(days: 6 - index));
  return labels[day.weekday - 1];
}

class _HabitDraft {
  final String title;
  final int targetPerWeek;
  final Map<String, Object?> fields;
  const _HabitDraft(this.title, this.targetPerWeek, this.fields);
}

class _HabitEditor extends StatefulWidget {
  final String title;
  final int targetPerWeek;
  final Map<String, dynamic> fields;
  const _HabitEditor({
    this.title = '',
    this.targetPerWeek = 7,
    this.fields = const {},
  });

  @override
  State<_HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends State<_HabitEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.title,
  );
  late int _target = widget.targetPerWeek;
  late final _fields = {
    for (final k in ['reason', 'cue', 'normalVersion', 'minimumVersion'])
      k: TextEditingController(text: '${widget.fields[k] ?? ''}'),
  };
  late final Set<int> _days = '${widget.fields['preferredDays'] ?? ''}'
      .split(',')
      .map(int.tryParse)
      .whereType<int>()
      .toSet();

  @override
  void dispose() {
    _title.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title.isEmpty ? 'Create a practice' : 'Adapt practice'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('habit-title'),
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'What do you want to repeat?',
            ),
          ),
          for (final entry in _fields.entries)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                controller: entry.value,
                decoration: InputDecoration(
                  labelText: switch (entry.key) {
                    'reason' => 'Why this matters',
                    'cue' => 'When would it fit?',
                    'normalVersion' => 'Usual version',
                    _ => 'Smallest useful version',
                  },
                ),
              ),
            ),
          const SizedBox(height: 18),
          const Text('Rhythm'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            children: [
              for (final target in const [1, 3, 5, 7])
                ChoiceChip(
                  key: Key('habit-target-$target'),
                  selected: _target == target,
                  onSelected: (_) => setState(() => _target = target),
                  label: Text(target == 7 ? 'Daily' : '$target× / week'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Preferred opportunities (optional)'),
          Wrap(
            spacing: 4,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(
                    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1],
                  ),
                  selected: _days.contains(d),
                  onSelected: (yes) => setState(() {
                    if (yes) {
                      _days.add(d);
                    } else {
                      _days.remove(d);
                    }
                  }),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('habit-save'),
        onPressed: () {
          if (_title.text.trim().isEmpty) return;
          Navigator.pop(
            context,
            _HabitDraft(_title.text.trim(), _target, {
              for (final e in _fields.entries) e.key: e.value.text.trim(),
              'preferredDays': (_days.toList()..sort()).join(','),
            }),
          );
        },
        child: const Text('Save practice'),
      ),
    ],
  );
}
