import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:plenara/operation_center.dart';
import 'package:test/test.dart';

void main() {
  test('detached work starts immediately and completes on its returned event',
      () async {
    final gate = Completer<String>();
    final began = Completer<void>();
    final center = OperationCenter();

    final started = center.start(
      kind: 'weekly-review',
      title: 'Weekly review',
      run: (_) {
        began.complete();
        return gate.future;
      },
    );
    await began.future;

    expect(center.records.single.state, OperationState.running);
    expect(started.terminal, isFalse);
    gate.complete('A grounded review');
    final finished = await center.wait(started.id);
    expect(finished.state, OperationState.succeeded);
    expect(finished.result, 'A grounded review');
  });

  test('work is serialized by completion events, never elapsed time', () async {
    final firstGate = Completer<String>();
    final firstBegan = Completer<void>();
    final order = <String>[];
    final center = OperationCenter();
    final first = center.start(
      kind: 'first',
      title: 'First',
      run: (_) async {
        firstBegan.complete();
        order.add('first-start');
        final result = await firstGate.future;
        order.add('first-end');
        return result;
      },
    );
    final second = center.start(
      kind: 'second',
      title: 'Second',
      run: (_) async {
        order.add('second-start');
        return 'second';
      },
    );
    await firstBegan.future;
    expect(order, ['first-start']);

    firstGate.complete('first');
    await center.wait(first.id);
    await center.wait(second.id);
    expect(order, ['first-start', 'first-end', 'second-start']);
  });

  test('relaunch marks in-flight work interrupted and never reruns it', () {
    final dir = Directory.systemTemp.createTempSync('plenara_operations_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/operations.json';
    final now = DateTime.parse('2026-08-17T10:00:00');
    File(path).writeAsStringSync(jsonEncode({
      'version': 1,
      'operations': [
        {
          'id': 'operation-1-1',
          'kind': 'weekly-review',
          'title': 'Weekly review',
          'input': {},
          'state': 'running',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
          'progress': 0.05,
        }
      ],
    }));

    final restored = OperationCenter(path: path, clock: () => now);

    expect(restored.records.single.state, OperationState.interrupted);
    expect(restored.records.single.error, contains('retry explicitly'));
  });

  test('terminal delivery is exactly once across relaunch', () async {
    final dir = Directory.systemTemp.createTempSync('plenara_operations_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/operations.json';
    final center = OperationCenter(path: path);
    final operation = center.start(
      kind: 'briefing',
      title: 'Morning briefing',
      run: (_) async => 'Ready',
    );
    await center.wait(operation.id);

    expect(center.takeDeliveries(), hasLength(1));
    expect(center.takeDeliveries(), isEmpty);
    expect(OperationCenter(path: path).takeDeliveries(), isEmpty);
  });

  test('a terminal event can drain delivery without recursively firing',
      () async {
    final center = OperationCenter();
    final delivered = <OperationRecord>[];
    final subscription = center.changes.listen((record) {
      if (record.terminal) delivered.addAll(center.takeDeliveries());
    });
    addTearDown(subscription.cancel);

    final operation = center.start(
      kind: 'review',
      title: 'Review',
      run: (_) async => 'ready',
    );
    await center.wait(operation.id);

    expect(delivered, hasLength(1));
    expect(delivered.single.result, 'ready');
  });

  test('queued cancellation prevents its work from starting', () async {
    final firstGate = Completer<String>();
    var secondRan = false;
    final center = OperationCenter();
    final first = center.start(
      kind: 'first',
      title: 'First',
      run: (_) => firstGate.future,
    );
    final second = center.start(
      kind: 'second',
      title: 'Second',
      run: (_) async {
        secondRan = true;
        return 'second';
      },
    );
    expect(center.cancel(second.id), isTrue);
    firstGate.complete('first');
    await center.wait(first.id);
    await center.wait(second.id);

    expect(secondRan, isFalse);
    expect(center.records.first.state, OperationState.cancelled);
  });

  test('delivered terminal history is bounded while undelivered survives', () async {
    final dir = Directory.systemTemp.createTempSync('plenara_operations_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/operations.json';
    final center = OperationCenter(path: path);
    const overCap = 55; // cap is 50
    for (var index = 0; index < overCap; index++) {
      final operation = center.start(
        kind: 'review',
        title: 'Review $index',
        run: (_) async => 'result $index',
      );
      await center.wait(operation.id);
    }

    // Every terminal record is still undelivered, so nothing may be pruned
    // no matter how far past the cap the ledger grows.
    List<dynamic> onDisk() => (jsonDecode(File(path).readAsStringSync())
        as Map<String, dynamic>)['operations'] as List;
    expect(onDisk(), hasLength(overCap));
    expect(center.takeDeliveries(), hasLength(overCap));

    // The next persist prunes oldest-first down to the cap.
    final latest = center.start(
      kind: 'review',
      title: 'Latest',
      run: (_) async => 'latest',
    );
    await center.wait(latest.id);
    expect(onDisk().length, lessThanOrEqualTo(50));
    final ids = onDisk().map((raw) => (raw as Map)['id']).toList();
    expect(ids, contains(latest.id));
    // Survivors are the most recent, not an arbitrary subset.
    expect(ids, contains(center.records.skip(1).first.id));
  });

  test('a failed delivery persist still hands the results to the user',
      () async {
    final dir = Directory.systemTemp.createTempSync('plenara_operations_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/operations.json';
    final center = OperationCenter(path: path);
    final operation = center.start(
      kind: 'review',
      title: 'Review',
      run: (_) async => 'ready',
    );
    await center.wait(operation.id);

    // Make the operations path unwritable at drain time: the file becomes a
    // directory, so the atomic rename in _persist must fail.
    File(path).deleteSync();
    Directory(path).createSync();

    final delivered = center.takeDeliveries();

    expect(delivered, hasLength(1));
    expect(delivered.single.result, 'ready');
    expect(center.issues, isNotEmpty);
  });

  test('a queued-then-cancelled operation releases its cancellation handle',
      () async {
    final firstGate = Completer<String>();
    final center = OperationCenter();
    final first = center.start(
      kind: 'first',
      title: 'First',
      run: (_) => firstGate.future,
    );
    final second = center.start(
      kind: 'second',
      title: 'Second',
      run: (_) async => 'never runs',
    );
    expect(center.cancel(second.id), isTrue);
    firstGate.complete('first');
    await center.wait(first.id);
    await center.wait(second.id);
    await center.whenIdle;

    expect(center.trackedCancellationCount, 0);
  });

  test('a failed queued-to-running persist aborts before provider spend',
      () async {
    final dir = Directory.systemTemp.createTempSync('plenara_operations_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/operations.json';
    final center = OperationCenter(path: path);
    var providerRan = false;
    final operation = center.start(
      kind: 'review',
      title: 'Review',
      run: (_) async {
        providerRan = true;
        return 'expensive result';
      },
    );
    // start() persisted the queued record successfully; now break the path
    // before the queued->running transition persists.
    File(path).deleteSync();
    Directory(path).createSync();

    final finished = await center.wait(operation.id);
    await center.whenIdle;

    expect(providerRan, isFalse,
        reason: 'work must not run once its record is already terminal');
    expect(finished.state, OperationState.failed);
    expect(center.records.single.state, OperationState.failed);
    expect(center.trackedCancellationCount, 0);
  });

  test('running cancellation is immediate and discards a late result',
      () async {
    final began = Completer<void>();
    final provider = Completer<String>();
    final center = OperationCenter();
    final operation = center.start(
      kind: 'review',
      title: 'Review',
      run: (_) {
        began.complete();
        return provider.future;
      },
    );
    await began.future;

    expect(center.cancel(operation.id), isTrue);
    expect((await center.wait(operation.id)).state, OperationState.cancelled);
    provider.complete('too late');
    await center.whenIdle;
    expect(center.records.single.state, OperationState.cancelled);
    expect(center.records.single.result, isNull);
  });
}
