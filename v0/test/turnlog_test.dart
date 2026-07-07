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
}
