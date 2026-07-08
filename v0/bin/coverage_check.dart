/// Plenara v0 — coverage gate (Spec 09 §8, O1). Reads `coverage/lcov.info`, prints per-file
/// line coverage (worst first) + the total, and exits non-zero if the total is below the floor
/// (default 80%, the Spec 09 §8 global target). The CI/quality primitive; ratchet-only in intent.
///
/// Run:
///   dart test --coverage=coverage
///   dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info \
///       --report-on=lib --packages=.dart_tool/package_config.json
///   dart bin/coverage_check.dart [floorPercent]
library;

import 'dart:io';

void main(List<String> args) {
  final floor = args.isNotEmpty ? double.parse(args.first) : 80.0;
  final f = File('coverage/lcov.info');
  if (!f.existsSync()) {
    stderr.writeln('coverage/lcov.info not found — run `dart test --coverage=coverage` + format_coverage first.');
    exit(2);
  }
  var totalLines = 0, hitLines = 0;
  String? sf;
  var lf = 0, lh = 0;
  final perFile = <String, List<int>>{}; // path -> [hit, found]
  for (final line in f.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      sf = line.substring(3);
      lf = 0;
      lh = 0;
    } else if (line.startsWith('LF:')) {
      lf = int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      lh = int.parse(line.substring(3));
      final key = sf;
      if (key != null) perFile[key] = [lh, lf];
      totalLines += lf;
      hitLines += lh;
    }
  }
  double pct(List<int> v) => v[1] == 0 ? 100.0 : 100 * v[0] / v[1];
  final entries = perFile.entries.toList()..sort((a, b) => pct(a.value).compareTo(pct(b.value)));
  for (final e in entries) {
    final name = e.key.split(RegExp(r'[\\/]')).last;
    print('${pct(e.value).toStringAsFixed(1).padLeft(6)}%  $name  (${e.value[0]}/${e.value[1]})');
  }
  final total = totalLines == 0 ? 0.0 : 100 * hitLines / totalLines;
  print('\nTOTAL: ${total.toStringAsFixed(1)}% ($hitLines/$totalLines lines) — floor ${floor.toStringAsFixed(0)}%');
  if (total < floor) {
    stderr.writeln('COVERAGE BELOW FLOOR (${total.toStringAsFixed(1)}% < ${floor.toStringAsFixed(0)}%)');
    exit(1);
  }
  print('OK — coverage floor met.');
}
