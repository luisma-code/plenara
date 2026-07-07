/// Plenara v0 — records real Haiku responses for the canonical cloud-path inputs
/// (lib/fixture_inputs.dart) into test/fixtures/cloud.json. Run ONCE (costs a few
/// BYOK Haiku calls), commit the fixture; tests then replay it offline.
///
///   dart run bin/record_fixtures.dart
library;

import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/fixture_inputs.dart';
import 'package:plenara/replay_cloud.dart';
import 'package:plenara/session.dart';
import 'package:plenara/store.dart';

/// A throwaway data dir (copy of types + skills + corpus.json) so authoring writes
/// don't touch the real seed data.
String _tempData() {
  final tmp = Directory.systemTemp.createTempSync('plenara_rec_');
  for (final sub in const ['types', 'skills']) {
    final dst = Directory('${tmp.path}/$sub')..createSync(recursive: true);
    for (final f in Directory('data/$sub').listSync().whereType<File>()) {
      f.copySync('${dst.path}/${f.path.replaceAll('\\', '/').split('/').last}');
    }
  }
  File('data/corpus.json').copySync('${tmp.path}/corpus.json');
  Directory('${tmp.path}/records').createSync();
  return tmp.path;
}

Future<void> main() async {
  final skills = loadDefs('data/skills', 'skillId');
  final real = ClaudeClient();
  if (!real.available) {
    print('No API key available (env ANTHROPIC_API_KEY or the rig .env) — cannot record.');
    return;
  }
  final rec = RecordingCloud(real);

  print('--- residual routing (${allResidualUtterances.length} utterances) ---');
  for (final u in allResidualUtterances) {
    final r = await rec.routeResidual(u, skills); // RecordingCloud throws on a CloudError
    final route = (r as CloudOk<Map<String, dynamic>?>).value;
    print('  route  "$u" -> ${route?['skillId'] ?? 'none'}');
  }

  // Authoring: drive the REAL Session authoring path (incl. its validate→retry loop)
  // so the recorded keys — including any priorError retry — are EXACTLY what replay
  // requests. A first-attempt out-of-vocab fn (a known Haiku flake) is then recorded
  // together with its priorError-corrected retry, instead of failing the suite.
  print('--- authoring via Session (${authoringDescriptions.length} descriptions) ---');
  final clock = DateTime.parse('2026-07-06T09:00:00');
  for (final d in authoringDescriptions) {
    final s = Session(_tempData(), clock: clock, cloud: rec);
    await s.init(retrieval: false);
    final resp = await s.handle('start tracking $d'); // def-triggered authoring
    print('  author "$d" -> $resp');
  }

  rec.save('test/fixtures/cloud.json');
  print('\nsaved ${rec.recorded.length} fixtures to test/fixtures/cloud.json');
}
