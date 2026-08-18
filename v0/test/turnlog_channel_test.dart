/// Turnlog channel boundary (Spec 11): external builds write NOTHING, and no
/// channel configuration may ever let a secret (Class S) reach the file bytes.
/// Internal content (the utterance itself) is retained — the redaction must not
/// destroy the instrument's diagnostic value.
import 'dart:io';

import 'package:plenara/storage_repository.dart';
import 'package:plenara/store.dart';
import 'package:test/test.dart';

String _tmp(String name) =>
    Directory.systemTemp.createTempSync('plenara_turnlog_$name').path;

void main() {
  test('enableTurnlog: false makes logTurn a complete no-op', () {
    final device = _tmp('gated_device');
    final repo = FileStorageRepository(
      _tmp('gated_data'),
      deviceDir: device,
      device: HlcDevice('A'),
      enableTurnlog: false,
    );
    repo.logTurn({'utterance': 'log a run', 'source': 'corpus'});
    expect(File('$device/turnlog.jsonl').existsSync(), isFalse,
        reason: 'an external build captures nothing — not even an empty file');
  });

  test('the default keeps the internal diagnostic channel writing', () {
    final device = _tmp('default_device');
    final repo = FileStorageRepository(
      _tmp('default_data'),
      deviceDir: device,
      device: HlcDevice('A'),
    );
    repo.logTurn({'utterance': 'log a run', 'source': 'corpus'});
    expect(File('$device/turnlog.jsonl').readAsStringSync(),
        contains('log a run'));
  });

  test(
      'registered secrets and credential patterns never reach the turnlog '
      'bytes, while ordinary content is retained', () {
    final device = _tmp('redact_device');
    final repo = FileStorageRepository(
      _tmp('redact_data'),
      deviceDir: device,
      device: HlcDevice('A'),
    );
    repo.registerTurnlogSecret('canary-9f2-live-key-value');
    repo.logTurn({
      'utterance': 'log a 5k run today',
      'echoedKey': 'my key is sk-ant-abc123-XYZ ok',
      'header': 'Authorization: Bearer tok_abcDEF123',
      'headerTwo': 'x-api-key: super-secret-val',
      'pem': '-----BEGIN RSA PRIVATE KEY-----\n'
          'MIIEowVERYSECRETBODY\n'
          '-----END RSA PRIVATE KEY-----',
      'secretEcho': 'she pasted canary-9f2-live-key-value into chat',
      'error': 'HttpException: 401 for Bearer tok_abcDEF123',
    });

    final bytes = File('$device/turnlog.jsonl').readAsStringSync();
    expect(bytes, isNot(contains('sk-ant-abc123-XYZ')));
    expect(bytes, isNot(contains('tok_abcDEF123')));
    expect(bytes, isNot(contains('super-secret-val')));
    expect(bytes, isNot(contains('MIIEowVERYSECRETBODY')));
    expect(bytes, isNot(contains('canary-9f2-live-key-value')));
    expect(bytes, contains('[redacted]'));
    expect(bytes, contains('log a 5k run today'),
        reason: 'the ordinary utterance survives — redaction must not '
            'destroy the diagnostic value of the internal channel');
  });

  test('a registered secret is scrubbed even in later entries', () {
    final device = _tmp('later_device');
    final repo = FileStorageRepository(
      _tmp('later_data'),
      deviceDir: device,
      device: HlcDevice('A'),
    );
    repo.registerTurnlogSecret('another-canary-value-77');
    repo.logTurn({'utterance': 'first turn, nothing secret'});
    repo.logTurn({'utterance': 'then another-canary-value-77 leaked'});
    final bytes = File('$device/turnlog.jsonl').readAsStringSync();
    expect(bytes, isNot(contains('another-canary-value-77')));
    expect(bytes, contains('first turn, nothing secret'));
  });
}
