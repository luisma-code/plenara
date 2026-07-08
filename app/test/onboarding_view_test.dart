import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/main.dart';
import 'package:plenara_app/onboarding_view.dart';

void main() {
  String cfg({String apiKey = ''}) {
    final dir = Directory.systemTemp.createTempSync('plenara_onb_');
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync('{"dataDir": "X:/data", "apiKey": "$apiKey"}');
    return path;
  }

  testWidgets('WelcomeScreen invites connecting and Continue proceeds', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var continued = false;
    await tester.pumpWidget(MaterialApp(
        home: WelcomeScreen(configPath: cfg(), onContinue: () => continued = true)));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Plenara'), findsOneWidget);
    expect(find.text('Connect Claude'), findsOneWidget); // the invite (no key yet)

    await tester.tap(find.textContaining('Continue'));
    await tester.pumpAndSettle();
    expect(continued, isTrue); // offline path never blocks
  });

  testWidgets('a key already set shows connected and no Connect button', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: WelcomeScreen(configPath: cfg(apiKey: 'sk-ant-x'), onContinue: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Claude is connected ✓'), findsOneWidget);
    expect(find.text('Connect Claude'), findsNothing);
  });

  testWidgets('Home routes a keyless first launch to the WelcomeScreen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Home(session: null, configPath: cfg())));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget); // onboarding, not straight to chat
  });
}
