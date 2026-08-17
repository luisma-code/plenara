/// Structured weekly review artifact. The deterministic recommendation layer
/// explains keep/defer/drop choices and persists user edits; an optional cloud
/// reflection may accompany it but never owns or applies the decisions.
library;

import 'dart:convert';
import 'dart:io';

import 'plan_proposal.dart' show taskPlanFingerprint;
import 'store.dart' show writeJsonAtomic;

enum ReviewDecision { keep, defer, drop }

enum WeeklyReviewState { draft, applied, dismissed, stale }

class WeeklyReviewItem {
  final String recordId;
  final String recordType;
  final String title;
  final String baseFingerprint;
  final ReviewDecision decision;
  final String evidence;

  const WeeklyReviewItem({
    required this.recordId,
    required this.recordType,
    required this.title,
    required this.baseFingerprint,
    required this.decision,
    required this.evidence,
  });

  WeeklyReviewItem copyWith({ReviewDecision? decision}) => WeeklyReviewItem(
        recordId: recordId,
        recordType: recordType,
        title: title,
        baseFingerprint: baseFingerprint,
        decision: decision ?? this.decision,
        evidence: evidence,
      );

  Map<String, dynamic> toJson() => {
        'recordId': recordId,
        'recordType': recordType,
        'title': title,
        'baseFingerprint': baseFingerprint,
        'decision': decision.name,
        'evidence': evidence,
      };

  static WeeklyReviewItem fromJson(Map<String, dynamic> raw) =>
      WeeklyReviewItem(
        recordId: raw['recordId'] as String,
        recordType: raw['recordType'] as String,
        title: raw['title'] as String,
        baseFingerprint: raw['baseFingerprint'] as String,
        decision: ReviewDecision.values.byName(raw['decision'] as String),
        evidence: raw['evidence'] as String,
      );
}

class WeeklyReviewArtifact {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final WeeklyReviewState state;
  final List<WeeklyReviewItem> items;
  final String? message;

  const WeeklyReviewArtifact({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.state,
    required this.items,
    this.message,
  });

  WeeklyReviewArtifact copyWith({
    DateTime? updatedAt,
    WeeklyReviewState? state,
    List<WeeklyReviewItem>? items,
    String? message,
  }) =>
      WeeklyReviewArtifact(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        state: state ?? this.state,
        items: items ?? this.items,
        message: message ?? this.message,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'state': state.name,
        'items': items.map((item) => item.toJson()).toList(),
        if (message != null) 'message': message,
      };

  static WeeklyReviewArtifact fromJson(Map<String, dynamic> raw) =>
      WeeklyReviewArtifact(
        id: raw['id'] as String,
        createdAt: DateTime.parse(raw['createdAt'] as String),
        updatedAt: DateTime.parse(raw['updatedAt'] as String),
        state: WeeklyReviewState.values.byName(raw['state'] as String),
        items: (raw['items'] as List)
            .map((item) => WeeklyReviewItem.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList(growable: false),
        message: raw['message'] as String?,
      );
}

String reviewFingerprint(Map<String, dynamic> record) =>
    record['typeId'] == 'task'
        ? taskPlanFingerprint(record)
        : jsonEncode({
            'id': record['id'],
            'typeId': record['typeId'],
            'title': record['title'] ?? record['name'],
            'status': record['status'],
            'target': record['target'],
          });

WeeklyReviewArtifact buildWeeklyReviewArtifact(
  Map<String, Map<String, dynamic>> records,
  DateTime now,
) {
  final items = <WeeklyReviewItem>[];
  for (final record in records.values) {
    if (record['typeId'] == 'task' &&
        record['completed'] != true &&
        record['status'] != 'done') {
      final due = DateTime.tryParse('${record['dueAt'] ?? ''}');
      final created = DateTime.tryParse('${record['createdAt'] ?? ''}');
      final old = created != null && now.difference(created).inDays >= 30;
      final someday = record['status'] == 'someday';
      final overdue = due != null && due.isBefore(now);
      final decision = someday && old
          ? ReviewDecision.drop
          : overdue || record['priority'] == 'high'
              ? ReviewDecision.keep
              : ReviewDecision.defer;
      final evidence = switch (decision) {
        ReviewDecision.keep => overdue
            ? 'Deadline ${due.month}/${due.day} has passed.'
            : 'Marked high priority.',
        ReviewDecision.defer => record['scheduledStartAt'] == null
            ? 'Open and unscheduled; move it out of the active week unless it earns time.'
            : 'Not urgent enough to displace committed work.',
        ReviewDecision.drop =>
          'Still in Someday after ${now.difference(created!).inDays} days.',
      };
      items.add(WeeklyReviewItem(
        recordId: '${record['id']}',
        recordType: 'task',
        title: '${record['description'] ?? 'Untitled task'}',
        baseFingerprint: reviewFingerprint(record),
        decision: decision,
        evidence: evidence,
      ));
    } else if (record['typeId'] == 'goal' && record['status'] != 'done') {
      items.add(WeeklyReviewItem(
        recordId: '${record['id']}',
        recordType: 'goal',
        title: '${record['title'] ?? record['name'] ?? 'Untitled goal'}',
        baseFingerprint: reviewFingerprint(record),
        decision: ReviewDecision.keep,
        evidence: 'Open goal; keep it visible while choosing task commitments.',
      ));
    }
  }
  items.sort((left, right) {
    final type = left.recordType.compareTo(right.recordType);
    return type != 0 ? type : left.title.compareTo(right.title);
  });
  return WeeklyReviewArtifact(
    id: 'weekly-review-${now.microsecondsSinceEpoch}',
    createdAt: now,
    updatedAt: now,
    state: WeeklyReviewState.draft,
    items: List.unmodifiable(items),
  );
}

class WeeklyReviewStore {
  final String? path;
  final List<String> issues = [];
  WeeklyReviewArtifact? _active;

  WeeklyReviewStore({this.path}) {
    if (path == null) return;
    final file = File(path!);
    if (!file.existsSync()) return;
    try {
      _active = WeeklyReviewArtifact.fromJson(
        Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map),
      );
    } catch (error) {
      issues.add('Weekly review could not be read: $error');
    }
  }

  WeeklyReviewArtifact? get active => _active;

  void save(WeeklyReviewArtifact artifact) {
    _active = artifact;
    if (path == null) return;
    final file = File(path!);
    file.parent.createSync(recursive: true);
    writeJsonAtomic(file, artifact.toJson());
  }
}
