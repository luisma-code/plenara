import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/build_channel.dart';
import 'package:plenara_app/credential_store.dart';

void main() {
  tearDown(resetAppCredentialsForTest);

  test('verified secure write removes a legacy plaintext credential', () async {
    final dir = Directory.systemTemp.createTempSync('plenara_credential_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/config.json';
    File(path).writeAsStringSync(
      jsonEncode({'dataDir': '${dir.path}/data', 'apiKey': 'fixture-legacy'}),
    );
    final secure = MemoryCredentialStore();

    await initializeAppCredentials(
      store: secure,
      configPath: path,
      environment: const {},
      channel: BuildChannel.internal,
    );

    expect(secure.value, isNotNull);
    final persisted = jsonDecode(File(path).readAsStringSync()) as Map;
    expect(persisted['apiKey'], isEmpty);
  });

  test(
    'failed secure verification preserves the plaintext credential',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'plenara_credential_fail_',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/config.json';
      File(path).writeAsStringSync(
        jsonEncode({'dataDir': '${dir.path}/data', 'apiKey': 'fixture-legacy'}),
      );
      final secure = MemoryCredentialStore(rejectWrites: true);

      // A secure store that cannot verify its own write must NOT take boot down
      // (that threw a StateError out of main() before runApp, bricking the app
      // with a blank screen). The honest degrade is: keep using the plaintext
      // key for this run and leave it on disk for the next attempt.
      await initializeAppCredentials(
        store: secure,
        configPath: path,
        environment: const {},
        channel: BuildChannel.internal,
      );

      final persisted = jsonDecode(File(path).readAsStringSync()) as Map;
      expect(
        persisted['apiKey'],
        'fixture-legacy',
        reason: 'an unverifiable secure write must never clear the only '
            'surviving copy of the key',
      );
      expect(
        activeApiKeyForTest,
        'fixture-legacy',
        reason: 'the process keeps a usable key rather than running keyless',
      );
    },
  );

  test('internal builds do not import an environment credential', () async {
    final dir = Directory.systemTemp.createTempSync('plenara_credential_env_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final secure = MemoryCredentialStore();

    await initializeAppCredentials(
      store: secure,
      configPath: '${dir.path}/config.json',
      environment: const {'ANTHROPIC_API_KEY': 'fixture-parent'},
      channel: BuildChannel.internal,
    );

    expect(secure.value, isNull);
  });

  test(
    'macOS Keychain adapter really round-trips',
    () async {
      final store = PlatformCredentialStore(
        key: 'plenara_unit_test_credential',
      );
      addTearDown(store.deleteApiKey);

      await store.deleteApiKey();
      expect(await store.readApiKey(), isNull);
      await store.writeApiKey('fixture-keychain-value');
      expect(await store.readApiKey(), 'fixture-keychain-value');
      await store.deleteApiKey();
      expect(await store.readApiKey(), isNull);
    },
    skip: !Platform.isMacOS,
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
