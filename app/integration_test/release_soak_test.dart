import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:plenara_app/plena.dart';

import '../tool/soak_analysis.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('three-minute animated-presence resource soak plateaus', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF0A0908),
          body: PresenceView(
            state: PresenceState.speaking,
            expression: PresenceExpression.neutral,
          ),
        ),
      ),
    );
    final rss = <int>[];
    final cpu = <double>[];
    for (var second = 0; second < 180; second++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      rss.add(ProcessInfo.currentRss);
      if (rss.length >= 30 && rss.length % 15 == 0) {
        final liveTrend = analyzeSoak(rss);
        if (liveTrend.ballooning) {
          fail(
            'RSS is ballooning during the soak; aborting immediately at '
            '${(liveTrend.peakBytes / 1024 / 1024).toStringAsFixed(1)} MiB.',
          );
        }
      }
      if (second % 10 == 0) {
        final result = await Process.run('ps', ['-p', '$pid', '-o', '%cpu=']);
        final value = double.tryParse('${result.stdout}'.trim());
        if (value != null) cpu.add(value);
      }
    }
    final trend = analyzeSoak(rss);
    final averageCpu = cpu.isEmpty
        ? 0
        : cpu.reduce((a, b) => a + b) / cpu.length;
    // ignore: avoid_print
    print(
      'SOAK samples=${rss.length} peakMiB='
      '${(trend.peakBytes / 1024 / 1024).toStringAsFixed(1)} '
      'finalSpreadMiB=${(trend.finalWindowSpreadBytes / 1024 / 1024).toStringAsFixed(1)} '
      'trailingGrowthMiB=${(trend.trailingGrowthBytes / 1024 / 1024).toStringAsFixed(1)} '
      'trailingSlopeMiB=${(trend.trailingSlopeBytesPerSample / 1024 / 1024).toStringAsFixed(3)} '
      'avgCpu=${averageCpu.toStringAsFixed(1)}%',
    );
    expect(trend.ballooning, isFalse);
    expect(trend.peakBytes, lessThan(1024 * 1024 * 1024));
  });
}
