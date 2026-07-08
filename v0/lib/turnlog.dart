/// Plenara v0 — turnlog aggregation (the dogfood instrument, Spec 03 §7.3). The
/// engine appends one JSON line per turn (source, skill, cloud health); this
/// summarizes it so skill/NLU decisions are measurement-driven, not guessed. The
/// make-or-break metric is the CLARIFY rate — how often the app failed to act.
library;

class TurnlogSummary {
  final int total;
  final Map<String, int> bySource; // corpus | cloud | correction | undo | help | authored | clarify | error
  final Map<String, int> byCloud; // ok | offline | badKey | rateLimited | ...
  final Map<String, int> bySkill;
  TurnlogSummary(this.total, this.bySource, this.byCloud, this.bySkill);

  double rate(String source) => total == 0 ? 0 : (bySource[source] ?? 0) / total;
}

TurnlogSummary summarizeTurns(Iterable<Map<String, dynamic>> turns) {
  final bySource = <String, int>{}, byCloud = <String, int>{}, bySkill = <String, int>{};
  var total = 0;
  for (final t in turns) {
    total++;
    final s = t['source']?.toString() ?? 'unknown';
    bySource[s] = (bySource[s] ?? 0) + 1;
    final c = t['cloud']?.toString();
    if (c != null) byCloud[c] = (byCloud[c] ?? 0) + 1;
    final sk = t['skill']?.toString();
    if (sk != null) bySkill[sk] = (bySkill[sk] ?? 0) + 1;
  }
  return TurnlogSummary(total, bySource, byCloud, bySkill);
}

String formatSummary(TurnlogSummary s) {
  if (s.total == 0) return 'Turnlog is empty — no turns recorded yet.';
  String pct(int n) => '${(100 * n / s.total).toStringAsFixed(1)}%';
  List<MapEntry<String, int>> desc(Map<String, int> m) =>
      m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final sb = StringBuffer('Turnlog summary — ${s.total} turns\n\nHow turns resolved:\n');
  for (final e in desc(s.bySource)) {
    sb.writeln('  ${e.key.padRight(12)} ${e.value.toString().padLeft(5)}  ${pct(e.value)}');
  }
  if (s.byCloud.isNotEmpty) {
    sb.write('\nCloud health (turns that consulted the cloud):\n');
    for (final e in desc(s.byCloud)) {
      sb.writeln('  ${e.key.padRight(12)} ${e.value.toString().padLeft(5)}');
    }
  }
  if (s.bySkill.isNotEmpty) {
    sb.write('\nTop skills:\n');
    for (final e in desc(s.bySkill).take(10)) {
      sb.writeln('  ${e.key.padRight(22)} ${e.value.toString().padLeft(5)}');
    }
  }
  sb.write('\nClarify rate: ${pct(s.bySource['clarify'] ?? 0)}  (the make-or-break metric — lower is better)');
  return sb.toString();
}

/// One turn as a human-readable debug trace — enough to diagnose a bad turn from the log
/// without re-running it (utterance -> route path, template, slots, record ops, response,
/// and the first line of any error). Used by `turnlog_report --trace` / `--errors`.
String formatTurnTrace(Map<String, dynamic> t) {
  final head = StringBuffer('• "${t['utterance']}"  [${t['source']}');
  if (t['skill'] != null) head.write('/${t['skill']}');
  if (t['ms'] != null) head.write(', ${t['ms']}ms');
  head.write(']');
  final sb = StringBuffer('$head\n');
  if (t['template'] != null) sb.writeln('    template: ${t['template']}');
  if (t['slots'] != null) sb.writeln('    slots:    ${t['slots']}');
  if (t['cloud'] != null) sb.writeln('    cloud:    ${t['cloud']}');
  if (t['diag'] != null) sb.writeln('    diag:     ${t['diag']}'); // WHY a miss (corpus/cloud/nearest)
  if (t['writes'] != null) sb.writeln('    writes:   ${t['writes']}');
  if (t['automations'] != null) sb.writeln('    automations: ${t['automations']}'); // unattended fires this turn
  if (t['response'] != null) sb.writeln('    -> ${t['response']}');
  if (t['error'] != null) sb.writeln('    ERROR: ${t['error'].toString().split('\n').first}');
  return sb.toString();
}

/// True if a turn is worth surfacing in a `--errors` view (failed to act or crashed).
bool isTroubleTurn(Map<String, dynamic> t) =>
    t.containsKey('error') || t['source'] == 'error' || t['source'] == 'clarify' || t['source'] == 'out-of-domain';
