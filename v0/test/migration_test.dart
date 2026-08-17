import 'dart:io';

import 'package:plenara/migration.dart';
import 'package:plenara/storage_repository.dart';
import 'package:test/test.dart';

Map<String, dynamic> typeDef({
  required int version,
  required List<Map<String, dynamic>> attributes,
  List<Map<String, dynamic>> migrations = const [],
}) =>
    {
      'typeId': 'x',
      'schemaVersion': version,
      'attributes': attributes,
      'migrations': migrations,
    };

Map<String, dynamic> step(
  int from, {
  Map<String, String> renames = const {},
  Map<String, Map<String, String>> coercions = const {},
  Map<String, dynamic> defaults = const {},
  List<String> removals = const [],
}) =>
    {
      'fromVersion': from,
      'toVersion': from + 1,
      'fieldRenames': renames,
      'fieldTypeCoercions': coercions,
      'fieldDefaults': defaults,
      'fieldRemovals': removals,
    };

void main() {
  group('declarative migration chain', () {
    test('applies rename, coerce, default, and remove in contiguous order', () {
      final original = {
        'id': 'r1',
        'typeId': 'x',
        '_schemaVersion': 1,
        'oldTitle': 'Plan',
        'seconds': 90,
        'obsolete': true,
      };
      final type = typeDef(
        version: 3,
        attributes: [
          {'name': 'title', 'valueType': 'text', 'required': true},
          {'name': 'secondsText', 'valueType': 'text'},
          {
            'name': 'status',
            'valueType': 'enum',
            'enumValues': ['open']
          },
        ],
        migrations: [
          step(1, renames: {
            'oldTitle': 'title',
            'seconds': 'secondsText',
          }),
          step(
            2,
            coercions: {
              'secondsText': {'from': 'number', 'to': 'text'},
            },
            defaults: {'status': 'open'},
            removals: ['obsolete'],
          ),
        ],
      );

      final result = migrateRecord(original, type);

      expect(result.failure, isNull);
      expect(result.changed, isTrue);
      expect(result.record, {
        'id': 'r1',
        'typeId': 'x',
        '_schemaVersion': 3,
        'title': 'Plan',
        'secondsText': '90',
        'status': 'open',
      });
      expect(original, containsPair('_schemaVersion', 1));
      expect(original, contains('oldTitle'));
    });

    test('supports nested dot paths without mutating the input tree', () {
      final original = {
        'id': 'r1',
        'typeId': 'x',
        '_schemaVersion': 1,
        'profile': {'oldName': 'Luis'},
      };
      final result = migrateRecord(
        original,
        typeDef(
          version: 2,
          attributes: [
            {'name': 'profile', 'valueType': 'json'},
          ],
          migrations: [
            step(1, renames: {'profile.oldName': 'profile.name'}),
          ],
        ),
      );

      expect(result.failure, isNull);
      expect(result.record['profile'], {'name': 'Luis'});
      expect(original['profile'], {'oldName': 'Luis'});
    });

    test('missing chain leaves the exact old record and version untouched', () {
      final original = {
        'id': 'r1',
        'typeId': 'x',
        '_schemaVersion': 1,
        'title': 'Keep me',
      };
      final result = migrateRecord(
        original,
        typeDef(
          version: 3,
          attributes: [
            {'name': 'title', 'valueType': 'text'},
          ],
          migrations: [step(2)],
        ),
      );

      expect(result.changed, isFalse);
      expect(result.failure?.code, 'missing_migration_step');
      expect(result.record, original);
    });

    test('unsafe retype fails atomically', () {
      final original = {
        'id': 'r1',
        'typeId': 'x',
        '_schemaVersion': 1,
        'value': 'not safely numeric',
      };
      final result = migrateRecord(
        original,
        typeDef(
          version: 2,
          attributes: [
            {'name': 'value', 'valueType': 'number'},
          ],
          migrations: [
            step(1, coercions: {
              'value': {'from': 'text', 'to': 'number'},
            }),
          ],
        ),
      );

      expect(result.failure?.code, 'unsafe_type_coercion');
      expect(result.record, original);
    });

    test('date to datetime accepts an already-written ISO timestamp', () {
      final original = {
        'id': 'r1',
        'typeId': 'x',
        '_schemaVersion': 1,
        'createdAt': '2026-08-17T09:10:11.000Z',
      };
      final result = migrateRecord(
        original,
        typeDef(
          version: 2,
          attributes: [
            {
              'name': 'createdAt',
              'valueType': 'datetime',
              'required': true,
            },
          ],
          migrations: [
            step(1, coercions: {
              'createdAt': {'from': 'date', 'to': 'datetime'},
            }),
          ],
        ),
      );

      expect(result.failure, isNull);
      expect(result.record['createdAt'], '2026-08-17T09:10:11.000Z');
      expect(result.record['_schemaVersion'], 2);
    });

    test('target enum/date/decimal/entity validation blocks version advance',
        () {
      final definitions = [
        (
          {'status': 'retired'},
          {
            'name': 'status',
            'valueType': 'enum',
            'enumValues': ['open']
          }
        ),
        ({'day': '2026-02-30'}, {'name': 'day', 'valueType': 'date'}),
        ({'amount': 'NaN'}, {'name': 'amount', 'valueType': 'decimal'}),
        (
          {'person': 'missing'},
          {'name': 'person', 'valueType': 'entityRef', 'refType': 'contact'}
        ),
      ];
      for (final pair in definitions) {
        final field = pair.$1;
        final result = migrateRecord(
          {
            'id': 'r1',
            'typeId': 'x',
            '_schemaVersion': 1,
            ...field,
          },
          typeDef(version: 2, attributes: [pair.$2], migrations: [step(1)]),
          records: const {
            'other': {'id': 'other', 'typeId': 'contact'}
          },
        );
        expect(result.failure?.code, 'target_validation_failed',
            reason: 'invalid field $field must not advance');
        expect(result.record['_schemaVersion'], 1);
      }
    });

    test('required null and undeclared retained fields fail validation', () {
      for (final original in [
        {'id': 'r1', 'typeId': 'x', '_schemaVersion': 1},
        {
          'id': 'r1',
          'typeId': 'x',
          '_schemaVersion': 1,
          'title': 'ok',
          'stale': true,
        },
      ]) {
        final result = migrateRecord(
          original,
          typeDef(
            version: 2,
            attributes: [
              {'name': 'title', 'valueType': 'text', 'required': true},
            ],
            migrations: [step(1)],
          ),
        );
        expect(result.failure?.code, 'target_validation_failed');
        expect(result.record, original);
      }
    });
  });

  test('current and future records are returned untouched', () {
    for (final version in [2, 5]) {
      final record = {
        'id': 'r1',
        'typeId': 'x',
        '_schemaVersion': version,
        'title': 'same',
      };
      final result = migrateRecord(
        record,
        typeDef(version: 2, attributes: const []),
      );
      expect(result.changed, isFalse);
      expect(result.failure, isNull);
      expect(identical(result.record, record), isTrue);
    }
  });

  test('absent record version reads as version one', () {
    expect(recordVersion({'id': 'r1'}), 1);
  });

  test('filesystem backup restores the exact pre-migration record bytes', () {
    final root =
        Directory.systemTemp.createTempSync('plenara_migration_backup_');
    addTearDown(() => root.deleteSync(recursive: true));
    final data = Directory('${root.path}/data')..createSync();
    final device = Directory('${root.path}/device')..createSync();
    final repository = FileStorageRepository(
      data.path,
      deviceDir: device.path,
    );
    repository.persist({
      'id': 'r1',
      'typeId': 'x',
      '_schemaVersion': 1,
      'oldTitle': 'Plan',
    });
    final recordFile = File('${data.path}/records/r1.json');
    final exactBefore = recordFile.readAsBytesSync();
    final loadedBefore = repository.loadRecords()['r1']!;

    final backup = repository.backupForMigration(loadedBefore, 2);
    repository.persist({
      'id': 'r1',
      'typeId': 'x',
      '_schemaVersion': 2,
      'title': 'Plan',
    });
    expect(repository.loadRecords()['r1']!['_schemaVersion'], 2);

    repository.restoreMigrationBackup(backup);

    expect(recordFile.readAsBytesSync(), exactBefore);
    expect(repository.loadRecords()['r1'], loadedBefore);
  });
}
