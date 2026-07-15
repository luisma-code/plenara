// Not a test — a dev tool. Renders chosen glyphs (their FINAL, fully-drawn line figures) to a PNG
// sheet so their shapes can be reviewed by eye (Spec 15 §5A: "refine by eye"). Run:
//   flutter test test/glyph_render.dart
// Writes the sheet to the path in [outPath]. Drawn light-on-dark to match the void.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/glyphs.dart';

// Written to the system temp dir (portable — CI-safe); the path is printed when it runs. Override
// with `--dart-define=GLYPH_SHEET_OUT=/some/path.png` to send it somewhere specific.
final outPath = const String.fromEnvironment('GLYPH_SHEET_OUT').isNotEmpty
    ? const String.fromEnvironment('GLYPH_SHEET_OUT')
    : '${Directory.systemTemp.path}/plenara-glyph-sheet.png';

// Which glyphs to render: the tour set + candidate swaps.
const _names = [
  'bell', 'flower', 'sun', 'check', 'heart', //
  'enso', 'rising-bars', 'seedling', 'small-check', 'target', //
];

void main() {
  testWidgets('render glyph sheet', (tester) async {
    const cell = 220.0, cols = 5;
    final rows = (_names.length / cols).ceil();
    final w = (cols * cell).toInt(), h = (rows * cell).toInt();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFF0A0908));
    final stroke = Paint()
      ..color = const Color(0xFFEAE2D8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dotPaint = Paint()..color = const Color(0xFFEAE2D8);

    for (var i = 0; i < _names.length; i++) {
      final g = kGlyphs[_names[i]];
      final cellX = (i % cols) * cell, cellY = (i ~/ cols) * cell;
      final r = cell * 0.34; // glyph half-extent inside the cell
      final ox = cellX + cell / 2, oy = cellY + cell / 2 - 8;
      Offset map(Offset p) => Offset(ox + p.dx * r, oy + p.dy * r);
      // faint cell border
      canvas.drawRect(Rect.fromLTWH(cellX + 1, cellY + 1, cell - 2, cell - 2),
          Paint()..color = const Color(0x14FFFFFF)..style = PaintingStyle.stroke);
      if (g != null) {
        for (final s in g.strokes) {
          if (s.pts.isEmpty) continue;
          final path = Path()..moveTo(map(s.pts.first).dx, map(s.pts.first).dy);
          for (final p in s.pts.skip(1)) {
            path.lineTo(map(p).dx, map(p).dy);
          }
          canvas.drawPath(path, stroke);
        }
        for (final d in g.dots) {
          canvas.drawCircle(map(d.at), 4, dotPaint);
        }
      }
      final tp = TextPainter(
        text: TextSpan(
            text: g == null ? '${_names[i]} (missing)' : _names[i],
            style: const TextStyle(color: Color(0xFFEAE2D8), fontSize: 15)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cellX + cell / 2 - tp.width / 2, cellY + cell - 26));
    }

    final pic = rec.endRecording();
    // Image rasterization needs a REAL async zone in flutter_test (the faked clock would hang it).
    await tester.runAsync(() async {
      final img = await pic.toImage(w, h);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File(outPath).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    // ignore: avoid_print
    print('WROTE $outPath (${w}x$h)');
  });
}
