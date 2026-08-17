import 'dart:convert';
import 'dart:io';

import 'package:plenara/session.dart';
import 'package:test/test.dart';

Directory copySeed() {
  final root = Directory.systemTemp.createTempSync('plenara_schema_hydration_');
  for (final entity in Directory('data').listSync(recursive: true)) {
    final relative = entity.path.substring('data'.length + 1);
    final target = '${root.path}${Platform.pathSeparator}$relative';
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      File(target)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
  }
  return root;
}

void main() {
  test('startup exposes a corrupt durable journal as a repair issue', () async {
    final root = copySeed();
    addTearDown(() => root.deleteSync(recursive: true));
    final device =
        Directory.systemTemp.createTempSync('plenara_journal_repair_');
    addTearDown(() => device.deleteSync(recursive: true));
    File('${device.path}/execution-journal.json')
        .writeAsStringSync('{interrupted');

    final session = Session(root.path, deviceDir: device.path);
    await session.init(retrieval: false);

    expect(session.executionRepairIssues.single,
        startsWith('execution_journal_corrupt:'));
    expect(File('${device.path}/execution-journal.json.corrupt').existsSync(),
        isTrue);
  });

  test('startup keeps invalid files inert and exposes structured repair state',
      () async {
    final root = copySeed();
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/types/not-the-id.json').writeAsStringSync(jsonEncode({
      'typeId': 'wrong_id',
      'displayName': 'Wrong',
      'schemaVersion': 1,
      'attributes': <Object>[],
    }));
    File('${root.path}/types/orphan.json').writeAsStringSync(jsonEncode({
      'typeId': 'orphan',
      'displayName': 'Orphan',
      'schemaVersion': 1,
      'parentType': 'missing_parent',
      'attributes': <Object>[],
    }));

    final session = Session(root.path);
    await session.init(retrieval: false);

    expect(session.types, isNot(contains('wrong_id')));
    expect(session.types, contains('orphan'));
    expect(session.schemaRegistry.degradedTypes, contains('orphan'));
    expect(
      session.schemaRegistry.issues.map((issue) => issue.code),
      containsAll(['filename_id_mismatch', 'unresolved_type_reference']),
    );
  });

  test('failed and future-version migrations are parked from typed reads',
      () async {
    final root = copySeed();
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/types/metric.json').writeAsStringSync(jsonEncode({
      'typeId': 'metric',
      'displayName': 'Metric',
      'schemaVersion': 2,
      'attributes': [
        {'name': 'value', 'valueType': 'number', 'required': true}
      ],
      'migrations': [
        {
          'fromVersion': 1,
          'toVersion': 2,
          'fieldTypeCoercions': {
            'value': {'from': 'text', 'to': 'number'}
          }
        }
      ],
    }));
    final records = Directory('${root.path}/records')..createSync();
    File('${records.path}/bad.json').writeAsStringSync(jsonEncode({
      'id': 'bad',
      'typeId': 'metric',
      'schemaVersion': 1,
      'fields': {'value': 'not-safe'},
      '_meta': {'stamps': {}}
    }));
    File('${records.path}/future.json').writeAsStringSync(jsonEncode({
      'id': 'future',
      'typeId': 'metric',
      'schemaVersion': 3,
      'fields': {'value': 1},
      '_meta': {'stamps': {}}
    }));

    final session = Session(root.path);
    await session.init(retrieval: false);

    expect(session.store, isNot(contains('bad')));
    expect(session.store, isNot(contains('future')));
    expect(
      session.migrationRepairItems.map((item) => item.code),
      containsAll(['unsafe_type_coercion', 'version_too_new']),
    );
    expect(
        jsonDecode(File('${records.path}/bad.json').readAsStringSync())[
            'schemaVersion'],
        1);
  });
}
