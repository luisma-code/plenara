import 'dart:io';

import 'package:plenara/plan_proposal.dart';
import 'package:test/test.dart';

Map<String, dynamic> task(
  String id,
  String title, {
  String? dueAt,
  int? estimate,
  String priority = 'none',
  String? scheduled,
}) =>
    {
      'id': id,
      'typeId': 'task',
      'description': title,
      'completed': false,
      'status': scheduled == null ? 'inbox' : 'scheduled',
      'priority': priority,
      'createdAt': '2026-08-01T09:00:00',
      if (dueAt != null) 'dueAt': dueAt,
      if (estimate != null) 'estimatedMinutes': estimate,
      if (scheduled != null) 'scheduledStartAt': scheduled,
    };

void main() {
  final now = DateTime.parse('2026-08-17T08:00:00');

  test(
      'weekly proposal orders deadlines, respects capacity, and makes no writes',
      () {
    final records = <String, Map<String, dynamic>>{
      'later': task('later', 'Later work', priority: 'low', estimate: 60),
      'due': task('due', 'Due soon', dueAt: '2026-08-18', estimate: 90),
      'fixed': task('fixed', 'Existing block',
          estimate: 420, scheduled: '2026-08-17T09:00:00'),
    };
    final before = records.map(
      (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
    );

    final proposal = buildWeeklyPlanProposal(records, now);

    expect(proposal.items.map((item) => item.taskId), ['due', 'later']);
    expect(proposal.items.first.proposedStartAt.day, 18,
        reason: 'Monday has only one hour after the existing block');
    expect(records, before, reason: 'preview creation must perform no writes');
    expect(proposal.conflictsAfter, 0);
  });

  test('blocked tasks are explained by omission rather than silently scheduled',
      () {
    final records = <String, Map<String, dynamic>>{
      'blocker': task('blocker', 'Finish research'),
      'blocked': {
        ...task('blocked', 'Write report'),
        'dependencyRefs': ['blocker'],
      },
    };

    final proposal = buildWeeklyPlanProposal(records, now);

    expect(proposal.items.map((item) => item.taskId), ['blocker']);
    expect(proposal.omissions.single, contains('dependency is unfinished'));
  });

  test('deterministic proposal benchmark needs no correction in at least 80%',
      () {
    final scenarios = <bool Function()>[
      () =>
          buildWeeklyPlanProposal({
            't': task('t', 'High', priority: 'high'),
          }, now)
              .items
              .single
              .taskId ==
          't',
      () =>
          buildWeeklyPlanProposal({
            't': task('t', 'Low', priority: 'low'),
          }, now)
              .items
              .single
              .taskId ==
          't',
      () => buildWeeklyPlanProposal({
            't': {...task('t', 'Done'), 'completed': true, 'status': 'done'},
          }, now)
              .items
              .isEmpty,
      () => buildWeeklyPlanProposal({
            't': task('t', 'Already planned', scheduled: '2026-08-18T09:00:00'),
          }, now)
              .items
              .isEmpty,
      () =>
          buildWeeklyPlanProposal({
            'a': task('a', 'Prerequisite'),
            'b': {
              ...task('b', 'Dependent'),
              'dependencyRefs': ['a']
            },
          }, now)
              .items
              .map((item) => item.taskId)
              .toList()
              .toString() ==
          '[a]',
      () {
        final proposal = buildWeeklyPlanProposal({
          't': {...task('t', 'Blocked'), 'blockedReason': 'Waiting on Sam'},
        }, now);
        return proposal.items.isEmpty &&
            proposal.omissions.single.contains('Waiting on Sam');
      },
      () {
        final proposal = buildWeeklyPlanProposal({
          't': task('t', 'Due tomorrow', dueAt: '2026-08-18', estimate: 60),
        }, now);
        return !proposal.items.single.proposedStartAt
            .isAfter(DateTime.parse('2026-08-18T23:59:59'));
      },
      () {
        final proposal = buildWeeklyPlanProposal({
          't': task('t', 'Overdue', dueAt: '2026-08-16', estimate: 30),
        }, now);
        return proposal.items.single.proposedStartAt.day == 17 &&
            proposal.items.single.rationale.contains('Deadline passed');
      },
      () {
        final proposal = buildWeeklyPlanProposal({
          't': task('t', 'Too large', estimate: 600),
        }, now, dailyCapacityMinutes: 480);
        return proposal.items.isEmpty &&
            proposal.omissions.single.contains('no remaining capacity');
      },
      () {
        final proposal = buildWeeklyPlanProposal({
          'fixed': task('fixed', 'Full Monday',
              estimate: 480, scheduled: '2026-08-17T09:00:00'),
          't': task('t', 'Next opening', estimate: 60),
        }, now);
        return proposal.items.single.proposedStartAt.day == 18;
      },
    ];

    final accepted = scenarios.where((scenario) => scenario()).length;
    expect(accepted / scenarios.length, greaterThanOrEqualTo(0.8));
  });

  test('proposal persists selected items and refinements across relaunch', () {
    final dir = Directory.systemTemp.createTempSync('plenara_proposal_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/proposal.json';
    final proposal = buildWeeklyPlanProposal({
      'one': task('one', 'One thing'),
    }, now);
    final refined = proposal.copyWith(items: [
      proposal.items.single.copyWith(
        selected: false,
        proposedStartAt: DateTime.parse('2026-08-19T11:00:00'),
      ),
    ]);
    PlanProposalStore(path: path).save(refined);

    final restored = PlanProposalStore(path: path).active!;

    expect(restored.items.single.selected, isFalse);
    expect(restored.items.single.proposedStartAt.hour, 11);
  });
}
