import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:plenara_app/relationship_contacts.dart';
import 'package:plenara_app/relationships_view.dart';
import 'package:plenara_app/today_view.dart';

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

String _base(String path) => path.replaceAll('\\', '/').split('/').last;

Future<Session> _session() async {
  final seed = '${Directory.current.path}/assets/seed';
  final temp = Directory.systemTemp.createTempSync('plenara_relationship_ui_');
  for (final sub in const ['types', 'skills']) {
    final destination = Directory('${temp.path}/$sub')
      ..createSync(recursive: true);
    for (final file in Directory('$seed/$sub').listSync().whereType<File>()) {
      file.copySync('${destination.path}/${_base(file.path)}');
    }
  }
  File('$seed/corpus.json').copySync('${temp.path}/corpus.json');
  Directory('${temp.path}/records').createSync();
  addTearDown(() => temp.deleteSync(recursive: true));
  final session = Session(
    temp.path,
    clock: DateTime.parse('2026-09-06T10:00:00'),
    cloud: _NoCloud(),
  );
  await session.init(retrieval: false);
  return session;
}

class _Contacts implements PhoneContactsSource {
  int calls = 0;

  @override
  Future<List<PhoneContact>> select() async {
    calls++;
    return [
      PhoneContact(
        systemContactId: 'ios-bob',
        displayName: 'Bob Rivera',
        primaryPhone: calls == 1 ? '+15551212' : '+15559999',
        primaryEmail: 'bob@example.com',
      ),
    ];
  }
}

class _Launcher implements RelationshipLauncher {
  int calls = 0;
  int faceTimes = 0;
  int emails = 0;

  @override
  Future<bool> phone(String number) async {
    calls++;
    return true;
  }

  @override
  Future<bool> facetime(String address) async {
    faceTimes++;
    return true;
  }

  @override
  Future<bool> email(String address) async {
    emails++;
    return true;
  }
}

void main() {
  testWidgets('People is an actionable relationship workspace', (tester) async {
    final session = await _session();
    await session.createRecord('contact', {
      'displayName': 'Mia',
      'primaryPhone': '+15550000',
      'primaryEmail': 'mia@example.com',
      'relationshipGoal': 'close',
    });
    final contact = session.store.values.singleWhere(
      (r) => r['typeId'] == 'contact',
    );
    await session.createRecord('interaction', {
      'subject': contact['id'],
      'medium': 'text',
      'at': '2026-08-20',
    });
    final launcher = _Launcher();
    await tester.pumpWidget(
      MaterialApp(
        home: RelationshipsView(session: session, launcher: launcher),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Who to contact next'), findsOneWidget);
    expect(find.textContaining('Mia'), findsWidgets);
    await tester.tap(find.byKey(Key('relationship-person-${contact['id']}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('person-relationship-view')), findsOneWidget);

    await tester.tap(find.byKey(const Key('relationship-add-follow-up')));
    await tester.pumpAndSettle();
    final followUp = session.store.values.singleWhere(
      (record) => record['typeId'] == 'task',
    );
    expect(followUp['description'], 'Reach out to Mia');
    expect(followUp['contactRefs'], [contact['id']]);

    await tester.tap(
      find.byKey(const Key('relationship-preset-connectedFriend')),
    );
    await tester.pumpAndSettle();
    expect(
      session.store['${contact['id']}']?['relationshipCircle'],
      'connected',
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('fact-add')),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fact-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'loves dahlias');
    await tester.tap(find.text('Remember'));
    await tester.pumpAndSettle();
    expect(find.text('loves dahlias'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).last, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('log-interaction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('interaction-medium-facetime')));
    await tester.tap(find.text('Quick touch'));
    await tester.enterText(find.byType(TextField), 'Talked about school');
    await tester.tap(find.byKey(const Key('interaction-save')));
    await tester.pumpAndSettle();
    expect(
      session.store.values
          .where((r) => r['typeId'] == 'interaction')
          .any(
            (r) =>
                r['medium'] == 'facetime' && r['note'] == 'Talked about school',
          ),
      isTrue,
    );
    expect(
      session.store.values
          .where((r) => r['typeId'] == 'interaction')
          .last['connectionDepth'],
      'quick',
    );
    final logged = session.store.values.singleWhere(
      (r) => r['typeId'] == 'interaction' && r['note'] == 'Talked about school',
    );
    await tester.scrollUntilVisible(
      find.byKey(Key('interaction-${logged['id']}')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(Key('interaction-${logged['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meaningful'));
    await tester.tap(find.text('Save interaction'));
    await tester.pumpAndSettle();
    expect(session.store['${logged['id']}']?['connectionDepth'], 'meaningful');

    await tester.drag(find.byType(Scrollable).last, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Call'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'FaceTime'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Email'));
    await tester.pump();
    expect((launcher.calls, launcher.faceTimes, launcher.emails), (1, 1, 1));
  });

  testWidgets('Contacts picker reopens and refreshes without cloning', (
    tester,
  ) async {
    final session = await _session();
    final contacts = _Contacts();
    await tester.pumpWidget(
      MaterialApp(
        home: RelationshipsView(session: session, contactsSource: contacts),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('relationships-import')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Organize this person'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-preset-picker')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Close remote friend').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('import-organize-save')));
    await tester.pumpAndSettle();

    var people = session.store.values
        .where((record) => record['typeId'] == 'contact')
        .toList();
    expect(contacts.calls, 1);
    expect(people, hasLength(1));
    expect(people.single['displayName'], 'Bob Rivera');
    expect(people.single['primaryPhone'], '+15551212');
    expect(people.single['primaryEmail'], 'bob@example.com');
    expect(people.single['relationshipCircle'], 'close');
    expect(people.single['proximity'], 'remote');
    final originalId = people.single['id'];

    await tester.tap(find.byKey(const Key('relationships-import')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('import-preset-picker')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Context only').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('import-organize-save')));
    await tester.pumpAndSettle();

    people = session.store.values
        .where((record) => record['typeId'] == 'contact')
        .toList();
    expect(contacts.calls, 2);
    expect(people, hasLength(1));
    expect(people.single['id'], originalId);
    expect(people.single['primaryPhone'], '+15559999');
    expect(people.single['relationshipCircle'], 'close');
    expect(find.text('Import people'), findsNothing);
    final bob = session.store.values.singleWhere(
      (r) => r['typeId'] == 'contact',
    );
    expect(bob['displayName'], 'Bob Rivera');
    expect(bob['primaryPhone'], '+15559999');
    expect(bob['primaryEmail'], 'bob@example.com');
    expect(find.text('Bob Rivera'), findsWidgets);
  });

  testWidgets('Today relationship signal opens the actionable workspace', (
    tester,
  ) async {
    final session = await _session();
    await session.createRecord('contact', {
      'displayName': 'Mia',
      'relationshipGoal': 'close',
    });
    final id =
        '${session.store.values.singleWhere((r) => r['typeId'] == 'contact')['id']}';
    await session.createRecord('interaction', {
      'subject': id,
      'medium': 'phone',
      'at': '2026-08-01',
    });
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: TodayBoard(
          session: session,
          onChanged: () {},
          onOpenLibrary: () {},
          onOpenRelationships: () => opened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final signal = find.byKey(const Key('planner-signal-relationshipNeglect'));
    await tester.scrollUntilVisible(
      signal,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(signal);
    expect(opened, isTrue);
  });
}
