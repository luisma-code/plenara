/// Turn/mutation SERIALIZATION (Session).
///
/// `Session.handle` and every UI-driven mutation entry point (`completeTask`,
/// `updateTaskPlans`, `editField`, `deleteRecord`, `undoLast`, `undoById`,
/// `applyPlanProposal`, `applyWeeklyReview`) mutate the SAME per-turn instance
/// state: the `_out*` telemetry the turnlog entry is built from, the
/// previous-turn correction snapshot, the last execution id the conversation
/// ledger stamps, and the `_turnInProgress` flag that defers external storage
/// refreshes. A tap that lands while a voice turn is awaiting the cloud used to
/// interleave with it and stomp all of that.
///
/// These tests hold a turn mid-flight on a gated cloud and drive a second
/// mutation into it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/reminders.dart';
import 'package:plenara/session.dart';
import 'package:plenara/storage_repository.dart';
import 'package:plenara/store.dart' as fs;
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-08-17T09:00:00');

/// A cloud whose residual route is held open per-utterance, so a turn can be
/// parked exactly where a real one parks: awaiting the cloud residual.
class _GatedCloud implements CloudClient {
  /// utterance -> the route to return once its gate opens.
  final Map<String, Map<String, dynamic>?> routes;
  final Map<String, Completer<void>> _entered = {};
  final Map<String, Completer<void>> _gates = {};

  _GatedCloud(this.routes);

  Completer<void> _enteredFor(String u) =>
      _entered.putIfAbsent(u, () => Completer<void>());
  Completer<void> _gateFor(String u) =>
      _gates.putIfAbsent(u, () => Completer<void>());

  /// Completes once the session's turn for [u] is parked inside routeResidual.
  Future<void> entered(String u) => _enteredFor(u).future;

  /// Let the parked turn for [u] proceed.
  void release(String u) {
    final gate = _gateFor(u);
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
    String utterance,
    Map<String, Map<String, dynamic>> skills, {
    Set<String> knownContacts = const {},
  }) async {
    if (!routes.containsKey(utterance)) {
      return const CloudError(CloudErrorKind.noKey);
    }
    final entered = _enteredFor(utterance);
    if (!entered.isCompleted) entered.complete();
    await _gateFor(utterance).future;
    return CloudOk(routes[utterance]);
  }

  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(
    String description, {
    String? priorError,
  }) async =>
      const CloudError(CloudErrorKind.noKey);

  @override
  Future<CloudResult<String>> generate(String kind, String context) async =>
      const CloudError(CloudErrorKind.noKey);
}

/// Records the armed set like a real backend, and holds the FIRST cancel of one
/// specific ref open — the lever that keeps a queued tap observably in-flight
/// after its write has already landed.
class _GatedScheduler implements NotificationScheduler {
  final Map<String, DateTime> _armed = {};
  final String gatedRef;
  final gate = Completer<void>();
  final reached = Completer<void>();
  bool _consumed = false;

  /// True once the gated cancel has run to completion — i.e. the tap that
  /// triggered it has finished its reconcile.
  bool cancelCompleted = false;

  _GatedScheduler(this.gatedRef);

  @override
  Future<void> schedule(String ref, DateTime when, String body) async {
    // ignore: avoid_print
    print('SCHEDULE $ref');
    _armed[ref] = when;
  }

  @override
  Future<void> cancel(String ref) async {
    // ignore: avoid_print
    print('CANCEL $ref consumed=$_consumed');
    if (ref == gatedRef && !_consumed) {
      _consumed = true;
      if (!reached.isCompleted) reached.complete();
      await gate.future;
      cancelCompleted = true;
    }
    _armed.remove(ref);
  }

  @override
  Map<String, DateTime> armed() => Map.of(_armed);

  @override
  Future<bool> selfTest() async => true;

  @override
  String? unavailableReason() => null;
}

/// A real file-backed repository whose external-change signal is driven by the
/// test instead of the OS watcher, so "a provider event arrived mid-turn" is
/// deterministic rather than a race with filesystem notifications.
class _ManualWatchStorage extends FileStorageRepository {
  final _events = StreamController<void>.broadcast();
  _ManualWatchStorage(super.dataDir, {super.deviceDir});

  @override
  Stream<void> watchChanges() => _events.stream;

  void signalExternalChange() {
    // ignore: avoid_print
    print('SIGNAL hasListener=${_events.hasListener}');
    _events.add(null);
  }
}

String _deviceDir() =>
    Directory.systemTemp.createTempSync('plenara_concurrency_dev_').path;

Future<Session> _open(
  String dataDir,
  String deviceDir,
  CloudClient cloud, {
  NotificationScheduler? scheduler,
  StorageRepository? storage,
  bool watchStorage = false,
}) async {
  final session = Session(
    dataDir,
    deviceDir: deviceDir,
    clock: _now,
    cloud: cloud,
    scheduler: scheduler,
    storage: storage,
  );
  await session.init(retrieval: false, watchStorage: watchStorage);
  return session;
}

List<Map<String, dynamic>> _turnlog(String deviceDir) {
  final file = File('$deviceDir/turnlog.jsonl');
  if (!file.existsSync()) return const [];
  return [
    for (final line in file.readAsLinesSync())
      if (line.trim().isNotEmpty)
        (jsonDecode(line) as Map).cast<String, dynamic>(),
  ];
}

void main() {
  test(
      'a tap issued mid-turn applies AFTER the turn, and the turn keeps its own '
      'telemetry, ledger entry and execution id', () async {
    final dataDir = makeTempDataDir();
    addTearDown(() => Directory(dataDir).deleteSync(recursive: true));
    final deviceDir = _deviceDir();
    addTearDown(() => Directory(deviceDir).deleteSync(recursive: true));

    const utterance = 'squirrel the widget into tomorrow please';
    final cloud = _GatedCloud({
      utterance: {
        'skillId': 'create-task',
        'slots': {'description': 'book flights'},
        'source': 'cloud',
      },
    });
    final session = await _open(dataDir, deviceDir, cloud);
    addTearDown(session.dispose);

    // A task to tap, created offline through the corpus.
    expect(await session.handle('add walk the dog to my list'),
        contains('Added'));
    final taskId = session.store.values
        .firstWhere((r) => r['description'] == 'walk the dog')['id'] as String;

    // Park a real turn inside the cloud residual, then tap a task row.
    final turn = session.handle(utterance);
    await cloud.entered(utterance);
    final tap = session.completeTask(taskId);
    // Give an unserialized tap every chance to run to completion mid-turn.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    cloud.release(utterance);

    final reply = await turn;
    final write = await tap;

    // Both mutations are real and durable.
    expect(reply, contains('book flights'));
    expect(write.ok, isTrue, reason: write.message);
    expect(session.store.values.any((r) => r['description'] == 'book flights'),
        isTrue);
    expect(session.store[taskId]!['completed'], isTrue);
    final onDisk = fs.loadRecords('$dataDir/records');
    expect(onDisk[taskId]!['completed'], isTrue);
    expect(onDisk.values.any((r) => r['description'] == 'book flights'), isTrue);

    // The tap ran AFTER the turn: its execution id is the later one.
    final turnExecution = session.executions.journal.entries
        .firstWhere((e) => '${e.description}'.contains('book flights'));
    // lastWhere, not firstWhere: this task was CREATED by a setup turn, so its
    // creation entry also mentions it and is the older of the two. The tap's
    // completion is the later entry, and it is the one whose ordering matters.
    final tapExecution = session.executions.journal.entries
        .lastWhere((e) => '${e.description}'.contains('walk the dog'));
    expect(tapExecution.id, greaterThan(turnExecution.id),
        reason: 'a tap must queue behind the live turn, not jump ahead of it');

    // The turn's turnlog entry describes the TURN, not the tap.
    final logged = _turnlog(deviceDir);
    final turnEntry = logged.firstWhere((e) => e['utterance'] == utterance);
    expect(turnEntry['source'], 'cloud');
    expect(turnEntry['skill'], 'create-task');
    expect(turnEntry['response'], contains('book flights'));
    expect('${turnEntry['writes']}', isNot(contains('walk the dog')));

    // The turn's conversation-ledger entry carries the TURN's execution id, not
    // the one the tap minted.
    final ledgerEntry =
        session.conversationLedger.entries.firstWhere((e) => e.utterance == utterance);
    expect(ledgerEntry.executionId, turnExecution.id,
        reason: 'a concurrent tap must not stamp its execution id on the turn');
  });

  test('two concurrent handle() calls each keep their own utterance, response '
      'and telemetry', () async {
    final dataDir = makeTempDataDir();
    addTearDown(() => Directory(dataDir).deleteSync(recursive: true));
    final deviceDir = _deviceDir();
    addTearDown(() => Directory(deviceDir).deleteSync(recursive: true));

    const first = 'squirrel the first widget';
    const second = 'squirrel the second widget';
    final cloud = _GatedCloud({
      first: {
        'skillId': 'create-task',
        'slots': {'description': 'first errand'},
        'source': 'cloud',
      },
      second: {
        'skillId': 'log-mood',
        'slots': {'mood': 'great'},
        'source': 'cloud',
      },
    });
    final session = await _open(dataDir, deviceDir, cloud);
    addTearDown(session.dispose);

    final a = session.handle(first);
    await cloud.entered(first);
    final b = session.handle(second);
    // Release out of order: the second turn must still not start early.
    cloud.release(second);
    await Future<void>.delayed(Duration.zero);
    cloud.release(first);

    final replyA = await a;
    final replyB = await b;
    expect(replyA, contains('first errand'));
    expect(replyB, isNot(contains('first errand')));

    final logged = _turnlog(deviceDir);
    // The cloud released the SECOND turn first. Serialized, the second turn had
    // not started yet, so the first still finishes — and logs — first. Without
    // the queue the second turn runs to completion while the first is parked,
    // and this order inverts.
    expect(
      logged.indexWhere((e) => e['utterance'] == first),
      lessThan(logged.indexWhere((e) => e['utterance'] == second)),
      reason: 'a queued turn must not overtake the turn it queued behind',
    );
    final entryA = logged.firstWhere((e) => e['utterance'] == first);
    final entryB = logged.firstWhere((e) => e['utterance'] == second);
    expect(entryA['skill'], 'create-task');
    expect(entryA['response'], contains('first errand'));
    expect(entryB['skill'], 'log-mood');
    expect(entryB['response'], replyB.length > 240 ? isNotNull : replyB);
    expect('${entryB['writes']}', isNot(contains('first errand')),
        reason: "one turn's writes must not bleed into the other's trace");

    // Each turn's ledger entry pairs its own utterance with its own reply.
    final ledger = session.conversationLedger.entries;
    expect(ledger.firstWhere((e) => e.utterance == first).reply, replyA);
    expect(ledger.firstWhere((e) => e.utterance == second).reply, replyB);
    expect(
      ledger.firstWhere((e) => e.utterance == first).executionId,
      isNot(ledger.firstWhere((e) => e.utterance == second).executionId),
    );
  });

  test(
      'a storage refresh queued during a turn drains once, after the queued tap '
      'has finished too', () async {
    final dataDir = makeTempDataDir();
    addTearDown(() => Directory(dataDir).deleteSync(recursive: true));
    final deviceDir = _deviceDir();
    addTearDown(() => Directory(deviceDir).deleteSync(recursive: true));

    // An armed reminder, so the queued tap's post-write reconcile has a cancel
    // to make — the lever that keeps it observably in flight.
    fs.persist({
      'id': 'rem-1',
      'typeId': 'reminder',
      'text': 'call the vet',
      'remindAt': '2026-08-18T09:00:00',
      'createdAt': '2026-08-17T08:00:00',
    }, '$dataDir/records', fs.HlcDevice('seed'));

    const utterance = 'squirrel the widget for later';
    final cloud = _GatedCloud({
      utterance: {
        'skillId': 'create-task',
        'slots': {'description': 'renew passport'},
        'source': 'cloud',
      },
    });
    final scheduler = _GatedScheduler('rem-1');
    final storage = _ManualWatchStorage(dataDir, deviceDir: deviceDir);
    final session = await _open(dataDir, deviceDir, cloud,
        scheduler: scheduler, storage: storage, watchStorage: true);
    addTearDown(session.dispose);

    var refreshes = 0;
    final refreshSawTapFinished = <bool>[];
    final sub = session.storageChanges.listen((_) {
      refreshes++;
      refreshSawTapFinished.add(scheduler.cancelCompleted);
    });
    addTearDown(sub.cancel);

    // Park the turn inside the cloud residual.
    final turn = session.handle(utterance);
    await cloud.entered(utterance);

    // An external device drops a record in while the turn is live: the refresh
    // must be DEFERRED, not applied mid-turn.
    fs.persist({
      'id': 'external-task',
      'typeId': 'task',
      'description': 'Arrived from another device',
      'completed': false,
    }, '$dataDir/records', fs.HlcDevice('remote'));
    storage.signalExternalChange();
    await Future<void>.delayed(Duration.zero);

    // The turn is still parked in the cloud, so the external change must be
    // holding: applying it here would swap the store out from under a live turn.
    expect(refreshes, 0,
        reason: 'the deferred refresh must not land while a turn is live');

    // ...and the user taps delete on the reminder row at the same moment.
    final tap = session.deleteRecord('rem-1');
    await Future<void>.delayed(Duration.zero);
    expect(refreshes, 0,
        reason: 'nor while a tap queued behind that turn is still pending');

    // Let the tap's post-delete reminder reconcile complete (the fake scheduler
    // holds its cancel so the tap is observably still in flight above).
    scheduler.gate.complete();
    cloud.release(utterance);
    final reply = await turn;
    expect(reply, contains('renew passport'));
    final write = await tap;
    expect(write.ok, isTrue, reason: write.message);

    // The deferred refresh drains as the LAST queued operation releases its
    // slot — which happens before that operation's future completes, so by here
    // it has already run. (Awaiting another storageChanges event would hang
    // forever waiting for a second refresh that correctly never comes.)
    await Future<void>.delayed(Duration.zero);
    expect(session.store.containsKey('external-task'), isTrue,
        reason: 'the record that arrived mid-turn is applied once it is safe');
    expect(refreshes, 1, reason: 'the deferred refresh drains exactly once');
    expect(refreshSawTapFinished, [true],
        reason: 'the refresh ran after the tap had finished its own work');
    expect(session.store.containsKey('rem-1'), isFalse,
        reason: 'the refresh must not resurrect the record the tap deleted');
    expect(session.store.values.any((r) => r['description'] == 'renew passport'),
        isTrue);
  });

  test('nested paths do not deadlock: a turn that mutates internally, a tap, '
      'and an undo all complete', () async {
    final dataDir = makeTempDataDir();
    addTearDown(() => Directory(dataDir).deleteSync(recursive: true));
    final deviceDir = _deviceDir();
    addTearDown(() => Directory(deviceDir).deleteSync(recursive: true));

    final session = await _open(dataDir, deviceDir, _GatedCloud(const {}));
    addTearDown(session.dispose);

    await session.handle('add file taxes to my list');
    await session.handle('add call the bank to my list');
    final taxes = session.store.values
        .firstWhere((r) => r['description'] == 'file taxes')['id'] as String;

    // "plan my week" + "apply the proposal" runs handle() -> applyPlanProposal()
    // -> updateTaskPlans(): the nested path that a naive lock deadlocks on.
    await session.handle('plan my week');
    final applied = await session.handle('apply the proposal');
    expect(applied, isNotEmpty);

    // A turn, a direct planner mutation and an undo fired together.
    final turn = session.handle('add water the plants to my list');
    final tap = session.completeTask(taxes);
    final undo = session.undoLast();
    final results = await Future.wait<Object>([turn, tap, undo])
        .timeout(const Duration(seconds: 10));
    expect(results, hasLength(3));

    // The engine is still usable afterwards (the queue drained, not wedged).
    expect(await session.handle('list my tasks').timeout(
          const Duration(seconds: 10),
        ),
        isNotEmpty);
  });
}
