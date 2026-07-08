/// Plenara v0 — runtime configuration for real (dogfood) use. Resolves where the
/// user's data lives and the BYOK key, so the app runs on the user's own synced
/// folder + key instead of a hardcoded repo path. Resolution order:
///   env override  >  user config file  >  first-run default (scaffolded to edit).
library;

import 'dart:convert';
import 'dart:io';

class PlenaraConfig {
  final String dataDir;
  final String? apiKey;
  PlenaraConfig(this.dataDir, this.apiKey);
}

String _home() => Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';

/// The user config file location (`~/.plenara/config.json`), overridable for tests.
String defaultConfigPath() => '${_home()}/.plenara/config.json';

/// The DEVICE-LOCAL (non-synced) app directory — `~/.plenara`, the same home as the
/// config + key. The deviceId and turnlog live here, NOT in the synced [dataDir]: a
/// synced `.device-id` is adopted by a second install and defeats the HLC tie-break,
/// and a synced turnlog re-uploads every turn and conflicts across devices.
String defaultDeviceDir() => '${_home()}/.plenara';

PlenaraConfig loadConfig({String? configPath}) {
  final f = File(configPath ?? defaultConfigPath());
  Map<String, dynamic> cfg = {};
  if (f.existsSync()) {
    try {
      cfg = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {/* malformed -> fall through to defaults */}
  } else {
    // first run: scaffold a config the user can edit (point at OneDrive, paste key)
    cfg = {
      'dataDir': '${_home()}/Plenara',
      'apiKey': '',
      '_hint': 'Set dataDir to your synced folder (e.g. your OneDrive/Plenara) and '
          'paste your Anthropic API key. Env ANTHROPIC_API_KEY / PLENARA_DATA override these.',
    };
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(cfg));
  }
  final dataDir = Platform.environment['PLENARA_DATA'] ?? (cfg['dataDir'] as String?) ?? '${_home()}/Plenara';
  final key = Platform.environment['ANTHROPIC_API_KEY'] ?? (cfg['apiKey'] as String?);
  return PlenaraConfig(dataDir, (key != null && key.trim().isNotEmpty) ? key.trim() : null);
}

/// Persist config edits from the in-app settings surface (Spec 07 §2.6): merges into the
/// existing `~/.plenara/config.json`, preserving unknown keys. [apiKey] null leaves the key
/// untouched; an empty string clears it. The key is written in plaintext (the accepted v0/dogfood
/// posture — Spec 10 A-08 / G-37 tracks the secure-store follow-up); it is never logged.
void saveConfig({required String dataDir, String? apiKey, String? configPath}) {
  final f = File(configPath ?? defaultConfigPath());
  Map<String, dynamic> cfg = {};
  if (f.existsSync()) {
    try {
      cfg = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {/* malformed -> start fresh */}
  }
  cfg['dataDir'] = dataDir;
  if (apiKey != null) cfg['apiKey'] = apiKey;
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(cfg));
}

/// First-run seeding: copy the shipped built-in capability defs (types, skills,
/// corpus) into [dataDir] if it has none yet, from [sourceDir]. Records, authored
/// defs, and the learned corpus accrete in [dataDir] thereafter — so the whole
/// "capabilities are data" surface lives in the user's own synced folder.
void ensureSeeded(String dataDir, String sourceDir) {
  final types = Directory('$dataDir/types');
  if (types.existsSync() && types.listSync().whereType<File>().isNotEmpty) return; // already seeded
  for (final sub in const ['types', 'skills', 'templates', 'automations']) {
    final dst = Directory('$dataDir/$sub')..createSync(recursive: true);
    final src = Directory('$sourceDir/$sub');
    if (!src.existsSync()) continue;
    for (final file in src.listSync().whereType<File>()) {
      if (file.path.endsWith('.json')) {
        file.copySync('${dst.path}/${file.path.replaceAll('\\', '/').split('/').last}');
      }
    }
  }
  final corpus = File('$sourceDir/corpus.json');
  if (corpus.existsSync()) corpus.copySync('$dataDir/corpus.json');
  Directory('$dataDir/records').createSync(recursive: true);
}
