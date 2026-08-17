import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:plenara/config.dart';

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
    _activeApiKey = secureKey;
    if (cfg.apiKeySource == ConfigValueSource.file) {
      saveConfig(apiKey: '', configPath: configPath);
    }
  } else if (legacyKey != null && cfg.apiKeySource == ConfigValueSource.file) {
    await _store.writeApiKey(legacyKey);
    final verified = _nonEmpty(await _store.readApiKey());
    if (verified != legacyKey) {
      throw StateError('Secure credential write could not be verified.');
    }
    saveConfig(apiKey: '', configPath: configPath);
    _activeApiKey = legacyKey;
  } else {
    // Environment keys are a development-only, process-lifetime override. They
    // are never silently copied into persistent storage.
    _activeApiKey = legacyKey;
  }
  _initialized = true;
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

void resetAppCredentialsForTest() {
  _store = PlatformCredentialStore();
  _activeApiKey = null;
  _initialized = false;
}
