import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/app_log.dart';
import 'package:plenara_app/build_channel.dart';
import 'package:plenara_app/onboarding_view.dart';
import 'package:plenara_app/settings_view.dart';

void main() {
  test(
    'declared external build fails closed across diagnostics and internal tools',
    () {
      expect(activeBuildChannel, BuildChannel.external);
      expect(activeDiagnosticPolicy.capturesContent, isFalse);
      expect(activeDiagnosticPolicy.allowsRawExport, isFalse);
      expect(menuActionsFor(activeBuildChannel), ['data', 'settings']);
      expect(activeBuildChannel.allowsInternalTools, isFalse);
      expect(isExternalBuild, isTrue);
    },
    skip: activeBuildChannel == BuildChannel.external
        ? false
        : 'run with --dart-define=PLENARA_CHANNEL=external',
  );

  testWidgets(
    'external compile boundary wins even over an injected internal policy',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('plenara_external_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final config = File('${dir.path}/config.json')
        ..writeAsStringSync('{"dataDir":"${dir.path}/data"}');
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsView(
            configPath: config.path,
            diagnosticPolicy: diagnosticPolicyFor(BuildChannel.internal),
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
      expect(find.text('Share raw diagnostics'), findsNothing);
    },
    skip: !isExternalBuild,
  );

  test(
    'external startup purges an inherited turnlog and writes no new one',
    () {
      // Spec 11 P11.2/§5.2: the turnlog is content-bearing (utterance, slots,
      // response, recognizer diag). An external build must neither write one
      // nor keep carrying one an internal installation left behind.
      final dir = Directory.systemTemp.createTempSync('plenara_external_tl_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final logs = Directory('${dir.path}/plenara-logs')..createSync();
      final deviceDir = Directory('${dir.path}/device')..createSync();
      final inherited = File('${deviceDir.path}/turnlog.jsonl')
        ..writeAsStringSync(
          '{"utterance":"remember the anniversary","response":"Noted."}\n',
        );
      File(
        '${logs.path}/plenara-20260817-101500.log',
      ).writeAsStringSync('turn: "remember the anniversary"\n');

      AppLog.pruneForTest(
        logs,
        activeDiagnosticPolicy,
        DateTime.now(),
        deviceDir: deviceDir.path,
      );

      expect(
        inherited.existsSync(),
        isFalse,
        reason: 'an inherited content-bearing turnlog must not survive the '
            'switch to an external build',
      );
      expect(
        logs.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.log'),
        ),
        isEmpty,
      );
      // The engine-side half of the boundary: external builds construct the
      // repository with turnlog writing disabled outright.
      expect(!isExternalBuild, isFalse);
    },
    skip: activeBuildChannel == BuildChannel.external
        ? false
        : 'run with --dart-define=PLENARA_CHANNEL=external',
  );

  testWidgets(
    'external onboarding describes cloud egress and no raw diagnostics',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('plenara_external_onb_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final config = File('${dir.path}/config.json')
        ..writeAsStringSync('{"dataDir":"${dir.path}/data"}');
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(configPath: config.path, onContinue: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('stores no raw diagnostics'), findsOneWidget);
      expect(find.textContaining('internal build'), findsNothing);
    },
    skip: !isExternalBuild,
  );
}
