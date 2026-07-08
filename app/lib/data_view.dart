import 'package:flutter/material.dart';
import 'package:plenara/automations.dart';
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

const _months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Render a field value per its Spec 01 §3 value type (Spec 07's per-value-type treatment):
/// dates/datetimes as friendly labels, booleans as ✓/✗, tags/lists joined. A null [valueType]
/// falls back to a best-effort render.
String renderValue(dynamic v, [String? valueType]) {
  if (v == null) return '—';
  switch (valueType) {
    case 'date':
      final d = DateTime.tryParse('$v');
      return d == null ? '$v' : '${_months[d.month]} ${d.day}, ${d.year}';
    case 'datetime':
      final d = DateTime.tryParse('$v');
      if (d == null) return '$v';
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      return '${_months[d.month]} ${d.day}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
    case 'boolean':
      return v == true ? '✓' : '✗';
    default:
      if (v is List) return v.join(' · ');
      return '$v';
  }
}

/// Best-effort render where the value type isn't in hand.
String fmtValue(dynamic v) => renderValue(v, null);

class DataView extends StatefulWidget {
  final Session session;
  const DataView({super.key, required this.session});
  @override
  State<DataView> createState() => _DataViewState();
}

class _DataViewState extends State<DataView> {
  Session get session => widget.session;
  bool _busy = false;

  /// Complete a task from the browse view — routes through the turn engine (so undo/journal
  /// stay intact), then rebuilds. Read paths elsewhere stay untouched.
  Future<void> _complete(String description) async {
    if (_busy) return;
    setState(() => _busy = true);
    await session.handle('mark $description done');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // group records by typeId
    final byType = <String, List<Map<String, dynamic>>>{};
    for (final r in session.store.values) {
      (byType[r['typeId'] as String? ?? '?'] ??= []).add(r);
    }
    final typeIds = byType.keys.toList()..sort();
    final autos = session.automations.statuses;
    return Scaffold(
      appBar: AppBar(title: const Text('Your data'), backgroundColor: cs.inversePrimary),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (autos.isNotEmpty) _AutomationsCard(session: session),
          if (typeIds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('Nothing logged yet.\nStart with a task, a run, or a note.', textAlign: TextAlign.center)),
            )
          else
            for (final typeId in typeIds)
              _TypeSection(
                typeId: typeId,
                typeDef: (session.types[typeId] ?? const {}).cast<String, dynamic>(),
                records: byType[typeId]!,
                onComplete: _complete,
              ),
        ],
      ),
    );
  }
}

/// A compact automation-management surface (Spec 04 §3.9): each registered automation with its
/// live status, plus any writes awaiting review. Read-only — reviews are resolved from the chat.
class _AutomationsCard extends StatelessWidget {
  final Session session;
  const _AutomationsCard({required this.session});

  IconData _icon(String state) => switch (state) {
        'active' => Icons.play_circle,
        'pending' => Icons.hourglass_empty,
        _ => Icons.pause_circle_outline, // deferred / inert
      };

  @override
  Widget build(BuildContext context) {
    final List<AutomationStatus> statuses = session.automations.statuses;
    final pending = session.automations.pendingReview;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Automations', key: const Key('automations-card'), style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            for (final a in statuses)
              ListTile(
                dense: true,
                leading: Icon(_icon(a.state)),
                title: Text(a.automationId),
                subtitle: Text(a.reason ?? a.state),
              ),
            if (pending.isNotEmpty) ...[
              const Divider(),
              for (final p in pending)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.rule),
                  title: Text('Review: ${p.description}'),
                  subtitle: const Text('Say "approve it" or "dismiss it" in the chat.'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypeSection extends StatelessWidget {
  final String typeId;
  final Map<String, dynamic> typeDef;
  final List<Map<String, dynamic>> records;
  final Future<void> Function(String description)? onComplete;
  const _TypeSection({required this.typeId, required this.typeDef, required this.records, this.onComplete});

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
            () {
              final done = r['done'] == true || r['completed'] == true;
              final desc = fmtValue(r['description'] ?? r['title'] ?? r['text']);
              return ListTile(
                dense: true,
                leading: IconButton(
                  icon: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked),
                  tooltip: done ? 'Done' : 'Mark done',
                  onPressed: (done || onComplete == null) ? null : () => onComplete!(desc),
                ),
                title: Text(desc),
                onTap: () => _showRecord(context, r),
              );
            }(),
        ];
      case Archetype.personCard:
        return [
          for (final r in records)
            ListTile(
              dense: true,
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(fmtValue(r['displayName'] ?? r['name'])),
              subtitle: r['aliases'] != null ? Text('aka ${fmtValue(r['aliases'])}') : null,
              onTap: () => _showRecord(context, r),
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
              title: Text(numF == null ? '—' : renderValue(r[numF], _valueTypes[numF])),
              trailing: Text(dateF == null ? '' : renderValue(r[dateF], _valueTypes[dateF])),
              onTap: () => _showRecord(context, r),
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
              trailing: Text(dateF == null ? '' : renderValue(r[dateF], _valueTypes[dateF])),
              onTap: () => _showRecord(context, r),
            ),
        ];
      case Archetype.collection:
        return [
          for (final r in records)
            ListTile(
              dense: true,
              leading: const Icon(Icons.circle, size: 10),
              title: Text(_summary(r)),
              onTap: () => _showRecord(context, r),
            ),
        ];
    }
  }

  /// Field name -> Spec 01 §3 value type, from the type definition (for per-type rendering).
  Map<String, String> get _valueTypes {
    final out = <String, String>{};
    for (final a in ((typeDef['attributes'] as List?) ?? const []).whereType<Map>()) {
      final n = a['name'], vt = a['valueType'];
      if (n is String && vt is String) out[n] = vt;
    }
    return out;
  }

  /// A one-line summary of a record's non-plumbing fields, each rendered per its value type.
  String _summary(Map<String, dynamic> r) {
    final vt = _valueTypes;
    final parts = <String>[];
    for (final e in r.entries) {
      if (const {'id', 'typeId', 'schemaVersion', '_schemaVersion', '_meta'}.contains(e.key)) continue;
      if (e.value == null) continue;
      parts.add('${e.key}: ${renderValue(e.value, vt[e.key])}');
    }
    return parts.isEmpty ? '(empty)' : parts.join('  ·  ');
  }

  /// Drill into one record — a bottom sheet of ALL its fields, each rendered by value type.
  void _showRecord(BuildContext context, Map<String, dynamic> r) {
    final vt = _valueTypes;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((typeDef['displayName'] as String?) ?? typeId,
                  key: const Key('record-detail'), style: Theme.of(context).textTheme.titleLarge),
              const Divider(),
              for (final e in r.entries)
                if (!const {'id', 'typeId', 'schemaVersion', '_schemaVersion', '_meta'}.contains(e.key) && e.value != null)
                  ListTile(dense: true, title: Text(e.key), trailing: Text(renderValue(e.value, vt[e.key]))),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _byDateDesc(List<Map<String, dynamic>> rs, String? dateF) {
    if (dateF == null) return rs;
    final copy = [...rs];
    copy.sort((a, b) => '${b[dateF]}'.compareTo('${a[dateF]}')); // ISO strings sort lexically
    return copy;
  }

  String _trim(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}
