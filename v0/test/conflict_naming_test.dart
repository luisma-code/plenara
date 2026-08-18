/// Provider conflict-copy naming matrix (Spec 06). Each sync provider renames a
/// conflicting record file its own way; every known pattern must be recognized,
/// CRDT-merged into the canonical file, and then removed — while a filename that
/// merely LOOKS suffixed (a legit hyphenated id, a manual backup) is surfaced
/// for repair and never deleted.
import 'dart:convert';
import 'dart:io';

import 'package:plenara/storage_repository.dart';
import 'package:plenara/store.dart';
import 'package:test/test.dart';

String _tmp(String name) =>
    Directory.systemTemp.createTempSync('plenara_conflict_$name').path;

Map<String, dynamic> _remoteDoc(String id, {required String description}) => {
      'id': id,
      'typeId': 'task',
      'schemaVersion': 1,
      'createdAt': '2026-08-17T00:00:00.000Z',
      'fields': {'description': description, 'priority': 'high'},
      '_meta': {
        'vv': {'B': 9000000000000},
        'stamps': {
          'description': {
            'ms': 9000000000000,
            'counter': 0,
            'deviceId': 'B',
          },
          'priority': {'ms': 9000000000000, 'counter': 1, 'deviceId': 'B'},
        },
        'conflicts': <dynamic>[],
      },
    };

void main() {
  group('provider conflict-copy naming matrix', () {
    for (final provider in const [
      ('Dropbox', "task-1 (Luis's conflicted copy 2026-08-17).json"),
      ('iCloud 2', 'task-1 2.json'),
      ('iCloud N', 'task-1 7.json'),
      ('OneDrive', 'task-1-DESKTOP-4KQ9F2.json'),
      (
        'Syncthing',
        'task-1.sync-conflict-20260817-123456-ABCD123.json',
      ),
    ]) {
      test('${provider.$1} copy is merged into the canonical then removed', () {
        final shared = _tmp(provider.$1.replaceAll(' ', '_').toLowerCase());
        final repo = FileStorageRepository(
          shared,
          deviceDir: _tmp('${provider.$1.toLowerCase()}_device'),
          device: HlcDevice('A'),
        );
        repo.persist({
          'id': 'task-1',
          'typeId': 'task',
          'description': 'base',
        });
        final copy = File('$shared/records/${provider.$2}');
        writeRecordDocument(copy, _remoteDoc('task-1', description: 'remote'));

        final records = repo.loadRecords();
        expect(records['task-1']!['description'], 'remote',
            reason: '${provider.$1}: the copy must be CRDT-merged');
        expect(records['task-1']!['priority'], 'high');
        expect(copy.existsSync(), isFalse,
            reason: '${provider.$1}: the merged copy must be removed');
        expect(repo.corruptFiles, isEmpty);
      });
    }

    test(
        'a hyphen-suffixed name whose stem has no canonical record is NOT '
        'swallowed as a OneDrive copy', () {
      // The OneDrive pattern (bare '-<ComputerName>' suffix) is only safe when
      // the stem is a record that exists canonically; otherwise a legitimate
      // export/backup with a hyphenated name would be silently deleted.
      final shared = _tmp('onedrive_negative');
      final repo = FileStorageRepository(
        shared,
        deviceDir: _tmp('onedrive_negative_device'),
        device: HlcDevice('A'),
      );
      final file = File('$shared/records/task-1-MACHINE.json');
      file.parent.createSync(recursive: true);
      writeRecordDocument(file, _remoteDoc('task-1', description: 'orphan'));

      repo.loadRecords();
      expect(file.existsSync(), isTrue,
          reason: 'no canonical task-1.json exists, so never auto-delete');
      expect(repo.corruptFiles, isNotEmpty,
          reason: 'the unexplained file is surfaced for repair');
    });

    test('an iCloud " 1" suffix is not treated as a conflict copy', () {
      // iCloud numbers duplicates from 2 upward; "<id> 1.json" is not a name it
      // produces, so it stays a repair item.
      final shared = _tmp('icloud_one');
      final repo = FileStorageRepository(
        shared,
        deviceDir: _tmp('icloud_one_device'),
        device: HlcDevice('A'),
      );
      repo.persist({'id': 'task-1', 'typeId': 'task', 'description': 'base'});
      final file = File('$shared/records/task-1 1.json');
      writeRecordDocument(file, _remoteDoc('task-1', description: 'odd'));

      repo.loadRecords();
      expect(file.existsSync(), isTrue);
      expect(repo.corruptFiles, isNotEmpty);
    });

    test('template and automation definition conflicts are surfaced too', () {
      // Regression: _scanDefinitionConflicts only covered types/ and skills/,
      // so a provider conflict copy of a template or automation stayed
      // invisible forever.
      final shared = _tmp('def_scan');
      final repo = FileStorageRepository(
        shared,
        deviceDir: _tmp('def_scan_device'),
        device: HlcDevice('A'),
      );
      Directory('$shared/templates').createSync(recursive: true);
      Directory('$shared/automations').createSync(recursive: true);
      File('$shared/templates/water.json').writeAsStringSync(
          jsonEncode({'templateId': 'water', 'displayName': 'Water'}));
      File('$shared/templates/water conflicted copy.json').writeAsStringSync(
          jsonEncode({'templateId': 'water', 'displayName': 'Agua'}));
      File('$shared/automations/nudge.json').writeAsStringSync(
          jsonEncode({'automationId': 'nudge', 'targetType': 'task'}));
      File('$shared/automations/nudge 2.json').writeAsStringSync(
          jsonEncode({'automationId': 'nudge', 'targetType': 'task'}));

      repo.loadRecords();
      expect(repo.definitionConflicts.map((c) => c.subdir).toSet(),
          containsAll({'templates', 'automations'}));
      expect(File('$shared/templates/water conflicted copy.json').existsSync(),
          isTrue,
          reason: 'definition conflicts are surfaced, never auto-deleted');
      expect(File('$shared/automations/nudge 2.json').existsSync(), isTrue);
    });

    test(
        'a definition file with a missing or non-string id is surfaced, '
        'not silently skipped', () {
      final shared = _tmp('def_noid');
      final repo = FileStorageRepository(
        shared,
        deviceDir: _tmp('def_noid_device'),
        device: HlcDevice('A'),
      );
      Directory('$shared/types').createSync(recursive: true);
      File('$shared/types/broken.json')
          .writeAsStringSync(jsonEncode({'displayName': 'No id here'}));

      repo.loadRecords();
      expect(repo.loadDefs('types', 'typeId'), isEmpty);
      expect(
          repo.corruptFiles.any((entry) => entry.contains('broken.json')), isTrue,
          reason: 'the unusable definition becomes a visible repair item');
    });

    test('merged conflict copies survive a reload with the merged content', () {
      final shared = _tmp('reload');
      final repo = FileStorageRepository(
        shared,
        deviceDir: _tmp('reload_device'),
        device: HlcDevice('A'),
      );
      repo.persist({'id': 'task-1', 'typeId': 'task', 'description': 'base'});
      writeRecordDocument(
        File('$shared/records/task-1-DESKTOP-4KQ9F2.json'),
        _remoteDoc('task-1', description: 'remote'),
      );
      repo.loadRecords();
      final onDisk = jsonDecode(
        File('$shared/records/task-1.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(onDisk['fields']['description'], 'remote');
      expect((onDisk['_meta'] as Map)['vv'], containsPair('B', 9000000000000));
    });
  });
}
