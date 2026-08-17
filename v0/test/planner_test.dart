import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/planner.dart';
import 'package:plenara/session.dart';
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
}
