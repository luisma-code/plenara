import 'package:flutter/material.dart';
import 'package:plenara/plan_proposal.dart';
import 'package:plenara/planner.dart';
import 'package:plenara/session.dart';

import 'plenara_theme.dart';

class PlanBoard extends StatefulWidget {
  final Session session;
  final VoidCallback onChanged;
  final VoidCallback? onVoice;

  const PlanBoard({
    super.key,
    required this.session,
    required this.onChanged,
    this.onVoice,
  });

  @override
  State<PlanBoard> createState() => _PlanBoardState();
}

class _PlanBoardState extends State<PlanBoard> {
  late DateTime _selectedDay = _day(widget.session.now);
  final Set<String> _selectedIds = {};
  bool _busy = false;

  PlanProjection get _projection => widget.session.planProjection(_selectedDay);

  void _refresh() {
    if (mounted) setState(() {});
    widget.onChanged();
  }

  Future<void> _run(Future<ManualWrite> operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await operation;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selectedIds.removeWhere((id) => !widget.session.store.containsKey(id));
    });
    widget.onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        action: result.undoId == null
            ? null
            : SnackBarAction(
                label: 'UNDO',
                onPressed: () async {
                  await widget.session.undoById(result.undoId!);
                  _refresh();
                },
              ),
      ),
    );
  }

  Future<void> _schedule(List<String> ids, {DateTime? start}) async {
    if (ids.isEmpty) return;
    var at = start;
    if (at == null) {
      final now = widget.session.now;
      final initial = _sameDay(_selectedDay, now)
          ? TimeOfDay(hour: (now.hour + 1).clamp(0, 23), minute: 0)
          : const TimeOfDay(hour: 9, minute: 0);
      final picked = await showTimePicker(
        context: context,
        initialTime: initial,
        helpText: ids.length == 1 ? 'Schedule task' : 'Start selected tasks',
      );
      if (picked == null || !mounted) return;
      at = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        picked.hour,
        picked.minute,
      );
    }
    await _run(widget.session.scheduleTasks(ids, at));
    if (mounted) setState(_selectedIds.clear);
  }

  Future<void> _estimate(String id) async {
    final current = widget.session.store[id]?['estimatedMinutes'];
    final controller = TextEditingController(text: current?.toString() ?? '30');
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Time estimate'),
        content: TextField(
          key: const Key('estimate-input'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'minutes'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (minutes != null && mounted) {
      await _run(widget.session.resizeTask(id, minutes));
    }
  }

  Future<void> _rename(String id) async {
    final controller = TextEditingController(
      text: '${widget.session.store[id]?['description'] ?? ''}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename task'),
        content: TextField(
          key: const Key('rename-input'),
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && mounted) {
      await _run(
        widget.session.updateTaskPlans([
          TaskPlanPatch(id: id, description: name),
        ]),
      );
    }
  }

  Future<void> _complete(String id) => _run(widget.session.completeTask(id));

  void _createProposal() {
    widget.session.createWeeklyProposal();
    _refresh();
  }

  Future<void> _applyProposal() async {
    await _run(widget.session.applyPlanProposal());
    _refresh();
  }

  void _dismissProposal() {
    widget.session.dismissPlanProposal();
    _refresh();
  }

  void _toggle(String id) => setState(() {
    _selectedIds.contains(id) ? _selectedIds.remove(id) : _selectedIds.add(id);
  });

  @override
  Widget build(BuildContext context) {
    final projection = _projection;
    final visibleIds = <String>[];
    final seen = <String>{};
    for (final item in [
      ...projection.agenda,
      ...projection.deadlines,
      ...projection.unscheduled,
    ]) {
      if (seen.add(item.id)) visibleIds.add(item.id);
    }
    widget.session.setPlannerContext(
      PlannerContext(
        visibleStart: projection.days.firstOrNull?.day,
        visibleEnd: projection.days.lastOrNull?.day,
        selectedDay: _selectedDay,
        selectedRecordIds: _selectedIds.toList(growable: false),
        visibleRecordIds: visibleIds,
      ),
    );
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1320),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 68, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PLAN',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: PlenaraTheme.amber,
                                      letterSpacing: 2.2,
                                    ),
                              ),
                              Text(
                                _longDate(_selectedDay),
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w300),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          key: const Key('create-plan-proposal'),
                          tooltip: 'Draft this week',
                          onPressed: _busy ? null : _createProposal,
                          icon: const Icon(Icons.auto_awesome_outlined),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          tooltip: 'Talk to Plena',
                          onPressed: widget.onVoice,
                          icon: const Icon(Icons.mic_none_rounded),
                        ),
                      ],
                    ),
                  ),
                  _WeekSelector(
                    days: projection.days,
                    selected: _selectedDay,
                    wide: wide,
                    onSelected: (day) => setState(() {
                      _selectedDay = day;
                      _selectedIds.clear();
                    }),
                    onDrop: (id, day) => _schedule([
                      id,
                    ], start: DateTime(day.year, day.month, day.day, 9)),
                  ),
                  if (widget.session.activePlanProposal case final proposal?
                      when proposal.state == PlanProposalState.draft ||
                          proposal.state == PlanProposalState.stale)
                    _ProposalCard(
                      proposal: proposal,
                      busy: _busy,
                      onSelected: (item, selected) {
                        widget.session.setProposalItemSelected(
                          item.taskId,
                          selected,
                        );
                        _refresh();
                      },
                      onApply: _applyProposal,
                      onDismiss: _dismissProposal,
                      onRefresh: _createProposal,
                    ),
                  if (_selectedIds.isNotEmpty)
                    _SelectionBar(
                      count: _selectedIds.length,
                      busy: _busy,
                      onSchedule: () => _schedule(_selectedIds.toList()),
                      onDefer: () async {
                        await _run(
                          widget.session.deferTasks(_selectedIds.toList()),
                        );
                        if (mounted) setState(_selectedIds.clear);
                      },
                      onClear: () => setState(_selectedIds.clear),
                    ),
                  Expanded(
                    child: wide
                        ? _WidePlan(
                            projection: projection,
                            selectedIds: _selectedIds,
                            onToggle: _toggle,
                            onComplete: _complete,
                            onSchedule: (id) => _schedule([id]),
                            onEstimate: _estimate,
                            onDefer: (id) =>
                                _run(widget.session.deferTasks([id])),
                            onRename: _rename,
                          )
                        : _PhonePlan(
                            projection: projection,
                            selectedIds: _selectedIds,
                            onToggle: _toggle,
                            onComplete: _complete,
                            onSchedule: (id) => _schedule([id]),
                            onEstimate: _estimate,
                            onDefer: (id) =>
                                _run(widget.session.deferTasks([id])),
                            onRename: _rename,
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  final PlanProposal proposal;
  final bool busy;
  final void Function(PlanProposalItem item, bool selected) onSelected;
  final VoidCallback onApply;
  final VoidCallback onDismiss;
  final VoidCallback onRefresh;

  const _ProposalCard({
    required this.proposal,
    required this.busy,
    required this.onSelected,
    required this.onApply,
    required this.onDismiss,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final stale = proposal.state == PlanProposalState.stale;
    return Card(
      key: const Key('plan-proposal'),
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 2),
      color: const Color(0xE62B211D),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: PlenaraTheme.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stale ? 'This proposal is stale' : proposal.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${proposal.scheduledMinutes} min',
                  style: const TextStyle(color: PlenaraTheme.quietInk),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              stale
                  ? proposal.message ??
                        'The plan changed. Refresh before applying.'
                  : '${proposal.items.length} proposed changes • conflicts ${proposal.conflictsBefore} → ${proposal.conflictsAfter}',
              style: const TextStyle(color: PlenaraTheme.quietInk),
            ),
            if (!stale)
              for (var index = 0; index < proposal.items.length; index++)
                CheckboxListTile(
                  key: Key('proposal-item-$index'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: proposal.items[index].selected,
                  onChanged: busy
                      ? null
                      : (value) =>
                            onSelected(proposal.items[index], value ?? false),
                  title: Text('${index + 1}. ${proposal.items[index].title}'),
                  subtitle: Text(
                    '${_shortDateTime(proposal.items[index].proposedStartAt)} • ${proposal.items[index].rationale}',
                  ),
                ),
            if (!stale && proposal.omissions.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text(
                'Left out',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final omission in proposal.omissions)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• $omission',
                    style: const TextStyle(color: PlenaraTheme.quietInk),
                  ),
                ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : onDismiss,
                  child: const Text('Dismiss'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  key: Key(stale ? 'refresh-proposal' : 'apply-proposal'),
                  onPressed: busy ? null : (stale ? onRefresh : onApply),
                  child: Text(stale ? 'Refresh' : 'Apply selected'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekSelector extends StatelessWidget {
  final List<PlanDaySummary> days;
  final DateTime selected;
  final bool wide;
  final ValueChanged<DateTime> onSelected;
  final void Function(String id, DateTime day) onDrop;

  const _WeekSelector({
    required this.days,
    required this.selected,
    required this.wide,
    required this.onSelected,
    required this.onDrop,
  });

  @override
  Widget build(BuildContext context) {
    Widget day(PlanDaySummary item) => DragTarget<String>(
      onAcceptWithDetails: (details) => onDrop(details.data, item.day),
      builder: (context, candidates, _) => InkWell(
        key: Key('plan-day-${_dateKey(item.day)}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => onSelected(item.day),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _sameDay(item.day, selected)
                ? const Color(0x33E9A58B)
                : candidates.isNotEmpty
                ? const Color(0x224AB58B)
                : const Color(0x10FFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: item.conflictCount > 0 || item.overloaded
                  ? const Color(0x99FFC2A8)
                  : const Color(0x16FFFFFF),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _weekday(item.day),
                style: const TextStyle(color: PlenaraTheme.quietInk),
              ),
              Text(
                '${item.day.day}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                item.scheduledMinutes == 0 && item.unknownEstimateCount == 0
                    ? 'clear'
                    : '${_hours(item.scheduledMinutes)}${item.unknownEstimateCount == 0 ? '' : ' + ?'}',
                style: TextStyle(
                  fontSize: 11,
                  color: item.overloaded || item.conflictCount > 0
                      ? const Color(0xFFFFC2A8)
                      : PlenaraTheme.quietInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            for (final item in days)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: day(item),
                ),
              ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 96,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) => SizedBox(width: 66, child: day(days[index])),
      ),
    );
  }
}

class _PhonePlan extends StatelessWidget {
  final PlanProjection projection;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onComplete;
  final ValueChanged<String> onSchedule;
  final ValueChanged<String> onEstimate;
  final ValueChanged<String> onDefer;
  final ValueChanged<String> onRename;

  const _PhonePlan({
    required this.projection,
    required this.selectedIds,
    required this.onToggle,
    required this.onComplete,
    required this.onSchedule,
    required this.onEstimate,
    required this.onDefer,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('phone-plan'),
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 130),
    children: [
      if (projection.conflicts.isNotEmpty)
        _ConflictCard(conflicts: projection.conflicts),
      _PlanSection(
        title: 'Agenda',
        empty: 'Nothing scheduled.',
        items: projection.agenda,
        selectedIds: selectedIds,
        onToggle: onToggle,
        onComplete: onComplete,
        onSchedule: onSchedule,
        onEstimate: onEstimate,
        onDefer: onDefer,
        onRename: onRename,
      ),
      _PlanSection(
        title: 'Deadlines',
        empty: 'No deadlines this day.',
        items: projection.deadlines,
        selectedIds: selectedIds,
        onToggle: onToggle,
        onComplete: onComplete,
        onSchedule: onSchedule,
        onEstimate: onEstimate,
        onDefer: onDefer,
        onRename: onRename,
      ),
      _PlanSection(
        title: 'Unscheduled',
        empty: 'The queue is clear.',
        items: projection.unscheduled,
        selectedIds: selectedIds,
        onToggle: onToggle,
        onComplete: onComplete,
        onSchedule: onSchedule,
        onEstimate: onEstimate,
        onDefer: onDefer,
        onRename: onRename,
      ),
    ],
  );
}

class _WidePlan extends StatelessWidget {
  final PlanProjection projection;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onComplete;
  final ValueChanged<String> onSchedule;
  final ValueChanged<String> onEstimate;
  final ValueChanged<String> onDefer;
  final ValueChanged<String> onRename;

  const _WidePlan({
    required this.projection,
    required this.selectedIds,
    required this.onToggle,
    required this.onComplete,
    required this.onSchedule,
    required this.onEstimate,
    required this.onDefer,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) => Row(
    key: const Key('desktop-plan'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 2,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 10, 130),
          children: [
            if (projection.conflicts.isNotEmpty)
              _ConflictCard(conflicts: projection.conflicts),
            _PlanSection(
              title: 'Agenda',
              empty: 'Nothing scheduled.',
              items: projection.agenda,
              selectedIds: selectedIds,
              onToggle: onToggle,
              onComplete: onComplete,
              onSchedule: onSchedule,
              onEstimate: onEstimate,
              onDefer: onDefer,
              onRename: onRename,
              draggable: true,
            ),
            _PlanSection(
              title: 'Deadlines',
              empty: 'No deadlines this day.',
              items: projection.deadlines,
              selectedIds: selectedIds,
              onToggle: onToggle,
              onComplete: onComplete,
              onSchedule: onSchedule,
              onEstimate: onEstimate,
              onDefer: onDefer,
              onRename: onRename,
              draggable: true,
            ),
          ],
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 18, 20, 130),
          children: [
            _PlanSection(
              title: 'Unscheduled queue',
              empty: 'The queue is clear.',
              items: projection.unscheduled,
              selectedIds: selectedIds,
              onToggle: onToggle,
              onComplete: onComplete,
              onSchedule: onSchedule,
              onEstimate: onEstimate,
              onDefer: onDefer,
              onRename: onRename,
              draggable: true,
            ),
          ],
        ),
      ),
    ],
  );
}

class _PlanSection extends StatelessWidget {
  final String title;
  final String empty;
  final List<PlanTaskItem> items;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onComplete;
  final ValueChanged<String> onSchedule;
  final ValueChanged<String> onEstimate;
  final ValueChanged<String> onDefer;
  final ValueChanged<String> onRename;
  final bool draggable;

  const _PlanSection({
    required this.title,
    required this.empty,
    required this.items,
    required this.selectedIds,
    required this.onToggle,
    required this.onComplete,
    required this.onSchedule,
    required this.onEstimate,
    required this.onDefer,
    required this.onRename,
    this.draggable = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              empty,
              style: const TextStyle(color: PlenaraTheme.quietInk),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  _maybeDraggable(
                    _PlanRow(
                      item: items[index],
                      selected: selectedIds.contains(items[index].id),
                      onToggle: onToggle,
                      onComplete: onComplete,
                      onSchedule: onSchedule,
                      onEstimate: onEstimate,
                      onDefer: onDefer,
                      onRename: onRename,
                    ),
                    items[index],
                  ),
                  if (index != items.length - 1)
                    const Divider(height: 1, indent: 52),
                ],
              ],
            ),
          ),
      ],
    ),
  );

  Widget _maybeDraggable(Widget child, PlanTaskItem item) {
    if (!draggable || item.kind != PlannerItemKind.task) return child;
    return LongPressDraggable<String>(
      data: item.id,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(item.title),
            ),
          ),
        ),
      ),
      child: child,
    );
  }
}

class _PlanRow extends StatelessWidget {
  final PlanTaskItem item;
  final bool selected;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onComplete;
  final ValueChanged<String> onSchedule;
  final ValueChanged<String> onEstimate;
  final ValueChanged<String> onDefer;
  final ValueChanged<String> onRename;

  const _PlanRow({
    required this.item,
    required this.selected,
    required this.onToggle,
    required this.onComplete,
    required this.onSchedule,
    required this.onEstimate,
    required this.onDefer,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final task = item.kind == PlannerItemKind.task;
    final details = <String>[
      if (item.scheduledStartAt != null) _time(item.scheduledStartAt!),
      if (item.dueAt != null) 'deadline ${_shortDate(item.dueAt!)}',
      if (item.estimatedMinutes != null) '${item.estimatedMinutes} min',
      if (item.priority != 'none') item.priority,
      if (item.energy != null) '${item.energy} energy',
      for (final context in item.contexts) '#$context',
      if (item.recurrence != null) item.recurrence!,
      if (item.blocked) item.blockedReason ?? 'blocked',
    ];
    return ListTile(
      key: Key('plan-item-${item.id}'),
      selected: selected,
      leading: task
          ? Checkbox(
              value: selected,
              onChanged: (_) => onToggle(item.id),
              semanticLabel: 'Select ${item.title}',
            )
          : const Icon(Icons.notifications_none_rounded),
      title: Text(item.title),
      subtitle: details.isEmpty
          ? null
          : Text(
              details.join(' · '),
              style: TextStyle(
                color: item.blocked
                    ? const Color(0xFFFFC2A8)
                    : PlenaraTheme.quietInk,
              ),
            ),
      onLongPress: task ? () => onToggle(item.id) : null,
      trailing: task
          ? PopupMenuButton<String>(
              tooltip: 'Plan ${item.title}',
              onSelected: (action) => switch (action) {
                'complete' => onComplete(item.id),
                'schedule' => onSchedule(item.id),
                'estimate' => onEstimate(item.id),
                'defer' => onDefer(item.id),
                _ => onRename(item.id),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'complete', child: Text('Complete')),
                PopupMenuItem(value: 'schedule', child: Text('Schedule')),
                PopupMenuItem(value: 'estimate', child: Text('Set estimate')),
                PopupMenuItem(value: 'defer', child: Text('Defer')),
                PopupMenuItem(value: 'rename', child: Text('Rename')),
              ],
            )
          : null,
    );
  }
}

class _ConflictCard extends StatelessWidget {
  final List<PlanConflict> conflicts;
  const _ConflictCard({required this.conflicts});

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xD92B1B16),
    margin: const EdgeInsets.only(bottom: 18),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Timing conflict',
            style: TextStyle(color: Color(0xFFFFC2A8)),
          ),
          const SizedBox(height: 4),
          for (final conflict in conflicts) Text(conflict.message),
        ],
      ),
    ),
  );
}

class _SelectionBar extends StatelessWidget {
  final int count;
  final bool busy;
  final VoidCallback onSchedule;
  final VoidCallback onDefer;
  final VoidCallback onClear;

  const _SelectionBar({
    required this.count,
    required this.busy,
    required this.onSchedule,
    required this.onDefer,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xF0221917),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text('$count selected')),
          TextButton(
            onPressed: busy ? null : onSchedule,
            child: const Text('Schedule'),
          ),
          TextButton(
            onPressed: busy ? null : onDefer,
            child: const Text('Defer'),
          ),
          IconButton(
            tooltip: 'Clear selection',
            onPressed: busy ? null : onClear,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    ),
  );
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String _dateKey(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
String _weekday(DateTime day) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day.weekday - 1];
String _longDate(DateTime day) =>
    '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][day.month - 1]} ${day.day}';
String _shortDate(DateTime day) => '${_weekday(day)} ${day.day}';
String _shortDateTime(DateTime at) => '${_shortDate(at)} at ${_time(at)}';
String _hours(int minutes) => minutes < 60
    ? '${minutes}m'
    : minutes % 60 == 0
    ? '${minutes ~/ 60}h'
    : '${minutes ~/ 60}h ${minutes % 60}m';
String _time(DateTime at) {
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final minute = at.minute == 0
      ? ''
      : ':${at.minute.toString().padLeft(2, '0')}';
  return '$hour$minute ${at.hour < 12 ? 'AM' : 'PM'}';
}
