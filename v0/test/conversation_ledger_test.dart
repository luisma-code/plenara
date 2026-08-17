import 'dart:io';

import 'package:plenara/conversation_ledger.dart';
import 'package:test/test.dart';

void main() {
  test('conversation entries survive restart with their execution link', () {
    final root =
        Directory.systemTemp.createTempSync('plenara_conversation_ledger_');
    addTearDown(() => root.deleteSync(recursive: true));
    final first = FileConversationLedger(root.path);
    first.append(
      utterance: 'add milk',
      reply: 'Added milk.',
      source: 'corpus',
      at: DateTime.parse('2026-08-17T09:00:00Z'),
      executionId: 42,
    );

    final reopened = FileConversationLedger(root.path);

    expect(reopened.entries.single.utterance, 'add milk');
    expect(reopened.entries.single.reply, 'Added milk.');
    expect(reopened.entries.single.executionId, 42);
  });

  test('a corrupt ledger is visible and exact bytes are preserved', () {
    final root =
        Directory.systemTemp.createTempSync('plenara_conversation_corrupt_');
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File('${root.path}/conversation-ledger.json')
      ..writeAsStringSync('{torn');
    final exact = file.readAsBytesSync();

    final ledger = FileConversationLedger(root.path);

    expect(ledger.issues.single, startsWith('conversation_ledger_corrupt:'));
    expect(File('${file.path}.corrupt').readAsBytesSync(), exact);
  });
}
