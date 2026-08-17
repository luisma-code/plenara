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
