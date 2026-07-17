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

  /// Edit one field (Spec 07 §5.5 tap-to-edit) — validates in the engine. The FAILURE message is
  /// surfaced by the detail sheet inline (a SnackBar would render behind the modal sheet, invisible),
  /// so this just persists + refreshes the view and hands the result back to the sheet.
  Future<ManualWrite> _edit(String id, String field, Object? value) async {
    final r = await session.editField(id, field, value);
    if (mounted) setState(() {});
    return r;
  }

  /// Delete a record with an UNDO snackbar — the voice-undo ethos (act-then-describe), doubly
  /// reversible (journal + storage tombstone), so no pre-delete confirm dialog. The UNDO is TARGETED
  /// to this delete's journal entry, so a later write can't make it reverse the wrong thing.
  Future<void> _delete(String id) async {
    final r = await session.deleteRecord(id);
    if (!mounted) return;
    setState(() {});
    if (r.ok) {
      final token = r.undoId;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.message),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            if (token != null) await session.undoById(token);
            if (mounted) setState(() {});
          },
        ),
      ));
    }
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
                session: session,
                typeId: typeId,
                typeDef: (session.types[typeId] ?? const {}).cast<String, dynamic>(),
                records: byType[typeId]!,
                onComplete: _complete,
                onEdit: _edit,
                onDelete: _delete,
              ),
          _LearnedPhrasesCard(session: session),
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
  final Session session;
  final String typeId;
  final Map<String, dynamic> typeDef;
  final List<Map<String, dynamic>> records;
  final Future<void> Function(String description)? onComplete;
  final Future<ManualWrite> Function(String id, String field, Object? value) onEdit;
  final Future<void> Function(String id) onDelete;
  const _TypeSection({
    required this.session,
    required this.typeId,
    required this.typeDef,
    required this.records,
    required this.onEdit,
    required this.onDelete,
    this.onComplete,
  });

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

  /// Drill into one record — an editable bottom sheet (Spec 07 §5.5 tap-to-edit + delete).
  void _showRecord(BuildContext context, Map<String, dynamic> r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecordDetailSheet(
        session: session,
        typeId: typeId,
        typeDef: typeDef,
        recordId: r['id'] as String,
        onEdit: onEdit,
        onDelete: onDelete,
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

const _plumbingFields = {'id', 'typeId', 'schemaVersion', '_schemaVersion', '_meta'};

/// An editable record detail sheet (Spec 07 §5.5 tap-to-edit — a reading page, NOT a form: each
/// value edits in place and commits on its own, one journal entry per field). Reads the live record
/// from the store each build, so an edit (or its undo) reflects immediately. Type-agnostic: rows
/// and editors are driven off `typeDef.attributes`, never per-type code.
class _RecordDetailSheet extends StatefulWidget {
  final Session session;
  final String typeId;
  final Map<String, dynamic> typeDef;
  final String recordId;
  final Future<ManualWrite> Function(String id, String field, Object? value) onEdit;
  final Future<void> Function(String id) onDelete;
  const _RecordDetailSheet({
    required this.session,
    required this.typeId,
    required this.typeDef,
    required this.recordId,
    required this.onEdit,
    required this.onDelete,
  });
  @override
  State<_RecordDetailSheet> createState() => _RecordDetailSheetState();
}

class _RecordDetailSheetState extends State<_RecordDetailSheet> {
  String? _editing; // the attribute name currently in edit mode (text/number only)
  String? _error; // inline validation failure for the editing row (shown IN the sheet, not behind it)
  bool _committing = false; // in-flight guard so a double-tap doesn't write twice (two journal entries)
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _attrs => ((widget.typeDef['attributes'] as List?) ?? const [])
      .whereType<Map>()
      .map((a) => a.cast<String, dynamic>())
      .toList();

  Future<void> _commit(String field, Object? value) async {
    if (_committing) return;
    _committing = true;
    try {
      final r = await widget.onEdit(widget.recordId, field, value);
      if (!mounted) return;
      // Surface the outcome INSIDE the sheet: a SnackBar would render behind the modal sheet and be
      // invisible (no silent failure — the failure keeps edit mode open with the reason shown).
      setState(() {
        if (r.ok) {
          _editing = null;
          _error = null;
        } else {
          _error = r.message;
        }
      });
    } finally {
      _committing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.session.store[widget.recordId];
    final cs = Theme.of(context).colorScheme;
    if (rec == null) {
      // deleted out from under the sheet (e.g. via undo of a create) — close it cleanly.
      return const SafeArea(child: Padding(padding: EdgeInsets.all(24), child: Text('This record is gone.')));
    }
    final schemaNames = _attrs.map((a) => a['name'] as String).toSet();
    final extraKeys = rec.keys.where((k) => !_plumbingFields.contains(k) && !schemaNames.contains(k)).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((widget.typeDef['displayName'] as String?) ?? widget.typeId,
                  key: const Key('record-detail'), style: Theme.of(context).textTheme.titleLarge),
              const Divider(),
              for (final a in _attrs) _attrRow(context, rec, a),
              if (extraKeys.isNotEmpty) ...[
                const Divider(),
                for (final k in extraKeys)
                  if (rec[k] != null)
                    ListTile(dense: true, title: Text(k), trailing: Text(renderValue(rec[k], null))),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('record-delete'),
                  icon: Icon(Icons.delete_outline, color: cs.error, size: 20),
                  label: Text('Delete', style: TextStyle(color: cs.error)),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await widget.onDelete(widget.recordId);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attrRow(BuildContext context, Map<String, dynamic> rec, Map<String, dynamic> attr) {
    final name = attr['name'] as String;
    final vt = attr['valueType'] as String? ?? 'text';
    final value = rec[name];

    // json — a structured value; NOT hand-editable in a text field (Spec 07 §5 "voice/skill only").
    // Show it read-only rather than let a raw TextField stringify a Map into garbage.
    if (vt == 'json') {
      return ListTile(dense: true, title: Text(name), trailing: Text(renderValue(value, vt)));
    }

    // boolean — the row IS the toggle; each tap commits a flip.
    if (vt == 'boolean') {
      return SwitchListTile(
        dense: true,
        title: Text(name),
        value: value == true,
        onChanged: (v) => _commit(name, v),
      );
    }

    // date / datetime — tap opens a picker; picker output is the only source, so no bad input.
    if (vt == 'date' || vt == 'datetime') {
      return ListTile(
        dense: true,
        title: Text(name),
        trailing: Text(renderValue(value, vt)),
        onTap: () => _pickDate(name, vt, value),
      );
    }

    // text / entity / number / decimal / tag / list — inline tap-to-edit text field.
    if (_editing == name) {
      final isNum = vt == 'number' || vt == 'decimal';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                decoration: InputDecoration(labelText: name, isDense: true, errorText: _error),
                onSubmitted: (t) => _commit(name, t),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Save',
              onPressed: () => _commit(name, _ctrl.text),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: () => setState(() {
                _editing = null;
                _error = null;
              }),
            ),
          ],
        ),
      );
    }
    return ListTile(
      dense: true,
      title: Text(name),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Text(renderValue(value, vt),
            textAlign: TextAlign.end, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Theme.of(context).colorScheme.primary)),
      ),
      onTap: () {
        _ctrl.text = value is List ? value.join(', ') : (value?.toString() ?? '');
        setState(() {
          _editing = name;
          _error = null;
        });
      },
    );
  }

  Future<void> _pickDate(String name, String vt, Object? current) async {
    final now = DateTime.now();
    // Window wide enough for birthdays (past) and far-future reminders; clamp initialDate INTO it,
    // or showDatePicker asserts (initialDate must be within first/lastDate) and crashes.
    final lo = DateTime(now.year - 120);
    final hi = DateTime(now.year + 50);
    final parsed = DateTime.tryParse('$current') ?? now;
    final seed = parsed.isBefore(lo) ? lo : (parsed.isAfter(hi) ? hi : parsed);
    final d = await showDatePicker(
      context: context,
      initialDate: seed,
      firstDate: lo,
      lastDate: hi,
    );
    if (d == null || !mounted) return;
    if (vt == 'date') {
      await _commit(name, '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
      return;
    }
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(seed));
    if (!mounted) return;
    final dt = DateTime(d.year, d.month, d.day, t?.hour ?? seed.hour, t?.minute ?? seed.minute);
    await _commit(name, dt.toIso8601String());
  }
}

/// Turn a raw corpus template into a friendly line: literal words stay (they're the user's own
/// phrasing); `{name:type}` placeholders become a plain-language noun. Presentation only.
String humanizeTemplate(String template) {
  return template.replaceAllMapped(RegExp(r'\{(\w+):(\w+)\}'), (m) {
    switch (m.group(2)) {
      case 'entity':
      case 'contact': // the mainline case: learn() abstracts a known person to {name:contact}
        return 'someone';
      case 'date':
      case 'datetime':
      case 'dayword': // corpus date slot-types (tracker bundles)
      case 'pastday':
      case 'futuredate':
        return 'a date';
      case 'number':
      case 'quantity':
      case 'decimal':
        return 'an amount';
      default:
        return 'something';
    }
  });
}

/// The "Learned phrases" showcase — ways of saying things Plena picked up from how Luis talks.
/// Each can be forgotten (symmetrical with the voice-side forget-on-correction); forgetting is
/// low-stakes (the phrasing just falls back to cloud routing) so it uses an UNDO snackbar.
class _LearnedPhrasesCard extends StatefulWidget {
  final Session session;
  const _LearnedPhrasesCard({required this.session});
  @override
  State<_LearnedPhrasesCard> createState() => _LearnedPhrasesCardState();
}

class _LearnedPhrasesCardState extends State<_LearnedPhrasesCard> {
  void _forget(LearnedFlow f) {
    final raw = widget.session.forgetLearnedFlow(f.template);
    setState(() {});
    if (raw != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text("Forgotten — Plena won't recognize that phrasing."),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            widget.session.restoreLearnedFlow(raw);
            if (mounted) setState(() {});
          },
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final flows = widget.session.learnedFlows;
    final tt = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Learned phrases', key: const Key('learned-phrases-card'), style: tt.titleMedium),
            Text('Ways of saying things Plena has picked up from you.', style: tt.bodySmall),
            const Divider(),
            if (flows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Nothing yet — Plena learns your phrasings as you talk (and when you correct her).'),
              )
            else
              for (final f in flows)
                ListTile(
                  dense: true,
                  title: Text('“${humanizeTemplate(f.template)}”'),
                  subtitle: Text('→ ${f.targetLabel}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Forget this phrasing',
                    onPressed: () => _forget(f),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
