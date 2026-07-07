/// Plenara v0 — print a summary of the device-local turnlog (dogfood telemetry).
///
///   dart run bin/turnlog_report.dart                # the configured data dir's turnlog
///   dart run bin/turnlog_report.dart <path.jsonl>   # a specific turnlog
library;

import 'dart:convert';
import 'dart:io';

import 'package:plenara/config.dart';
import 'package:plenara/turnlog.dart';

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : '${loadConfig().dataDir}/turnlog.jsonl';
  final file = File(path);
  if (!file.existsSync()) {
    print('No turnlog at $path — use the app/console first, or pass a path.');
    return;
  }
  final turns = file.readAsLinesSync().where((l) => l.trim().isNotEmpty).map((l) {
    try {
      return jsonDecode(l) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{}; // skip a corrupt/half-written line, don't abort
    }
  });
  print('($path)\n');
  print(formatSummary(summarizeTurns(turns)));
}
