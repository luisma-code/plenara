import 'package:plenara/schema_registry.dart';
import 'package:test/test.dart';

Map<String, dynamic> type(
  String id, {
  int version = 1,
  List<Map<String, dynamic>>? attributes,
  String? parentType,
  Map<String, dynamic>? presentation,
  List<Map<String, dynamic>>? migrations,
}) =>
    {
      'typeId': id,
      'displayName': id,
      'schemaVersion': version,
      'attributes': attributes ??
          [
            {'name': 'name', 'valueType': 'text', 'required': true},
          ],
      if (parentType != null) 'parentType': parentType,
      if (presentation != null) 'presentation': presentation,
      if (migrations != null) 'migrations': migrations,
    };

void main() {
  test(
      'invalid ids, filenames, versions, duplicates, and enum definitions stay inert',
      () {
    final result = SchemaRegistry.hydrate([
      SchemaSource('good.json', type('good')),
      SchemaSource('wrong-name.json', type('mismatch')),
      SchemaSource('zero.json', type('zero', version: 0)),
      SchemaSource('duplicate_a.json', type('duplicate_a')),
      SchemaSource('duplicate_a.json', type('duplicate_a')),
      SchemaSource(
          'bad_enum.json',
          type('bad_enum', attributes: [
            {
              'name': 'state',
              'valueType': 'enum',
              'enumValues': [],
              'required': true
            },
          ])),
    ]);

    expect(result.all.keys, {'good', 'duplicate_a'});
    expect(
        result.issues.map((issue) => issue.code),
        containsAll([
          'filename_id_mismatch',
          'invalid_schema_version',
          'duplicate_type_id',
          'invalid_enum',
        ]));
    expect(
        result.issues
            .where((issue) => issue.severity == SchemaIssueSeverity.rejected)
            .length,
        4);
  });

  test('unresolved references and invalid presentation degrade visibly', () {
    final result = SchemaRegistry.hydrate([
      SchemaSource(
        'child.json',
        type(
          'child',
          parentType: 'missing',
          presentation: {'archetype': 'gallery', 'mediaField': 'name'},
        ),
      ),
    ]);

    expect(result.contains('child'), isTrue,
        reason: 'capture survives cosmetic/cross-link repair');
    expect(result.degradedTypes, {'child'});
    expect(
        result.issues.map((issue) => issue.code),
        containsAll([
          'unresolved_type_reference',
          'invalid_presentation',
        ]));
  });

  test('automation closure makes missing and destructive skills inert', () {
    final result = SchemaRegistry.hydrate(
      [SchemaSource('task.json', type('task'))],
      skills: {
        'erase': {'skillId': 'erase', 'dangerLevel': 'destructive'},
      },
      automations: {
        'missing-target': {'targetType': 'unknown', 'skillId': 'erase'},
        'missing-skill': {'targetType': 'task', 'skillId': 'absent'},
        'destructive': {'targetType': 'task', 'skillId': 'erase'},
        'pending': {
          'targetType': 'task',
          'skillId': 'later',
          'pendingSkill': true
        },
      },
    );

    expect(result.inertAutomations,
        {'missing-target', 'missing-skill', 'destructive'});
    expect(result.inertAutomations, isNot(contains('pending')));
  });

  test('a version bump without a contiguous declarative chain is inert', () {
    final result = SchemaRegistry.hydrate([
      SchemaSource('missing.json', type('missing', version: 2)),
      SchemaSource(
        'valid.json',
        type('valid', version: 2, migrations: [
          {'fromVersion': 1, 'toVersion': 2, 'fieldDefaults': {}}
        ]),
      ),
    ]);

    expect(result.contains('missing'), isFalse);
    expect(result.contains('valid'), isTrue);
    expect(result.issues.map((issue) => issue.code),
        contains('invalid_migrations'));
  });
}
