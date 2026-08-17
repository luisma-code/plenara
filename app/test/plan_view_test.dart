import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:plenara_app/library_home.dart';
import 'package:plenara_app/plan_view.dart';
import 'package:plenara_app/plenara_theme.dart';

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
  final root = Directory.systemTemp.createTempSync('plenara_plan_ui_');
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

Widget _app(Widget child) => MaterialApp(
  theme: PlenaraTheme.dark,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('phone Plan multi-select schedules through one durable action', (
    tester,
  ) async {
    final session = await _session();
    await session.handle('add write proposal to my list');
    await session.handle('add call Sam to my list');

    await tester.pumpWidget(
      _app(PlanBoard(session: session, onChanged: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('phone-plan')), findsOneWidget);
    expect(find.text('Unscheduled'), findsOneWidget);
    expect(find.text('write proposal'), findsOneWidget);
    expect(find.text('call Sam'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Select write proposal'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Select call Sam'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Start selected tasks'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final tasks = session.store.values.where(
      (record) => record['typeId'] == 'task',
    );
    expect(tasks.every((record) => record['status'] == 'scheduled'), isTrue);
    expect(tasks.every((record) => record['scheduledStartAt'] != null), isTrue);
    expect(
      session.todayProjection().latestChange!.description,
      'updated 2 tasks in the plan',
    );
  });

  testWidgets('Library provides purpose summaries before the generic browser', (
    tester,
  ) async {
    final session = await _session();
    session.store['contact-a'] = {
      'id': 'contact-a',
      'typeId': 'contact',
      'displayName': 'Mia',
    };
    String? opened;
    Set<String>? filter;

    await tester.pumpWidget(
      _app(
        LibraryHome(
          session: session,
          onOpen: (title, typeIds) {
            opened = title;
            filter = typeIds;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('library-home')), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Projects & areas'), findsOneWidget);
    expect(find.text('Learned phrases'), findsOneWidget);
    expect(find.text('All data'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-people')));
    expect(opened, 'People');
    expect(filter, contains('contact'));
  });
}
