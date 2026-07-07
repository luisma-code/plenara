/// Full-pipeline + property/fuzz tests: sample NLU text driven end-to-end through
/// route -> resolve -> execute -> persist -> reload -> undo, plus randomized
/// (seeded, reproducible) input sweeps that catch edge cases the enumerated cases
/// miss. Combines the router, interpreter, and store layers in one flow.
import 'dart:math';

import 'package:plenara/interpreter.dart';
import 'package:plenara/router.dart';
import 'package:plenara/store.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');
final _types = loadDefs('data/types', 'typeId');
final _skills = loadDefs('data/skills', 'skillId');
final _router = Router.load('data/corpus.json', _now);

/// Route -> resolve -> execute -> persist -> reload; returns the reloaded store.
Map<String, Map<String, dynamic>> _pipeline(String utterance, String dir) {
  final routed = _router.route(utterance);
  if (routed == null) throw StateError('no route for "$utterance"');
  final i = Interpreter(_types, _now);
  final store = loadRecords('$dir/records');
  final plan = i.resolve(_skills[routed['skillId']]!, routed['slots'], store);
  i.execute(plan, store);
  final dev = HlcDevice('d');
  for (final w in plan.writes) {
    persist(w, '$dir/records', dev);
  }
  return loadRecords('$dir/records');
}

void main() {
  group('full pipeline round-trips to disk (per skill)', () {
    test('create-task', () {
      final store = _pipeline('add call the plumber to my list', makeTempDataDir());
      expect(store.length, 1);
      final t = store.values.single;
      expect(t['typeId'], 'task');
      expect(t['description'], 'call the plumber');
      expect(t['completed'], false); // default survived the round-trip
    });
    test('log-run', () {
      final store = _pipeline('log a 5k run', makeTempDataDir());
      final w = store.values.single;
      expect(w['activity'], 'run');
      expect(w['distance'], 5);
      expect(w['date'], '2026-07-06');
    });
    test('log-mood', () {
      final store = _pipeline("i'm feeling great", makeTempDataDir());
      expect(store.values.single['rating'], 'great');
    });
    test('remember-person-fact writes the whole graph to disk', () {
      final store = _pipeline(
          "remember that Mia is allergic to peanuts and she is Sarah Mitchell's daughter", makeTempDataDir());
      expect(store.values.where((r) => r['typeId'] == 'contact').length, 2);
      expect(store.values.where((r) => r['typeId'] == 'contact_fact').length, 1);
      expect(store.values.where((r) => r['typeId'] == 'contact_relationship').length, 1);
      final fact = store.values.firstWhere((r) => r['typeId'] == 'contact_fact');
      final mia = store.values.firstWhere((r) => r['typeId'] == 'contact' && r['displayName'] == 'Mia');
      expect(fact['subject'], mia['id']); // entityRef by id survived persist+reload
    });
  });

  group('pipeline + undo round-trip', () {
    test('add then undo leaves the store (and disk) empty', () {
      final dir = makeTempDataDir();
      final routed = _router.route('add buy milk to my list')!;
      final i = Interpreter(_types, _now);
      final store = loadRecords('$dir/records');
      final plan = i.resolve(_skills['create-task']!, routed['slots'], store);
      final before = i.execute(plan, store);
      final dev = HlcDevice('d');
      for (final w in plan.writes) {
        persist(w, '$dir/records', dev);
      }
      expect(loadRecords('$dir/records').length, 1);
      undoTurn(before, '$dir/records', dev, store);
      expect(store, isEmpty);
      expect(loadRecords('$dir/records'), isEmpty); // disk really cleared
    });
  });

  group('property: 200 random task descriptions survive route->resolve->execute', () {
    final rng = Random(42); // seeded -> reproducible
    const verbs = ['call', 'email', 'buy', 'schedule', 'fix', 'return', 'pay', 'order',
      'book', 'cancel', 'renew', 'water', 'walk', 'draft', 'confirm', 'text', 'charge'];
    const nouns = ['the plumber', 'milk', 'the dentist', 'the report', 'the faucet',
      'the books', 'the bill', 'a gift', 'a table', 'the subscription', 'the registration',
      'the plants', 'the dog', 'the newsletter', 'the reservation', 'grandma', 'the babysitter'];
    for (var k = 0; k < 200; k++) {
      final desc = '${verbs[rng.nextInt(verbs.length)]} ${nouns[rng.nextInt(nouns.length)]}';
      test('#$k "$desc"', () {
        final store = <String, Map<String, dynamic>>{};
        final routed = _router.route('add $desc to my list');
        expect(routed?['skillId'], 'create-task', reason: desc);
        expect(routed?['slots']['description'], desc, reason: 'slot must equal the surface');
        final i = Interpreter(_types, _now);
        final plan = i.resolve(_skills['create-task']!, routed!['slots'], store);
        final before = i.execute(plan, store);
        expect(store.length, 1);
        expect(store.values.single['description'], desc);
        expect(before[plan.writes.first['id']], isNull, reason: 'undo-ready before-image');
      });
    }
  });

  group('property: 60 random run distances round-trip', () {
    final rng = Random(7);
    for (var k = 0; k < 60; k++) {
      final n = rng.nextBool() ? rng.nextInt(42) + 1 : (rng.nextInt(400) + 1) / 10.0;
      test('#$k ${n}k', () {
        final routed = _router.route('log a ${n}k run');
        expect(routed?['skillId'], 'log-run', reason: '$n');
        expect(routed?['slots']['distance'], n);
        final store = <String, Map<String, dynamic>>{};
        final i = Interpreter(_types, _now);
        final plan = i.resolve(_skills['log-run']!, routed!['slots'], store);
        i.execute(plan, store);
        expect(store.values.single['distance'], n);
        expect(plan.confirmation, 'Logged a $n km run today.');
      });
    }
  });
}
