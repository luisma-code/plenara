// Host/simulator (real engine + GPU) render smoke. This is the ONE place the animated presence
// actually rasterizes: the mote swarm, the comet-trail ping-pong offscreen buffer (toImageSync),
// the veilYield corner transition, and a glyph flight all run for real here. Headless flutter_test
// builds PresenceView with animate:false (an ever-moving swarm never lets pumpAndSettle terminate),
// so it never touches this path — which is exactly how the list-reply raster crash shipped
// (resizing the widget reallocated the trail buffer mid-animation → native crash).
//
// Run on macOS or an explicitly selected local phone simulator. Never target
// Luis's physical iPhone; that phone is deployment-only.
//   flutter test integration_test/render_test.dart -d macos
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';
import 'package:plenara/people.dart';
import 'package:plenara/session.dart';
import 'package:plenara_app/credential_store.dart';
import 'package:plenara_app/data_location.dart';
import 'package:plenara_app/glyphs.dart';
import 'package:plenara_app/main.dart';
import 'package:plenara_app/plan_view.dart';
import 'package:plenara_app/plena.dart';
import 'package:plenara_app/plenara_theme.dart';
import 'package:plenara_app/relationship_contacts.dart';
import 'package:plenara_app/relationships_view.dart';
import 'package:plenara_app/seed_assets.dart';
import 'package:plenara_app/speech.dart';

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

class _ListeningTrapSpeech implements SpeechRecognizer {
  int listenCalls = 0;

  @override
  bool get available => true;
  @override
  Stream<double> get levels => const Stream<double>.empty();
  @override
  Future<void> init() async {}
  @override
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required void Function() onDone,
    void Function(SpeechNotice notice)? onNotice,
  }) async {
    listenCalls++;
  }

  @override
  Future<void> stop() async {}
  @override
  void cancel() {}
}

Future<Session> _session() async {
  final root = Directory.systemTemp.createTempSync('plenara_it_');
  final data = Directory('${root.path}/data')..createSync();
  final device = Directory('${root.path}/device')..createSync();
  ensureSeeded(data.path, await extractSeedAssets());
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  return Session(
    data.path,
    deviceDir: device.path,
    clock: DateTime.parse('2026-07-06T09:00:00'),
    cloud: _NullCloud(),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> runFrames(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  // Re-pumping the SAME widget structure preserves PresenceView's State (Element reuse), so
  // yieldTarget changes flow through didUpdateWidget and the veilYield smoothing animates — the
  // real corner transition, not a fresh mount.
  Widget harness(
    double yieldTarget, {
    GlyphDef? glyph,
    int nonce = 0,
  }) => MaterialApp(
    theme: PlenaraTheme.dark,
    home: Scaffold(
      backgroundColor: const Color(0xFF0A0908),
      body: PresenceView(
        state: PresenceState.speaking,
        animate:
            true, // the REAL ticker + trail buffer — the whole point of this test
        yieldTarget: yieldTarget,
        glyph: glyph,
        glyphNonce: nonce,
      ),
    ),
  );

  const captureOnly = bool.fromEnvironment('PLENARA_CAPTURE_ONLY');
  if (!captureOnly) {
    testWidgets(
      'animated presence yields to the corner + flies a glyph without a raster crash',
      (tester) async {
        await tester.pumpWidget(harness(0));
        await runFrames(tester, 30);
        // Ease to the corner AND fire a glyph — the exact list-reply moment that used to crash.
        await tester.pumpWidget(harness(1, glyph: kGlyphs['check'], nonce: 1));
        await runFrames(tester, 50);
        await tester.pumpWidget(harness(0));
        await runFrames(tester, 30);
        // Toggle a few more times quickly — stress the transition + buffer reuse.
        for (var i = 0; i < 4; i++) {
          await tester.pumpWidget(
            harness(i.isEven ? 1 : 0, glyph: kGlyphs['heart'], nonce: 2 + i),
          );
          await runFrames(tester, 12);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a real list-reply turn renders with the presence ANIMATING and does not crash',
      (tester) async {
        // forceAnimate:true drives the real animated raster while a real (offline) turn runs — the
        // end-to-end path a "list my tasks" reply takes: reply → _displayIsList → yieldTarget → the
        // animated presence eases to the corner and the trail buffer rasterizes.
        await tester.pumpWidget(
          MaterialApp(
            theme: PlenaraTheme.dark,
            home: ChatScreen(session: await _session(), forceAnimate: true),
          ),
        );
        await runFrames(tester, 30); // init + live Today projection
        expect(find.byKey(const Key('today-board')), findsOneWidget);

        await tester.enterText(
          find.byType(TextField),
          'add buy milk to my list',
        );
        await tester.tap(find.text('Send'));
        await runFrames(tester, 20);

        await tester.enterText(find.byType(TextField), 'list my tasks');
        await tester.tap(find.text('Send'));
        await runFrames(
          tester,
          80,
        ); // let the yield + trail buffer rasterize a real list reply

        expect(tester.takeException(), isNull);
        expect(find.textContaining('buy milk'), findsWidgets);
      },
    );
  }

  testWidgets(
    'Relationships, Todos, Habits, Plan, and Library render through the real engine',
    (tester) async {
      final session = await _session();
      await session.init(retrieval: false);
      await session.handle('add write the proposal to my list');
      await session.handle('add call Sam to my list');
      await session.createRecord('contact', {
        'displayName': 'Sam',
        ...relationshipPresetFields(RelationshipPreset.closeFamily),
        'proximity': 'remote',
        'primaryPhone': '+1 415 555 0100',
        'primaryEmail': 'sam@example.com',
      });
      final samId =
          '${session.store.values.singleWhere((record) => record['typeId'] == 'contact')['id']}';
      await session.createRecord('contact_fact', {
        'subject': samId,
        'fact': 'Training for a half marathon.',
      });
      await session.createRecord('interaction', {
        'subject': samId,
        'medium': 'phone',
        'at': '2026-06-28',
        'note': 'Caught up about summer plans.',
      });
      await session.createRecord('task', {
        'description': 'Renew the passport',
        'createdAt': '2026-06-01T09:00:00',
        'status': 'inbox',
      });
      await session.handle('track meditation as a habit');
      final taskIds = session.store.values
          .where((record) => record['typeId'] == 'task')
          .map((record) => '${record['id']}')
          .toList();
      await session.scheduleTasks([
        taskIds.first,
      ], DateTime.parse('2026-07-06T10:00:00'));
      session.createMorningPlan();
      session.createWeeklyReview();
      session.createWeeklyProposal();

      await tester.pumpWidget(
        MaterialApp(
          theme: PlenaraTheme.dark,
          home: ChatScreen(
            session: session,
            retrieval: false,
            forceAnimate: true,
          ),
        ),
      );
      await runFrames(tester, 35);
      expect(find.byKey(const Key('today-board')), findsOneWidget);
      expect(
        find.byKey(const Key('planning-artifact-morning')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('weekly-review-card')), findsOneWidget);

      final todosScroll = find
          .descendant(
            of: find.byKey(const Key('today-board')),
            matching: find.byType(Scrollable),
          )
          .first;
      final staleSignal = find.byKey(const Key('planner-signal-staleQueue'));
      await tester.scrollUntilVisible(
        staleSignal,
        300,
        scrollable: todosScroll,
      );
      await tester.drag(todosScroll, const Offset(0, -140));
      await runFrames(tester, 3);
      await tester.tap(staleSignal);
      await runFrames(tester, 30);
      expect(find.byType(PlanBoard), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Renew the passport'), findsOneWidget);
      if (const bool.fromEnvironment('PLENARA_CAPTURE_SCREENSHOT')) {
        await binding.takeScreenshot('todo-stale-signal-plan');
      }
      await tester.tap(find.byTooltip('Back'));
      await runFrames(tester, 20);

      final relationshipSignal = find.byKey(
        const Key('planner-signal-relationshipNeglect'),
      );
      await tester.scrollUntilVisible(
        relationshipSignal,
        300,
        scrollable: todosScroll,
      );
      await tester.drag(todosScroll, const Offset(0, -140));
      await runFrames(tester, 3);
      await tester.tap(relationshipSignal);
      await runFrames(tester, 25);
      expect(find.byType(PersonRelationshipView), findsOneWidget);
      expect(find.text('Sam'), findsWidgets);
      expect(find.byKey(const Key('log-interaction')), findsOneWidget);
      if (const bool.fromEnvironment('PLENARA_CAPTURE_SCREENSHOT')) {
        await binding.takeScreenshot('todo-relationship-signal-person');
      }
      await tester.tap(find.byTooltip('Back'));
      await runFrames(tester, 20);

      await tester.tap(find.text('Relationships').last);
      await runFrames(tester, 25);
      expect(find.byKey(const Key('relationships-view')), findsOneWidget);
      expect(find.text('Sam'), findsWidgets);
      final addPerson = find.byKey(const Key('relationships-add-person'));
      final globalMenu = find.byKey(const Key('global-menu'));
      expect(
        tester.getRect(addPerson).overlaps(tester.getRect(globalMenu)),
        isFalse,
        reason: 'Relationships actions must not share the More hit target',
      );
      if (const bool.fromEnvironment('PLENARA_CAPTURE_SCREENSHOT')) {
        await binding.takeScreenshot('relationships-header-actions');
        await binding.takeScreenshot('relationships-proximity-filters');
      }
      await tester.tap(addPerson);
      await runFrames(tester, 10);
      expect(find.text('Add a person'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Alex');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await runFrames(tester, 20);
      expect(find.byType(SnackBar), findsOneWidget);
      if (const bool.fromEnvironment('PLENARA_CAPTURE_SCREENSHOT')) {
        await binding.takeScreenshot('relationships-change-notification');
      }
      await tester.pump(const Duration(seconds: 6));
      await runFrames(tester, 20);
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'the change notification should auto-dismiss',
      );
      final allCircles = find.byKey(const Key('relationships-filter-all'));
      await tester.ensureVisible(allCircles);
      await runFrames(tester, 3);
      await tester.tap(allCircles);
      await runFrames(tester, 20);
      final alexName = find.text('Alex');
      final samName = find.text('Sam');
      expect(alexName, findsOneWidget);
      expect(samName, findsOneWidget);
      expect(
        tester.getTopLeft(alexName).dy,
        lessThan(tester.getTopLeft(samName).dy),
        reason: 'Relationships rows must be alphabetized by display name',
      );
      if (const bool.fromEnvironment('PLENARA_CAPTURE_SCREENSHOT') ||
          const bool.fromEnvironment('PLENARA_CAPTURE_ALPHABETICAL')) {
        await binding.takeScreenshot('relationships-alphabetical-all');
      }
      final relationshipPerson = find.byKey(Key('relationship-person-$samId'));
      final relationshipScroll = find
          .descendant(
            of: find.byKey(const Key('relationships-view')),
            matching: find.byType(Scrollable),
          )
          .first;
      final relationshipObstructionTop = [
        tester.getRect(find.byKey(const Key('planner-navigation'))).top,
        tester.getRect(find.byKey(const Key('planner-input-bar'))).top,
      ].reduce((a, b) => a < b ? a : b);
      for (var attempt = 0; attempt < 6; attempt++) {
        if (tester.getRect(relationshipPerson).bottom <
            relationshipObstructionTop - 8) {
          break;
        }
        await tester.drag(relationshipScroll, const Offset(0, -90));
        await runFrames(tester, 2);
      }
      expect(
        tester.getRect(relationshipPerson).bottom,
        lessThan(relationshipObstructionTop - 8),
        reason:
            'the person row must be wholly above persistent bottom surfaces',
      );
      await tester.tap(relationshipPerson);
      await runFrames(tester, 25);
      expect(find.byKey(const Key('person-relationship-view')), findsOneWidget);
      expect(find.text('Core'), findsOneWidget);
      expect(find.text('Relationship plan'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('FaceTime'), findsOneWidget);
      expect(find.text('Email'), findsWidgets);
      if (const bool.fromEnvironment('PLENARA_CAPTURE_SCREENSHOT')) {
        await binding.takeScreenshot('relationship-detail-actions');
      }
      await tester.tap(find.byTooltip('Back'));
      await runFrames(tester, 20);
      expect(find.byKey(const Key('relationships-view')), findsOneWidget);

      await tester.tap(find.text('Habits').last);
      await runFrames(tester, 25);
      expect(find.byKey(const Key('habits-view')), findsOneWidget);
      expect(find.text('meditation'), findsOneWidget);

      await tester.tap(find.text('Todos').last);
      await runFrames(tester, 25);
      final todosPlanScroll = find
          .descendant(
            of: find.byKey(const Key('today-board')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('todos-plan')),
        300,
        scrollable: todosPlanScroll,
      );
      final todosPlan = find.byKey(const Key('todos-plan'));
      final navigation = find.byKey(const Key('planner-navigation'));
      final inputBar = find.byKey(const Key('planner-input-bar'));
      // A partially visible chip is not actionable when either persistent
      // bottom surface paints above its center. On hosts without speech the
      // text input sits above navigation, so it is the earlier obstruction.
      final obstructionTop = [
        tester.getRect(navigation).top,
        if (inputBar.evaluate().isNotEmpty) tester.getRect(inputBar).top,
      ].reduce((a, b) => a < b ? a : b);
      for (var attempt = 0; attempt < 5; attempt++) {
        if (tester.getRect(todosPlan).bottom < obstructionTop - 8) {
          break;
        }
        await tester.drag(todosPlanScroll, const Offset(0, -80));
        await runFrames(tester, 2);
      }
      expect(
        tester.getRect(todosPlan).bottom,
        lessThan(obstructionTop - 8),
        reason:
            'Plan must be wholly above persistent bottom surfaces; '
            'planBottom=${tester.getRect(todosPlan).bottom}, '
            'obstructionTop=$obstructionTop, '
            'scroll=${tester.state<ScrollableState>(todosPlanScroll).position.pixels}/'
            '${tester.state<ScrollableState>(todosPlanScroll).position.maxScrollExtent}',
      );
      await tester.tap(todosPlan);
      await runFrames(tester, 35);
      expect(
        find.byKey(const Key('phone-plan')).evaluate().isNotEmpty ||
            find.byKey(const Key('desktop-plan')).evaluate().isNotEmpty,
        isTrue,
      );
      expect(find.text('Agenda'), findsOneWidget);
      expect(find.text('write the proposal'), findsOneWidget);
      expect(find.byKey(const Key('plan-proposal')), findsOneWidget);
      // The proposal card makes the phone plan taller than one viewport. This is
      // a real scroll surface, so prove the lower section by bringing it into
      // view instead of assuming every lazy child was built at first paint.
      if (find.text('Unscheduled').evaluate().isEmpty &&
          find.byKey(const Key('phone-plan')).evaluate().isNotEmpty) {
        final planScroll = find
            .descendant(
              of: find.byKey(const Key('phone-plan')),
              matching: find.byType(Scrollable),
            )
            .first;
        final state = tester.state<ScrollableState>(planScroll);
        var offset = 0.0;
        while (find.text('Unscheduled').evaluate().isEmpty &&
            offset <= state.position.maxScrollExtent) {
          state.position.jumpTo(offset);
          await runFrames(tester, 2);
          offset += 80;
        }
      }
      expect(find.text('Unscheduled'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Back'));
      await runFrames(tester, 20);
      await tester.enterText(find.byType(TextField), 'open library');
      await tester.tap(find.text('Send'));
      await runFrames(tester, 25);
      expect(find.byKey(const Key('library-home')), findsOneWidget);
      expect(find.text('People'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('library-projects')),
        300,
        scrollable: find.descendant(
          of: find.byKey(const Key('library-home')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Projects & areas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  if (!captureOnly) {
    testWidgets(
      'task title opens details; its circle completes; neither enters voice',
      (tester) async {
        final session = await _session();
        await session.init(retrieval: false);
        await session.handle('add pack clothes to my list');
        final task = session.store.values.singleWhere(
          (record) => record['typeId'] == 'task',
        );
        expect(
          (await session.editField('${task['id']}', 'status', 'today')).ok,
          isTrue,
        );
        final speech = _ListeningTrapSpeech();

        await tester.pumpWidget(
          MaterialApp(
            theme: PlenaraTheme.dark,
            home: ChatScreen(
              session: session,
              speech: speech,
              retrieval: false,
              forceAnimate: true,
            ),
          ),
        );
        await runFrames(tester, 35);
        expect(find.text('pack clothes'), findsOneWidget);

        await tester.tap(find.text('pack clothes'));
        await runFrames(tester, 25);

        expect(session.store['${task['id']}']!['status'], 'today');
        expect(find.byKey(const Key('record-detail')), findsOneWidget);
        expect(find.byKey(const Key('today-board')), findsOneWidget);
        expect(speech.listenCalls, 0);

        Navigator.of(
          tester.element(find.byKey(const Key('record-detail'))),
        ).pop();
        await runFrames(tester, 15);
        await tester.tap(find.byTooltip('Complete pack clothes'));
        await runFrames(tester, 25);

        expect(session.store['${task['id']}']!['status'], 'done');
        expect(find.byKey(const Key('record-detail')), findsNothing);
        expect(find.text('Completed — pack clothes.'), findsOneWidget);
        expect(session.todayProjection().latestChange, isNotNull);
        expect(speech.listenCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );

    // Resize-crash guard (kept in THIS file, not a separate one: running multiple integration_test
    // files back-to-back on macOS flakes on app relaunch — one file, one launch, is reliable). The
    // ORIGINAL shipped crash was the presence widget being RESIZED mid-animation, reallocating the
    // trail buffer; the veilYield redesign stopped resizing the widget, but this holds the line.
    testWidgets(
      'resizing the animated presence mid-flight never crashes the raster',
      (tester) async {
        Widget sized(double w, double h) => MaterialApp(
          theme: PlenaraTheme.dark,
          home: Scaffold(
            backgroundColor: const Color(0xFF0A0908),
            body: Center(
              child: SizedBox(
                width: w,
                height: h,
                child: const PresenceView(
                  state: PresenceState.speaking,
                  animate: true,
                ),
              ),
            ),
          ),
        );
        const sizes = <List<double>>[
          [420, 320],
          [700, 520],
          [180, 140],
          [900, 680],
          [260, 900],
          [900, 200],
          [420, 320],
        ];
        await tester.pumpWidget(sized(sizes.first[0], sizes.first[1]));
        await runFrames(tester, 30);
        for (final s in sizes.skip(1)) {
          await tester.pumpWidget(sized(s[0], s[1]));
          await runFrames(tester, 30);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('native secure storage really round-trips and deletes', (
      tester,
    ) async {
      final store = PlatformCredentialStore(
        key: 'plenara_integration_test_credential',
      );
      addTearDown(store.deleteApiKey);

      await store.deleteApiKey();
      expect(await store.readApiKey(), isNull);
      await store.writeApiKey('integration-fixture-value');
      expect(await store.readApiKey(), 'integration-fixture-value');
      await store.deleteApiKey();
      expect(await store.readApiKey(), isNull);
    });

    testWidgets('the iOS Contacts bridge reports status repeatedly', (
      tester,
    ) async {
      if (!Platform.isIOS) return;

      final source = NativePhoneContactsSource();
      const statuses = {
        'notDetermined',
        'restricted',
        'denied',
        'authorized',
        'limited',
        'unknown',
      };
      expect(statuses, contains(await source.authorizationStatus()));
      expect(statuses, contains(await source.authorizationStatus()));
    });

    testWidgets('startup data failure resets and reaches a live fresh Today', (
      tester,
    ) async {
      final root = Directory.systemTemp.createTempSync('plenara_recovery_it_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final data = Directory('${root.path}/Plenara')..createSync();
      final bad = File('${data.path}/records/broken.json');
      bad.parent.createSync(recursive: true);
      bad.writeAsStringSync('{not-json');
      final device = Directory('${root.path}/device')..createSync();
      final config = '${root.path}/config.json';
      final brokenSession = Session(
        data.path,
        deviceDir: device.path,
        cloud: _NullCloud(),
      );
      final freshSession = Session(
        data.path,
        deviceDir: device.path,
        cloud: _NullCloud(),
      );
      var failed = true;
      DataResetResult? reset;

      await tester.pumpWidget(
        MaterialApp(
          theme: PlenaraTheme.dark,
          home: StatefulBuilder(
            builder: (context, setHarnessState) => ChatScreen(
              key: ValueKey('recovery-$failed'),
              session: failed ? brokenSession : freshSession,
              retrieval: false,
              initializeSession: failed
                  ? (_) async => throw StateError('integration broken folder')
                  : null,
              resetData: () async {
                reset = await resetDataToDeviceLocal(
                  configPath: config,
                  localDataDir: data.path,
                );
                ensureSeeded(data.path, await extractSeedAssets());
                return reset!;
              },
              onDataReset: () => setHarnessState(() => failed = false),
            ),
          ),
        ),
      );
      await runFrames(tester, 20);
      expect(find.byKey(const Key('startup-recovery')), findsOneWidget);
      expect(find.textContaining('integration broken folder'), findsOneWidget);

      await tester.tap(find.byKey(const Key('startup-reset-data')));
      await runFrames(tester, 45);

      expect(reset?.backupDir, isNotNull);
      expect(
        File('${reset!.backupDir}/records/broken.json').existsSync(),
        isTrue,
      );
      expect(find.byKey(const Key('startup-recovery')), findsNothing);
      expect(find.byKey(const Key('today-board')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
