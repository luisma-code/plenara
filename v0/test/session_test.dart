/// End-to-end turn engine (Session) over the OFFLINE corpus paths + system
/// commands + cross-skill integration. A _NoCloud client throws if the cloud is
/// hit, proving these flows are fully deterministic (no network). Cloud paths are
/// covered separately in cloud_test.dart via the replay cassette.
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:plenara/storage_repository.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');

/// An in-memory StorageRepository — proves the seam is real (nothing about
/// Session depends on the filesystem backend).
class _MemStorage implements StorageRepository {
  final Map<String, Map<String, dynamic>> types, skills;
  final Map<String, Map<String, dynamic>> records = {};
  final List<dynamic> learned = [];
  final List<Map<String, dynamic>> turns = [];
  _MemStorage(this.types, this.skills);
  @override
  Map<String, Map<String, dynamic>> loadDefs(String subdir, String key) =>
      subdir == 'types' ? types : (subdir == 'skills' ? skills : <String, Map<String, dynamic>>{});
  @override
  Map<String, Map<String, dynamic>> loadRecords() => {for (final e in records.entries) e.key: Map.of(e.value)};
  @override
  void persist(Map<String, dynamic> record) => records[record['id'] as String] = Map.of(record);
  @override
  void remove(String id) => records.remove(id);
  @override
  List<dynamic> loadCorpusLearned() => learned;
  @override
  void appendCorpusLearned(Map<String, dynamic> entry) => learned.add(entry);
  @override
  void removeCorpusLearned(String template) => learned.removeWhere((e) => (e as Map)['template'] == template);
  @override
  void writeDef(String subdir, String idKey, Map<String, dynamic> def) =>
      (subdir == 'types' ? types : skills)[def[idKey] as String] = def;
  @override
  void logTurn(Map<String, dynamic> entry) => turns.add(entry);
}

class _NoCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
          String utterance, Map<String, Map<String, dynamic>> skills) async =>
      throw StateError('cloud routeResidual called for "$utterance" — expected a corpus/offline path');
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String description, {String? priorError}) async =>
      throw StateError('cloud authorCapability called — expected a corpus/offline path');
  @override
  Future<CloudResult<String>> generate(String kind, String context) async =>
      throw StateError('cloud generate called — expected a corpus/offline path');
}

Future<Session> _session([String? dir]) async {
  final s = Session(dir ?? makeTempDataDir(), clock: _now, cloud: _NoCloud());
  await s.init(retrieval: false);
  return s;
}

void main() {
  group('hero-example turns route + describe (offline corpus)', () {
    final cases = <String, String>{
      'add call the plumber to my to-do list': 'call the plumber',
      'remind me to buy milk': 'buy milk',
      'remind me to email the accountant on thursday': 'due Thursday',
      'add wash the car to my list due tomorrow': 'due Tuesday',
      'log a 5k run': '5 km run',
      'i ran 8k': '8 km run',
      'log a run': 'Logged a run',
      "i'm feeling great": 'mood as great',
      'log my mood as anxious': 'mood as anxious',
      'note that Mia loves drawing': 'Noted that Mia loves drawing',
      'list my tasks': '0 task',
      'how many runs this week': 'so far this week',
    };
    cases.forEach((utterance, expected) {
      test('"$utterance" -> contains "$expected"', () async {
        final s = await _session();
        expect(await s.handle(utterance), contains(expected));
      });
    });
  });

  group('due-tasks (agenda view)', () {
    test('shows overdue + due-today, excludes future / no-date / completed', () async {
      final s = await _session(); // clock is Monday 2026-07-06
      await s.handle('add pay rent to my list due yesterday'); // overdue (07-05)
      await s.handle('add call the bank to my list due today'); // due today
      await s.handle('add book flights to my list due friday'); // future (07-10)
      await s.handle('add water the plants to my list'); // no due date
      final r = await s.handle("what's due");
      expect(r, contains('pay rent'));
      expect(r, contains('overdue'));
      expect(r, contains('call the bank'));
      expect(r, contains('due today'));
      expect(r.contains('book flights'), isFalse); // future excluded
      expect(r.contains('water the plants'), isFalse); // no-date excluded
    });

    test('completed tasks drop out; nothing due -> clear message', () async {
      final s = await _session();
      await s.handle('add call the bank to my list due today');
      await s.handle('mark call the bank done');
      expect(await s.handle('anything overdue'), contains("you're clear"));
    });

    test('reschedule-task moves a due date (out of the overdue set)', () async {
      final s = await _session(); // Monday 2026-07-06
      await s.handle('add pay rent to my list due today');
      await s.handle('move pay rent to friday'); // -> 2026-07-10 (future)
      final t = s.store.values.where((x) => x['typeId'] == 'task').single;
      expect(t['dueAt'], '2026-07-10');
      expect((await s.handle("what's due")).contains('pay rent'), isFalse); // now future
    });

    test('rescheduling an unknown task is a clear no-op', () async {
      final s = await _session();
      expect(await s.handle('move buy milk to friday'), contains("couldn't find"));
    });
  });

  group('realistic day — broad cross-skill integration (all offline)', () {
    test('tasks, reminders, people, birthdays, mood all cohere in one session', () async {
      final s = await _session(); // Monday 2026-07-06, _NoCloud (proves it's all corpus)

      // tasks + due
      await s.handle('add pay rent to my list due today');
      await s.handle('add book flights to my list due friday');
      expect(await s.handle("what's due"), contains('pay rent'));
      await s.handle('move pay rent to friday');
      expect((await s.handle("what's due")).toLowerCase(), contains("you're clear"));

      // people: relationship (the offline gap we closed) + interaction, queryable
      await s.handle("remember that Mia is Sarah Mitchell's daughter");
      expect(await s.handle('who is Mia related to'), contains('daughter of Sarah Mitchell'));
      await s.handle('talked to Sam about the trip');
      expect(await s.handle('when did i last talk to Sam'), contains('2026-07-06'));

      // birthdays
      await s.handle("Sarah Mitchell's birthday is july 10");
      expect(await s.handle('whose birthday is coming up'), contains('Sarah Mitchell'));

      // mood
      await s.handle("i'm feeling great");
      expect(await s.handle('how have i been feeling'), contains('great'));

      // undo the last write (the mood) leaves the rest intact
      await s.handle('undo');
      expect((await s.handle('how have i been feeling')).toLowerCase(), contains("haven't logged"));
      expect(await s.handle('who is Mia related to'), contains('Sarah Mitchell')); // untouched

      // sanity: nothing crashed, records are coherent
      expect(s.store.values.where((x) => x['typeId'] == 'task').length, 2);
      expect(s.store.values.where((x) => x['typeId'] == 'contact_relationship').length, 1);
    });
  });

  group('total-distance (aggregation via the new sum fn)', () {
    test('sums distance across all runs', () async {
      final s = await _session();
      await s.handle('log a 3k run');
      await s.handle('log a 5k run');
      final r = await s.handle('how far have i run');
      expect(r, contains('8')); // 3 + 5 km
      expect(r, contains('2 run'));
    });
  });

  group('run-streak', () {
    test('counts consecutive days of runs', () async {
      final dir = makeTempDataDir();
      for (final d in const ['2026-07-04', '2026-07-05', '2026-07-06']) {
        final s = Session(dir, clock: DateTime.parse('${d}T09:00:00'), cloud: _NoCloud());
        await s.init(retrieval: false);
        await s.handle('log a 3k run');
      }
      final s = await _session(dir); // queries at Monday 2026-07-06
      final r = await s.handle("what's my running streak");
      expect(r, contains('3 day(s) current'));
      expect(r, contains('3 day(s) longest'));
    });
    test('no runs -> friendly empty', () async {
      expect(await (await _session()).handle('running streak'), contains('No runs logged'));
    });
  });

  group('list-tasks hides completed (Fable#2)', () {
    test('a completed task drops off the list', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      await s.handle('add call the dentist to my list');
      await s.handle('mark buy milk as done');
      final r = await s.handle('list my tasks');
      expect(r, contains('call the dentist'));
      expect(r, isNot(contains('buy milk')));
      expect(r, contains('1 task'));
    });
  });

  group('record-anchored dates (F-19) — "the day before Sarah\'s birthday"', () {
    test('creates a task dated the day before the person\'s birthday', () async {
      final s = await _session();
      await s.handle("Sarah's birthday is july 16"); // creates Sarah + birthday
      final r = await s.handle("remind me to buy flowers the day before Sarah's birthday");
      expect(r, contains('buy flowers'));
      final tasks = s.store.values.where((x) => x['typeId'] == 'task').toList();
      expect(tasks.length, 1);
      expect(tasks.single['dueAt'], '2026-07-15'); // 16th minus one day
    });
    test('unknown person -> asks for their birthday, writes nothing', () async {
      final s = await _session();
      final r = await s.handle("add call the florist the day before Nobody's birthday");
      expect(r.toLowerCase(), contains("don't have"));
      expect(s.store.values.where((x) => x['typeId'] == 'task'), isEmpty);
    });
  });

  group('template instantiation (G-22 / #3)', () {
    test('"start tracking my water intake" instantiates the template free (no cloud), works by voice', () async {
      final s = await _session(); // _NoCloud throws if the cloud is hit
      final r = await s.handle('start tracking my water intake');
      expect(r.toLowerCase(), contains('set up'));
      expect(s.skills.containsKey('log-water'), isTrue);
      expect(s.types.containsKey('hydration'), isTrue);
      // corpus injected -> the new tracker routes immediately
      final logged = await s.handle('log 500ml of water');
      expect(logged, contains('500'));
      expect(s.store.values.where((x) => x['typeId'] == 'hydration').length, 1);
    });
    for (final c in const [
      ('reading', 'i read 30 pages', 'reading_log'),
      ('my meds', 'i took my meds', 'medication_log'),
      ('my steps', 'i walked 8000 steps', 'step_log'),
      ('my weight', 'i weigh 165', 'weight_log'),
    ]) {
      test('template "${c.$1}" instantiates free and routes its log by voice', () async {
        final s = await _session();
        expect((await s.handle('start tracking ${c.$1}')).toLowerCase(), contains('set up'));
        expect((await s.handle(c.$2)).toLowerCase(), contains('logged'));
        expect(s.store.values.where((x) => x['typeId'] == c.$3).length, 1);
      });
    }

    test('a template ships a QUERY skill too: "how many steps this week" aggregates (F-17)', () async {
      final s = await _session();
      await s.handle('start tracking my steps');
      await s.handle('i walked 8000 steps');
      await s.handle('i did 5000 steps today');
      final r = await s.handle('how many steps this week');
      expect(r, contains('13000'));
    });

    test('a template query skill computes a streak: reading streak (F-18)', () async {
      final s = await _session();
      await s.handle('start tracking my reading');
      await s.handle('i read 30 pages');
      expect((await s.handle("what's my longest reading streak")).toLowerCase(), contains('streak'));
    });

    test('re-instantiating is idempotent ("already tracking")', () async {
      final s = await _session();
      await s.handle('start tracking my water intake');
      expect((await s.handle('start tracking my water')).toLowerCase(), contains('already'));
      expect(s.store.values.where((x) => x['typeId'] == 'hydration'), isEmpty);
    });
    test('an instantiated tracker survives a restart (defs + corpus persisted)', () async {
      final dir = makeTempDataDir();
      final s1 = Session(dir, clock: _now, cloud: _NoCloud());
      await s1.init(retrieval: false);
      await s1.handle('start tracking my water intake');
      final s2 = Session(dir, clock: _now, cloud: _NoCloud());
      await s2.init(retrieval: false);
      expect(s2.skills.containsKey('log-water'), isTrue); // skill def persisted + loaded
      expect(await s2.handle('log 300ml of water'), contains('300')); // corpus persisted + loaded
    });
  });

  group('out-of-domain boundary (G-19)', () {
    test('a world-knowledge question gets a graceful boundary, writes nothing', () async {
      final s = await _session();
      final r = await s.handle("what's the capital of France");
      expect(r.toLowerCase(), contains('outside what'));
      expect(s.store, isEmpty);
    });
    test('a personal-cue query is NEVER classified out-of-domain (privacy, G-19)', () async {
      final s = await _session();
      // "weather" would trip the world-knowledge matcher, but "what did I…" is a personal cue
      final r = await s.handle('what did i say about the weather');
      expect(r.toLowerCase(), isNot(contains('outside what')));
    });
    test('"who is <a known contact>" is NOT out-of-domain (Fable#2 regression)', () async {
      final s = await _session();
      await s.handle('remember that Mia loves drawing'); // Mia is now a stored contact
      final r = await s.handle('who is Mia'); // "who is" trips world-knowledge, but Mia is ours
      expect(r.toLowerCase(), isNot(contains('outside what')));
    });
    test('"who is <a stranger>" still gets the boundary', () async {
      final s = await _session();
      final r = await s.handle('who is the president of france');
      expect(r.toLowerCase(), contains('outside what'));
    });
  });

  group('scope-denial floor (DF-10 / DP-03 / DP-04)', () {
    for (final u in const [
      'text Marco for me',
      'text Marco this opener',
      'add this to my Google Calendar',
      'buy the hiking boots for Sarah',
      'pay my rent',
      'send money to Sam',
      'book a table for two',
    ]) {
      test('refuses external action, offers the in-scope alternative: "$u"', () async {
        final s = await _session();
        final r = await s.handle(u);
        expect(r.toLowerCase(), contains("can't do that"));
        expect(s.store, isEmpty, reason: 'a scope refusal must not write');
      });
    }
    test('a real reminder/task containing "text"/"buy" is NOT refused', () async {
      final s = await _session();
      expect(await s.handle('remind me to text mom on thursday at 5pm'), isNot(contains("can't do that")));
      expect(await s.handle('add buy milk to my list'), contains('buy milk'));
    });
  });

  group('05a corpus-phrasing (F-05 run+duration, F-10 time-since via alias)', () {
    test('F-05: "ran 5k in 27 minutes" records distance + duration', () async {
      final s = await _session();
      await s.handle('ran 5k in 27 minutes');
      final w = s.store.values.where((x) => x['typeId'] == 'workout').single;
      expect(w['distance'], 5);
      expect(w['duration'], 27);
    });
    test('F-10: "how long since I called Mum" resolves via alias to last-interaction', () async {
      final s = await _session();
      await s.handle('i talked to Sarah about the trip');
      await s.handle("Sarah's nickname is Mum");
      final r = await s.handle('how long since i called Mum');
      expect(r, isNot(contains("don't have")));
      expect(r, contains('Mum'));
    });
  });

  group('more denial floors (DP-06 medical, DP-09 impersonation, DF-03 schema-edit)', () {
    test('DP-06 medical: refuses to diagnose, defers to a professional', () async {
      final s = await _session();
      expect((await s.handle("based on my meds and symptoms, what's wrong with me")).toLowerCase(),
          contains("can't diagnose"));
      expect((await s.handle('do i have cancer')).toLowerCase(), contains("can't diagnose"));
    });
    test('DP-09 impersonation: refuses to speak as a third party', () async {
      final s = await _session();
      final r = await s.handle('write a message pretending to be my wife telling my mum she is fine with the plan');
      expect(r.toLowerCase(), contains('own voice'));
    });
    test('DF-03 schema-edit: adding a field to a live tracker is a paid change', () async {
      final s = await _session();
      expect((await s.handle('add a mood-score field to my running tracker')).toLowerCase(), contains('schema edit'));
    });
    test('normal inputs are not caught by the new floors', () async {
      final s = await _session();
      expect(await s.handle('add buy milk to my list'), contains('buy milk'));
      expect((await s.handle('log a 5k run')).toLowerCase(), contains('run'));
    });
  });

  group('aliases (G-24) — resolve a person by a nickname/role', () {
    test('set an alias, then reach the contact through it', () async {
      final s = await _session();
      await s.handle('i talked to Sarah about the cabin trip');
      final ack = await s.handle("Sarah's nickname is Mum");
      expect(ack, contains('Mum'));
      final r = await s.handle('when did i last talk to Mum'); // "Mum" only resolves via alias
      expect(r, isNot(contains("don't have")));
      expect(r, contains('last talked to Mum'));
    });
  });

  group('journaling', () {
    test('log a journal entry then read it back', () async {
      final s = await _session();
      expect(await s.handle('read my journal'), contains('empty'));
      await s.handle('journal that today was a good day');
      await s.handle('note in my journal that i started a new book');
      final r = await s.handle('read my journal');
      expect(r, contains('2 entries'));
      expect(r, contains('today was a good day'));
      expect(r, contains('started a new book'));
      expect(r, contains('2026-07-06')); // dated
    });
  });

  group('recall-mood', () {
    test('lists logged moods, with a clear message when there are none', () async {
      final s = await _session();
      expect(await s.handle('how have i been feeling'), contains("haven't logged any moods"));
      await s.handle("i'm feeling great");
      await s.handle('log my mood as tired');
      final r = await s.handle('show my moods');
      expect(r, contains('2 mood'));
      expect(r, contains('great'));
      expect(r, contains('tired'));
    });
  });

  group('cross-skill integration: write -> read', () {
    test('log a run, then the weekly count reflects it', () async {
      final s = await _session();
      await s.handle('log a 3k run');
      expect(await s.handle('how many runs this week'), contains("You've run 3 km"));
    });
    test('log two runs, count sums them', () async {
      final s = await _session();
      await s.handle('log a 3k run');
      await s.handle('i ran 4k');
      expect(await s.handle('how far have i run this week'), contains("You've run 7 km"));
    });
    test('remember a fact, then recall it', () async {
      final s = await _session();
      await s.handle('note that Mia loves drawing');
      final r = await s.handle('what do i know about Mia');
      expect(r, contains("Here's what I know about Mia"));
      expect(r, contains('loves drawing'));
    });
    test('add tasks, then list them', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      await s.handle('add walk the dog to my list');
      final r = await s.handle('list my tasks');
      expect(r, contains('2 task(s)'));
      expect(r, contains('buy milk'));
      expect(r, contains('walk the dog'));
    });
    test('relational remember creates the graph, recall reads the fact', () async {
      final s = await _session();
      final r = await s.handle("remember that Mia is allergic to peanuts and she is Sarah Mitchell's daughter");
      expect(r, contains('Noted that Mia'));
      // contact(Mia) + fact + contact(Sarah) + relationship = 4 records
      expect(s.store.length, 4);
      expect(await s.handle('what do i know about Mia'), contains('allergic to peanuts'));
    });
  });

  group('system commands: undo + correction', () {
    test('undo reverses the last write', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      expect(s.store.length, 1);
      expect(await s.handle('undo that'), contains('Undone'));
      expect(s.store.length, 0);
    });
    test('"what can you do" gives a grounded capability overview (no cloud, no write)', () async {
      final s = await _session();
      final r = await s.handle('what can you do');
      expect(r, contains('Here\'s what I can do'));
      expect(r, contains('Reminders'));
      expect(r, contains('Birthdays'));
      expect(r, contains('undo'));
      expect(s.store, isEmpty); // discoverability is read-only
    });
    test('undo with nothing to undo', () async {
      final s = await _session();
      expect(await s.handle('undo'), contains('Nothing to undo'));
    });
    test('multi-turn undo walks back the journal ring', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      await s.handle('add walk the dog to my list');
      await s.handle('log a 3k run');
      expect(s.store.length, 3);
      expect(await s.handle('undo that'), contains('run')); // reverses the most recent (the run)
      expect(s.store.length, 2);
      await s.handle('undo that'); // walk the dog
      await s.handle('undo that'); // buy milk
      expect(s.store.length, 0);
      expect(await s.handle('undo that'), contains('Nothing to undo'));
    });
    test('undo says what it reversed (transparent safety net)', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      final r = await s.handle('undo that');
      expect(r, contains('Undone'));
      expect(r, contains('buy milk')); // not a bare "Undone."
    });
    test('undo targets the last WRITE, skipping a read-only query', () async {
      final s = await _session();
      await s.handle('add buy milk to my list'); // write
      await s.handle('list my tasks'); // read-only, no before-images
      await s.handle('undo that');
      expect(s.store.length, 0);
    });
    test('correction "no, I meant to X" undoes then redoes', () async {
      final s = await _session();
      await s.handle('log a 5k run');
      final r = await s.handle('no, I meant to add buy running shoes to my list');
      expect(r, contains('buy running shoes'));
      expect(s.store.values.where((r) => r['typeId'] == 'workout'), isEmpty);
      expect(s.store.values.where((r) => r['typeId'] == 'task').length, 1);
    });
    test('correction after a NON-WRITING turn does not reverse an earlier write (Fable#2 P0)', () async {
      final s = await _session();
      await s.handle('add buy milk to my list'); // writes a task
      await s.handle('what can you do'); // help: early return, no write, stale-flag trap
      final r = await s.handle('no, I meant to log a 3k run'); // correction
      expect(r, contains('run'));
      // the milk task must survive — the correction must not reverse an unrelated older write
      expect(s.store.values.where((x) => x['typeId'] == 'task').length, 1, reason: 'milk survives');
      expect(s.store.values.where((x) => x['typeId'] == 'workout').length, 1);
    });
    test('mark a task done (update), then undo restores it as not-done', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      expect(await s.handle('mark buy milk as done'), contains('done'));
      expect(s.store.values.firstWhere((r) => r['typeId'] == 'task')['completed'], true);
      await s.handle('undo that');
      expect(s.store.values.firstWhere((r) => r['typeId'] == 'task')['completed'], false);
    });
    test('delete a task, then undo restores it', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      expect(await s.handle('delete buy milk from my list'), contains('Deleted'));
      expect(s.store.values.where((r) => r['typeId'] == 'task'), isEmpty);
      await s.handle('undo that');
      expect(s.store.values.where((r) => r['typeId'] == 'task').length, 1);
    });
    test('correction with a natural prefix ("sorry, I meant to X") also undoes then redoes', () async {
      final s = await _session();
      await s.handle('log a 5k run');
      final r = await s.handle('sorry, I meant to add buy milk to my list');
      expect(r, contains('buy milk'));
      expect(s.store.values.where((x) => x['typeId'] == 'workout'), isEmpty);
      expect(s.store.values.where((x) => x['typeId'] == 'task').length, 1);
    });
    test('F-14: "no, that was a walk" reverses the run and re-logs a walk, carrying distance', () async {
      final s = await _session();
      await s.handle('log a 5k run');
      expect(s.store.values.where((x) => x['typeId'] == 'workout' && x['activity'] == 'run').length, 1);
      final r = await s.handle('no, that was a walk');
      expect(r.toLowerCase(), contains('walk'));
      final workouts = s.store.values.where((x) => x['typeId'] == 'workout').toList();
      expect(workouts.length, 1, reason: 'the run was reversed, only the walk remains');
      expect(workouts.single['activity'], 'walk');
      expect(workouts.single['distance'], 5); // distance carried over from the run
    });
    test('F-15: "actually, 28 minutes" updates the last workout in place (not a reverse)', () async {
      final s = await _session();
      await s.handle('log a 5k run');
      final r = await s.handle('actually, 28 minutes');
      expect(r, contains('28'));
      final w = s.store.values.where((x) => x['typeId'] == 'workout').toList();
      expect(w.length, 1, reason: 'same record updated, not reversed+recreated');
      expect(w.single['duration'], 28);
      expect(w.single['distance'], 5); // untouched
      expect(w.single['activity'], 'run'); // still a run
    });
    test('F-15: "make it 3k" updates the distance of the last workout', () async {
      final s = await _session();
      await s.handle('log a 5k run');
      await s.handle('make it 3k');
      expect(s.store.values.where((x) => x['typeId'] == 'workout').single['distance'], 3);
    });
    test('F-15: undo restores the pre-correction value', () async {
      final s = await _session();
      await s.handle('log a 5k run');
      await s.handle('actually, 28 minutes');
      expect(await s.handle('undo that'), contains('Undone'));
      expect(s.store.values.where((x) => x['typeId'] == 'workout').single['duration'], isNull);
    });
    test('"no wait, I meant X" is a correction', () async {
      final s = await _session();
      await s.handle('log a 5k run');
      await s.handle('no wait, I meant to log a 3k run');
      final runs = s.store.values.where((x) => x['typeId'] == 'workout').toList();
      expect(runs.length, 1); // the 5k was reversed, only the 3k remains
      expect(runs.single['distance'], 3);
    });
    test('correction after a read-only misroute does not reverse an unrelated write (Fable defect)', () async {
      final s = await _session();
      await s.handle('add buy milk to my list'); // a write, two turns back
      await s.handle('list my tasks'); // read-only route (no write) — the misroute
      final r = await s.handle('no, I meant to log a 3k run'); // correction of the READ turn
      expect(r, contains('run'));
      expect(s.store.values.where((x) => x['typeId'] == 'task').length, 1); // milk task survives
      expect(s.store.values.where((x) => x['typeId'] == 'workout').length, 1);
    });
    test('scratch that / take that back also undo', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      expect(await s.handle('scratch that'), contains('Undone'));
      expect(s.store.length, 0);
    });
  });

  group('persistence across Session instances (same data dir)', () {
    test('a written record is loaded by a fresh Session on the same dir', () async {
      final dir = makeTempDataDir();
      final s1 = await _session(dir);
      await s1.handle('add buy milk to my list');
      final s2 = await _session(dir); // fresh instance, same folder
      expect(await s2.handle('list my tasks'), contains('buy milk'));
    });
    test('undo persists (deleted file does not reappear)', () async {
      final dir = makeTempDataDir();
      final s1 = await _session(dir);
      await s1.handle('add buy milk to my list');
      await s1.handle('undo that');
      final s2 = await _session(dir);
      expect(await s2.handle('list my tasks'), contains('0 task(s)'));
    });
  });

  group('StorageRepository seam (Fable review)', () {
    test('Session runs on an injected in-memory repository (no disk touched)', () async {
      final file = FileStorageRepository('data');
      final mem = _MemStorage(file.loadDefs('types', 'typeId'), file.loadDefs('skills', 'skillId'));
      final s = Session('data', clock: _now, cloud: _NoCloud(), storage: mem);
      await s.init(retrieval: false);
      await s.handle('add buy milk to my list');
      final tasks = mem.records.values.where((r) => r['typeId'] == 'task').toList();
      expect(tasks.length, 1);
      expect(tasks.single['description'], 'buy milk');
      // undo goes through the repo too
      await s.handle('undo that');
      expect(mem.records.values.where((r) => r['typeId'] == 'task'), isEmpty);
    });

    test('turn log records the source + skill of each turn (dogfood telemetry)', () async {
      final file = FileStorageRepository('data');
      final mem = _MemStorage(file.loadDefs('types', 'typeId'), file.loadDefs('skills', 'skillId'));
      final s = Session('data', clock: _now, cloud: _NoCloud(), storage: mem);
      await s.init(retrieval: false);
      await s.handle('add buy milk to my list');
      await s.handle('list my tasks');
      await s.handle('undo that');
      expect(mem.turns.map((t) => t['source']).toList(), ['corpus', 'corpus', 'undo']);
      expect(mem.turns[0]['skill'], 'create-task');
      expect(mem.turns[1]['skill'], 'list-tasks');
    });

    test('turn log is a rich debug trace — template, slots, writes, timing, response', () async {
      final file = FileStorageRepository('data');
      final mem = _MemStorage(file.loadDefs('types', 'typeId'), file.loadDefs('skills', 'skillId'));
      final s = Session('data', clock: _now, cloud: _NoCloud(), storage: mem);
      await s.init(retrieval: false);
      await s.handle('add buy milk to my list');
      final t = mem.turns.single;
      expect(t['template'], 'add {description:text} to my {_:text}'); // which corpus template fired
      expect((t['slots'] as Map)['description'], 'buy milk'); // what was extracted
      final writes = (t['writes'] as List).cast<Map>();
      expect(writes.single['op'], 'write');
      expect(writes.single['typeId'], 'task'); // what record was written
      expect(t['response'], contains('buy milk')); // what the user was told
      expect(t['ms'], isA<int>()); // timing
      expect(t.containsKey('error'), isFalse);
    });

    test('a crashing turn logs the exception + stack to the trace (never to the user)', () async {
      final file = FileStorageRepository('data');
      final mem = _MemStorage(file.loadDefs('types', 'typeId'), file.loadDefs('skills', 'skillId'));
      // a cloud that throws forces the handle() catch-all on a corpus-miss turn
      final s = Session('data', clock: _now, cloud: _NoCloud(), storage: mem);
      await s.init(retrieval: false);
      final resp = await s.handle('zubble frotz wibble'); // corpus miss -> _NoCloud throws
      expect(resp, contains("didn't do anything")); // user sees the safe message
      final t = mem.turns.single;
      expect(t['source'], 'error');
      expect(t['error'], contains('StateError')); // full detail is in the trace
    });
  });

  group('compound utterances (F-13) — two commands joined by "and"', () {
    test('"log a run and journal that I feel great" performs BOTH, composed confirmation', () async {
      final s = await _session(); // _NoCloud: the split is fully offline
      final r = await s.handle('log a run and journal that I feel great');
      expect(r, contains('Logged a run'));
      expect(r, contains('Saved to your journal'));
      expect(s.store.values.where((x) => x['typeId'] == 'workout').length, 1);
      final j = s.store.values.where((x) => x['typeId'] == 'journal_entry').toList();
      expect(j.length, 1);
      expect(j.single['entry'], 'I feel great');
    });

    test('slots survive the split: "log a 3k run and i\'m feeling great"', () async {
      final s = await _session();
      final r = await s.handle("log a 3k run and i'm feeling great");
      expect(r, contains('3 km run'));
      expect(r, contains('mood as great'));
      expect(s.store.values.where((x) => x['typeId'] == 'workout').single['distance'], 3);
      expect(s.store.values.where((x) => x['typeId'] == 'mood').single['rating'], 'great');
    });

    test('write-then-read compound executes in order: the read sees the write', () async {
      final s = await _session();
      final r = await s.handle('log a 3k run and how far have i run');
      expect(r, contains('Logged a 3 km run'));
      expect(r, contains("You've run 3 km")); // the total includes the run logged a moment before
    });

    test('", and" seam also splits', () async {
      final s = await _session();
      final r = await s.handle('log a run, and journal that I feel great');
      expect(r, contains('Logged a run'));
      expect(r, contains('Saved to your journal'));
      expect(s.store.values.where((x) => x['typeId'] == 'workout').length, 1);
      expect(s.store.values.where((x) => x['typeId'] == 'journal_entry').length, 1);
    });

    test('undo after a compound walks back one action at a time, most recent first', () async {
      final s = await _session();
      await s.handle('log a run and journal that I feel great');
      await s.handle('undo that'); // reverses the journal entry (the most recent write)
      expect(s.store.values.where((x) => x['typeId'] == 'journal_entry'), isEmpty);
      expect(s.store.values.where((x) => x['typeId'] == 'workout').length, 1);
      await s.handle('undo that'); // then the run
      expect(s.store.values.where((x) => x['typeId'] == 'workout'), isEmpty);
    });

    test('compound turn is logged with source=compound and both skills (telemetry)', () async {
      final file = FileStorageRepository('data');
      final mem = _MemStorage(file.loadDefs('types', 'typeId'), file.loadDefs('skills', 'skillId'));
      final s = Session('data', clock: _now, cloud: _NoCloud(), storage: mem);
      await s.init(retrieval: false);
      await s.handle('log a run and journal that I feel great');
      expect(mem.turns.single['source'], 'compound');
      expect(mem.turns.single['skill'], 'log-run+log-journal');
    });

    // ---- negative controls: single commands that CONTAIN "and" must NOT split ----

    test('control: "remind me to buy milk and eggs" is ONE task, not two', () async {
      final s = await _session();
      final r = await s.handle('remind me to buy milk and eggs');
      expect(r, contains('buy milk and eggs'));
      final tasks = s.store.values.where((x) => x['typeId'] == 'task').toList();
      expect(tasks.length, 1, reason: 'a whole-utterance corpus match always wins over a split');
      expect(tasks.single['description'], 'buy milk and eggs');
    });

    test('control: "talked to Sam and Jo about the trip" is ONE interaction', () async {
      final s = await _session();
      await s.handle('talked to Sam and Jo about the trip');
      expect(s.store.values.where((x) => x['typeId'] == 'interaction').length, 1);
      // the compound NAME stays intact — nothing was split into two dispatches
      expect(s.store.values.where((x) => x['typeId'] == 'contact' && x['displayName'] == 'Sam and Jo').length, 1);
    });

    test('control: seed template with a literal "and" (relational remember) still routes whole', () async {
      final s = await _session();
      await s.handle("remember that Mia is allergic to peanuts and she is Sarah Mitchell's daughter");
      expect(s.store.length, 4); // contact(Mia) + fact + contact(Sarah) + relationship — unchanged
    });

    test('control: "note that Mia loves drawing and painting" keeps the fact whole', () async {
      final s = await _session();
      await s.handle('note that Mia loves drawing and painting');
      final facts = s.store.values.where((x) => x['typeId'] == 'contact_fact').toList();
      expect(facts.length, 1);
      expect(facts.single['fact'], 'loves drawing and painting');
    });

    test('control: one half not routing means NO split and NO half-execution', () async {
      final s = await _session();
      // "log a run" routes but "dance a jig" does not -> not a compound; falls to the
      // residual path (_NoCloud throws -> the safe catch-all). Crucially: NOTHING was written.
      final r = await s.handle('log a run and dance a jig');
      expect(r, contains("didn't do anything"));
      expect(s.store, isEmpty, reason: 'a declined split must have zero side effects');
    });
  });

  group('multi-turn story (the full offline pipeline)', () {
    test('a realistic sequence keeps consistent state', () async {
      final s = await _session();
      expect(await s.handle('add call the plumber to my to-do list'), contains('call the plumber'));
      expect(await s.handle('add buy milk to my list'), contains('buy milk'));
      expect(await s.handle('list my tasks'), contains('2 task(s)'));
      expect(await s.handle('undo that'), contains('Undone')); // undoes the last add (buy milk)
      expect(await s.handle('list my tasks'), contains('1 task(s)'));
      await s.handle('log a 6k run');
      expect(await s.handle('how many runs this week'), contains("You've run 6 km"));
      await s.handle('note that Tom fixed the sink');
      expect(await s.handle('tell me about Tom'), contains('fixed the sink'));
    });
  });
}
