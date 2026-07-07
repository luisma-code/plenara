/// Plenara v0 — records real Haiku responses for the canonical cloud-path inputs
/// (lib/fixture_inputs.dart) into test/fixtures/cloud.json. Run ONCE (costs a few
/// BYOK Haiku calls), commit the fixture; tests then replay it offline.
///
///   dart run bin/record_fixtures.dart
library;

import 'package:plenara/claude.dart';
import 'package:plenara/fixture_inputs.dart';
import 'package:plenara/replay_cloud.dart';
import 'package:plenara/store.dart';

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

  print('--- authoring (${authoringDescriptions.length} descriptions) ---');
  for (final d in authoringDescriptions) {
    final r = await rec.authorCapability(d);
    final authored = (r as CloudOk<Map<String, dynamic>?>).value;
    print('  author "$d" -> ${(authored?['skill'] as Map?)?['skillId'] ?? 'FAILED'}');
  }

  rec.save('test/fixtures/cloud.json');
  print('\nsaved ${rec.recorded.length} fixtures to test/fixtures/cloud.json');
}
