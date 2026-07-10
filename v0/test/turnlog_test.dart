/// The dogfood instrument (turnlog aggregation) — the numbers that make skill/NLU
/// decisions measurement-driven rather than guessed.
import 'package:plenara/turnlog.dart';
import 'package:test/test.dart';

void main() {
  final turns = <Map<String, dynamic>>[
    {'source': 'corpus', 'skill': 'create-task'},
    {'source': 'corpus', 'skill': 'list-tasks'},
    {'source': 'cloud', 'skill': 'log-run', 'cloud': 'ok'},
    {'source': 'clarify', 'cloud': 'badKey'},
    {'source': 'clarify'},
    {'source': 'undo'},
  ];

  test('dailyUsage buckets turns by day with cloud calls + cost, most recent first', () {
    final t = <Map<String, dynamic>>[
      {'source': 'corpus', 'at': '2026-07-09T10:00:00'},
      {'source': 'cloud', 'at': '2026-07-10T09:00:00', 'cost': {'in': 100, 'out': 20, 'usd': 0.0002}},
      {'source': 'cloud', 'at': '2026-07-10T11:00:00', 'cost': {'in': 200, 'out': 40, 'usd': 0.0004}},
    ];
    final days = dailyUsage(t);
    expect(days.first.date, '2026-07-10'); // most recent first
    expect(days.first.turns, 2);
    expect(days.first.cloudCalls, 2);
    expect(days.first.costUsd, closeTo(0.0006, 1e-9));
    expect(days.last.date, '2026-07-09');
    expect(days.last.cloudCalls, 0); // an offline day
  });

  test('summarizeTurns counts sources, cloud health, and skills', () {
    final s = summarizeTurns(turns);
    expect(s.total, 6);
    expect(s.bySource['corpus'], 2);
    expect(s.bySource['clarify'], 2);
    expect(s.byCloud['ok'], 1);
    expect(s.byCloud['badKey'], 1);
    expect(s.bySkill['create-task'], 1);
    expect(s.rate('clarify'), closeTo(2 / 6, 1e-9));
  });

  test('formatSummary reports totals, clarify rate, cloud health, top skills', () {
    final r = formatSummary(summarizeTurns(turns));
    expect(r, contains('6 turns'));
    expect(r, contains('Clarify rate'));
    expect(r, contains('badKey'));
    expect(r, contains('create-task'));
  });

  test('an empty turnlog reports empty, never divides by zero', () {
    expect(formatSummary(summarizeTurns([])), contains('empty'));
    expect(summarizeTurns([]).rate('clarify'), 0);
  });

  test('cost: sums spend across paid turns and derives spend-per-active-day', () {
    final t = <Map<String, dynamic>>[
      {'source': 'corpus', 'at': '2026-07-07T09:00:00'}, // free
      {'source': 'cloud', 'at': '2026-07-07T09:01:00', 'cost': {'in': 1000, 'out': 40, 'usd': 0.0012}},
      {'source': 'cloud', 'at': '2026-07-08T10:00:00', 'cost': {'in': 175, 'out': 150, 'usd': 0.000925}},
    ];
    final s = summarizeTurns(t);
    expect(s.paidCalls, 2);
    expect(s.activeDays, 2);
    expect(s.spendUsd, closeTo(0.002125, 1e-9));
    expect(s.spendPerDayUsd, closeTo(0.0010625, 1e-9)); // total / 2 days
    final r = formatSummary(s);
    expect(r, contains('Estimated API spend'));
    expect(r, contains('/day'));
    expect(r, contains('/month'));
  });

  test('formatTurnTrace renders a diagnosable one-turn trace', () {
    final line = formatTurnTrace({
      'utterance': 'add buy milk to my list',
      'source': 'corpus',
      'skill': 'create-task',
      'ms': 3,
      'template': 'add {description:text} to my {_:text}',
      'slots': {'description': 'buy milk', '_': 'list'},
      'writes': [{'op': 'write', 'id': 't-1', 'typeId': 'task'}],
      'response': 'Added "buy milk" to your tasks.',
    });
    expect(line, contains('add buy milk to my list'));
    expect(line, contains('corpus/create-task'));
    expect(line, contains('template:'));
    expect(line, contains('buy milk'));
    expect(line, contains('task'));
  });

  test('formatTurnTrace surfaces the error line for a crashed turn', () {
    final line = formatTurnTrace({'utterance': 'x', 'source': 'error', 'error': 'StateError: boom\n#0 …'});
    expect(line, contains('ERROR: StateError: boom'));
    expect(line, isNot(contains('#0'))); // only the first line, not the whole stack
  });

  test('isTroubleTurn flags failed/clarify/OOD turns, not a clean route', () {
    expect(isTroubleTurn({'source': 'error', 'error': 'X'}), isTrue);
    expect(isTroubleTurn({'source': 'clarify'}), isTrue);
    expect(isTroubleTurn({'source': 'out-of-domain'}), isTrue);
    expect(isTroubleTurn({'source': 'corpus', 'skill': 'create-task'}), isFalse);
  });
}
