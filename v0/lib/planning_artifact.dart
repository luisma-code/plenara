/// Durable, explicitly resolved planning prompts that must not disappear as
/// transient conversation text. Morning orientation and relationship/event
/// preparation stay visible until accepted, dismissed, or superseded.
library;

import 'dart:convert';
import 'dart:io';

import 'store.dart' show writeJsonAtomic;

enum PlanningArtifactKind { morning, relationshipPrep, relationshipSuggestion }

enum PlanningArtifactState { draft, deferred, accepted, dismissed, superseded }

class PlanningArtifactItem {
  final String recordId;
  final String title;
  final String evidence;

  const PlanningArtifactItem({
    required this.recordId,
    required this.title,
    required this.evidence,
  });

  Map<String, dynamic> toJson() => {
        'recordId': recordId,
        'title': title,
        'evidence': evidence,
      };

  static PlanningArtifactItem fromJson(Map<String, dynamic> raw) =>
      PlanningArtifactItem(
        recordId: raw['recordId'] as String,
        title: raw['title'] as String,
        evidence: raw['evidence'] as String,
      );
}

class PlanningArtifact {
  final String id;
  final PlanningArtifactKind kind;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final PlanningArtifactState state;
  final DateTime? deferUntil;
  final List<PlanningArtifactItem> items;
  final String summary;

  const PlanningArtifact({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.state,
    this.deferUntil,
    required this.items,
    required this.summary,
  });

  PlanningArtifact copyWith({
    DateTime? updatedAt,
    PlanningArtifactState? state,
    DateTime? deferUntil,
    bool clearDeferUntil = false,
  }) =>
      PlanningArtifact(
        id: id,
        kind: kind,
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        state: state ?? this.state,
        deferUntil: clearDeferUntil ? null : deferUntil ?? this.deferUntil,
        items: items,
        summary: summary,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'state': state.name,
        if (deferUntil != null) 'deferUntil': deferUntil!.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
        'summary': summary,
      };

  static PlanningArtifact fromJson(Map<String, dynamic> raw) =>
      PlanningArtifact(
        id: raw['id'] as String,
        kind: PlanningArtifactKind.values.byName(raw['kind'] as String),
        title: raw['title'] as String,
        createdAt: DateTime.parse(raw['createdAt'] as String),
        updatedAt: DateTime.parse(raw['updatedAt'] as String),
        state: PlanningArtifactState.values.byName(raw['state'] as String),
        deferUntil: raw['deferUntil'] == null
            ? null
            : DateTime.parse(raw['deferUntil'] as String),
        items: (raw['items'] as List)
            .map((item) => PlanningArtifactItem.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList(growable: false),
        summary: raw['summary'] as String,
      );
}

PlanningArtifact buildMorningPlanningArtifact(
  Map<String, Map<String, dynamic>> records,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  bool todayValue(dynamic raw) {
    final value = DateTime.tryParse('${raw ?? ''}');
    return value != null &&
        value.year == today.year &&
        value.month == today.month &&
        value.day == today.day;
  }

  final candidates = <({int rank, DateTime at, PlanningArtifactItem item})>[];
  for (final record in records.values) {
    if (record['typeId'] == 'task' &&
        record['completed'] != true &&
        record['status'] != 'done') {
      final scheduled =
          DateTime.tryParse('${record['scheduledStartAt'] ?? ''}');
      final due = DateTime.tryParse('${record['dueAt'] ?? ''}');
      final relevant = todayValue(record['scheduledStartAt']) ||
          todayValue(record['dueAt']) ||
          record['priority'] == 'high';
      if (!relevant) continue;
      final evidence = todayValue(record['scheduledStartAt'])
          ? 'Scheduled today${scheduled == null ? '' : ' at ${scheduled.hour.toString().padLeft(2, '0')}:${scheduled.minute.toString().padLeft(2, '0')}'}.'
          : todayValue(record['dueAt'])
              ? 'Deadline is today.'
              : 'High-priority unscheduled work.';
      candidates.add((
        rank: todayValue(record['scheduledStartAt'])
            ? 0
            : todayValue(record['dueAt'])
                ? 1
                : 2,
        at: scheduled ?? due ?? today.add(const Duration(days: 1)),
        item: PlanningArtifactItem(
          recordId: '${record['id']}',
          title: '${record['description'] ?? 'Untitled task'}',
          evidence: evidence,
        ),
      ));
    } else if (record['typeId'] == 'reminder' &&
        record['done'] != true &&
        todayValue(record['remindAt'])) {
      final at = DateTime.parse('${record['remindAt']}');
      candidates.add((
        rank: 0,
        at: at,
        item: PlanningArtifactItem(
          recordId: '${record['id']}',
          title: '${record['text'] ?? 'Reminder'}',
          evidence: 'Reminder today at '
              '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}.',
        ),
      ));
    }
  }
  candidates.sort((left, right) {
    final rank = left.rank.compareTo(right.rank);
    return rank != 0 ? rank : left.at.compareTo(right.at);
  });
  final items = candidates.take(5).map((entry) => entry.item).toList();
  return PlanningArtifact(
    id: 'morning-${now.microsecondsSinceEpoch}',
    kind: PlanningArtifactKind.morning,
    title: 'Morning plan',
    createdAt: now,
    updatedAt: now,
    state: PlanningArtifactState.draft,
    items: List.unmodifiable(items),
    summary: items.isEmpty
        ? 'Nothing time-sensitive is asking for attention this morning.'
        : '${items.length} commitments deserve attention today.',
  );
}

PlanningArtifact? buildRelationshipPrepArtifact(
  String personName,
  Map<String, Map<String, dynamic>> records,
  DateTime now,
) {
  final wanted = personName.toLowerCase().trim();
  final contacts =
      records.values.where((record) => record['typeId'] == 'contact');
  Map<String, dynamic>? contact;
  for (final candidate in contacts) {
    final name = '${candidate['displayName'] ?? ''}'.toLowerCase();
    if (name == wanted || name.contains(wanted)) {
      contact = candidate;
      break;
    }
  }
  if (contact == null) return null;
  final contactId = '${contact['id']}';
  final items = <PlanningArtifactItem>[];
  for (final fact in records.values.where(
    (record) =>
        record['typeId'] == 'contact_fact' &&
        '${record['subject']}' == contactId,
  )) {
    items.add(PlanningArtifactItem(
      recordId: '${fact['id']}',
      title: '${fact['fact']}',
      evidence: 'A fact you asked Plenara to remember.',
    ));
  }
  final interactions = records.values
      .where((record) =>
          record['typeId'] == 'interaction' &&
          '${record['subject']}' == contactId)
      .toList()
    ..sort((a, b) => '${b['at']}'.compareTo('${a['at']}'));
  if (interactions.isNotEmpty) {
    final latest = interactions.first;
    items.add(PlanningArtifactItem(
      recordId: '${latest['id']}',
      title: '${latest['note'] ?? latest['kind'] ?? 'Last interaction'}',
      evidence: 'Most recent logged interaction: ${latest['at']}.',
    ));
  }
  if (contact['birthday'] != null) {
    items.add(PlanningArtifactItem(
      recordId: contactId,
      title: 'Birthday ${contact['birthday']}',
      evidence: 'Saved on ${contact['displayName']}’s profile.',
    ));
  }
  return PlanningArtifact(
    id: 'relationship-${now.microsecondsSinceEpoch}',
    kind: PlanningArtifactKind.relationshipPrep,
    title: 'Prepare for ${contact['displayName']}',
    createdAt: now,
    updatedAt: now,
    state: PlanningArtifactState.draft,
    items: List.unmodifiable(items.take(6)),
    summary: items.isEmpty
        ? 'No saved context yet; add a fact or interaction to make this useful.'
        : '${items.length.clamp(0, 6)} pieces of saved context are ready.',
  );
}

class PlanningArtifactStore {
  final String? path;
  final List<String> issues = [];
  final List<PlanningArtifact> _artifacts = [];

  PlanningArtifactStore({this.path}) {
    if (path == null) return;
    final file = File(path!);
    if (!file.existsSync()) return;
    try {
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      _artifacts.addAll((raw['artifacts'] as List).map(
        (item) => PlanningArtifact.fromJson(
          Map<String, dynamic>.from(item as Map),
        ),
      ));
    } catch (error) {
      issues.add('Planning artifacts could not be read: $error');
    }
  }

  List<PlanningArtifact> activeAt(DateTime now) => _artifacts
      .where(
        (artifact) =>
            artifact.state == PlanningArtifactState.draft ||
            (artifact.state == PlanningArtifactState.deferred &&
                artifact.deferUntil != null &&
                !artifact.deferUntil!.isAfter(now)),
      )
      .toList(growable: false);

  /// Draft-only compatibility view. Time-aware product surfaces use
  /// [activeAt] so a deferred artifact can return when its date arrives.
  List<PlanningArtifact> get active => _artifacts
      .where((artifact) => artifact.state == PlanningArtifactState.draft)
      .toList(growable: false);

  List<PlanningArtifact> get history => List.unmodifiable(_artifacts);

  void create(PlanningArtifact artifact) {
    if (_artifacts.any((existing) => existing.id == artifact.id)) return;
    for (var index = 0; index < _artifacts.length; index++) {
      final current = _artifacts[index];
      if (current.kind == artifact.kind &&
          (current.state == PlanningArtifactState.draft ||
              current.state == PlanningArtifactState.deferred)) {
        _artifacts[index] = current.copyWith(
          state: PlanningArtifactState.superseded,
          updatedAt: artifact.createdAt,
        );
      }
    }
    _artifacts.add(artifact);
    _persist();
  }

  PlanningArtifact? resolve(
    String id,
    PlanningArtifactState state,
    DateTime now, {
    DateTime? deferUntil,
  }) {
    if (state != PlanningArtifactState.accepted &&
        state != PlanningArtifactState.dismissed &&
        state != PlanningArtifactState.deferred) {
      throw ArgumentError.value(state, 'state', 'must resolve the artifact');
    }
    if (state == PlanningArtifactState.deferred &&
        (deferUntil == null || !deferUntil.isAfter(now))) {
      throw ArgumentError.value(
        deferUntil,
        'deferUntil',
        'must be after now',
      );
    }
    final index = _artifacts.indexWhere(
      (artifact) =>
          artifact.id == id &&
          (artifact.state == PlanningArtifactState.draft ||
              artifact.state == PlanningArtifactState.deferred),
    );
    if (index < 0) return null;
    _artifacts[index] = _artifacts[index].copyWith(
      state: state,
      updatedAt: now,
      deferUntil: deferUntil,
      clearDeferUntil: state != PlanningArtifactState.deferred,
    );
    _persist();
    return _artifacts[index];
  }

  void _persist() {
    if (path == null) return;
    final file = File(path!);
    file.parent.createSync(recursive: true);
    writeJsonAtomic(file, {
      'version': 2,
      'artifacts': _artifacts.map((artifact) => artifact.toJson()).toList(),
    });
  }
}
