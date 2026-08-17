import 'package:flutter/material.dart';
import 'package:plenara/conversation_ledger.dart';
import 'package:plenara/planner.dart';
import 'package:plenara/session.dart';

import 'plenara_theme.dart';

class TodayBoard extends StatelessWidget {
  final Session session;
  final VoidCallback onChanged;
  final VoidCallback? onVoice;
  final VoidCallback onOpenLibrary;

  const TodayBoard({
    super.key,
    required this.session,
    required this.onChanged,
    required this.onOpenLibrary,
    this.onVoice,
  });

  @override
  Widget build(BuildContext context) {
    final projection = session.todayProjection();
    final notices = session.plannerNotices();
    final day = projection.day;
    final visibleIds = <String>[];
    final seen = <String>{};
    for (final item in [
      ...projection.now,
      ...projection.next,
      ...projection.later,
    ]) {
      if (item.kind == PlannerItemKind.task && seen.add(item.id)) {
        visibleIds.add(item.id);
      }
    }
    session.setPlannerContext(
      PlannerContext(
        visibleStart: day,
        visibleEnd: day.add(const Duration(days: 7)),
        selectedDay: day,
        visibleRecordIds: visibleIds,
      ),
    );
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onVoice,
            child: ListView(
              key: const Key('today-board'),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 118),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TODAY',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: PlenaraTheme.amber,
                                  letterSpacing: 2.2,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _dateLabel(day),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w300),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      key: const Key('today-voice'),
                      tooltip: 'Talk to Plena',
                      onPressed: onVoice,
                      icon: const Icon(Icons.mic_none_rounded),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      key: const Key('today-library'),
                      tooltip: 'Open Library',
                      onPressed: onOpenLibrary,
                      icon: const Icon(Icons.grid_view_rounded),
                    ),
                    const SizedBox(width: 42),
                  ],
                ),
                const SizedBox(height: 28),
                if (session.repairIssues.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Card(
                      color: const Color(0xD92B1B16),
                      child: ListTile(
                        key: const Key('repair-needed'),
                        leading: const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFFFC2A8),
                        ),
                        title: const Text('Some local data needs attention'),
                        subtitle: Text(session.repairIssues.first),
                      ),
                    ),
                  ),
                if (projection.now.isNotEmpty)
                  _Section(
                    title: 'Now',
                    items: projection.now,
                    session: session,
                    onChanged: onChanged,
                  ),
                _Section(
                  title: 'Next',
                  empty: projection.now.isEmpty
                      ? 'Nothing pressing. Capture anything on your mind.'
                      : 'The rest of today is clear.',
                  items: projection.next,
                  session: session,
                  onChanged: onChanged,
                ),
                for (final notice in notices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        key: const Key('planner-notice'),
                        title: Text(notice),
                      ),
                    ),
                  ),
                if (projection.later.isNotEmpty)
                  _Section(
                    title: 'Later this week',
                    items: projection.later,
                    session: session,
                    onChanged: onChanged,
                  ),
                if (projection.relationshipNudge case final nudge?)
                  _RelationshipCard(item: nudge),
                if (projection.latestChange case final change?)
                  _LatestChange(
                    change: change,
                    onUndo: () async {
                      final message = await session.undoById(
                        change.executionId,
                      );
                      if (!context.mounted) return;
                      onChanged();
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(message)));
                    },
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.inbox_outlined, size: 18),
                      label: Text('${projection.inboxCount} in Inbox'),
                      onPressed: onOpenLibrary,
                    ),
                    ActionChip(
                      key: const Key('conversation-history'),
                      avatar: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('History'),
                      onPressed: () async {
                        final changed = await showConversationLedger(
                          context,
                          session,
                        );
                        if (changed && context.mounted) onChanged();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? empty;
  final List<PlannerItem> items;
  final Session session;
  final VoidCallback onChanged;

  const _Section({
    required this.title,
    required this.items,
    required this.session,
    required this.onChanged,
    this.empty,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: PlenaraTheme.quietInk,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 9),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              empty ?? 'Clear',
              style: const TextStyle(color: PlenaraTheme.quietInk),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  _PlannerRow(
                    item: items[index],
                    onComplete: items[index].completable
                        ? () => _complete(context, items[index])
                        : null,
                  ),
                  if (index != items.length - 1)
                    const Divider(height: 1, indent: 54),
                ],
              ],
            ),
          ),
      ],
    ),
  );

  Future<void> _complete(BuildContext context, PlannerItem item) async {
    final result = await session.completeTask(item.id);
    if (!context.mounted) return;
    onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        action: result.undoId == null
            ? null
            : SnackBarAction(
                label: 'UNDO',
                onPressed: () async {
                  await session.undoById(result.undoId!);
                  onChanged();
                },
              ),
      ),
    );
  }
}

class _PlannerRow extends StatelessWidget {
  final PlannerItem item;
  final VoidCallback? onComplete;

  const _PlannerRow({required this.item, this.onComplete});

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${item.kind.name}: ${item.title}${item.detail == null ? '' : ', ${item.detail}'}',
    child: ListTile(
      key: Key('planner-${item.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      leading: onComplete == null
          ? Icon(_icon(item.kind), color: PlenaraTheme.amber)
          : IconButton(
              tooltip: 'Complete ${item.title}',
              onPressed: onComplete,
              icon: const Icon(Icons.radio_button_unchecked_rounded),
            ),
      title: Text(
        item.title,
        style: TextStyle(
          color: item.overdue ? const Color(0xFFFFC2A8) : null,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: item.detail == null
          ? null
          : Text(
              item.detail!,
              style: const TextStyle(color: PlenaraTheme.quietInk),
            ),
    ),
  );
}

class _RelationshipCard extends StatelessWidget {
  final PlannerItem item;
  const _RelationshipCard({required this.item});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Card(
      color: const Color(0xD9221917),
      child: ListTile(
        key: const Key('relationship-nudge'),
        leading: const Icon(
          Icons.favorite_outline_rounded,
          color: Color(0xFFE9A58B),
        ),
        title: Text(item.title),
        subtitle: Text(item.detail ?? 'Coming up'),
      ),
    ),
  );
}

class _LatestChange extends StatelessWidget {
  final PlannerChange change;
  final VoidCallback onUndo;
  const _LatestChange({required this.change, required this.onUndo});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Card(
      child: ListTile(
        key: const Key('latest-change'),
        leading: const Icon(Icons.check_rounded, color: PlenaraTheme.amber),
        title: const Text('Latest change'),
        subtitle: Text(change.description),
        trailing: TextButton(onPressed: onUndo, child: const Text('Undo')),
      ),
    ),
  );
}

Future<bool> showConversationLedger(
  BuildContext context,
  Session session,
) async {
  final entries = session.conversationLedger.entries.reversed.toList();
  var changed = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF15120F),
    builder: (context) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: .78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Text(
                'Conversation history',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('No conversations yet.'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (_, index) => _ConversationCard(
                        entry: entries[index],
                        session: session,
                        onChanged: () => changed = true,
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
  return changed;
}

class _ConversationCard extends StatelessWidget {
  final ConversationEntry entry;
  final Session session;
  final VoidCallback onChanged;
  const _ConversationCard({
    required this.entry,
    required this.session,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.utterance,
            style: const TextStyle(color: PlenaraTheme.quietInk),
          ),
          const SizedBox(height: 8),
          Text(entry.reply),
          const SizedBox(height: 9),
          Text(
            entry.source,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: PlenaraTheme.amber),
          ),
          if (entry.executionId != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final message = await session.undoById(entry.executionId!);
                  if (!context.mounted) return;
                  onChanged();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(message)));
                },
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Undo this action'),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

IconData _icon(PlannerItemKind kind) => switch (kind) {
  PlannerItemKind.task => Icons.check_circle_outline_rounded,
  PlannerItemKind.reminder => Icons.notifications_none_rounded,
  PlannerItemKind.routine => Icons.self_improvement_rounded,
  PlannerItemKind.relationship => Icons.favorite_outline_rounded,
};

String _dateLabel(DateTime day) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${weekdays[day.weekday - 1]}, ${months[day.month - 1]} ${day.day}';
}
