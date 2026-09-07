import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
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

    final removed = await session.deleteRecord(id);
    expect(removed.ok, isTrue);
    expect(session.store.containsKey(id), isFalse);
    expect(session.store.values.where((r) => '${r['subject']}' == id), isEmpty);
    expect(
        session.store.values
            .singleWhere((r) => r['typeId'] == 'task')['contactRefs'],
        isNull);

    expect(await session.undoById(removed.undoId!), contains('Undone'));
    expect(session.store.containsKey(id), isTrue);
    expect(session.store.values.where((r) => '${r['subject']}' == id),
        hasLength(2));
    expect(
        session.store.values
            .singleWhere((r) => r['typeId'] == 'task')['contactRefs'],
        [id]);
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
  });
}
