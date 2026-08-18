import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/planner.dart';
import 'package:plenara/plan_proposal.dart';
import 'package:plenara/planning_artifact.dart';
import 'package:plenara/session.dart';
import 'package:plenara/weekly_review.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final now = DateTime.parse('2026-08-17T09:00:00');

class _NoCloud implements CloudClient {
  int routeCalls = 0;

  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
      String utterance, Map<String, Map<String, dynamic>> skills,
      {Set<String> knownContacts = const {}}) async {
    routeCalls++;
    return const CloudError(CloudErrorKind.noKey);
  }

  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(
          String description,
          {String? priorError}) async =>
      const CloudError(CloudErrorKind.noKey);
  @override
  Future<CloudResult<String>> generate(String kind, String context) async =>
      const CloudError(CloudErrorKind.noKey);
}

class _DeferredCloud implements CloudClient {
  final started = Completer<void>();
  final result = Completer<CloudResult<String>>();

  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
          String utterance, Map<String, Map<String, dynamic>> skills,
          {Set<String> knownContacts = const {}}) async =>
      const CloudError(CloudErrorKind.noKey);

  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(
          String description,
          {String? priorError}) async =>
      const CloudError(CloudErrorKind.noKey);

  @override
  Future<CloudResult<String>> generate(String kind, String context) {
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

void main() {
  test(
      'Today distinguishes overdue, scheduled, deadline, later, and relationship state',
      () {
    final projection = buildTodayProjection({
      'overdue': {
        'id': 'overdue',
        'typeId': 'task',
        'description': 'File paperwork',
        'dueAt': '2026-08-16',
        'status': 'inbox',
      },
      'scheduled': {
        'id': 'scheduled',
        'typeId': 'task',
        'description': 'School pickup',
        'scheduledStartAt': '2026-08-17T09:15:00',
        'dueAt': '2026-08-18',
        'status': 'today',
      },
      'later': {
        'id': 'later',
        'typeId': 'task',
        'description': 'Call accountant',
        'dueAt': '2026-08-20',
        'status': 'scheduled',
      },
      'contact': {
        'id': 'contact',
        'typeId': 'contact',
        'displayName': 'Mia',
        'birthday': '2014-08-19',
      },
    }, now);

    expect(projection.now.single.title, 'School pickup');
    expect(projection.now.single.detail, contains('Scheduled today · 9:15 AM'));
    expect(projection.next.single.title, 'File paperwork');
    expect(projection.next.single.overdue, isTrue);
    expect(projection.later.single.title, 'Call accountant');
    expect(projection.relationshipNudge!.title, "Mia's birthday");
    expect(projection.relationshipNudge!.detail, 'In 2 days');
    expect(projection.inboxCount, 1);
  });

  test('direct planner completion is durable, visible, and targeted-undoable',
      () async {
    final data = makeTempDataDir();
    addTearDown(() => Directory(data).deleteSync(recursive: true));
    final device =
        Directory.systemTemp.createTempSync('plenara_planner_direct_').path;
    addTearDown(() => Directory(device).deleteSync(recursive: true));
    final session =
        Session(data, deviceDir: device, clock: now, cloud: _NoCloud());
    await session.init(retrieval: false);
    await session.handle('add buy milk to my list');
    final id = session.store.values.single['id'] as String;

    final completed = await session.completeTask(id);

    expect(completed.ok, isTrue);
    expect(session.store[id]!['status'], 'done');
    expect(session.store[id]!['completedAt'], now.toIso8601String());
    expect(session.todayProjection().latestChange!.description,
        'completed "buy milk"');
    expect(await session.undoById(completed.undoId!), contains('Undone'));
    expect(session.store[id]!['completed'], isFalse);

    final reopened =
        Session(data, deviceDir: device, clock: now, cloud: _NoCloud());
    await reopened.init(retrieval: false);
    expect(reopened.store[id]!['completed'], isFalse);
    expect(reopened.conversationLedger.entries.length, 1,
        reason: 'the spoken capture/reply remains findable after relaunch');
    expect(reopened.conversationLedger.entries.single.utterance,
        'add buy milk to my list');
    expect(
        reopened.conversationLedger.entries.single.reply, contains('buy milk'));
  });

  test('Plan separates agenda, deadlines, queue, load, and conflicts', () {
    final projection = buildPlanProjection({
      'pickup': {
        'id': 'pickup',
        'typeId': 'task',
        'description': 'School pickup',
        'scheduledStartAt': '2026-08-17T10:00:00',
        'estimatedMinutes': 60,
        'status': 'scheduled',
      },
      'call': {
        'id': 'call',
        'typeId': 'task',
        'description': 'Call accountant',
        'scheduledStartAt': '2026-08-17T10:30:00',
        'estimatedMinutes': 30,
        'status': 'scheduled',
      },
      'deadline': {
        'id': 'deadline',
        'typeId': 'task',
        'description': 'File paperwork',
        'dueAt': '2026-08-17',
        'priority': 'high',
        'status': 'today',
      },
      'inbox': {
        'id': 'inbox',
        'typeId': 'task',
        'description': 'Buy milk',
        'status': 'inbox',
      },
      'blocked': {
        'id': 'blocked',
        'typeId': 'task',
        'description': 'Send paperwork',
        'dependencyRefs': ['deadline'],
        'energy': 'low',
        'contexts': ['home', 'phone'],
        'recurrence': 'every Friday',
        'status': 'inbox',
      },
    }, DateTime.parse('2026-08-17T09:00:00'), selectedDay: now);

    expect(projection.agenda.map((item) => item.id), ['pickup', 'call']);
    expect(projection.deadlines.single.id, 'deadline');
    expect(projection.unscheduled.map((item) => item.id),
        containsAll(['inbox', 'blocked']));
    expect(
      projection.unscheduled
          .singleWhere((item) => item.id == 'blocked')
          .blocked,
      isTrue,
    );
    final blocked =
        projection.unscheduled.singleWhere((item) => item.id == 'blocked');
    expect(blocked.energy, 'low');
    expect(blocked.contexts, ['home', 'phone']);
    expect(blocked.recurrence, 'every Friday');
    expect(
        projection.days
            .singleWhere((day) => day.day.day == 17)
            .scheduledMinutes,
        90);
    expect(projection.conflicts.single.recordIds, ['pickup', 'call']);
  });

  test('multi-select scheduling is one durable execution and one undo',
      () async {
    final data = makeTempDataDir();
    addTearDown(() => Directory(data).deleteSync(recursive: true));
    final device =
        Directory.systemTemp.createTempSync('plenara_plan_batch_').path;
    addTearDown(() => Directory(device).deleteSync(recursive: true));
    final session =
        Session(data, deviceDir: device, clock: now, cloud: _NoCloud());
    await session.init(retrieval: false);
    await session.handle('add write proposal to my list');
    await session.handle('add call Sam to my list');
    final byTitle = {
      for (final record in session.store.values)
        '${record['description']}': '${record['id']}',
    };
    expect(
      (await session.resizeTask(byTitle['write proposal']!, 45)).ok,
      isTrue,
    );

    final result = await session.scheduleTasks(
      [byTitle['write proposal']!, byTitle['call Sam']!],
      DateTime.parse('2026-08-18T10:00:00'),
    );

    expect(result.ok, isTrue);
    expect(
      session.store[byTitle['write proposal']]!['scheduledStartAt'],
      '2026-08-18T10:00:00.000',
    );
    expect(
      session.store[byTitle['call Sam']]!['scheduledStartAt'],
      '2026-08-18T10:45:00.000',
    );
    expect(
        session.planProjection(DateTime.parse('2026-08-18')).agenda.length, 2);
    expect(await session.undoById(result.undoId!), contains('Undone'));
    expect(
        session.store[byTitle['write proposal']]!
            .containsKey('scheduledStartAt'),
        isFalse);
    expect(session.store[byTitle['call Sam']]!.containsKey('scheduledStartAt'),
        isFalse);
  });

  test(
      'contextual planner voice targets the visible selection deterministically',
      () async {
    final data = makeTempDataDir();
    addTearDown(() => Directory(data).deleteSync(recursive: true));
    final device =
        Directory.systemTemp.createTempSync('plenara_plan_voice_').path;
    addTearDown(() => Directory(device).deleteSync(recursive: true));
    final session =
        Session(data, deviceDir: device, clock: now, cloud: _NoCloud());
    await session.init(retrieval: false);
    await session.handle('add write proposal to my list');
    await session.handle('add call Sam to my list');
    final ids = session.store.values
        .where((record) => record['typeId'] == 'task')
        .map((record) => '${record['id']}')
        .toList();
    session.setPlannerContext(PlannerContext(
      visibleStart: now,
      visibleEnd: now.add(const Duration(days: 7)),
      selectedDay: now,
      selectedRecordIds: ids,
      visibleRecordIds: ids,
    ));

    final reply = await session.handle('move these to tomorrow at 10am');

    expect(reply, contains('Updated 2 tasks together'));
    expect(session.lastSource, 'planner-context');
    expect(
        session.store[ids[0]]!['scheduledStartAt'], '2026-08-18T10:00:00.000');
    expect(
        session.store[ids[1]]!['scheduledStartAt'], '2026-08-18T10:30:00.000');
    expect(session.conversationLedger.entries.last.source, 'planner-context');

    expect(await session.handle('make the first one 45 minutes'),
        contains('Updated'));
    expect(session.store[ids[0]]!['estimatedMinutes'], 45);
  });

  test('in-process retrieval routes a held-out task phrasing before cloud',
      () async {
    final data = makeTempDataDir();
    addTearDown(() => Directory(data).deleteSync(recursive: true));
    final cloud = _NoCloud();
    final session = Session(data, clock: now, cloud: cloud);
    await session.init();

    const cases = {
      'capture a task to book the dentist': 'book the dentist',
      'jot down a todo to renew the passport': 'renew the passport',
      'note down a task to call the school': 'call the school',
      'record a task to replace the filter': 'replace the filter',
    };
    for (final entry in cases.entries) {
      final reply = await session.handle(entry.key);
      expect(reply, contains(entry.value), reason: entry.key);
      expect(session.lastSource, 'retrieval', reason: entry.key);
    }

    expect(cloud.routeCalls, 0);
    expect(
        session.store.values
            .where((record) => record['typeId'] == 'task')
            .map((record) => record['description']),
        containsAll(cases.values));

    await session.handle('capture a note about quantum physics');
    expect(
      session.store.values
          .where((record) => record['typeId'] == 'task')
          .map((record) => record['description']),
      isNot(contains('a note about quantum physics')),
      reason: 'retrieval never acts without the candidate-specific task cue',
    );
  });

  test(
      'weekly proposal previews, refines by voice, applies once, and undoes once',
      () async {
    final data = makeTempDataDir();
    addTearDown(() => Directory(data).deleteSync(recursive: true));
    final device =
        Directory.systemTemp.createTempSync('plenara_plan_proposal_').path;
    addTearDown(() => Directory(device).deleteSync(recursive: true));
    final session =
        Session(data, deviceDir: device, clock: now, cloud: _NoCloud());
    await session.init(retrieval: false);
    await session.handle('add write proposal to my list');
    await session.handle('add call Sam to my list');
    final ids = session.store.values
        .where((record) => record['typeId'] == 'task')
        .map((record) => '${record['id']}')
        .toList();

    final preview = await session.handle('plan my week');

    expect(preview, contains('without applying'));
    expect(session.activePlanProposal!.state, PlanProposalState.draft);
    expect(session.store[ids.first]!.containsKey('scheduledStartAt'), isFalse);
    final firstProposalId = session.activePlanProposal!.items.first.taskId;
    final secondProposalId = session.activePlanProposal!.items[1].taskId;
    expect(await session.handle('move the first one to tomorrow at 11am'),
        contains('Nothing has been applied'));
    expect(await session.handle('remove the second one'),
        contains('Nothing has been applied'));
    final applied = await session.handle('apply the proposal');
    expect(applied, contains('Updated'));
    expect(session.activePlanProposal!.state, PlanProposalState.applied);
    expect(session.store[firstProposalId]!['scheduledStartAt'],
        '2026-08-18T11:00:00.000');
    expect(session.store[secondProposalId]!.containsKey('scheduledStartAt'),
        isFalse);
    final execution = session.executions.completed.last;
    expect(execution.origin, 'planner-proposal');
    expect(await session.undoById(execution.id), contains('Undone'));
    expect(session.store[firstProposalId]!.containsKey('scheduledStartAt'),
        isFalse);
  });

  test('a stale proposal fails before any write and survives relaunch',
      () async {
    final data = makeTempDataDir();
    addTearDown(() => Directory(data).deleteSync(recursive: true));
    final device =
        Directory.systemTemp.createTempSync('plenara_plan_stale_').path;
    addTearDown(() => Directory(device).deleteSync(recursive: true));
    final session =
        Session(data, deviceDir: device, clock: now, cloud: _NoCloud());
    await session.init(retrieval: false);
    await session.handle('add write proposal to my list');
    await session.handle('plan my week');
    final id = session.activePlanProposal!.items.single.taskId;
    await session.resizeTask(id, 75);

    final result = await session.applyPlanProposal();

    expect(result.ok, isFalse);
    expect(result.message, contains('nothing was applied'));
    expect(session.store[id]!.containsKey('scheduledStartAt'), isFalse);
    expect(session.activePlanProposal!.state, PlanProposalState.stale);
    final reopened =
        Session(data, deviceDir: device, clock: now, cloud: _NoCloud());
    await reopened.init(retrieval: false);
    expect(reopened.activePlanProposal!.state, PlanProposalState.stale);
  });

  test(
      'detached synthesis leaves local capture available while cloud is running',
      () async {
    final data = makeTempDataDir();
    addTearDown(() => Directory(data).deleteSync(recursive: true));
    final cloud = _DeferredCloud();
    final session = Session(data, clock: now, cloud: cloud);
    await session.init(retrieval: false);
    await session.handle('add finish taxes to my list');
    final firstId = '${session.store.values.single['id']}';
    await session.completeTask(firstId);

    final startedReply = await session.handle('how was my week');
    expect(startedReply, contains('keep capturing'));
    await cloud.started.future;

    final capture = await session.handle('add call the school to my list');
    expect(capture, contains('call the school'));
    cloud.result.complete(const CloudOk('A finished weekly review'));
    final operation = await session.operations.wait(
      session.operations.records.single.id,
    );
    expect(operation.result, 'A finished weekly review');
    expect(session.operations.takeDeliveries(), hasLength(1));
    expect(session.operations.takeDeliveries(), isEmpty);
    final traces = File('$data/turnlog.jsonl')
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>);
    expect(
      traces.any(
        (trace) =>
            trace['source'] == 'operation-completion' &&
            trace['operationKind'] == 'weekly_review',
      ),
      isTrue,
    );
  });

  test('weekly review decisions apply together and undo together', () async {
    final data = makeTempDataDir();
    addTearDown(() => Directory(data).deleteSync(recursive: true));
    final device =
        Directory.systemTemp.createTempSync('plenara_weekly_apply_').path;
    addTearDown(() => Directory(device).deleteSync(recursive: true));
    final session =
        Session(data, deviceDir: device, clock: now, cloud: _NoCloud());
    await session.init(retrieval: false);
    await session.handle('add write proposal to my list');
    await session.handle('add call Sam to my list');

    final reply = await session.handle('how was my week');
    expect(reply, contains('editable keep/defer/drop'));
    final review = session.activeWeeklyReview!;
    expect(review.state, WeeklyReviewState.draft);
    session.setWeeklyReviewDecision(
      review.items.first.recordId,
      ReviewDecision.keep,
    );
    final result = await session.applyWeeklyReview();

    expect(result.ok, isTrue);
    expect(session.activeWeeklyReview!.state, WeeklyReviewState.applied);
    expect(session.executions.completed.last.origin, 'weekly-review');
    expect(
      session.store[review.items.first.recordId]!['reviewDecision'],
      'keep',
    );
    expect(
      session.store[review.items.last.recordId]!['reviewDecision'],
      'defer',
    );
    expect(await session.undoById(result.undoId!), contains('Undone'));
    expect(
      session.store.values
          .where((record) => record['typeId'] == 'task')
          .every((record) => record['reviewDecision'] == null),
      isTrue,
    );
  });

  test('weekly review fails closed when reviewed plan state changed', () async {
    final data = makeTempDataDir();
    addTearDown(() => Directory(data).deleteSync(recursive: true));
    final session = Session(data, clock: now, cloud: _NoCloud());
    await session.init(retrieval: false);
    await session.handle('add write proposal to my list');
    final taskId = '${session.store.values.single['id']}';
    session.createWeeklyReview();
    await session.updateTaskPlans([
      TaskPlanPatch(id: taskId, estimatedMinutes: 30),
    ]);
    final executionsBeforeApply = session.executions.completed.length;

    final result = await session.applyWeeklyReview();

    expect(result.ok, isFalse);
    expect(result.message, contains('nothing was applied'));
    expect(session.activeWeeklyReview!.state, WeeklyReviewState.stale);
    expect(session.executions.completed.length, executionsBeforeApply);
    expect(session.store[taskId]!['reviewDecision'], isNull);
  });

  group('day windows and annual dates use calendar arithmetic (DST-immune)', () {
    Map<String, Map<String, dynamic>> birthdayOnly(String birthday) => {
          'mia': {
            'id': 'mia',
            'typeId': 'contact',
            'displayName': 'Mia',
            'birthday': birthday,
          },
        };

    test('a birthday tomorrow across the spring-forward night reads Tomorrow',
        () {
      final projection = buildTodayProjection(
          birthdayOnly('2014-03-08'), DateTime.parse('2026-03-07T09:00:00'));
      expect(projection.relationshipNudge!.detail, 'Tomorrow');
    });

    test('the 7-day week window does not leak an extra hour past a transition',
        () {
      // 2026-03-15 is exactly 7 days after 2026-03-08; the old
      // add(Duration(days: 7)) landed weekEnd at 01:00 on the 15th and let a
      // midnight occurrence leak in.
      final projection = buildTodayProjection(
          birthdayOnly('2014-03-15'), DateTime.parse('2026-03-08T09:00:00'));
      expect(projection.relationshipNudge, isNull);
    });

    test('a task due exactly 7 days out stays out of the week window', () {
      final projection = buildTodayProjection({
        'far': {
          'id': 'far',
          'typeId': 'task',
          'description': 'Renew insurance',
          'dueAt': '2026-03-15',
          'status': 'scheduled',
        },
      }, DateTime.parse('2026-03-08T09:00:00'));
      expect(projection.later, isEmpty);
      expect(projection.next, isEmpty);
    });

    test('a reminder 2 days out across the transition is labeled Mon, not tomorrow',
        () {
      final projection = buildTodayProjection({
        'rem': {
          'id': 'rem',
          'typeId': 'reminder',
          'text': 'Water plants',
          'remindAt': '2026-03-09T09:00:00',
        },
      }, DateTime.parse('2026-03-07T10:00:00'));
      expect(projection.later.single.detail, contains('Mon'));
      expect(projection.later.single.detail, isNot(contains('tomorrow')));
    });

    test('a Feb-29 birthday is observed on Feb 28 in common years everywhere',
        () {
      final records = birthdayOnly('2016-02-29');
      final nudge = buildTodayProjection(
              records, DateTime.parse('2026-02-27T09:00:00'))
          .relationshipNudge!;
      expect(nudge.detail, 'Tomorrow');
      expect(nudge.at, DateTime(2026, 2, 28));

      final commonAgenda = buildPlanProjection(records,
              DateTime.parse('2026-02-27T09:00:00'),
              selectedDay: DateTime.parse('2026-02-28'))
          .agenda;
      expect(commonAgenda.single.title, "Mia's birthday");

      final leapAgenda = buildPlanProjection(records,
              DateTime.parse('2028-02-27T09:00:00'),
              selectedDay: DateTime.parse('2028-02-29'))
          .agenda;
      expect(leapAgenda.single.title, "Mia's birthday",
          reason: 'a leap year keeps the real day');
      final leapFeb28 = buildPlanProjection(records,
              DateTime.parse('2028-02-27T09:00:00'),
              selectedDay: DateTime.parse('2028-02-28'))
          .agenda;
      expect(leapFeb28, isEmpty,
          reason: 'no double showing on Feb 28 in a leap year');
    });
  });

  group('overload signal scans today through the horizon only', () {
    Map<String, dynamic> task(String id, String? scheduledStartAt) => {
          'id': id,
          'typeId': 'task',
          'description': id,
          'status': 'scheduled',
          if (scheduledStartAt != null) 'scheduledStartAt': scheduledStartAt,
          'estimatedMinutes': 540,
          'createdAt': '2026-08-10T09:00:00',
        };

    test('a slipped past day never pins the overload signal', () {
      final signals = buildPlannerSignals(
          {'slipped': task('slipped', '2026-08-16T09:00:00')}, now);
      expect(signals.where((s) => s.kind == PlannerSignalKind.overload),
          isEmpty);
      expect(signals.map((s) => s.detail).join(),
          isNot(contains('overdue has')));
    });

    test('an overload today or later this week still signals coherently', () {
      final signals = buildPlannerSignals({
        'slipped': task('slipped', '2026-08-16T09:00:00'),
        'heavy': task('heavy', '2026-08-18T09:00:00'),
      }, now);
      final overload = signals
          .singleWhere((s) => s.kind == PlannerSignalKind.overload);
      expect(overload.detail, startsWith('tomorrow has'));
      expect(overload.recordIds, ['heavy']);
    });

    test('overload beyond the 7-day scan horizon is not signaled', () {
      final signals = buildPlannerSignals(
          {'far': task('far', '2026-08-27T09:00:00')}, now);
      expect(signals.where((s) => s.kind == PlannerSignalKind.overload),
          isEmpty);
    });
  });

  group('comparators are a total order (no filesystem-dependent ties)', () {
    Map<String, Map<String, dynamic>> tieRecords(List<String> order) {
      final defs = <String, Map<String, dynamic>>{
        'routine-a': {
          'id': 'routine-a',
          'typeId': 'routine',
          'title': 'Evening reset',
          'status': 'active',
        },
        'routine-b': {
          'id': 'routine-b',
          'typeId': 'routine',
          'title': 'Morning pages',
          'status': 'active',
        },
        'goal-a': {
          'id': 'goal-a',
          'typeId': 'goal',
          'description': 'Be present',
        },
        'goal-b': {
          'id': 'goal-b',
          'typeId': 'goal',
          'description': 'Read more',
        },
      };
      return {for (final id in order) id: defs[id]!};
    }

    test('Next/Later are identical for any record insertion order', () {
      // `now` is a Monday, so goals qualify; two routines + two goals all tie
      // on rank+time and only a stable id compare can order them.
      final forward = buildTodayProjection(
          tieRecords(['routine-a', 'routine-b', 'goal-a', 'goal-b']), now);
      final reversed = buildTodayProjection(
          tieRecords(['goal-b', 'goal-a', 'routine-b', 'routine-a']), now);
      expect(forward.next.map((i) => i.id).toList(),
          reversed.next.map((i) => i.id).toList());
      expect(forward.later.map((i) => i.id).toList(),
          reversed.later.map((i) => i.id).toList());
      expect(forward.next.map((i) => i.id), ['routine-a', 'routine-b', 'goal-a']);
    });

    test('Plan agenda ties break deterministically by id', () {
      Map<String, Map<String, dynamic>> reminders(List<String> order) {
        final defs = <String, Map<String, dynamic>>{
          'rem-a': {
            'id': 'rem-a',
            'typeId': 'reminder',
            'text': 'First',
            'remindAt': '2026-08-17T10:00:00',
          },
          'rem-b': {
            'id': 'rem-b',
            'typeId': 'reminder',
            'text': 'Second',
            'remindAt': '2026-08-17T10:00:00',
          },
        };
        return {for (final id in order) id: defs[id]!};
      }

      final forward = buildPlanProjection(reminders(['rem-a', 'rem-b']), now,
          selectedDay: now);
      final reversed = buildPlanProjection(reminders(['rem-b', 'rem-a']), now,
          selectedDay: now);
      expect(forward.agenda.map((i) => i.id).toList(), ['rem-a', 'rem-b']);
      expect(reversed.agenda.map((i) => i.id).toList(), ['rem-a', 'rem-b']);
    });
  });

  test('a past-scheduled task stays in Now with a coherent overdue label', () {
    // Kept behavior: a slipped scheduled task is still on your plate, so it
    // qualifies for Now. The label must read as overdue, not "Scheduled Overdue".
    final projection = buildTodayProjection({
      'slip': {
        'id': 'slip',
        'typeId': 'task',
        'description': 'Renew passport',
        'scheduledStartAt': '2026-08-13T10:00:00', // the previous Thursday
        'status': 'scheduled',
      },
    }, now);
    final item = projection.now.single;
    expect(item.detail, contains('Overdue — was scheduled Thu'));
    expect(item.detail, isNot(contains('Scheduled Overdue')));
  });

  group('Now reserves capacity so slipped work cannot hide today', () {
    Map<String, dynamic> scheduledTask(String id, String at) => {
          'id': id,
          'typeId': 'task',
          'description': id,
          'scheduledStartAt': at,
          'status': 'scheduled',
        };

    Map<String, Map<String, dynamic>> records(
      List<Map<String, dynamic>> defs, {
      bool reversed = false,
    }) {
      final ordered = reversed ? defs.reversed.toList() : defs;
      return {for (final def in ordered) '${def['id']}': def};
    }

    test('today keeps a place in Now when three older items have slipped', () {
      final projection = buildTodayProjection(
        records([
          scheduledTask('slip-mon', '2026-08-10T09:00:00'),
          scheduledTask('slip-tue', '2026-08-11T09:00:00'),
          scheduledTask('slip-wed', '2026-08-12T09:00:00'),
          scheduledTask('today-early', '2026-08-17T08:00:00'),
          scheduledTask('today-late', '2026-08-17T08:30:00'),
        ]),
        now,
      );
      final ids = projection.now.map((item) => item.id).toList();
      expect(ids, hasLength(3));
      expect(ids.where((id) => id.startsWith('today-')), isNotEmpty,
          reason: 'Now must answer "what am I doing right now"');
      // Allocation: current keeps min(count, 2) of the 3 slots, overdue takes
      // the remainder, and the leading overdue item is the most overdue.
      expect(ids, ['slip-mon', 'today-early', 'today-late']);
    });

    test('overdue may still fill Now when nothing is scheduled today', () {
      final projection = buildTodayProjection(
        records([
          scheduledTask('slip-mon', '2026-08-10T09:00:00'),
          scheduledTask('slip-tue', '2026-08-11T09:00:00'),
          scheduledTask('slip-wed', '2026-08-12T09:00:00'),
          scheduledTask('slip-thu', '2026-08-13T09:00:00'),
        ]),
        now,
      );
      expect(projection.now.map((item) => item.id).toList(),
          ['slip-mon', 'slip-tue', 'slip-wed']);
    });

    test('with no overdue items today fills Now in scheduled order', () {
      final projection = buildTodayProjection(
        records([
          scheduledTask('today-a', '2026-08-17T07:00:00'),
          scheduledTask('today-b', '2026-08-17T08:00:00'),
          scheduledTask('today-c', '2026-08-17T08:45:00'),
          scheduledTask('today-d', '2026-08-17T09:20:00'),
        ]),
        now,
      );
      expect(projection.now.map((item) => item.id).toList(),
          ['today-a', 'today-b', 'today-c']);
    });

    test('Now is identical for any record insertion order', () {
      final defs = [
        scheduledTask('overdue-a', '2026-08-14T09:00:00'),
        scheduledTask('overdue-b', '2026-08-14T09:00:00'),
        scheduledTask('current-a', '2026-08-17T08:00:00'),
        scheduledTask('current-b', '2026-08-17T08:00:00'),
      ];
      final forward = buildTodayProjection(records(defs), now);
      final backward =
          buildTodayProjection(records(defs, reversed: true), now);
      expect(forward.now.map((item) => item.id).toList(),
          backward.now.map((item) => item.id).toList());
      expect(forward.now.map((item) => item.id).toList(),
          ['overdue-a', 'current-a', 'current-b']);
    });
  });

  test('morning and relationship prep stay durable until explicitly resolved',
      () async {
    final data = makeTempDataDir();
    addTearDown(() => Directory(data).deleteSync(recursive: true));
    final device =
        Directory.systemTemp.createTempSync('plenara_artifacts_').path;
    addTearDown(() => Directory(device).deleteSync(recursive: true));
    final session =
        Session(data, deviceDir: device, clock: now, cloud: _NoCloud());
    await session.init(retrieval: false);
    await session.handle('add call Dad to my list');
    final taskId = '${session.store.values.single['id']}';
    await session.updateTaskPlans([
      TaskPlanPatch(id: taskId, scheduledStartAt: now),
    ]);

    expect(await session.handle('plan my morning'), contains('kept'));
    expect(
        session.activePlanningArtifacts.single.items.single.title, 'call Dad');

    final reopened =
        Session(data, deviceDir: device, clock: now, cloud: _NoCloud());
    await reopened.init(retrieval: false);
    expect(reopened.activePlanningArtifacts, hasLength(1));
    reopened.resolvePlanningArtifact(
      reopened.activePlanningArtifacts.single.id,
      accepted: true,
    );
    expect(reopened.activePlanningArtifacts, isEmpty);

    await reopened.handle('remember that Sam loves jazz');
    expect(await reopened.handle('prepare me for seeing Sam'),
        contains('prep card'));
    final prep = reopened.activePlanningArtifacts.single;
    expect(prep.kind, PlanningArtifactKind.relationshipPrep);
    expect(prep.items.map((item) => item.title), contains('loves jazz'));
  });
}
