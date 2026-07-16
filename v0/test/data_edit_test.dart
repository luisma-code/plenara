/// The manual "Your data" facade (Spec 07 §5.5 tap-to-edit + the Learned phrases showcase, G-47).
/// Edits/deletes ride the same journal as spoken writes, so voice "undo that" reverses them; the
/// learned-flow forget/restore is symmetrical with the voice-side forget-on-correct. Real storage.
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');

class _NoCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s,
          {Set<String> knownContacts = const {}}) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<String>> generate(String k, String c) async => const CloudError(CloudErrorKind.noKey);
}

Future<Session> _s() async {
  final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud());
  await s.init(retrieval: false);
  return s;
}

String _taskId(Session s, String desc) =>
    s.store.values.firstWhere((r) => r['typeId'] == 'task' && r['description'] == desc)['id'] as String;

void main() {
  group('editable data view — facade', () {
    test('editField updates a value, validated, and voice undo reverses it', () async {
      final s = await _s();
      await s.handle('add buy milk to my list');
      final id = _taskId(s, 'buy milk');
      final r = await s.editField(id, 'description', 'buy oat milk');
      expect(r.ok, isTrue);
      expect(s.store[id]!['description'], 'buy oat milk');
      final undo = await s.handle('undo that'); // the SAME journal as a spoken write
      expect(undo.toLowerCase(), contains('undone'));
      expect(s.store[id]!['description'], 'buy milk');
    });

    test('editField coerces a decimal field and rejects non-numbers', () async {
      final s = await _s();
      await s.handle('log a 3k run'); // workout with a decimal distance
      final w = s.store.values.firstWhere((r) => r['typeId'] == 'workout');
      final bad = await s.editField(w['id'] as String, 'distance', 'not a number');
      expect(bad.ok, isFalse);
      expect(bad.message.toLowerCase(), contains('number'));
      final good = await s.editField(w['id'] as String, 'distance', '9');
      expect(good.ok, isTrue);
      expect(s.store[w['id']]!['distance'], 9);
    });

    test('editField refuses to empty a required field', () async {
      final s = await _s();
      await s.handle('add pay rent to my list');
      final id = _taskId(s, 'pay rent');
      final r = await s.editField(id, 'description', '   ');
      expect(r.ok, isFalse);
      expect(r.message.toLowerCase(), contains('required'));
      expect(s.store[id]!['description'], 'pay rent'); // unchanged
    });

    test('editField on a non-schema field is refused (no silent write)', () async {
      final s = await _s();
      await s.handle('add x to my list');
      final id = _taskId(s, 'x');
      final r = await s.editField(id, 'not_a_field', 'whatever');
      expect(r.ok, isFalse);
    });

    test('deleteRecord removes the record and undoLast restores it', () async {
      final s = await _s();
      await s.handle('add temporary to my list');
      final id = _taskId(s, 'temporary');
      final del = await s.deleteRecord(id);
      expect(del.ok, isTrue);
      expect(s.store.containsKey(id), isFalse);
      final undo = await s.undoLast();
      expect(undo.toLowerCase(), contains('undone'));
      expect(s.store.containsKey(id), isTrue);
    });

    test('editField on a vanished record fails gracefully', () async {
      final s = await _s();
      final r = await s.editField('task-does-not-exist', 'description', 'x');
      expect(r.ok, isFalse);
      expect(r.message.toLowerCase(), contains('no longer exists'));
    });
  });

  group('learned phrases — showcase + forget/restore', () {
    test('a learned template shows up as a LearnedFlow with a human target', () async {
      final s = await _s();
      // Learn a phrasing by teaching it a known way then repeating (offline learn path).
      s.router.addLearned('list-tasks', 'show my todo list');
      final flows = s.learnedFlows;
      expect(flows.any((f) => f.template == 'show my todo list'), isTrue);
      final f = flows.firstWhere((f) => f.template == 'show my todo list');
      expect(f.targetLabel, 'List your tasks'); // skill displayName, not the raw skillId
      expect(f.isGenerative, isFalse);
    });

    test('forgetLearnedFlow drops it; restoreLearnedFlow brings it back', () async {
      final s = await _s();
      s.router.addLearned('list-tasks', 'show my todo list');
      s.repo.appendCorpusLearned({'skillId': 'list-tasks', 'template': 'show my todo list'}); // persist
      final token = s.forgetLearnedFlow('show my todo list');
      expect(token, isNotNull);
      expect(s.learnedFlows.any((f) => f.template == 'show my todo list'), isFalse);
      s.restoreLearnedFlow(token!);
      expect(s.learnedFlows.any((f) => f.template == 'show my todo list'), isTrue);
    });

    test('forgetting a non-learned (seed) template returns null', () async {
      final s = await _s();
      final token = s.forgetLearnedFlow('this was never learned');
      expect(token, isNull);
    });
  });
}
