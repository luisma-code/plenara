/// Durable detached work coordinator. Long cloud work enters through [start],
/// runs serially outside the interactive turn, and reaches the UI through one
/// exactly-once delivery ledger. Relaunch never guesses that an in-flight HTTP
/// request completed: queued/running records become interrupted and require an
/// explicit retry, preventing duplicate spend.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'store.dart' show writeJsonAtomic;

enum OperationState {
  queued,
  running,
  succeeded,
  failed,
  cancelled,
  interrupted,
}

class OperationRecord {
  final String id;
  final String kind;
  final String title;
  final Map<String, dynamic> input;
  final OperationState state;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double progress;
  final String? result;
  final String? error;
  final DateTime? deliveredAt;

  const OperationRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.input,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    required this.progress,
    this.result,
    this.error,
    this.deliveredAt,
  });

  bool get terminal => const {
        OperationState.succeeded,
        OperationState.failed,
        OperationState.cancelled,
        OperationState.interrupted,
      }.contains(state);

  OperationRecord copyWith({
    OperationState? state,
    DateTime? updatedAt,
    double? progress,
    String? result,
    String? error,
    DateTime? deliveredAt,
  }) =>
      OperationRecord(
        id: id,
        kind: kind,
        title: title,
        input: input,
        state: state ?? this.state,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        progress: progress ?? this.progress,
        result: result ?? this.result,
        error: error ?? this.error,
        deliveredAt: deliveredAt ?? this.deliveredAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'input': input,
        'state': state.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'progress': progress,
        if (result != null) 'result': result,
        if (error != null) 'error': error,
        if (deliveredAt != null) 'deliveredAt': deliveredAt!.toIso8601String(),
      };

  static OperationRecord fromJson(Map<String, dynamic> raw) => OperationRecord(
        id: raw['id'] as String,
        kind: raw['kind'] as String,
        title: raw['title'] as String,
        input: Map<String, dynamic>.from(raw['input'] as Map? ?? const {}),
        state: OperationState.values.byName(raw['state'] as String),
        createdAt: DateTime.parse(raw['createdAt'] as String),
        updatedAt: DateTime.parse(raw['updatedAt'] as String),
        progress: (raw['progress'] as num).toDouble(),
        result: raw['result'] as String?,
        error: raw['error'] as String?,
        deliveredAt: raw['deliveredAt'] == null
            ? null
            : DateTime.parse(raw['deliveredAt'] as String),
      );
}

class OperationCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
}

typedef DetachedWork = Future<String> Function(OperationCancellation cancel);

class OperationCenter {
  final String? path;
  final DateTime Function() clock;
  final List<OperationRecord> _records = [];
  final Map<String, OperationCancellation> _cancellations = {};
  final Map<String, Completer<OperationRecord>> _waiters = {};
  final List<String> issues = [];
  final StreamController<OperationRecord> _changes =
      StreamController<OperationRecord>.broadcast(sync: true);
  Future<void> _tail = Future.value();
  int _nextId = 1;

  OperationCenter({this.path, DateTime Function()? clock})
      : clock = clock ?? DateTime.now {
    _load();
  }

  List<OperationRecord> get records => List.unmodifiable(_records.reversed);
  Stream<OperationRecord> get changes => _changes.stream;
  Future<void> get whenIdle => _tail;

  void _load() {
    if (path == null) return;
    final file = File(path!);
    if (!file.existsSync()) return;
    try {
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final loaded = (raw['operations'] as List)
          .map((entry) => OperationRecord.fromJson(
                Map<String, dynamic>.from(entry as Map),
              ))
          .toList();
      final now = clock();
      _records.addAll(loaded.map((record) {
        final numeric = int.tryParse(record.id.split('-').last);
        if (numeric != null && numeric >= _nextId) _nextId = numeric + 1;
        if (record.state == OperationState.queued ||
            record.state == OperationState.running) {
          return record.copyWith(
            state: OperationState.interrupted,
            updatedAt: now,
            error: 'Interrupted by app restart; retry explicitly.',
          );
        }
        return record;
      }));
      _persist();
    } catch (error) {
      issues.add('Operation history could not be read: $error');
    }
  }

  OperationRecord start({
    required String kind,
    required String title,
    Map<String, dynamic> input = const {},
    required DetachedWork run,
  }) {
    final now = clock();
    final record = OperationRecord(
      id: 'operation-${now.microsecondsSinceEpoch}-${_nextId++}',
      kind: kind,
      title: title,
      input: Map.unmodifiable(Map<String, dynamic>.from(input)),
      state: OperationState.queued,
      createdAt: now,
      updatedAt: now,
      progress: 0,
    );
    _records.add(record);
    final cancellation = OperationCancellation();
    _cancellations[record.id] = cancellation;
    _waiters[record.id] = Completer<OperationRecord>();
    _persistOrFail(record.id);
    _changes.add(_byId(record.id)!);
    if (_byId(record.id)!.terminal) {
      _completeWaiter(record.id);
      return _byId(record.id)!;
    }
    _tail = _tail.then((_) => _run(record.id, cancellation, run));
    return _byId(record.id)!;
  }

  Future<void> _run(
    String id,
    OperationCancellation cancellation,
    DetachedWork work,
  ) async {
    final queued = _byId(id);
    if (queued == null || queued.state == OperationState.cancelled) {
      _completeWaiter(id);
      return;
    }
    _replace(queued.copyWith(
      state: OperationState.running,
      updatedAt: clock(),
      progress: 0.05,
    ));
    try {
      final result = await work(cancellation);
      final current = _byId(id)!;
      _replace(current.copyWith(
        state: cancellation.isCancelled
            ? OperationState.cancelled
            : OperationState.succeeded,
        updatedAt: clock(),
        progress: cancellation.isCancelled ? current.progress : 1,
        result: cancellation.isCancelled ? null : result,
      ));
    } catch (error) {
      final current = _byId(id)!;
      _replace(current.copyWith(
        state: cancellation.isCancelled
            ? OperationState.cancelled
            : OperationState.failed,
        updatedAt: clock(),
        error: cancellation.isCancelled ? null : '$error',
      ));
    } finally {
      _cancellations.remove(id);
      _completeWaiter(id);
    }
  }

  bool cancel(String id) {
    final record = _byId(id);
    if (record == null || record.terminal) return false;
    _cancellations[id]?._cancelled = true;
    _replace(record.copyWith(
      state: OperationState.cancelled,
      updatedAt: clock(),
      error: record.state == OperationState.running
          ? 'Cancelled locally; an in-flight provider request may still finish.'
          : null,
    ));
    _completeWaiter(id);
    return true;
  }

  Future<OperationRecord> wait(String id) {
    final record = _byId(id);
    if (record == null)
      return Future.error(StateError('Unknown operation $id'));
    if (record.terminal) return Future.value(record);
    return (_waiters[id] ??= Completer<OperationRecord>()).future;
  }

  List<OperationRecord> takeDeliveries() {
    final pending = _records
        .where((record) =>
            record.deliveredAt == null &&
            (record.state == OperationState.succeeded ||
                record.state == OperationState.failed ||
                record.state == OperationState.interrupted))
        .toList();
    if (pending.isEmpty) return const [];
    final deliveredAt = clock();
    for (final record in pending) {
      _replace(
        record.copyWith(deliveredAt: deliveredAt),
        persist: false,
        notify: false,
      );
    }
    _persist();
    return List.unmodifiable(pending);
  }

  OperationRecord? _byId(String id) {
    for (final record in _records) {
      if (record.id == id) return record;
    }
    return null;
  }

  void _replace(
    OperationRecord next, {
    bool persist = true,
    bool notify = true,
  }) {
    final index = _records.indexWhere((record) => record.id == next.id);
    if (index < 0) return;
    _records[index] = next;
    if (persist) _persistOrFail(next.id);
    if (notify) _changes.add(next);
  }

  void _completeWaiter(String id) {
    final waiter = _waiters.remove(id);
    final record = _byId(id);
    if (waiter != null && !waiter.isCompleted && record != null) {
      waiter.complete(record);
    }
  }

  void _persistOrFail(String id) {
    try {
      _persist();
    } catch (error) {
      final current = _byId(id);
      if (current != null && !current.terminal) {
        _replace(
            current.copyWith(
              state: OperationState.failed,
              updatedAt: clock(),
              error: 'Could not persist operation state: $error',
            ),
            persist: false);
      }
      issues.add('Operation state could not be saved: $error');
    }
  }

  void _persist() {
    if (path == null) return;
    final file = File(path!);
    file.parent.createSync(recursive: true);
    writeJsonAtomic(file, {
      'version': 1,
      'operations': _records.map((record) => record.toJson()).toList(),
    });
  }
}
