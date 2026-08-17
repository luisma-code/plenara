import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/planner.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final now = DateTime.parse('2026-08-17T09:00:00');

class _NoCloud implements CloudClient {
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
}
