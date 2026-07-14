// P1 visual net (Fable's review) — "render-and-measure" INVARIANTS, not exact-pixel goldens.
// Renders the REAL presence per state to a ui.Image (readback under runAsync, the gesture_snap
// recipe), then asserts the Spec 15 relative gates as NUMBERS: distinguishable states, and the
// spec-mandated orderings (speaking is brighter + broader than thinking; listening is tighter than
// speaking). Numeric bounds are robust to antialiasing / Skia-vs-Impeller noise and portable across
// OSes — which is exactly why goldens were demoted for the animated swarm. Static path (animate:
// false) → one deterministic frame per state, so this runs headless in `flutter test` on every OS.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/plena.dart';

class _Metrics {
  final double luminance; // mean luminance over the whole frame (motes are additive over dark)
  final double coverage; // fraction of pixels lit clearly above the warm-black ground
  const _Metrics(this.luminance, this.coverage);
  @override
  String toString() =>
      'lum=${luminance.toStringAsFixed(4)} cov=${coverage.toStringAsFixed(4)}';
}

double _lum(int r, int g, int b) => (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;

_Metrics _measure(ByteData bytes, int w, int h) {
  // Ground is 0xFF0A0908 (~lum 0.035). "Lit" = clearly above it.
  const groundLum = 0.05;
  var sum = 0.0;
  var lit = 0;
  final n = w * h;
  for (var i = 0; i < n; i++) {
    final o = i * 4;
    final l = _lum(bytes.getUint8(o), bytes.getUint8(o + 1), bytes.getUint8(o + 2));
    sum += l;
    if (l > groundLum + 0.06) lit++;
  }
  return _Metrics(sum / n, lit / n);
}

Future<_Metrics> _renderState(WidgetTester tester, PresenceState state) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(), // static frame comes from animate:false, not reduced-motion
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 320,
              height: 320,
              child: PresenceView(state: state, animate: false), // deterministic static frame
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  late _Metrics m;
  // GPU→CPU readback completes on a real event loop — the fake-async zone deadlocks, so runAsync.
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await boundary.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    m = _measure(bytes, img.width, img.height);
    img.dispose();
  });
  return m;
}

void main() {
  testWidgets('presence states are visually distinguishable + obey the spec orderings (§15 X7)', (
    tester,
  ) async {
    final idle = await _renderState(tester, PresenceState.idle);
    final listening = await _renderState(tester, PresenceState.listening);
    final thinking = await _renderState(tester, PresenceState.thinking);
    final speaking = await _renderState(tester, PresenceState.speaking);
    // ignore: avoid_print
    print('idle=$idle listening=$listening thinking=$thinking speaking=$speaking');

    // Every state actually renders something (not a black frame).
    for (final m in [idle, listening, thinking, speaking]) {
      expect(m.coverage, greaterThan(0.02), reason: 'a state rendered nearly nothing: $m');
    }

    // Spec 15 orderings (targets: speaking lum .62 / spread .56; thinking .36 / .46; listening .42
    // spread — the tightest). Assert the DIRECTION with headroom, robust to AA noise.
    expect(
      speaking.luminance,
      greaterThan(thinking.luminance * 1.15),
      reason: 'speaking should read clearly brighter than thinking — $speaking vs $thinking',
    );
    expect(
      speaking.coverage,
      greaterThan(listening.coverage),
      reason: 'speaking should spread broader than the tighter listening — $speaking vs $listening',
    );

    // Pairwise distinguishability: the spec-differentiated pairs differ by a clear margin on at
    // least one axis (so a regression that collapses two states is caught).
    double sep(_Metrics a, _Metrics b) =>
        ((a.luminance - b.luminance).abs()) + ((a.coverage - b.coverage).abs());
    expect(sep(speaking, thinking), greaterThan(0.02), reason: 'speaking≈thinking — states collapsed');
    expect(sep(speaking, idle), greaterThan(0.015), reason: 'speaking≈idle — states collapsed');
    expect(sep(thinking, listening), greaterThan(0.01), reason: 'thinking≈listening — states collapsed');
  });
}
