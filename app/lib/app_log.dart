/// Plenara app — diagnostics log. Opens a timestamped .log in the system temp
/// folder at startup and prints its full path to stdout, so a manual test that
/// goes wrong can be diagnosed from the file (not by guessing). Captures boot,
/// every Session.init phase, every turn, and any uncaught/Flutter error — each
/// line flushed immediately, so even a hard hang leaves the last event on disk.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

class AppLog {
  final File file;
  AppLog._(this.file);

  /// Verbose traces (speech lifecycle, and other chatty per-interaction diagnostics) are ON during
  /// development + dogfood and OFF in a retail release build — unless the user opts in with
  /// PLENARA_DEBUG=1. Essential events (boot, init phases, turns, errors) ALWAYS log via [log].
  /// This is the "rich traces we can turn off in retail" switch: log everything now, quiet later.
  static bool verbose = !kReleaseMode || Platform.environment['PLENARA_DEBUG'] == '1';

  static AppLog? _instance;
  static AppLog get instance => _instance ??= _create();

  static AppLog _create() {
    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}plenara-logs');
    try {
      dir.createSync(recursive: true);
    } catch (_) {}
    // sortable, filename-safe timestamp; newest file = latest run
    final ts = DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-');
    final f = File('${dir.path}${Platform.pathSeparator}plenara-$ts.log');
    try {
      f.writeAsStringSync('=== Plenara diagnostics — ${DateTime.now()} ===\n');
    } catch (_) {}
    return AppLog._(f);
  }

  void log(String msg) {
    final line = '${DateTime.now().toIso8601String()}  $msg\n';
    try {
      file.writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// A verbose trace — written only when [verbose] is on (dev/dogfood), silent in retail.
  void debug(String msg) {
    if (verbose) log(msg);
  }

  void call(String msg) => log(msg);
}
