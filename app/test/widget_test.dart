// Widget smoke tests for the Plenara chat UI. Inject a Session pointed at a temp
// data dir with an offline (null) cloud so the UI test is hermetic and writes
// nothing to the real data folder.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:plenara_app/main.dart';

class _NullCloud implements CloudClient {
  @override
  Future<Map<String, dynamic>?> routeResidual(String u, Map<String, Map<String, dynamic>> s) async => null;
  @override
  Future<Map<String, dynamic>?> authorCapability(String d, {String? priorError}) async => null;
}

String _base(String p) => p.replaceAll('\\', '/').split('/').last;

String _tempData() {
  final tmp = Directory.systemTemp.createTempSync('plenara_ui_');
  for (final sub in const ['types', 'skills']) {
    final dst = Directory('${tmp.path}/$sub')..createSync(recursive: true);
    for (final f in Directory('$dataDir/$sub').listSync().whereType<File>()) {
      f.copySync('${dst.path}/${_base(f.path)}');
    }
  }
  File('$dataDir/corpus.json').copySync('${tmp.path}/corpus.json');
  Directory('${tmp.path}/records').createSync();
  return tmp.path;
}

Session _session() => Session(_tempData(),
    clock: DateTime.parse('2026-07-06T09:00:00'), cloud: _NullCloud());

void main() {
  testWidgets('renders greeting + controls, and responds to a turn', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session(), retrieval: false)));
    await tester.pumpAndSettle();

    expect(find.textContaining("I'm Plenara"), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Send'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'add buy milk to my list');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('add buy milk to my list'), findsOneWidget); // user bubble
    expect(find.textContaining('Added'), findsOneWidget); // response bubble
    expect(find.textContaining('buy milk'), findsWidgets); // in both bubbles
  });

  testWidgets('tapping Send with empty input adds no bubble', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session(), retrieval: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsOneWidget); // only the greeting bubble
  });
}
