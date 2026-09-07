import 'package:flutter/material.dart';
import 'package:plenara/session.dart';

import 'undo_feedback.dart';

Future<void> addTodoFromUi(
  BuildContext context,
  Session session,
  VoidCallback onChanged,
) async {
  final draft = await showDialog<_TodoDraft>(
    context: context,
    builder: (_) => _TodoEditor(now: session.now),
  );
  if (draft == null || !context.mounted) return;
  final today = DateTime(session.now.year, session.now.month, session.now.day);
  final due = draft.due;
  final result = await session.createRecord('task', {
    'description': draft.description,
    'createdAt': session.now.toIso8601String(),
    'status': due != null && _sameDay(due, today) ? 'today' : 'inbox',
    if (due != null) 'dueAt': _isoDate(due),
  }, description: 'added ${draft.description}');
  if (!context.mounted) return;
  onChanged();
  showUndoableResult(
    context,
    message: result.message,
    onUndo: result.undoId == null
        ? null
        : () async {
            final message = await session.undoById(result.undoId!);
            onChanged();
            return message;
          },
  );
}

class _TodoDraft {
  final String description;
  final DateTime? due;
  const _TodoDraft(this.description, this.due);
}

class _TodoEditor extends StatefulWidget {
  final DateTime now;
  const _TodoEditor({required this.now});

  @override
  State<_TodoEditor> createState() => _TodoEditorState();
}

class _TodoEditorState extends State<_TodoEditor> {
  final _description = TextEditingController();
  DateTime? _due;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    return AlertDialog(
      title: const Text('Add a one-off todo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('todo-description'),
            controller: _description,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'What needs doing?'),
          ),
          const SizedBox(height: 16),
          const Text('When does it matter?'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              ChoiceChip(
                label: const Text('No date'),
                selected: _due == null,
                onSelected: (_) => setState(() => _due = null),
              ),
              ChoiceChip(
                key: const Key('todo-due-today'),
                label: const Text('Today'),
                selected: _due != null && _sameDay(_due!, today),
                onSelected: (_) => setState(() => _due = today),
              ),
              ChoiceChip(
                label: const Text('Tomorrow'),
                selected:
                    _due != null &&
                    _sameDay(_due!, today.add(const Duration(days: 1))),
                onSelected: (_) =>
                    setState(() => _due = today.add(const Duration(days: 1))),
              ),
              ActionChip(
                avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                label: const Text('Pick date'),
                onPressed: () async {
                  final chosen = await showDatePicker(
                    context: context,
                    initialDate: _due ?? today,
                    firstDate: today,
                    lastDate: DateTime(today.year + 10),
                  );
                  if (chosen != null) setState(() => _due = chosen);
                },
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
          key: const Key('todo-save'),
          onPressed: () {
            final description = _description.text.trim();
            if (description.isEmpty) return;
            Navigator.pop(context, _TodoDraft(description, _due));
          },
          child: const Text('Add todo'),
        ),
      ],
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
