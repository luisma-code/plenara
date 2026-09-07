import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:plenara_app/habits_view.dart';
import 'package:plenara_app/main.dart';
import 'package:plenara_app/relationships_view.dart';

class _NoCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
    String utterance,
    Map<String, Map<String, dynamic>> skills, {
    Set<String> knownContacts = const {},
  }) async => const CloudOk(null);

  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(
    String description, {
    String? priorError,
  }) async => const CloudOk(null);

  @override
  Future<CloudResult<String>> generate(String kind, String context) async =>
      const CloudError(CloudErrorKind.noKey);
}

String _base(String path) => path.replaceAll('\\', '/').split('/').last;

Future<Session> _session() async {
  final seed = '${Directory.current.path}/assets/seed';
  final temp = Directory.systemTemp.createTempSync('plenara_three_pillars_');
  for (final sub in const ['types', 'skills']) {
    final destination = Directory('${temp.path}/$sub')
      ..createSync(recursive: true);
    for (final file in Directory('$seed/$sub').listSync().whereType<File>()) {
      file.copySync('${destination.path}/${_base(file.path)}');
    }
  }
  File('$seed/corpus.json').copySync('${temp.path}/corpus.json');
  Directory('${temp.path}/records').createSync();
  addTearDown(() => temp.deleteSync(recursive: true));
  final session = Session(
    temp.path,
    clock: DateTime.parse('2026-09-06T10:00:00'),
    cloud: _NoCloud(),
  );
  await session.init(retrieval: false);
  return session;
}

void main() {
  testWidgets('primary navigation is Relationships, Todos, and Habits', (
    tester,
  ) async {
    final session = await _session();
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: session)));
    await tester.pumpAndSettle();

    expect(find.text('Relationships'), findsOneWidget);
    expect(find.text('Todos'), findsOneWidget);
    expect(find.text('Habits'), findsOneWidget);
    expect(find.byKey(const Key('today-board')), findsOneWidget);

    await tester.tap(find.text('Relationships'));
    await tester.pumpAndSettle();
    expect(find.byType(RelationshipsView), findsOneWidget);

    await tester.tap(find.text('Habits'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitsView), findsOneWidget);
  });

  testWidgets('Todos adds a one-off item without turning it into a habit', (
    tester,
  ) async {
    final session = await _session();
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: session)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('todo-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('todo-description')),
      'Book the dentist',
    );
    await tester.tap(find.byKey(const Key('todo-due-today')));
    await tester.tap(find.byKey(const Key('todo-save')));
    await tester.pumpAndSettle();

    final task = session.store.values.singleWhere(
      (record) => record['typeId'] == 'task',
    );
    expect(task['description'], 'Book the dentist');
    expect(task['status'], 'today');
    expect(session.store.values.where((r) => r['typeId'] == 'habit'), isEmpty);
    expect(find.text('Book the dentist'), findsOneWidget);
  });

  testWidgets('Habits creates a weekly rhythm and checks it in from the UI', (
    tester,
  ) async {
    final session = await _session();
    await tester.pumpWidget(MaterialApp(home: HabitsView(session: session)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('habits-empty-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('habit-title')), 'Meditate');
    await tester.tap(find.byKey(const Key('habit-target-3')));
    await tester.tap(find.byKey(const Key('habit-save')));
    await tester.pumpAndSettle();

    final habit = session.store.values.singleWhere(
      (record) => record['typeId'] == 'habit',
    );
    expect(habit['targetPerWeek'], 3);
    expect(find.text('0 of 3 this week'), findsOneWidget);

    await tester.tap(find.byKey(Key('habit-check-${habit['id']}')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 this week'), findsOneWidget);
    expect(
      session.store.values.where((r) => r['typeId'] == 'habit_checkin'),
      hasLength(1),
    );
  });
}
