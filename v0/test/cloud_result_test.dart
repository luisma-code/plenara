/// Phase-1 acceptance (typed CloudResult): a cloud FAILURE is surfaced honestly —
/// a named cause, recorded in the turnlog — and is distinct from a genuine abstain;
/// and cloud-routed date/datetime slots are normalized so the cloud path can neither
/// arm a midnight reminder (date-only time) nor silently drop one (unparseable time).
import 'dart:convert';
import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/reminders.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00'); // Monday

/// Cloud that always fails with a fixed kind (drives the error surfaces).
class _ErrCloud implements CloudClient {
  final CloudErrorKind kind;
  _ErrCloud(this.kind);
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s) async =>
      CloudError(kind);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      CloudError(kind);
}

/// Cloud returning a fixed route (drives cloud-slot normalization).
class _RouteCloud implements CloudClient {
  final Map<String, dynamic>? route;
  _RouteCloud(this.route);
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s) async =>
      CloudOk(route);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      const CloudOk(null);
}

Future<Session> _session(String dir, CloudClient c, {NotificationScheduler? sched}) async {
  final s = Session(dir, clock: _now, cloud: c, scheduler: sched);
  await s.init(retrieval: false);
  return s;
}

const _miss = 'zzz nonsense that the corpus cannot possibly match';

void main() {
  group('cloud failure is surfaced honestly (R1 — no silent degradation)', () {
    test('bad key -> the miss names the cause AND the turnlog records the kind', () async {
      final dir = makeTempDataDir();
      final s = await _session(dir, _ErrCloud(CloudErrorKind.badKey));
      final r = await s.handle(_miss);
      expect(r.toLowerCase(), contains('api key was rejected'));
      final last = jsonDecode(File('$dir/turnlog.jsonl').readAsLinesSync().last) as Map;
      expect(last['cloud'], 'badKey'); // dogfood telemetry measures cloud health
    });

    test('offline -> the miss says offline', () async {
      final s = await _session(makeTempDataDir(), _ErrCloud(CloudErrorKind.offline));
      expect((await s.handle(_miss)).toLowerCase(), contains('offline'));
    });

    test('authoring with no key -> the true reason, not the old "offline or no key" guess', () async {
      final s = await _session(makeTempDataDir(), _ErrCloud(CloudErrorKind.noKey));
      final r = await s.handle('start tracking my water intake');
      expect(r.toLowerCase(), contains('api key'));
      expect(r.contains('offline or no key'), isFalse);
    });

    test('a genuine abstain still reads as a clean clarify (no cloud-error suffix)', () async {
      final s = await _session(makeTempDataDir(), _RouteCloud(null)); // Ok(null)
      final r = await s.handle(_miss);
      expect(r.contains("couldn't check with the cloud"), isFalse);
      expect(r.toLowerCase(), contains("didn't catch"));
    });
  });

  group('cloud date/datetime slots are normalized (R2 — no wrong/dropped reminders)', () {
    test('a date-only cloud "when" -> clarify, never a midnight reminder', () async {
      final fake = FakeScheduler();
      final s = await _session(
          makeTempDataDir(),
          _RouteCloud({
            'skillId': 'set-reminder',
            'slots': <String, dynamic>{'text': 'call mom', 'when': '2026-07-08'}, // a date, no time
            'source': 'cloud',
          }),
          sched: fake);
      final r = await s.handle('give me a nudge about calling mom on the 8th'); // misses the corpus -> cloud
      expect(r.toLowerCase(), contains('when')); // asks for a time instead of arming midnight
      expect(s.store.values.where((x) => x['typeId'] == 'reminder'), isEmpty);
      expect(fake.armed(), isEmpty);
    });

    test('a natural-language cloud "when" -> a real ISO datetime, armed correctly', () async {
      final fake = FakeScheduler();
      final s = await _session(
          makeTempDataDir(),
          _RouteCloud({
            'skillId': 'set-reminder',
            'slots': <String, dynamic>{'text': 'call mom', 'when': 'thursday at 5pm'},
            'source': 'cloud',
          }),
          sched: fake);
      final r = await s.handle('nudge me to call mom later this week');
      expect(r, contains('call mom'));
      expect(fake.armed().length, 1);
      expect(fake.scheduled.values.single.at, DateTime.parse('2026-07-09T17:00:00'));
    });

    test('a natural-language cloud dueDate normalizes for create-task', () async {
      final s = await _session(
          makeTempDataDir(),
          _RouteCloud({
            'skillId': 'create-task',
            'slots': <String, dynamic>{'description': 'renew passport', 'dueDate': 'friday'},
            'source': 'cloud',
          }));
      await s.handle('i need to renew my passport by the end of the week');
      final t = s.store.values.where((x) => x['typeId'] == 'task').single;
      expect(t['dueAt'], '2026-07-10'); // resolved to ISO, not the raw "friday"
    });
  });
}
