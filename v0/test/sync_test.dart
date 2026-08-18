import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:plenara/storage_repository.dart';
import 'package:plenara/store.dart';
import 'package:plenara/session.dart';
import 'package:plenara/claude.dart';
import 'package:test/test.dart';

import 'helpers.dart';

String _tmp(String name) =>
    Directory.systemTemp.createTempSync('plenara_sync_$name').path;

Map<String, dynamic> _document({
  required String device,
  required int version,
  required Map<String, dynamic> fields,
  Map<String, dynamic> tombstones = const {},
  bool deleted = false,
}) =>
    {
      'id': 'task-1',
      'typeId': 'task',
      'schemaVersion': 1,
      'createdAt': '2026-08-17T00:00:00.000Z',
      'fields': fields,
      '_meta': {
        'vv': {device: version},
        'stamps': {
          for (final key in fields.keys)
            key: {'ms': version, 'counter': 0, 'deviceId': device},
        },
        'conflicts': <dynamic>[],
        if (tombstones.isNotEmpty) 'fieldTombstones': tombstones,
        if (deleted) ...{
          'deleted': true,
          'deletedStamp': {
            'ms': version,
            'counter': 1,
            'deviceId': device,
          },
        },
      },
    };

Map<String, dynamic> _canonical(Map<String, dynamic> value) {
  Object? normalize(Object? item) {
    if (item is Map) {
      final keys = item.keys.map((key) => '$key').toList()..sort();
      return {for (final key in keys) key: normalize(item[key])};
    }
    if (item is List) return item.map(normalize).toList();
    return item;
  }

  return normalize(value) as Map<String, dynamic>;
}

void main() {
  group('record CRDT', () {
    test('concurrent edits to different fields are both preserved', () {
      final left = _document(
        device: 'A',
        version: 2,
        fields: {'description': 'Call Mum', 'dueAt': '2026-08-18'},
      );
      final right = _document(
        device: 'B',
        version: 3,
        fields: {'description': 'Call Mom', 'priority': 'high'},
      );
      final result = mergeRecordDocuments(left, right);
      expect(result.document['fields'], {
        'description': 'Call Mom',
        'dueAt': '2026-08-18',
        'priority': 'high',
      });
      expect(result.newConflicts, hasLength(1));
      expect(result.newConflicts.single['value'], 'Call Mum');
    });

    test('field tombstone prevents an older value from resurrecting', () {
      final live = _document(
        device: 'A',
        version: 1,
        fields: {'notes': 'old'},
      );
      final cleared = _document(
        device: 'B',
        version: 3,
        fields: const {},
        tombstones: {
          'notes': {'ms': 3, 'counter': 0, 'deviceId': 'B'},
        },
      );
      final result = mergeRecordDocuments(live, cleared).document;
      expect(result['fields'], isNot(contains('notes')));
      expect(result['_meta']['fieldTombstones'], contains('notes'));
    });

    test('a later live edit revives a concurrently deleted record', () {
      final deleted = _document(
        device: 'A',
        version: 2,
        fields: {'description': 'old'},
        deleted: true,
      );
      final live = _document(
        device: 'B',
        version: 4,
        fields: {'description': 'new'},
      );
      final result = mergeRecordDocuments(deleted, live).document;
      expect(result['_meta']['deleted'], isNot(true));
      expect(result['fields']['description'], 'new');
    });

    test('merge is commutative, associative, and idempotent', () {
      final random = Random(73);
      for (var run = 0; run < 100; run++) {
        Map<String, dynamic> branch(String device) => _document(
              device: device,
              version: random.nextInt(500) + 1,
              fields: {
                'description': 'task-${random.nextInt(8)}',
                if (random.nextBool()) 'priority': random.nextInt(4),
                if (random.nextBool()) 'completed': random.nextBool(),
              },
            );

        final a = branch('A'), b = branch('B'), c = branch('C');
        Map<String, dynamic> merge(
                Map<String, dynamic> x, Map<String, dynamic> y) =>
            mergeRecordDocuments(x, y).document;
        expect(_canonical(merge(a, b)), _canonical(merge(b, a)),
            reason: 'commutative run $run');
        expect(_canonical(merge(a, a)), _canonical(a),
            reason: 'idempotent run $run');
        expect(
          _canonical(merge(merge(a, b), c)),
          _canonical(merge(a, merge(b, c))),
          reason: 'associative run $run',
        );
      }
    });
  });

  group('real file reconciliation', () {
    test('device shadow recovers a branch overwritten by the provider', () {
      final shared = _tmp('shared');
      final localDevice = _tmp('local_device');
      final remote = _tmp('remote');
      final local = FileStorageRepository(
        shared,
        deviceDir: localDevice,
        device: HlcDevice('A'),
      );
      local.persist({
        'id': 'task-1',
        'typeId': 'task',
        'description': 'initial',
        'priority': 'normal',
      });
      Directory('$remote/records').createSync(recursive: true);
      File('$shared/records/task-1.json')
          .copySync('$remote/records/task-1.json');

      local.persist({
        'id': 'task-1',
        'typeId': 'task',
        'description': 'local edit',
        'priority': 'normal',
      });
      persist({
        'id': 'task-1',
        'typeId': 'task',
        'description': 'initial',
        'priority': 'high',
      }, '$remote/records', HlcDevice('B'));
      File('$remote/records/task-1.json')
          .copySync('$shared/records/task-1.json');

      final records = local.loadRecords();
      expect(records['task-1']!['description'], 'local edit');
      expect(records['task-1']!['priority'], 'high');
      final onDisk = jsonDecode(
        File('$shared/records/task-1.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(onDisk['_meta']['vv'], {'A': 2, 'B': 1});
    });

    test('provider conflict copy is merged then removed after success', () {
      final shared = _tmp('copy');
      final repo = FileStorageRepository(
        shared,
        deviceDir: _tmp('copy_device'),
        device: HlcDevice('A'),
      );
      repo.persist({
        'id': 'task-1',
        'typeId': 'task',
        'description': 'base',
      });
      final conflict = File('$shared/records/task-1 conflicted copy.json');
      final remote = _document(
        device: 'B',
        version: 9000000000000,
        fields: {'description': 'remote', 'priority': 'high'},
      );
      writeRecordDocument(conflict, remote);

      expect(repo.loadRecords()['task-1']!['description'], 'remote');
      expect(repo.loadRecords()['task-1']!['priority'], 'high');
      expect(conflict.existsSync(), isFalse);
    });

    test('definition conflicts are surfaced and never auto-deleted', () {
      final shared = _tmp('defs');
      final repo = FileStorageRepository(shared);
      Directory('$shared/types').createSync(recursive: true);
      File('$shared/types/task.json').writeAsStringSync(
        jsonEncode({'typeId': 'task', 'displayName': 'Task'}),
      );
      final conflict = File('$shared/types/task conflicted copy.json')
        ..writeAsStringSync(
          jsonEncode({'typeId': 'task', 'displayName': 'Todo'}),
        );

      repo.loadRecords();
      expect(repo.definitionConflicts, hasLength(1));
      expect(repo.definitionConflicts.single.id, 'task');
      expect(repo.loadDefs('types', 'typeId')['task']!['displayName'], 'Task');
      expect(conflict.existsSync(), isTrue);
      repo.resolveDefinitionConflict(
        repo.definitionConflicts.single,
        useConflicting: true,
      );
      expect(repo.loadDefs('types', 'typeId')['task']!['displayName'], 'Todo');
      expect(conflict.existsSync(), isFalse);
      expect(repo.definitionConflicts, isEmpty);
    });

    test('corrupt conflict copy is surfaced and retained for repair', () {
      final shared = _tmp('corrupt');
      final repo = FileStorageRepository(shared);
      final conflict = File('$shared/records/task conflicted copy.json');
      conflict.parent.createSync(recursive: true);
      conflict.writeAsStringSync('{not-json');

      repo.loadRecords();
      expect(repo.corruptFiles, contains(conflict.path));
      expect(conflict.existsSync(), isTrue);
    });

    test('an unrelated misnamed record is surfaced and never deleted', () {
      final shared = _tmp('misnamed');
      final repo = FileStorageRepository(shared);
      final file = File('$shared/records/manual backup.json');
      file.parent.createSync(recursive: true);
      writeRecordDocument(
        file,
        _document(device: 'B', version: 4, fields: {'description': 'saved'}),
      );

      repo.loadRecords();
      expect(repo.corruptFiles, contains(file.path));
      expect(file.existsSync(), isTrue);
    });

    test('watch stream emits from a real external record write', () async {
      final shared = _tmp('watch');
      final repo = FileStorageRepository(shared);
      Directory('$shared/records').createSync(recursive: true);
      final event =
          repo.watchChanges().first.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      File('$shared/records/external.json').writeAsStringSync('{}');
      await expectLater(event, completes);
    });

    test('unsupported native watching leaves a file-backed session usable',
        () async {
      final shared = makeTempDataDir();
      final repo = FileStorageRepository(shared, watchSupported: false);
      await expectLater(
        repo.watchChanges().timeout(const Duration(milliseconds: 100)),
        emitsDone,
      );
      final session = Session(
        shared,
        storage: repo,
        cloud: ClaudeClient(apiKeyOverride: ''),
      );

      await session.init(retrieval: false, watchStorage: true);
      addTearDown(session.dispose);

      expect(session.externalStorageIssues, isEmpty);
      expect(session.skills, contains('create-task'));
    });
  });

  test('HLC observes a future remote stamp before issuing locally', () {
    final clock = HlcDevice('local');
    clock.observe({'ms': 9000000000000, 'counter': 12, 'deviceId': 'remote'});
    final local = clock.stamp();
    expect(
        compareHlc(local, {
          'ms': 9000000000000,
          'counter': 12,
          'deviceId': 'remote',
        }),
        greaterThan(0));
  });

  test('Session applies an external file event to its live planner store',
      () async {
    final dataDir = makeTempDataDir();
    final deviceDir = _tmp('session_device');
    final session = Session(
      dataDir,
      deviceDir: deviceDir,
      cloud: ClaudeClient(apiKeyOverride: ''),
    );
    await session.init(retrieval: false, watchStorage: true);
    addTearDown(session.dispose);
    final loaded = session.storageChanges
        .where((_) => session.store.containsKey('external-task'))
        .first
        .timeout(const Duration(seconds: 3));

    persist({
      'id': 'external-task',
      'typeId': 'task',
      'description': 'Arrived from another device',
      'completed': false,
    }, '$dataDir/records', HlcDevice('remote'));

    await loaded;
    expect(
      session.store['external-task']!['description'],
      'Arrived from another device',
    );
  });
}
