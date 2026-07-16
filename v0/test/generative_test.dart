/// GenerativeService (Spec 04 §3.10) — the grounded, paid synthesis path. A fake
/// generative cloud ECHOES the assembled context, so we can assert the prompt was
/// grounded in the user's real records (never invented) and that tier/connectivity
/// failures degrade honestly. The real model call lives behind the CloudClient seam.
import 'package:plenara/claude.dart';
import 'package:plenara/generative.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');

class _GenCloud implements CloudClient {
  final CloudErrorKind? err;
  String? lastKind, lastContext;
  int residualCalls = 0; // how many times the cloud residual was consulted (0 after a learned hit)
  _GenCloud({this.err});
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s, {Set<String> knownContacts = const {}}) async {
    residualCalls++;
    // Stand in for Haiku's G-46 generative recognition: a "suggest/gift … for <name>" phrasing the
    // frozen regex misses is classified as gift_ideas with the contact param (mirrors the real
    // {generativeKind, params} residual contract). Everything else abstains.
    final lc = u.toLowerCase();
    if (lc.contains('gift') && (lc.contains('suggest') || RegExp(r'gift ideas? for').hasMatch(lc))) {
      final m = RegExp(r'\bfor\s+([A-Za-z]+)', caseSensitive: false).firstMatch(u);
      return CloudOk<Map<String, dynamic>?>({
        'generativeKind': 'gift_ideas',
        'params': {'contact': m?.group(1)}, // null contact when no "for <name>" — exercises the follow-up
        'source': 'cloud',
      });
    }
    return const CloudOk(null); // abstain
  }
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<String>> generate(String kind, String context) async {
    lastKind = kind;
    lastContext = context;
    return err != null ? CloudError(err!) : CloudOk('Some ideas, grounded in:\n$context');
  }
}

Future<Session> _s(CloudClient c) async {
  final s = Session(makeTempDataDir(), clock: _now, cloud: c);
  await s.init(retrieval: false);
  return s;
}

void main() {
  group('gift ideas — grounded in the person\'s real facts', () {
    test('assembles the actual facts into the prompt (never invents)', () async {
      final cloud = _GenCloud();
      final s = await _s(cloud);
      await s.handle('remember that Sarah loves hiking');
      await s.handle('remember that Sarah is into pottery');
      final r = await s.handle('what should i get Sarah for her birthday');
      expect(cloud.lastKind, 'gift_ideas');
      expect(cloud.lastContext, contains('hiking'));
      expect(cloud.lastContext, contains('pottery'));
      expect(r, contains('hiking')); // surfaced back to the user
    });

    test('"gift ideas for X" phrasing also routes generative', () async {
      final cloud = _GenCloud();
      final s = await _s(cloud);
      await s.handle('remember that Sarah loves hiking');
      await s.handle('gift ideas for Sarah');
      expect(cloud.lastKind, 'gift_ideas');
      expect(cloud.lastContext, contains('hiking'));
    });

    test('"suggest a gift for X" the regex misses is recognized by the residual (G-46; dogfood 2026-07-15)', () async {
      // The frozen _giftRe does NOT match these; recognition comes from the cloud residual, and the
      // session dispatches the {generativeKind, params} route to giftIdeas.
      for (final phrase in [
        'can you suggest a gift for Sarah',
        'can you suggest some gifts for Sarah',
        'suggest a gift for Sarah',
      ]) {
        final cloud = _GenCloud();
        final s = await _s(cloud);
        await s.handle('remember that Sarah loves hiking');
        await s.handle(phrase);
        expect(cloud.lastKind, 'gift_ideas', reason: phrase);
        expect(cloud.lastContext, contains('hiking'), reason: phrase);
      }
    });

    test('a DELIVERED recognition is learned — the 2nd identical phrasing routes OFFLINE (G-46)', () async {
      final cloud = _GenCloud();
      final s = await _s(cloud);
      await s.handle('remember that Sarah loves hiking');
      await s.handle('can you suggest a gift for Sarah'); // residual recognizes, delivers, LEARNS
      final callsAfterFirst = cloud.residualCalls;
      expect(callsAfterFirst, greaterThan(0));
      cloud.lastKind = null;
      await s.handle('can you suggest a gift for Sarah'); // 2nd: the learned corpus template catches it
      expect(cloud.residualCalls, callsAfterFirst, reason: 'no NEW residual call — recognized offline');
      expect(cloud.lastKind, 'gift_ideas'); // still dispatched the synthesis
    });

    test('a DEGRADED generation is NOT learned — the 2nd phrasing still hits the residual (G-46)', () async {
      final cloud = _GenCloud(err: CloudErrorKind.offline); // the generate() call fails
      final s = await _s(cloud);
      await s.handle('remember that Sarah loves hiking');
      await s.handle('can you suggest a gift for Sarah'); // recognized, but generation degrades → no learn
      final callsAfterFirst = cloud.residualCalls;
      await s.handle('can you suggest a gift for Sarah');
      expect(cloud.residualCalls, greaterThan(callsAfterFirst), reason: 'not learned → re-consults the residual');
    });

    test('a learned recognition is FORGOTTEN on a next-turn correction (§5.2 negative half, G-46)', () async {
      final cloud = _GenCloud();
      final s = await _s(cloud);
      await s.handle('remember that Sarah loves hiking');
      await s.handle('can you suggest a gift for Sarah'); // learns
      await s.handle('no, I meant remember that Sarah is my sister'); // correct → forget the learned template
      final callsBefore = cloud.residualCalls;
      await s.handle('can you suggest a gift for Sarah'); // template gone → back to the residual
      expect(cloud.residualCalls, greaterThan(callsBefore), reason: 'forgotten → re-consults the residual');
    });

    test('a generative request with no contact asks (§6.3 follow-up), then the answer runs it (G-46)', () async {
      final cloud = _GenCloud();
      final s = await _s(cloud);
      await s.handle('remember that Sarah loves hiking');
      final ask = await s.handle('can you suggest a gift'); // no contact
      expect(ask.toLowerCase(), contains('whom'));
      expect(cloud.lastKind, isNull); // nothing generated yet
      final r = await s.handle('Sarah'); // the answer
      expect(cloud.lastKind, 'gift_ideas');
      expect(cloud.lastContext, contains('hiking'));
      expect(r, contains('hiking'));
    });

    test('unknown person -> asks to learn about them first, no cloud call', () async {
      final cloud = _GenCloud();
      final s = await _s(cloud);
      final r = await s.handle('gift ideas for Nobody');
      expect(r.toLowerCase(), contains("don't have"));
      expect(cloud.lastKind, isNull); // never spent a generative call
    });

    test('offline -> honest degrade (not a vague failure)', () async {
      final cloud = _GenCloud(err: CloudErrorKind.offline);
      final s = await _s(cloud);
      await s.handle('remember that Sarah loves hiking');
      expect((await s.handle('gift ideas for Sarah')).toLowerCase(), contains('offline'));
    });

    test('no key -> tier degrade names it a cloud feature', () async {
      final cloud = _GenCloud(err: CloudErrorKind.noKey);
      final s = await _s(cloud);
      await s.handle('remember that Sarah loves hiking');
      expect((await s.handle('gift ideas for Sarah')).toLowerCase(), contains('cloud feature'));
    });
  });

  group('reconnect coaching — grounded in facts + time since contact', () {
    test('assembles facts and last-contact into the prompt', () async {
      final cloud = _GenCloud();
      final s = await _s(cloud);
      await s.handle('remember that Sam loves jazz');
      await s.handle('i talked to Sam about the concert'); // logs an interaction
      final r = await s.handle('help me reconnect with Sam');
      expect(cloud.lastKind, 'reconnect');
      expect(cloud.lastContext, contains('jazz'));
      expect(cloud.lastContext, contains('Last time you logged talking'));
      expect(r, isNotEmpty);
    });
    test('"i\'ve lost touch with X" phrasing also routes reconnect', () async {
      final cloud = _GenCloud();
      final s = await _s(cloud);
      await s.handle('remember that Sam loves jazz');
      await s.handle("i've lost touch with Sam");
      expect(cloud.lastKind, 'reconnect');
    });
    test('offline -> honest degrade', () async {
      final cloud = _GenCloud(err: CloudErrorKind.offline);
      final s = await _s(cloud);
      await s.handle('remember that Sam loves jazz');
      expect((await s.handle('help me reconnect with Sam')).toLowerCase(), contains('offline'));
    });
  });

  group('daily briefing — grounded in what is actually on the plate', () {
    test('assembles open tasks into the briefing prompt', () async {
      final cloud = _GenCloud();
      final s = await _s(cloud);
      await s.handle('add buy milk to my list');
      final r = await s.handle('give me my briefing');
      expect(cloud.lastKind, 'briefing');
      expect(cloud.lastContext, contains('buy milk'));
      expect(r, isNotEmpty);
    });

    test('offline briefing degrades honestly', () async {
      final cloud = _GenCloud(err: CloudErrorKind.offline);
      final s = await _s(cloud);
      expect((await s.handle('brief me')).toLowerCase(), contains('offline'));
    });
  });

  // The three P-10/P-11/P-20 kinds are exercised on the service directly (their
  // session routes belong to session.dart) with the same fake cloud: assert the
  // prompt is grounded in the hand-built store and that thin-data/tier failures
  // degrade honestly.
  group('weekly review — grounded in the week\'s actual activity', () {
    test('assembles this week\'s workouts, moods, interactions, done tasks', () async {
      final cloud = _GenCloud();
      final g = GenerativeService(cloud);
      final store = _store([
        {'id': 'c1', 'typeId': 'contact', 'displayName': 'Sarah'},
        {'typeId': 'interaction', 'subject': 'c1', 'at': '2026-07-02', 'note': 'caught up about the trip'},
        {'typeId': 'workout', 'activity': 'run', 'distance': 5, 'date': '2026-07-03'},
        {'typeId': 'mood', 'rating': 'great', 'loggedAt': '2026-07-04'},
        {'typeId': 'task', 'description': 'buy milk', 'completed': true},
      ]);
      final r = await g.weeklyReview(store, _now);
      expect(cloud.lastKind, 'weekly_review');
      expect(cloud.lastContext, contains('run 5 km on 2026-07-03'));
      expect(cloud.lastContext, contains('great'));
      expect(cloud.lastContext, contains('Sarah on 2026-07-02 (caught up about the trip)'));
      expect(cloud.lastContext, contains('buy milk'));
      expect(r, isNotEmpty);
    });

    test('records older than the week stay OUT of the prompt', () async {
      final cloud = _GenCloud();
      final g = GenerativeService(cloud);
      final store = _store([
        {'typeId': 'workout', 'activity': 'run', 'distance': 10, 'date': '2026-06-01'}, // stale
        {'typeId': 'mood', 'rating': 'fine', 'loggedAt': '2026-07-05'},
      ]);
      await g.weeklyReview(store, _now);
      expect(cloud.lastContext, isNot(contains('2026-06-01')));
      expect(cloud.lastContext, contains('Workouts this week: none logged'));
      expect(cloud.lastContext, contains('fine'));
    });

    test('empty week -> honest local answer, no cloud call spent', () async {
      final cloud = _GenCloud();
      final g = GenerativeService(cloud);
      final r = await g.weeklyReview(_store([]), _now);
      expect(r.toLowerCase(), contains('nothing logged'));
      expect(cloud.lastKind, isNull);
    });

    test('offline -> honest degrade', () async {
      final cloud = _GenCloud(err: CloudErrorKind.offline);
      final g = GenerativeService(cloud);
      final store = _store([
        {'typeId': 'mood', 'rating': 'great', 'loggedAt': '2026-07-04'},
      ]);
      expect((await g.weeklyReview(store, _now)).toLowerCase(), contains('offline'));
    });
  });

  group('pattern insight — a cross-record pattern grounded in the data', () {
    test('assembles the mood and workout series into the prompt', () async {
      final cloud = _GenCloud();
      final g = GenerativeService(cloud);
      final store = _store([
        {'typeId': 'mood', 'rating': 'great', 'loggedAt': '2026-07-03'},
        {'typeId': 'mood', 'rating': 'meh', 'loggedAt': '2026-07-05'},
        {'typeId': 'workout', 'activity': 'run', 'distance': 5, 'date': '2026-07-03'},
      ]);
      await g.patternInsight(store, _now);
      expect(cloud.lastKind, 'pattern_insight');
      expect(cloud.lastContext, contains('2026-07-03: great'));
      expect(cloud.lastContext, contains('2026-07-05: meh'));
      expect(cloud.lastContext, contains('2026-07-03: run, 5 km'));
      expect(cloud.lastContext, contains('never invent one'));
    });

    test('only one tracker logged -> honest local answer, no cloud call', () async {
      final cloud = _GenCloud();
      final g = GenerativeService(cloud);
      final store = _store([
        {'typeId': 'mood', 'rating': 'great', 'loggedAt': '2026-07-03'},
      ]);
      final r = await g.patternInsight(store, _now);
      expect(r.toLowerCase(), contains('enough logged data'));
      expect(cloud.lastKind, isNull);
    });

    test('no key -> tier degrade names it a cloud feature', () async {
      final cloud = _GenCloud(err: CloudErrorKind.noKey);
      final g = GenerativeService(cloud);
      final store = _store([
        {'typeId': 'mood', 'rating': 'great', 'loggedAt': '2026-07-03'},
        {'typeId': 'workout', 'activity': 'run', 'date': '2026-07-03'},
      ]);
      expect((await g.patternInsight(store, _now)).toLowerCase(), contains('cloud feature'));
    });
  });

  group('draft message — the user\'s voice, grounded in recent interactions', () {
    test('assembles facts + most-recent-first interactions into the prompt', () async {
      final cloud = _GenCloud();
      final g = GenerativeService(cloud);
      final store = _store([
        {'id': 'c1', 'typeId': 'contact', 'displayName': 'Sam'},
        {'typeId': 'contact_fact', 'subject': 'c1', 'fact': 'loves jazz'},
        {'typeId': 'interaction', 'subject': 'c1', 'at': '2026-06-20', 'note': 'planned the gig'},
        {'typeId': 'interaction', 'subject': 'c1', 'at': '2026-07-01', 'note': 'talked about the concert'},
      ]);
      final r = await g.draftMessage('Sam', store, _now);
      expect(cloud.lastKind, 'draft_message');
      expect(cloud.lastContext, contains('loves jazz'));
      expect(cloud.lastContext, contains('talked about the concert'));
      // most recent interaction listed before the older one
      expect(cloud.lastContext!.indexOf('2026-07-01'), lessThan(cloud.lastContext!.indexOf('2026-06-20')));
      // the draft boundary is pinned in the prompt itself (DP-03: drafts yes, sends no)
      expect(cloud.lastContext, contains('never sends'));
      expect(r, isNotEmpty);
    });

    test('unknown contact -> asks to learn about them first, no cloud call', () async {
      final cloud = _GenCloud();
      final g = GenerativeService(cloud);
      final r = await g.draftMessage('Nobody', _store([]), _now);
      expect(r.toLowerCase(), contains("don't have"));
      expect(cloud.lastKind, isNull);
    });

    test('known contact, no interactions yet -> still grounded, says so honestly', () async {
      final cloud = _GenCloud();
      final g = GenerativeService(cloud);
      final store = _store([
        {'id': 'c1', 'typeId': 'contact', 'displayName': 'Sam'},
      ]);
      await g.draftMessage('Sam', store, _now);
      expect(cloud.lastKind, 'draft_message');
      expect(cloud.lastContext, contains('Recent interactions: none logged yet'));
    });

    test('offline -> honest degrade', () async {
      final cloud = _GenCloud(err: CloudErrorKind.offline);
      final g = GenerativeService(cloud);
      final store = _store([
        {'id': 'c1', 'typeId': 'contact', 'displayName': 'Sam'},
      ]);
      expect((await g.draftMessage('Sam', store, _now)).toLowerCase(), contains('offline'));
    });
  });
}

/// Hand-built store keyed by record id, mirroring the shapes the real skills
/// write (log-run/log-mood/log-interaction/create-task JSON defs).
Map<String, Map<String, dynamic>> _store(List<Map<String, dynamic>> records) {
  final m = <String, Map<String, dynamic>>{};
  var i = 0;
  for (final r in records) {
    final id = (r['id'] as String?) ?? 'r${i++}';
    m[id] = {...r, 'id': id};
  }
  return m;
}
