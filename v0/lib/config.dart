/// Plenara v0 — runtime configuration for real (dogfood) use. Resolves where the
/// user's data lives and the BYOK key, so the app runs on the user's own synced
/// folder + key instead of a hardcoded repo path. Resolution order:
///   env override  >  user config file  >  first-run default (scaffolded to edit).
library;

import 'dart:convert';
import 'dart:io';

import 'store.dart' show writeJsonAtomic;

enum ConfigValueSource { environment, file, secureStore, absent }

class PlenaraConfig {
  final String dataDir;
  final String? apiKey;
  final ConfigValueSource apiKeySource;

  /// Free (offline-only) mode: when true, the app runs with NO cloud client even if a
  /// key is configured — every cloud feature (residual routing, generative, authoring)
  /// degrades to its offline path, so there is zero Anthropic spend. A dev/testing switch
  /// for now; a real release would ship separate free/paid binaries instead.
  final bool freeTier;

  /// Plena's voice pref. `null` = the user hasn't chosen yet (first run) → the app asks once,
  /// so audio never blasts unbidden on a cold launch. `true`/`false` = the remembered choice.
  final bool? voiceMuted;

  /// Chosen TTS voice NAME (e.g. "Matilda (Premium)"), as reported by the engine. `null` = let the
  /// app auto-pick the most natural installed voice. Lets the user override the auto-pick (e.g. a
  /// preferred accent) from Settings → Voice. Matched by name against the installed voices at launch;
  /// if it's no longer installed, the app falls back to auto-pick.
  final String? voiceName;

  /// How many capture sessions have shown the "tap when you're done" affordance line. Capture is
  /// user-delimited (tap to start, tap to stop), so the gesture has to be taught — but only for the
  /// first few sessions, and the count must survive relaunch or the hint never stops appearing.
  final int micHintsShown;

  /// Ask before spending on a paid cloud build ("that's a custom build — want me to?").
  /// DEFAULT FALSE: the ask was friction on every single custom capability, and the user already
  /// said what they wanted. Turn it on in Settings to get a yes/no before each paid authoring call.
  final bool confirmCloudSpend;

  /// Stops Plena's ambient particle motion independently of the operating
  /// system's Reduce Motion preference. State remains legible as a still form.
  final bool stillPresence;
  PlenaraConfig(this.dataDir, this.apiKey,
      {this.freeTier = false,
      this.apiKeySource = ConfigValueSource.absent,
      this.voiceMuted,
      this.voiceName,
      this.micHintsShown = 0,
      this.confirmCloudSpend = false,
      this.stillPresence = false});
}

/// App-injected home base. Desktop leaves this null — USERPROFILE/HOME are set. iOS and Android
/// expose NO such env var, so without an override `_home()` collapses to `'.'` and every `~/…` path
/// becomes a non-writable `./…` (which is exactly what white-screened the first iOS build:
/// `loadConfig` tried to create `./.plenara` → "operation not permitted"). The Flutter app resolves
/// the real per-user directory via path_provider and sets this BEFORE any config/log path is derived.
String? homeOverride;
String _home() =>
    homeOverride ??
    Platform.environment['USERPROFILE'] ??
    Platform.environment['HOME'] ??
    '.';

/// The user config file location (`~/.plenara/config.json`), overridable for tests.
String defaultConfigPath() => '${_home()}/.plenara/config.json';

/// The DEVICE-LOCAL (non-synced) app directory — `~/.plenara`, the same home as the
/// config + key. The deviceId and turnlog live here, NOT in the synced [dataDir]: a
/// synced `.device-id` is adopted by a second install and defeats the HLC tie-break,
/// and a synced turnlog re-uploads every turn and conflicts across devices.
String defaultDeviceDir() => '${_home()}/.plenara';

/// The device-local on-device model directory (`~/.plenara/models`). One owner for this path so the
/// app doesn't re-derive `~/.plenara/...` inline (which drifts across OSes). Dart's File/Directory
/// accept `/` on Windows, so this style is canonical.
String modelsDir() => '${defaultDeviceDir()}/models';

/// An explicit config path is a hermetic test/tool seam: unless [environment] is also injected it
/// must not inherit process credentials, whose value a failed matcher could print into logs.
PlenaraConfig loadConfig(
    {String? configPath, Map<String, String>? environment}) {
  final env = environment ??
      (configPath == null ? Platform.environment : const <String, String>{});
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
      '_hint': 'Set dataDir to your synced folder. The Flutter app stores its API key in the '
          'platform secure store; apiKey remains only as a legacy/pure-Dart operator migration seam. '
          'Development env ANTHROPIC_API_KEY / PLENARA_DATA may override these.',
    };
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(cfg));
  }
  // On mobile the container path is unstable (the iOS UUID rotates on reinstall), so NEVER trust a
  // persisted absolute dataDir — it goes dead and points at an inaccessible container. Always derive
  // from the live injected home. Desktop keeps the user's chosen (possibly synced) folder. One source
  // of truth, so buildSession, built-in installation, and Settings all agree.
  final mobile = (Platform.isIOS || Platform.isAndroid) && homeOverride != null;
  final dataDir = env['PLENARA_DATA'] ??
      (mobile
          ? '${_home()}/Plenara'
          : ((cfg['dataDir'] as String?) ?? '${_home()}/Plenara'));
  final envKey = env['ANTHROPIC_API_KEY'];
  final fileKey = cfg['apiKey'] as String?;
  final key = envKey ?? fileKey;
  final keySource = (key == null || key.trim().isEmpty)
      ? ConfigValueSource.absent
      : envKey != null
          ? ConfigValueSource.environment
          : ConfigValueSource.file;
  // env PLENARA_FREE=1 forces offline mode (handy for tests/demos); else the persisted flag.
  final free = env['PLENARA_FREE'] == '1' || cfg['freeTier'] == true;
  final vm = cfg['voiceMuted'];
  final vn = cfg['voiceName'];
  final mh = cfg['micHintsShown'];
  final cs = cfg['confirmCloudSpend'];
  final sp = cfg['stillPresence'];
  return PlenaraConfig(
      dataDir, (key != null && key.trim().isNotEmpty) ? key.trim() : null,
      apiKeySource: keySource,
      freeTier: free,
      voiceMuted: vm is bool ? vm : null,
      voiceName: vn is String && vn.isNotEmpty ? vn : null,
      micHintsShown: mh is int ? mh : 0,
      confirmCloudSpend: cs is bool ? cs : false,
      stillPresence: sp is bool ? sp : false);
}

/// Persist config edits from the in-app settings surface (Spec 07 §2.6): merges into the
/// existing `~/.plenara/config.json`, preserving unknown keys. [apiKey] null leaves the legacy
/// field untouched; an empty string clears it. The Flutter app never writes a non-empty value here:
/// it uses CredentialStore and this field exists only for verified migration and pure-Dart tools.
void saveConfig(
    {String? dataDir,
    String? apiKey,
    bool? freeTier,
    bool? voiceMuted,
    String? voiceName,
    int? micHintsShown,
    bool? confirmCloudSpend,
    bool? stillPresence,
    String? configPath}) {
  final f = File(configPath ?? defaultConfigPath());
  Map<String, dynamic> cfg = {};
  if (f.existsSync()) {
    try {
      cfg = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {/* malformed -> start fresh */}
  }
  // Only persist dataDir when explicitly given — a caller updating just a pref (e.g. the mute
  // toggle) must NOT bake a resolved PLENARA_DATA env override in as the permanent dataDir.
  if (dataDir != null) cfg['dataDir'] = dataDir;
  if (apiKey != null) cfg['apiKey'] = apiKey;
  if (freeTier != null)
    cfg['freeTier'] = freeTier; // null leaves the mode untouched
  if (voiceMuted != null)
    cfg['voiceMuted'] = voiceMuted; // null leaves the pref untouched
  // Empty string clears the override (back to auto-pick); a non-empty name pins that voice; null
  // leaves it untouched.
  if (voiceName != null)
    cfg['voiceName'] = voiceName.isEmpty ? null : voiceName;
  if (micHintsShown != null) cfg['micHintsShown'] = micHintsShown;
  if (confirmCloudSpend != null) cfg['confirmCloudSpend'] = confirmCloudSpend;
  if (stillPresence != null) cfg['stillPresence'] = stillPresence;
  f.parent.createSync(recursive: true);
  // ATOMIC. loadConfig degrades a malformed config to defaults, which is the right call for a
  // hand-edited file — but it means a torn write silently loses dataDir and the API key, and the
  // app then opens against a fresh empty folder. To the user that is indistinguishable from
  // losing all their data.
  writeJsonAtomic(f, cfg);
}

/// Install and upgrade the shipped capability definitions without touching
/// authored definitions or same-version user edits. Missing built-ins are added
/// on every launch; a built-in type advances only when its shipped schemaVersion
/// is newer, after preserving the exact prior definition in `.seed-backups`.
/// Records migrate later through Session's normal contiguous migration path.
///
/// True iff [dataDir] already holds at least one capability definition. This is
/// a display/setup hint only: it must never be used to skip built-in upgrades.
bool isSeeded(String dataDir) {
  final types = Directory('$dataDir/types');
  return types.existsSync() && types.listSync().whereType<File>().isNotEmpty;
}

void ensureSeeded(String dataDir, String sourceDir) {
  // FAIL LOUDLY if the shipped seed data isn't where we expect — otherwise a mis-configured install
  // silently creates empty dirs and boots with ZERO capabilities (every utterance clarify-fails).
  // NOTE (pre-distribution): the app still points sourceDir at a dev path; before shipping, bundle
  // data/ as Flutter assets and seed from rootBundle so this works on any machine (see HANDOFF).
  if (!Directory('$sourceDir/types').existsSync()) {
    throw StateError(
        'Plenara cannot find its built-in capability data at "$sourceDir". '
        'The app is not installed correctly (seed data missing).');
  }
  for (final sub in const [
    'types',
    'skills',
    'templates',
    'automations',
    'reference'
  ]) {
    final dst = Directory('$dataDir/$sub')..createSync(recursive: true);
    final src = Directory('$sourceDir/$sub');
    if (!src.existsSync()) continue;
    for (final file in src.listSync().whereType<File>()) {
      if (file.path.endsWith('.json')) {
        final name = file.path.replaceAll('\\', '/').split('/').last;
        final target = File('${dst.path}/$name');
        if (!target.existsSync()) {
          file.copySync(target.path);
          continue;
        }
        if (sub != 'types') continue;
        try {
          final shipped =
              jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          final installed =
              jsonDecode(target.readAsStringSync()) as Map<String, dynamic>;
          final shippedVersion = shipped['schemaVersion'];
          final encodedInstalledVersion = installed['schemaVersion'];
          final installedVersion =
              encodedInstalledVersion is int ? encodedInstalledVersion : 1;
          if (shipped['typeId'] != installed['typeId'] ||
              shippedVersion is! int ||
              shippedVersion < installedVersion) {
            continue;
          }
          final versionLabel = encodedInstalledVersion is int
              ? 'v$installedVersion'
              : 'legacy-v1';
          final backup = File(
            '$dataDir/.seed-backups/types/$name.$versionLabel.json',
          );
          if ((shippedVersion > installedVersion ||
                  encodedInstalledVersion is! int) &&
              !backup.existsSync()) {
            backup.parent.createSync(recursive: true);
            target.copySync(backup.path);
          }
          if (shippedVersion > installedVersion) {
            writeJsonAtomic(target, shipped);
          } else if (encodedInstalledVersion is! int) {
            installed['schemaVersion'] = installedVersion;
            writeJsonAtomic(target, installed);
          }
        } catch (_) {
          // A malformed installed definition belongs to the repair surface; do
          // not erase it under the guise of an upgrade.
        }
      }
    }
  }
  final corpus = File('$sourceDir/corpus.json');
  final installedCorpus = File('$dataDir/corpus.json');
  if (corpus.existsSync() && !installedCorpus.existsSync()) {
    corpus.copySync(installedCorpus.path);
  }
  Directory('$dataDir/records').createSync(recursive: true);
}
