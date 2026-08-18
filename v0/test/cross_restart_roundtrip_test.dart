/// Cross-restart round-trip: every shipped type with an update path must accept
/// an UPDATE and an UNDO in a NEW session over the same real temp dirs.
///
/// This locks two regressions the review reproduced at runtime:
///  1. store.loadRecords injects the storage envelope's `createdAt` into every
///     flat record, so any post-restart update re-validated the record WITH that
///     field — and the validator rejected it (`unknown_field: createdAt`) until
///     createdAt became a structural passthrough in value_codec.dart.
///  2. An after-image journaled WITHOUT `createdAt` could never deep-equal the
///     reloaded record (which has it injected), so "undo that" for a pre-restart
///     write reported a false conflict ("the record changed afterward") — until
///     Session._executeMutation began stamping createdAt on new records. This
///     half was observed red against the pre-fix session.dart (a journal entry
///     logged in session 1 could not be undone in session 2).
///
/// Two session pairs drive ALL types (real temp dirs, per the storage-tests-use
/// -real-files rule); each stays inside the execution journal's 25-entry ring so
/// the undo drain can reach every pre-restart write.
library;

import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:plenara/store.dart' as fs;
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-08-17T09:00:00');

/// Offline cloud that can also author one scripted routine (so routine +
/// routine_step records exist without a network). Figures decline — text-only
/// steps are the common case and keep this suite deterministic.
class _AuthorCloud implements CloudClient, RoutineAuthor {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
          String u, Map<String, Map<String, dynamic>> s,
          {Set<String> knownContacts = const {}}) async =>
      const CloudError(CloudErrorKind.noKey);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d,
          {String? priorError}) async =>
      const CloudError(CloudErrorKind.noKey);
  @override
  Future<CloudResult<String>> generate(String k, String c) async =>
      const CloudError(CloudErrorKind.noKey);
  @override
  Future<CloudResult<Map<String, dynamic>>> authorRoutine(
      String request, String catalogue,
      {String? kind, String? priorError}) async {
    final keys = catalogue
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(2)
        .map((l) => l.split(' | ').first)
        .toList();
    return CloudOk({
      'title': 'Restart loosener',
      'focusArea': 'low back',
      'kind': 'stretch',
      'estMinutes': 5,
      'steps': [
        {
          'exerciseKey': keys[0],
          'name': 'Step one',
          'durationSeconds': 30,
          'side': 'both'
        },
        {'exerciseKey': keys[1], 'name': 'Step two', 'reps': 8, 'side': 'both'},
      ],
    });
  }

  @override
  Future<CloudResult<Map<String, dynamic>>> authorFigures(
          List<String> movements) async =>
      const CloudError(CloudErrorKind.malformed, 'no figures in this suite');
}

Future<Session> _open(String dataDir, String deviceDir) async {
  final s = Session(dataDir,
      deviceDir: deviceDir, clock: _now, cloud: _AuthorCloud());
  await s.init(retrieval: false);
  return s;
}

(String dataDir, String deviceDir) _dirs(String tag) {
  final dataDir = makeTempDataDir();
  addTearDown(() => Directory(dataDir).deleteSync(recursive: true));
  final deviceDir =
      Directory.systemTemp.createTempSync('plenara_roundtrip_$tag').path;
  addTearDown(() => Directory(deviceDir).deleteSync(recursive: true));
  return (dataDir, deviceDir);
}

String _idOf(Session s, String typeId) => s.store.values
    .firstWhere((r) => r['typeId'] == typeId)['id'] as String;

/// Undo everything in the ring, newest first, asserting EVERY undo succeeds.
/// The LIFO walk crosses the restart boundary into the pre-restart writes —
/// each of which used to false-conflict on the injected createdAt.
Future<void> _drainUndo(Session s) async {
  for (var i = 0; i < 40; i++) {
    final msg = await s.handle('undo that');
    if (msg == 'Nothing to undo.') return;
    expect(msg, contains('Undone'),
        reason: 'every undo in the ring must succeed, got: $msg');
  }
  fail('the undo ring did not drain');
}

void main() {
  test('people & planning types survive restart: update + pre-restart undo',
      () async {
    final (dataDir, deviceDir) = _dirs('people');
    // project/area have no voice creation path — seed them as another device
    // would (the storage envelope invents their createdAt, which is exactly the
    // injected field the codec fix must tolerate on later updates).
    final dev = fs.HlcDevice('remote-seed');
    fs.persist({
      'id': 'project-1',
      'typeId': 'project',
      'name': 'Garden overhaul',
      'status': 'active',
    }, '$dataDir/records', dev);
    fs.persist({'id': 'area-1', 'typeId': 'area', 'name': 'Health'},
        '$dataDir/records', dev);

    // ---- Session 1: create task/reminder/contact/contact_date/contact_fact/
    // goal, and write to the seeded project/area -------------------------------
    final s1 = await _open(dataDir, deviceDir);
    expect(await s1.handle('add buy milk to my list'), contains('Added'));
    expect(await s1.handle('remind me in 20 minutes to water plants'),
        isNot(contains("didn't catch")));
    expect(await s1.handle("Sarah's birthday is on March 3"),
        isNot(contains("didn't catch"))); // contact + contact_date
    expect(await s1.handle('remember that Sarah loves tulips'),
        isNot(contains("didn't catch"))); // contact_fact
    expect(await s1.handle('set a goal to run 20k'),
        isNot(contains("didn't catch")));
    expect((await s1.editField('project-1', 'notes', 'phase one')).ok, isTrue);
    expect((await s1.editField('area-1', 'notes', 'weekly check')).ok, isTrue);
    await s1.dispose();

    // ---- Session 2: update EVERY one of those types over the reload ----------
    final s2 = await _open(dataDir, deviceDir);
    expect(await s2.handle("Sarah's nickname is Sar"),
        isNot(contains("couldn't"))); // set-alias updates the contact
    expect(await s2.handle("Sarah's birthday is on March 4"),
        isNot(contains("couldn't"))); // set-birthday updates contact_date
    expect(await s2.handle('mark buy milk as done'), contains('Marked'));
    expect(
        await s2.handle('change my goal to 30k'), isNot(contains("couldn't")));
    expect(await s2.handle('mark the reminder to water plants as done'),
        isNot(contains("couldn't")));
    for (final (typeId, field, value) in [
      ('contact_fact', 'fact', 'loves tulips and dahlias'),
      ('project', 'notes', 'phase two'),
      ('area', 'notes', 'daily check'),
    ]) {
      final result = await s2.editField(_idOf(s2, typeId), field, value);
      expect(result.ok, isTrue,
          reason:
              'post-restart update of $typeId must succeed: ${result.message}');
    }

    await _drainUndo(s2);
    // Everything voice-created is gone; the externally seeded records remain,
    // restored to their pre-edit state by their editField undos.
    final leftover = s2.store.values.map((r) => r['typeId']).toList()..sort();
    expect(leftover, ['area', 'project']);
    expect(s2.store['project-1']!.containsKey('notes'), isFalse);
    expect(s2.store['area-1']!.containsKey('notes'), isFalse);
    await s2.dispose();
  });

  test('log & routine types survive restart: update + pre-restart undo',
      () async {
    final (dataDir, deviceDir) = _dirs('logs');

    // ---- Session 1: journal/meal/mood/workout/interaction/routine(+steps) ----
    final s1 = await _open(dataDir, deviceDir);
    expect(await s1.handle('journal that today was a good day'),
        contains('journal'));
    expect(await s1.handle('i had pasta for lunch'),
        isNot(contains("didn't catch")));
    expect(await s1.handle('log my mood as great'),
        isNot(contains("didn't catch")));
    expect(await s1.handle('log a 3k run'), isNot(contains("didn't catch")));
    expect(await s1.handle('talked to Sarah about the garden'),
        isNot(contains("didn't catch"))); // contact + interaction
    expect(await s1.handle('create a stretching routine for my low back'),
        contains('Restart loosener')); // routine + routine_step records
    await s1.pendingFigureFill; // declined figures — completes without writes
    await s1.dispose();

    // ---- Session 2: update every one of those types over the reload ----------
    final s2 = await _open(dataDir, deviceDir);
    for (final (typeId, field, value) in [
      ('journal_entry', 'entry', 'today was a great day'),
      ('meal', 'food', 'pasta and salad'),
      ('mood', 'note', 'sunny'),
      ('workout', 'distance', 5),
      ('interaction', 'note', 'the garden plan'),
      ('routine_step', 'instruction', 'ease into it slowly'),
    ]) {
      final result = await s2.editField(_idOf(s2, typeId), field, value);
      expect(result.ok, isTrue,
          reason:
              'post-restart update of $typeId must succeed: ${result.message}');
    }

    await _drainUndo(s2);
    expect(s2.store, isEmpty,
        reason: 'undoing the full history must reverse every record');
    await s2.dispose();
  });
}
