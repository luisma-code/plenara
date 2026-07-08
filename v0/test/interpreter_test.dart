/// Interpreter layer (Spec 02) — driven by simulated NLU output ({skillId, slots}).
/// Exercises the primitive vocabulary, every seed skill across many inputs,
/// schema defaults + required-validation, read_one ambiguity, the static
/// authoring gate (pass + many rejections), and error paths. Offline.
import 'package:plenara/interpreter.dart';
import 'package:plenara/store.dart';
import 'package:test/test.dart';

final _types = loadDefs('data/types', 'typeId');
final _skills = loadDefs('data/skills', 'skillId');
final _now = DateTime.parse('2026-07-06T09:00:00'); // Monday
Interpreter _i() => Interpreter(_types, _now);
Map<String, Map<String, dynamic>> _store() => <String, Map<String, dynamic>>{};

/// resolve + execute a skill against a store; returns (plan, before-images).
(Plan, Map<String, Map<String, dynamic>?>) _run(
    String skillId, Map<String, dynamic> slots, Map<String, Map<String, dynamic>> store) {
  final i = _i();
  final p = i.resolve(_skills[skillId]!, slots, store);
  final b = i.execute(p, store);
  return (p, b);
}

Map<String, dynamic> _workout(String id, String activity, dynamic distance, String date) =>
    {'id': id, 'typeId': 'workout', 'activity': activity, 'distance': distance, 'date': date};

// weekday name for the ISO dates used below
const _weekday = {
  '2026-07-06': 'Monday', '2026-07-07': 'Tuesday', '2026-07-08': 'Wednesday',
  '2026-07-09': 'Thursday', '2026-07-10': 'Friday', '2026-07-11': 'Saturday',
  '2026-07-12': 'Sunday', '2026-12-25': 'Friday',
};

void main() {
  group('compute (closed fn vocabulary)', () {
    test('now -> ISO datetime', () => expect(_i().compute('now', [], {}), '2026-07-06T09:00:00.000'));
    test('today -> ISO date', () => expect(_i().compute('today', [], {}), '2026-07-06'));
    test('format_date EEEE -> weekday', () => expect(_i().compute('format_date', ['2026-07-09', 'EEEE'], {}), 'Thursday'));
    test('format_date other -> date only', () => expect(_i().compute('format_date', ['2026-07-09', 'y'], {}), '2026-07-09'));
    test('format_date null -> null', () => expect(_i().compute('format_date', [null, 'EEEE'], {}), isNull));
    test('format_time afternoon -> 12h clock', () => expect(_i().compute('format_time', ['2026-07-09T17:05:00'], {}), '5:05 PM'));
    test('format_time noon -> 12 PM', () => expect(_i().compute('format_time', ['2026-07-09T12:00:00'], {}), '12:00 PM'));
    test('format_time midnight -> 12 AM', () => expect(_i().compute('format_time', ['2026-07-09T00:00:00'], {}), '12:00 AM'));
    test('format_time morning -> AM', () => expect(_i().compute('format_time', ['2026-07-09T09:30:00'], {}), '9:30 AM'));
    test('format_time null -> null', () => expect(_i().compute('format_time', [null], {}), isNull));
    // clock is Monday 2026-07-06 (see _i())
    test('next_annual later this year', () => expect(_i().compute('next_annual', ['2020-12-25'], {}), '2026-12-25'));
    test('next_annual already passed -> next year', () => expect(_i().compute('next_annual', ['1990-03-03'], {}), '2027-03-03'));
    test('next_annual today -> today', () => expect(_i().compute('next_annual', ['1990-07-06'], {}), '2026-07-06'));
    test('days_until_annual future', () => expect(_i().compute('days_until_annual', ['2000-07-16'], {}), 10));
    test('days_until_annual today -> 0', () => expect(_i().compute('days_until_annual', ['2000-07-06'], {}), 0));
    test('days_until_annual passed -> rolls to next year', () => expect(_i().compute('days_until_annual', ['2000-07-05'], {}), 364));
    test('next_annual null -> null', () => expect(_i().compute('next_annual', [null], {}), isNull));
    // streaks over a record list's date field (clock is Monday 2026-07-06)
    test('current_streak today + back', () => expect(_i().compute('current_streak',
        [[{'date': '2026-07-06'}, {'date': '2026-07-05'}, {'date': '2026-07-04'}], 'date'], {}), 3));
    test('current_streak alive via yesterday', () => expect(_i().compute('current_streak',
        [[{'date': '2026-07-05'}, {'date': '2026-07-04'}], 'date'], {}), 2));
    test('current_streak broken (only older days)', () => expect(_i().compute('current_streak',
        [[{'date': '2026-07-04'}], 'date'], {}), 0));
    test('current_streak dedupes same-day', () => expect(_i().compute('current_streak',
        [[{'date': '2026-07-06'}, {'date': '2026-07-06'}], 'date'], {}), 1));
    test('longest_streak finds the max run', () => expect(_i().compute('longest_streak',
        [[{'date': '2026-07-01'}, {'date': '2026-07-02'}, {'date': '2026-07-03'}, {'date': '2026-07-06'}], 'date'], {}), 3));
    test('streak over empty list -> 0', () => expect(_i().compute('current_streak', [[], 'date'], {}), 0));
    // aggregation + date math (spec §3.7)
    test('sum over a field', () => expect(_i().compute('sum', [[{'d': 2}, {'d': 3}, {'d': 5}], 'd'], {}), 10));
    test('sum parses numeric strings', () => expect(_i().compute('sum', [[{'d': '2.5'}, {'d': '1.5'}], 'd'], {}), 4.0));
    test('avg over a field', () => expect(_i().compute('avg', [[{'d': 2}, {'d': 4}], 'd'], {}), 3));
    test('avg empty -> null (no data, not a misleading 0)', () => expect(_i().compute('avg', [[], 'd'], {}), isNull));
    test('min / max', () {
      expect(_i().compute('min', [[{'d': 5}, {'d': 2}, {'d': 8}], 'd'], {}), 2);
      expect(_i().compute('max', [[{'d': 5}, {'d': 2}, {'d': 8}], 'd'], {}), 8);
    });
    test('count_where', () => expect(_i().compute('count_where', [[{'a': 'run'}, {'a': 'walk'}, {'a': 'run'}], 'a', 'run'], {}), 2));
    test('days_between', () => expect(_i().compute('days_between', ['2026-07-06', '2026-07-10'], {}), 4));
    test('add_days', () => expect(_i().compute('add_days', ['2026-07-06', 5], {}), '2026-07-11'));
    test('if ternary', () {
      expect(_i().compute('if', [true, 'a', 'b'], {}), 'a');
      expect(_i().compute('if', [false, 'a', 'b'], {}), 'b');
    });
    test('start_of_week(Wed) -> Monday', () => expect(_i().compute('start_of_week', ['2026-07-08'], {}), '2026-07-06'));
    test('start_of_week(Sun) -> Monday', () => expect(_i().compute('start_of_week', ['2026-07-12'], {}), '2026-07-06'));
    test('start_of_week(Mon) -> same', () => expect(_i().compute('start_of_week', ['2026-07-06'], {}), '2026-07-06'));
    for (final c in [[3, 4, 7], [0, 5, 5], [10, 0, 10], [2, 2, 4]]) {
      test('add ${c[0]}+${c[1]}=${c[2]}', () => expect(_i().compute('add', [c[0], c[1]], {}), c[2]));
    }
    test('add with null -> treats as 0', () => expect(_i().compute('add', [5, null], {}), 5));
    test('mul', () => expect(_i().compute('mul', [6, 7], {}), 42));
    test('div', () => expect(_i().compute('div', [10, 4], {}), 2.5));
    test('div by zero -> null (guarded, no crash/Infinity)', () => expect(_i().compute('div', [5, 0], {}), isNull));
    test('div non-number -> null', () => expect(_i().compute('div', ['x', 2], {}), isNull));
    test('round', () => expect(_i().compute('round', [2.6], {}), 3));
    test('percentage idiom: round(100 * part/whole)', () {
      final pct = _i().compute('round', [_i().compute('mul', [100, _i().compute('div', [30, 50], {})], {})], {});
      expect(pct, 60);
    });
    test('ordinal_num maps the ordinal word', () {
      expect(_i().compute('ordinal_num', ['second'], {}), 2);
      expect(_i().compute('ordinal_num', ['last'], {}), -1);
    });
    test('start_of_month', () => expect(_i().compute('start_of_month', ['2026-07-14'], {}), '2026-07-01'));
    test('format renders {name} AND the model-variant {var:name} (authoring robustness)', () {
      final skill = {
        'skillId': 'x', 'inputs': [{'name': 'count'}], 'reads': [], 'writes': [],
        'steps': {'main': [{'op': 'format', 'template': 'Logged {count} / {var:count}.', 'into': 'confirmationText'}]}
      };
      final p = _i().resolve(skill, {'count': 20}, {});
      expect(p.confirmation, 'Logged 20 / 20.');
    });
    test('count list', () => expect(_i().compute('count', [[1, 2, 3]], {}), 3));
    test('count empty', () => expect(_i().compute('count', [[]], {}), 0));
    test('count null -> 0', () => expect(_i().compute('count', [null], {}), 0));
    test('concat', () => expect(_i().compute('concat', ['a', 'b', 'c'], {}), 'abc'));
    test('concat skips null', () => expect(_i().compute('concat', ['x', null, 'y'], {}), 'xy'));
    test('unknown fn -> throws', () => expect(() => _i().compute('bogus', [], {}), throwsA(isA<ResolveError>())));
  });

  group('val (value resolution)', () {
    test('{var}', () => expect(_i().val({'var': 'x'}, {'x': 5}), 5));
    test('{ref} -> record id', () => expect(_i().val({'ref': 'p'}, {'p': {'id': 'c1'}}), 'c1'));
    test('{ref} to null -> null', () => expect(_i().val({'ref': 'p'}, {}), isNull));
    test('{field}', () => expect(_i().val({'field': ['r', 'date']}, {'r': {'date': '2026-07-06'}}), '2026-07-06'));
    test('{field} of missing -> null', () => expect(_i().val({'field': ['r', 'x']}, {}), isNull));
    test('{fn}', () => expect(_i().val({'fn': 'add', 'args': [2, 3]}, {}), 5));
    test('literal num', () => expect(_i().val(42, {}), 42));
    test('literal string', () => expect(_i().val('lit', {}), 'lit'));
  });

  group('cond', () {
    test('isNull true', () => expect(_i().cond({'isNull': 'x'}, {}), isTrue));
    test('isNull false', () => expect(_i().cond({'isNull': 'x'}, {'x': 1}), isFalse));
    test('notNull true', () => expect(_i().cond({'notNull': 'x'}, {'x': 1}), isTrue));
    test('notNull false', () => expect(_i().cond({'notNull': 'x'}, {}), isFalse));
    test('gte dates equal (inclusive)', () => expect(_i().cond({'gte': ['2026-07-06', '2026-07-06']}, {}), isTrue));
    test('gte dates before', () => expect(_i().cond({'gte': ['2026-07-05', '2026-07-06']}, {}), isFalse));
    test('gte dates after', () => expect(_i().cond({'gte': ['2026-07-20', '2026-07-06']}, {}), isTrue));
    test('gte numeric single digit', () => expect(_i().cond({'gte': [5, 1]}, {}), isTrue));
    test('gte numeric multi-digit (fixed: 10>=3)', () => expect(_i().cond({'gte': [10, 3]}, {}), isTrue));
    test('gte numeric-as-string 10>=3', () => expect(_i().cond({'gte': ['10', '3']}, {}), isTrue));
    test('gte 0>=1 false', () => expect(_i().cond({'gte': [0, 1]}, {}), isFalse));
    test('eq true', () => expect(_i().cond({'eq': [1, 1]}, {}), isTrue));
    test('eq false', () => expect(_i().cond({'eq': [1, 2]}, {}), isFalse));
    test('contains substring (case-insensitive)',
        () => expect(_i().cond({'contains': ['She likes CHESS', 'likes chess']}, {}), isTrue));
    test('contains miss', () => expect(_i().cond({'contains': ['plays piano', 'chess']}, {}), isFalse));
    test('contains empty needle never matches',
        () => expect(_i().cond({'contains': ['anything', '']}, {}), isFalse));
    test('unknown cond -> throws', () => expect(() => _i().cond({'bogus': 1}, {}), throwsA(isA<ResolveError>())));
  });

  group('read_many — ordering, limit, filter operators', () {
    Map<String, Map<String, dynamic>> store() => {
          'i-1': {'id': 'i-1', 'typeId': 'workout', 'activity': 'run', 'distance': 3, 'date': '2026-07-04'},
          'i-2': {'id': 'i-2', 'typeId': 'workout', 'activity': 'run', 'distance': 8, 'date': '2026-07-08'},
          'i-3': {'id': 'i-3', 'typeId': 'workout', 'activity': 'walk', 'distance': 2, 'date': '2026-07-06'},
        };
    String? run(List<Map<String, dynamic>> main) =>
        _i().resolve({'skillId': 'x', 'steps': {'main': main}}, {}, store()).confirmation;

    test('orderBy desc + limit 1 -> most recent (retires the foreach-MAX hack)', () {
      expect(
          run([
            {'op': 'read_many', 'typeId': 'workout', 'orderBy': 'date', 'orderDir': 'desc', 'limit': 1, 'into': 'recent'},
            {'op': 'set', 'var': 'out', 'value': ''},
            {'op': 'foreach', 'list': {'var': 'recent'}, 'as': 'r', 'body': [
              {'op': 'compute', 'fn': 'concat', 'args': [{'var': 'out'}, {'field': ['r', 'date']}], 'into': 'out'}
            ]},
            {'op': 'format', 'template': '{out}', 'into': 'confirmationText'},
          ]),
          '2026-07-08');
    });

    test('filter gte on date + sum over distance', () {
      expect(
          run([
            {'op': 'read_many', 'typeId': 'workout', 'filter': {'field': 'date', 'op': 'gte', 'value': '2026-07-06'}, 'into': 'recent'},
            {'op': 'compute', 'fn': 'sum', 'args': [{'var': 'recent'}, 'distance'], 'into': 'total'},
            {'op': 'format', 'template': '{total}', 'into': 'confirmationText'},
          ]),
          '10'); // i-2 (8) + i-3 (2), i-1 (07-04) excluded
    });

    test('filter neq + count', () {
      expect(
          run([
            {'op': 'read_many', 'typeId': 'workout', 'filter': {'field': 'activity', 'op': 'neq', 'value': 'run'}, 'into': 'nonRuns'},
            {'op': 'compute', 'fn': 'count', 'args': [{'var': 'nonRuns'}], 'into': 'n'},
            {'op': 'format', 'template': '{n}', 'into': 'confirmationText'},
          ]),
          '1'); // only the walk
    });
  });

  group('read_one — alias tier (G-24)', () {
    String? who(String q) {
      final store = {
        'c1': {'id': 'c1', 'typeId': 'contact', 'displayName': 'Sarah', 'aliases': 'Mum, the boss'},
        'c2': {'id': 'c2', 'typeId': 'contact', 'displayName': 'Tom'},
      };
      final skill = {'skillId': 'x', 'steps': {'main': [
        {'op': 'read_one', 'typeId': 'contact', 'match': {'displayName': {'var': 'q'}}, 'partial': true, 'into': 'p'},
        {'op': 'branch', 'cond': {'isNull': 'p'}, 'then': [
          {'op': 'format', 'template': 'none', 'into': 'confirmationText'}
        ], 'else': [
          {'op': 'set', 'var': 'w', 'value': {'field': ['p', 'displayName']}},
          {'op': 'format', 'template': '{w}', 'into': 'confirmationText'}
        ]}
      ]}};
      return _i().resolve(skill, {'q': q}, store).confirmation;
    }

    test('resolves a nickname via aliases', () => expect(who('the boss'), 'Sarah'));
    test('resolves a comma-listed alias', () => expect(who('Mum'), 'Sarah'));
    test('exact displayName still wins (no alias needed)', () => expect(who('Tom'), 'Tom'));
    test('an unknown name matches nothing (no false alias hit)', () => expect(who('Nobody'), 'none'));
  });

  group('format', () {
    test('renders a null/absent var as empty — never leaks a literal {var}', () {
      final skill = {
        'skillId': 'x',
        'steps': {
          'main': [
            {'op': 'format', 'template': 'Hi {name}, due {when}.', 'into': 'confirmationText'}
          ]
        }
      };
      final plan = _i().resolve(skill, {'name': 'Sam'}, {}); // `when` is absent
      expect(plan.confirmation, 'Hi Sam, due .');
      expect(plan.confirmation!.contains('{'), isFalse);
    });
  });

  group('create-task — NLU slots (no due date, many descriptions)', () {
    for (final d in ['call the plumber', 'buy milk', 'walk the dog', 'pay the rent',
      'schedule a dentist appointment', 'book flights to Boston', 'renew the registration']) {
      test('"$d"', () {
        final store = _store();
        final (p, _) = _run('create-task', {'description': d}, store);
        expect(p.writes.length, 1);
        final t = p.writes.first;
        expect(t['typeId'], 'task');
        expect(t['description'], d);
        expect(t['completed'], isFalse, reason: 'schema default');
        expect(t['createdAt'], '2026-07-06T09:00:00.000');
        expect(t['dueAt'], isNull);
        expect(p.confirmation, 'Added "$d" to your tasks.');
        expect(store.length, 1);
      });
    }
  });

  group('create-task — NLU slots (with due date -> weekday label)', () {
    for (final entry in _weekday.entries) {
      test('due ${entry.key} -> "${entry.value}"', () {
        final (p, _) = _run('create-task', {'description': 'X', 'dueDate': entry.key}, _store());
        expect(p.writes.first['dueAt'], entry.key);
        expect(p.confirmation, 'Added "X" to your tasks, due ${entry.value}.');
      });
    }
  });

  group('log-run — NLU slots (many distances)', () {
    for (final n in [1, 2, 3, 5, 8, 10, 12, 15, 21, 26, 0.5, 3.5, 13.1]) {
      test('distance $n', () {
        final store = _store();
        final (p, _) = _run('log-run', {'distance': n}, store);
        final w = p.writes.first;
        expect(w['typeId'], 'workout');
        expect(w['activity'], 'run');
        expect(w['distance'], n);
        expect(w['date'], '2026-07-06');
        expect(p.confirmation, 'Logged a $n km run today.');
      });
    }
    test('no distance -> generic confirmation', () {
      final (p, _) = _run('log-run', {}, _store());
      expect(p.writes.first['distance'], isNull);
      expect(p.confirmation, 'Logged a run today.');
    });
  });

  group('log-mood — NLU slots (many ratings)', () {
    for (final m in ['great', 'good', 'anxious', 'tired', 'excited', 'stressed', 'content']) {
      test('"$m"', () {
        final (p, _) = _run('log-mood', {'rating': m}, _store());
        final r = p.writes.first;
        expect(r['typeId'], 'mood');
        expect(r['rating'], m);
        expect(r['loggedAt'], '2026-07-06');
        expect(p.confirmation, 'Logged your mood as $m.');
      });
    }
  });

  group('count-runs-this-week — aggregation over many stores (read-only)', () {
    final scenarios = <String, (List<Map<String, dynamic>>, String)>{
      'two runs this week': ([_workout('a', 'run', 5, '2026-07-06'), _workout('b', 'run', 3, '2026-07-07')], '8'),
      'run last week excluded': ([_workout('a', 'run', 5, '2026-07-06'), _workout('b', 'run', 10, '2026-06-28')], '5'),
      'walk excluded by activity': ([_workout('a', 'run', 5, '2026-07-06'), _workout('b', 'walk', 2, '2026-07-06')], '5'),
      'empty store': (<Map<String, dynamic>>[], '0'),
      'boundary: run exactly on weekStart counts': ([_workout('a', 'run', 4, '2026-07-06')], '4'),
      'day before weekStart excluded': ([_workout('a', 'run', 9, '2026-07-05')], '0'),
      'decimals sum': ([_workout('a', 'run', 3.5, '2026-07-06'), _workout('b', 'run', 2.5, '2026-07-08')], '6.0'),
      'null distance adds nothing': ([_workout('a', 'run', null, '2026-07-06'), _workout('b', 'run', 4, '2026-07-07')], '4'),
      'many runs': ([
        _workout('a', 'run', 2, '2026-07-06'), _workout('b', 'run', 3, '2026-07-07'),
        _workout('c', 'run', 4, '2026-07-08'), _workout('d', 'run', 1, '2026-07-09')
      ], '10'),
    };
    scenarios.forEach((name, sc) {
      test(name, () {
        final store = {for (final r in sc.$1) r['id'] as String: r};
        final (p, before) = _run('count-runs-this-week', {}, store);
        expect(p.writes, isEmpty, reason: 'aggregation must not write');
        expect(before, isEmpty);
        expect(p.confirmation, "You've run ${sc.$2} km so far this week.");
      });
    });
  });

  group('remember-person-fact — resolve-or-create + entityRefs', () {
    test('new person, no relation -> contact + fact; fact.subject = minted id', () {
      final store = _store();
      final (p, _) = _run('remember-person-fact', {'personName': 'Mia', 'fact': 'likes tea'}, store);
      expect(p.writes.map((w) => w['typeId']), ['contact', 'contact_fact']);
      final contact = p.writes[0], fact = p.writes[1];
      expect(contact['displayName'], 'Mia');
      expect(fact['subject'], contact['id']); // entityRef by resolved id, not the name
      expect(fact['fact'], 'likes tea');
      expect(p.confirmation, 'Noted that Mia likes tea.');
    });
    test('existing person -> resolved, no new contact', () {
      final store = <String, Map<String, dynamic>>{'c1': {'id': 'c1', 'typeId': 'contact', 'displayName': 'Sarah Mitchell'}};
      final (p, _) = _run('remember-person-fact', {'personName': 'Sarah Mitchell', 'fact': 'runs marathons'}, store);
      expect(p.writes.map((w) => w['typeId']), ['contact_fact']); // no new contact
      expect(p.writes[0]['subject'], 'c1');
    });
    test('with relation, new relative -> contact + fact + relative + relationship', () {
      final store = _store();
      final (p, _) = _run('remember-person-fact',
          {'personName': 'Mia', 'fact': 'is allergic to peanuts', 'relationTo': 'Sarah Mitchell', 'relationType': 'daughter'}, store);
      expect(p.writes.map((w) => w['typeId']),
          ['contact', 'contact_fact', 'contact', 'contact_relationship']);
      final person = p.writes[0], rel = p.writes[3], relative = p.writes[2];
      expect(rel['from'], relative['id']);
      expect(rel['to'], person['id']);
      expect(rel['relationType'], 'daughter');
    });
    test('resolves an existing person case-insensitively (no duplicate contact)', () {
      final store = <String, Map<String, dynamic>>{'c1': {'id': 'c1', 'typeId': 'contact', 'displayName': 'Mia'}};
      final (p, _) = _run('remember-person-fact', {'personName': 'mia', 'fact': 'likes tea'}, store);
      expect(p.writes.map((w) => w['typeId']), ['contact_fact']); // NOT [contact, contact_fact]
      expect(p.writes[0]['subject'], 'c1');
    });
    test('with relation, existing relative -> resolved (no 2nd contact write)', () {
      final store = <String, Map<String, dynamic>>{'c1': {'id': 'c1', 'typeId': 'contact', 'displayName': 'Sarah Mitchell'}};
      final (p, _) = _run('remember-person-fact',
          {'personName': 'Mia', 'fact': 'is her daughter', 'relationTo': 'Sarah Mitchell', 'relationType': 'daughter'}, store);
      expect(p.writes.map((w) => w['typeId']), ['contact', 'contact_fact', 'contact_relationship']);
      expect(p.writes[2]['from'], 'c1'); // resolved Sarah
    });
  });

  group('recall-facts', () {
    test('unknown person', () {
      final (p, _) = _run('recall-facts', {'personName': 'Nobody'}, _store());
      expect(p.writes, isEmpty);
      expect(p.confirmation, "I don't know anyone named Nobody yet.");
    });
    test('known with facts', () {
      final store = {
        'c1': {'id': 'c1', 'typeId': 'contact', 'displayName': 'Mia'},
        'f1': {'id': 'f1', 'typeId': 'contact_fact', 'subject': 'c1', 'fact': 'allergic to peanuts'},
        'f2': {'id': 'f2', 'typeId': 'contact_fact', 'subject': 'c1', 'fact': 'loves drawing'},
        'f3': {'id': 'f3', 'typeId': 'contact_fact', 'subject': 'cX', 'fact': 'someone else'},
      };
      final (p, _) = _run('recall-facts', {'personName': 'Mia'}, store);
      expect(p.confirmation, contains("Here's what I know about Mia:"));
      expect(p.confirmation, contains('allergic to peanuts'));
      expect(p.confirmation, contains('loves drawing'));
      expect(p.confirmation, isNot(contains('someone else'))); // filtered by subject
    });
    test('known with no facts', () {
      final store = {'c1': {'id': 'c1', 'typeId': 'contact', 'displayName': 'Tom'}};
      final (p, _) = _run('recall-facts', {'personName': 'Tom'}, store);
      expect(p.confirmation, 'I have Tom as a contact but nothing noted yet.');
    });
  });

  group('list-tasks', () {
    test('empty', () {
      final (p, _) = _run('list-tasks', {}, _store());
      expect(p.confirmation, 'You have 0 task(s):');
    });
    for (final n in [1, 3, 7]) {
      test('$n tasks', () {
        final store = {
          for (var k = 0; k < n; k++)
            't$k': {'id': 't$k', 'typeId': 'task', 'description': 'task $k'}
        };
        final (p, _) = _run('list-tasks', {}, store);
        expect(p.confirmation, startsWith('You have $n task(s):'));
        for (var k = 0; k < n; k++) {
          expect(p.confirmation, contains('task $k'));
        }
      });
    }
  });

  group('static validation — the authoring gate', () {
    test('all ${_skills.length} seed skills pass', () {
      for (final s in _skills.values) {
        expect(() => _i().validateSkill(s), returnsNormally, reason: s['skillId']);
      }
    });

    Map<String, dynamic> skillWriting(dynamic subjectField) => {
          'skillId': 'x',
          'steps': {'main': [
            {'op': 'write_record', 'typeId': 'contact_fact', 'fields': {'subject': subjectField, 'fact': 'y'}, 'into': 'f'}
          ]}
        };

    test('reject: entity fed by a raw {var}', () {
      expect(() => _i().validateSkill(skillWriting({'var': 'x'})), throwsA(isA<ResolveError>()));
    });
    test('reject: entity fed by a literal', () {
      expect(() => _i().validateSkill(skillWriting('some-id')), throwsA(isA<ResolveError>()));
    });
    test('reject: entity fed by {ref} to a non-record var', () {
      expect(() => _i().validateSkill(skillWriting({'ref': 'ghost'})), throwsA(isA<ResolveError>()));
    });
    test('reject: entity fed by {field:[rec, name]} (not id)', () {
      final s = {
        'skillId': 'x',
        'steps': {'main': [
          {'op': 'read_one', 'typeId': 'contact', 'match': {'displayName': {'var': 'n'}}, 'into': 'p'},
          {'op': 'write_record', 'typeId': 'contact_fact', 'fields': {'subject': {'field': ['p', 'displayName']}, 'fact': 'y'}, 'into': 'f'}
        ]}
      };
      expect(() => _i().validateSkill(s), throwsA(isA<ResolveError>()));
    });
    test('reject: an unbound variable (typo) — closure rule 4 (Fable#2)', () {
      final s = {
        'skillId': 'x',
        'inputs': [{'name': 'name'}],
        'steps': {'main': [
          {'op': 'format', 'template': 'hi {naem}', 'into': 'confirmationText'} // typo: naem, not name
        ]}
      };
      expect(() => _i().validateSkill(s), throwsA(isA<ResolveError>()));
    });
    test('accept: entity fed by {ref} to a read_one record', () {
      final s = {
        'skillId': 'x',
        'inputs': [{'name': 'n'}],
        'steps': {'main': [
          {'op': 'read_one', 'typeId': 'contact', 'match': {'displayName': {'var': 'n'}}, 'into': 'p'},
          {'op': 'write_record', 'typeId': 'contact_fact', 'fields': {'subject': {'ref': 'p'}, 'fact': 'y'}, 'into': 'f'},
          {'op': 'format', 'template': 'ok', 'into': 'confirmationText'}
        ]}
      };
      expect(() => _i().validateSkill(s), returnsNormally);
    });
    test('accept: entity fed by {field:[rec, id]}', () {
      final s = {
        'skillId': 'x',
        'inputs': [{'name': 'n'}],
        'steps': {'main': [
          {'op': 'read_one', 'typeId': 'contact', 'match': {'displayName': {'var': 'n'}}, 'into': 'p'},
          {'op': 'write_record', 'typeId': 'contact_fact', 'fields': {'subject': {'field': ['p', 'id']}, 'fact': 'y'}, 'into': 'f'},
          {'op': 'format', 'template': 'ok', 'into': 'confirmationText'}
        ]}
      };
      expect(() => _i().validateSkill(s), returnsNormally);
    });
    test('accept: entity fed by a foreach loop var (scoped record)', () {
      final s = {
        'skillId': 'x',
        'steps': {'main': [
          {'op': 'read_many', 'typeId': 'contact', 'into': 'ps'},
          {'op': 'foreach', 'list': {'var': 'ps'}, 'as': 'p', 'body': [
            {'op': 'write_record', 'typeId': 'contact_fact', 'fields': {'subject': {'ref': 'p'}, 'fact': 'y'}, 'into': 'f'}
          ]},
          {'op': 'format', 'template': 'ok', 'into': 'confirmationText'}
        ]}
      };
      expect(() => _i().validateSkill(s), returnsNormally);
    });
  });

  group('update + delete ops (Fable review)', () {
    test('write_record with target updates an existing record (merge, same id)', () {
      final store = <String, Map<String, dynamic>>{
        'task-x': {'id': 'task-x', 'typeId': 'task', 'description': 'buy milk', 'completed': false, 'createdAt': 'c'}
      };
      final (p, before) = _run('complete-task', {'description': 'buy milk'}, store);
      final t = p.writes.single;
      expect(t['id'], 'task-x'); // same record, not a fresh mint
      expect(t['completed'], true);
      expect(t['description'], 'buy milk'); // untouched fields preserved
      expect(store['task-x']!['completed'], true);
      expect(before['task-x'], isNotNull); // update -> before is the prior (undo can restore)
      expect(p.confirmation, contains('done'));
    });
    test('complete-task on a missing task -> friendly message, no write', () {
      final (p, _) = _run('complete-task', {'description': 'nope'}, _store());
      expect(p.writes, isEmpty);
      expect(p.confirmation, contains("couldn't find"));
    });
    test('delete_record removes from store and captures the before-image', () {
      final store = <String, Map<String, dynamic>>{
        'task-x': {'id': 'task-x', 'typeId': 'task', 'description': 'buy milk'}
      };
      final (p, before) = _run('delete-task', {'description': 'buy milk'}, store);
      expect(p.deletes, ['task-x']);
      expect(store.containsKey('task-x'), isFalse);
      expect(before['task-x']!['description'], 'buy milk'); // undo can restore it
    });
    test('read_related returns records whose via-attr points at the from record', () {
      final store = <String, Map<String, dynamic>>{
        'c1': {'id': 'c1', 'typeId': 'contact', 'displayName': 'Mia'},
        'f1': {'id': 'f1', 'typeId': 'contact_fact', 'subject': 'c1', 'fact': 'a'},
        'f2': {'id': 'f2', 'typeId': 'contact_fact', 'subject': 'cX', 'fact': 'b'},
      };
      final s = {'skillId': 'x', 'reads': ['contact', 'contact_fact'], 'writes': [], 'steps': {'main': [
        {'op': 'read_one', 'typeId': 'contact', 'match': {'displayName': 'Mia'}, 'into': 'p'},
        {'op': 'read_related', 'typeId': 'contact_fact', 'via': 'subject', 'from': {'ref': 'p'}, 'into': 'fs'},
        {'op': 'compute', 'fn': 'count', 'args': [{'var': 'fs'}], 'into': 'n'},
        {'op': 'format', 'template': '{n}', 'into': 'confirmationText'},
      ]}};
      final i = _i();
      expect(() => i.validateSkill(s), returnsNormally);
      expect(i.resolve(s, {}, store).confirmation, '1'); // only f1 points at c1
    });
    test('update to a non-existent target throws (no silent create)', () {
      final s = {'skillId': 'x', 'steps': {'main': [
        {'op': 'write_record', 'typeId': 'task', 'target': {'var': 'missing'}, 'fields': {'completed': true}, 'into': 't'},
        {'op': 'format', 'template': 'ok', 'into': 'confirmationText'},
      ]}};
      expect(() => _i().resolve(s, {}, _store()), throwsA(isA<ResolveError>()));
    });
  });

  group('hardened authoring gate (Fable review)', () {
    Map<String, dynamic> skill(List main) => {'skillId': 'x', 'steps': {'main': main}};
    final ok = {'op': 'format', 'template': 'done', 'into': 'confirmationText'};

    test('unknown op rejected', () {
      expect(() => _i().validateSkill(skill([{'op': 'delete_everything'}, ok])), throwsA(isA<ResolveError>()));
    });
    test('delete_record without an id is rejected; with an id is accepted', () {
      expect(() => _i().validateSkill(skill([{'op': 'delete_record'}, ok])), throwsA(isA<ResolveError>()));
      expect(() => _i().validateSkill(skill([{'op': 'delete_record', 'id': {'var': 'x'}}, ok])), returnsNormally);
    });
    test('unknown compute fn (e.g. median, unimplemented) rejected', () {
      expect(() => _i().validateSkill(skill([{'op': 'compute', 'fn': 'median', 'args': [], 'into': 'x'}, ok])), throwsA(isA<ResolveError>()));
    });
    test('write to unknown type rejected', () {
      expect(() => _i().validateSkill(skill([{'op': 'write_record', 'typeId': 'ghost', 'fields': {}, 'into': 'r'}, ok])), throwsA(isA<ResolveError>()));
    });
    test('read_many bad filter op rejected at the gate', () {
      expect(() => _i().validateSkill(skill([{'op': 'read_many', 'typeId': 'task', 'filter': {'field': 'dueAt', 'op': 'bogus', 'value': 1}, 'into': 'ts'}, ok])), throwsA(isA<ResolveError>()));
    });
    test('read_many unknown filter op also throws at resolve time', () {
      final s = skill([{'op': 'read_many', 'typeId': 'task', 'filter': {'field': 'dueAt', 'op': 'bogus', 'value': 1}, 'into': 'ts'}, ok]);
      expect(() => _i().resolve(s, {}, _store()), throwsA(isA<ResolveError>()));
    });
    test('missing confirmation rejected', () {
      expect(() => _i().validateSkill(skill([{'op': 'compute', 'fn': 'today', 'into': 't'}])), throwsA(isA<ResolveError>()));
    });
    test('missing steps.main rejected without crashing', () {
      expect(() => _i().validateSkill({'skillId': 'x'}), throwsA(isA<ResolveError>()));
      expect(() => _i().validateSkill({'skillId': 'x', 'steps': {}}), throwsA(isA<ResolveError>()));
    });
    test('branch-leak: a var resolved only in then, used after the branch, is rejected', () {
      final s = skill([
        {'op': 'branch', 'cond': {'notNull': 'q'}, 'then': [
          {'op': 'read_one', 'typeId': 'contact', 'match': {'displayName': {'var': 'q'}}, 'into': 'p'}
        ], 'else': []},
        {'op': 'write_record', 'typeId': 'contact_fact', 'fields': {'subject': {'ref': 'p'}, 'fact': 'y'}, 'into': 'f'},
        ok,
      ]);
      expect(() => _i().validateSkill(s), throwsA(isA<ResolveError>()));
    });
    test('refType mismatch: entity ref to a wrong-typed record is rejected', () {
      final s = skill([
        {'op': 'read_one', 'typeId': 'task', 'match': {'description': {'var': 'd'}}, 'into': 't'},
        {'op': 'write_record', 'typeId': 'contact_fact', 'fields': {'subject': {'ref': 't'}, 'fact': 'y'}, 'into': 'f'},
        ok,
      ]);
      expect(() => _i().validateSkill(s), throwsA(isA<ResolveError>()));
    });
    test('validateType rejects unknown valueType + entity without refType; accepts valid', () {
      expect(() => _i().validateType({'typeId': 't', 'attributes': [{'name': 'x', 'valueType': 'bogus'}]}), throwsA(isA<ResolveError>()));
      expect(() => _i().validateType({'typeId': 't', 'attributes': [{'name': 'x', 'valueType': 'entityRef'}]}), throwsA(isA<ResolveError>()));
      expect(() => _i().validateType({'typeId': 't', 'attributes': [{'name': 'x', 'valueType': 'text'}]}), returnsNormally);
    });
    test('validateType accepts the Spec 01 §3 value-type set (G-40 alignment)', () {
      for (final vt in const ['number', 'decimal', 'duration', 'tag', 'attachment', 'json', 'datetime', 'boolean']) {
        expect(() => _i().validateType({'typeId': 't', 'attributes': [{'name': 'x', 'valueType': vt}]}),
            returnsNormally, reason: vt);
      }
    });
    test('capability closure: writing an undeclared type is rejected', () {
      final s = {'skillId': 'x', 'reads': [], 'writes': ['task'], 'steps': {'main': [
        {'op': 'compute', 'fn': 'today', 'into': 't'},
        {'op': 'write_record', 'typeId': 'mood', 'fields': {'rating': 'x', 'loggedAt': {'var': 't'}}, 'into': 'm'},
        {'op': 'format', 'template': 'ok', 'into': 'confirmationText'},
      ]}};
      expect(() => _i().validateSkill(s), throwsA(isA<ResolveError>()));
    });
    test('capability closure: reading an undeclared type is rejected', () {
      final s = {'skillId': 'x', 'reads': [], 'writes': [], 'steps': {'main': [
        {'op': 'read_many', 'typeId': 'task', 'into': 'ts'},
        {'op': 'format', 'template': 'ok', 'into': 'confirmationText'},
      ]}};
      expect(() => _i().validateSkill(s), throwsA(isA<ResolveError>()));
    });
    test('all seed skills declare and satisfy their reads/writes', () {
      for (final sk in _skills.values) {
        expect(sk['reads'], isA<List>(), reason: '${sk['skillId']} must declare reads');
        expect(sk['writes'], isA<List>(), reason: '${sk['skillId']} must declare writes');
        expect(() => _i().validateSkill(sk), returnsNormally, reason: sk['skillId'] as String);
      }
    });
    test('mint produces unique ids across 500 fresh interpreters (no cross-session collision)', () {
      final ids = <String>{};
      for (var k = 0; k < 500; k++) {
        final p = Interpreter(_types, _now).resolve(_skills['create-task']!, {'description': 'x'}, _store());
        ids.add(p.writes.first['id'] as String);
      }
      expect(ids.length, 500, reason: 'every minted id must be unique across sessions');
      expect(ids.first, startsWith('task-'));
    });
  });

  group('error paths (resolve/execute throw ResolveError, not crash)', () {
    test('required field missing', () {
      final s = {'skillId': 'x', 'steps': {'main': [
        {'op': 'write_record', 'typeId': 'mood', 'fields': {'loggedAt': '2026-07-06'}, 'into': 'm'} // no rating
      ]}};
      expect(() => _i().resolve(s, {}, _store()), throwsA(isA<ResolveError>()));
    });
    test('read_one ambiguous (G-12)', () {
      final store = {
        'c1': {'id': 'c1', 'typeId': 'contact', 'displayName': 'Mia'},
        'c2': {'id': 'c2', 'typeId': 'contact', 'displayName': 'Mia'},
      };
      expect(() => _run('recall-facts', {'personName': 'Mia'}, store), throwsA(isA<ResolveError>()));
    });
    test('unknown op', () {
      final s = {'skillId': 'x', 'steps': {'main': [{'op': 'teleport'}]}};
      expect(() => _i().resolve(s, {}, _store()), throwsA(isA<ResolveError>()));
    });
    test('format renders an unknown placeholder as empty (no {var} leak to the user)', () {
      final s = {'skillId': 'x', 'steps': {'main': [
        {'op': 'format', 'template': 'hi {missing}', 'into': 'confirmationText'}
      ]}};
      final p = _i().resolve(s, {}, _store());
      expect(p.confirmation, 'hi ');
    });
  });

  group('execute — before-images (undo correctness)', () {
    test('created record -> before is null', () {
      final store = _store();
      final (p, before) = _run('create-task', {'description': 'x'}, store);
      expect(before[p.writes.first['id']], isNull);
    });
    test('overwritten record -> before is the prior state', () {
      final store = <String, Map<String, dynamic>>{};
      final i = _i();
      final p = i.resolve(_skills['create-task']!, {'description': 'new'}, store);
      final id = p.writes.first['id'] as String;
      // put a prior record at the minted id so the write overwrites it
      store[id] = <String, dynamic>{'id': id, 'typeId': 'task', 'description': 'prior'};
      final before = i.execute(p, store);
      expect(before[id], isNotNull);
      expect(before[id]!['description'], 'prior');
    });
  });
}
