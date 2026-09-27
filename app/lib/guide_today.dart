import 'package:flutter/material.dart';
import 'package:plenara/habits.dart';
import 'package:plenara/people.dart';
import 'package:plenara/session.dart';
import 'plenara_theme.dart';
import 'undo_feedback.dart';

class GuideToday extends StatelessWidget {
  final Session session;
  final ValueChanged<String> onConversation;
  final ValueChanged<String> onPerson;
  final VoidCallback onTasks, onRoutines, onHistory, onChanged;
  final Widget menuAction;
  const GuideToday({
    super.key,
    required this.session,
    required this.onConversation,
    required this.onPerson,
    required this.onTasks,
    required this.onRoutines,
    required this.onHistory,
    required this.onChanged,
    required this.menuAction,
  });

  Future<void> _result(BuildContext context, Future<ManualWrite> action) async {
    final result = await action;
    onChanged();
    if (!context.mounted) return;
    showUndoableResult(
      context,
      message: result.message,
      onUndo: result.undoId == null
          ? null
          : () async {
              final response = await session.undoById(result.undoId!);
              onChanged();
              return response;
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final people = relationshipStatuses(session.store, session.now)
        .where(
          (p) =>
              p.engagement == RelationshipEngagement.active &&
              p.circle != RelationshipCircle.context &&
              !p.acknowledged,
        )
        .toList();
    final person =
        people.where((p) => p.needsContact).firstOrNull ?? people.firstOrNull;
    final tasks =
        session.store.values
            .where(
              (r) =>
                  r['typeId'] == 'task' &&
                  r['completed'] != true &&
                  r['status'] != 'done' &&
                  r['reviewDecision'] != 'drop' &&
                  '${r['blockedReason'] ?? ''}'.isEmpty &&
                  !const {'waiting', 'someday'}.contains(r['status']) &&
                  !((r['dependencyRefs'] as List?) ?? []).any((id) {
                    final dependency = session.store[id];
                    return dependency == null ||
                        (dependency['completed'] != true &&
                            dependency['status'] != 'done');
                  }),
            )
            .toList()
          ..sort((a, b) {
            final ad = DateTime.tryParse('${a['dueAt']}'),
                bd = DateTime.tryParse('${b['dueAt']}');
            if (ad != null && bd != null) return ad.compareTo(bd);
            if (ad != null) return -1;
            if (bd != null) return 1;
            return '${a['description']}'.compareTo('${b['description']}');
          });
    final task = tasks.firstOrNull;
    final practice = habitsDueToday(session.store, session.now).firstOrNull;
    final last = session.conversationLedger.entries.lastOrNull;
    final returning =
        last != null && session.now.difference(last.at).inDays >= 7;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(
            tooltip: 'History',
            onPressed: onHistory,
            icon: const Icon(Icons.history_rounded),
          ),
          menuAction,
        ],
      ),
      body: ListView(
        key: const Key('guide-today'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            returning
                ? "Let's pick up from here"
                : 'What would make today feel worthwhile?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            returning
                ? 'We can start with one useful step. Updates can happen as we go.'
                : 'Make space for people, follow through on a commitment, or find a routine that fits.',
            style: const TextStyle(color: PlenaraTheme.quietInk),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () => onConversation(
                  'Help me choose one attainable next step for today.',
                ),
                child: const Text('Help me choose'),
              ),
              OutlinedButton(
                onPressed: () => onConversation(
                  'Something happened that I would like to tell you about.',
                ),
                child: const Text('Something happened'),
              ),
            ],
          ),
          if (person != null)
            _Opportunity(
              title: 'People',
              text: person.displayName,
              detail: person.health == RelationshipHealth.noHistory
                  ? 'Last update unknown. Is there someone you would enjoy connecting with?'
                  : 'You wanted to keep connected. ${relationshipProximityGuidance(person.proximity)}.',
              actions: [
                TextButton(
                  onPressed: () => onPerson(person.contactId),
                  child: const Text('Make space for them'),
                ),
                TextButton(
                  onPressed: () => _result(
                    context,
                    session.acknowledgeRelationship(person.contactId),
                  ),
                  child: const Text('We already caught up'),
                ),
              ],
            ),
          if (task != null)
            _Opportunity(
              title: 'One commitment',
              text: '${task['description']}',
              detail: task['dueAt'] != null
                  ? 'Deadline: ${task['dueAt']}'
                  : 'Choose a small next step when you have space.',
              actions: [
                TextButton(
                  onPressed: () =>
                      _result(context, session.completeTask('${task['id']}')),
                  child: const Text('Done'),
                ),
                TextButton(
                  onPressed: () => onConversation(
                    'Help me take the next step on ${task['description']}.',
                  ),
                  child: const Text('Help me start'),
                ),
                TextButton(onPressed: onTasks, child: const Text('See tasks')),
              ],
            ),
          if (practice != null)
            _Opportunity(
              title: 'A routine that fits',
              text: practice.title,
              detail: practice.minimumVersion.isNotEmpty
                  ? '${practice.cue}\n${practice.minimumVersion} counts.'
                  : 'A smaller attempt can still count. ${practice.remainingThisWeek} opportunities left this week.',
              actions: [
                TextButton(onPressed: onRoutines, child: const Text('Start')),
                TextButton(
                  onPressed: () => onConversation(
                    'Help me adapt ${practice.title} to today.',
                  ),
                  child: const Text('Adapt today'),
                ),
              ],
            ),
          if (person == null && task == null && practice == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'You can start with a conversation. There is no setup checklist to finish first.',
              ),
            ),
        ],
      ),
    );
  }
}

class _Opportunity extends StatelessWidget {
  final String title, text, detail;
  final List<Widget> actions;
  const _Opportunity({
    required this.title,
    required this.text,
    required this.detail,
    required this.actions,
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: PlenaraTheme.amber)),
          const SizedBox(height: 6),
          Text(text, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(detail, style: const TextStyle(color: PlenaraTheme.quietInk)),
          Wrap(spacing: 6, runSpacing: 4, children: actions),
        ],
      ),
    ),
  );
}
