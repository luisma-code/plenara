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

  const HabitsView({
    super.key,
    required this.session,
    this.onVoice,
    this.menuAction,
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
      ),
    );
    if (draft == null) return;
    _showResult(
      await widget.session.editFields(status.id, {
        'title': draft.title.trim(),
        'targetPerWeek': draft.targetPerWeek,
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
        title: const Text('Habits'),
        actions: [
          IconButton.filledTonal(
            key: const Key('habits-voice'),
            tooltip: 'Talk to Plena',
            onPressed: widget.onVoice,
            icon: const Icon(Icons.mic_none_rounded),
          ),
          IconButton(
            key: const Key('habits-add'),
            tooltip: 'Add habit',
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
                'HABITS',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: PlenaraTheme.amber,
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Repeat what matters, see the pattern',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'One-off commitments stay in Todos. Habits are practices you want to repeat and track.',
                style: TextStyle(color: PlenaraTheme.quietInk),
              ),
              const SizedBox(height: 18),
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
                          label: const Text('Track a habit'),
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
  final VoidCallback onEdit;
  final VoidCallback onPause;
  final VoidCallback onDelete;

  const _HabitCard({
    required this.habit,
    required this.today,
    required this.onCheckIn,
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
                  PopupMenuItem(value: 'edit', child: Text('Edit habit')),
                  PopupMenuItem(value: 'pause', child: Text('Pause')),
                  PopupMenuItem(value: 'delete', child: Text('Remove')),
                ],
              ),
            ],
          ),
          Text(
            '${habit.completedThisWeek} of ${habit.targetPerWeek} this week'
            '${habit.currentStreakDays > 1 ? ' · ${habit.currentStreakDays}-day streak' : ''}',
            style: const TextStyle(color: PlenaraTheme.quietInk),
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
                  child: Column(
                    children: [
                      Icon(
                        done ? Icons.circle : Icons.circle_outlined,
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
  const _HabitDraft(this.title, this.targetPerWeek);
}

class _HabitEditor extends StatefulWidget {
  final String title;
  final int targetPerWeek;

  const _HabitEditor({this.title = '', this.targetPerWeek = 7});

  @override
  State<_HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends State<_HabitEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.title,
  );
  late int _target = widget.targetPerWeek;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title.isEmpty ? 'Track a habit' : 'Edit habit'),
    content: Column(
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
      ],
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
          Navigator.pop(context, _HabitDraft(_title.text.trim(), _target));
        },
        child: const Text('Save habit'),
      ),
    ],
  );
}
