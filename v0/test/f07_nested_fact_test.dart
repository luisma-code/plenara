/// 05a example F-07 — the nested people-fact utterance "Sarah's daughter Mia is
/// allergic to peanuts": ONE sentence routes (offline, via corpus) to the existing
/// remember-person-fact skill and creates the contact Mia, the relationship
/// Mia = Sarah's daughter, and the allergy fact. A _NoCloud client throws if the
/// cloud is hit, proving the whole flow is deterministic corpus routing.
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');

class _NoCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
          String utterance, Map<String, Map<String, dynamic>> skills) async =>
      throw StateError('cloud routeResidual called for "$utterance" — expected a corpus/offline path');
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String description, {String? priorError}) async =>
      throw StateError('cloud authorCapability called — expected a corpus/offline path');
  @override
  Future<CloudResult<String>> generate(String kind, String context) async =>
      throw StateError('cloud generate called — expected a corpus/offline path');
}

Future<Session> _session() async {
  final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud());
  await s.init(retrieval: false);
  return s;
}

/// The single contact record named [name], or fails the test.
Map<String, dynamic> _contact(Session s, String name) => s.store.values
    .where((x) => x['typeId'] == 'contact' && x['displayName'] == name)
    .single;

void main() {
  group('F-07 nested people-fact — one sentence creates contact + relationship + fact', () {
    test("\"Sarah's daughter Mia is allergic to peanuts\" (offline corpus route)", () async {
      final s = await _session();
      final r = await s.handle("Sarah's daughter Mia is allergic to peanuts");

      // routed to remember-person-fact, whose confirmation is "Noted that {personName} {fact}."
      expect(r, contains('Noted that Mia'));
      expect(r, contains('allergic to peanuts'));

      // exactly what remember-person-fact writes: contact(Mia) + contact_fact +
      // contact(Sarah) + contact_relationship = 4 records, no more.
      expect(s.store.length, 4);

      final mia = _contact(s, 'Mia');
      final sarah = _contact(s, 'Sarah');

      // the fact record hangs off Mia (subject is a ref -> the record id)
      final fact = s.store.values.where((x) => x['typeId'] == 'contact_fact').single;
      expect(fact['subject'], mia['id']);
      expect(fact['fact'], 'allergic to peanuts');

      // the relationship links Mia to Sarah as daughter (from=relative, to=person —
      // the same shape remember-relationship writes, read as "to is from's relationType")
      final rel = s.store.values.where((x) => x['typeId'] == 'contact_relationship').single;
      expect(rel['from'], sarah['id']);
      expect(rel['to'], mia['id']);
      expect(rel['relationType'], 'daughter');
    });

    test('the created graph is queryable: recall the fact + the relationship', () async {
      final s = await _session();
      await s.handle("Sarah's daughter Mia is allergic to peanuts");
      expect(await s.handle('what do i know about Mia'), contains('allergic to peanuts'));
      expect(await s.handle('who is Mia related to'), contains('daughter of Sarah'));
    });

    test('multi-word relative name: "Sarah Mitchell\'s daughter Mia is allergic to peanuts"', () async {
      final s = await _session();
      await s.handle("Sarah Mitchell's daughter Mia is allergic to peanuts");
      final mia = _contact(s, 'Mia');
      final sarah = _contact(s, 'Sarah Mitchell');
      final rel = s.store.values.where((x) => x['typeId'] == 'contact_relationship').single;
      expect(rel['from'], sarah['id']);
      expect(rel['to'], mia['id']);
      expect(rel['relationType'], 'daughter');
    });

    test('prefixed variants route the same way (and are not stolen by the flat-fact template)', () async {
      for (final u in const [
        "remember that Sarah's daughter Mia is allergic to peanuts",
        "note that Sarah's daughter Mia is allergic to peanuts",
      ]) {
        final s = await _session();
        await s.handle(u);
        expect(s.store.length, 4, reason: 'u="$u"');
        final rel = s.store.values.where((x) => x['typeId'] == 'contact_relationship').single;
        expect(rel['relationType'], 'daughter', reason: 'u="$u"');
        final fact = s.store.values.where((x) => x['typeId'] == 'contact_fact').single;
        expect(fact['fact'], 'allergic to peanuts', reason: 'u="$u"');
      }
    });

    test('the new template does not steal neighboring possessive phrasings (regressions)', () async {
      final s = await _session();
      // set-birthday still wins its phrasing
      await s.handle("Sarah's birthday is july 10");
      expect(s.store.values.where((x) => x['typeId'] == 'contact_fact'), isEmpty);
      expect(s.store.values.where((x) => x['typeId'] == 'contact_relationship'), isEmpty);
      // set-alias still wins its phrasing
      await s.handle("Sarah's nickname is Mum");
      expect(s.store.values.where((x) => x['typeId'] == 'contact_relationship'), isEmpty);
      // remember-relationship still wins the inverted phrasing
      await s.handle("remember that Mia is Sarah's daughter");
      expect(s.store.values.where((x) => x['typeId'] == 'contact_relationship').length, 1);
      expect(s.store.values.where((x) => x['typeId'] == 'contact_fact'), isEmpty);
    });
  });
}
