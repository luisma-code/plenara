import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';
import 'package:plenara/session.dart';
import 'package:plenara/storage_repository.dart';
import 'package:plenara/store.dart';
import 'package:plenara_app/attention_view.dart';
import 'package:plenara_app/plenara_theme.dart';

void main() {
  testWidgets(
    'record conflict shows both values and restores the other undoably',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(700, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final data = Directory.systemTemp
          .createTempSync('plenara_attention_')
          .path;
      final device = Directory.systemTemp
          .createTempSync('plenara_attention_dev_')
          .path;
      ensureSeeded(data, '../v0/data');
      final repository = FileStorageRepository(
        data,
        deviceDir: device,
        device: HlcDevice('A'),
      );
      repository.persist({
        'id': 'task-1',
        'typeId': 'task',
        '_schemaVersion': 5,
        'description': 'Current plan',
        'createdAt': '2026-08-17T10:00:00.000Z',
      });
      final base =
          jsonDecode(File('$data/records/task-1.json').readAsStringSync())
              as Map<String, dynamic>;
      (base['fields'] as Map<String, dynamic>)['description'] = 'Other plan';
      base['_meta'] = {
        'vv': {'B': 1},
        'stamps': {
          'description': {'ms': 9000000000000, 'counter': 0, 'deviceId': 'B'},
          'createdAt': {'ms': 1, 'counter': 0, 'deviceId': 'B'},
        },
        'conflicts': <dynamic>[],
      };
      writeRecordDocument(
        File('$data/records/task-1 conflicted copy.json'),
        base,
      );
      final session = Session(
        data,
        storage: repository,
        deviceDir: device,
        cloud: ClaudeClient(apiKeyOverride: ''),
      );
      await session.init(retrieval: false);
      addTearDown(session.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: PlenaraTheme.dark,
          home: AttentionView(session: session),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Two devices edited description'),
        findsOneWidget,
      );
      expect(find.text('Current: Other plan'), findsOneWidget);
      expect(find.text('Other version: Current plan'), findsOneWidget);
      await tester.tap(find.text('Restore other'));
      await tester.pumpAndSettle();

      expect(session.store['task-1']!['description'], 'Current plan');
      expect(session.recordSyncConflicts, isEmpty);
      expect(find.textContaining('saved and undoable'), findsOneWidget);
    },
  );
}
