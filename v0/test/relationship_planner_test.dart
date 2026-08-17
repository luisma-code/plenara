import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/plan_proposal.dart';
import 'package:plenara/planner.dart';
import 'package:plenara/planning_artifact.dart';
import 'package:plenara/session.dart';
import 'package:plenara/weekly_review.dart';
import 'package:test/test.dart';

import 'helpers.dart';

class _NoCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
    String utterance,
    Map<String, Map<String, dynamic>> skills, {
    Set<String> knownContacts = const {},
  }) async =>
      const CloudError(CloudErrorKind.noKey);

  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(
    String description, {
    String? priorError,
  }) async =>
      const CloudError(CloudErrorKind.noKey);

  @override
  Future<CloudResult<String>> generate(String kind, String context) async =>
      const CloudError(CloudErrorKind.noKey);
}

void main() {
  final now = DateTime.parse('2026-08-17T09:00:00');

  test('people-linked commitments keep context and win equal-risk plan ties',
      () {
    final records = <String, Map<String, dynamic>>{
      'mia': {
        'id': 'mia',
        'typeId': 'contact',
        'displayName': 'Mia',
      },
      'generic': {
        'id': 'generic',
        'typeId': 'task',
        'description': 'Sort receipts',
        'status': 'inbox',
        'priority': 'medium',
        'estimatedMinutes': 30,
        'createdAt': '2026-08-17T08:00:00',
      },
      'promise': {
        'id': 'promise',
        'typeId': 'task',
        'description': 'Call Mia about school',
        'status': 'inbox',
        'priority': 'medium',
        'estimatedMinutes': 30,
        'contactRefs': ['mia'],
        'createdAt': '2026-08-17T08:00:00',
      },
      'goal': {
        'id': 'goal',
        'typeId': 'goal',
        'description': 'Be present after work',
        'target': 4,
        'createdAt': '2026-08-01',
      },
      'routine': {
        'id': 'routine',
        'typeId': 'routine',
        'title': 'Evening reset',
        'kind': 'mobility',
        'status': 'active',
        'createdAt': '2026-08-01',
      },
      'plan': {
        'id': 'plan',
        'typeId': 'interaction',
        'subject': 'mia',
        'kind': 'Dinner',
        'at': '2026-08-19',
        'planned': true,
      },
    };

    final today = buildTodayProjection(records, now);
    final promise = today.next.singleWhere((item) => item.id == 'promise');
    expect(promise.detail, contains('For Mia'));
    expect(today.later.map((item) => item.id), contains('plan'));
    expect(today.next.map((item) => item.id), contains('goal'));

    final plan = buildPlanProjection(records, now, selectedDay: now);
    expect(
      plan.unscheduled
          .singleWhere((item) => item.id == 'promise')
          .relationshipContext,
      'Mia',
    );
    expect(
        plan.rhythms.map((item) => item.id), containsAll(['goal', 'routine']));
    final eventPlan = buildPlanProjection(
      records,
      now,
      selectedDay: DateTime.parse('2026-08-19'),
    );
    expect(
      eventPlan.agenda.singleWhere((item) => item.id == 'plan').title,
      'Dinner with Mia',
    );

    final proposal = buildWeeklyPlanProposal(records, now);
    expect(proposal.items.first.taskId, 'promise');
    expect(proposal.items.first.rationale, contains('commitment to Mia'));
    final review = buildWeeklyReviewArtifact(records, now);
    expect(
      review.items.singleWhere((item) => item.recordId == 'promise').evidence,
      contains('Commitment to Mia'),
    );
  });

  test('overload, stale queue, and neglect are bounded deterministic signals',
      () {
    final signals = buildPlannerSignals({
      'mia': {'id': 'mia', 'typeId': 'contact', 'displayName': 'Mia'},
      'old': {
        'id': 'old',
        'typeId': 'interaction',
        'subject': 'mia',
        'at': '2026-06-01',
      },
      'one': {
        'id': 'one',
        'typeId': 'task',
        'description': 'One',
        'status': 'scheduled',
        'scheduledStartAt': '2026-08-17T09:00:00',
        'estimatedMinutes': 300,
        'createdAt': '2026-08-01T09:00:00',
      },
      'two': {
        'id': 'two',
        'typeId': 'task',
        'description': 'Two',
        'status': 'scheduled',
        'scheduledStartAt': '2026-08-17T14:00:00',
        'estimatedMinutes': 240,
        'createdAt': '2026-08-01T09:00:00',
      },
      'stale': {
        'id': 'stale',
        'typeId': 'task',
        'description': 'Stale',
        'status': 'inbox',
        'createdAt': '2026-07-01T09:00:00',
      },
    }, now);

    expect(signals, hasLength(2), reason: 'Today never becomes a warning wall');
    expect(signals.map((signal) => signal.kind), [
      PlannerSignalKind.overload,
      PlannerSignalKind.staleQueue,
    ]);
    expect(
      buildPlannerSignals({
        'mia': {'id': 'mia', 'typeId': 'contact', 'displayName': 'Mia'},
        'old': {
          'id': 'old',
          'typeId': 'interaction',
          'subject': 'mia',
          'at': '2026-06-01',
        },
      }, now)
          .single
          .kind,
      PlannerSignalKind.relationshipNeglect,
    );
  });

  test('proactive relationship suggestion defers, returns, and never respawns',
      () async {
    final data = makeTempDataDir();
    final device = Directory.systemTemp.createTempSync('plenara_relationship_');
    addTearDown(() => Directory(data).deleteSync(recursive: true));
    addTearDown(() => device.deleteSync(recursive: true));

    final first = Session(
      data,
      deviceDir: device.path,
      clock: now,
      cloud: _NoCloud(),
    );
    await first.init(retrieval: false);
    await first.handle("Mia's birthday is august 19");
    first.todayProjection();

    final suggestion = first.activePlanningArtifacts.single;
    expect(suggestion.kind, PlanningArtifactKind.relationshipSuggestion);
    expect(first.plannerEngagement.suggestionsAccepted, 0,
        reason: 'an impression is not engagement');
    first.deferPlanningArtifact(suggestion.id);
    expect(first.activePlanningArtifacts, isEmpty);
    expect(first.plannerEngagement.suggestionsDeferred, 1);

    final tomorrow = Session(
      data,
      deviceDir: device.path,
      clock: now.add(const Duration(days: 1)),
      cloud: _NoCloud(),
    );
    await tomorrow.init(retrieval: false);
    expect(tomorrow.activePlanningArtifacts.single.id, suggestion.id);
    tomorrow.resolvePlanningArtifact(suggestion.id, accepted: false);
    expect(tomorrow.activePlanningArtifacts, isEmpty);
    expect(tomorrow.plannerEngagement.suggestionsDismissed, 1);

    final reopened = Session(
      data,
      deviceDir: device.path,
      clock: now.add(const Duration(days: 1)),
      cloud: _NoCloud(),
    );
    await reopened.init(retrieval: false);
    expect(reopened.activePlanningArtifacts, isEmpty);
    expect(
      reopened.planningArtifacts.history
          .where((artifact) => artifact.id == suggestion.id),
      hasLength(1),
    );
  });
}
