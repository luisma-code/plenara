/// Config + first-run seeding (dogfood enablement).
import 'dart:io';

import 'package:plenara/config.dart';
import 'package:test/test.dart';

void main() {
  test('loadConfig reads dataDir + apiKey from a config file', () {
    final dir = Directory.systemTemp.createTempSync('plenara_cfg_');
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync('{"dataDir": "X:/mydata", "apiKey": "sk-test-123"}');
    final cfg = loadConfig(configPath: path);
    if (Platform.environment['PLENARA_DATA'] == null) expect(cfg.dataDir, 'X:/mydata');
    if (Platform.environment['ANTHROPIC_API_KEY'] == null) expect(cfg.apiKey, 'sk-test-123');
  });

  test('loadConfig scaffolds a default config the user can edit on first run', () {
    final dir = Directory.systemTemp.createTempSync('plenara_cfg_');
    final path = '${dir.path}/nested/config.json';
    final cfg = loadConfig(configPath: path);
    expect(File(path).existsSync(), isTrue);
    expect(cfg.dataDir, isNotEmpty);
    expect(File(path).readAsStringSync(), contains('OneDrive')); // has the hint
  });

  test('empty apiKey in config -> null (not the empty string)', () {
    final dir = Directory.systemTemp.createTempSync('plenara_cfg_');
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync('{"dataDir": "X:/d", "apiKey": ""}');
    if (Platform.environment['ANTHROPIC_API_KEY'] == null) {
      expect(loadConfig(configPath: path).apiKey, isNull);
    }
  });

  test('ensureSeeded copies the built-in defs into an empty data dir', () {
    final dir = Directory.systemTemp.createTempSync('plenara_seed_');
    ensureSeeded(dir.path, 'data'); // source = the repo's shipped data dir
    expect(File('${dir.path}/types/task.json').existsSync(), isTrue);
    expect(File('${dir.path}/skills/create-task.json').existsSync(), isTrue);
    expect(File('${dir.path}/corpus.json').existsSync(), isTrue);
    expect(Directory('${dir.path}/records').existsSync(), isTrue);
  });

  test('ensureSeeded is a no-op once the folder has defs (never wipes user data)', () {
    final dir = Directory.systemTemp.createTempSync('plenara_seed_');
    ensureSeeded(dir.path, 'data');
    File('${dir.path}/types/_authored.json').writeAsStringSync('{}'); // simulate an authored type
    final n = Directory('${dir.path}/types').listSync().length;
    ensureSeeded(dir.path, 'data'); // second run
    expect(Directory('${dir.path}/types').listSync().length, n); // unchanged, marker intact
  });
}
