import 'package:plenara/interpreter.dart';
import 'package:plenara/router.dart';
import 'package:plenara/store.dart';
import 'package:test/test.dart';

// Runs from the package root (v0/), so the seed data is at data/.
final _now = DateTime.parse('2026-07-06T09:00:00'); // a Monday
final _types = loadDefs('data/types', 'typeId');
final _skills = loadDefs('data/skills', 'skillId');

void main() {
  group('interpreter', () {
    test('all seed skills pass static validation', () {
      final interp = Interpreter(_types, _now);
      for (final s in _skills.values) {
        expect(() => interp.validateSkill(s), returnsNormally, reason: s['skillId']);
      }
    });

    test('create-task applies schema default (G-02) + weekday label', () {
      final interp = Interpreter(_types, _now);
      final plan = interp.resolve(
          _skills['create-task']!, {'description': 'x', 'dueDate': '2026-07-09'}, {});
      expect(plan.writes.first['completed'], isFalse);
      expect(plan.confirmation, contains('Thursday'));
    });

    test('resolve-or-create + entityRefs by resolved id (G-12/G-17)', () {
      final interp = Interpreter(_types, _now);
      final store = {
        'c1': {'id': 'c1', 'typeId': 'contact', 'displayName': 'Sarah Mitchell'}
      };
      final plan = interp.resolve(_skills['remember-person-fact']!, {
        'personName': 'Mia',
        'fact': 'is allergic to peanuts',
        'relationTo': 'Sarah Mitchell',
        'relationType': 'daughter',
      }, store);
      expect(plan.writes.map((w) => w['typeId']),
          ['contact', 'contact_fact', 'contact_relationship']);
      final mia = plan.writes[0], fact = plan.writes[1], rel = plan.writes[2];
      expect(fact['subject'], mia['id']); // entityRef -> minted Mia id
      expect(rel['from'], 'c1'); // Sarah resolved from the store
      expect(rel['to'], mia['id']);
    });

    test('foreach aggregation is read-only and sums this-week runs', () {
      final interp = Interpreter(_types, _now);
      final store = {
        'w1': {'id': 'w1', 'typeId': 'workout', 'activity': 'run', 'distance': 5, 'date': '2026-07-06'},
        'w2': {'id': 'w2', 'typeId': 'workout', 'activity': 'run', 'distance': 3, 'date': '2026-07-07'},
        'w3': {'id': 'w3', 'typeId': 'workout', 'activity': 'run', 'distance': 10, 'date': '2026-06-28'},
        'w4': {'id': 'w4', 'typeId': 'workout', 'activity': 'walk', 'distance': 2, 'date': '2026-07-06'},
      };
      final plan = interp.resolve(_skills['count-runs-this-week']!, {}, store);
      expect(plan.writes, isEmpty);
      expect(plan.confirmation, contains('8 km'));
    });

    test('G-17: an entityRef fed by a raw var is rejected statically', () {
      final interp = Interpreter(_types, _now);
      final bad = {
        'skillId': 'bad',
        'inputs': [],
        'steps': {
          'main': [
            {'op': 'write_record', 'typeId': 'contact_fact',
             'fields': {'subject': {'var': 'x'}, 'fact': 'y'}, 'into': 'f'}
          ]
        }
      };
      expect(() => interp.validateSkill(bad), throwsA(isA<ResolveError>()));
    });

    test('execute captures before-images (null for a create)', () {
      final interp = Interpreter(_types, _now);
      final store = <String, Map<String, dynamic>>{};
      final plan = interp.resolve(_skills['create-task']!, {'description': 'x'}, store);
      final before = interp.execute(plan, store);
      final id = plan.writes.first['id'] as String;
      expect(store.length, 1);
      expect(before[id], isNull); // a created record's before-image is null -> undo deletes it
    });
  });

  group('router', () {
    test('corpus template match + slot extraction + date resolve', () {
      final r = Router.load('data/corpus.json', _now);
      final routed = r.route('add call the plumber to my to-do list due thursday');
      expect(routed?['skillId'], 'create-task');
      expect(routed?['slots']['description'], 'call the plumber');
      expect(routed?['slots']['dueDate'], '2026-07-09');
    });

    test('date resolver (relative + weekday)', () {
      final r = Router.load('data/corpus.json', _now);
      expect(r.resolveDate('tomorrow', _now), '2026-07-07');
      expect(r.resolveDate('thursday', _now), '2026-07-09');
      expect(r.resolveDate('in 3 days', _now), '2026-07-09');
    });

    test('learn generalizes a new phrasing across its slot (§5.2)', () {
      final r = Router.load('data/corpus.json', _now);
      expect(r.route('jot down that I need to buy milk'), isNull); // no template yet
      r.learn('jot down that I need to buy milk', 'create-task', {'description': 'buy milk'});
      final routed = r.route('jot down that I need to call mom');
      expect(routed?['skillId'], 'create-task');
      expect(routed?['slots']['description'], 'call mom'); // learned template caught it
    });
  });
}
