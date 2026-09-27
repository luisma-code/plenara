// Run on an iPad simulator. This exercises the actual iOS window dimensions and
// renderer rather than relying only on a synthetic widget-test viewport.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';
import 'package:plenara/people.dart';
import 'package:plenara/session.dart';
import 'package:plenara_app/main.dart';
import 'package:plenara_app/seed_assets.dart';

class _NoCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
    String utterance,
    Map<String, Map<String, dynamic>> skills, {
    Set<String> knownContacts = const {},
  }) async => const CloudOk(null);

  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(
    String description, {
    String? priorError,
  }) async => const CloudOk(null);

  @override
  Future<CloudResult<String>> generate(String kind, String context) async =>
      const CloudError(CloudErrorKind.noKey);
}

Future<Session> _session() async {
  final root = Directory.systemTemp.createTempSync('plenara_ipad_');
  final data = Directory('${root.path}/data')..createSync();
  final device = Directory('${root.path}/device')..createSync();
  ensureSeeded(data.path, await extractSeedAssets());
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  return Session(
    data.path,
    deviceDir: device.path,
    clock: DateTime.parse('2026-09-26T09:00:00'),
    cloud: _NoCloud(),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iPad Today uses its wide shell and readable pillars', (
    tester,
  ) async {
    final session = await _session();
    await session.init(retrieval: false);
    await session.createRecord('contact', {
      'displayName': 'Alex Rivera',
      ...relationshipPresetFields(RelationshipPreset.closeFamily),
    });
    await session.createRecord('contact', {
      'displayName': 'Sam Rivera',
      ...relationshipPresetFields(RelationshipPreset.closeFamily),
    });
    await session.createRecord('task', {
      'description': 'Send Alex the guide',
      'status': 'today',
      'createdAt': session.now.toIso8601String(),
    });
    await session.createRecord('habit', {
      'title': 'Walk after lunch',
      'status': 'active',
      'targetPerWeek': 3,
      'preferredDays': '6',
      'createdAt': session.now.toIso8601String(),
      'cue': 'After lunch',
      'minimumVersion': 'Two minutes outside',
    });

    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: session)));
    await tester.pumpAndSettle();

    expect(
      MediaQuery.sizeOf(tester.element(find.byType(ChatScreen))).width,
      greaterThanOrEqualTo(840),
    );
    expect(find.byKey(const Key('planner-navigation-rail')), findsOneWidget);
    expect(find.byKey(const Key('planner-navigation')), findsNothing);
    expect(find.byKey(const Key('tablet-opportunity-grid')), findsOneWidget);
    final cards = find.descendant(
      of: find.byKey(const Key('tablet-opportunity-grid')),
      matching: find.byType(Card),
    );
    expect(cards, findsNWidgets(3));
    final cardLeftEdges = <double>{
      for (var i = 0; i < 3; i++) tester.getRect(cards.at(i)).left,
    };
    expect(cardLeftEdges.length, greaterThan(1));
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('ipad-today-wide');
  });
}
