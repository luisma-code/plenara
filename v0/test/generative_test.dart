/// GenerativeService (Spec 04 §3.10) — the grounded, paid synthesis path. A fake
/// generative cloud ECHOES the assembled context, so we can assert the prompt was
/// grounded in the user's real records (never invented) and that tier/connectivity
/// failures degrade honestly. The real model call lives behind the CloudClient seam.
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');

class _GenCloud implements CloudClient {
  final CloudErrorKind? err;
  String? lastKind, lastContext;
  _GenCloud({this.err});
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s) async =>
      const CloudOk(null); // abstain — these flows are corpus/generative, never residual
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
}
