import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/planner.dart';
import 'package:plenara/session.dart';
import 'package:plenara_app/plenara_theme.dart';
import 'package:plenara_app/today_view.dart';

class _NoCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
    String utterance,
    Map<String, Map<String, dynamic>> skills, {
    Set<String> knownContacts = const {},
  }) async => const CloudError(CloudErrorKind.noKey);

  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(
    String description, {
    String? priorError,
  }) async => const CloudError(CloudErrorKind.noKey);

  @override
  Future<CloudResult<String>> generate(String kind, String context) async =>
      const CloudError(CloudErrorKind.noKey);
}

String _base(String path) => path.replaceAll('\\', '/').split('/').last;

Future<Session> _session() async {
  final root = Directory.systemTemp.createTempSync('plenara_today_ui_');
  for (final sub in const ['types', 'skills']) {
    final destination = Directory('${root.path}/$sub')
      ..createSync(recursive: true);
    for (final source in Directory(
      'assets/seed/$sub',
    ).listSync().whereType<File>()) {
      source.copySync('${destination.path}/${_base(source.path)}');
    }
  }
  File('assets/seed/corpus.json').copySync('${root.path}/corpus.json');
  Directory('${root.path}/records').createSync();
  final device = Directory('${root.path}/device')..createSync();
  final session = Session(
    root.path,
    deviceDir: device.path,
    clock: DateTime.parse('2026-08-17T09:00:00'),
    cloud: _NoCloud(),
  );
  await session.init(retrieval: false);
  addTearDown(() => root.deleteSync(recursive: true));
  return session;
}

Widget _board(Session session) => MaterialApp(
  theme: PlenaraTheme.dark,
  home: Scaffold(
    body: StatefulBuilder(
      builder: (context, setState) => TodayBoard(
        session: session,
        onChanged: () => setState(() {}),
        onOpenLibrary: () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('Today externalizes a captured task and completes it directly', (
    tester,
  ) async {
    final session = await _session();
    await session.handle('add buy milk to my list');
    final id = session.store.values.single['id'] as String;
    expect((await session.editField(id, 'status', 'today')).ok, isTrue);

    await tester.pumpWidget(_board(session));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('today-board')), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.byKey(Key('planner-$id')), findsOneWidget);
    expect(find.byTooltip('Talk to Plena'), findsOneWidget);

    await tester.tap(find.byTooltip('Complete buy milk'));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('planner-$id')), findsNothing);
    expect(find.byKey(const Key('latest-change')), findsOneWidget);
    expect(session.store[id]!['status'], 'done');
  });

  testWidgets('conversation history remains reachable from Today', (
    tester,
  ) async {
    final session = await _session();
    await session.handle('add call Dad to my list');

    await tester.pumpWidget(_board(session));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('latest-change')), findsOneWidget);
    await tester.tap(find.byKey(const Key('conversation-history')));
    await tester.pumpAndSettle();

    expect(find.text('Conversation history'), findsOneWidget);
    expect(find.text('add call Dad to my list'), findsOneWidget);
    expect(find.textContaining('Added'), findsWidgets);
    expect(find.text('Undo this action'), findsOneWidget);

    await tester.tap(find.text('Undo this action'));
    await tester.pumpAndSettle();
    expect(session.store, isEmpty);

    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();
    expect(find.text('Conversation history'), findsNothing);
    expect(find.byKey(const Key('latest-change')), findsNothing);
  });

  testWidgets('degraded durability is visible on Today', (tester) async {
    final session = await _session();
    // The public repair surface is what the widget consumes; corrupt-ledger byte
    // preservation itself is covered in the engine test.
    session.executionRepairIssues.add('execution_journal_corrupt');

    await tester.pumpWidget(_board(session));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('repair-needed')), findsOneWidget);
    expect(find.text('Some local data needs attention'), findsOneWidget);
  });

  testWidgets(
    'weekly review is editable and applies through one undoable action',
    (tester) async {
      final session = await _session();
      await session.handle('add buy milk to my list');
      await session.handle('add call Dad to my list');

      await tester.pumpWidget(_board(session));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('today-weekly-review')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('weekly-review-card')), findsOneWidget);
      expect(find.textContaining('Evidence-backed'), findsOneWidget);
      expect(find.byKey(const Key('review-decision-0')), findsOneWidget);

      await tester.tap(find.byKey(const Key('apply-weekly-review')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('weekly-review-card')), findsNothing);
      expect(session.executions.completed.last.origin, 'weekly-review');
      expect(
        session.store.values
            .where((record) => record['typeId'] == 'task')
            .every((record) => record['status'] == 'someday'),
        isTrue,
      );
    },
  );

  testWidgets('morning plan remains visible until accepted', (tester) async {
    final session = await _session();
    await session.handle('add call Dad to my list');
    final taskId = '${session.store.values.single['id']}';
    await session.updateTaskPlans([
      TaskPlanPatch(id: taskId, scheduledStartAt: session.now),
    ]);
    await tester.pumpWidget(_board(session));
    await tester.pumpAndSettle();

    final trigger = find.byKey(const Key('today-morning-plan'));
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('planning-artifact-morning')), findsOneWidget);
    expect(find.text('call Dad'), findsWidgets);
    await tester.tap(find.byKey(const Key('accept-artifact-morning')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('planning-artifact-morning')), findsNothing);
  });
}
