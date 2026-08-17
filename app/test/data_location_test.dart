import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/config.dart';
import 'package:plenara_app/data_location.dart';

void main() {
  tearDown(() => dataDirOverride = null);

  test(
    'fresh destination receives a complete copy and leaves source intact',
    () async {
      final root = Directory.systemTemp.createTempSync('plenara_location_');
      final source = Directory('${root.path}/source')..createSync();
      final selected = Directory('${root.path}/cloud')..createSync();
      final config = '${root.path}/config.json';
      final record = File('${source.path}/records/task.json');
      record.parent.createSync(recursive: true);
      record.writeAsStringSync('{"id":"task"}');
      Directory('${source.path}/types').createSync();

      final result = await switchDataFolder(
        currentDataDir: source.path,
        selectedPath: selected.path,
        configPath: config,
      );

      expect(result.copiedExistingData, isTrue);
      expect(
        File('${selected.path}/Plenara/records/task.json').readAsStringSync(),
        '{"id":"task"}',
      );
      expect(
        record.existsSync(),
        isTrue,
        reason: 'the old root is a rollback copy',
      );
      final cfg = loadConfig(configPath: config, environment: const {});
      expect(cfg.dataDir, '${selected.path}/Plenara');
      expect(cfg.dataFolderSelected, isTrue);
    },
  );

  test('existing Plenara data is adopted without overwriting it', () async {
    final root = Directory.systemTemp.createTempSync('plenara_location_');
    final source = Directory('${root.path}/source')..createSync();
    File('${source.path}/marker.txt').writeAsStringSync('source');
    final existing = Directory('${root.path}/cloud/Plenara')
      ..createSync(recursive: true);
    final existingRecord = File('${existing.path}/records/task.json');
    existingRecord.parent.createSync(recursive: true);
    existingRecord.writeAsStringSync('existing');
    Directory('${existing.path}/types').createSync();

    final result = await switchDataFolder(
      currentDataDir: source.path,
      selectedPath: existing.parent.path,
      configPath: '${root.path}/config.json',
    );

    expect(result.adoptedExistingData, isTrue);
    expect(existingRecord.readAsStringSync(), 'existing');
  });

  test(
    'an incomplete destination is rejected without changing the source',
    () async {
      final root = Directory.systemTemp.createTempSync('plenara_location_');
      final source = Directory('${root.path}/source')..createSync();
      final sourceFile = File('${source.path}/record.json')
        ..writeAsStringSync('source');
      final partial = Directory('${root.path}/cloud/Plenara')
        ..createSync(recursive: true);
      File('${partial.path}/partial.tmp').writeAsStringSync('interrupted');

      await expectLater(
        switchDataFolder(
          currentDataDir: source.path,
          selectedPath: partial.parent.path,
          configPath: '${root.path}/config.json',
        ),
        throwsA(isA<StateError>()),
      );
      expect(sourceFile.readAsStringSync(), 'source');
      expect(File('${partial.path}/partial.tmp').existsSync(), isTrue);
    },
  );

  test(
    'start fresh preserves cloud data and moves old local bytes to a backup',
    () async {
      final root = Directory.systemTemp.createTempSync('plenara_reset_');
      final local = Directory('${root.path}/local')..createSync();
      final bad = File('${local.path}/records/broken.json');
      bad.parent.createSync(recursive: true);
      bad.writeAsStringSync('{not-json');
      final cloud = Directory('${root.path}/cloud/Plenara')
        ..createSync(recursive: true);
      final cloudRecord = File('${cloud.path}/records/keep.json');
      cloudRecord.parent.createSync(recursive: true);
      cloudRecord.writeAsStringSync('{"keep":true}');
      Directory('${cloud.path}/types').createSync();
      final config = '${root.path}/config.json';
      File(config).writeAsStringSync(
        jsonEncode({
          'dataDir': cloud.path,
          'dataFolderSelected': true,
          'voiceMuted': true,
        }),
      );
      dataDirOverride = cloud.path;
      var clearedSelection = 0;

      final result = await resetDataToDeviceLocal(
        configPath: config,
        localDataDir: local.path,
        clearSelection: () async => clearedSelection++,
        now: () => DateTime.utc(2026, 8, 17, 23, 59),
      );

      expect(clearedSelection, 1);
      expect(result.dataDir, local.path);
      expect(result.backupDir, isNotNull);
      expect(
        File('${result.backupDir}/records/broken.json').readAsStringSync(),
        '{not-json',
      );
      expect(local.existsSync(), isTrue);
      expect(local.listSync(), isEmpty);
      expect(cloudRecord.readAsStringSync(), '{"keep":true}');
      expect(dataDirOverride, isNull);
      final cfg = loadConfig(configPath: config, environment: const {});
      expect(cfg.dataDir, local.path);
      expect(cfg.dataFolderSelected, isFalse);
      expect(
        cfg.voiceMuted,
        isTrue,
        reason: 'reset changes data, not preferences',
      );
    },
  );
}
