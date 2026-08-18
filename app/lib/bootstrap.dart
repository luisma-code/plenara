// Process startup and dependency wiring for the Plenara app. `lib/main.dart` is
// the Dart entrypoint and owns the widget tree; this file owns the ORDER in
// which the app comes up (home override → bookmark restore → credentials →
// config/log paths → seed extraction → runApp) and the construction of the
// production [Session]. That ordering is hard-won — see WORK-CAPSULE.md — so
// keep it here, in one place, rather than spread across the UI layer.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';
import 'package:plenara/reminders.dart';
import 'package:plenara/session.dart';
import 'package:plenara/storage_repository.dart';

import 'app_log.dart';
import 'build_channel.dart';
import 'credential_store.dart';
import 'data_location.dart';
import 'macos_scheduler.dart';
import 'seed_assets.dart';
import 'windows_scheduler.dart';

// Dev fallback seed source. A SHIPPED build installs/upgrades from its BUNDLED assets instead —
// main() extracts them each launch and sets _bundledSeedDir (see seed_assets.dart). A dev machine can
// point PLENARA_SEED_DIR at the repo (e.g. macOS: export PLENARA_SEED_DIR="$HOME/code/plenara/v0/data").
const sourceDataDir = r'Z:\code\plenara\v0\data';
// Set by main() when it extracts the bundled seed assets; read by buildSession.
String? _bundledSeedDir;

/// Build the production Session from user config: the real (synced) data folder,
/// installed/upgraded with bundled capabilities, the BYOK key, and the real
/// Windows toast scheduler (reminders now fire as OS notifications, not just on-open
/// nudges). The scheduler self-inits lazily on first schedule/cancel.
/// Pick the OS notification backend for this platform. The single place `Platform.is*` decides a
/// scheduler — add a backend here, not at the call site. A platform with no native backend gets the
/// in-memory FakeScheduler (reminders still reconcile + surface as on-open nudges), logged so a
/// silent downgrade is diagnosable.
NotificationScheduler platformScheduler() {
  if (Platform.isWindows) return WindowsToastScheduler();
  if (Platform.isMacOS) return MacToastScheduler();
  AppLog.instance.log(
    'sched: no native notification backend on this platform — in-app nudges only',
  );
  return FakeScheduler();
}

Session buildSession({NotificationScheduler? scheduler}) {
  final cfg = loadAppConfig();
  AppLog.instance.registerSecret(cfg.apiKey);
  AppLog.instance.log(
    'boot: data root = ${cfg.dataDir} '
    '(${cfg.dataFolderSelected ? 'provider-selected' : 'device-local'})',
  );
  // loadConfig already derives the correct dataDir per platform (live Documents dir on mobile, where
  // the container path is unstable; the user's folder on desktop) — one source of truth, so this and
  // main()'s bundled-definition extraction agree.
  final dataDir = cfg.dataDir;
  // Seed source priority: explicit dev override > extracted bundled assets (shipped build) > dev
  // path. ensureSeeded installs missing built-ins and only advances explicitly newer type schemas.
  final seed =
      Platform.environment['PLENARA_SEED_DIR'] ??
      _bundledSeedDir ??
      sourceDataDir;
  ensureSeeded(dataDir, seed);
  // Free mode runs offline-only: hand the Session an EXPLICIT offline client (empty key ->
  // every cloud call returns noKey, zero Anthropic spend). Passing null would NOT work — the
  // Session falls back to a default ClaudeClient() that picks the key up from the environment,
  // so free mode has to inject a deliberately-keyless client. (A real release ships two binaries.)
  final useCloud = cfg.apiKey != null && !cfg.freeTier;
  // The storage repository is built HERE (not left to Session's default) so the
  // channel gate reaches the turnlog: external builds pass enableTurnlog=false
  // and logTurn is a complete no-op (Spec 11 — external captures no content).
  // The live key is also registered with the turnlog's secret-rejection
  // registry: secrets are Class S in EVERY channel, internal included.
  final storage = FileStorageRepository(
    dataDir,
    deviceDir: defaultDeviceDir(),
    enableTurnlog: !isExternalBuild,
  );
  final apiKey = cfg.apiKey;
  if (apiKey != null) storage.registerTurnlogSecret(apiKey);
  return Session(
    dataDir,
    cloud: useCloud
        ? ClaudeClient(
            apiKeyOverride: cfg.apiKey,
            usagePath: '${defaultDeviceDir()}/cloud-usage.json',
          )
        : ClaudeClient(
            apiKeyOverride: '',
            usagePath: '${defaultDeviceDir()}/cloud-usage.json',
          ),
    storage: storage,
    scheduler: scheduler,
    deviceDir:
        defaultDeviceDir(), // deviceId + turnlog stay device-local, off the synced folder
  );
}

/// The whole of app startup, in order. [app] is the root widget `main()` hands
/// over — passed in rather than imported so this file stays below the UI layer.
Future<void> bootstrapAndRun(Widget app) async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // iOS/Android expose no HOME env var, so v0's `~/…` paths collapse to a non-writable `./…` — which
    // white-screened the first iOS build (loadConfig tried to create `./.plenara`). Resolve the app's
    // real per-user directory and inject it as the home base BEFORE any config OR log path is derived
    // (so it must precede the first AppLog.instance access too). Documents is chosen so diagnostics
    // are also Files-app-visible for cable-free retrieval.
    if (Platform.isIOS || Platform.isAndroid) {
      try {
        homeOverride = (await getApplicationDocumentsDirectory()).path;
      } catch (_) {
        /* desktop never reaches here; on failure fall back to env/'.' */
      }
    }
    // The first AppLog access must come AFTER the homeOverride resolution above
    // (the log path derives from it on iOS), so no marker can precede it — the
    // log's own creation timestamp is the home-override phase marker.
    AppLog.instance.log('boot: phase home-override done');
    if (Platform.isIOS) {
      AppLog.instance.log('boot: phase restore-selection begin');
      try {
        final selected = await const DataFolderAccess().restoreSelection();
        if (selected != null && selected.isNotEmpty) {
          dataDirOverride = dataRootForSelection(selected);
          AppLog.instance.log(
            'boot: data-folder restore -> $dataDirOverride (provider-selected)',
          );
        } else {
          AppLog.instance.log(
            'boot: data-folder restore -> no stored selection (device-local)',
          );
        }
      } catch (error, stack) {
        // A stale provider grant must never prevent runApp from creating the
        // recovery surface. Session startup will use the device-local root.
        dataDirOverride = null;
        AppLog.instance.log(
          'boot: data-folder restore FAILED (falling back to the device-local root): $error\n$stack',
        );
        stdout.writeln('Plenara data-folder restore failed: $error');
      }
      AppLog.instance.log('boot: phase restore-selection done');
    }
    AppLog.instance.log('boot: phase credentials begin');
    try {
      await initializeAppCredentials();
    } catch (error, stack) {
      // A locked keychain / PlatformException / failed migration must never
      // prevent runApp — a permanent blank screen with zero diagnostics is the
      // exact failure this log exists to prevent. Settings handles a missing
      // key; continue keyless.
      AppLog.instance.log(
        'boot: credential init FAILED (continuing keyless): $error\n$stack',
      );
    }
    AppLog.instance.log('boot: phase credentials done');
    final log = AppLog.instance;
    log.registerSecret(loadAppConfig().apiKey);
    // Print the diagnostics log path so a manual test that goes wrong is one file away.
    stdout.writeln('Plenara diagnostics log: ${log.file.path}');
    log('boot: main() starting');
    // Extract the bundled definitions on every launch (unless a dev source is
    // explicit). ensureSeeded adds missing built-ins and promotes newer type
    // schemas without clobbering same-version edits; skipping extraction for a
    // non-empty folder would strand older installs forever.
    if (Platform.environment['PLENARA_SEED_DIR'] == null) {
      try {
        _bundledSeedDir = await extractSeedAssets();
        log('boot: extracted bundled seed assets -> $_bundledSeedDir');
      } catch (e, st) {
        log(
          'boot: seed asset extraction FAILED (falling back to dev path): $e\n$st',
        );
      }
    }
    FlutterError.onError = (details) {
      log('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
      FlutterError.presentError(details);
    };
    runApp(app);
  }, (error, stack) => AppLog.instance.log('UNCAUGHT: $error\n$stack'));
}
