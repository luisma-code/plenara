import 'dart:convert';
import 'dart:io';
import 'package:plenara/claude.dart';
import 'package:plenara/guide.dart';
import 'package:plenara/session.dart';
import 'package:plenara/habits.dart';
import 'package:plenara/people.dart';
import 'package:test/test.dart';
import 'helpers.dart';

class Conversation implements GuideClient {
  final List<Map<String, dynamic>> outputs;
  final inputs = <List<Map<String, dynamic>>>[];
  Conversation(this.outputs);
  @override
  Future<CloudResult<Map<String, dynamic>>> respond(
      List<Map<String, dynamic>> input,
      List<Map<String, dynamic>> tools) async {
    inputs.add(jsonDecode(jsonEncode(input)).cast<Map<String, dynamic>>());
    return CloudOk({'output': outputs.removeAt(0)['output']});
  }
}

Map<String, dynamic> reply(String text) => {
      'output': [
        {
          'type': 'message',
          'content': [
            {'type': 'output_text', 'text': text}
          ]
        }
      ]
    };
Map<String, dynamic> call(String name, Map<String, dynamic> args) => {
      'output': [
        {
          'type': 'function_call',
          'call_id': 'call-${DateTime.now().microsecondsSinceEpoch}',
          'name': name,
          'arguments': jsonEncode(args)
        }
      ]
    };
void main() {
  late String root, device;
  final now = DateTime(2026, 9, 26, 12);
  setUp(() {
    root = makeTempDataDir();
    device = Directory.systemTemp.createTempSync('guide_device_').path;
  });
  tearDown(() {
    Directory(root).deleteSync(recursive: true);
    Directory(device).deleteSync(recursive: true);
  });
  Future<Session> session(GuideClient guide) async {
    final s = Session(root, deviceDir: device, guide: guide, clock: now);
    await s.init(retrieval: false);
    return s;
  }

  test(
      'Help seeking is a conversation, never an implicit mood log; transcript resumes',
      () async {
    final guide = Conversation([
      reply('Let’s start with one person.'),
      reply('Alex could be that person.')
    ]);
    var s = await session(guide);
    final response = await s.converse(
        'I feel disconnected from my friends and I do not know where to start');
    expect(response, contains('one person'));
    expect(s.store.values.where((r) => r['typeId'] == 'mood'), isEmpty);
    await s.dispose();
    s = await session(guide);
    await s.converse('Who did we choose?');
    expect(jsonEncode(guide.inputs.last),
        contains('Let’s start with one person.'));
    final diagnostics = Directory(device)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('turnlog'))
        .map((f) => f.readAsStringSync())
        .join();
    expect(diagnostics, isNot(contains('I feel disconnected')));
    await s.dispose();
  });
  test(
      'Mixed receipt is reviewed, atomic, restart safe, undoable, with forward references',
      () async {
    final guide = Conversation([
      call('propose_changes', {
        'title': 'Lunch and follow-through',
        'changes': [
          {
            'operation': 'create',
            'type': 'task',
            'id': 'new:task',
            'reason': 'Your promise',
            'fields': {
              'description': 'Send Alex the guide',
              'contactRefs': ['new:alex']
            }
          },
          {
            'operation': 'create',
            'type': 'contact',
            'id': 'new:alex',
            'reason': 'The person you named',
            'fields': {'displayName': 'Alex'}
          },
          {
            'operation': 'create',
            'type': 'interaction',
            'id': 'new:lunch',
            'reason': 'Lunch yesterday',
            'fields': {
              'subject': 'new:alex',
              'at': '2026-09-25',
              'kind': 'in_person',
              'connectionDepth': 'meaningful'
            }
          },
        ]
      }),
      reply('I proposed your lunch and follow-up.')
    ]);
    var s = await session(guide);
    await s.converse('Lunch with Alex yesterday; promised the guide.');
    expect(s.store, isEmpty);
    expect(s.guideReceipt, isNotNull);
    final savedReceipt = jsonEncode({'receipt': s.guideReceipt!.toJson()});
    await s.dispose();
    s = await session(Conversation([]));
    final result = await s.applyGuideReceipt();
    expect(result.ok, isTrue, reason: result.message);
    expect(result.undoId, isNotNull);
    expect(s.store.length, 3);
    await s.dispose();
    File('$device/guide-receipt.json').writeAsStringSync(savedReceipt);
    s = await session(Conversation([]));
    expect(s.guideReceipt, isNull);
    expect(s.store.length, 3);
    await s.undoById(result.undoId!);
    expect(s.store, isEmpty);
    await s.dispose();
  });
  test('Invalid mixed receipt applies nothing and stays editable', () async {
    final guide = Conversation([
      call('propose_changes', {
        'title': 'Invalid',
        'changes': [
          {
            'operation': 'create',
            'type': 'task',
            'id': 'new:t',
            'reason': 'Valid task',
            'fields': {'description': 'Valid'}
          },
          {
            'operation': 'create',
            'type': 'habit_checkin',
            'id': 'new:c',
            'reason': 'Invalid',
            'fields': {'habit': 'nonexistent', 'date': '2026-09-26'}
          },
        ]
      }),
      reply('Review these updates.')
    ]);
    final s = await session(guide);
    await s.converse('Capture');
    final result = await s.applyGuideReceipt();
    expect(result.ok, isFalse);
    expect(s.store, isEmpty);
    expect(s.guideReceipt, isNotNull);
    await s.removeGuideReceiptChange(1);
    expect((await s.applyGuideReceipt()).ok, isTrue);
    expect(s.store.length, 1);
    await s.dispose();
  });
  test(
      'Forbidden record classes and contact identifiers never reach guide tools',
      () async {
    final guide = Conversation([
      call('search_records', {'type': 'mood'}),
      call('search_records', {'type': 'contact'}),
      reply('No private journal access.')
    ]);
    final s = await session(guide);
    final created = await s.createRecord('contact', {
      'displayName': 'Alex',
      'primaryPhone': '555-CANARY',
      'primaryEmail': 'secret@example.test'
    });
    expect(created.ok, isTrue, reason: created.message);
    await s.converse('Find relevant context');
    final payload = jsonEncode(guide.inputs.last);
    expect(payload, isNot(contains('555-CANARY')));
    expect(payload, isNot(contains('secret@example.test')));
    expect(payload, contains('not permitted'));
    await s.dispose();
  });
  test(
      'Relationship unknown is not due; acknowledgement does not fabricate interaction',
      () async {
    final s = await session(Conversation([]));
    await s.createRecord('contact', {
      'displayName': 'Alex',
      'relationshipCircle': 'close',
      'proximity': 'local'
    });
    final person = s.store.values.single;
    expect(relationshipStatuses(s.store, now).single.needsContact, isFalse);
    final result = await s.acknowledgeRelationship('${person['id']}');
    expect(result.ok, isTrue);
    expect(relationshipStatuses(s.store, now).single.acknowledged, isTrue);
    expect(s.store.values.where((r) => r['typeId'] == 'interaction'), isEmpty);
    await s.dispose();
  });
  test('Minimum, skip, unknown and flexible rest retain distinct meaning',
      () async {
    final s = await session(Conversation([]));
    await s.createRecord('habit', {
      'title': 'Walk',
      'targetPerWeek': 3,
      'preferredDays': '1,3,5',
      'minimumVersion': 'Two minutes',
      'createdAt': now.toIso8601String()
    });
    final id = '${s.store.values.single['id']}';
    var state = habitStatuses(s.store, now).single;
    expect(state.dueToday, isFalse);
    expect(state.completedToday, isFalse);
    expect(state.skippedToday, isFalse);
    await s.recordHabitCheckIn(id, outcome: 'skipped');
    state = habitStatuses(s.store, now).single;
    expect(state.skippedToday, isTrue);
    expect(state.completedThisWeek, 0);
    await s.recordHabitCheckIn(id, outcome: 'minimum');
    state = habitStatuses(s.store, now).single;
    expect(state.completedToday, isTrue);
    expect(state.completedThisWeek, 1);
    expect(
        s.store.values.where((r) => r['typeId'] == 'habit_checkin').length, 1);
    await s.dispose();
  });
  test('Spending gate persists reservations, rejects corruption and rollback',
      () {
    final path = '$device/budget.json';
    final budget = GuideBudget(path, 10, clock: () => now);
    final reservation = budget.reserve(1000)!;
    expect(reservation, greaterThan(1.28));
    budget.settle(reservation, {'input_tokens': 5000, 'output_tokens': 1000});
    expect(budget.snapshot['spent'], closeTo(.02, .000001));
    expect(GuideBudget(path, .01, clock: () => now).reserve(1), isNull);
    expect(GuideBudget(path, 10, clock: () => DateTime(2026, 8)).reserve(1),
        isNull);
    File(path).writeAsStringSync('{"month":"garbage","spent":0,"reserved":0}');
    expect(budget.reserve(1), isNull);
  });
  test('Responses transport requests no hosted storage, settles real usage',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? body;
    final receive = server.first.then((request) async {
      body = jsonDecode(await utf8.decoder.bind(request).join());
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'status': 'completed',
        'output': reply('Hello')['output'],
        'usage': {'input_tokens': 5000, 'output_tokens': 1000}
      }));
      await request.response.close();
    });
    final budget = GuideBudget('$device/budget.json', 10, clock: () => now);
    final client = OpenAiGuide(
        key: 'fake-test-key',
        budget: budget,
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/responses'));
    expect(
        await client.respond([
          {'role': 'user', 'content': 'Hi'}
        ], guideTools),
        isA<CloudOk<Map<String, dynamic>>>());
    await receive;
    await server.close(force: true);
    expect(body!['store'], isFalse);
    expect(body!['model'], guideModel);
    expect(body!['max_output_tokens'], 128000);
    expect(budget.snapshot['spent'], closeTo(.02, .000001));
    expect(budget.snapshot['reserved'], 0);
  });
}
