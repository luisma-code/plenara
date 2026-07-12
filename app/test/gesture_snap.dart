// Gesture snapshot harness (dev workflow — NOT part of the default suite; the filename has no
// `_test` suffix so `flutter test` skips it, and it's run explicitly, one glyph at a time).
//
// It renders the REAL Plena (`plena.dart` + `glyphs.dart`) headlessly, fires a glyph, freezes the
// simulation at 8 evenly-spaced points across the full gesture (trace → flourish → hold → rejoin),
// and writes a PNG per point. We then read those PNGs back and judge each glyph by eye:
//   • is it the intended symbol?
//   • does the motion read as fluid / organic?
//   • does it look like it's SHED FROM Plena, not a disembodied figure that just appears?
// The PNGs are a temp effect of iteration — they live under a scratch dir, not the repo.
//
// Usage:
//   PLENA_GLYPH=heart PLENA_SNAP_DIR=/abs/out flutter test test/gesture_snap.dart
//   (PLENA_GLYPH may be a comma list or "all"; defaults to "heart". Dir defaults to ./.gesture-snaps)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/glyphs.dart';
import 'package:plenara_app/plena.dart';

const _size = 640.0; // square canvas, 1:1 with the glyph's normalized [-1,1] space
const _frames = 8; // snapshots across the sequence (every 1/8)
const _step = Duration(microseconds: 16667); // one 60 Hz substep per pump → deterministic sim

void main() {
  final dir = Platform.environment['PLENA_SNAP_DIR'] ?? '.gesture-snaps';
  final want = (Platform.environment['PLENA_GLYPH'] ?? 'heart').trim();
  final ids = (want == 'all')
      ? kGlyphs.keys.toList()
      : want.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  for (final id in ids) {
    final g = kGlyphs[id];
    if (g == null) {
      test('missing glyph "$id"', () => fail('no glyph named "$id"'));
      continue;
    }
    testWidgets('snap $id', (tester) async {
      final key = GlobalKey();
      Widget host(int nonce) => Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(), // disableAnimations=false → ticker runs
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: _size,
                height: _size,
                child: PresenceView(
                  key: const ValueKey('plena'), // stable → a nonce bump hits didUpdateWidget
                  state: PresenceState.speaking, // the glyph-firing state (a lively body)
                  glyph: g,
                  glyphNonce: nonce,
                ),
              ),
            ),
          ),
        ),
      );

      // 1) mount idle, let the mote sprite finish loading + the body settle a few frames.
      await tester.pumpWidget(host(0));
      for (var i = 0; i < 30; i++) {
        await tester.pump(_step);
      }
      // 2) fire the glyph (nonce bump), then snapshot at each 1/8 of the full sequence.
      await tester.pumpWidget(host(1));
      final totalMs = g.lastFill + 2240; // = _startGlyph's endAt (rejoin complete)
      final outDir = Directory('$dir/$id')..createSync(recursive: true);
      var elapsed = 0.0, next = 1;
      while (next <= _frames) {
        await tester.pump(_step);
        elapsed += _step.inMicroseconds / 1000.0;
        if (elapsed >= next / _frames * totalMs) {
          // The GPU→CPU readback (toImage/toByteData) completes on a REAL event loop, which the
          // fake-async test zone would deadlock on — so run just the capture under runAsync.
          final frame = next;
          await tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final img = await boundary.toImage(pixelRatio: 1);
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            img.dispose();
            File('${outDir.path}/${frame.toString().padLeft(2, '0')}-of-08.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
          });
          next++;
        }
      }
      // ignore: avoid_print
      print('snapped $id → ${outDir.path} ($_frames frames, sequence ${totalMs.round()}ms)');
    });
  }
}
