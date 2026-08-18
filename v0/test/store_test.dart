/// Storage + CRDT layer (Spec 04 §3.1 / storage-crdt spike). Per-record file
/// shape, the `_meta` HLC block, round-trips, HLC monotonicity, and undoTurn
/// (create/update reversal) on both memory and disk.
import 'dart:convert';
import 'dart:io';

import 'package:plenara/store.dart';
import 'package:plenara/storage_repository.dart';
import 'package:test/test.dart';

String _tmp() => Directory.systemTemp.createTempSync('plenara_store_').path;

void main() {
  group('Fable#2 CRDT format fixes', () {
    test(
        'tombstone of a never-persisted id still writes a tombstone (no resurrection)',
        () {
      final dir = _tmp();
      tombstone('ghost-1', dir, HlcDevice('d')); // record was never on disk
      expect(
          loadRecords(dir), isEmpty); // tombstone stays out of the live store
      final f = File('$dir/ghost-1.json');
      expect(f.existsSync(), isTrue,
          reason: 'a tombstone file must exist to block resurrection');
      final rec = jsonDecode(f.readAsStringSync()) as Map;
      expect((rec['_meta'] as Map)['deleted'], true);
    });

    test(
        'device id is stable per install, distinct across installs, never the shared constant',
        () {
      final d1 = _tmp(), d2 = _tmp();
      final id1 = FileStorageRepository(d1).dev.stamp()['deviceId'] as String;
      final id1again = FileStorageRepository(d1).dev.stamp()['deviceId']
          as String; // same dir
      final id2 = FileStorageRepository(d2).dev.stamp()['deviceId']
          as String; // other dir
      expect(id1, id1again, reason: 'a reopened install keeps its id');
      expect(id1, isNot('this-device'));
      expect(id1, isNot(id2), reason: 'two installs must tie-break distinctly');
    });
  });
  group('loadDefs', () {
    test('indexes type defs by typeId', () {
      final types = loadDefs('data/types', 'typeId');
      expect(
          types.keys,
          containsAll([
            'task',
            'contact',
            'workout',
            'mood',
            'contact_fact',
            'contact_relationship'
          ]));
      expect(types['task']!['displayName'], 'Task');
    });
    test('indexes skills by skillId', () {
      final skills = loadDefs('data/skills', 'skillId');
      expect(skills.length, greaterThanOrEqualTo(7));
      expect(skills['create-task']!['displayName'], 'Create a task');
    });
  });

  group('persist — on-disk CRDT shape', () {
    test('writes {id,typeId,fields,_meta} with a per-field stamp', () {
      final dir = _tmp();
      persist({
        'id': 'task-1',
        'typeId': 'task',
        'description': 'buy milk',
        'completed': false,
        'dueAt': null
      }, dir, HlcDevice('dev-A'));
      final j = jsonDecode(File('$dir/task-1.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(j['id'], 'task-1');
      expect(j['typeId'], 'task');
      expect(j['fields']['description'], 'buy milk');
      expect(j['fields']['completed'], false);
      expect((j['fields'] as Map).containsKey('dueAt'), isTrue,
          reason: 'null field is kept');
      expect((j['fields'] as Map).containsKey('id'), isFalse,
          reason: 'id/typeId not duplicated into fields');
      final stamps = j['_meta']['stamps'] as Map;
      expect(stamps.keys, containsAll(['description', 'completed', 'dueAt']));
      expect(stamps['description']['deviceId'], 'dev-A');
      expect(stamps['description'].containsKey('ms'), isTrue);
      expect(stamps['description'].containsKey('counter'), isTrue);
      expect(j['_meta']['conflicts'], isEmpty);
    });
  });

  group('persist -> loadRecords round-trip (flat records)', () {
    test('multiple records, mixed value types', () {
      final dir = _tmp();
      final dev = HlcDevice('d');
      persist({
        'id': 'w-1',
        'typeId': 'workout',
        'activity': 'run',
        'distance': 5,
        'date': '2026-07-06'
      }, dir, dev);
      persist({
        'id': 'w-2',
        'typeId': 'workout',
        'activity': 'walk',
        'distance': 2.5,
        'date': '2026-07-07'
      }, dir, dev);
      persist({
        'id': 't-1',
        'typeId': 'task',
        'description': 'x',
        'completed': true,
        'dueAt': null
      }, dir, dev);
      final store = loadRecords(dir);
      expect(store.length, 3);
      expect(store['w-1'], containsPair('id', 'w-1'));
      expect(store['w-1'], containsPair('typeId', 'workout'));
      expect(store['w-1'], containsPair('activity', 'run'));
      expect(store['w-1'], containsPair('distance', 5));
      expect(store['w-1'], containsPair('date', '2026-07-06'));
      expect(store['w-1'], containsPair('_schemaVersion', 1));
      expect(store['w-1']!['createdAt'], isA<String>());
      expect(store['w-2']!['distance'], 2.5);
      expect(store['t-1']!['completed'], true);
      expect(store['t-1']!.containsKey('dueAt'), isTrue);
      expect(store['t-1']!['dueAt'], isNull);
    });
    test('missing dir -> empty store', () {
      expect(loadRecords('${_tmp()}/does-not-exist'), isEmpty);
    });
  });

  group('HlcDevice — monotonic stamps', () {
    test('1000 stamps strictly increase by (ms, counter); deviceId constant',
        () {
      final dev = HlcDevice('dev-A');
      final stamps = List.generate(1000, (_) => dev.stamp());
      for (var i = 1; i < stamps.length; i++) {
        final a = stamps[i - 1], b = stamps[i];
        final aMs = a['ms'] as int, bMs = b['ms'] as int;
        expect(bMs >= aMs, isTrue, reason: 'ms non-decreasing');
        if (bMs == aMs) {
          expect(b['counter'] as int, greaterThan(a['counter'] as int),
              reason: 'counter increments within a ms');
        }
        expect(b['deviceId'], 'dev-A');
      }
    });
    test('two devices carry distinct ids', () {
      expect(HlcDevice('A').stamp()['deviceId'], 'A');
      expect(HlcDevice('B').stamp()['deviceId'], 'B');
    });
  });

  group('undoTurn', () {
    test(
        'created record (prior null) -> tombstoned, not resurrectable by a sync restore',
        () {
      final dir = _tmp();
      final dev = HlcDevice('d');
      final store = <String, Map<String, dynamic>>{
        't-1': {'id': 't-1', 'typeId': 'task', 'description': 'x'}
      };
      persist(store['t-1']!, dir, dev);
      undoTurn({'t-1': null}, dir, dev, store);
      expect(store.containsKey('t-1'), isFalse);
      expect(File('$dir/t-1.json').existsSync(),
          isTrue); // tombstone file remains (CRDT)
      expect(
          (jsonDecode(File('$dir/t-1.json').readAsStringSync()) as Map)['_meta']
              ['deleted'],
          isTrue);
      expect(loadRecords(dir), isEmpty); // and a reload cannot bring it back
    });

    test('updated record (prior != null) -> restored in memory + disk', () {
      final dir = _tmp();
      final dev = HlcDevice('d');
      final store = <String, Map<String, dynamic>>{
        't-1': {'id': 't-1', 'typeId': 'task', 'description': 'new'}
      };
      persist(store['t-1']!, dir, dev);
      undoTurn({
        't-1': <String, dynamic>{
          'id': 't-1',
          'typeId': 'task',
          'description': 'old'
        }
      }, dir, dev, store);
      expect(store['t-1']!['description'], 'old');
      final j = jsonDecode(File('$dir/t-1.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(j['fields']['description'], 'old');
    });

    test('mixed multi-record turn: one created + one updated', () {
      final dir = _tmp();
      final dev = HlcDevice('d');
      final store = <String, Map<String, dynamic>>{
        'a': {'id': 'a', 'typeId': 'task', 'description': 'created'},
        'b': {'id': 'b', 'typeId': 'task', 'description': 'updated'},
      };
      persist(store['a']!, dir, dev);
      persist(store['b']!, dir, dev);
      undoTurn({
        'a': null,
        'b': <String, dynamic>{
          'id': 'b',
          'typeId': 'task',
          'description': 'before'
        }
      }, dir, dev, store);
      expect(store.containsKey('a'), isFalse);
      expect(loadRecords(dir).containsKey('a'),
          isFalse); // tombstoned -> not loaded
      expect(store['b']!['description'], 'before');
    });
  });

  group('CRDT fidelity (Fable review)', () {
    test('stamp-on-change: an unchanged field keeps its prior stamp', () {
      final dir = _tmp();
      final dev = HlcDevice('d');
      persist(
          {'id': 't', 'typeId': 'task', 'description': 'a', 'completed': false},
          dir,
          dev);
      final s1 = (jsonDecode(File('$dir/t.json').readAsStringSync())
          as Map)['_meta']['stamps'] as Map;
      persist(
          {'id': 't', 'typeId': 'task', 'description': 'a', 'completed': true},
          dir,
          dev); // only completed changed
      final s2 = (jsonDecode(File('$dir/t.json').readAsStringSync())
          as Map)['_meta']['stamps'] as Map;
      expect(s2['description'], s1['description'],
          reason: 'unchanged field keeps its stamp');
      expect(s2['completed'], isNot(s1['completed']),
          reason: 'changed field gets a fresh stamp');
    });
    test(
        'stamp-on-change holds for LIST/MAP fields too (deep, not identity, equality)',
        () {
      // Regression: `==` on List/Map is identity in Dart, so a tag/list/json field
      // compared unequal to its own reloaded self and was re-stamped on EVERY write —
      // collapsing those fields to whole-record LWW at merge time.
      final dir = _tmp();
      final dev = HlcDevice('d');
      persist({
        'id': 't',
        'typeId': 'task',
        'tags': ['a', 'b'],
        'meta': {'k': 1},
        'description': 'x'
      }, dir, dev);
      final s1 = (jsonDecode(File('$dir/t.json').readAsStringSync())
          as Map)['_meta']['stamps'] as Map;
      // same VALUES, fresh instances (what a reload-then-save actually produces)
      persist({
        'id': 't',
        'typeId': 'task',
        'tags': ['a', 'b'],
        'meta': {'k': 1},
        'description': 'y'
      }, dir, dev);
      final s2 = (jsonDecode(File('$dir/t.json').readAsStringSync())
          as Map)['_meta']['stamps'] as Map;
      expect(s2['tags'], s1['tags'], reason: 'unchanged list keeps its stamp');
      expect(s2['meta'], s1['meta'], reason: 'unchanged map keeps its stamp');
      expect(s2['description'], isNot(s1['description']),
          reason: 'the changed field re-stamps');
      // a genuinely changed list still re-stamps
      persist({
        'id': 't',
        'typeId': 'task',
        'tags': ['a', 'c'],
        'meta': {'k': 1},
        'description': 'y'
      }, dir, dev);
      final s3 = (jsonDecode(File('$dir/t.json').readAsStringSync())
          as Map)['_meta']['stamps'] as Map;
      expect(s3['tags'], isNot(s2['tags']),
          reason: 'a changed list must re-stamp');
    });

    test(
        'a cleared field leaves a stamped tombstone (it must not resurrect on merge)',
        () {
      final dir = _tmp();
      final dev = HlcDevice('d');
      persist({'id': 't', 'typeId': 'task', 'description': 'x', 'note': 'temp'},
          dir, dev);
      persist({'id': 't', 'typeId': 'task', 'description': 'x'}, dir,
          dev); // note cleared
      final j = jsonDecode(File('$dir/t.json').readAsStringSync()) as Map;
      expect((j['fields'] as Map).containsKey('note'), isFalse);
      final tombs = j['_meta']['fieldTombstones'] as Map;
      expect(tombs.containsKey('note'), isTrue,
          reason: 'removal must be recorded, not silent');
      expect(tombs['note']['deviceId'], 'd');
      // stamped ONCE: a later unrelated write must not re-stamp the tombstone
      persist({'id': 't', 'typeId': 'task', 'description': 'z'}, dir, dev);
      final t2 = (jsonDecode(File('$dir/t.json').readAsStringSync())
          as Map)['_meta']['fieldTombstones'] as Map;
      expect(t2['note'], tombs['note'],
          reason: 'tombstone is stamped at removal, then carried forward');
      // and if the field comes back it is live again, with no lingering tombstone
      persist({'id': 't', 'typeId': 'task', 'description': 'z', 'note': 'back'},
          dir, dev);
      final j3 = jsonDecode(File('$dir/t.json').readAsStringSync()) as Map;
      expect((j3['fields'] as Map)['note'], 'back');
      expect((j3['_meta'] as Map).containsKey('fieldTombstones'), isFalse);
    });

    test('a corrupt/half-synced file is skipped, not fatal', () {
      final dir = _tmp();
      persist({'id': 'good', 'typeId': 'task', 'description': 'x'}, dir,
          HlcDevice('d'));
      File('$dir/bad.json')
          .writeAsStringSync('{ half written, not valid json ');
      final store = loadRecords(dir);
      expect(store.keys, ['good']);
    });
    test(
        'a valid-JSON record with a corrupt envelope shape is skipped AND surfaced, not fatal',
        () {
      // Regression: the envelope reads (`rec['id'] as String`, fields cast) sat
      // OUTSIDE the try/catch that only guarded jsonDecode, so one shape-defective
      // file (numeric id, missing id, non-map fields) bricked every cold open.
      final dir = _tmp();
      persist({'id': 'good', 'typeId': 'task', 'description': 'x'}, dir,
          HlcDevice('d'));
      File('$dir/numeric-id.json')
          .writeAsStringSync('{"id": 7, "typeId": "task", "fields": {}}');
      File('$dir/no-id.json')
          .writeAsStringSync('{"typeId": "task", "fields": {}}');
      File('$dir/bad-fields.json').writeAsStringSync(
          '{"id": "bad-fields", "typeId": "task", "fields": "oops"}');
      final surfaced = <String>[];
      final store =
          loadRecords(dir, onCorrupt: (path, error) => surfaced.add(path));
      expect(store.keys, ['good']);
      expect(surfaced, contains('$dir/numeric-id.json'));
      expect(surfaced, contains('$dir/no-id.json'));
      expect(surfaced, contains('$dir/bad-fields.json'));
    });
    test('tombstone() marks a record deleted; load skips it', () {
      final dir = _tmp();
      final dev = HlcDevice('d');
      persist({'id': 'x', 'typeId': 'task', 'description': 'y'}, dir, dev);
      tombstone('x', dir, dev);
      expect(loadRecords(dir).containsKey('x'), isFalse);
      expect(
          (jsonDecode(File('$dir/x.json').readAsStringSync()) as Map)['_meta']
              ['deleted'],
          isTrue);
    });
    test('atomic write leaves no .tmp behind', () {
      final dir = _tmp();
      persist({'id': 'x', 'typeId': 'task', 'description': 'y'}, dir,
          HlcDevice('d'));
      expect(File('$dir/x.json.tmp').existsSync(), isFalse);
      expect(File('$dir/x.json').existsSync(), isTrue);
    });
  });
}
