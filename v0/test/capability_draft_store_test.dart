import 'dart:io';

import 'package:plenara/capability_draft_store.dart';
import 'package:test/test.dart';

void main() {
  test('validated draft persists until the activation door clears it', () {
    final dir = Directory.systemTemp.createTempSync('plenara_draft_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/pending-capability.json';
    final draft = {
      'typeId': 'stretch_log',
      'skillId': 'log-stretch',
      'type': {'typeId': 'stretch_log'},
      'skill': {'skillId': 'log-stretch'},
      'displayName': 'Stretch',
      'examples': ['log a stretch'],
    };

    CapabilityDraftStore(path: path).save(draft);
    expect(CapabilityDraftStore(path: path).active, draft);

    CapabilityDraftStore(path: path).clear();
    expect(File(path).existsSync(), isFalse);
    expect(CapabilityDraftStore(path: path).active, isNull);
  });

  test('a corrupt draft is inert and produces a repair issue', () {
    final dir = Directory.systemTemp.createTempSync('plenara_draft_bad_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/pending-capability.json';
    File(path).writeAsStringSync('{not json');

    final store = CapabilityDraftStore(path: path);
    expect(store.active, isNull);
    expect(store.issues, isNotEmpty);
  });
}
