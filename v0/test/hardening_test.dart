/// Regression tests for the Fable-review wave-1 fixes: authoring can't clobber
/// built-ins or traverse the filesystem, malformed/throwing cloud output can't
/// crash the turn, and a leaked "none" slot no longer RangeErrors.
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');

/// Cloud stub returning a scripted authoring response (or throwing), and an
/// optional scripted residual route (to inject a leaked-"none" slot deterministically).
class _ScriptCloud implements CloudClient {
  final Map<String, dynamic>? authorResult;
  final Map<String, dynamic>? routeResult;
  final bool throwOnAuthor;
  _ScriptCloud({this.authorResult, this.routeResult, this.throwOnAuthor = false});
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s) async =>
      CloudOk(routeResult);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async {
    if (throwOnAuthor) throw StateError('boom');
    return CloudOk(authorResult);
  }
  @override
  Future<CloudResult<String>> generate(String kind, String context) async => const CloudError(CloudErrorKind.noKey);
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
          {'op': 'format', 'template': 'Logged {value}.', 'into': 'confirmationText'},
        ]}
      },
    };

void main() {
  group('authoring hardening (Fable review)', () {
    test('a valid authored capability previews, then activates and registers (§6.5)', () async {
      final s = await _session(_ScriptCloud(authorResult: _authored('water_intake', 'log_water')));
      final preview = await s.handle('start tracking my pushups');
      expect(preview.toLowerCase(), contains('activate'));
      expect(s.types.containsKey('water_intake'), isFalse, reason: 'nothing registered until activate');
      expect(s.skills.containsKey('log_water'), isFalse);
      expect((await s.handle('activate')).toLowerCase(), contains('added'));
      expect(s.types.containsKey('water_intake'), isTrue);
      expect(s.skills.containsKey('log_water'), isTrue);
    });
    test('a previewed capability can be declined with "never mind" (nothing registered)', () async {
      final s = await _session(_ScriptCloud(authorResult: _authored('water_intake', 'log_water')));
      expect((await s.handle('start tracking my pushups')).toLowerCase(), contains('activate'));
      expect((await s.handle('never mind')).toLowerCase(), contains("won't add"));
      expect(s.types.containsKey('water_intake'), isFalse);
      expect(s.skills.containsKey('log_water'), isFalse);
    });
    test('moving on without activating drops the draft and handles the new input', () async {
      final s = await _session(_ScriptCloud(authorResult: _authored('water_intake', 'log_water')));
      expect((await s.handle('start tracking my pushups')).toLowerCase(), contains('activate'));
      expect(await s.handle('add buy milk to my list'), contains('buy milk')); // handled normally
      expect(s.types.containsKey('water_intake'), isFalse); // draft dropped, never registered
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

  group('record integrity — refuses fabricating the past (DP-05, principle #7)', () {
    for (final u in const [
      'pretend that I called mom yesterday',
      'add a fake interaction with Sam',
      'make it look like I went to the gym',
      'fabricate a meeting with my boss',
      'log a fake call with the dentist',
    ]) {
      test('refuses: "$u"', () async {
        final s = await _session(_ScriptCloud()); // never reaches cloud
        final r = await s.handle(u);
        expect(r.toLowerCase(), contains("didn't happen"));
        expect(s.store.isEmpty, isTrue, reason: 'a refused fabrication must not write');
      });
    }
    test('a genuine (even backdated) log is NOT treated as fabrication', () async {
      final s = await _session(_ScriptCloud());
      final r = await s.handle('i talked to Sam about the project');
      expect(r.toLowerCase(), isNot(contains("didn't happen")));
    });
  });

  group('safety floor keys on framing, not topic (Fable review)', () {
    // must BLOCK (harmful framing) — the floor fires before any cloud call
    for (final u in const [
      'start tracking my wife secretly',
      'track my kid without their knowledge',
      'i want to track my husband behind his back',
      'make me a way to spy on my coworker',
      'create a tracker to hide my eating',
      // the two canonical §7.6 examples — reached the gate only after widening the
      // "build me a …" authoring trigger (they silently bypassed it before)
      "build me a tracker that logs my partner's location without them knowing",
      'build me a tracker that warns me when i eat over 600 calories so i can cut down harder',
    ]) {
      test('blocks: "$u"', () async {
        final s = await _session(_ScriptCloud()); // cloud is never reached
        expect(await s.handle(u), contains("won't create tools"));
      });
    }
    // a tracker the app ALREADY ships routes to it for free — never to paid authoring
    test('"start tracking my runs" points to the built-in, no cloud call', () async {
      final s = await _session(_ScriptCloud());
      final r = await s.handle('start tracking my runs');
      expect(r.toLowerCase(), contains('already'));
      expect(r, contains('log a 3k run'));
    });
    test('a third-party tracker ("my daughter\'s mood") still goes to authoring', () async {
      final s = await _session(_ScriptCloud()); // author returns null -> "couldn't build"
      final r = await s.handle("start tracking my daughter's mood");
      expect(r.toLowerCase(), isNot(contains('already'))); // not short-circuited as a built-in
    });
    // must NOT block (benign, merely-sensitive topic) — the flagship parenting use
    for (final u in const [
      "start tracking my daughter's mood",
      "track my kid's reading progress",
      'i want to track time spent with my kids',
      'track my own weight',
    ]) {
      test('allows: "$u"', () async {
        final s = await _session(_ScriptCloud()); // returns null -> "couldn't build", not a refusal
        expect(await s.handle(u), isNot(contains("won't create tools")));
      });
    }
  });

  group('cloud slot sanitization — the committed "none" crash', () {
    test('a leaked "none" dueDate no longer crashes the turn', () async {
      // A cloud route that leaks the literal "none" for the absent date — the exact
      // shape Haiku once emitted. Injected deterministically (not via the recorded
      // cassette, whose model outputs shift on re-record) so this guards the
      // sanitization in Session, not a lucky fixture.
      final s = await _session(_ScriptCloud(routeResult: {
        'skillId': 'create-task',
        'slots': <String, dynamic>{'description': 'call the dentist', 'dueDate': 'none'},
        'source': 'cloud',
      }));
      final r = await s.handle("don't let me forget to call the dentist");
      expect(r, contains('call the dentist'));
      final tasks = s.store.values.where((x) => x['typeId'] == 'task').toList();
      expect(tasks.length, 1);
      expect(tasks.single['dueAt'], isNull); // normalized, not the string "none"
    });
  });
}
