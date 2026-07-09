import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';
import 'package:plenara_app/settings_view.dart';

void main() {
  String newCfg({String apiKey = ''}) {
    final dir = Directory.systemTemp.createTempSync('plenara_set_');
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync('{"dataDir": "X:/data", "apiKey": "$apiKey"}');
    return path;
  }

  testWidgets('shows not-connected, and Save without testing persists a pasted key', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = newCfg();
    await tester.pumpWidget(MaterialApp(home: SettingsView(configPath: path)));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'not connected'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'my-byok-key');
    await tester.tap(find.text('Save without testing'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, 'connected ✓'), findsOneWidget);
    if (Platform.environment['ANTHROPIC_API_KEY'] == null) {
      expect(loadConfig(configPath: path).apiKey, 'my-byok-key');
    }
  });

  testWidgets('Test connection: a working key auto-saves and reports connected', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = newCfg();
    await tester.pumpWidget(MaterialApp(
        home: SettingsView(configPath: path, validateKey: (k) async => const CloudOk<String>('OK'))));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'sk-ant-good');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Connected ✓'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'connected ✓'), findsOneWidget);
    if (Platform.environment['ANTHROPIC_API_KEY'] == null) {
      expect(loadConfig(configPath: path).apiKey, 'sk-ant-good');
    }
  });

  testWidgets('Test connection: a no-credits key is diagnosed to BILLING and NOT saved', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = newCfg();
    await tester.pumpWidget(MaterialApp(
        home: SettingsView(
            configPath: path,
            validateKey: (k) async => const CloudError<String>(CloudErrorKind.insufficientCredits))));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'sk-ant-nocredits');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no credits'), findsOneWidget); // the actionable billing message
    if (Platform.environment['ANTHROPIC_API_KEY'] == null) {
      expect(loadConfig(configPath: path).apiKey, 'sk-ant-nocredits'); // valid key -> SAVED, not discarded
      expect(find.widgetWithText(Chip, 'connected ✓'), findsOneWidget);
    }
  });

  testWidgets('Disconnect removes the saved key', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    if (Platform.environment['ANTHROPIC_API_KEY'] != null) return; // env overrides the file — skip
    final path = newCfg(apiKey: 'sk-ant-existing');
    await tester.pumpWidget(MaterialApp(home: SettingsView(configPath: path)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, 'connected ✓'), findsOneWidget);
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Chip, 'not connected'), findsOneWidget);
    expect(loadConfig(configPath: path).apiKey, isNull);
  });

  testWidgets('Test connection: a rejected key maps to a recopy hint and is not saved', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = newCfg();
    await tester.pumpWidget(MaterialApp(
        home: SettingsView(configPath: path, validateKey: (k) async => const CloudError<String>(CloudErrorKind.badKey))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'sk-ant-wrong');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('rejected'), findsOneWidget);
    if (Platform.environment['ANTHROPIC_API_KEY'] == null) {
      expect(loadConfig(configPath: path).apiKey, isNull); // rejected -> never saved
    }
  });

  testWidgets('Free mode checkbox toggles and persists the offline-only flag', (tester) async {
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
    if (Platform.environment['ANTHROPIC_API_KEY'] == null) {
      expect(loadConfig(configPath: path).apiKey, 'sk-ant-existing'); // key untouched by the toggle
    }

    await tester.tap(find.byKey(const Key('free-mode')));
    await tester.pumpAndSettle();
    expect(loadConfig(configPath: path).freeTier, isFalse); // back to paid
  });

  testWidgets('Open Anthropic Console invokes the URL opener', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = newCfg();
    String? opened;
    await tester.pumpWidget(MaterialApp(home: SettingsView(configPath: path, openUrl: (u) async => opened = u)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Anthropic Console'));
    await tester.pumpAndSettle();
    expect(opened, contains('console.anthropic.com'));
  });
}
