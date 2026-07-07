/// Regression tests for the Fable-review wave-1 fixes: authoring can't clobber
/// built-ins or traverse the filesystem, malformed/throwing cloud output can't
/// crash the turn, and a leaked "none" slot no longer RangeErrors.
import 'package:plenara/claude.dart';
import 'package:plenara/replay_cloud.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');

/// Cloud stub returning a scripted authoring response (or throwing).
class _ScriptCloud implements CloudClient {
  final Map<String, dynamic>? authorResult;
  final bool throwOnAuthor;
  _ScriptCloud({this.authorResult, this.throwOnAuthor = false});
  @override
  Future<Map<String, dynamic>?> routeResidual(String u, Map<String, Map<String, dynamic>> s) async => null;
  @override
  Future<Map<String, dynamic>?> authorCapability(String d, {String? priorError}) async {
    if (throwOnAuthor) throw StateError('boom');
    return authorResult;
  }
}

Future<Session> _session(CloudClient cloud) async {
  final s = Session(makeTempDataDir(), clock: _now, cloud: cloud);
  await s.init(retrieval: false);
  return s;
}

Map<String, dynamic> _authored(String typeId, String skillId) => {
      'type': {
        'typeId': typeId,
        'displayName': 'X',
        'attributes': [
          {'name': 'value', 'valueType': 'text', 'required': true},
          {'name': 'loggedAt', 'valueType': 'date', 'required': true},
        ]
      },
      'skill': {
        'skillId': skillId,
        'displayName': 'Log X',
        'inputs': [{'name': 'value', 'required': true}],
        'examplePhrases': ['log x'],
        'steps': {'main': [
          {'op': 'compute', 'fn': 'today', 'into': 't'},
          {'op': 'write_record', 'typeId': typeId, 'fields': {'value': {'var': 'value'}, 'loggedAt': {'var': 't'}}, 'into': 'r'},
          {'op': 'format', 'template': 'Logged {value}.', 'into': 'confirmation'},
        ]}
      },
    };

void main() {
  group('authoring hardening (Fable review)', () {
    test('a valid authored capability registers and works', () async {
      final s = await _session(_ScriptCloud(authorResult: _authored('water_intake', 'log_water')));
      expect(await s.handle('start tracking my water intake'), contains('Built'));
      expect(s.types.containsKey('water_intake'), isTrue);
      expect(s.skills.containsKey('log_water'), isTrue);
    });

    test('a colliding typeId cannot clobber or delete a built-in type', () async {
      final s = await _session(_ScriptCloud(authorResult: _authored('task', 'log_task_thing')));
      final before = s.types['task'];
      final r = await s.handle('start tracking my task thing');
      expect(r, isNot(contains('Built')));
      expect(s.types['task'], same(before)); // built-in intact — not overwritten or removed on rollback
      expect(await s.handle('add buy milk to my list'), contains('buy milk')); // still works
    });

    test('a path-traversal / bad-charset id is rejected, nothing registered', () async {
      final s = await _session(_ScriptCloud(authorResult: _authored('../evil', 'log_evil')));
      final r = await s.handle('start tracking my evil thing');
      expect(r, contains('could not be validated'));
      expect(s.types.containsKey('../evil'), isFalse);
    });

    test('a malformed authoring shape degrades gracefully (no crash)', () async {
      final s = await _session(_ScriptCloud(authorResult: {'type': 'not a map', 'skill': 42}));
      expect(await s.handle('start tracking my something'), contains('could not be validated'));
    });

    test('a throwing cloud is caught by the boundary (no exception escapes)', () async {
      final s = await _session(_ScriptCloud(throwOnAuthor: true));
      expect(await s.handle('start tracking my whatever'), contains('something went wrong'));
    });
  });

  group('cloud slot sanitization — the committed "none" crash', () {
    test('a leaked "none" dueDate no longer crashes the turn', () async {
      final s = Session(makeTempDataDir(), clock: _now, cloud: ReplayCloud.load('test/fixtures/cloud.json'));
      await s.init(retrieval: false);
      // this fixture recorded dueDate:"none"; pre-fix it RangeError'd out of handle
      final r = await s.handle("don't let me forget to call the dentist");
      expect(r, contains('call the dentist'));
      final tasks = s.store.values.where((x) => x['typeId'] == 'task').toList();
      expect(tasks.length, 1);
      expect(tasks.single['dueAt'], isNull); // normalized, not the string "none"
    });
  });
}
