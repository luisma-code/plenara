/// Durable, device-local history of what the user said and what Plena replied.
/// This is a product surface, distinct from diagnostic telemetry.
library;

import 'dart:convert';
import 'dart:io';

import 'store.dart' as fs;

class ConversationEntry {
  final int id;
  final String utterance;
  final String reply;
  final String source;
  final String outcome;
  final DateTime at;
  final int? executionId;
  final List<String> affectedRecordIds;
  final String? proposalState;
  final String? failureState;

  const ConversationEntry({
    required this.id,
    required this.utterance,
    required this.reply,
    required this.source,
    required this.outcome,
    required this.at,
    this.executionId,
    this.affectedRecordIds = const [],
    this.proposalState,
    this.failureState,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'utterance': utterance,
        'reply': reply,
        'source': source,
        'outcome': outcome,
        'at': at.toIso8601String(),
        if (executionId != null) 'executionId': executionId,
        if (affectedRecordIds.isNotEmpty)
          'affectedRecordIds': affectedRecordIds,
        if (proposalState != null) 'proposalState': proposalState,
        if (failureState != null) 'failureState': failureState,
      };

  factory ConversationEntry.fromJson(Map<String, dynamic> json) =>
      ConversationEntry(
        id: json['id'] as int,
        utterance: json['utterance'] as String,
        reply: json['reply'] as String,
        source: json['source'] as String,
        outcome: json['outcome'] as String? ?? json['source'] as String,
        at: DateTime.parse(json['at'] as String),
        executionId: json['executionId'] as int?,
        affectedRecordIds: ((json['affectedRecordIds'] as List?) ?? const [])
            .map((value) => '$value')
            .toList(),
        proposalState: json['proposalState'] as String?,
        failureState: json['failureState'] as String?,
      );
}

abstract interface class ConversationLedger {
  List<ConversationEntry> get entries;
  List<String> get issues;
  void append({
    required String utterance,
    required String reply,
    required String source,
    String? outcome,
    required DateTime at,
    int? executionId,
    List<String> affectedRecordIds = const [],
    String? proposalState,
    String? failureState,
  });
}

class FileConversationLedger implements ConversationLedger {
  static const maxEntries = 250;
  final File file;
  final List<ConversationEntry> _entries = [];
  final List<String> _issues = [];
  int _nextId = 1;

  FileConversationLedger(String deviceDir)
      : file = File(
            '$deviceDir${Platform.pathSeparator}conversation-ledger.json') {
    _load();
  }

  @override
  List<ConversationEntry> get entries => List.unmodifiable(_entries);

  @override
  List<String> get issues => List.unmodifiable(_issues);

  void _load() {
    if (!file.existsSync()) return;
    try {
      final value = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      _nextId = value['nextId'] as int? ?? 1;
      _entries.addAll(((value['entries'] as List?) ?? const []).map((raw) =>
          ConversationEntry.fromJson(Map<String, dynamic>.from(raw as Map))));
    } catch (error) {
      _issues.add('conversation_ledger_corrupt: $error');
      try {
        final preserved = File('${file.path}.corrupt');
        if (!preserved.existsSync()) {
          preserved.writeAsBytesSync(file.readAsBytesSync(), flush: true);
        }
      } catch (_) {
        // The repair issue remains visible if preserving bytes also fails.
      }
    }
  }

  @override
  void append({
    required String utterance,
    required String reply,
    required String source,
    String? outcome,
    required DateTime at,
    int? executionId,
    List<String> affectedRecordIds = const [],
    String? proposalState,
    String? failureState,
  }) {
    _entries.add(ConversationEntry(
      id: _nextId++,
      utterance: utterance,
      reply: reply,
      source: source,
      outcome: outcome ?? source,
      at: at,
      executionId: executionId,
      affectedRecordIds: List.unmodifiable(affectedRecordIds),
      proposalState: proposalState,
      failureState: failureState,
    ));
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    try {
      file.parent.createSync(recursive: true);
      fs.writeJsonAtomic(file, {
        'nextId': _nextId,
        'entries': _entries.map((entry) => entry.toJson()).toList(),
      });
    } catch (error) {
      _issues.add('conversation_ledger_write_failed: ${error.runtimeType}');
    }
  }
}

class MemoryConversationLedger implements ConversationLedger {
  final List<ConversationEntry> _entries = [];

  @override
  List<ConversationEntry> get entries => List.unmodifiable(_entries);

  @override
  List<String> get issues => const [];

  @override
  void append({
    required String utterance,
    required String reply,
    required String source,
    String? outcome,
    required DateTime at,
    int? executionId,
    List<String> affectedRecordIds = const [],
    String? proposalState,
    String? failureState,
  }) {
    _entries.add(ConversationEntry(
      id: _entries.length + 1,
      utterance: utterance,
      reply: reply,
      source: source,
      outcome: outcome ?? source,
      at: at,
      executionId: executionId,
      affectedRecordIds: List.unmodifiable(affectedRecordIds),
      proposalState: proposalState,
      failureState: failureState,
    ));
  }
}
