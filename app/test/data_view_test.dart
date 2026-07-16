// Tests for the Spec 07 "Your data" view: the structural archetype inference (unit) and the
// view rendering + reachability (widget). Hermetic — an offline cloud, a temp data dir.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:plenara_app/data_view.dart';
import 'package:plenara_app/main.dart';

class _NullCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
    String u,
    Map<String, Map<String, dynamic>> s, {
    Set<String> knownContacts = const {},
  }) async => const CloudOk(null);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(
    String d, {
    String? priorError,
  }) async => const CloudOk(null);
  @override
  Future<CloudResult<String>> generate(String k, String c) async =>
      const CloudError(CloudErrorKind.noKey);
}

String _base(String p) => p.replaceAll('\\', '/').split('/').last;

// Seed data ships bundled at app/assets/seed (mirrored from v0/data by tool/sync_seed.sh). Resolve
// it relative to the package root — flutter test's cwd — so the helper is cross-platform (no dev
// machine path like the Windows `sourceDataDir` fallback).
String get _seedDir => '${Directory.current.path}/assets/seed';

String _tempData() {
  final tmp = Directory.systemTemp.createTempSync('plenara_dv_');
  for (final sub in const ['types', 'skills']) {
    final dst = Directory('${tmp.path}/$sub')..createSync(recursive: true);
    for (final f in Directory('$_seedDir/$sub').listSync().whereType<File>()) {
      f.copySync('${dst.path}/${_base(f.path)}');
    }
  }
  File('$_seedDir/corpus.json').copySync('${tmp.path}/corpus.json');
  Directory('${tmp.path}/records').createSync();
  return tmp.path;
}

Session _session() => Session(
  _tempData(),
  clock: DateTime.parse('2026-07-06T09:00:00'),
  cloud: _NullCloud(),
);

void main() {
  group(
    'archetypeFor — structural inference (Spec 07 §4, no per-type UI code)',
    () {
      Map<String, dynamic> t(List<Map<String, dynamic>> attrs) => {
        'attributes': attrs,
      };
      test('a type with a done/completed flag -> checklist', () {
        expect(
          archetypeFor(
            'task',
            t([
              {'name': 'description', 'valueType': 'text'},
              {'name': 'completed', 'valueType': 'boolean'},
            ]),
          ),
          Archetype.checklist,
        );
      });
      test('the contact type -> personCard', () {
        expect(
          archetypeFor(
            'contact',
            t([
              {'name': 'displayName', 'valueType': 'text'},
            ]),
          ),
          Archetype.personCard,
        );
      });
      test('a numeric measure + a date -> tracker', () {
        expect(
          archetypeFor(
            'step_log',
            t([
              {'name': 'count', 'valueType': 'number'},
              {'name': 'loggedAt', 'valueType': 'date'},
            ]),
          ),
          Archetype.tracker,
        );
      });
      test('a dated log with no number -> timeline', () {
        expect(
          archetypeFor(
            'journal_entry',
            t([
              {'name': 'text', 'valueType': 'text'},
              {'name': 'loggedAt', 'valueType': 'date'},
            ]),
          ),
          Archetype.timeline,
        );
      });
      test('no date/bool/number -> collection (the universal fallback)', () {
        expect(
          archetypeFor(
            'note',
            t([
              {'name': 'body', 'valueType': 'text'},
            ]),
          ),
          Archetype.collection,
        );
      });
    },
  );

  group('renderValue — per value-type formatting (Spec 07)', () {
    test(
      'date -> friendly label',
      () => expect(renderValue('2026-07-08', 'date'), 'Jul 8, 2026'),
    );
    test(
      'datetime -> label with 12h time',
      () => expect(
        renderValue('2026-07-08T17:05:00', 'datetime'),
        'Jul 8, 5:05 PM',
      ),
    );
    test('boolean -> check / cross', () {
      expect(renderValue(true, 'boolean'), '✓');
      expect(renderValue(false, 'boolean'), '✗');
    });
    test(
      'tag/list -> joined',
      () => expect(renderValue(['a', 'b'], 'tag'), 'a · b'),
    );
    test('null -> em dash', () => expect(renderValue(null, 'text'), '—'));
    test(
      'a number/text passes through',
      () => expect(renderValue(42, 'number'), '42'),
    );
  });

  testWidgets(
    'the data view opens from the chat and renders a task under a checklist archetype',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ChatScreen(session: _session(), retrieval: false)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'add buy milk to my list');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_horiz)); // open the discreet menu
      await tester.pumpAndSettle();
      await tester.tap(find.text('Your data'));
      await tester.pumpAndSettle();

      expect(find.text('Your data'), findsOneWidget);
      expect(
        find.byKey(const Key('archetype-task')),
        findsOneWidget,
      ); // the task section rendered
      expect(
        find.textContaining('checklist'),
        findsWidgets,
      ); // chosen by structure, not by type name
      expect(
        find.textContaining('buy milk'),
        findsWidgets,
      ); // the record itself
    },
  );

  testWidgets('tapping a record opens a detail sheet showing all its fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(session: _session(), retrieval: false)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'add buy milk to my list');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Your data'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(ListTile, 'buy milk'),
    ); // the task tile
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('record-detail')),
      findsOneWidget,
    ); // the detail sheet opened
    expect(
      find.text('createdAt'),
      findsOneWidget,
    ); // a field shown in detail but not in the checklist summary
  });

  testWidgets(
    'a task can be completed from the data view (actionable checklist)',
    (tester) async {
      final session = _session();
      await tester.pumpWidget(
        MaterialApp(home: ChatScreen(session: session, retrieval: false)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'add buy milk to my list');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Your data'));
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.radio_button_unchecked),
        findsOneWidget,
      ); // the incomplete task
      await tester.tap(find.byIcon(Icons.radio_button_unchecked));
      await tester.pumpAndSettle();

      final task = session.store.values.firstWhere(
        (r) => r['typeId'] == 'task',
      );
      expect(task['completed'], true); // completed through the turn engine
      expect(
        find.byIcon(Icons.check_circle),
        findsOneWidget,
      ); // and reflected in the UI
    },
  );

  testWidgets(
    'the data view surfaces an automations card with each automation status',
    (tester) async {
      final dir = _tempData();
      Directory('$dir/automations').createSync(recursive: true);
      File('$dir/automations/x.json').writeAsStringSync(
        jsonEncode({
          'automationId': 'demo-auto',
          'targetType': 'workout',
          'condition': {'kind': 'onWrite', 'afterField': 'date'},
          'skillId': 'demo',
          'description': 'a demo automation',
          'skill': {
            'skillId': 'demo',
            'inputs': [],
            'reads': ['workout'],
            'writes': [],
            'steps': {
              'main': [
                {'op': 'read_many', 'typeId': 'workout', 'into': 'w'},
                {
                  'op': 'compute',
                  'fn': 'count',
                  'args': [
                    {'var': 'w'},
                  ],
                  'into': 'n',
                },
                {
                  'op': 'format',
                  'template': '{n} workouts',
                  'into': 'confirmationText',
                },
              ],
            },
          },
        }),
      );
      final session = Session(
        dir,
        clock: DateTime.parse('2026-07-06T09:00:00'),
        cloud: _NullCloud(),
      );
      await tester.pumpWidget(
        MaterialApp(home: ChatScreen(session: session, retrieval: false)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Your data'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('automations-card')), findsOneWidget);
      expect(find.text('demo-auto'), findsOneWidget);
    },
  );

  testWidgets('an empty vault shows the empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(session: _session(), retrieval: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Your data'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing logged yet'), findsOneWidget);
  });

  Future<Session> openDataViewWithTask(WidgetTester tester) async {
    final session = _session();
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: session, retrieval: false)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'add buy milk to my list');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Your data'));
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('tap-to-edit a field commits through the engine (Spec 07 §5.5)', (tester) async {
    final session = await openDataViewWithTask(tester);
    await tester.tap(find.widgetWithText(ListTile, 'buy milk'));
    await tester.pumpAndSettle();
    // tap the description value to enter edit mode, change it, and save
    await tester.tap(find.widgetWithText(ListTile, 'description'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'buy oat milk');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    final task = session.store.values.firstWhere((r) => r['typeId'] == 'task');
    expect(task['description'], 'buy oat milk'); // persisted through session.editField
  });

  testWidgets('delete from the detail sheet removes the record with an UNDO snackbar', (tester) async {
    final session = await openDataViewWithTask(tester);
    await tester.tap(find.widgetWithText(ListTile, 'buy milk'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('record-delete')));
    await tester.pumpAndSettle();
    expect(session.store.values.where((r) => r['typeId'] == 'task'), isEmpty); // gone
    expect(find.text('UNDO'), findsOneWidget); // the safety-net snackbar
    await tester.tap(find.text('UNDO'));
    await tester.pumpAndSettle();
    expect(session.store.values.where((r) => r['typeId'] == 'task'), isNotEmpty); // restored
  });

  testWidgets('the Learned phrases card lists a learned flow and can forget it', (tester) async {
    final session = _session();
    await session.init(retrieval: false);
    session.router.addLearned('list-tasks', 'show my todo list');
    session.repo.appendCorpusLearned({'skillId': 'list-tasks', 'template': 'show my todo list'});
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: session, retrieval: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Your data'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('learned-phrases-card')), findsOneWidget);
    expect(find.textContaining('show my todo list'), findsOneWidget);
    expect(find.textContaining('List your tasks'), findsOneWidget); // human target, not skillId
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(session.learnedFlows.any((f) => f.template == 'show my todo list'), isFalse);
  });

  test('humanizeTemplate turns slot placeholders into plain nouns', () {
    expect(humanizeTemplate('suggest a gift for {contact:entity}'), 'suggest a gift for someone');
    expect(humanizeTemplate('remind me on {when:date}'), 'remind me on a date');
  });
}
