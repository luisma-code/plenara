import 'dart:io';

import 'package:plenara/execution_coordinator.dart';
import 'package:plenara/storage_repository.dart';
import 'package:test/test.dart';

Map<String, dynamic> task(String id) => {
      'id': id,
      'typeId': 'task',
      '_schemaVersion': 1,
      'description': id,
      'completed': false,
      'createdAt': '2026-08-17',
    };

void main() {
  test('a kill after every operation index recovers the same three-record turn',
      () {
    for (var crashAt = 0; crashAt < 3; crashAt++) {
      final root = Directory.systemTemp.createTempSync('plenara_exec_crash_');
      addTearDown(() => root.deleteSync(recursive: true));
      final data = Directory('${root.path}/data')..createSync();
      final device = Directory('${root.path}/device')..createSync();
      final repository =
          FileStorageRepository(data.path, deviceDir: device.path);
      final journal = FileExecutionJournal(device.path);
      final store = repository.loadRecords();
      final crashing = ExecutionCoordinator(
        repository: repository,
        store: store,
        journal: journal,
        afterPersist: (_, index) {
          if (index == crashAt) throw SimulatedProcessDeath(index);
        },
      );

      expect(
        () => crashing.execute(
          writes: [task('a'), task('b'), task('c')],
          deletes: const [],
          origin: 'voice',
          description: 'created three tasks',
          frozenInputs: const {'utterance': 'add a, b, and c'},
        ),
        throwsA(isA<SimulatedProcessDeath>()),
      );

      final reopenedRepository = FileStorageRepository(
        data.path,
        deviceDir: device.path,
      );
      final reopenedStore = reopenedRepository.loadRecords();
      final reopened = ExecutionCoordinator(
        repository: reopenedRepository,
        store: reopenedStore,
        journal: FileExecutionJournal(device.path),
      );
      final recovery = reopened.recover();

      expect(recovery.single.state, ExecutionResultState.recovered);
      expect(reopenedStore.keys, containsAll(['a', 'b', 'c']));
      expect(FileExecutionJournal(device.path).entries.single.phase,
          ExecutionPhase.completed);
    }
  });

  test('targeted undo survives restart and ignores an intervening write', () {
    final root = Directory.systemTemp.createTempSync('plenara_exec_undo_');
    addTearDown(() => root.deleteSync(recursive: true));
    final data = Directory('${root.path}/data')..createSync();
    final device = Directory('${root.path}/device')..createSync();
    final repository = FileStorageRepository(data.path, deviceDir: device.path);
    final store = repository.loadRecords();
    final coordinator = ExecutionCoordinator(
      repository: repository,
      store: store,
      journal: FileExecutionJournal(device.path),
    );
    final first = coordinator.execute(
      writes: [task('first')],
      deletes: const [],
      origin: 'voice',
    );
    coordinator.execute(
      writes: [task('second')],
      deletes: const [],
      origin: 'voice',
    );

    final reopenedRepository =
        FileStorageRepository(data.path, deviceDir: device.path);
    final reopenedStore = reopenedRepository.loadRecords();
    final reopened = ExecutionCoordinator(
      repository: reopenedRepository,
      store: reopenedStore,
      journal: FileExecutionJournal(device.path),
    );
    final undo = reopened.undo(first.record!.id);

    expect(undo.state, ExecutionResultState.reversed);
    expect(reopenedStore, isNot(contains('first')));
    expect(reopenedStore, contains('second'));
  });

  test('targeted undo refuses to overwrite a later edit to the same record',
      () {
    final root = Directory.systemTemp.createTempSync('plenara_exec_conflict_');
    addTearDown(() => root.deleteSync(recursive: true));
    final data = Directory('${root.path}/data')..createSync();
    final device = Directory('${root.path}/device')..createSync();
    final repository = FileStorageRepository(data.path, deviceDir: device.path);
    final store = repository.loadRecords();
    final coordinator = ExecutionCoordinator(
      repository: repository,
      store: store,
      journal: FileExecutionJournal(device.path),
    );
    final first = coordinator.execute(
      writes: [task('same')],
      deletes: const [],
      origin: 'voice',
    );
    final edited = task('same')..['description'] = 'edited later';
    coordinator.execute(
      writes: [edited],
      deletes: const [],
      origin: 'manual-edit',
    );

    final undo = coordinator.undo(first.record!.id);

    expect(undo.state, ExecutionResultState.conflict);
    expect(store['same']!['description'], 'edited later');
  });

  test('a corrupt journal is visible and its exact bytes are preserved', () {
    final root = Directory.systemTemp.createTempSync('plenara_exec_corrupt_');
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File('${root.path}/execution-journal.json')
      ..writeAsStringSync('{half-written');
    final exact = file.readAsBytesSync();

    final journal = FileExecutionJournal(root.path);

    expect(journal.issues.single, startsWith('execution_journal_corrupt:'));
    expect(File('${file.path}.corrupt').readAsBytesSync(), exact);
    expect(journal.entries, isEmpty);
  });

  test('every declared mutation origin shares failed-before-write semantics',
      () {
    const origins = [
      'voice',
      'reference',
      'manual-edit',
      'planner-direct',
      'routine-authoring',
      'routine-figure-fill',
      'automation-approval',
      'correction',
      'cloud',
    ];
    for (final origin in origins) {
      final store = <String, Map<String, dynamic>>{};
      final result = ExecutionCoordinator(
        repository: _NeverReachedRepository(),
        store: store,
        journal: _FailingJournal(),
      ).execute(
        writes: [task(origin)],
        deletes: const [],
        origin: origin,
      );
      expect(result.state, ExecutionResultState.failedBeforeWrite,
          reason: origin);
      expect(store, isEmpty, reason: origin);
    }
  });

  test('journal failure is failed-before-write and never mutates memory', () {
    final root =
        Directory.systemTemp.createTempSync('plenara_exec_journal_fail_');
    addTearDown(() => root.deleteSync(recursive: true));
    final repository = FileStorageRepository(root.path);
    final store = <String, Map<String, dynamic>>{};
    final coordinator = ExecutionCoordinator(
      repository: repository,
      store: store,
      journal: _FailingJournal(),
    );

    final result = coordinator.execute(
      writes: [task('never-written')],
      deletes: const [],
      origin: 'voice',
    );

    expect(result.state, ExecutionResultState.failedBeforeWrite);
    expect(store, isEmpty);
    expect(Directory('${root.path}/records').existsSync(), isFalse);
  });

  test('recovery refuses to replay a stuck write over a later durable edit',
      () {
    final root =
        Directory.systemTemp.createTempSync('plenara_exec_recover_conflict_');
    addTearDown(() => root.deleteSync(recursive: true));
    final data = Directory('${root.path}/data')..createSync();
    final device = Directory('${root.path}/device')..createSync();
    final inner = FileStorageRepository(data.path, deviceDir: device.path);
    final repository = _FlakyRepository(inner);
    final store = inner.loadRecords();
    final coordinator = ExecutionCoordinator(
      repository: repository,
      store: store,
      journal: FileExecutionJournal(device.path),
    );

    repository.failPersist = true;
    final stuck = coordinator.execute(
      writes: [task('same')..['description'] = 'first version'],
      deletes: const [],
      origin: 'voice',
    );
    expect(stuck.state, ExecutionResultState.appliedInMemory);
    repository.failPersist = false;
    final later = coordinator.execute(
      writes: [task('same')..['description'] = 'edited later'],
      deletes: const [],
      origin: 'manual-edit',
    );
    expect(later.state, ExecutionResultState.persisted);

    final reopenedRepository =
        FileStorageRepository(data.path, deviceDir: device.path);
    final reopenedStore = reopenedRepository.loadRecords();
    final reopened = ExecutionCoordinator(
      repository: reopenedRepository,
      store: reopenedStore,
      journal: FileExecutionJournal(device.path),
    );
    final outcomes = reopened.recover();

    expect(reopenedStore['same']!['description'], 'edited later');
    expect(outcomes.single.state, ExecutionResultState.conflict);
    expect(outcomes.single.record!.id, stuck.record!.id);
    // A later launch must not resurrect the conflicted record either.
    final again = ExecutionCoordinator(
      repository: FileStorageRepository(data.path, deviceDir: device.path),
      store: reopenedStore,
      journal: FileExecutionJournal(device.path),
    );
    expect(again.recover(), isEmpty);
    expect(reopenedStore['same']!['description'], 'edited later');
  });

  test('undo of an applying record refuses to overwrite a later edit', () {
    final root =
        Directory.systemTemp.createTempSync('plenara_exec_applying_undo_');
    addTearDown(() => root.deleteSync(recursive: true));
    final data = Directory('${root.path}/data')..createSync();
    final device = Directory('${root.path}/device')..createSync();
    final repository =
        _FlakyRepository(FileStorageRepository(data.path, deviceDir: device.path));
    final store = <String, Map<String, dynamic>>{};
    final coordinator = ExecutionCoordinator(
      repository: repository,
      store: store,
      journal: FileExecutionJournal(device.path),
    );

    repository.failPersist = true;
    final stuck = coordinator.execute(
      writes: [task('same')..['description'] = 'first version'],
      deletes: const [],
      origin: 'voice',
    );
    expect(stuck.state, ExecutionResultState.appliedInMemory);
    repository.failPersist = false;
    coordinator.execute(
      writes: [task('same')..['description'] = 'edited later'],
      deletes: const [],
      origin: 'manual-edit',
    );

    final undo = coordinator.undo(stuck.record!.id);

    expect(undo.state, ExecutionResultState.conflict);
    expect(store['same']!['description'], 'edited later');
  });

  test('a deterministically failing replay escalates after three attempts',
      () {
    final root =
        Directory.systemTemp.createTempSync('plenara_exec_replay_cap_');
    addTearDown(() => root.deleteSync(recursive: true));
    final data = Directory('${root.path}/data')..createSync();
    File('${data.path}/records').writeAsStringSync('blocks records directory');
    final device = Directory('${root.path}/device')..createSync();
    final first = ExecutionCoordinator(
      repository: FileStorageRepository(data.path, deviceDir: device.path),
      store: <String, Map<String, dynamic>>{},
      journal: FileExecutionJournal(device.path),
    ).execute(
      writes: [task('stuck')],
      deletes: const [],
      origin: 'voice',
    );
    expect(first.state, ExecutionResultState.appliedInMemory);

    ExecutionCoordinator relaunch() => ExecutionCoordinator(
          repository: FileStorageRepository(data.path, deviceDir: device.path),
          store: <String, Map<String, dynamic>>{},
          journal: FileExecutionJournal(device.path),
        );
    for (var attempt = 1; attempt <= 3; attempt++) {
      expect(relaunch().recover().single.state,
          ExecutionResultState.appliedInMemory,
          reason: 'replay attempt $attempt still retries');
    }

    final escalated = relaunch().recover();
    expect(escalated.single.state, ExecutionResultState.conflict);
    // Escalation is terminal-but-preserved: later launches leave it alone
    // and the journal still holds the record for repair.
    expect(relaunch().recover(), isEmpty);
    expect(
      FileExecutionJournal(device.path)
          .entries
          .where((entry) => entry.id == first.record!.id),
      isNotEmpty,
    );
  });

  test('undo over a corrupted journal refuses honestly and preserves bytes',
      () {
    final root =
        Directory.systemTemp.createTempSync('plenara_exec_undo_corrupt_');
    addTearDown(() => root.deleteSync(recursive: true));
    final data = Directory('${root.path}/data')..createSync();
    final device = Directory('${root.path}/device')..createSync();
    final repository = FileStorageRepository(data.path, deviceDir: device.path);
    final store = repository.loadRecords();
    final seeded = ExecutionCoordinator(
      repository: repository,
      store: store,
      journal: FileExecutionJournal(device.path),
    ).execute(
      writes: [task('first')],
      deletes: const [],
      origin: 'voice',
    );
    expect(seeded.state, ExecutionResultState.persisted);

    final journalFile =
        File('${device.path}/execution-journal.json')
          ..writeAsStringSync('{torn mid-write');
    final exact = journalFile.readAsBytesSync();

    final reopenedRepository =
        FileStorageRepository(data.path, deviceDir: device.path);
    final reopenedStore = reopenedRepository.loadRecords();
    final journal = FileExecutionJournal(device.path);
    expect(journal.issues.single, startsWith('execution_journal_corrupt:'));
    final reopened = ExecutionCoordinator(
      repository: reopenedRepository,
      store: reopenedStore,
      journal: journal,
    );

    final undo = reopened.undo(seeded.record!.id);

    expect(undo.state, ExecutionResultState.failedBeforeWrite);
    expect(reopenedStore, contains('first'));
    expect(File('${journalFile.path}.corrupt').readAsBytesSync(), exact);
  });

  test(
      'record persistence failure reports applied-in-memory and stays recoverable',
      () {
    final root =
        Directory.systemTemp.createTempSync('plenara_exec_persist_fail_');
    addTearDown(() => root.deleteSync(recursive: true));
    final data = Directory('${root.path}/data')..createSync();
    File('${data.path}/records').writeAsStringSync('blocks records directory');
    final device = Directory('${root.path}/device')..createSync();
    final store = <String, Map<String, dynamic>>{};
    final coordinator = ExecutionCoordinator(
      repository: FileStorageRepository(data.path, deviceDir: device.path),
      store: store,
      journal: FileExecutionJournal(device.path),
    );

    final result = coordinator.execute(
      writes: [task('memory-only')],
      deletes: const [],
      origin: 'voice',
    );

    expect(result.state, ExecutionResultState.appliedInMemory);
    expect(store, contains('memory-only'));
    expect(FileExecutionJournal(device.path).entries.single.phase,
        ExecutionPhase.applying);
  });
}

class _FailingJournal implements ExecutionJournal {
  @override
  List<String> get issues => const [];

  @override
  int allocateId() => 1;

  @override
  List<DurableExecutionRecord> get entries => const [];

  @override
  void prune(int maxCompleted) => throw UnsupportedError('not reached');

  @override
  void put(DurableExecutionRecord record) =>
      throw FileSystemException('journal unavailable');
}

/// Delegates to a real file repository but can be told to fail record
/// persistence, producing an honest applied-in-memory (`applying`) record.
class _FlakyRepository implements StorageRepository {
  final StorageRepository inner;
  bool failPersist = false;

  _FlakyRepository(this.inner);

  @override
  void persist(Map<String, dynamic> record) {
    if (failPersist) {
      throw const FileSystemException('simulated persist failure');
    }
    inner.persist(record);
  }

  @override
  void appendCorpusLearned(Map<String, dynamic> entry) =>
      inner.appendCorpusLearned(entry);
  @override
  List<dynamic> loadCorpusLearned() => inner.loadCorpusLearned();
  @override
  Map<String, Map<String, dynamic>> loadDefs(String subdir, String key) =>
      inner.loadDefs(subdir, key);
  @override
  Map<String, Map<String, dynamic>> loadRecords() => inner.loadRecords();
  @override
  void logTurn(Map<String, dynamic> entry) => inner.logTurn(entry);
  @override
  void remove(String id) => inner.remove(id);
  @override
  void removeCorpusLearned(String template) =>
      inner.removeCorpusLearned(template);
  @override
  void removeDef(String subdir, String id) => inner.removeDef(subdir, id);
  @override
  void writeDef(String subdir, String idKey, Map<String, dynamic> def) =>
      inner.writeDef(subdir, idKey, def);
}

class _NeverReachedRepository implements StorageRepository {
  Never _fail() => throw StateError('record storage must not be reached');

  @override
  void appendCorpusLearned(Map<String, dynamic> entry) => _fail();
  @override
  List<dynamic> loadCorpusLearned() => _fail();
  @override
  Map<String, Map<String, dynamic>> loadDefs(String subdir, String key) =>
      _fail();
  @override
  Map<String, Map<String, dynamic>> loadRecords() => _fail();
  @override
  void logTurn(Map<String, dynamic> entry) => _fail();
  @override
  void persist(Map<String, dynamic> record) => _fail();
  @override
  void remove(String id) => _fail();
  @override
  void removeCorpusLearned(String template) => _fail();
  @override
  void removeDef(String subdir, String id) => _fail();
  @override
  void writeDef(String subdir, String idKey, Map<String, dynamic> def) =>
      _fail();
}
