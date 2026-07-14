// Real-GPU resize-crash guard. The ORIGINAL shipped crash was the presence widget being RESIZED
// mid-animation: the comet-trail offscreen buffer is sized from the paint (w,h), so a resize forced
// it to reallocate, and that realloc-during-animation crashed the raster. The list-reply redesign
// stopped resizing the widget (it eases the ENTITY via veilYield instead), but nothing prevents a
// future change from reintroducing a resize — this holds the line.
//
// Run: flutter test integration_test/resize_stress_test.dart -d macos
//
// (An in-test native-memory SOAK was tried here too but removed: IntegrationTestWidgetsFlutterBinding
// accumulates ~1MB per tester.pump(), so a spinner with zero custom rendering "grew" >1GB over 900
// pumps — the harness noise swamps any app signal, making phys_footprint-in-a-test a false gate. The
// real native-leak gate is tool/leak-check.sh, which soaks the actual app process, not a test.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:plenara_app/plena.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> runFrames(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  // Re-pumping the SAME structure (Center > SizedBox > PresenceView) preserves the State via Element
  // reuse, so changing w/h flows a NEW paint size to the painter and forces the trail buffer (bw,bh)
  // to reallocate — the exact realloc path that crashed. animate:true drives the real ticker.
  Widget sizedHarness(double w, double h) => MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF0A0908),
      body: Center(
        child: SizedBox(
          width: w,
          height: h,
          child: const PresenceView(state: PresenceState.speaking, animate: true),
        ),
      ),
    ),
  );

  testWidgets(
    'resizing the animated presence mid-flight never crashes the raster',
    (tester) async {
      const sizes = <List<double>>[
        [420, 320], // start
        [700, 520], // grow
        [180, 140], // shrink hard (tiny buffer)
        [900, 680], // grow big
        [260, 900], // extreme aspect (tall + thin)
        [900, 200], // extreme aspect (short + wide)
        [420, 320], // back home
      ];
      await tester.pumpWidget(sizedHarness(sizes.first[0], sizes.first[1]));
      await runFrames(tester, 30);
      for (final s in sizes.skip(1)) {
        await tester.pumpWidget(sizedHarness(s[0], s[1]));
        await runFrames(tester, 30);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
