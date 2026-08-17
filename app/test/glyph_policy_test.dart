import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/glyph_policy.dart';

void main() {
  test('production register excludes routine acknowledgement sketches', () {
    expect(activeProductionGlyphs, contains('heart'));
    expect(activeProductionGlyphs, contains('undo-loop'));
    expect(activeProductionGlyphs, isNot(contains('nod')));
    expect(activeProductionGlyphs, isNot(contains('spark')));
    expect(activeProductionGlyphs.length, lessThan(16));
  });

  test('rarity gate persists 90-second separation and a daily budget', () {
    final dir = Directory.systemTemp.createTempSync('plenara_glyph_gate_');
    addTearDown(() => dir.deleteSync(recursive: true));
    var now = DateTime(2026, 8, 17, 9);
    GlyphRarityGate gate() => GlyphRarityGate(
      path: '${dir.path}/glyphs.json',
      clock: () => now,
      dailyBudget: 2,
    );

    expect(gate().admit('heart'), isTrue);
    now = now.add(const Duration(seconds: 89));
    expect(gate().admit('check'), isFalse);
    now = now.add(const Duration(seconds: 1));
    expect(gate().admit('check'), isTrue);
    now = now.add(const Duration(minutes: 2));
    expect(gate().admit('star'), isFalse);
    now = DateTime(2026, 8, 18, 9);
    expect(gate().admit('star'), isTrue);
    expect(gate().admit('nod'), isFalse);
  });

  test('rarity gate fails closed when its persisted budget is unreadable', () {
    final dir = Directory.systemTemp.createTempSync('plenara_glyph_gate_bad_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/glyphs.json';
    File(path).writeAsStringSync('{not json');

    expect(GlyphRarityGate(path: path).admit('heart'), isFalse);

    File(path).writeAsStringSync('{"version":1,"events":["not-a-time"]}');
    expect(GlyphRarityGate(path: path).admit('heart'), isFalse);
  });
}
