/// Authoring clarity (Luis, dogfooding build 15): he asked for a stretching routine, was asked to
/// approve a paid build, said yes — and got a tracker that logs stretches. His words: "after
/// conferring with haiku it doesn't seem like anything really happened, since logging things is a
/// core skill anyway."
///
/// Two changes come out of that:
///  1. After a capability is activated, SAY WHAT CHANGED in concrete terms and CHECK. "Added X.
///     Try: …" was technically true and practically useless. A "no" now removes it.
///  2. The pre-spend confirm is a PREFERENCE, off by default. Asking every time is friction —
///     the user already said what they wanted.
library;

import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');

/// Returns a valid, minimal authored capability so the whole activate path can run offline.
class _AuthoringCloud implements CloudClient {
  int authorCalls = 0;
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async {
    authorCalls++;
    return const CloudOk({
      'type': {
        'typeId': 'stretch_log',
        'displayName': 'Stretch',
        'attributes': [
          {'name': 'note', 'valueType': 'text', 'required': true},
          {'name': 'loggedAt', 'valueType': 'date', 'required': true},
        ],
      },
      'skill': {
        'skillId': 'log-stretch',
        'displayName': 'Log a stretch',
        'reads': <String>[],
        'writes': ['stretch_log'],
        'inputs': [
          {'name': 'note', 'required': true},
        ],
        'examplePhrases': ['log a stretch'],
        'steps': {
          'main': [
            {'op': 'compute', 'fn': 'today', 'args': <dynamic>[], 'into': 'today'},
            {
              'op': 'write_record',
              'typeId': 'stretch_log',
              'into': 'w',
              'fields': {
                'note': {'var': 'note'},
                'loggedAt': {'var': 'today'},
              },
            },
            {'op': 'format', 'template': 'Logged it.', 'into': 'confirmationText'},
          ],
        },
      },
    });
  }

  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s,
          {Set<String> knownContacts = const {}}) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<String>> generate(String k, String c) async => const CloudError(CloudErrorKind.noKey);
}

Future<Session> _s({bool confirmSpend = false}) async {
  final s = Session(makeTempDataDir(), clock: _now, cloud: _AuthoringCloud());
  await s.init(retrieval: false);
  s.confirmCloudSpend = confirmSpend;
  return s;
}

void main() {
  group('the paid confirm is a preference, not a rule', () {
    test('by default it just builds — no "want me to go ahead?" round trip', () async {
      final s = await _s();
      final out = await s.handle('start tracking my stretching');
      expect(out.toLowerCase(), isNot(contains('want me to go ahead')));
      expect((s.claude as _AuthoringCloud).authorCalls, 1);
    });

    test('with the pref ON it asks first, and spends NOTHING until yes', () async {
      final s = await _s(confirmSpend: true);
      final ask = await s.handle('start tracking my stretching');
      expect(ask.toLowerCase(), contains('want me to go ahead'));
      expect((s.claude as _AuthoringCloud).authorCalls, 0, reason: 'the ask must precede the spend');
      await s.handle('yes');
      expect((s.claude as _AuthoringCloud).authorCalls, 1);
    });

    test('declining the ask builds nothing and spends nothing', () async {
      final s = await _s(confirmSpend: true);
      await s.handle('start tracking my stretching');
      final out = await s.handle('never mind');
      expect(out.toLowerCase(), contains("won't build"));
      expect((s.claude as _AuthoringCloud).authorCalls, 0);
    });
  });

  group('activation says what actually changed, then checks', () {
    Future<Session> activated() async {
      final s = await _s();
      await s.handle('start tracking my stretching'); // -> preview
      await s.handle('activate'); // -> learned + the check question
      return s;
    }

    test('the confirmation names the phrase that now works and what it records', () async {
      final s = await _s();
      await s.handle('start tracking my stretching');
      final out = await s.handle('activate');
      expect(out, contains('log a stretch'), reason: 'the phrase that now works');
      expect(out, contains('note'), reason: 'what it will record');
      expect(out.toLowerCase(), contains('is that what you wanted'));
    });

    test('"no" REMOVES the capability — a wrong build is reversible in one word', () async {
      final s = await activated();
      expect(s.skills.containsKey('log-stretch'), isTrue);
      final out = await s.handle('no');
      expect(out.toLowerCase(), contains('forgotten'));
      expect(s.skills.containsKey('log-stretch'), isFalse);
      expect(s.types.containsKey('stretch_log'), isFalse);
      expect(out.toLowerCase(), contains('tell me again'), reason: 'invite a better description');
    });

    test('"yes" keeps it and the capability really works', () async {
      final s = await activated();
      expect(await s.handle('yes'), contains('yours'));
      expect(s.skills.containsKey('log-stretch'), isTrue);
      // The example phrase now routes OFFLINE (activation teaches it to the corpus). It asks for
      // the required slot, which is the normal ProvideSlot flow — not a failure.
      final asked = await s.handle('log a stretch');
      expect(asked, contains('note'), reason: 'routed, and asking for its required input');
      final logged = await s.handle('hamstrings, 2 minutes');
      expect(logged, contains('Logged'));
      expect(s.store.values.where((r) => r['typeId'] == 'stretch_log').length, 1);
    });

    test('moving on without answering KEEPS it — silence is not a rejection', () async {
      final s = await activated();
      final out = await s.handle('add buy milk to my list');
      expect(out, contains('buy milk'), reason: 'the unrelated command still runs');
      expect(s.skills.containsKey('log-stretch'), isTrue);
    });

    test('a forgotten capability leaves no ROUTING behind either', () async {
      // Activation teaches the example phrases to the corpus. If forgetting doesn't unteach them,
      // the phrase still routes — to a skill that no longer exists.
      final s = await activated();
      await s.handle('no');
      final out = await s.handle('log a stretch');
      expect(out.toLowerCase(), isNot(contains('went wrong')), reason: 'must not crash the turn');
      expect(s.router.route('log a stretch'), isNull,
          reason: 'the learned template must be unlearned with the capability');
    });

    test('a forgotten capability leaves no definition files behind', () async {
      final s = await activated();
      await s.handle('no');
      // a fresh Session over the same folder must not resurrect it
      final s2 = Session(s.dataDir, clock: _now, cloud: _AuthoringCloud());
      await s2.init(retrieval: false);
      expect(s2.skills.containsKey('log-stretch'), isFalse);
      expect(s2.types.containsKey('stretch_log'), isFalse);
    });
  });
}
