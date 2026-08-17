/// Runs the 60-example Spec 05a suite through test's JSON protocol and derives
/// pass/skip totals from the actual result events. No hand-maintained tally.
library;

import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    const ['test', 'test/spec05a_test.dart', '--reporter=json'],
    workingDirectory: Directory.current.path,
  );
  final names = <int, String>{};
  final totals = <String, List<int>>{
    'F': [0, 0],
    'P': [0, 0],
    'DF': [0, 0],
    'DP': [0, 0],
  }; // tier -> [pass, skip]
  final errors = StringBuffer();
  await Future.wait([
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          final event = jsonDecode(line) as Map<String, dynamic>;
          if (event['type'] == 'testStart') {
            final test = event['test'] as Map<String, dynamic>;
            names[test['id'] as int] = test['name'] as String;
          } else if (event['type'] == 'testDone' && event['hidden'] != true) {
            final name = names[event['testID'] as int] ?? '';
            final match = RegExp(r'\b(DF|DP|F|P)-(\d\d)\b').firstMatch(name);
            if (match == null) return;
            final bucket = totals[match.group(1)]!;
            if (event['skipped'] == true) {
              bucket[1]++;
            } else if (event['result'] == 'success') {
              bucket[0]++;
            }
          }
        }),
    process.stderr.transform(utf8.decoder).forEach(errors.write),
  ]);
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    stderr.write(errors);
    stderr.writeln('Spec 05a conformance suite failed.');
    exit(exitCode);
  }

  var passing = 0;
  var skipped = 0;
  for (final tier in const ['F', 'P', 'DF', 'DP']) {
    final counts = totals[tier]!;
    passing += counts[0];
    skipped += counts[1];
    print('$tier: ${counts[0]} pass / ${counts[1]} skip');
  }
  if (passing + skipped != 60) {
    stderr.writeln(
      'CONFORMANCE INSTRUMENT ERROR: counted ${passing + skipped}/60 examples.',
    );
    exit(2);
  }
  final baseline = int.parse(File('test/conformance-baseline.txt').readAsStringSync().trim());
  print('TOTAL: $passing pass / $skipped skip of 60 (baseline $baseline)');
  if (passing < baseline) {
    stderr.writeln('CONFORMANCE REGRESSED ($passing < $baseline)');
    exit(1);
  }
  if (passing > baseline) {
    stderr.writeln(
      'CONFORMANCE IMPROVED: update test/conformance-baseline.txt to $passing.',
    );
    exit(1);
  }
}
