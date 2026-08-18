import 'package:flutter/material.dart';
import 'package:plenara/conversation_ledger.dart';
import 'package:plenara/operation_center.dart';
import 'package:plenara/planning_artifact.dart';
import 'package:plenara/planner.dart';
import 'package:plenara/session.dart';
import 'package:plenara/weekly_review.dart';

import 'plenara_theme.dart';
import 'motion.dart';

class TodayBoard extends StatelessWidget {
  final Session session;
  final VoidCallback onChanged;
  final VoidCallback? onVoice;
  final VoidCallback onOpenLibrary;
  final VoidCallback? onOpenAttention;

  const TodayBoard({
    super.key,
    required this.session,
    required this.onChanged,
    required this.onOpenLibrary,
    this.onOpenAttention,
    this.onVoice,
  });

  @override
  Widget build(BuildContext context) {
    final projection = session.todayProjection();
    final notices = session.plannerNotices();
    final signals = session.plannerSignals();
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
                      key: const Key('today-weekly-review'),
                      tooltip: 'Review this week',
                      onPressed: () {
                        session.createWeeklyReview();
                        onChanged();
                      },
                      icon: const Icon(Icons.fact_check_outlined),
                    ),
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
                        trailing: const Icon(Icons.chevron_right),
                        onTap: onOpenAttention,
                      ),
                    ),
                  ),
                if (session.activeWeeklyReview case final review?
                    when review.state == WeeklyReviewState.draft ||
                        review.state == WeeklyReviewState.stale)
                  _WeeklyReviewCard(
                    review: review,
                    onDecision: (item, decision) {
                      session.setWeeklyReviewDecision(item.recordId, decision);
                      onChanged();
                    },
                    onRefresh: () {
                      session.createWeeklyReview();
                      onChanged();
                    },
                    onDismiss: () {
                      session.dismissWeeklyReview();
                      onChanged();
                    },
                    onApply: () async {
                      final result = await session.applyWeeklyReview();
                      onChanged();
                      if (!context.mounted) return;
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
                    },
                  ),
                for (final artifact in session.activePlanningArtifacts)
                  _PlanningArtifactCard(
                    artifact: artifact,
                    onAccept: () {
                      session.resolvePlanningArtifact(
                        artifact.id,
                        accepted: true,
                      );
                      onChanged();
                    },
                    onDismiss: () {
                      session.resolvePlanningArtifact(
                        artifact.id,
                        accepted: false,
                      );
                      onChanged();
                    },
                    onDefer: () {
                      session.deferPlanningArtifact(artifact.id);
                      onChanged();
                    },
                  ),
                _Section(
                  title: 'Now',
                  empty: 'Nothing is underway.',
                  items: projection.now,
                  session: session,
                  onChanged: onChanged,
                ),
                for (final operation in session.operations.records.where(
                  (record) =>
                      record.state == OperationState.queued ||
                      record.state == OperationState.running,
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        key: Key('operation-${operation.id}'),
                        leading: const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        title: Text(operation.title),
                        subtitle: const Text(
                          'Working in the background — capture remains available',
                        ),
                        trailing: TextButton(
                          onPressed: () {
                            session.operations.cancel(operation.id);
                            onChanged();
                          },
                          child: const Text('Cancel'),
                        ),
                      ),
                    ),
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
                for (final signal in signals)
                  _PlannerSignalCard(signal: signal),
                _Section(
                  title: 'Later this week',
                  empty: 'Nothing waiting later this week.',
                  items: projection.later,
                  session: session,
                  onChanged: onChanged,
                ),
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
                      key: const Key('today-morning-plan'),
                      avatar: const Icon(Icons.wb_sunny_outlined, size: 18),
                      label: const Text('Plan morning'),
                      onPressed: () {
                        session.createMorningPlan();
                        onChanged();
                      },
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

class _PlanningArtifactCard extends StatelessWidget {
  final PlanningArtifact artifact;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;
  final VoidCallback onDefer;

  const _PlanningArtifactCard({
    required this.artifact,
    required this.onAccept,
    required this.onDismiss,
    required this.onDefer,
  });

  @override
  Widget build(BuildContext context) => Card(
    key: Key('planning-artifact-${artifact.kind.name}'),
    margin: const EdgeInsets.only(bottom: 18),
    color: const Color(0xE6221917),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                artifact.kind == PlanningArtifactKind.morning
                    ? Icons.wb_sunny_outlined
                    : Icons.favorite_outline_rounded,
                color: PlenaraTheme.amber,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  artifact.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            artifact.summary,
            style: const TextStyle(color: PlenaraTheme.quietInk),
          ),
          for (final item in artifact.items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item.title),
              subtitle: Text(item.evidence),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 4,
            children: [
              TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
              TextButton(onPressed: onDefer, child: const Text('Tomorrow')),
              FilledButton(
                key: Key('accept-artifact-${artifact.kind.name}'),
                onPressed: onAccept,
                child: const Text('Keep this plan'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _WeeklyReviewCard extends StatelessWidget {
  final WeeklyReviewArtifact review;
  final void Function(WeeklyReviewItem item, ReviewDecision decision)
  onDecision;
  final VoidCallback onRefresh;
  final VoidCallback onDismiss;
  final VoidCallback onApply;

  const _WeeklyReviewCard({
    required this.review,
    required this.onDecision,
    required this.onRefresh,
    required this.onDismiss,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final stale = review.state == WeeklyReviewState.stale;
    return Card(
      key: const Key('weekly-review-card'),
      margin: const EdgeInsets.only(bottom: 18),
      color: const Color(0xE62B211D),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.fact_check_outlined,
                  color: PlenaraTheme.amber,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stale ? 'Weekly review needs a refresh' : 'Weekly review',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              stale
                  ? review.message ?? 'One of these records changed.'
                  : 'Evidence-backed recommendations. Edit every choice before applying.',
              style: const TextStyle(color: PlenaraTheme.quietInk),
            ),
            if (!stale)
              for (var index = 0; index < review.items.length; index++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${index + 1}. ${review.items[index].title}'),
                  subtitle: Text(review.items[index].evidence),
                  trailing: DropdownButton<ReviewDecision>(
                    key: Key('review-decision-$index'),
                    value: review.items[index].decision,
                    onChanged: review.items[index].recordType == 'goal'
                        ? null
                        : (decision) {
                            if (decision != null) {
                              onDecision(review.items[index], decision);
                            }
                          },
                    items: [
                      for (final decision in ReviewDecision.values)
                        DropdownMenuItem(
                          value: decision,
                          child: Text(decision.name),
                        ),
                    ],
                  ),
                ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
                const SizedBox(width: 6),
                FilledButton(
                  key: Key(
                    stale ? 'refresh-weekly-review' : 'apply-weekly-review',
                  ),
                  onPressed: stale ? onRefresh : onApply,
                  child: Text(stale ? 'Refresh' : 'Apply decisions'),
                ),
              ],
            ),
          ],
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
        Card(
          child: Column(
            children: [
              ContinuityColumn<PlannerItem>(
                key: ValueKey('today-continuity-$title'),
                items: items,
                keyOf: (item) => item.id,
                separator: const Divider(height: 1, indent: 54),
                itemBuilder: (context, item) => _PlannerRow(
                  item: item,
                  onComplete: item.completable
                      ? () => _complete(context, item)
                      : null,
                ),
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    empty ?? 'Clear',
                    style: const TextStyle(color: PlenaraTheme.quietInk),
                  ),
                ),
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
    button: onComplete != null,
    label:
        '${item.kind.name}: ${item.title}${item.detail == null ? '' : ', ${item.detail}'}',
    child: ListTile(
      key: Key('planner-${item.id}'),
      onTap: onComplete,
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

class _PlannerSignalCard extends StatelessWidget {
  final PlannerSignal signal;
  const _PlannerSignalCard({required this.signal});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: ListTile(
        key: Key('planner-signal-${signal.kind.name}'),
        leading: Icon(switch (signal.kind) {
          PlannerSignalKind.relationshipNeglect =>
            Icons.favorite_outline_rounded,
          PlannerSignalKind.overload => Icons.balance_rounded,
          PlannerSignalKind.staleQueue => Icons.inbox_outlined,
        }, color: PlenaraTheme.amber),
        title: Text(signal.title),
        subtitle: Text(signal.detail),
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
  PlannerItemKind.goal => Icons.flag_outlined,
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
