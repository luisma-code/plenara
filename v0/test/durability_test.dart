/// Storage durability boundaries (Spec 06): torn-write recovery windows and the
/// shadow-envelope fallback. All tests run against real temp directories — the
/// crash states they simulate are file states, not mock states.
import 'dart:convert';
import 'dart:io';

import 'package:plenara/config.dart';
import 'package:plenara/storage_repository.dart';
import 'package:plenara/store.dart';
import 'package:test/test.dart';

String _tmp(String name) =>
    Directory.systemTemp.createTempSync('plenara_durability_$name').path;

void main() {
  group('shadow-envelope fallback for an unreadable canonical', () {
    test('persist carries the shadow version vector forward, bumped', () {
      // Regression: persist's catch discarded the prior envelope entirely and
      // rewrote the version vector as {dev: 1}; a peer's copy then strictly
      // dominated and the user's edit was silently discarded on the next sync.
      final data = _tmp('persist_data');
      final device = _tmp('persist_device');
      final repo = FileStorageRepository(
        data,
        deviceDir: device,
        device: HlcDevice('A'),
      );
      repo.persist({'id': 'r1', 'typeId': 'task', 'description': 'one'});
      final canonical = File('$data/records/r1.json');
      final before =
          jsonDecode(canonical.readAsStringSync()) as Map<String, dynamic>;
      expect(before['_meta']['vv'], {'A': 1});
      canonical.writeAsStringSync('{ torn, not json');

      repo.persist({'id': 'r1', 'typeId': 'task', 'description': 'two'});

      final after =
          jsonDecode(canonical.readAsStringSync()) as Map<String, dynamic>;
      expect(after['_meta']['vv'], {'A': 2},
          reason: 'the shadow envelope is the prior, so the vector bumps '
              'instead of resetting to {A: 1}');
      expect(after['createdAt'], before['createdAt'],
          reason: 'creation time survives the torn canonical');
      expect(after['fields']['description'], 'two');
      expect(repo.corruptFiles, isNotEmpty,
          reason: 'the torn canonical is surfaced, not silently repaired');
    });

    test('remove (tombstone) carries the shadow version vector forward too',
        () {
      final data = _tmp('remove_data');
      final device = _tmp('remove_device');
      final repo = FileStorageRepository(
        data,
        deviceDir: device,
        device: HlcDevice('A'),
      );
      repo.persist({'id': 'r1', 'typeId': 'task', 'description': 'one'});
      final canonical = File('$data/records/r1.json');
      canonical.writeAsStringSync('{ torn, not json');

      repo.remove('r1');

      final after =
          jsonDecode(canonical.readAsStringSync()) as Map<String, dynamic>;
      expect(after['_meta']['deleted'], isTrue);
      expect(after['_meta']['vv'], {'A': 2},
          reason: 'a tombstone over a torn canonical must not reset the '
              'vector either, or the delete loses to every peer');
    });
  });

  group('atomic-write crash windows', () {
    test('loadRecords restores a record left only as .json.bak', () {
      // The Windows fallback in _atomicWrite moves the live file to '.bak'
      // before renaming the temp file in; a crash between the two leaves no
      // canonical file at all. The loader must treat the .bak as the record.
      final dir = _tmp('bak_records');
      final dev = HlcDevice('d');
      persist({'id': 'r1', 'typeId': 'task', 'description': 'kept'}, dir, dev);
      final canonical = File('$dir/r1.json');
      canonical.renameSync('$dir/r1.json.bak'); // the crash window state

      final store = loadRecords(dir);
      expect(store['r1']?['description'], 'kept',
          reason: 'the .bak is the only surviving copy of the record');
      expect(canonical.existsSync(), isTrue,
          reason: 'recovery restores the canonical file');
      expect(File('$dir/r1.json.bak').existsSync(), isFalse);
    });

    test('loadDefs restores a definition left only as .json.bak', () {
      final dir = _tmp('bak_defs');
      final file = File('$dir/task.json');
      file.parent.createSync(recursive: true);
      writeJsonAtomic(file, {'typeId': 'task', 'displayName': 'Task'});
      file.renameSync('$dir/task.json.bak');

      final defs = loadDefs(dir, 'typeId');
      expect(defs['task']?['displayName'], 'Task');
      expect(file.existsSync(), isTrue);
    });

    test('a stale .bak next to a healthy file is left alone', () {
      final dir = _tmp('bak_stale');
      final dev = HlcDevice('d');
      persist({'id': 'r1', 'typeId': 'task', 'description': 'new'}, dir, dev);
      File('$dir/r1.json.bak').writeAsStringSync(
          jsonEncode({'id': 'r1', 'typeId': 'task', 'fields': {}}));

      final store = loadRecords(dir);
      expect(store['r1']?['description'], 'new',
          reason: 'the live file wins; the stale .bak must not clobber it');
    });
  });

  group('first-run scaffold and seed copies are atomic', () {
    test('config scaffold goes through temp+rename (no orphan .tmp, no direct '
        'write)', () {
      final dir = _tmp('cfg');
      final path = '$dir/nested/config.json';
      final cfg = loadConfig(configPath: path, environment: const {});
      expect(cfg.dataDir, isNotEmpty);
      expect(File(path).existsSync(), isTrue);
      expect(File('$path.tmp').existsSync(), isFalse);
      // The scaffold parses back — the atomicity contract's observable half.
      expect(jsonDecode(File(path).readAsStringSync()), isA<Map>());
    });

    test('ensureSeeded replaces an orphaned .tmp from a crashed earlier copy',
        () {
      // Regression proxy for the torn-seed window: with plain copySync a
      // crashed earlier attempt left '<name>.json.tmp' orphans behind forever.
      // The atomic copy path claims the same temp name, so seeding must leave
      // the orphan gone and the target complete.
      final dir = _tmp('seed');
      Directory('$dir/types').createSync(recursive: true);
      File('$dir/types/task.json.tmp').writeAsStringSync('{ torn half of a c');

      ensureSeeded(dir, 'data');

      expect(File('$dir/types/task.json.tmp').existsSync(), isFalse,
          reason: 'the seed copy goes through the temp file and renames it');
      final seeded =
          jsonDecode(File('$dir/types/task.json').readAsStringSync()) as Map;
      expect(seeded['typeId'], 'task');
    });
  });
}
