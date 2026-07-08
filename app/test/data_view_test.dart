// Tests for the Spec 07 "Your data" view: the structural archetype inference (unit) and the
// view rendering + reachability (widget). Hermetic — an offline cloud, a temp data dir.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:plenara_app/data_view.dart';
import 'package:plenara_app/main.dart';

class _NullCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<String>> generate(String k, String c) async => const CloudError(CloudErrorKind.noKey);
}

String _base(String p) => p.replaceAll('\\', '/').split('/').last;

String _tempData() {
  final tmp = Directory.systemTemp.createTempSync('plenara_dv_');
  for (final sub in const ['types', 'skills']) {
    final dst = Directory('${tmp.path}/$sub')..createSync(recursive: true);
    for (final f in Directory('$sourceDataDir/$sub').listSync().whereType<File>()) {
      f.copySync('${dst.path}/${_base(f.path)}');
    }
  }
  File('$sourceDataDir/corpus.json').copySync('${tmp.path}/corpus.json');
  Directory('${tmp.path}/records').createSync();
  return tmp.path;
}

Session _session() => Session(_tempData(), clock: DateTime.parse('2026-07-06T09:00:00'), cloud: _NullCloud());

void main() {
  group('archetypeFor — structural inference (Spec 07 §4, no per-type UI code)', () {
    Map<String, dynamic> t(List<Map<String, dynamic>> attrs) => {'attributes': attrs};
    test('a type with a done/completed flag -> checklist', () {
      expect(
          archetypeFor('task', t([
            {'name': 'description', 'valueType': 'text'},
            {'name': 'completed', 'valueType': 'boolean'},
          ])),
          Archetype.checklist);
    });
    test('the contact type -> personCard', () {
      expect(archetypeFor('contact', t([{'name': 'displayName', 'valueType': 'text'}])), Archetype.personCard);
    });
    test('a numeric measure + a date -> tracker', () {
      expect(
          archetypeFor('step_log', t([
            {'name': 'count', 'valueType': 'number'},
            {'name': 'loggedAt', 'valueType': 'date'},
          ])),
          Archetype.tracker);
    });
    test('a dated log with no number -> timeline', () {
      expect(
          archetypeFor('journal_entry', t([
            {'name': 'text', 'valueType': 'text'},
            {'name': 'loggedAt', 'valueType': 'date'},
          ])),
          Archetype.timeline);
    });
    test('no date/bool/number -> collection (the universal fallback)', () {
      expect(archetypeFor('note', t([{'name': 'body', 'valueType': 'text'}])), Archetype.collection);
    });
  });

  testWidgets('the data view opens from the chat and renders a task under a checklist archetype', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session(), retrieval: false)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'add buy milk to my list');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.storage)); // open "Your data"
    await tester.pumpAndSettle();

    expect(find.text('Your data'), findsOneWidget);
    expect(find.byKey(const Key('archetype-task')), findsOneWidget); // the task section rendered
    expect(find.textContaining('checklist'), findsWidgets); // chosen by structure, not by type name
    expect(find.textContaining('buy milk'), findsWidgets); // the record itself
  });

  testWidgets('an empty vault shows the empty state', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session(), retrieval: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.storage));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing logged yet'), findsOneWidget);
  });
}
