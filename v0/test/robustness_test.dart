/// Robustness / adversarial inputs — the router, interpreter, and Session must
/// never crash or mis-interpolate on empty, whitespace, unicode, huge, or
/// injection-shaped input. Offline.
import 'package:plenara/claude.dart';
import 'package:plenara/interpreter.dart';
import 'package:plenara/router.dart';
import 'package:plenara/session.dart';
import 'package:plenara/store.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');
final _router = Router.load('data/corpus.json', _now);
final _types = loadDefs('data/types', 'typeId');
final _skills = loadDefs('data/skills', 'skillId');

/// The cloud always abstains (Ok(null)). Adversarial input then degrades to clarify
/// rather than throwing. (A true offline/error path is covered in claude_test.)
class _NullCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      const CloudOk(null);
}

Future<Session> _session() async {
  final s = Session(makeTempDataDir(), clock: _now, cloud: _NullCloud());
  await s.init(retrieval: false);
  return s;
}

void main() {
  group('router never crashes on adversarial input', () {
    final weird = [
      '', '   ', '\t\n', '!!!', '???', '.....', 'add', 'remind', 'log a',
      'to my list', 'due thursday', '{var}', '{{}}', r'$(rm -rf /)', '"; DROP TABLE',
      'a' * 5000, '😀🎉🔥', 'ADD BUY MILK TO MY LIST', '   add   x   to my   list   ',
    ];
    for (final u in weird) {
      final label = u.length > 20 ? '${u.substring(0, 20)}…(${u.length})' : u;
      test('route("$label") returns without throwing', () {
        expect(() => _router.route(u), returnsNormally);
        final r = _router.route(u);
        expect(r == null || r['skillId'] is String, isTrue);
      });
    }
  });

  group('unicode & odd content preserved in slots', () {
    test('accented task description', () {
      expect(_router.route('add café à la maison to my list')?['slots']['description'], 'café à la maison');
    });
    test('emoji task description', () {
      expect(_router.route('add 🎉 plan the party to my list')?['slots']['description'], '🎉 plan the party');
    });
    test('unicode person name in recall', () {
      expect(_router.route('what do i know about 李明')?['slots']['personName'], '李明');
    });
    test('extra internal whitespace collapses on trim boundaries', () {
      expect(_router.route('add    buy   bread    to my list')?['slots']['description'], 'buy   bread');
    });
  });

  group('format is not a template-injection vector', () {
    test('a slot value containing {placeholders} is NOT re-interpolated', () {
      final store = <String, Map<String, dynamic>>{};
      final i = Interpreter(_types, _now);
      // user input carries a brace-expression; it must appear literally in output
      final plan = i.resolve(_skills['create-task']!, {'description': '{total} and {n}'}, store);
      i.execute(plan, store);
      expect(plan.confirmation, 'Added "{total} and {n}" to your tasks.');
      expect(store.values.single['description'], '{total} and {n}');
    });
    test('a slot value with quotes/backslashes is stored verbatim', () {
      final store = <String, Map<String, dynamic>>{};
      final i = Interpreter(_types, _now);
      final plan = i.resolve(_skills['create-task']!, {'description': r'say "hi" \ bye'}, store);
      i.execute(plan, store);
      expect(store.values.single['description'], r'say "hi" \ bye');
      expect(plan.confirmation, contains(r'say "hi" \ bye'));
    });
  });

  group('Session degrades gracefully (offline) on adversarial input', () {
    for (final u in ['', '   ', '!!!', 'asdkfjhaskdjfh', '😀', r'$(whoami)', 'a' * 3000]) {
      final label = u.length > 15 ? '${u.substring(0, 15)}…' : (u.isEmpty ? '<empty>' : u);
      test('handle("$label") does not throw and writes nothing', () async {
        final s = await _session();
        late String resp;
        expect(() async => resp = await s.handle(u), returnsNormally);
        resp = await s.handle(u);
        expect(s.store, isEmpty, reason: 'adversarial input must not write');
        expect(resp, isNotEmpty);
      });
    }
    test('a huge valid utterance still routes and writes exactly one record', () async {
      final s = await _session();
      final desc = 'buy ${'x' * 2000}';
      await s.handle('add $desc to my list');
      expect(s.store.length, 1);
      expect(s.store.values.single['description'], desc);
    });
  });
}
