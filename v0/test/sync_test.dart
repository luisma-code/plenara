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

    test('a record delete meeting two concurrent live branches is associative',
        () {
      // Regression: resolving delete-vs-live by whole-record LWW BEFORE field
      // merge made merge(merge(D,L1),L2) != merge(D,merge(L1,L2)) — replicas
      // diverged permanently (delete stamp 3, live x stamp 2, live y stamp 4).
      final deleted = _document(
        device: 'A',
        version: 3,
        fields: {'description': 'old'},
        deleted: true,
      );
      final liveX = _document(device: 'B', version: 2, fields: {'x': 'bx'});
      final liveY = _document(device: 'C', version: 4, fields: {'y': 'cy'});
      Map<String, dynamic> merge(
              Map<String, dynamic> x, Map<String, dynamic> y) =>
          mergeRecordDocuments(x, y).document;

      final leftFirst = merge(merge(deleted, liveX), liveY);
      final rightFirst = merge(deleted, merge(liveX, liveY));
      expect(_canonical(leftFirst), _canonical(rightFirst),
          reason: 'delete vs two live branches must merge associatively');
      // The live stamp 4 outvotes the delete stamp 3 in every order.
      expect(leftFirst['_meta']['deleted'], isNot(true));
      expect(leftFirst['fields'], containsPair('x', 'bx'));
      expect(leftFirst['fields'], containsPair('y', 'cy'));
    });

    test('a record delete newer than every live stamp wins in every order', () {
      final deleted = _document(
        device: 'A',
        version: 5,
        fields: {'description': 'old'},
        deleted: true,
      );
      final liveX = _document(device: 'B', version: 2, fields: {'x': 'bx'});
      final liveY = _document(device: 'C', version: 4, fields: {'y': 'cy'});
      Map<String, dynamic> merge(
              Map<String, dynamic> x, Map<String, dynamic> y) =>
          mergeRecordDocuments(x, y).document;
      for (final result in [
        merge(merge(deleted, liveX), liveY),
        merge(deleted, merge(liveX, liveY)),
        merge(merge(liveY, deleted), liveX),
      ]) {
        expect(result['_meta']['deleted'], isTrue,
            reason: 'the newest stamp is the delete, in every merge order');
      }
    });

    test('a stamp-less legacy field vs plain absence merges commutatively', () {
      // Regression: with compareHlc(null,null)==0 the LEFT argument always won
      // the tie, so a legacy (pre-stamping) field survived or vanished
      // depending on argument order.
      final legacy = {
        'id': 'task-1',
        'typeId': 'task',
        'schemaVersion': 1,
        'fields': {'note': 'keep'},
        '_meta': {
          'stamps': <String, dynamic>{},
          'conflicts': <dynamic>[],
        },
      };
      final absent = {
        'id': 'task-1',
        'typeId': 'task',
        'schemaVersion': 1,
        'fields': <String, dynamic>{},
        '_meta': {
          'stamps': <String, dynamic>{},
          'conflicts': <dynamic>[],
        },
      };
      final ab = mergeRecordDocuments(legacy, absent).document;
      final ba = mergeRecordDocuments(absent, legacy).document;
      expect(_canonical(ab), _canonical(ba),
          reason: 'stamp-less field vs absence must not depend on order');
      expect(ab['fields'], containsPair('note', 'keep'),
          reason: 'presence beats absence-without-tombstone on a stamp tie');
    });

    test(
        'merge is commutative, associative, and idempotent across deletes, '
        'tombstones, vv domination, stamp ties, and legacy fields', () {
      final random = Random(73);
      const fieldPool = ['alpha', 'beta', 'gamma', 'delta'];

      for (var run = 0; run < 150; run++) {
        // A causally honest generator: every branch is derived from a real
        // ancestor by persist/tombstone-shaped operations, so a version vector
        // that dominates really does carry the dominated document's history
        // (the merge's domination shortcut assumes exactly that).
        Map<String, dynamic> nextStamp(Map<String, dynamic> doc, String device) {
          final meta = (doc['_meta'] as Map?) ?? const {};
          var maxMs = 0, maxCounter = 0;
          for (final raw in [
            ...((meta['stamps'] as Map?) ?? const {}).values,
            ...((meta['fieldTombstones'] as Map?) ?? const {}).values,
            meta['deletedStamp'],
          ]) {
            if (raw is! Map) continue;
            final ms = raw['ms'] as int? ?? 0;
            final counter = raw['counter'] as int? ?? 0;
            if (ms > maxMs || (ms == maxMs && counter > maxCounter)) {
              maxMs = ms;
              maxCounter = counter;
            }
          }
          // HLC receive contract: strictly after everything observed. Advancing
          // by the SAME amount on concurrent branches manufactures exact
          // (ms, counter) ties across devices, tie-broken only by deviceId.
          return random.nextBool()
              ? {
                  'ms': maxMs + 1 + random.nextInt(2),
                  'counter': random.nextInt(2),
                  'deviceId': device,
                }
              : {
                  'ms': maxMs,
                  'counter': maxCounter + 1,
                  'deviceId': device,
                };
        }

        Map<String, dynamic> mutate(Map<String, dynamic> parent, String device,
            {required int ops}) {
          final doc =
              jsonDecode(jsonEncode(parent)) as Map<String, dynamic>;
          final meta = Map<String, dynamic>.from(
              (doc['_meta'] as Map?) ?? const {});
          final fields = Map<String, dynamic>.from(
              (doc['fields'] as Map?) ?? const {});
          final stamps = Map<String, dynamic>.from(
              (meta['stamps'] as Map?) ?? const {});
          final tombstones = Map<String, dynamic>.from(
              (meta['fieldTombstones'] as Map?) ?? const {});
          final vv = {
            for (final entry in ((meta['vv'] as Map?) ?? const {}).entries)
              '${entry.key}': entry.value as int,
          };
          for (var op = 0; op < ops; op++) {
            vv[device] = (vv[device] ?? 0) + 1;
            final choice = random.nextInt(10);
            if (choice < 5) {
              // Edit a field (persist semantics: fresh stamp, tombstone lifted,
              // a local edit to a tombstoned record revives it).
              final key = fieldPool[random.nextInt(fieldPool.length)];
              doc['_meta'] = {
                ...meta,
                'stamps': stamps,
                'fieldTombstones': tombstones
              };
              fields[key] = 'v${random.nextInt(4)}';
              stamps[key] = nextStamp(doc, device);
              tombstones.remove(key);
              meta.remove('deleted');
              meta.remove('deletedStamp');
            } else if (choice < 8) {
              // Clear a field (stamped once, at removal). The removal stamp is
              // taken BEFORE the field's own stamp is dropped: persist()
              // observes every prior stamp, so a real clear is always stamped
              // after the value it clears.
              final present = fields.keys.toList();
              if (present.isEmpty) continue;
              final key = present[random.nextInt(present.length)];
              doc['_meta'] = {
                ...meta,
                'stamps': stamps,
                'fieldTombstones': tombstones
              };
              final removal = nextStamp(doc, device);
              fields.remove(key);
              stamps.remove(key);
              tombstones[key] = removal;
              meta.remove('deleted');
              meta.remove('deletedStamp');
            } else {
              // Delete the whole record (tombstone() semantics).
              doc['_meta'] = {
                ...meta,
                'stamps': stamps,
                'fieldTombstones': tombstones
              };
              meta['deleted'] = true;
              meta['deletedStamp'] = nextStamp(doc, device);
            }
          }
          doc['fields'] = fields;
          doc['_meta'] = {
            ...meta,
            'vv': vv,
            'stamps': stamps,
            'conflicts': meta['conflicts'] ?? <dynamic>[],
            if (tombstones.isNotEmpty)
              'fieldTombstones': tombstones
            else
              ...{},
          };
          if (tombstones.isEmpty) {
            (doc['_meta'] as Map).remove('fieldTombstones');
          }
          return doc;
        }

        var base = <String, dynamic>{
          'id': 'task-1',
          'typeId': 'task',
          'schemaVersion': 1,
          'createdAt': '2026-08-17T00:00:00.000Z',
          'fields': <String, dynamic>{
            // Legacy pre-stamping fields: present in fields, absent in stamps.
            if (random.nextBool()) 'legacy': 'seed',
            if (random.nextInt(4) == 0) 'legacyTwo': 'seed2',
          },
          '_meta': {
            'vv': <String, int>{},
            'stamps': <String, dynamic>{},
            'conflicts': <dynamic>[],
          },
        };
        base = mutate(base, 'S', ops: random.nextInt(3));

        final a = mutate(base, 'A', ops: random.nextInt(4));
        // Chaining b or c off another branch produces genuinely dominating
        // version vectors; zero ops produces equal ones.
        final b = random.nextInt(3) == 0
            ? mutate(a, 'B', ops: random.nextInt(4))
            : mutate(base, 'B', ops: random.nextInt(4));
        final c = switch (random.nextInt(4)) {
          0 => mutate(a, 'C', ops: random.nextInt(4)),
          1 => mutate(b, 'C', ops: random.nextInt(4)),
          _ => mutate(base, 'C', ops: random.nextInt(4)),
        };

        Map<String, dynamic> merge(
                Map<String, dynamic> x, Map<String, dynamic> y) =>
            mergeRecordDocuments(x, y).document;
        // The CRDT state (fields, stamps, tombstones, deletion, vv, envelope)
        // must be a join-semilattice: identical from every merge order. The
        // `conflicts` list is an advisory repair surface, not CRDT state — a
        // domination shortcut knows a sequential overwrite is not a conflict,
        // while a different order sees the same overwrite as a concurrent
        // loss — so it is asserted separately: replicas that exchange their
        // merged documents converge on it byte-for-byte (conflict union).
        Map<String, dynamic> state(Map<String, dynamic> document) {
          final copy = _canonical(document);
          (copy['_meta'] as Map?)?.remove('conflicts');
          return copy;
        }

        expect(_canonical(merge(a, b)), _canonical(merge(b, a)),
            reason: 'commutative run $run');
        expect(_canonical(merge(a, a)), _canonical(merge(a, a)),
            reason: 'self-merge deterministic run $run');
        final ab = merge(a, b);
        expect(_canonical(merge(ab, ab)), _canonical(ab),
            reason: 'merge output is a fixpoint run $run');
        final leftAssoc = merge(ab, c);
        final rightAssoc = merge(a, merge(b, c));
        final otherAssoc = merge(merge(a, c), b);
        expect(state(leftAssoc), state(rightAssoc),
            reason: 'associative run $run');
        expect(state(otherAssoc), state(leftAssoc),
            reason: 'associative (all orders) run $run');
        final full = merge(merge(leftAssoc, rightAssoc), otherAssoc);
        expect(
            _canonical(merge(leftAssoc, merge(otherAssoc, rightAssoc))),
            _canonical(full),
            reason: 'conflict exchange is order-independent run $run');
        expect(
            _canonical(merge(otherAssoc, merge(rightAssoc, leftAssoc))),
            _canonical(full),
            reason: 'conflict exchange is order-independent (2) run $run');
        for (final replica in [leftAssoc, rightAssoc, otherAssoc]) {
          expect(_canonical(merge(full, replica)), _canonical(full),
              reason: 'replicas converge byte-for-byte run $run');
        }
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
      expect(repo.corruptFiles, contains(startsWith('${conflict.path}: ')),
          reason: 'the entry carries the path AND the parse error');
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
      expect(repo.corruptFiles, contains(startsWith('${file.path}: ')),
          reason: 'the entry carries the path AND the cause');
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
