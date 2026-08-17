import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/config.dart';
import 'package:plenara_app/data_location.dart';

void main() {
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
}
