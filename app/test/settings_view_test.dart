import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';
import 'package:plenara_app/app_log.dart';
import 'package:plenara_app/build_channel.dart';
import 'package:plenara_app/settings_view.dart';

void main() {
  String newCfg({String apiKey = ''}) {
    final dir = Directory.systemTemp.createTempSync('plenara_set_');
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync('{"dataDir": "X:/data", "apiKey": "$apiKey"}');
    return path;
  }

  testWidgets(
    'shows not-connected, and Save without testing persists a pasted key',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final path = newCfg();
      await tester.pumpWidget(
        MaterialApp(home: SettingsView(configPath: path)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.byKey(const Key('plena-detail-ember')), findsOneWidget);
      expect(find.widgetWithText(Chip, 'not connected'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'my-byok-key');
      await tester.tap(find.text('Save without testing'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, 'connected ✓'), findsOneWidget);
      expect(loadConfig(configPath: path).apiKey, 'my-byok-key');
    },
  );

  testWidgets('declares cloud content classes and journal exclusion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: SettingsView(configPath: newCfg())),
    );
    await tester.pumpAndSettle();

    final declaration = find.byKey(const Key('cloud-content-declarations'));
    await tester.ensureVisible(declaration);
    await tester.tap(declaration);
    await tester.pumpAndSettle();

    expect(find.text('Gift ideas'), findsOneWidget);
    expect(find.text('contact, contact_fact'), findsWidgets);
    expect(find.text('Journal'), findsOneWidget);
    expect(find.textContaining('ask separately each session'), findsOneWidget);
  });

  testWidgets(
    'Test connection: a working key auto-saves and reports connected',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final path = newCfg();
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsView(
            configPath: path,
            validateKey: (k) async => const CloudOk<String>('OK'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'sk-ant-good');
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Connected ✓'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'connected ✓'), findsOneWidget);
      expect(loadConfig(configPath: path).apiKey, 'sk-ant-good');
    },
  );

  testWidgets(
    'Test connection: a no-credits key is diagnosed to BILLING and NOT saved',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final path = newCfg();
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsView(
            configPath: path,
            validateKey: (k) async =>
                const CloudError<String>(CloudErrorKind.insufficientCredits),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'sk-ant-nocredits');
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('no credits'),
        findsOneWidget,
      ); // the actionable billing message
      expect(loadConfig(configPath: path).apiKey, 'sk-ant-nocredits');
      expect(find.widgetWithText(Chip, 'connected ✓'), findsOneWidget);
    },
  );

  testWidgets('Disconnect removes the saved key', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = newCfg(apiKey: 'sk-ant-existing');
    await tester.pumpWidget(MaterialApp(home: SettingsView(configPath: path)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, 'connected ✓'), findsOneWidget);
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Chip, 'not connected'), findsOneWidget);
    expect(loadConfig(configPath: path).apiKey, isNull);
  });

  testWidgets(
    'Test connection: a rejected key maps to a recopy hint and is not saved',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final path = newCfg();
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsView(
            configPath: path,
            validateKey: (k) async =>
                const CloudError<String>(CloudErrorKind.badKey),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sk-ant-wrong');
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();
      expect(find.textContaining('rejected'), findsOneWidget);
      expect(
        loadConfig(configPath: path).apiKey,
        isNull,
      ); // rejected -> never saved
    },
  );

  testWidgets('Free mode checkbox toggles and persists the offline-only flag', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = newCfg(apiKey: 'sk-ant-existing');
    await tester.pumpWidget(MaterialApp(home: SettingsView(configPath: path)));
    await tester.pumpAndSettle();

    // defaults to paid (unchecked)
    expect(loadConfig(configPath: path).freeTier, isFalse);

    await tester.tap(find.byKey(const Key('free-mode')));
    await tester.pumpAndSettle();
    expect(loadConfig(configPath: path).freeTier, isTrue); // persisted
    expect(find.textContaining('Free mode on'), findsOneWidget);
    expect(loadConfig(configPath: path).apiKey, 'sk-ant-existing');

    await tester.tap(find.byKey(const Key('free-mode')));
    await tester.pumpAndSettle();
    expect(loadConfig(configPath: path).freeTier, isFalse); // back to paid
  });

  testWidgets('still presence toggles immediately and persists', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = newCfg();
    bool? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsView(
          configPath: path,
          onStillPresenceChanged: (value) => changed = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('still-presence')));
    await tester.pumpAndSettle();
    expect(loadConfig(configPath: path).stillPresence, isTrue);
    expect(changed, isTrue);
    expect(find.textContaining('Still presence on'), findsOneWidget);
  });

  testWidgets('Cloud usage shows persisted admission counters', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = newCfg();
    final usagePath = '${File(path).parent.path}/cloud-usage.json';
    final admission = CloudAdmissionController(
      path: usagePath,
      clock: () => DateTime.now(),
    );
    expect(admission.admit(), isTrue);

    await tester.pumpWidget(MaterialApp(home: SettingsView(configPath: path)));
    await tester.pumpAndSettle();

    expect(find.text('Cloud admission today'), findsOneWidget);
    expect(find.text('1 / 200'), findsOneWidget);
    expect(find.text('Recent burst'), findsOneWidget);
    expect(find.text('1 / 30'), findsOneWidget);
  });

  testWidgets('Internal diagnostics explicitly say raw and content-bearing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = newCfg();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsView(
          configPath: path,
          diagnosticPolicy: diagnosticPolicyFor(BuildChannel.internal),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byKey(const Key('share-logs')),
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    expect(find.byKey(const Key('share-logs')), findsOneWidget);
    expect(find.text('Share raw diagnostics'), findsOneWidget);
    expect(
      find.textContaining('conversation text, record values'),
      findsOneWidget,
    );
  });

  testWidgets('External builds expose neither raw export nor its local path', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = newCfg();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsView(
          configPath: path,
          diagnosticPolicy: diagnosticPolicyFor(BuildChannel.external),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Diagnostics capture and raw export are disabled'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('share-logs')), findsNothing);
    expect(
      find.textContaining('Diagnostics capture and raw export are disabled'),
      findsOneWidget,
    );
  });

  testWidgets('Open Anthropic Console invokes the URL opener', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = newCfg();
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsView(configPath: path, openUrl: (u) async => opened = u),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Anthropic Console'));
    await tester.pumpAndSettle();
    expect(opened, contains('console.anthropic.com'));
  });

  testWidgets(
    'data location chooser copies data and reports backed-up status',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = Directory.systemTemp.createTempSync(
        'plenara_settings_folder_',
      );
      final source = Directory('${root.path}/source')..createSync();
      final selected = Directory('${root.path}/cloud')..createSync();
      final path = '${root.path}/config.json';
      File(
        path,
      ).writeAsStringSync('{"dataDir": "${source.path}", "apiKey": ""}');
      final record = File('${source.path}/records/task.json');
      record.parent.createSync(recursive: true);
      record.writeAsStringSync('{"id":"task"}');
      Directory('${source.path}/types').createSync();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsView(
            configPath: path,
            chooseDataFolder: () async => selected.path,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Chip, 'Device-local only'), findsOneWidget);

      await tester.tap(find.byKey(const Key('choose-data-folder')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Chip, 'User-selected folder'), findsOneWidget);
      expect(find.textContaining('Data copied safely'), findsOneWidget);
      expect(
        File('${selected.path}/Plenara/records/task.json').existsSync(),
        isTrue,
      );
    },
  );
}
