/// People loop (Fable #3): log-interaction + last-interaction. Offline/corpus,
/// hermetic. Proves the contact-reuse, note capture, and — since the DSL has no
/// sort — that "when did I last talk to X" finds the MAX interaction date via the
/// foreach/branch reduction, independent of insertion order.
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

class _NoCloud implements CloudClient {
  @override
  Future<Map<String, dynamic>?> routeResidual(String u, Map<String, Map<String, dynamic>> s) async =>
      throw StateError('cloud hit for "$u" — people flows must be pure corpus');
  @override
  Future<Map<String, dynamic>?> authorCapability(String d, {String? priorError}) async =>
      throw StateError('unexpected authoring');
}

Future<Session> _session(String dir, {required DateTime clock}) async {
  final s = Session(dir, clock: clock, cloud: _NoCloud());
  await s.init(retrieval: false);
  return s;
}

DateTime _d(String iso) => DateTime.parse('${iso}T09:00:00');

void main() {
  group('log-interaction', () {
    test('creates the contact if absent and logs an interaction dated today', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      final r = await s.handle('talked to Sarah');
      expect(r, contains('Sarah'));
      final contacts = s.store.values.where((x) => x['typeId'] == 'contact').toList();
      expect(contacts.length, 1);
      expect(contacts.single['displayName'], 'Sarah');
      final ints = s.store.values.where((x) => x['typeId'] == 'interaction').toList();
      expect(ints.length, 1);
      expect(ints.single['at'], '2026-07-06');
      expect(ints.single['subject'], contacts.single['id']); // entity ref wired
    });

    test('captures a note and reuses an existing contact (no duplicate)', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle('talked to Sarah');
      await s.handle('spoke to Sarah about the school trip');
      expect(s.store.values.where((x) => x['typeId'] == 'contact').length, 1); // reused
      final ints = s.store.values.where((x) => x['typeId'] == 'interaction').toList();
      expect(ints.length, 2);
      expect(ints.any((i) => i['note'] == 'the school trip'), isTrue);
    });
  });

  group('last-interaction (max date via reduction, not insertion order)', () {
    test('reports the most recent date even when logged out of order', () async {
      final dir = makeTempDataDir();
      // log the LATER interaction first, then an earlier one, over the same folder
      await (await _session(dir, clock: _d('2026-07-08'))).handle('talked to Sarah about the trip');
      await (await _session(dir, clock: _d('2026-07-06'))).handle('talked to Sarah');

      final ask = await _session(dir, clock: _d('2026-07-10'));
      final r = await ask.handle('when did i last talk to Sarah');
      expect(r, contains('2026-07-08')); // the max, not the last inserted (07-06)
      expect(r, contains('Wednesday')); // 2026-07-08 weekday
    });

    test('unknown contact -> says so; known contact with no interactions -> says so', () async {
      final dir = makeTempDataDir();
      final s = await _session(dir, clock: _d('2026-07-06'));
      expect(await s.handle('when did i last talk to Nobody'), contains("don't have"));

      // create a contact via a fact, but never log an interaction
      await s.handle('note that Amir plays the cello');
      final r = await s.handle('when did i last speak to Amir');
      expect(r.toLowerCase(), contains("haven't logged"));
    });
  });

  group('people-loop routing', () {
    test('"talked to X about Y" -> log-interaction with a note', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle('talked to Dad about the car');
      final ints = s.store.values.where((x) => x['typeId'] == 'interaction').toList();
      expect(ints.single['note'], 'the car');
    });
    test('"caught up with X" and "called X" both log an interaction', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle('caught up with Mia');
      await s.handle('called Grandma');
      expect(s.store.values.where((x) => x['typeId'] == 'interaction').length, 2);
      expect(s.store.values.where((x) => x['typeId'] == 'contact').length, 2);
    });
  });
}
