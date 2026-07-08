/// Plenara v0 — import-lint layering gate (Spec 09 §8.4 step 5; the research §9 dependency rule;
/// the standing CLAUDE.md promise "dependency rule enforced by import-lint"). No `lib/` file may
/// import a HIGHER architectural layer. Layers (Spec 04 §2's row): util(0) < storage(1) ==
/// intelligence(1) < business-logic/orchestration(2). The UI (the `app` package) sits above all
/// and depends only on `package:plenara`, so it is not part of this intra-package check.
///
/// Run:  dart bin/import_lint.dart   (from v0/)  — exits non-zero on any upward import.
library;

import 'dart:io';

const kRank = <String, int>{
  // util / kernel (no dependencies)
  'cron': 0, 'dates': 0, 'fixture_inputs': 0,
  // storage
  'store': 1, 'storage_repository': 1,
  // intelligence — NLU routing, the cloud seam, retrieval
  'claude': 1, 'router': 1, 'embed': 1, 'replay_cloud': 1,
  // business logic + orchestration
  'interpreter': 2, 'reminders': 2, 'people': 2, 'generative': 2,
  'automations': 2, 'config': 2, 'turnlog': 2, 'session': 2,
};

/// Pure core (testable): the upward-import violations for [graph] (file → its lib imports).
/// An unclassified file is treated as the bottom layer, so ITS upward imports are still caught.
List<String> lintGraph(Map<String, List<String>> graph, [Map<String, int> ranks = kRank]) {
  final violations = <String>[];
  graph.forEach((name, imports) {
    final srcRank = ranks[name] ?? 0;
    for (final target in imports) {
      final tRank = ranks[target];
      if (tRank != null && tRank > srcRank) {
        violations.add('$name (L$srcRank) imports $target (L$tRank) — UPWARD import, forbidden by the §9 dependency rule');
      }
    }
  });
  return violations;
}

void main() {
  final graph = <String, List<String>>{};
  final unclassified = <String>{};
  final importRe = RegExp(r"^import '([a-z_]+)\.dart'");
  for (final f in Directory('lib').listSync().whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final name = f.uri.pathSegments.last.replaceAll('.dart', '');
    if (!kRank.containsKey(name)) unclassified.add(name);
    final imports = <String>[];
    for (final line in f.readAsLinesSync()) {
      final m = importRe.firstMatch(line);
      if (m != null) imports.add(m.group(1)!);
    }
    graph[name] = imports;
  }
  for (final u in unclassified) {
    stderr.writeln('note: unclassified lib file "$u" — add it to bin/import_lint.dart kRank');
  }
  final violations = lintGraph(graph);
  if (violations.isNotEmpty) {
    for (final v in violations) {
      stderr.writeln('VIOLATION: $v');
    }
    exit(1);
  }
  print('import-lint OK — no upward imports across ${kRank.length} classified lib files.');
}
