/// Deterministic, declarative record migrations (Spec 01 §7 / Spec 06 §8).
library;

import 'value_codec.dart';

int recordVersion(Map<String, dynamic> record) =>
    (record['_schemaVersion'] as int?) ?? 1;

int typeVersion(Map<String, dynamic> typeDef) =>
    (typeDef['schemaVersion'] as int?) ?? 1;

bool isFutureVersioned(
        Map<String, dynamic> record, Map<String, dynamic> typeDef) =>
    recordVersion(record) > typeVersion(typeDef);

class MigrationFailure {
  final String code;
  final String message;
  final int fromVersion;

  const MigrationFailure(this.code, this.message, this.fromVersion);

  @override
  String toString() => '$code at v$fromVersion: $message';
}

class RecordMigrationResult {
  final Map<String, dynamic> record;
  final bool changed;
  final MigrationFailure? failure;

  const RecordMigrationResult({
    required this.record,
    required this.changed,
    this.failure,
  });
}

class MigrationRepairItem {
  final String recordId;
  final String typeId;
  final String code;
  final String message;
  final Map<String, dynamic> rawRecord;

  const MigrationRepairItem({
    required this.recordId,
    required this.typeId,
    required this.code,
    required this.message,
    required this.rawRecord,
  });
}

RecordMigrationResult migrateRecord(
  Map<String, dynamic> record,
  Map<String, dynamic> typeDef, {
  ValueCodec codec = const ValueCodec(),
  Map<String, Map<String, dynamic>> records = const {},
  String? dataRoot,
}) {
  final original = _copy(record);
  final start = recordVersion(record);
  final target = typeVersion(typeDef);
  if (start >= target) {
    return RecordMigrationResult(record: record, changed: false);
  }

  try {
    final migrations = ((typeDef['migrations'] as List?) ?? const [])
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();
    final byFrom = <int, Map<String, dynamic>>{};
    for (final step in migrations) {
      final from = step['fromVersion'];
      final to = step['toVersion'];
      if (from is! int || to is! int || to != from + 1) {
        throw MigrationFailure(
          'invalid_migration_step',
          'Each step must advance exactly one positive version.',
          start,
        );
      }
      if (byFrom.containsKey(from)) {
        throw MigrationFailure(
          'duplicate_migration_step',
          'More than one migration starts at version $from.',
          from,
        );
      }
      byFrom[from] = step;
    }

    var current = start;
    var out = _copy(record);
    while (current < target) {
      final step = byFrom[current];
      if (step == null || step['toVersion'] != current + 1) {
        throw MigrationFailure(
          'missing_migration_step',
          'No contiguous migration from version $current to ${current + 1}.',
          current,
        );
      }
      out = _applyStep(out, step, current);
      current++;
      out['_schemaVersion'] = current;
    }

    final validated = codec.validateRecord(
      typeDef,
      out,
      records: records,
      dataRoot: dataRoot,
      requireEntities: records.isNotEmpty,
    );
    validated['_schemaVersion'] = target;
    return RecordMigrationResult(record: validated, changed: true);
  } on MigrationFailure catch (failure) {
    return RecordMigrationResult(
      record: original,
      changed: false,
      failure: failure,
    );
  } on ValueCodecError catch (error) {
    return RecordMigrationResult(
      record: original,
      changed: false,
      failure: MigrationFailure(
        'target_validation_failed',
        error.toString(),
        start,
      ),
    );
  } catch (error) {
    return RecordMigrationResult(
      record: original,
      changed: false,
      failure: MigrationFailure('migration_failed', '$error', start),
    );
  }
}

Map<String, dynamic> _applyStep(
  Map<String, dynamic> record,
  Map<String, dynamic> step,
  int version,
) {
  final out = _copy(record);
  final renames = _stringMap(step['fieldRenames'], 'fieldRenames', version);
  for (final entry in renames.entries) {
    if (!_hasPath(out, entry.key)) continue;
    if (_hasPath(out, entry.value)) {
      throw MigrationFailure(
        'rename_collision',
        'Cannot rename ${entry.key} to existing ${entry.value}.',
        version,
      );
    }
    final value = _getPath(out, entry.key);
    _removePath(out, entry.key);
    _setPath(out, entry.value, value);
  }

  final coercions = step['fieldTypeCoercions'];
  if (coercions != null && coercions is! Map) {
    throw MigrationFailure(
      'invalid_type_coercions',
      'fieldTypeCoercions must be an object.',
      version,
    );
  }
  for (final raw in (coercions as Map? ?? const {}).entries) {
    final path = raw.key.toString();
    if (!_hasPath(out, path)) continue;
    if (raw.value is! Map) {
      throw MigrationFailure(
        'invalid_type_coercion',
        '$path must declare from and to.',
        version,
      );
    }
    final descriptor = Map<String, dynamic>.from(raw.value as Map);
    _setPath(
      out,
      path,
      _coerceMigrationValue(
        _getPath(out, path),
        descriptor['from']?.toString(),
        descriptor['to']?.toString(),
        path,
        version,
      ),
    );
  }

  final defaults = step['fieldDefaults'];
  if (defaults != null && defaults is! Map) {
    throw MigrationFailure(
      'invalid_field_defaults',
      'fieldDefaults must be an object.',
      version,
    );
  }
  for (final raw in (defaults as Map? ?? const {}).entries) {
    final path = raw.key.toString();
    if (!_hasPath(out, path)) _setPath(out, path, _deepCopy(raw.value));
  }

  final removals = step['fieldRemovals'];
  if (removals != null && removals is! List) {
    throw MigrationFailure(
      'invalid_field_removals',
      'fieldRemovals must be a list.',
      version,
    );
  }
  for (final raw in (removals as List? ?? const [])) {
    _removePath(out, raw.toString());
  }
  return out;
}

Object? _coerceMigrationValue(
  Object? value,
  String? from,
  String? to,
  String path,
  int version,
) {
  if (from == null || to == null) {
    throw MigrationFailure(
      'invalid_type_coercion',
      '$path must declare from and to.',
      version,
    );
  }
  if (to == 'json') return {'value': value};
  switch ('$from->$to') {
    case 'number->text':
    case 'boolean->text':
    case 'enum->text':
    case 'datetime->text':
    case 'date->text':
      return value.toString();
    case 'date->datetime':
      final raw = '$value'.trim();
      final date = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)
          ? DateTime.tryParse('${raw}T00:00:00Z')
          : null;
      if (date != null) return date.toUtc().toIso8601String();
      // Early task writers already emitted an ISO timestamp even though the
      // v1 schema called createdAt a date. Treat an already-valid target value
      // as idempotent instead of parking real records during the schema fix.
      final alreadyDatetime =
          RegExp(r'^\d{4}-\d{2}-\d{2}[Tt ]\d{2}:\d{2}').hasMatch(raw) &&
              DateTime.tryParse(raw) != null;
      if (alreadyDatetime) return raw;
      break;
    case 'duration->number':
      if (value is int && value >= 0) return value.toDouble();
      break;
  }
  throw MigrationFailure(
    'unsafe_type_coercion',
    'Cannot safely coerce $path from $from to $to.',
    version,
  );
}

Map<String, String> _stringMap(Object? raw, String field, int version) {
  if (raw == null) return const {};
  if (raw is! Map) {
    throw MigrationFailure(
      'invalid_$field',
      '$field must be an object.',
      version,
    );
  }
  return {for (final entry in raw.entries) '${entry.key}': '${entry.value}'};
}

List<String> _parts(String path) =>
    path.split('.').where((part) => part.isNotEmpty).toList();

bool _hasPath(Map<String, dynamic> map, String path) {
  Object? cursor = map;
  for (final part in _parts(path)) {
    if (cursor is! Map || !cursor.containsKey(part)) return false;
    cursor = cursor[part];
  }
  return true;
}

Object? _getPath(Map<String, dynamic> map, String path) {
  Object? cursor = map;
  for (final part in _parts(path)) {
    cursor = (cursor as Map)[part];
  }
  return cursor;
}

void _setPath(Map<String, dynamic> map, String path, Object? value) {
  final parts = _parts(path);
  if (parts.isEmpty) throw ArgumentError.value(path, 'path');
  var cursor = map;
  for (final part in parts.take(parts.length - 1)) {
    final existing = cursor[part];
    if (existing == null) {
      final child = <String, dynamic>{};
      cursor[part] = child;
      cursor = child;
    } else if (existing is Map<String, dynamic>) {
      cursor = existing;
    } else if (existing is Map) {
      final child = Map<String, dynamic>.from(existing);
      cursor[part] = child;
      cursor = child;
    } else {
      throw ArgumentError('Composite path crosses scalar field $part.');
    }
  }
  cursor[parts.last] = value;
}

void _removePath(Map<String, dynamic> map, String path) {
  final parts = _parts(path);
  if (parts.isEmpty) return;
  Map? cursor = map;
  for (final part in parts.take(parts.length - 1)) {
    final next = cursor?[part];
    if (next is! Map) return;
    cursor = next;
  }
  cursor?.remove(parts.last);
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    _deepCopy(value) as Map<String, dynamic>;

Object? _deepCopy(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _deepCopy(entry.value),
    };
  }
  if (value is List) return value.map(_deepCopy).toList();
  return value;
}
