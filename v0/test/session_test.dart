/// End-to-end turn engine (Session) over the OFFLINE corpus paths + system
/// commands + cross-skill integration. A _NoCloud client throws if the cloud is
/// hit, proving these flows are fully deterministic (no network). Cloud paths are
/// covered separately in cloud_test.dart via the replay cassette.
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');

class _NoCloud implements CloudClient {
  @override
  Future<Map<String, dynamic>?> routeResidual(
          String utterance, Map<String, Map<String, dynamic>> skills) async =>
      throw StateError('cloud routeResidual called for "$utterance" — expected a corpus/offline path');
  @override
  Future<Map<String, dynamic>?> authorCapability(String description, {String? priorError}) async =>
      throw StateError('cloud authorCapability called — expected a corpus/offline path');
}

Future<Session> _session([String? dir]) async {
  final s = Session(dir ?? makeTempDataDir(), clock: _now, cloud: _NoCloud());
  await s.init(retrieval: false);
  return s;
}

void main() {
  group('hero-example turns route + describe (offline corpus)', () {
    final cases = <String, String>{
      'add call the plumber to my to-do list': 'call the plumber',
      'remind me to buy milk': 'buy milk',
      'remind me to email the accountant on thursday': 'due Thursday',
      'add wash the car to my list due tomorrow': 'due Tuesday',
      'log a 5k run': '5 km run',
      'i ran 8k': '8 km run',
      'log a run': 'Logged a run',
      "i'm feeling great": 'mood as great',
      'log my mood as anxious': 'mood as anxious',
      'note that Mia loves drawing': 'Noted that Mia loves drawing',
      'list my tasks': '0 task',
      'how many runs this week': 'so far this week',
    };
    cases.forEach((utterance, expected) {
      test('"$utterance" -> contains "$expected"', () async {
        final s = await _session();
        expect(await s.handle(utterance), contains(expected));
      });
    });
  });

  group('cross-skill integration: write -> read', () {
    test('log a run, then the weekly count reflects it', () async {
      final s = await _session();
      await s.handle('log a 3k run');
      expect(await s.handle('how many runs this week'), contains("You've run 3 km"));
    });
    test('log two runs, count sums them', () async {
      final s = await _session();
      await s.handle('log a 3k run');
      await s.handle('i ran 4k');
      expect(await s.handle('how far have i run this week'), contains("You've run 7 km"));
    });
    test('remember a fact, then recall it', () async {
      final s = await _session();
      await s.handle('note that Mia loves drawing');
      final r = await s.handle('what do i know about Mia');
      expect(r, contains("Here's what I know about Mia"));
      expect(r, contains('loves drawing'));
    });
    test('add tasks, then list them', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      await s.handle('add walk the dog to my list');
      final r = await s.handle('list my tasks');
      expect(r, contains('2 task(s)'));
      expect(r, contains('buy milk'));
      expect(r, contains('walk the dog'));
    });
    test('relational remember creates the graph, recall reads the fact', () async {
      final s = await _session();
      final r = await s.handle("remember that Mia is allergic to peanuts and she is Sarah Mitchell's daughter");
      expect(r, contains('Noted that Mia'));
      // contact(Mia) + fact + contact(Sarah) + relationship = 4 records
      expect(s.store.length, 4);
      expect(await s.handle('what do i know about Mia'), contains('allergic to peanuts'));
    });
  });

  group('system commands: undo + correction', () {
    test('undo reverses the last write', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      expect(s.store.length, 1);
      expect(await s.handle('undo that'), contains('Undone'));
      expect(s.store.length, 0);
    });
    test('undo with nothing to undo', () async {
      final s = await _session();
      expect(await s.handle('undo'), contains('Nothing to undo'));
    });
    test('undo says what it reversed (transparent safety net)', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      final r = await s.handle('undo that');
      expect(r, contains('Undone'));
      expect(r, contains('buy milk')); // not a bare "Undone."
    });
    test('undo targets the last WRITE, skipping a read-only query', () async {
      final s = await _session();
      await s.handle('add buy milk to my list'); // write
      await s.handle('list my tasks'); // read-only, no before-images
      await s.handle('undo that');
      expect(s.store.length, 0);
    });
    test('correction "no, I meant to X" undoes then redoes', () async {
      final s = await _session();
      await s.handle('log a 5k run');
      final r = await s.handle('no, I meant to add buy running shoes to my list');
      expect(r, contains('buy running shoes'));
      expect(s.store.values.where((r) => r['typeId'] == 'workout'), isEmpty);
      expect(s.store.values.where((r) => r['typeId'] == 'task').length, 1);
    });
    test('mark a task done (update), then undo restores it as not-done', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      expect(await s.handle('mark buy milk as done'), contains('done'));
      expect(s.store.values.firstWhere((r) => r['typeId'] == 'task')['completed'], true);
      await s.handle('undo that');
      expect(s.store.values.firstWhere((r) => r['typeId'] == 'task')['completed'], false);
    });
    test('delete a task, then undo restores it', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      expect(await s.handle('delete buy milk from my list'), contains('Deleted'));
      expect(s.store.values.where((r) => r['typeId'] == 'task'), isEmpty);
      await s.handle('undo that');
      expect(s.store.values.where((r) => r['typeId'] == 'task').length, 1);
    });
    test('scratch that / take that back also undo', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      expect(await s.handle('scratch that'), contains('Undone'));
      expect(s.store.length, 0);
    });
  });

  group('persistence across Session instances (same data dir)', () {
    test('a written record is loaded by a fresh Session on the same dir', () async {
      final dir = makeTempDataDir();
      final s1 = await _session(dir);
      await s1.handle('add buy milk to my list');
      final s2 = await _session(dir); // fresh instance, same folder
      expect(await s2.handle('list my tasks'), contains('buy milk'));
    });
    test('undo persists (deleted file does not reappear)', () async {
      final dir = makeTempDataDir();
      final s1 = await _session(dir);
      await s1.handle('add buy milk to my list');
      await s1.handle('undo that');
      final s2 = await _session(dir);
      expect(await s2.handle('list my tasks'), contains('0 task(s)'));
    });
  });

  group('multi-turn story (the full offline pipeline)', () {
    test('a realistic sequence keeps consistent state', () async {
      final s = await _session();
      expect(await s.handle('add call the plumber to my to-do list'), contains('call the plumber'));
      expect(await s.handle('add buy milk to my list'), contains('buy milk'));
      expect(await s.handle('list my tasks'), contains('2 task(s)'));
      expect(await s.handle('undo that'), contains('Undone')); // undoes the last add (buy milk)
      expect(await s.handle('list my tasks'), contains('1 task(s)'));
      await s.handle('log a 6k run');
      expect(await s.handle('how many runs this week'), contains("You've run 6 km"));
      await s.handle('note that Tom fixed the sink');
      expect(await s.handle('tell me about Tom'), contains('fixed the sink'));
    });
  });
}
