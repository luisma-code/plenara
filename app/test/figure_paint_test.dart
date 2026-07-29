/// Does a prompt-compliant, sanitiser-approved figure actually PAINT?
///
/// The readability spike that justified generated figures rendered them in a BROWSER with a
/// stylesheet (`svg { stroke: …; stroke-width: … }`). flutter_svg has no CSS at all. A path with
/// `fill="none"` and no stroke attributes computes a null paint and is never drawn — so every
/// figure the prompt mandates (fill none, never author a stroke) painted ZERO pixels in the app.
/// This test rasterises through the real flutter_svg pipeline and counts lit pixels.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/routine_view.dart';

// Exactly what the authoring prompt mandates and the sanitiser accepts: fill="none", NO stroke.
const _compliant = '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">'
    '<circle cx="50" cy="25" r="10" fill="none"/>'
    '<path d="M50 35 L50 70" fill="none"/>'
    '<line x1="20" y1="80" x2="80" y2="80"/></svg>';

Future<int> _litPixels(String svg) async {
  final info = await vg.loadPicture(SvgStringLoader(svg), null);
  final rec = ui.PictureRecorder();
  Canvas(rec)
    ..drawRect(const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = const Color(0xFF000000))
    ..drawPicture(info.picture);
  final img = await rec.endRecording().toImage(100, 100);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  var lit = 0;
  for (var i = 0; i < bytes!.lengthInBytes; i += 4) {
    if (bytes.getUint8(i + 3) > 8 && bytes.getUint8(i) > 40) lit++;
  }
  return lit;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the RAW compliant figure paints nothing — this is why the stroke must be imposed', () async {
    expect(await _litPixels(_compliant), 0,
        reason: 'documents WHY FigureView wraps the markup; if this ever paints, the wrap can go');
  });

  test('FigureView imposes a stroke, so the same figure is visible', () async {
    const view = FigureView(svg: _compliant);
    final lit = await _litPixels(view.strokedMarkup);
    expect(lit, greaterThan(50), reason: 'a figure that paints nothing is money spent on nothing');
  });
}
