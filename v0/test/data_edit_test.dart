/// The manual "Your data" facade (Spec 07 §5.5 tap-to-edit + the Learned phrases showcase, G-49).
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

    test('editField coerces a boolean field (B4)', () async {
      final s = await _s();
      await s.handle('add toggle me to my list');
      final id = _taskId(s, 'toggle me');
      final r = await s.editField(id, 'completed', 'true');
      expect(r.ok, isTrue);
      expect(s.store[id]!['completed'], isTrue); // a real bool, not the string "true"
    });

    test('editField stores a date value (picker ISO passthrough, B4)', () async {
      final s = await _s();
      await s.handle('remember that Sarah loves hiking'); // creates a contact
      final c = s.store.values.firstWhere((r) => r['typeId'] == 'contact');
      final r = await s.editField(c['id'] as String, 'birthday', '1990-04-12');
      expect(r.ok, isTrue);
      expect(s.store[c['id']]!['birthday'], '1990-04-12');
    });

    test('a manual edit is NOT reversed by a following voice correction (review #2)', () async {
      final s = await _s();
      await s.handle('log a 3k run'); // a voice write (workout)
      await s.handle('add buy milk to my list');
      final id = _taskId(s, 'buy milk');
      await s.editField(id, 'description', 'buy oat milk'); // manual edit — supersedes "the last turn"
      await s.handle('no, I meant buy bread'); // a voice correction
      expect(s.store[id]!['description'], 'buy oat milk'); // the manual edit survived — not reversed
    });

    test('targeted undo (undoById) reverses the delete even after a later write (review #4)', () async {
      final s = await _s();
      await s.handle('add doomed to my list');
      final id = _taskId(s, 'doomed');
      final del = await s.deleteRecord(id);
      expect(del.undoId, isNotNull);
      await s.handle('add another to my list'); // a later write lands on the ring
      final msg = await s.undoById(del.undoId!);
      expect(msg.toLowerCase(), contains('undone'));
      expect(s.store.containsKey(id), isTrue); // the DELETE was reversed, not the later add
      expect(s.store.values.any((r) => r['description'] == 'another'), isTrue); // later add survived
    });

    test('undoById is an honest no-op once the entry rolled off', () async {
      final s = await _s();
      await s.handle('add x to my list');
      final del = await s.deleteRecord(_taskId(s, 'x'));
      await s.undoById(del.undoId!); // consume it
      final again = await s.undoById(del.undoId!); // already gone
      expect(again.toLowerCase(), contains('no longer undoable'));
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

    test('forget -> restore of a GENERATIVE-kind learned flow round-trips (B6)', () async {
      final s = await _s();
      const tmpl = 'ideas for a present for {contact:entity}';
      s.router.restore({'generativeKind': 'gift_ideas', 'template': tmpl});
      s.repo.appendCorpusLearned({'generativeKind': 'gift_ideas', 'template': tmpl});
      final flow = s.learnedFlows.firstWhere((f) => f.template == tmpl);
      expect(flow.isGenerative, isTrue);
      expect(flow.targetLabel, 'Gift ideas'); // humanized generativeKind, not a skillId
      final token = s.forgetLearnedFlow(tmpl);
      expect(token, isNotNull);
      expect(token!['generativeKind'], 'gift_ideas'); // token preserves the generative shape
      expect(s.learnedFlows.any((f) => f.template == tmpl), isFalse);
      s.restoreLearnedFlow(token);
      expect(s.learnedFlows.any((f) => f.template == tmpl && f.isGenerative), isTrue);
    });

    test('double restore does not duplicate a learned flow (review #13)', () async {
      final s = await _s();
      s.router.addLearned('list-tasks', 'show my todos');
      s.repo.appendCorpusLearned({'skillId': 'list-tasks', 'template': 'show my todos'});
      final token = s.forgetLearnedFlow('show my todos')!;
      s.restoreLearnedFlow(token);
      s.restoreLearnedFlow(token); // second restore must be a no-op, not a duplicate
      expect(s.learnedFlows.where((f) => f.template == 'show my todos').length, 1);
    });
  });
}
