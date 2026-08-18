/// Total schema-value coercion and validation shared by every mutation origin.
library;

import 'dart:io';

class ValueCodecError implements Exception {
  final String code;
  final String message;
  const ValueCodecError(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

class ValueCodec {
  static const valueTypes = {
    'text',
    'number',
    'decimal',
    'boolean',
    'datetime',
    'date',
    'duration',
    'enum',
    'entityRef',
    'tag',
    'attachment',
    'json',
    'integer', // read-compatible legacy alias for number
  };

  const ValueCodec();

  Object? coerce(
    Map<String, dynamic> attribute,
    Object? raw, {
    Map<String, Map<String, dynamic>> records = const {},
    String? dataRoot,
    bool requireEntity = true,
  }) {
    final name = attribute['name']?.toString() ?? '?';
    final type = attribute['valueType']?.toString();
    if (!valueTypes.contains(type)) {
      throw ValueCodecError(
          'unknown_value_type', '$name declares unknown valueType "$type".');
    }
    if (raw == null) return null;

    switch (type) {
      case 'text':
        return raw is String ? raw : raw.toString();
      case 'number':
      case 'integer':
        final number = raw is num
            ? raw.toDouble()
            : double.tryParse(raw.toString().trim());
        if (number == null || !number.isFinite) {
          throw ValueCodecError(
              'invalid_number', '$name expects a finite number.');
        }
        return number;
      case 'decimal':
        final value = raw.toString().trim();
        if (!RegExp(r'^[+-]?(?:0|[1-9]\d*)(?:\.\d+)?$').hasMatch(value)) {
          throw ValueCodecError('invalid_decimal',
              '$name expects a number in exact base-10 form.');
        }
        return value;
      case 'boolean':
        if (raw is bool) return raw;
        switch (raw.toString().trim().toLowerCase()) {
          case 'true':
          case 'yes':
          case '1':
            return true;
          case 'false':
          case 'no':
          case '0':
            return false;
          default:
            throw ValueCodecError(
                'invalid_boolean', '$name expects true or false.');
        }
      case 'datetime':
        final parsed =
            raw is DateTime ? raw : DateTime.tryParse(raw.toString().trim());
        if (parsed == null) {
          throw ValueCodecError(
              'invalid_datetime', '$name expects an ISO 8601 datetime.');
        }
        // Preserve the wall-clock/offset semantics supplied by the resolver.
        // Converting an offset-less local reminder to UTC changes the user's
        // intended hour before the notification scheduler sees it.
        return parsed.toIso8601String();
      case 'date':
        final value = raw is DateTime
            ? '${raw.year.toString().padLeft(4, '0')}-${raw.month.toString().padLeft(2, '0')}-${raw.day.toString().padLeft(2, '0')}'
            : raw.toString().trim();
        final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
        if (match == null) {
          throw ValueCodecError(
              'invalid_date', '$name expects a YYYY-MM-DD date.');
        }
        final y = int.parse(match.group(1)!);
        final m = int.parse(match.group(2)!);
        final d = int.parse(match.group(3)!);
        final rebuilt = DateTime.utc(y, m, d);
        if (rebuilt.year != y || rebuilt.month != m || rebuilt.day != d) {
          throw ValueCodecError(
              'invalid_date', '$name is not a real calendar date.');
        }
        return value;
      case 'duration':
        final value = raw is int ? raw : int.tryParse(raw.toString().trim());
        if (value == null || value < 0) {
          throw ValueCodecError('invalid_duration',
              '$name expects non-negative integer seconds.');
        }
        return value;
      case 'enum':
        final value = raw.toString();
        final allowed = ((attribute['enumValues'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet();
        if (!allowed.contains(value)) {
          throw ValueCodecError(
              'invalid_enum', '$name must be one of: ${allowed.join(', ')}.');
        }
        return value;
      case 'entityRef':
        if (attribute['cardinality'] == 'many') {
          if (raw is! List) {
            throw ValueCodecError(
                'invalid_entity_ref', '$name expects a list of record ids.');
          }
          return [
            for (final value in raw)
              coerce(
                {...attribute, 'cardinality': 'one'},
                value,
                records: records,
                dataRoot: dataRoot,
                requireEntity: requireEntity,
              ),
          ];
        }
        final id = raw.toString().trim();
        if (id.isEmpty) {
          throw ValueCodecError(
              'invalid_entity_ref', '$name expects a record id.');
        }
        final target = records[id];
        if (requireEntity && target == null) {
          throw ValueCodecError(
              'missing_entity_ref', '$name references missing record "$id".');
        }
        final expected = attribute['refType']?.toString();
        if (target != null &&
            expected != null &&
            target['typeId'] != expected) {
          throw ValueCodecError(
            'wrong_entity_type',
            '$name expects a $expected reference, not ${target['typeId']}.',
          );
        }
        return id;
      case 'tag':
        final values = raw is List
            ? raw
            : raw.toString().split(',').map((value) => value.trim()).toList();
        final out = <String>[];
        for (final value in values) {
          if (value is! String) {
            throw ValueCodecError(
                'invalid_tag', '$name expects a list of strings.');
          }
          final trimmed = value.trim();
          if (trimmed.isNotEmpty && !out.contains(trimmed)) out.add(trimmed);
        }
        return out;
      case 'attachment':
        final path = raw.toString().trim();
        final segments = path.replaceAll('\\', '/').split('/');
        final absolute = path.startsWith('/') ||
            path.startsWith('\\') ||
            RegExp(r'^[A-Za-z]:').hasMatch(path);
        if (path.isEmpty ||
            absolute ||
            segments.any((part) => part == '..' || part.isEmpty)) {
          throw ValueCodecError(
              'invalid_attachment', '$name must be a contained relative path.');
        }
        if (dataRoot != null) {
          final root = Directory(dataRoot).absolute.path;
          final resolved =
              File('$root${Platform.pathSeparator}$path').absolute.path;
          if (resolved != root &&
              !resolved.startsWith('$root${Platform.pathSeparator}')) {
            throw ValueCodecError(
                'invalid_attachment', '$name escapes the Plenara data folder.');
          }
        }
        return path;
      case 'json':
        if (raw is! Map) {
          throw ValueCodecError('invalid_json', '$name expects a JSON object.');
        }
        _assertJson(raw, name);
        return Map<String, dynamic>.from(raw);
    }
    throw StateError('unreachable value type $type');
  }

  Map<String, dynamic> validateRecord(
    Map<String, dynamic> type,
    Map<String, dynamic> record, {
    Map<String, Map<String, dynamic>> records = const {},
    String? dataRoot,
    bool requireEntities = true,
  }) {
    final typeId = type['typeId']?.toString();
    if (record['typeId'] != typeId) {
      throw ValueCodecError('wrong_record_type',
          'Record type ${record['typeId']} does not match $typeId.');
    }
    if (record['id'] is! String || (record['id'] as String).isEmpty) {
      throw const ValueCodecError(
          'missing_record_id', 'Record id is required.');
    }
    final attributes = <String, Map<String, dynamic>>{
      for (final raw in ((type['attributes'] as List?) ?? const []))
        if (raw is Map && raw['name'] is String)
          raw['name'] as String: Map<String, dynamic>.from(raw),
    };
    // `createdAt` is structural: store.loadRecords injects the envelope's
    // write-once createdAt into every flat record, and persist routes it back
    // to the envelope. Types may still declare it as an attribute (task does);
    // the attribute loop below then coerces and overwrites the passthrough.
    const structural = {'id', 'typeId', '_schemaVersion', 'parentId', 'createdAt'};
    for (final field in record.keys) {
      if (!structural.contains(field) && !attributes.containsKey(field)) {
        throw ValueCodecError(
            'unknown_field', '$typeId has no field "$field".');
      }
    }
    final out = <String, dynamic>{
      'id': record['id'],
      'typeId': typeId,
      if (record.containsKey('_schemaVersion'))
        '_schemaVersion': record['_schemaVersion'],
      if (record.containsKey('parentId')) 'parentId': record['parentId'],
      if (record.containsKey('createdAt')) 'createdAt': record['createdAt'],
    };
    for (final entry in attributes.entries) {
      final attr = entry.value;
      final hasValue =
          record.containsKey(entry.key) && record[entry.key] != null;
      if (!hasValue && attr['required'] == true) {
        throw ValueCodecError(
            'required_null', '$typeId.${entry.key} is required.');
      }
      if (hasValue) {
        out[entry.key] = coerce(
          attr,
          record[entry.key],
          records: records,
          dataRoot: dataRoot,
          requireEntity: requireEntities,
        );
      } else if (attr.containsKey('default')) {
        out[entry.key] = coerce(
          attr,
          attr['default'],
          records: records,
          dataRoot: dataRoot,
          requireEntity: requireEntities,
        );
      }
    }
    return out;
  }

  void _assertJson(Object? value, String name) {
    if (value == null || value is String || value is bool || value is num)
      return;
    if (value is List) {
      for (final item in value) {
        _assertJson(item, name);
      }
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw ValueCodecError(
              'invalid_json', '$name contains a non-string object key.');
        }
        _assertJson(entry.value, name);
      }
      return;
    }
    throw ValueCodecError('invalid_json', '$name contains a non-JSON value.');
  }
}
