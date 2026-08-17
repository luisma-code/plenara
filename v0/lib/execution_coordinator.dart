/// Durable, serial mutation coordinator. The journal is device-local execution
/// state, never part of the synced record folder.
library;

import 'dart:convert';
import 'dart:io';

import 'storage_repository.dart';
import 'store.dart' as fs;

enum ExecutionPhase { prepared, applying, completed, reversing, reversed }

enum ExecutionResultState {
  persisted,
  appliedInMemory,
  recovered,
  reversed,
  conflict,
  failedBeforeWrite,
}

class ExecutionOperation {
  final String kind;
  final String id;
  final Map<String, dynamic>? record;

  ExecutionOperation.write(Map<String, dynamic> value)
      : kind = 'write',
        id = value['id'] as String,
        record = value;

  ExecutionOperation.delete(this.id)
      : kind = 'delete',
        record = null;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'id': id,
        if (record != null) 'record': record,
      };

  factory ExecutionOperation.fromJson(Map<String, dynamic> json) =>
      json['kind'] == 'write'
          ? ExecutionOperation.write(
              Map<String, dynamic>.from(json['record'] as Map),
            )
          : ExecutionOperation.delete(json['id'] as String);
}

class DurableExecutionRecord {
  final int id;
  final String origin;
  final String? description;
  final bool visible;
  final Map<String, dynamic> frozenInputs;
  final List<ExecutionOperation> operations;
  final Map<String, Map<String, dynamic>?> before;
  ExecutionPhase phase;
  int nextOperation;
  final String createdAt;

  DurableExecutionRecord({
    required this.id,
    required this.origin,
    required this.description,
    required this.visible,
    required this.frozenInputs,
    required this.operations,
    required this.before,
    required this.phase,
    required this.nextOperation,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'origin': origin,
        'description': description,
        'visible': visible,
        'frozenInputs': frozenInputs,
        'operations':
            operations.map((operation) => operation.toJson()).toList(),
        'before': before,
        'phase': phase.name,
        'nextOperation': nextOperation,
        'createdAt': createdAt,
      };

  factory DurableExecutionRecord.fromJson(Map<String, dynamic> json) {
    final before = <String, Map<String, dynamic>?>{};
    (json['before'] as Map).forEach((key, value) {
      before[key as String] =
          value == null ? null : Map<String, dynamic>.from(value as Map);
    });
    return DurableExecutionRecord(
      id: json['id'] as int,
      origin: json['origin'] as String,
      description: json['description'] as String?,
      visible: json['visible'] as bool? ?? true,
      frozenInputs: Map<String, dynamic>.from(json['frozenInputs'] as Map),
      operations: (json['operations'] as List)
          .map((value) => ExecutionOperation.fromJson(
              Map<String, dynamic>.from(value as Map)))
          .toList(),
      before: before,
      phase: ExecutionPhase.values.byName(json['phase'] as String),
      nextOperation: json['nextOperation'] as int,
      createdAt: json['createdAt'] as String,
    );
  }
}

abstract interface class ExecutionJournal {
  List<DurableExecutionRecord> get entries;
  List<String> get issues;
  int allocateId();
  void put(DurableExecutionRecord record);
  void prune(int maxCompleted);
}

class FileExecutionJournal implements ExecutionJournal {
  final File file;
  final List<String> _issues = [];
  final List<DurableExecutionRecord> _entries = [];
  // Keep durable ids in a separate range from the legacy in-session journal's
  // small positive counters while mutation origins are migrated incrementally.
  int _nextId = 1000000;

  FileExecutionJournal(String deviceDir)
      : file =
            File('$deviceDir${Platform.pathSeparator}execution-journal.json') {
    _load();
  }

  @override
  List<DurableExecutionRecord> get entries => List.unmodifiable(_entries);

  @override
  List<String> get issues => List.unmodifiable(_issues);

  void _load() {
    if (!file.existsSync()) return;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      _nextId = json['nextId'] as int? ?? 1000000;
      _entries
        ..clear()
        ..addAll(
          ((json['entries'] as List?) ?? const []).map(
            (value) => DurableExecutionRecord.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          ),
        );
    } catch (error) {
      _issues.add('execution_journal_corrupt: $error');
      try {
        final preserved = File('${file.path}.corrupt');
        if (!preserved.existsSync()) {
          preserved.writeAsBytesSync(file.readAsBytesSync(), flush: true);
        }
      } catch (_) {
        // The issue remains visible even if the damaged bytes cannot be copied.
      }
    }
  }

  @override
  int allocateId() => _nextId++;

  @override
  void put(DurableExecutionRecord record) {
    final index = _entries.indexWhere((entry) => entry.id == record.id);
    if (index < 0) {
      _entries.add(record);
    } else {
      _entries[index] = record;
    }
    _flush();
  }

  @override
  void prune(int maxCompleted) {
    final terminal = _entries
        .where(
          (entry) =>
              entry.phase == ExecutionPhase.completed ||
              entry.phase == ExecutionPhase.reversed,
        )
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    while (terminal.length > maxCompleted) {
      final oldest = terminal.removeAt(0);
      _entries.removeWhere((entry) => entry.id == oldest.id);
    }
    _flush();
  }

  void _flush() {
    file.parent.createSync(recursive: true);
    fs.writeJsonAtomic(file, {
      'nextId': _nextId,
      'entries': _entries.map((entry) => entry.toJson()).toList(),
    });
  }
}

class MemoryExecutionJournal implements ExecutionJournal {
  final List<DurableExecutionRecord> _entries = [];
  int _nextId = 1000000;

  @override
  List<DurableExecutionRecord> get entries => List.unmodifiable(_entries);

  @override
  List<String> get issues => const [];

  @override
  int allocateId() => _nextId++;

  @override
  void put(DurableExecutionRecord record) {
    final index = _entries.indexWhere((entry) => entry.id == record.id);
    if (index < 0) {
      _entries.add(record);
    } else {
      _entries[index] = record;
    }
  }

  @override
  void prune(int maxCompleted) {
    final terminal = _entries
        .where(
          (entry) =>
              entry.phase == ExecutionPhase.completed ||
              entry.phase == ExecutionPhase.reversed,
        )
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    while (terminal.length > maxCompleted) {
      final oldest = terminal.removeAt(0);
      _entries.removeWhere((entry) => entry.id == oldest.id);
    }
  }
}

class ExecutionResult {
  final ExecutionResultState state;
  final DurableExecutionRecord? record;
  final Object? error;

  const ExecutionResult(this.state, {this.record, this.error});
}

/// Test-only process-death marker: it deliberately escapes the coordinator so
/// the next instance must recover from the last durable checkpoint.
class SimulatedProcessDeath implements Exception {
  final int operationIndex;
  const SimulatedProcessDeath(this.operationIndex);
}

class ExecutionCoordinator {
  final StorageRepository repository;
  final Map<String, Map<String, dynamic>> store;
  final ExecutionJournal journal;
  final Map<String, dynamic> Function(
    Map<String, dynamic> record,
    Map<String, Map<String, dynamic>> projectedStore,
  )? recordValidator;
  final void Function(DurableExecutionRecord record, int operationIndex)?
      afterPersist;
  static const maxCompleted = 25;

  ExecutionCoordinator({
    required this.repository,
    required this.store,
    required this.journal,
    this.recordValidator,
    this.afterPersist,
  });

  List<DurableExecutionRecord> get completed => journal.entries
      .where((entry) => entry.phase == ExecutionPhase.completed)
      .toList()
    ..sort((a, b) => a.id.compareTo(b.id));

  ExecutionResult execute({
    required List<Map<String, dynamic>> writes,
    required List<String> deletes,
    required String origin,
    String? description,
    bool visible = true,
    Map<String, dynamic> frozenInputs = const {},
  }) {
    final validatedWrites = <Map<String, dynamic>>[];
    try {
      final projected = <String, Map<String, dynamic>>{
        for (final entry in store.entries) entry.key: _copyMap(entry.value),
        for (final write in writes) write['id'] as String: _copyMap(write),
      };
      for (final write in writes) {
        validatedWrites.add(recordValidator == null
            ? _copyMap(write)
            : recordValidator!(_copyMap(write), projected));
      }
    } catch (error) {
      return ExecutionResult(
        ExecutionResultState.failedBeforeWrite,
        error: error,
      );
    }
    final operations = <ExecutionOperation>[
      for (final write in validatedWrites) ExecutionOperation.write(write),
      for (final id in deletes) ExecutionOperation.delete(id),
    ];
    final before = <String, Map<String, dynamic>?>{};
    for (final operation in operations) {
      before.putIfAbsent(
        operation.id,
        () =>
            store[operation.id] == null ? null : _copyMap(store[operation.id]!),
      );
    }
    final record = DurableExecutionRecord(
      id: journal.allocateId(),
      origin: origin,
      description: description,
      visible: visible,
      frozenInputs: _copyMap(frozenInputs),
      operations: operations,
      before: before,
      phase: ExecutionPhase.prepared,
      nextOperation: 0,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    try {
      journal.put(record); // durable intent before the first user-data write
    } catch (error) {
      return ExecutionResult(ExecutionResultState.failedBeforeWrite,
          error: error);
    }
    return _continue(record, recovered: false);
  }

  List<ExecutionResult> recover() {
    final outcomes = <ExecutionResult>[];
    for (final record in journal.entries.toList()) {
      if (record.phase == ExecutionPhase.prepared ||
          record.phase == ExecutionPhase.applying) {
        outcomes.add(_continue(record, recovered: true));
      } else if (record.phase == ExecutionPhase.reversing) {
        outcomes.add(_continueUndo(record, recovered: true));
      }
    }
    return outcomes;
  }

  ExecutionResult undo(int id) {
    final record = journal.entries.where((entry) => entry.id == id).firstOrNull;
    if (record == null ||
        record.phase == ExecutionPhase.reversing ||
        record.phase == ExecutionPhase.reversed) {
      return const ExecutionResult(ExecutionResultState.failedBeforeWrite);
    }
    if (record.phase == ExecutionPhase.completed &&
        !_afterImagesStillMatch(record)) {
      return ExecutionResult(
        ExecutionResultState.conflict,
        record: record,
      );
    }
    record
      ..phase = ExecutionPhase.reversing
      ..nextOperation = 0;
    try {
      journal.put(record);
    } catch (error) {
      return ExecutionResult(
        ExecutionResultState.failedBeforeWrite,
        record: record,
        error: error,
      );
    }
    return _continueUndo(record, recovered: false);
  }

  ExecutionResult _continue(
    DurableExecutionRecord record, {
    required bool recovered,
  }) {
    try {
      record.phase = ExecutionPhase.applying;
      journal.put(record);
      while (record.nextOperation < record.operations.length) {
        final index = record.nextOperation;
        _apply(record.operations[index]);
        afterPersist?.call(record, index);
        record.nextOperation++;
        journal.put(record); // checkpoint only after the atomic operation
      }
      record.phase = ExecutionPhase.completed;
      journal.put(record);
      journal.prune(maxCompleted);
      return ExecutionResult(
        recovered
            ? ExecutionResultState.recovered
            : ExecutionResultState.persisted,
        record: record,
      );
    } on SimulatedProcessDeath {
      rethrow;
    } catch (error) {
      return ExecutionResult(
        ExecutionResultState.appliedInMemory,
        record: record,
        error: error,
      );
    }
  }

  ExecutionResult _continueUndo(
    DurableExecutionRecord record, {
    required bool recovered,
  }) {
    final inverse = record.before.entries.toList().reversed.toList();
    try {
      record.phase = ExecutionPhase.reversing;
      journal.put(record);
      while (record.nextOperation < inverse.length) {
        final index = record.nextOperation;
        final entry = inverse[index];
        if (entry.value == null) {
          store.remove(entry.key);
          repository.remove(entry.key);
        } else {
          final prior = _copyMap(entry.value!);
          store[entry.key] = prior;
          repository.persist(prior);
        }
        afterPersist?.call(record, index);
        record.nextOperation++;
        journal.put(record);
      }
      record.phase = ExecutionPhase.reversed;
      journal.put(record);
      journal.prune(maxCompleted);
      return ExecutionResult(
        recovered
            ? ExecutionResultState.recovered
            : ExecutionResultState.reversed,
        record: record,
      );
    } on SimulatedProcessDeath {
      rethrow;
    } catch (error) {
      return ExecutionResult(
        ExecutionResultState.appliedInMemory,
        record: record,
        error: error,
      );
    }
  }

  void _apply(ExecutionOperation operation) {
    if (operation.kind == 'write') {
      final record = _copyMap(operation.record!);
      store[operation.id] = record;
      repository.persist(record);
    } else {
      store.remove(operation.id);
      repository.remove(operation.id);
    }
  }

  bool _afterImagesStillMatch(DurableExecutionRecord record) {
    final expected = <String, Map<String, dynamic>?>{};
    for (final operation in record.operations) {
      expected[operation.id] =
          operation.kind == 'write' ? _copyMap(operation.record!) : null;
    }
    for (final entry in expected.entries) {
      final actual = store[entry.key];
      if (!_deepEqual(actual, entry.value)) return false;
    }
    return true;
  }

  static bool _deepEqual(Object? left, Object? right) {
    if (identical(left, right)) return true;
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final key in left.keys) {
        if (!right.containsKey(key) || !_deepEqual(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_deepEqual(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }

  static Map<String, dynamic> _copyMap(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
}
