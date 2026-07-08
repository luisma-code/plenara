import 'package:flutter/material.dart';
import 'package:plenara/session.dart';

/// A first slice of Spec 07 — a read-only "Your data" view. Records are grouped by type and each
/// type renders through an ARCHETYPE chosen from the type's STRUCTURE, not per-type code (Spec 07
/// §4's no-per-type-UI guarantee). This is a faithful subset of the archetype set.
enum Archetype { checklist, personCard, tracker, timeline, collection }

/// Pick an archetype from a type definition's shape (Spec 07 §4, simplified inference).
Archetype archetypeFor(String typeId, Map<String, dynamic> typeDef) {
  final attrs = ((typeDef['attributes'] as List?) ?? const [])
      .whereType<Map>()
      .map((a) => a.cast<String, dynamic>())
      .toList();
  bool boolNamed(String n) => attrs.any((a) => a['name'] == n && a['valueType'] == 'boolean');
  final hasDate = attrs.any((a) => a['valueType'] == 'date' || a['valueType'] == 'datetime');
  final hasNum = attrs.any((a) => a['valueType'] == 'number' || a['valueType'] == 'decimal');
  if (boolNamed('done') || boolNamed('completed')) return Archetype.checklist;
  if (typeId == 'contact') return Archetype.personCard;
  if (hasDate && hasNum) return Archetype.tracker;
  if (hasDate) return Archetype.timeline;
  return Archetype.collection;
}

/// The name of the first date/datetime attribute of a type (the timeline/tracker axis), or null.
String? _dateField(Map<String, dynamic> typeDef) {
  for (final a in ((typeDef['attributes'] as List?) ?? const []).whereType<Map>()) {
    if (a['valueType'] == 'date' || a['valueType'] == 'datetime') return a['name'] as String?;
  }
  return null;
}

String? _numField(Map<String, dynamic> typeDef) {
  for (final a in ((typeDef['attributes'] as List?) ?? const []).whereType<Map>()) {
    if (a['valueType'] == 'number' || a['valueType'] == 'decimal') return a['name'] as String?;
  }
  return null;
}

/// Render one field value readably (dates stay as their ISO/day string; lists as chips-ish text).
String fmtValue(dynamic v) {
  if (v == null) return '—';
  if (v is List) return v.join(', ');
  return '$v';
}

class DataView extends StatelessWidget {
  final Session session;
  const DataView({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // group records by typeId
    final byType = <String, List<Map<String, dynamic>>>{};
    for (final r in session.store.values) {
      (byType[r['typeId'] as String? ?? '?'] ??= []).add(r);
    }
    final typeIds = byType.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Your data'), backgroundColor: cs.inversePrimary),
      body: typeIds.isEmpty
          ? const Center(child: Text('Nothing logged yet.\nStart with a task, a run, or a note.', textAlign: TextAlign.center))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final typeId in typeIds)
                  _TypeSection(
                    typeId: typeId,
                    typeDef: (session.types[typeId] ?? const {}).cast<String, dynamic>(),
                    records: byType[typeId]!,
                  ),
              ],
            ),
    );
  }
}

class _TypeSection extends StatelessWidget {
  final String typeId;
  final Map<String, dynamic> typeDef;
  final List<Map<String, dynamic>> records;
  const _TypeSection({required this.typeId, required this.typeDef, required this.records});

  @override
  Widget build(BuildContext context) {
    final archetype = archetypeFor(typeId, typeDef);
    final title = (typeDef['displayName'] as String?) ?? typeId;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              Chip(
                label: Text('${archetype.name} · ${records.length}'),
                visualDensity: VisualDensity.compact,
                key: Key('archetype-$typeId'),
              ),
            ]),
            const Divider(),
            ..._renderBody(context, archetype),
          ],
        ),
      ),
    );
  }

  List<Widget> _renderBody(BuildContext context, Archetype archetype) {
    switch (archetype) {
      case Archetype.checklist:
        return [
          for (final r in records)
            ListTile(
              dense: true,
              leading: Icon((r['done'] == true || r['completed'] == true)
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked),
              title: Text(fmtValue(r['description'] ?? r['title'] ?? r['text'])),
            ),
        ];
      case Archetype.personCard:
        return [
          for (final r in records)
            ListTile(
              dense: true,
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(fmtValue(r['displayName'] ?? r['name'])),
              subtitle: r['aliases'] != null ? Text('aka ${fmtValue(r['aliases'])}') : null,
            ),
        ];
      case Archetype.tracker:
        final numF = _numField(typeDef);
        final dateF = _dateField(typeDef);
        num total = 0;
        for (final r in records) {
          final v = numF == null ? null : r[numF];
          if (v is num) total += v;
        }
        final sorted = _byDateDesc(records, dateF);
        return [
          Text('${records.length} entries · total ${_trim(total)}',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          for (final r in sorted.take(5))
            ListTile(
              dense: true,
              leading: const Icon(Icons.timeline),
              title: Text(numF == null ? '—' : fmtValue(r[numF])),
              trailing: Text(dateF == null ? '' : fmtValue(r[dateF])),
            ),
        ];
      case Archetype.timeline:
        final dateF = _dateField(typeDef);
        return [
          for (final r in _byDateDesc(records, dateF).take(20))
            ListTile(
              dense: true,
              leading: const Icon(Icons.schedule),
              title: Text(_summary(r)),
              trailing: Text(dateF == null ? '' : fmtValue(r[dateF])),
            ),
        ];
      case Archetype.collection:
        return [
          for (final r in records)
            ListTile(dense: true, leading: const Icon(Icons.circle, size: 10), title: Text(_summary(r))),
        ];
    }
  }

  /// A one-line summary of a record's non-plumbing fields.
  String _summary(Map<String, dynamic> r) {
    final parts = <String>[];
    for (final e in r.entries) {
      if (const {'id', 'typeId', 'schemaVersion', '_meta'}.contains(e.key)) continue;
      if (e.value == null) continue;
      parts.add('${e.key}: ${fmtValue(e.value)}');
    }
    return parts.isEmpty ? '(empty)' : parts.join('  ·  ');
  }

  List<Map<String, dynamic>> _byDateDesc(List<Map<String, dynamic>> rs, String? dateF) {
    if (dateF == null) return rs;
    final copy = [...rs];
    copy.sort((a, b) => '${b[dateF]}'.compareTo('${a[dateF]}')); // ISO strings sort lexically
    return copy;
  }

  String _trim(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}
