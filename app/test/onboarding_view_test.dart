import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/main.dart';
import 'package:plenara_app/onboarding_view.dart';
import 'package:plenara_app/plena.dart';
import 'package:plenara_app/plenara_theme.dart';

void main() {
  String cfg({String apiKey = ''}) {
    final dir = Directory.systemTemp.createTempSync('plenara_onb_');
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync('{"dataDir": "X:/data", "apiKey": "$apiKey"}');
    return path;
  }

  Widget welcome({
    required String configPath,
    required VoidCallback onContinue,
    double textScale = 1,
  }) => MaterialApp(
    theme: PlenaraTheme.dark,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: WelcomeScreen(configPath: configPath, onContinue: onContinue),
  );

  testWidgets(
    'small-phone welcome introduces Plena and keeps both choices above the fold',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var continued = false;
      await tester.pumpWidget(
        welcome(configPath: cfg(), onContinue: () => continued = true),
      );
      await tester.pumpAndSettle();

      expect(find.text('Meet Plena'), findsOneWidget);
      expect(find.byType(PresenceView), findsOneWidget);
      expect(find.text('Connect Claude'), findsOneWidget);
      expect(find.text('Continue offline for now'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no clipping or overflow');

      await tester.tap(find.text('Continue offline for now'));
      await tester.pumpAndSettle();
      expect(continued, isTrue);
    },
  );

  testWidgets('a key already set shows connected and no Connect button', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      welcome(
        configPath: cfg(apiKey: 'test-key'),
        onContinue: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Claude is connected ✓'), findsOneWidget);
    expect(find.text('Connect Claude'), findsNothing);
    expect(find.text('Continue to Today'), findsOneWidget);
  });

  testWidgets('large text keeps both onboarding decisions reachable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      welcome(configPath: cfg(), onContinue: () {}, textScale: 2),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect Claude'), findsOneWidget);
    expect(find.text('Continue offline for now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home routes a keyless first launch to the WelcomeScreen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: Home(session: null, configPath: cfg())),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(WelcomeScreen),
      findsOneWidget,
    ); // onboarding, not straight to chat
  });
}
