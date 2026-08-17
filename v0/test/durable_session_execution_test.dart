import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-08-17T09:00:00');

class _NoCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
    String utterance,
    Map<String, Map<String, dynamic>> skills, {
    Set<String> knownContacts = const {},
  }) async =>
      const CloudError(CloudErrorKind.noKey);

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

Future<Session> openSession(String dataDir, String deviceDir) async {
  final session = Session(
    dataDir,
    deviceDir: deviceDir,
    clock: _now,
    cloud: _NoCloud(),
  );
  await session.init(retrieval: false);
  return session;
}

void main() {
  test('task creation remains undoable after a full session restart', () async {
    final dataDir = makeTempDataDir();
    addTearDown(() => Directory(dataDir).deleteSync(recursive: true));
    final deviceDir =
        Directory.systemTemp.createTempSync('plenara_durable_session_').path;
    addTearDown(() => Directory(deviceDir).deleteSync(recursive: true));

    final first = await openSession(dataDir, deviceDir);
    expect(await first.handle('add buy milk to my list'), contains('Added'));
    expect(first.store.values.single['description'], 'buy milk');
    expect(File('$deviceDir/execution-journal.json').existsSync(), isTrue);

    final reopened = await openSession(dataDir, deviceDir);
    expect(reopened.store.values.single['description'], 'buy milk');
    expect(await reopened.handle('undo that'), contains('Undone'));
    expect(reopened.store, isEmpty);

    final verified = await openSession(dataDir, deviceDir);
    expect(verified.store, isEmpty);
  });

  test('task completion and its undo both survive restart', () async {
    final dataDir = makeTempDataDir();
    addTearDown(() => Directory(dataDir).deleteSync(recursive: true));
    final deviceDir =
        Directory.systemTemp.createTempSync('plenara_durable_completion_').path;
    addTearDown(() => Directory(deviceDir).deleteSync(recursive: true));

    final first = await openSession(dataDir, deviceDir);
    await first.handle('add book flights to my list');

    final second = await openSession(dataDir, deviceDir);
    expect(await second.handle('mark book flights done'), contains('Marked'));
    expect(second.store.values.single['completed'], isTrue);

    final third = await openSession(dataDir, deviceDir);
    expect(await third.handle('undo that'), contains('Undone'));
    expect(third.store.values.single['completed'], isFalse);

    final verified = await openSession(dataDir, deviceDir);
    expect(verified.store.values.single['completed'], isFalse);
  });
}
