/// Two live Sessions over ONE shared provider folder (Spec 06): the closest
/// in-process approximation of two devices syncing through a cloud folder.
/// Each session has its own device-local dir (own device id, own shadow), both
/// watch the shared dataDir, and every interleaved edit — including a record
/// delete — must converge in BOTH in-memory stores, with the tombstone
/// surviving on disk so a restore cannot resurrect the record.
import 'dart:convert';
import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

String _tmp(String name) =>
    Directory.systemTemp.createTempSync('plenara_twosession_$name').path;

void main() {
  test(
      'two watch-enabled Sessions over one shared folder converge through '
      'interleaved edits and a delete, tombstone included', () async {
    final dataDir = makeTempDataDir();
    final a = Session(
      dataDir,
      deviceDir: _tmp('device_a'),
      cloud: ClaudeClient(apiKeyOverride: ''),
    );
    final b = Session(
      dataDir,
      deviceDir: _tmp('device_b'),
      cloud: ClaudeClient(apiKeyOverride: ''),
    );
    await a.init(retrieval: false, watchStorage: true);
    await b.init(retrieval: false, watchStorage: true);
    addTearDown(a.dispose);
    addTearDown(b.dispose);

    const id = 'shared-task';
    Future<void> converged(Session session, bool Function(Session) done) =>
        done(session)
            ? Future.value()
            : session.storageChanges
                .where((_) => done(session))
                .first
                .timeout(const Duration(seconds: 5));

    // A creates the record; both live stores pick it up from the file event.
    var seenA = converged(a, (s) => s.store.containsKey(id));
    var seenB = converged(b, (s) => s.store.containsKey(id));
    a.repo.persist({
      'id': id,
      'typeId': 'task',
      'description': 'from device A',
      'completed': false,
    });
    await seenA;
    await seenB;
    expect(b.store[id]!['description'], 'from device A');

    // B edits it; A must observe the edit.
    seenA = converged(a, (s) => s.store[id]?['completed'] == true);
    seenB = converged(b, (s) => s.store[id]?['completed'] == true);
    b.repo.persist({
      'id': id,
      'typeId': 'task',
      'description': 'from device A',
      'completed': true,
    });
    await seenA;
    await seenB;
    expect(a.store[id]!['completed'], isTrue);

    // A deletes it; the delete must propagate to B's live store as well.
    seenA = converged(a, (s) => !s.store.containsKey(id));
    seenB = converged(b, (s) => !s.store.containsKey(id));
    a.repo.remove(id);
    await seenA;
    await seenB;
    expect(a.store.containsKey(id), isFalse);
    expect(b.store.containsKey(id), isFalse);

    // Tombstone propagation: the record is deleted-but-present on disk, so a
    // provider restore of either replica cannot resurrect it.
    final onDisk = jsonDecode(
      File('$dataDir/records/$id.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(onDisk['_meta']['deleted'], isTrue);
    expect(onDisk['_meta']['deletedStamp'], isNotNull);
  });
}
