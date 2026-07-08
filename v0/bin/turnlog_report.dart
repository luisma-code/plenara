/// Plenara v0 — print a summary of the device-local turnlog (dogfood telemetry).
///
///   dart run bin/turnlog_report.dart                # summary of the configured turnlog
///   dart run bin/turnlog_report.dart <path.jsonl>   # summary of a specific turnlog
///   dart run bin/turnlog_report.dart --errors       # full trace of every failed/clarify turn
///   dart run bin/turnlog_report.dart --trace [N]    # full trace of the last N turns (default 25)
library;

import 'dart:convert';
import 'dart:io';

import 'package:plenara/config.dart';
import 'package:plenara/turnlog.dart';

void main(List<String> args) {
  final flags = args.where((a) => a.startsWith('--')).toSet();
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final path = positional.isNotEmpty && !RegExp(r'^\d+$').hasMatch(positional.first)
      ? positional.first
      : '${loadConfig().dataDir}/turnlog.jsonl';
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
  }).toList();

  if (flags.contains('--errors')) {
    final bad = turns.where(isTroubleTurn).toList();
    print('($path) — ${bad.length} failed/clarify/OOD turns of ${turns.length}\n');
    for (final t in bad) {
      print(formatTurnTrace(t));
    }
  } else if (flags.contains('--trace')) {
    final n = int.tryParse(positional.firstWhere((a) => RegExp(r'^\d+$').hasMatch(a), orElse: () => '')) ?? 25;
    final recent = turns.length > n ? turns.sublist(turns.length - n) : turns;
    print('($path) — last ${recent.length} of ${turns.length} turns\n');
    for (final t in recent) {
      print(formatTurnTrace(t));
    }
  } else {
    print('($path)\n');
    print(formatSummary(summarizeTurns(turns)));
  }
}
