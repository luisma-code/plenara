import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/onboarding_view.dart';
import 'package:plenara_app/plenara_theme.dart';

void main() {
  final cases = <(String, Size, double)>[
    ('small phone', const Size(320, 568), 1),
    ('small phone large text', const Size(320, 568), 2),
    ('current phone', const Size(393, 852), 1),
    ('large phone', const Size(430, 932), 1),
    ('phone landscape', const Size(852, 393), 1),
    ('tablet portrait', const Size(768, 1024), 1),
    ('tablet large text', const Size(768, 1024), 2),
  ];

  for (final (name, size, scale) in cases) {
    testWidgets('$name keeps first-run choices visible and tappable', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dir = Directory.systemTemp.createTempSync('plenara_matrix_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final config = File('${dir.path}/config.json')
        ..writeAsStringSync('{"dataDir":"${dir.path}/data"}');
      await tester.pumpWidget(
        MaterialApp(
          theme: PlenaraTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: WelcomeScreen(configPath: config.path, onContinue: () {}),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in ['Connect Claude', 'Continue offline for now']) {
        final target = find.text(label);
        expect(target, findsOneWidget);
        final rect = tester.getRect(target);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
      }
      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsLabel('Plena, a warm constellation of light'),
        findsOneWidget,
      );
    });
  }
}
