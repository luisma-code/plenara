/// Schema hydration boundary: invalid definitions stay inert and every defect
/// is returned as structured repair state instead of surfacing as a later cast.
library;

import 'value_codec.dart';

enum SchemaIssueSeverity { rejected, degraded }

class SchemaIssue {
  final String code;
  final String source;
  final String message;
  final SchemaIssueSeverity severity;

  const SchemaIssue(this.code, this.source, this.message, this.severity);
}

class SchemaSource {
  final String filename;
  final Map<String, dynamic> definition;

  const SchemaSource(this.filename, this.definition);
}

class SchemaHydration {
  final Map<String, Map<String, dynamic>> definitions;
  final List<SchemaIssue> issues;
  final Set<String> degradedTypes;
  final Set<String> inertAutomations;

  const SchemaHydration({
    required this.definitions,
    required this.issues,
    required this.degradedTypes,
    required this.inertAutomations,
  });
}

class SchemaRegistry {
  static final _typeId = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static final _attributeName = RegExp(r'^[a-z][A-Za-z0-9]{0,63}$');
  static const _archetypes = {
    'timeline',
    'checklist',
    'ledger',
    'journal',
    'person_card',
    'progress',
    'gallery',
    'collection',
    'counter',
    'event_list',
    'key_value',
    'edge',
  };

  final Map<String, Map<String, dynamic>> _definitions;
  final List<SchemaIssue> issues;
  final Set<String> degradedTypes;
  final Set<String> inertAutomations;

  SchemaRegistry._(SchemaHydration hydration)
      : _definitions = hydration.definitions,
        issues = hydration.issues,
        degradedTypes = hydration.degradedTypes,
        inertAutomations = hydration.inertAutomations;

  factory SchemaRegistry.hydrate(
    Iterable<SchemaSource> sources, {
    Map<String, Map<String, dynamic>> skills = const {},
    Map<String, Map<String, dynamic>> automations = const {},
  }) =>
      SchemaRegistry._(
        hydrateSources(sources, skills: skills, automations: automations),
      );

  factory SchemaRegistry.fromDefinitions(
    Map<String, Map<String, dynamic>> definitions, {
    Map<String, Map<String, dynamic>> skills = const {},
    Map<String, Map<String, dynamic>> automations = const {},
  }) =>
      SchemaRegistry.hydrate(
        definitions.entries
            .map((entry) => SchemaSource('${entry.key}.json', entry.value)),
        skills: skills,
        automations: automations,
      );

  Map<String, dynamic>? lookup(String typeId) => _definitions[typeId];
  bool contains(String typeId) => _definitions.containsKey(typeId);
  Map<String, Map<String, dynamic>> get all => Map.unmodifiable(_definitions);

  static SchemaHydration hydrateSources(
    Iterable<SchemaSource> sources, {
    Map<String, Map<String, dynamic>> skills = const {},
    Map<String, Map<String, dynamic>> automations = const {},
  }) {
    final definitions = <String, Map<String, dynamic>>{};
    final issues = <SchemaIssue>[];
    final degraded = <String>{};
    const codec = ValueCodec();

    void reject(String code, SchemaSource source, String message) {
      issues.add(
        SchemaIssue(
            code, source.filename, message, SchemaIssueSeverity.rejected),
      );
    }

    for (final source in sources) {
      final type = Map<String, dynamic>.from(source.definition);
      final id = type['typeId'];
      if (id is! String || !_typeId.hasMatch(id)) {
        reject(
            'invalid_type_id', source, 'typeId must be lowercase snake_case.');
        continue;
      }
      if (source.filename != '$id.json') {
        reject('filename_id_mismatch', source, 'Expected filename $id.json.');
        continue;
      }
      if (definitions.containsKey(id)) {
        reject('duplicate_type_id', source,
            'A type named "$id" is already registered.');
        continue;
      }
      final version = type['schemaVersion'];
      if (version is! int || version <= 0) {
        reject('invalid_schema_version', source,
            '$id.schemaVersion must be a positive integer.');
        continue;
      }
      if (type['displayName'] is! String ||
          (type['displayName'] as String).trim().isEmpty) {
        reject('missing_display_name', source, '$id.displayName is required.');
        continue;
      }
      final rawAttributes = type['attributes'];
      if (rawAttributes is! List) {
        reject('invalid_attributes', source, '$id.attributes must be a list.');
        continue;
      }
      // Same boundary as attributes: a non-list `relations` (e.g. `{}` from a
      // hand edit or a half-synced write) makes the definition invalid repair
      // state — an unguarded cast here crashed hydrate, and startup, on every
      // syncing device.
      final rawRelations = type['relations'];
      if (rawRelations != null && rawRelations is! List) {
        reject('invalid_relations', source, '$id.relations must be a list.');
        continue;
      }
      final names = <String>{};
      var invalid = false;
      final members = [...rawAttributes, ...?rawRelations as List?];
      for (final raw in members) {
        if (raw is! Map) {
          reject('invalid_attribute', source,
              '$id contains a non-object attribute.');
          invalid = true;
          break;
        }
        final attribute = Map<String, dynamic>.from(raw);
        final name = attribute['name'];
        final valueType = attribute['valueType'];
        if (name is! String ||
            !_attributeName.hasMatch(name) ||
            !names.add(name)) {
          reject('invalid_attribute_name', source,
              '$id has an invalid or duplicate attribute name "$name".');
          invalid = true;
          break;
        }
        if (!ValueCodec.valueTypes.contains(valueType)) {
          reject('invalid_value_type', source,
              '$id.$name has unknown valueType "$valueType".');
          invalid = true;
          break;
        }
        if (attribute['required'] is! bool) {
          reject('invalid_required', source,
              '$id.$name.required must be boolean.');
          invalid = true;
          break;
        }
        if (valueType == 'enum') {
          final values = attribute['enumValues'];
          if (values is! List ||
              values.isEmpty ||
              values.any((value) => value is! String)) {
            reject('invalid_enum', source,
                '$id.$name needs a non-empty string enumValues list.');
            invalid = true;
            break;
          }
        }
        if (valueType == 'entityRef' && attribute['refType'] is! String) {
          reject('missing_ref_type', source, '$id.$name needs refType.');
          invalid = true;
          break;
        }
        if (attribute['cardinality'] != null &&
            attribute['cardinality'] != 'one' &&
            attribute['cardinality'] != 'many') {
          reject('invalid_cardinality', source,
              '$id.$name.cardinality must be one or many.');
          invalid = true;
          break;
        }
        if (attribute.containsKey('default')) {
          try {
            codec.coerce(attribute, attribute['default'], requireEntity: false);
          } on ValueCodecError catch (error) {
            reject('invalid_default', source,
                '$id.$name default is invalid: ${error.message}');
            invalid = true;
            break;
          }
        }
      }
      final migrationProblem = _migrationProblem(type);
      if (!invalid && migrationProblem != null) {
        reject('invalid_migrations', source, migrationProblem);
        invalid = true;
      }
      if (!invalid) definitions[id] = type;
    }

    for (final entry in definitions.entries) {
      final type = entry.value;
      final refs = <String>{
        if (type['parentType'] is String) type['parentType'] as String,
        for (final raw in [
          ...?type['attributes'] as List?,
          ...?type['relations'] as List?,
        ])
          if (raw is Map &&
              raw['valueType'] == 'entityRef' &&
              raw['refType'] is String)
            raw['refType'] as String,
      };
      for (final ref in refs) {
        if (!definitions.containsKey(ref)) {
          degraded.add(entry.key);
          issues.add(
            SchemaIssue(
              'unresolved_type_reference',
              '${entry.key}.json',
              '${entry.key} references missing type "$ref"; that edge is inert.',
              SchemaIssueSeverity.degraded,
            ),
          );
        }
      }
      final presentation = type['presentation'];
      if (presentation is Map) {
        final problem = _presentationProblem(type, presentation);
        if (problem != null) {
          degraded.add(entry.key);
          issues.add(
            SchemaIssue(
              'invalid_presentation',
              '${entry.key}.json',
              problem,
              SchemaIssueSeverity.degraded,
            ),
          );
        }
      }
    }

    final inertAutomations = <String>{};
    for (final entry in automations.entries) {
      final automation = entry.value;
      final target = automation['targetType'];
      final skillId = automation['skillId'];
      final pending = automation['pendingSkill'] == true;
      final embedded = automation['skill'];
      final skill = skills[skillId] ??
          (embedded is Map && embedded['skillId'] == skillId
              ? Map<String, dynamic>.from(embedded)
              : null);
      final destructive = skill?['dangerLevel'] == 'destructive';
      if (!definitions.containsKey(target) ||
          (!pending && skill == null) ||
          destructive) {
        inertAutomations.add(entry.key);
        issues.add(
          SchemaIssue(
            'inert_automation',
            '${entry.key}.json',
            'Automation target/skill closure failed or the skill is destructive.',
            SchemaIssueSeverity.degraded,
          ),
        );
      }
    }

    return SchemaHydration(
      definitions: definitions,
      issues: issues,
      degradedTypes: degraded,
      inertAutomations: inertAutomations,
    );
  }

  static String? _presentationProblem(
      Map<String, dynamic> type, Map presentation) {
    final archetype = presentation['archetype'];
    if (!_archetypes.contains(archetype))
      return '${type['typeId']} names an unknown presentation archetype.';
    final attrs = <String, String>{
      for (final raw in ((type['attributes'] as List?) ?? const []))
        if (raw is Map && raw['name'] is String && raw['valueType'] is String)
          raw['name'] as String: raw['valueType'] as String,
    };
    bool eligible(String hint, Set<String> types) {
      final field = presentation[hint];
      return field == null || (field is String && types.contains(attrs[field]));
    }

    if (!eligible('timestampField', {'date', 'datetime'}) ||
        !eligible('valueField', {'number', 'decimal'}) ||
        !eligible('mediaField', {'attachment'})) {
      return '${type['typeId']} has a presentation hint pointing to an ineligible field.';
    }
    if ((archetype == 'key_value' || archetype == 'edge') &&
        type['parentType'] == null) {
      final refs = ((type['relations'] as List?) ?? const [])
          .whereType<Map>()
          .where((relation) => relation['valueType'] == 'entityRef')
          .length;
      if (archetype != 'edge' || refs < 2) {
        return '${type['typeId']} uses child archetype $archetype without an eligible parent/edge shape.';
      }
    }
    return null;
  }

  static String? _migrationProblem(Map<String, dynamic> type) {
    final target = type['schemaVersion'] as int;
    final raw = type['migrations'];
    if (target == 1) {
      return raw == null || (raw is List && raw.isEmpty)
          ? null
          : '${type['typeId']}.migrations must be empty at schemaVersion 1.';
    }
    if (raw is! List) {
      return '${type['typeId']} needs a contiguous migrations list through version $target.';
    }
    final fromVersions = <int>{};
    for (final item in raw) {
      if (item is! Map ||
          item['fromVersion'] is! int ||
          item['toVersion'] != (item['fromVersion'] as int) + 1) {
        return '${type['typeId']} has a migration that does not advance exactly one version.';
      }
      final from = item['fromVersion'] as int;
      if (!fromVersions.add(from)) {
        return '${type['typeId']} has duplicate migrations from version $from.';
      }
      for (final key in const [
        'fieldRenames',
        'fieldDefaults',
        'fieldTypeCoercions',
      ]) {
        if (item[key] != null && item[key] is! Map) {
          return '${type['typeId']} migration $from.$key must be an object.';
        }
      }
      if (item['fieldRemovals'] != null && item['fieldRemovals'] is! List) {
        return '${type['typeId']} migration $from.fieldRemovals must be a list.';
      }
    }
    for (var version = 1; version < target; version++) {
      if (!fromVersions.contains(version)) {
        return '${type['typeId']} is missing migration $version→${version + 1}.';
      }
    }
    return null;
  }
}
