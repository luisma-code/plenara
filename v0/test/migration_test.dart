import 'package:plenara/migration.dart';
import 'package:test/test.dart';

void main() {
  Map<String, dynamic> typeV(int v, List<Map<String, dynamic>> attrs) => {'schemaVersion': v, 'attributes': attrs};

  group('migrateRecord (Spec 01 §7.4 / Spec 06 D12)', () {
    test('a v1 record migrates to the type v2 — a new optional attr takes its default', () {
      final rec = {'id': 'r1', 'typeId': 'x', 'a': 1, '_schemaVersion': 1};
      final type = typeV(2, [
        {'name': 'a', 'valueType': 'number'},
        {'name': 'b', 'valueType': 'text', 'default': '-'},
      ]);
      final m = migrateRecord(rec, type);
      expect(m.changed, isTrue);
      expect(m.record['a'], 1); // existing value preserved
      expect(m.record['b'], '-'); // new attr defaulted
      expect(m.record['_schemaVersion'], 2); // stamped forward
    });

    test('a missing attr with no default becomes null', () {
      final m = migrateRecord({'id': 'r1', 'typeId': 'x', '_schemaVersion': 1}, typeV(2, [
        {'name': 'b', 'valueType': 'text'},
      ]));
      expect(m.changed, isTrue);
      expect(m.record.containsKey('b'), isTrue);
      expect(m.record['b'], isNull);
    });

    test('a record without _schemaVersion is treated as v1 (absent ⇒ 1)', () {
      final m = migrateRecord({'id': 'r1', 'typeId': 'x'}, typeV(2, [{'name': 'b', 'valueType': 'text', 'default': 0}]));
      expect(m.changed, isTrue);
      expect(m.record['_schemaVersion'], 2);
    });

    test('a record already at the type version is untouched', () {
      final rec = {'id': 'r1', 'typeId': 'x', '_schemaVersion': 2};
      final m = migrateRecord(rec, typeV(2, [{'name': 'b', 'valueType': 'text'}]));
      expect(m.changed, isFalse);
      expect(identical(m.record, rec), isTrue);
    });

    test('a FUTURE-versioned record is left intact, not mangled (versionTooNew)', () {
      final rec = {'id': 'r1', 'typeId': 'x', '_schemaVersion': 5, 'b': 'from-newer-app'};
      final type = typeV(2, [{'name': 'b', 'valueType': 'text'}]);
      expect(isFutureVersioned(rec, type), isTrue);
      final m = migrateRecord(rec, type);
      expect(m.changed, isFalse);
      expect(m.record['b'], 'from-newer-app');
    });

    test('an existing value is never overwritten by a default', () {
      final m = migrateRecord({'id': 'r1', 'typeId': 'x', 'b': 'real', '_schemaVersion': 1},
          typeV(2, [{'name': 'b', 'valueType': 'text', 'default': 'DEFAULT'}]));
      expect(m.record['b'], 'real');
    });
  });
}
