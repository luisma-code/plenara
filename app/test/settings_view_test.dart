import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/config.dart';
import 'package:plenara_app/settings_view.dart';

void main() {
  testWidgets('settings shows key status and saves a pasted BYOK key (in-app)', (tester) async {
    final dir = Directory.systemTemp.createTempSync('plenara_set_');
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync('{"dataDir": "X:/data", "apiKey": ""}');

    await tester.pumpWidget(MaterialApp(home: SettingsView(configPath: path)));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'not set'), findsOneWidget); // no key yet

    await tester.enterText(find.byType(TextField), 'my-byok-key');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Chip, 'set ✓'), findsOneWidget); // status flipped
    if (Platform.environment['ANTHROPIC_API_KEY'] == null) {
      expect(loadConfig(configPath: path).apiKey, 'my-byok-key'); // persisted to config
    }
  });
}
