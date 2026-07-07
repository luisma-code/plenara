/// Storage + CRDT layer (Spec 04 §3.1 / storage-crdt spike). Per-record file
/// shape, the `_meta` HLC block, round-trips, HLC monotonicity, and undoTurn
/// (create/update reversal) on both memory and disk.
import 'dart:convert';
import 'dart:io';

import 'package:plenara/store.dart';
import 'package:test/test.dart';

String _tmp() => Directory.systemTemp.createTempSync('plenara_store_').path;

void main() {
  group('loadDefs', () {
    test('indexes type defs by typeId', () {
      final types = loadDefs('data/types', 'typeId');
      expect(types.keys,
          containsAll(['task', 'contact', 'workout', 'mood', 'contact_fact', 'contact_relationship']));
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
      persist({'id': 'task-1', 'typeId': 'task', 'description': 'buy milk', 'completed': false, 'dueAt': null},
          dir, HlcDevice('dev-A'));
      final j = jsonDecode(File('$dir/task-1.json').readAsStringSync()) as Map<String, dynamic>;
      expect(j['id'], 'task-1');
      expect(j['typeId'], 'task');
      expect(j['fields']['description'], 'buy milk');
      expect(j['fields']['completed'], false);
      expect((j['fields'] as Map).containsKey('dueAt'), isTrue, reason: 'null field is kept');
      expect((j['fields'] as Map).containsKey('id'), isFalse, reason: 'id/typeId not duplicated into fields');
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
      persist({'id': 'w-1', 'typeId': 'workout', 'activity': 'run', 'distance': 5, 'date': '2026-07-06'}, dir, dev);
      persist({'id': 'w-2', 'typeId': 'workout', 'activity': 'walk', 'distance': 2.5, 'date': '2026-07-07'}, dir, dev);
      persist({'id': 't-1', 'typeId': 'task', 'description': 'x', 'completed': true, 'dueAt': null}, dir, dev);
      final store = loadRecords(dir);
      expect(store.length, 3);
      expect(store['w-1'], {'id': 'w-1', 'typeId': 'workout', 'activity': 'run', 'distance': 5, 'date': '2026-07-06'});
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
    test('1000 stamps strictly increase by (ms, counter); deviceId constant', () {
      final dev = HlcDevice('dev-A');
      final stamps = List.generate(1000, (_) => dev.stamp());
      for (var i = 1; i < stamps.length; i++) {
        final a = stamps[i - 1], b = stamps[i];
        final aMs = a['ms'] as int, bMs = b['ms'] as int;
        expect(bMs >= aMs, isTrue, reason: 'ms non-decreasing');
        if (bMs == aMs) {
          expect(b['counter'] as int, greaterThan(a['counter'] as int), reason: 'counter increments within a ms');
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
    test('created record (prior null) -> tombstoned, not resurrectable by a sync restore', () {
      final dir = _tmp();
      final dev = HlcDevice('d');
      final store = <String, Map<String, dynamic>>{'t-1': {'id': 't-1', 'typeId': 'task', 'description': 'x'}};
      persist(store['t-1']!, dir, dev);
      undoTurn({'t-1': null}, dir, dev, store);
      expect(store.containsKey('t-1'), isFalse);
      expect(File('$dir/t-1.json').existsSync(), isTrue); // tombstone file remains (CRDT)
      expect((jsonDecode(File('$dir/t-1.json').readAsStringSync()) as Map)['_meta']['deleted'], isTrue);
      expect(loadRecords(dir), isEmpty); // and a reload cannot bring it back
    });

    test('updated record (prior != null) -> restored in memory + disk', () {
      final dir = _tmp();
      final dev = HlcDevice('d');
      final store = <String, Map<String, dynamic>>{'t-1': {'id': 't-1', 'typeId': 'task', 'description': 'new'}};
      persist(store['t-1']!, dir, dev);
      undoTurn({'t-1': <String, dynamic>{'id': 't-1', 'typeId': 'task', 'description': 'old'}}, dir, dev, store);
      expect(store['t-1']!['description'], 'old');
      final j = jsonDecode(File('$dir/t-1.json').readAsStringSync()) as Map<String, dynamic>;
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
      undoTurn({'a': null, 'b': <String, dynamic>{'id': 'b', 'typeId': 'task', 'description': 'before'}}, dir, dev, store);
      expect(store.containsKey('a'), isFalse);
      expect(loadRecords(dir).containsKey('a'), isFalse); // tombstoned -> not loaded
      expect(store['b']!['description'], 'before');
    });
  });

  group('CRDT fidelity (Fable review)', () {
    test('stamp-on-change: an unchanged field keeps its prior stamp', () {
      final dir = _tmp();
      final dev = HlcDevice('d');
      persist({'id': 't', 'typeId': 'task', 'description': 'a', 'completed': false}, dir, dev);
      final s1 = (jsonDecode(File('$dir/t.json').readAsStringSync()) as Map)['_meta']['stamps'] as Map;
      persist({'id': 't', 'typeId': 'task', 'description': 'a', 'completed': true}, dir, dev); // only completed changed
      final s2 = (jsonDecode(File('$dir/t.json').readAsStringSync()) as Map)['_meta']['stamps'] as Map;
      expect(s2['description'], s1['description'], reason: 'unchanged field keeps its stamp');
      expect(s2['completed'], isNot(s1['completed']), reason: 'changed field gets a fresh stamp');
    });
    test('a corrupt/half-synced file is skipped, not fatal', () {
      final dir = _tmp();
      persist({'id': 'good', 'typeId': 'task', 'description': 'x'}, dir, HlcDevice('d'));
      File('$dir/bad.json').writeAsStringSync('{ half written, not valid json ');
      final store = loadRecords(dir);
      expect(store.keys, ['good']);
    });
    test('tombstone() marks a record deleted; load skips it', () {
      final dir = _tmp();
      final dev = HlcDevice('d');
      persist({'id': 'x', 'typeId': 'task', 'description': 'y'}, dir, dev);
      tombstone('x', dir, dev);
      expect(loadRecords(dir).containsKey('x'), isFalse);
      expect((jsonDecode(File('$dir/x.json').readAsStringSync()) as Map)['_meta']['deleted'], isTrue);
    });
    test('atomic write leaves no .tmp behind', () {
      final dir = _tmp();
      persist({'id': 'x', 'typeId': 'task', 'description': 'y'}, dir, HlcDevice('d'));
      expect(File('$dir/x.json.tmp').existsSync(), isFalse);
      expect(File('$dir/x.json').existsSync(), isTrue);
    });
  });
}
