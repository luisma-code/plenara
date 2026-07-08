import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';
import 'package:plenara_app/settings_view.dart';

void main() {
  String newCfg() {
    final dir = Directory.systemTemp.createTempSync('plenara_set_');
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync('{"dataDir": "X:/data", "apiKey": ""}');
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
    expect(find.widgetWithText(Chip, 'not connected'), findsOneWidget); // a broken key is NOT persisted
    expect(loadConfig(configPath: path).apiKey, isNull);
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
