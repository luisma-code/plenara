import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/app_log.dart';
import 'package:plenara_app/build_channel.dart';

void main() {
  test(
    'internal diagnostics preserve user exchanges but reject every secret form',
    () {
      final dir = Directory.systemTemp.createTempSync('plenara_log_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final log = AppLog.forTest(
        dir,
        diagnosticPolicyFor(BuildChannel.internal),
      );
      log.registerSecret('live-fixture-secret');

      log.log('Luis said: dinner with Katherine; key=live-fixture-secret');
      log.log('Authorization: Bearer bearer-fixture-value');
      log.log('x-api-key: header-fixture-value');
      log.log('provider returned sk-ant-fixture-1234');

      final text = log.file.readAsStringSync();
      expect(
        text,
        contains('dinner with Katherine'),
        reason: 'internal raw content must remain useful',
      );
      expect(text, isNot(contains('live-fixture-secret')));
      expect(text, isNot(contains('bearer-fixture-value')));
      expect(text, isNot(contains('header-fixture-value')));
      expect(text, isNot(contains('sk-ant-fixture-1234')));
      expect('[secret]'.allMatches(text).length, greaterThanOrEqualTo(4));
    },
  );

  test('external policy writes no content and exposes no raw export', () {
    final dir = Directory.systemTemp.createTempSync('plenara_log_external_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final policy = diagnosticPolicyFor(BuildChannel.external);
    final log = AppLog.forTest(dir, policy);
    log.log('private conversation');
    log.debug('private debug trace');
    expect(log.file.existsSync(), isFalse);
    expect(policy.allowsRawExport, isFalse);
  });

  test('external startup purges raw logs inherited from an internal build', () {
    final dir = Directory.systemTemp.createTempSync(
      'plenara_log_external_purge_',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final inherited = File('${dir.path}/internal.log')
      ..writeAsStringSync('private conversation from dogfood');

    AppLog.pruneForTest(
      dir,
      diagnosticPolicyFor(BuildChannel.external),
      DateTime.utc(2026, 8, 17),
    );

    expect(inherited.existsSync(), isFalse);
  });

  test('retention removes expired logs by age independently of size', () {
    final dir = Directory.systemTemp.createTempSync('plenara_log_retention_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final now = DateTime.utc(2026, 8, 17);
    File('${dir.path}/expired.log')
      ..writeAsStringSync('old')
      ..setLastModifiedSync(now.subtract(const Duration(days: 31)));
    File('${dir.path}/current.log')
      ..writeAsStringSync('abcdef')
      ..setLastModifiedSync(now.subtract(const Duration(days: 1)));
    final policy = DiagnosticPolicy(
      channel: BuildChannel.internal,
      capturesContent: true,
      allowsRawExport: true,
      verbose: true,
      maxAge: const Duration(days: 30),
      maxBytes: 1024,
    );

    AppLog.pruneForTest(dir, policy, now);
    expect(File('${dir.path}/expired.log').existsSync(), isFalse);
    expect(File('${dir.path}/current.log').existsSync(), isTrue);
  });

  test('retention removes oldest current logs above the byte cap', () {
    final dir = Directory.systemTemp.createTempSync('plenara_log_size_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final now = DateTime.utc(2026, 8, 17);
    File('${dir.path}/oldest.log')
      ..writeAsStringSync('123456')
      ..setLastModifiedSync(now.subtract(const Duration(days: 2)));
    File('${dir.path}/newest.log')
      ..writeAsStringSync('abcdef')
      ..setLastModifiedSync(now.subtract(const Duration(days: 1)));
    final policy = DiagnosticPolicy(
      channel: BuildChannel.internal,
      capturesContent: true,
      allowsRawExport: true,
      verbose: true,
      maxAge: const Duration(days: 30),
      maxBytes: 6,
    );

    AppLog.pruneForTest(dir, policy, now);
    expect(File('${dir.path}/oldest.log').existsSync(), isFalse);
    expect(File('${dir.path}/newest.log').existsSync(), isTrue);
  });
}
