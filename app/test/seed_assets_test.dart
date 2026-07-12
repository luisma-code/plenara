// The first-run seed chain: bundled assets -> extracted staging dir -> ensureSeeded -> data folder.
// Hermetic: rootBundle serves the real pubspec assets under `flutter test`, and ensureSeeded runs
// against a temp data dir. Proves a SHIPPED binary can seed itself with no repo present.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/config.dart';
import 'package:plenara_app/seed_assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // needed for rootBundle

  test('extractSeedAssets writes the full built-in def set from bundled assets', () async {
    final dir = await extractSeedAssets();
    // the exact set ensureSeeded copies from
    expect(File('$dir/corpus.json').existsSync(), isTrue);
    for (final sub in const ['types', 'skills', 'templates', 'automations', 'reference']) {
      final d = Directory('$dir/$sub');
      expect(d.existsSync(), isTrue, reason: '$sub/ should be extracted');
      expect(d.listSync().whereType<File>(), isNotEmpty, reason: '$sub/ should have defs');
    }
    // a specific known def survives the round-trip (skills are the bulk of the corpus)
    expect(File('$dir/skills/create-task.json').existsSync(), isTrue);
  });

  test('extracted assets seed a fresh data dir (isSeeded false -> true)', () async {
    final seed = await extractSeedAssets();
    final dataDir = Directory.systemTemp.createTempSync('plenara-seed-test').path;
    expect(isSeeded(dataDir), isFalse);
    ensureSeeded(dataDir, seed);
    expect(isSeeded(dataDir), isTrue);
    // types + skills landed, and the corpus came across
    expect(Directory('$dataDir/types').listSync().whereType<File>(), isNotEmpty);
    expect(File('$dataDir/corpus.json').existsSync(), isTrue);
  });
}
