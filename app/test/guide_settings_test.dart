import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/config.dart';
import 'package:plenara_app/guide_settings.dart';
import 'package:plenara_app/credential_store.dart';

class _Keys implements CredentialStore {
  String? key;
  bool fail = false;
  @override
  Future<String?> readApiKey() async => key;
  @override
  Future<void> writeApiKey(String value) async {
    if (fail) throw StateError('Unavailable');
    key = value;
  }

  @override
  Future<void> deleteApiKey() async {
    key = null;
  }
}

void main() {
  late String path;
  late _Keys keys;
  late CredentialStore previous;
  setUp(() {
    final root = Directory.systemTemp.createTempSync('guide_settings_');
    path = '${root.path}/config.json';
    File(path).writeAsStringSync('{"guideMonthlyLimit":0}');
    keys = _Keys();
    previous = guideCredentialStore;
    guideCredentialStore = keys;
    activeGuideKey = null;
  });
  tearDown(() {
    guideCredentialStore = previous;
    activeGuideKey = null;
    Directory(File(path).parent.path).deleteSync(recursive: true);
  });
  testWidgets(
    'Consent and positive budget are required; credential stays out of config',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GuideSettingsCard(configPath: path),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('guide-api-key')),
        'test-openai-key',
      );
      await tester.enterText(
        find.byKey(const Key('guide-monthly-limit')),
        '10',
      );
      await tester.ensureVisible(find.text('Save guide settings'));
      await tester.tap(find.text('Save guide settings'));
      await tester.pumpAndSettle();
      expect(loadConfig(configPath: path).guideMonthlyLimit, 0);
      expect(keys.key, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save guide settings'));
      await tester.tap(find.text('Save guide settings'));
      await tester.pumpAndSettle();
      expect(loadConfig(configPath: path).guideMonthlyLimit, 10);
      expect(keys.key, 'test-openai-key');
      expect(File(path).readAsStringSync(), isNot(contains('test-openai-key')));
      await tester.tap(find.text('Disconnect GPT'));
      await tester.pumpAndSettle();
      expect(keys.key, isNull);
      expect(loadConfig(configPath: path).guideMonthlyLimit, 0);
    },
  );
  test('Failed key replacement preserves existing secure credential', () async {
    keys.key = 'previous-test-key';
    activeGuideKey = keys.key;
    keys.fail = true;
    await expectLater(saveGuideCredential('new-test-key'), throwsStateError);
    expect(keys.key, 'previous-test-key');
    expect(activeGuideKey, 'previous-test-key');
  });
}
