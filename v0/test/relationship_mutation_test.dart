import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:plenara/people.dart';
import 'package:test/test.dart';

import 'helpers.dart';

class _NoCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
    String utterance,
    Map<String, Map<String, dynamic>> skills, {
    Set<String> knownContacts = const {},
  }) async =>
      const CloudOk(null);

  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(
    String description, {
    String? priorError,
  }) async =>
      const CloudOk(null);

  @override
  Future<CloudResult<String>> generate(String kind, String context) async =>
      const CloudError(CloudErrorKind.noKey);
}

Future<Session> _session() async {
  final dir = makeTempDataDir();
  addTearDown(() => Directory(dir).deleteSync(recursive: true));
  final session = Session(
    dir,
    clock: DateTime.parse('2026-09-06T10:00:00'),
    cloud: _NoCloud(),
  );
  await session.init(retrieval: false);
  return session;
}

void main() {
  test('product UI can create facts and typed interactions durably', () async {
    final session = await _session();
    final person = await session.createRecord('contact', {
      'displayName': 'Mia',
      'relationshipGoal': 'close',
    });
    expect(person.ok, isTrue);
    final id =
        session.store.values.singleWhere((r) => r['typeId'] == 'contact')['id'];
    expect(
        (await session.createRecord('contact_fact', {
          'subject': id,
          'fact': 'loves dahlias',
        }))
            .ok,
        isTrue);
    expect(
        (await session.createRecord('interaction', {
          'subject': id,
          'medium': 'facetime',
          'at': '2026-09-06',
          'note': 'talked about school',
        }))
            .ok,
        isTrue);
    expect(
      session.store.values
          .singleWhere((r) => r['typeId'] == 'interaction')['medium'],
      'facetime',
    );
  });

  test(
      'removing a person cascades relationship data and unlinks tasks, then undoes',
      () async {
    final session = await _session();
    await session.createRecord('contact', {'displayName': 'Mia'});
    final id =
        '${session.store.values.singleWhere((r) => r['typeId'] == 'contact')['id']}';
    await session
        .createRecord('contact_fact', {'subject': id, 'fact': 'likes tea'});
    await session.createRecord('interaction', {
      'subject': id,
      'medium': 'phone',
      'at': '2026-09-01',
    });
    await session.createRecord('task', {
      'description': 'Call Mia',
      'createdAt': '2026-09-06T10:00:00',
      'contactRefs': [id],
    });
    await session.createRecord('contact', {
      'displayName': 'Sam',
      'introducedBy': id,
    });

    final removed = await session.deleteRecord(id);
    expect(removed.ok, isTrue);
    expect(session.store.containsKey(id), isFalse);
    expect(session.store.values.where((r) => '${r['subject']}' == id), isEmpty);
    expect(
        session.store.values
            .singleWhere((r) => r['typeId'] == 'task')['contactRefs'],
        isNull);
    expect(
        session.store.values.singleWhere(
          (r) => r['typeId'] == 'contact' && r['displayName'] == 'Sam',
        )['introducedBy'],
        isNull);

    expect(await session.undoById(removed.undoId!), contains('Undone'));
    expect(session.store.containsKey(id), isTrue);
    expect(session.store.values.where((r) => '${r['subject']}' == id),
        hasLength(2));
    expect(
        session.store.values
            .singleWhere((r) => r['typeId'] == 'task')['contactRefs'],
        [id]);
    expect(
        session.store.values.singleWhere(
          (r) => r['typeId'] == 'contact' && r['displayName'] == 'Sam',
        )['introducedBy'],
        id);
  });

  test('reimport refreshes one matching contact instead of cloning it',
      () async {
    final session = await _session();
    expect(
        (await session.importContacts([
          {
            'systemContactId': 'ios-1',
            'displayName': 'Mia',
            'primaryPhone': '+15551212',
          },
        ]))
            .ok,
        isTrue);
    expect(
        (await session.importContacts([
          {
            'systemContactId': 'ios-1',
            'displayName': 'Mia Rose',
            'primaryPhone': '+15559999',
            'primaryEmail': 'mia@example.com',
          },
        ]))
            .ok,
        isTrue);
    final contacts =
        session.store.values.where((r) => r['typeId'] == 'contact').toList();
    expect(contacts, hasLength(1));
    expect(contacts.single['displayName'], 'Mia Rose');
    expect(contacts.single['primaryPhone'], '+15559999');
  });

  test('ambiguous voice interaction asks for medium, then stores it', () async {
    final session = await _session();
    expect(
        await session.handle('talked to Mia'), contains('How did you connect'));
    expect(await session.handle('FaceTime'), contains('Logged'));
    final interaction =
        session.store.values.singleWhere((r) => r['typeId'] == 'interaction');
    expect(interaction['medium'], 'facetime');
    expect(interaction['connectionDepth'], 'meaningful');
  });

  test('contact import defaults safely and never overwrites an existing plan',
      () async {
    final session = await _session();
    await session.importContacts([
      {'systemContactId': 'ios-1', 'displayName': 'Mia'},
    ]);
    final id =
        '${session.store.values.singleWhere((r) => r['typeId'] == 'contact')['id']}';
    expect(session.store[id]?['relationshipCircle'], 'context');
    await session.setRelationshipPreset(
      id,
      RelationshipPreset.closeRemoteFriend,
    );
    await session.importContacts([
      {
        'systemContactId': 'ios-1',
        'displayName': 'Mia',
        'relationshipCircle': 'warm',
        'primaryPhone': '+15551212',
      },
    ]);
    expect(session.store[id]?['relationshipCircle'], 'close');
    expect(session.store[id]?['proximity'], 'remote');
    expect(session.store[id]?['primaryPhone'], '+15551212');
  });

  test('moving several people between circles is atomic and undoable',
      () async {
    final session = await _session();
    for (final (name, preset) in [
      ('Mia', RelationshipPreset.closeRemoteFriend),
      ('Jo', RelationshipPreset.contextOnly),
    ]) {
      await session.createRecord('contact', {
        'displayName': name,
        ...relationshipPresetFields(preset),
      });
    }
    final contacts = {
      for (final contact in session.store.values
          .where((record) => record['typeId'] == 'contact'))
        '${contact['displayName']}': '${contact['id']}',
    };
    await session.editField(contacts['Mia']!, 'touchFrequencyDays', 17);

    final moved = await session.setRelationshipCircles(
      contacts.values,
      RelationshipCircle.connected,
    );

    expect(moved.ok, isTrue);
    expect(moved.message, 'Moved 2 people to Keep connected.');
    expect(
      contacts.values.map((id) => session.store[id]?['relationshipCircle']),
      everyElement('connected'),
    );
    expect(session.store[contacts['Mia']]?['touchFrequencyDays'], isNull);

    expect(await session.undoById(moved.undoId!), contains('Undone'));
    expect(session.store[contacts['Mia']]?['relationshipCircle'], 'close');
    expect(session.store[contacts['Mia']]?['touchFrequencyDays'], 17);
    expect(session.store[contacts['Jo']]?['relationshipCircle'], 'context');
  });

  test('voice assigns relationship categories, pauses, and reports due people',
      () async {
    final session = await _session();
    await session.createRecord('contact', {'displayName': 'Mia'});
    final id =
        '${session.store.values.singleWhere((r) => r['typeId'] == 'contact')['id']}';
    expect(
      await session.handle('categorize Mia as close remote friend'),
      contains('Close remote friend'),
    );
    expect(session.store[id]?['relationshipCircle'], 'close');
    expect(session.store[id]?['proximity'], 'remote');
    expect(
      await session.handle(
        'set meaningful connection goal for Mia every 45 days',
      ),
      contains('45 days'),
    );
    expect(session.store[id]?['meaningfulFrequencyDays'], 45);
    expect(await session.handle('who should I reach out to'), contains('Mia'));
    expect(
      await session.handle('pause reminders for Mia'),
      contains('Paused'),
    );
    expect(suggestedContacts(session.store, session.now), isEmpty);
  });

  test('voice respects an explicit meaningful text interaction', () async {
    final session = await _session();
    expect(
      await session.handle('texted Mia, it was meaningful'),
      contains('Logged'),
    );
    final interaction =
        session.store.values.singleWhere((r) => r['typeId'] == 'interaction');
    expect(interaction['medium'], 'text');
    expect(interaction['connectionDepth'], 'meaningful');
    expect(await session.handle('called Mia, quick'), contains('Logged'));
    final phone = session.store.values.singleWhere(
      (r) => r['typeId'] == 'interaction' && r['medium'] == 'phone',
    );
    expect(phone['connectionDepth'], 'quick');
  });
}
