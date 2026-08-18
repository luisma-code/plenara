import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:plenara/config.dart';

import 'app_log.dart';
import 'build_channel.dart';

/// The only app-layer home for spendable credentials. Production uses the
/// platform keychain/keystore; tests inject a memory implementation.
abstract interface class CredentialStore {
  Future<String?> readApiKey();
  Future<void> writeApiKey(String value);
  Future<void> deleteApiKey();
}

class PlatformCredentialStore implements CredentialStore {
  static const _defaultKey = 'anthropic_api_key';
  static const _account = 'Plenara';
  final FlutterSecureStorage? _storage;
  final String _key;

  factory PlatformCredentialStore({
    FlutterSecureStorage? storage,
    String? key,
  }) => PlatformCredentialStore._(storage, key ?? _defaultKey);

  PlatformCredentialStore._(this._storage, this._key);

  FlutterSecureStorage get _platformStorage =>
      _storage ?? const FlutterSecureStorage();

  String get _service => 'com.plenara.credentials.$_key';

  @override
  Future<String?> readApiKey() async {
    if (Platform.isMacOS && _storage == null) {
      final result = await Process.run('/usr/bin/security', [
        'find-generic-password',
        '-a',
        _account,
        '-s',
        _service,
        '-w',
      ]);
      if (result.exitCode == 44) return null;
      if (result.exitCode != 0) _checkMacOsResult('read', result);
      return (result.stdout as String).trim();
    }
    return _platformStorage.read(key: _key);
  }

  @override
  Future<void> writeApiKey(String value) async {
    if (Platform.isMacOS && _storage == null) {
      // Unsigned macOS apps cannot use the data-protection keychain API. The
      // system `security` helper writes the same login Keychain without adding
      // a provisioning-profile dependency to local builds. Never log this
      // command or its arguments: the value exists in argv for this brief call.
      final result = await Process.run('/usr/bin/security', [
        'add-generic-password',
        '-a',
        _account,
        '-s',
        _service,
        '-U',
        '-w',
        value,
      ]);
      if (result.exitCode != 0) {
        throw StateError(
          'macOS Keychain write failed (${result.exitCode}): '
          '${(result.stderr as String).trim()}',
        );
      }
      return;
    }
    await _platformStorage.write(key: _key, value: value);
  }

  @override
  Future<void> deleteApiKey() async {
    if (Platform.isMacOS && _storage == null) {
      final result = await Process.run('/usr/bin/security', [
        'delete-generic-password',
        '-a',
        _account,
        '-s',
        _service,
      ]);
      if (result.exitCode == 44) return;
      if (result.exitCode != 0) _checkMacOsResult('delete', result);
      return;
    }
    await _platformStorage.delete(key: _key);
  }

  Never _checkMacOsResult(String operation, ProcessResult result) {
    throw StateError(
      'macOS Keychain $operation failed (${result.exitCode}): '
      '${(result.stderr as String).trim()}',
    );
  }
}

class MemoryCredentialStore implements CredentialStore {
  String? value;
  bool rejectWrites;

  MemoryCredentialStore({this.value, this.rejectWrites = false});

  @override
  Future<String?> readApiKey() async => value;

  @override
  Future<void> writeApiKey(String value) async {
    if (rejectWrites) return;
    this.value = value;
  }

  @override
  Future<void> deleteApiKey() async => value = null;
}

CredentialStore _store = PlatformCredentialStore();
String? _activeApiKey;
bool _initialized = false;

/// Loads the secure value and migrates a legacy plaintext config value. The
/// plaintext is removed only after reading the same value back from secure
/// storage, so an interrupted or rejected keychain write cannot lose the key.
Future<void> initializeAppCredentials({
  CredentialStore? store,
  String? configPath,
  Map<String, String>? environment,
  BuildChannel? channel,
}) async {
  if (store != null) _store = store;
  final activeChannel = channel ?? activeBuildChannel;
  final allowedEnvironment = activeChannel == BuildChannel.development
      ? environment ?? Platform.environment
      : const <String, String>{};
  final cfg = loadConfig(
    configPath: configPath,
    environment: allowedEnvironment,
  );
  final secure = await _store.readApiKey();
  final secureKey = _nonEmpty(secure);
  final legacyKey = _nonEmpty(cfg.apiKey);

  if (secureKey != null) {
    if (legacyKey != null &&
        legacyKey != secureKey &&
        cfg.apiKeySource == ConfigValueSource.file) {
      // V9: a DIFFERENT key sitting in the plaintext config alongside a secure
      // key is a deliberate user rotation (the file was edited by hand). Adopt
      // the file key through the same verified-write ritual — silently erasing
      // it (the old behavior) discarded the key the user just chose.
      _activeApiKey = await _adoptPlaintextKey(
        legacyKey,
        configPath: configPath,
        reason: 'rotated config-file key',
      );
    } else {
      _activeApiKey = secureKey;
      if (cfg.apiKeySource == ConfigValueSource.file) {
        saveConfig(apiKey: '', configPath: configPath);
      }
    }
  } else if (legacyKey != null && cfg.apiKeySource == ConfigValueSource.file) {
    _activeApiKey = await _adoptPlaintextKey(
      legacyKey,
      configPath: configPath,
      reason: 'legacy plaintext key',
    );
  } else {
    // Environment keys are a development-only, process-lifetime override. They
    // are never silently copied into persistent storage.
    _activeApiKey = legacyKey;
  }
  _initialized = true;
}

/// The verified-write ritual: the plaintext config value is cleared only after
/// reading the same value back from secure storage. A failed or unverifiable
/// write FALLS BACK to using the plaintext key for this process — it
/// deliberately remains on disk for the next attempt — instead of throwing;
/// a keychain hiccup at boot must never cost the key or the launch.
Future<String> _adoptPlaintextKey(
  String key, {
  String? configPath,
  required String reason,
}) async {
  try {
    await _store.writeApiKey(key);
    if (_nonEmpty(await _store.readApiKey()) == key) {
      saveConfig(apiKey: '', configPath: configPath);
      AppLog.instance.log(
        'credentials: adopted $reason into secure storage (plaintext cleared after verified readback)',
      );
      return key;
    }
    AppLog.instance.log(
      'credentials: secure write of $reason could not be verified — using the '
      'plaintext key for this run; it remains on disk for the next attempt',
    );
  } catch (error) {
    AppLog.instance.log(
      'credentials: secure write of $reason failed ($error) — using the '
      'plaintext key for this run; it remains on disk for the next attempt',
    );
  }
  return key;
}

PlenaraConfig loadAppConfig({String? configPath}) {
  final cfg = loadConfig(
    configPath: configPath,
    environment:
        configPath == null && activeBuildChannel == BuildChannel.development
        ? Platform.environment
        : const <String, String>{},
  );
  // Explicit config paths are test/tool seams and retain v0 file semantics.
  if (configPath != null || !_initialized) return cfg;
  return PlenaraConfig(
    cfg.dataDir,
    _activeApiKey,
    apiKeySource: _activeApiKey == null
        ? ConfigValueSource.absent
        : ConfigValueSource.secureStore,
    freeTier: cfg.freeTier,
    voiceMuted: cfg.voiceMuted,
    voiceName: cfg.voiceName,
    micHintsShown: cfg.micHintsShown,
    confirmCloudSpend: cfg.confirmCloudSpend,
    stillPresence: cfg.stillPresence,
    dataFolderSelected: cfg.dataFolderSelected,
  );
}

Future<void> saveAppCredential(String value, {String? configPath}) async {
  if (configPath != null) {
    saveConfig(apiKey: value, configPath: configPath);
    return;
  }
  final key = value.trim();
  if (key.isEmpty) {
    await _store.deleteApiKey();
    _activeApiKey = null;
    saveConfig(apiKey: '');
    return;
  }
  await _store.writeApiKey(key);
  if (_nonEmpty(await _store.readApiKey()) != key) {
    throw StateError('Secure credential write could not be verified.');
  }
  _activeApiKey = key;
  saveConfig(apiKey: '');
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// The credential this process is actually using, for tests that assert a
/// degraded boot stayed usable rather than silently running keyless.
@visibleForTesting
String? get activeApiKeyForTest => _activeApiKey;

void resetAppCredentialsForTest() {
  _store = PlatformCredentialStore();
  _activeApiKey = null;
  _initialized = false;
}
