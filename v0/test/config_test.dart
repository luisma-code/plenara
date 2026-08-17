/// Config + built-in installation/upgrades (dogfood enablement).
import 'dart:convert';
import 'dart:io';

import 'package:plenara/config.dart';
import 'package:test/test.dart';

PlenaraConfig _load(String path,
        {Map<String, String> environment = const {}}) =>
    loadConfig(configPath: path, environment: environment);

void main() {
  test('loadConfig reads dataDir + apiKey from a config file', () {
    final dir = Directory.systemTemp.createTempSync('plenara_cfg_');
    final path = '${dir.path}/config.json';
    File(path)
        .writeAsStringSync('{"dataDir": "X:/mydata", "apiKey": "sk-test-123"}');
    final cfg = _load(path);
    expect(cfg.dataDir, 'X:/mydata');
    expect(cfg.apiKey, 'sk-test-123');
    expect(cfg.apiKeySource, ConfigValueSource.file);
  });

  test('explicit config path is hermetic without printing a key value', () {
    final dir = Directory.systemTemp.createTempSync('plenara_cfg_');
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync(
        '{"dataDir": "X:/mydata", "apiKey": "fixture-file-key"}');
    expect(loadConfig(configPath: path).apiKeySource, ConfigValueSource.file);
  });

  test('loadConfig scaffolds a default config the user can edit on first run',
      () {
    final dir = Directory.systemTemp.createTempSync('plenara_cfg_');
    final path = '${dir.path}/nested/config.json';
    final cfg = _load(path);
    expect(File(path).existsSync(), isTrue);
    expect(cfg.dataDir, isNotEmpty);
    expect(File(path).readAsStringSync(), contains('platform secure store'));
  });

  test('empty apiKey in config -> null (not the empty string)', () {
    final dir = Directory.systemTemp.createTempSync('plenara_cfg_');
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync('{"dataDir": "X:/d", "apiKey": ""}');
    expect(_load(path).apiKey, isNull);
  });

  test('still-presence preference defaults off and round-trips', () {
    final dir = Directory.systemTemp.createTempSync('plenara_cfg_');
    final path = '${dir.path}/config.json';
    saveConfig(dataDir: 'X:/d', stillPresence: true, configPath: path);
    expect(_load(path).stillPresence, isTrue);
    saveConfig(stillPresence: false, configPath: path);
    expect(_load(path).stillPresence, isFalse);
  });

  test('ensureSeeded copies the built-in defs into an empty data dir', () {
    final dir = Directory.systemTemp.createTempSync('plenara_seed_');
    ensureSeeded(dir.path, 'data'); // source = the repo's shipped data dir
    expect(File('${dir.path}/types/task.json').existsSync(), isTrue);
    expect(File('${dir.path}/skills/create-task.json').existsSync(), isTrue);
    expect(File('${dir.path}/corpus.json').existsSync(), isTrue);
    expect(Directory('${dir.path}/records').existsSync(), isTrue);
  });

  test(
      'ensureSeeded fails LOUDLY if the seed source is missing (no silent empty boot)',
      () {
    final dir = Directory.systemTemp.createTempSync('plenara_seed_');
    expect(() => ensureSeeded(dir.path, '/no-such-seed-source'),
        throwsA(isA<StateError>()));
  });

  test('ensureSeeded preserves authored and same-version edited definitions',
      () {
    final dir = Directory.systemTemp.createTempSync('plenara_seed_');
    ensureSeeded(dir.path, 'data');
    File('${dir.path}/types/_authored.json')
        .writeAsStringSync('{}'); // simulate an authored type
    final task = File('${dir.path}/types/task.json');
    final edited = jsonDecode(task.readAsStringSync()) as Map<String, dynamic>;
    edited['userMarker'] = 'preserve me';
    task.writeAsStringSync(jsonEncode(edited));

    ensureSeeded(dir.path, 'data');

    expect(File('${dir.path}/types/_authored.json').existsSync(), isTrue);
    expect(
      (jsonDecode(task.readAsStringSync())
          as Map<String, dynamic>)['userMarker'],
      'preserve me',
    );
  });

  test('ensureSeeded adds a newly shipped built-in to an existing folder', () {
    final dir = Directory.systemTemp.createTempSync('plenara_seed_upgrade_');
    ensureSeeded(dir.path, 'data');
    final addedLater = File('${dir.path}/types/contact_fact.json')
      ..deleteSync();

    ensureSeeded(dir.path, 'data');

    expect(addedLater.existsSync(), isTrue);
  });

  test('ensureSeeded promotes a newer type after an exact definition backup',
      () {
    final dir = Directory.systemTemp.createTempSync('plenara_seed_upgrade_');
    ensureSeeded(dir.path, 'data');
    final task = File('${dir.path}/types/task.json');
    final old = jsonDecode(task.readAsStringSync()) as Map<String, dynamic>;
    old['schemaVersion'] = 3;
    old['migrations'] = (old['migrations'] as List).take(2).toList();
    old['attributes'] = (old['attributes'] as List)
        .where((attribute) => !const {
              'dependencyRefs',
              'blockedReason',
              'energy',
              'contexts',
              'recurrence',
            }.contains((attribute as Map)['name']))
        .toList();
    task.writeAsStringSync(jsonEncode(old));

    ensureSeeded(dir.path, 'data');

    final promoted =
        jsonDecode(task.readAsStringSync()) as Map<String, dynamic>;
    expect(promoted['schemaVersion'], 5);
    final backup = File(
      '${dir.path}/.seed-backups/types/task.json.v3.json',
    );
    expect(backup.existsSync(), isTrue);
    expect(jsonDecode(backup.readAsStringSync()), old);
  });

  test('ensureSeeded normalizes a legacy v1 definition without replacing it',
      () {
    final dir = Directory.systemTemp.createTempSync('plenara_seed_legacy_');
    ensureSeeded(dir.path, 'data');
    final fact = File('${dir.path}/types/contact_fact.json');
    final legacy = jsonDecode(fact.readAsStringSync()) as Map<String, dynamic>
      ..remove('schemaVersion')
      ..['legacyMarker'] = 'keep';
    fact.writeAsStringSync(jsonEncode(legacy));

    ensureSeeded(dir.path, 'data');

    final normalized =
        jsonDecode(fact.readAsStringSync()) as Map<String, dynamic>;
    expect(normalized['schemaVersion'], 1);
    expect(normalized['legacyMarker'], 'keep');
    final backup = File(
      '${dir.path}/.seed-backups/types/contact_fact.json.legacy-v1.json',
    );
    expect(backup.existsSync(), isTrue);
    expect(jsonDecode(backup.readAsStringSync()), legacy);
  });

  test(
      'saveConfig writes a config loadConfig reads back; a null key preserves the stored one',
      () {
    final dir = Directory.systemTemp.createTempSync('plenara_cfg_');
    final path = '${dir.path}/config.json';
    saveConfig(dataDir: 'X:/data', apiKey: 'dummy-key-value', configPath: path);
    final c = _load(path);
    expect(c.dataDir, 'X:/data');
    expect(c.apiKey, 'dummy-key-value');
    saveConfig(
        dataDir: 'X:/data2', configPath: path); // null apiKey -> leave the key
    final c2 = _load(path);
    expect(c2.apiKey, 'dummy-key-value');
  });

  test('freeTier defaults to false and round-trips via saveConfig', () {
    final dir = Directory.systemTemp.createTempSync('plenara_cfg_');
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync('{"dataDir": "X:/d", "apiKey": "sk-x"}');
    expect(_load(path).freeTier, isFalse); // absent -> false

    saveConfig(dataDir: 'X:/d', freeTier: true, configPath: path);
    expect(_load(path).freeTier, isTrue);
    expect(_load(path).apiKey, 'sk-x'); // toggling mode leaves the key intact

    saveConfig(dataDir: 'X:/d', freeTier: false, configPath: path);
    expect(_load(path).freeTier, isFalse);

    // a saveConfig that omits freeTier leaves the stored mode untouched
    saveConfig(dataDir: 'X:/d', freeTier: true, configPath: path);
    saveConfig(dataDir: 'X:/d', apiKey: 'sk-y', configPath: path);
    expect(_load(path).freeTier, isTrue);
  });

  test('voiceMuted is three-state (null=unset / true / false) and round-trips',
      () {
    final dir = Directory.systemTemp.createTempSync('plenara_cfg_');
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync('{"dataDir": "X:/d", "apiKey": "sk-x"}');
    // ABSENT must read as null (the first-run "not chosen yet" state), NOT false — this gates the
    // "no audio blast on cold launch" behavior.
    expect(_load(path).voiceMuted, isNull);

    saveConfig(dataDir: 'X:/d', voiceMuted: true, configPath: path);
    expect(_load(path).voiceMuted, isTrue);

    saveConfig(dataDir: 'X:/d', voiceMuted: false, configPath: path);
    expect(_load(path).voiceMuted, isFalse); // false is distinct from unset

    // a saveConfig that omits voiceMuted leaves the stored pref untouched
    saveConfig(dataDir: 'X:/d', voiceMuted: true, configPath: path);
    saveConfig(dataDir: 'X:/d', apiKey: 'sk-z', configPath: path);
    expect(_load(path).voiceMuted, isTrue);

    // a non-bool stored value degrades to null rather than throwing
    File(path).writeAsStringSync('{"dataDir": "X:/d", "voiceMuted": "yes"}');
    expect(_load(path).voiceMuted, isNull);
  });

  test(
      'voiceName round-trips: null=auto-pick, a name pins, empty clears, omit preserves',
      () {
    final dir = Directory.systemTemp.createTempSync('plenara_cfg_');
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync('{"dataDir": "X:/d", "apiKey": "sk-x"}');
    expect(_load(path).voiceName, isNull); // absent → auto-pick

    saveConfig(
        dataDir: 'X:/d', voiceName: 'Matilda (Premium)', configPath: path);
    expect(_load(path).voiceName, 'Matilda (Premium)');

    // omitting voiceName leaves the stored pick untouched
    saveConfig(dataDir: 'X:/d', apiKey: 'sk-z', configPath: path);
    expect(_load(path).voiceName, 'Matilda (Premium)');

    saveConfig(
        dataDir: 'X:/d',
        voiceName: '',
        configPath: path); // empty string clears → back to auto
    expect(_load(path).voiceName, isNull);

    // a non-string / empty stored value degrades to null
    File(path).writeAsStringSync('{"dataDir": "X:/d", "voiceName": ""}');
    expect(_load(path).voiceName, isNull);
  });

  test('PLENARA_FREE=1 env forces free mode regardless of the file', () {
    final dir = Directory.systemTemp.createTempSync('plenara_cfg_');
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync('{"dataDir": "X:/d", "freeTier": false}');
    expect(
        _load(path, environment: const {'PLENARA_FREE': '1'}).freeTier, isTrue);
  });

  test('injected environment overrides file and reports only the source', () {
    final dir = Directory.systemTemp.createTempSync('plenara_cfg_');
    final path = '${dir.path}/config.json';
    File(path)
        .writeAsStringSync('{"dataDir": "X:/d", "apiKey": "fixture-file-key"}');
    final cfg = _load(path, environment: const {
      'PLENARA_DATA': 'X:/environment-data',
      'ANTHROPIC_API_KEY': 'fixture-environment-key',
    });
    expect(cfg.dataDir, 'X:/environment-data');
    expect(cfg.apiKeySource, ConfigValueSource.environment);
  });
}
