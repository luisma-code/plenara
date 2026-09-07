import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/habits.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

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

String _base(String path) => path.replaceAll('\\', '/').split('/').last;

Future<Session> _session() async {
  final source = Directory('data');
  final temp = Directory.systemTemp.createTempSync('plenara_habits_');
  for (final sub in const ['types', 'skills']) {
    final destination = Directory('${temp.path}/$sub')
      ..createSync(recursive: true);
    for (final file
        in Directory('${source.path}/$sub').listSync().whereType<File>()) {
      file.copySync('${destination.path}/${_base(file.path)}');
    }
  }
  File('${source.path}/corpus.json').copySync('${temp.path}/corpus.json');
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

void main() {
  test('habit voice flow creates, checks in, and refuses duplicate days',
      () async {
    final session = await _session();

    expect(
      (await session.handle('track meditation as a habit')).toLowerCase(),
      contains('started tracking meditation'),
    );
    final habit = session.store.values.singleWhere(
      (record) => record['typeId'] == 'habit',
    );
    expect(habit['targetPerWeek'], 7);

    expect(
      (await session.handle('i did my meditation habit')).toLowerCase(),
      contains('checked in meditation'),
    );
    expect(
      session.store.values.where((r) => r['typeId'] == 'habit_checkin'),
      hasLength(1),
    );
    expect(
      (await session.handle('i did my meditation habit')).toLowerCase(),
      contains('already checked in'),
    );
    expect(
      session.store.values.where((r) => r['typeId'] == 'habit_checkin'),
      hasLength(1),
    );

    final progress = (await session.handle('how is my meditation habit going'))
        .toLowerCase();
    expect(progress, contains('meditation: 1 of 7 this week'));
    expect(progress, contains('1-day streak'));

    final status = habitStatuses(session.store, session.now).single;
    expect(status.completedToday, isTrue);
    expect(status.completedThisWeek, 1);
    expect(status.currentStreakDays, 1);
  });

  test('voice cadence is bounded and preserves a requested weekly target',
      () async {
    final session = await _session();

    expect(
      (await session.handle('track strength training 3 times a week'))
          .toLowerCase(),
      contains('3 time(s) a week'),
    );
    expect(
      session.store.values
          .singleWhere((r) => r['typeId'] == 'habit')['targetPerWeek'],
      3,
    );
    expect(
      (await session.handle('track stretching 9 times a week')).toLowerCase(),
      contains('from 1 to 7'),
    );
    expect(
      session.store.values.where((r) => r['typeId'] == 'habit'),
      hasLength(1),
    );
  });

  test('typed habit check-in is targeted-undoable and habit delete cascades',
      () async {
    final session = await _session();
    final created = await session.createRecord('habit', {
      'title': 'Walk after lunch',
      'targetPerWeek': 5,
      'status': 'active',
      'createdAt': session.now.toIso8601String(),
    });
    expect(created.ok, isTrue);
    final habit = session.store.values.singleWhere(
      (record) => record['typeId'] == 'habit',
    );

    final checkIn = await session.recordHabitCheckIn('${habit['id']}');
    expect(checkIn.ok, isTrue);
    expect(habitStatuses(session.store, session.now).single.completedToday,
        isTrue);
    expect(await session.undoById(checkIn.undoId!), contains('Undone'));
    expect(habitStatuses(session.store, session.now).single.completedToday,
        isFalse);

    await session.recordHabitCheckIn('${habit['id']}');
    final deleted = await session.deleteRecord('${habit['id']}');
    expect(deleted.ok, isTrue);
    expect(session.store.values.where((r) => r['typeId'] == 'habit_checkin'),
        isEmpty);
    expect(await session.undoById(deleted.undoId!), contains('Undone'));
    expect(session.store.values.where((r) => r['typeId'] == 'habit'),
        hasLength(1));
    expect(session.store.values.where((r) => r['typeId'] == 'habit_checkin'),
        hasLength(1));
  });
}
