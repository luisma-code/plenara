// Plenara dogfood CLI — drive the REAL assistant from the command line.
//
// It builds the exact same Session the desktop app does (your real synced data
// folder, your BYOK key, the device-local ~/.plenara for turnlog), so an utterance
// typed here is routed, interpreted, and stored identically to the app. This is the
// easy dogfood loop: feed it input, read back the reply — no copy/paste.
//
//   echo "I had dinner with Sam tonight" | dart run bin/dogfood.dart
//   dart run bin/dogfood.dart "add milk to my list"      # one-shot, from args
//   dart run bin/dogfood.dart                            # interactive REPL (type, Enter)
//   printf 'log a 5k run\nwhat did i do today\n' | dart run bin/dogfood.dart -v
//
// Flags:
//   -v, --verbose   after each reply, show route (source/skill/cost) + what records changed
//   --temp          use a FRESH seeded temp folder instead of your real data (safe sandbox)
//   --show          dump all records at the end
// Input: utterances from the args, else one-per-line from stdin. Blank lines are
// skipped; a line starting with '#' is echoed as a comment (handy in scripted runs).
import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';
import 'package:plenara/session.dart';

const _sourceData = r'Z:\code\plenara\v0\data';

Map<String, int> _byType(Session s) {
  final m = <String, int>{};
  for (final r in s.store.values) {
    if (r['deleted'] == true) continue;
    m[r['typeId'] as String? ?? '?'] = (m[r['typeId']] ?? 0) + 1;
  }
  return m;
}

String _diff(Map<String, int> before, Map<String, int> after) {
  final parts = <String>[];
  for (final k in {...before.keys, ...after.keys}.toList()..sort()) {
    final d = (after[k] ?? 0) - (before[k] ?? 0);
    if (d != 0) parts.add('${d > 0 ? '+' : ''}$d $k');
  }
  return parts.isEmpty ? 'no records changed' : parts.join(', ');
}

Future<void> main(List<String> argv) async {
  final verbose = argv.contains('-v') || argv.contains('--verbose');
  final temp = argv.contains('--temp');
  final show = argv.contains('--show');
  final utterances = argv.where((a) => !a.startsWith('-')).toList();

  final cfg = loadConfig();
  final String dataDir;
  if (temp) {
    dataDir = Directory.systemTemp.createTempSync('plenara_dogfood_').path;
    ensureSeeded(dataDir, _sourceData);
  } else {
    dataDir = cfg.dataDir;
    ensureSeeded(dataDir, _sourceData); // idempotent — only seeds an empty folder
  }

  // Mirror the app's buildSession: real key unless free mode, explicit keyless client offline.
  final useCloud = cfg.apiKey != null && !cfg.freeTier;
  final session = Session(
    dataDir,
    cloud: useCloud ? ClaudeClient(apiKeyOverride: cfg.apiKey) : ClaudeClient(apiKeyOverride: ''),
    deviceDir: temp ? null : defaultDeviceDir(),
  );
  await session.init(retrieval: false);

  final loc = temp ? 'temp sandbox: $dataDir' : dataDir;
  stderr.writeln('[plenara] data: $loc  cloud: ${useCloud ? 'on' : 'OFF (free/no-key)'}  '
      'records: ${session.store.values.where((r) => r['deleted'] != true).length}');

  Future<void> turn(String u) async {
    u = u.trim();
    if (u.isEmpty) return;
    if (u.startsWith('#')) {
      stdout.writeln(u);
      return;
    }
    final before = _byType(session);
    final reply = await session.handle(u);
    stdout.writeln('> $u');
    stdout.writeln(reply);
    // Always report whether the turn stayed on-device or reached the cloud back end
    // (lastTurnUsedCloud = real Anthropic tokens spent this turn). -v adds the route + diff.
    final where = session.lastTurnUsedCloud ? 'cloud (back end)' : 'offline (on-device)';
    if (verbose) {
      stdout.writeln('   [$where · source=${session.lastSource} · ${_diff(before, _byType(session))}]');
    } else {
      stdout.writeln('   [$where]');
    }
    stdout.writeln('');
  }

  if (utterances.isNotEmpty) {
    for (final u in utterances) {
      await turn(u);
    }
  } else {
    // REPL / pipe: one utterance per line until EOF.
    while (true) {
      final line = stdin.readLineSync();
      if (line == null) break;
      await turn(line);
    }
  }

  if (show) {
    stdout.writeln('--- records (${_byType(session)}) ---');
    for (final r in session.store.values.where((r) => r['deleted'] != true)) {
      stdout.writeln('  ${r['typeId']}: ${Map.of(r)..remove('_hlc')}');
    }
  }
}
