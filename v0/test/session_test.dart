/// End-to-end turn engine (Session) over the OFFLINE corpus paths + system
/// commands + cross-skill integration. A _NoCloud client throws if the cloud is
/// hit, proving these flows are fully deterministic (no network). Cloud paths are
/// covered separately in cloud_test.dart via the replay cassette.
import 'dart:convert';
import 'dart:io';

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

/// A cloud with no key set — every call fails cleanly with noKey (the common pre-BYOK dogfood
/// state), so a miss is a real "corpus + cloud couldn't help" rather than a thrown exception.
class _NoKeyCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s) async =>
      const CloudError(CloudErrorKind.noKey);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      const CloudError(CloudErrorKind.noKey);
  @override
  Future<CloudResult<String>> generate(String k, String c) async => const CloudError(CloudErrorKind.noKey);
}

Future<Session> _session([String? dir]) async {
  final s = Session(dir ?? makeTempDataDir(), clock: _now, cloud: _NoCloud());
  await s.init(retrieval: false);
  return s;
}

void main() {
  group('device-local artifacts stay off the synced folder (CS-01/CS-02)', () {
    test('injected deviceDir holds deviceId + turnlog; the synced dataDir stays clean', () async {
      final dataDir = makeTempDataDir();
      final deviceDir = Directory.systemTemp.createTempSync('plenara-dev').path;
      final s = Session(dataDir, clock: _now, cloud: _NoCloud(), deviceDir: deviceDir);
      await s.init(retrieval: false);
      await s.handle('log a run'); // a real turn -> a turnlog line + a minted deviceId
      expect(File('$deviceDir/.device-id').existsSync(), isTrue);
      expect(File('$deviceDir/turnlog.jsonl').existsSync(), isTrue);
      expect(File('$dataDir/.device-id').existsSync(), isFalse, reason: 'a synced deviceId defeats the HLC tie-break');
      expect(File('$dataDir/turnlog.jsonl').existsSync(), isFalse, reason: 'telemetry must not ride the sync folder');
    });
    test('default deviceDir keeps them in dataDir (backward-compatible CLI/tests)', () async {
      final dataDir = makeTempDataDir();
      final s = Session(dataDir, clock: _now, cloud: _NoCloud());
      await s.init(retrieval: false);
      await s.handle('log a run');
      expect(File('$dataDir/turnlog.jsonl').existsSync(), isTrue);
    });
  });

  group('corrupt files are surfaced, never silently dropped or crashed (P2.8, Spec 06)', () {
    test('a corrupt record file is skipped AND surfaced for repair', () async {
      final dataDir = makeTempDataDir();
      Directory('$dataDir/records').createSync(recursive: true);
      File('$dataDir/records/bad.json').writeAsStringSync('{ this is not json');
      final s = Session(dataDir, clock: _now, cloud: _NoCloud());
      await s.init(retrieval: false); // must NOT throw
      expect(s.corruptFiles.any((p) => p.endsWith('bad.json')), isTrue);
    });
    test('a corrupt type def does not crash startup (loadDefs was an unguarded throw)', () async {
      final dataDir = makeTempDataDir();
      File('$dataDir/types/bad.json').writeAsStringSync('not json at all');
      final s = Session(dataDir, clock: _now, cloud: _NoCloud());
      await s.init(retrieval: false); // previously threw and bricked startup
      expect(s.corruptFiles.any((p) => p.endsWith('bad.json')), isTrue);
    });
  });

  group('automation Review Feed — approve/decline a held write from the chat (Spec 02 §7.5)', () {
    Map<String, dynamic> stretchAutomation() => {
          'automationId': 'stretch-after-run',
          'targetType': 'workout',
          'condition': {'kind': 'onWrite', 'afterField': 'date'},
          'skillId': 'stretch-skill',
          'description': 'add a stretch task after a workout',
          'skill': {
            'skillId': 'stretch-skill', 'displayName': 'Stretch task', 'inputs': [], 'reads': [], 'writes': ['task'],
            'steps': {
              'main': [
                {'op': 'compute', 'fn': 'today', 'into': 'ca'},
                {'op': 'write_record', 'typeId': 'task', 'fields': {'description': 'stretch', 'createdAt': {'var': 'ca'}}, 'into': 'r'},
                {'op': 'format', 'template': 'queued a stretch task', 'into': 'confirmationText'},
              ]
            }
          }
        };
    Future<Session> withStretch() async {
      final dir = makeTempDataDir();
      Directory('$dir/automations').createSync(recursive: true);
      File('$dir/automations/stretch.json').writeAsStringSync(jsonEncode(stretchAutomation()));
      final s = Session(dir, clock: _now, cloud: _NoCloud());
      await s.init(retrieval: false);
      return s;
    }

    bool hasStretch(Session s) => s.store.values.any((x) => x['typeId'] == 'task' && x['description'] == 'stretch');

    test('a writing automation is HELD (not applied) until "approve it"', () async {
      final s = await withStretch();
      await s.handle('log a run'); // fires the automation, whose plan WRITES -> held for review
      expect(hasStretch(s), isFalse, reason: 'a writing automation must not auto-apply');
      expect(s.automations.pendingReview, isNotEmpty);
      expect((await s.handle('approve it')).toLowerCase(), contains('applied'));
      expect(hasStretch(s), isTrue);
    });
    test('"dismiss it" reaps the held write, nothing applied', () async {
      final s = await withStretch();
      await s.handle('log a run');
      expect((await s.handle('dismiss it')).toLowerCase(), contains('dismissed'));
      expect(hasStretch(s), isFalse);
      expect(s.automations.pendingReview, isEmpty);
    });
  });

  group('gap-fill batch — new capabilities', () {
    test('partial description: "remove milk from my list" matches "buy milk"', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      await s.handle('remove milk from my list');
      expect(s.store.values.where((x) => x['typeId'] == 'task' && x['completed'] != true), isEmpty);
    });
    test('log-workout logs a generic activity', () async {
      final s = await _session();
      await s.handle('i did a 45 minute bike ride');
      final w = s.store.values.firstWhere((x) => x['typeId'] == 'workout');
      expect(w['activity'].toString().toLowerCase(), contains('bike'));
    });
    test('list-meals shows today\'s meals', () async {
      final s = await _session();
      await s.handle('i ate a banana');
      expect((await s.handle('what did i eat today')).toLowerCase(), contains('banana'));
    });
    test('walk-distance totals walks', () async {
      final s = await _session();
      await s.handle('log a 3k walk');
      expect(await s.handle('how far have i walked'), contains('3'));
    });
    test('recall-latest-journal returns the last entry', () async {
      final s = await _session();
      await s.handle('journal that today was productive');
      expect((await s.handle('read my last journal entry')).toLowerCase(), contains('productive'));
    });
    test('list-completed-tasks after completing one', () async {
      final s = await _session();
      await s.handle('add call the bank to my list');
      await s.handle('mark call the bank as done');
      expect((await s.handle('what have i completed')).toLowerCase(), contains('bank'));
    });
  });

  group('tracker query gaps (dogfood)', () {
    test('reading-today sums pages read today', () async {
      final s = await _session();
      await s.handle('start tracking my reading');
      await s.handle('i read 20 pages');
      expect(await s.handle('how many pages today'), contains('20'));
    });
    test('water-this-week query routes + runs', () async {
      final s = await _session();
      await s.handle('start tracking my water');
      expect((await s.handle('how much water this week')).toLowerCase(), contains('water'));
    });
  });

  group('latest-weight — weight tracker query (was missing)', () {
    test('logs then reports the most recent weight', () async {
      final s = await _session();
      await s.handle('start tracking my weight');
      await s.handle('i weigh 180');
      expect((await s.handle("what's my weight")), contains('180'));
    });
  });

  group('clear-tasks — bulk delete + undo', () {
    test('"delete all my tasks" clears the list with a count', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      await s.handle('add call mom to my list');
      final r = await s.handle('delete all my tasks');
      expect(r.toLowerCase(), contains('cleared'));
      expect(r, contains('2'));
    });
    test('clear on an empty list says so', () async {
      final s = await _session();
      expect((await s.handle('delete all todos')).toLowerCase(), contains('already empty'));
    });
    test('undo restores the cleared tasks', () async {
      final s = await _session();
      await s.handle('add buy milk to my list');
      await s.handle('delete all my tasks');
      await s.handle('undo that');
      expect(await s.handle('list my tasks'), contains('buy milk'));
    });
  });

  group('helpful replies for meta-questions', () {
    test('"can I start a todo list" explains the built-in list instead of missing', () async {
      final s = await _session();
      final r = (await s.handle('can i start a todo list')).toLowerCase();
      expect(r, contains('add')); // guidance, not "I didn't catch that"
      expect(r, isNot(contains("didn't catch")));
    });
  });

  group('reference KB — offline calorie lookup (Spec 13)', () {
    test('a known food attaches calories + reference provenance', () async {
      final s = await _session();
      final r = (await s.handle('i ate mac and cheese')).toLowerCase();
      expect(r, contains('390'));
      final meal = s.store.values.firstWhere((x) => x['typeId'] == 'meal');
      expect(meal['kcal'], 390);
      expect(meal['provenance'], 'reference'); // never confused with a user-entered number
    });
    test('an article is normalized away ("a banana" -> banana)', () async {
      final s = await _session();
      expect((await s.handle('i ate a banana')).toLowerCase(), contains('105'));
    });
    test('an unknown food logs honestly — no guessed number', () async {
      final s = await _session();
      final r = (await s.handle('i ate grandmothers secret stew')).toLowerCase();
      expect(r, contains("don't have calorie data"));
      expect(s.store.values.firstWhere((x) => x['typeId'] == 'meal')['provenance'], 'user');
    });
    test('calories today sums the logged meals', () async {
      final s = await _session();
      await s.handle('i ate a banana'); // 105
      await s.handle('i ate mac and cheese'); // 390
      expect(await s.handle('how many calories today'), contains('495'));
    });
  });

  group('content search (F-12) — "find that note about…", offline via keyword', () {
    test('finds a journal entry by keyword', () async {
      final s = await _session();
      await s.handle('journal that the cabin trip to the lake was so peaceful');
      final r = await s.handle('find that note about the cabin trip');
      expect(r.toLowerCase(), contains('cabin'));
    });
    test('"search my notes for X" also works', () async {
      final s = await _session();
      await s.handle('journal that I finally fixed the leaky kitchen faucet');
      expect((await s.handle('search my notes for the faucet')).toLowerCase(), contains('faucet'));
    });
    test('a miss is honest, never a silent failure', () async {
      final s = await _session();
      await s.handle('journal that today was a good day');
      expect((await s.handle('find that note about quantum physics')).toLowerCase(), contains("couldn't find"));
    });
  });

  group('offline fact recall (F-08) — a :contact-guarded fact query', () {
    test('"what is Mia allergic to" recalls the filtered fact offline', () async {
      final s = await _session();
      await s.handle("Sarah's daughter Mia is allergic to peanuts");
      expect((await s.handle('what is Mia allergic to')).toLowerCase(), contains('peanuts'));
    });
    test('a trailing "?" does not leak into the fact filter (question phrasing works)', () async {
      final s = await _session();
      await s.handle("Sarah's daughter Mia is allergic to peanuts");
      expect((await s.handle('what is Mia allergic to?')).toLowerCase(), contains('peanuts'));
    });
    test('the :contact guard keeps world-knowledge OUT (no over-match to recall)', () async {
      final s = await _session();
      final r = (await s.handle('what is the capital of france')).toLowerCase();
      expect(r, isNot(contains("don't know anyone named the"))); // recall-fact-about did NOT fire
    });
    test('the :contact guard lets template queries win ("my" is not a contact)', () async {
      final s = await _session();
      await s.handle('start tracking my reading');
      await s.handle('i read 20 pages');
      final r = (await s.handle("what's my reading streak")).toLowerCase();
      expect(r, isNot(contains("don't know anyone"))); // reading-streak, not recall-fact-about
    });
  });

  group('template vs customization overlap (live-caught) — a unit/field prefers authoring', () {
    test('"start tracking my water intake in glasses" offers authoring, not the ml template', () async {
      final s = await _session();
      final r = (await s.handle('start tracking my water intake in glasses')).toLowerCase();
      expect(r, anyOf(contains('want me to go ahead'), contains('build you a custom')));
      expect(r, isNot(contains('ml'))); // the ml-based water template did NOT pre-empt it
    });
    test('plain "start tracking my water" still hits the free template', () async {
      final s = await _session();
      final r = (await s.handle('start tracking my water')).toLowerCase();
      expect(r, isNot(contains('want me to go ahead'))); // template, not paid authoring
    });
    test('a time qualifier "in the morning" does NOT trip the customization guard', () async {
      final s = await _session();
      final r = (await s.handle('start tracking my steps in the morning')).toLowerCase();
      expect(r, isNot(contains('want me to go ahead'))); // steps template still fires
    });
  });

  group('goal-progress (P-18 offline) — set a goal, track % via mul/div/round', () {
    test('set a goal, log runs, get progress percentage', () async {
      final s = await _session();
      expect((await s.handle('how am i doing on my goal')).toLowerCase(), contains("haven't set")); // no goal yet
      await s.handle('set a goal to run 50k');
      await s.handle('log a 3k run');
      await s.handle('log a 2k run'); // 5 of 50 km
      final r = await s.handle('how am i doing on my goal');
      expect(r, contains('10%')); // round(100 * 5/50) — proves div+mul+round in a real skill
      expect(r.toLowerCase(), contains('goal'));
    });
  });

  group('turnlog diagnostics — enough to diagnose a bad turn from the log alone', () {
    Map<String, dynamic> lastTurn(String dir) =>
        jsonDecode(File('$dir/turnlog.jsonl').readAsLinesSync().last) as Map<String, dynamic>;

    test('a MISS records diag: corpus no-match + the cloud outcome', () async {
      final dir = makeTempDataDir();
      final s = Session(dir, clock: _now, cloud: _NoKeyCloud());
      await s.init(retrieval: false);
      await s.handle('zxcvbnm qwerty nonsense that cannot match');
      final t = lastTurn(dir);
      expect(t['source'], 'clarify');
      final diag = t['diag'] as Map;
      expect(diag['corpus'], 'no-match');
      expect(diag['cloud'], contains('noKey')); // the cloud couldn't help — and WHY
    });

    test('an unattended onWrite automation fire is recorded in the turn that triggered it', () async {
      final dir = makeTempDataDir();
      Directory('$dir/automations').createSync(recursive: true);
      File('$dir/automations/enc.json').writeAsStringSync(jsonEncode({
        'automationId': 'enc',
        'targetType': 'workout',
        'condition': {'kind': 'onWrite', 'afterField': 'date'},
        'skillId': 'enc-skill',
        'description': 'encourage',
        'skill': {
          'skillId': 'enc-skill', 'inputs': [], 'reads': ['workout'], 'writes': [],
          'steps': {
            'main': [
              {'op': 'read_many', 'typeId': 'workout', 'into': 'w'},
              {'op': 'compute', 'fn': 'count', 'args': [{'var': 'w'}], 'into': 'n'},
              {'op': 'format', 'template': '{n} workouts', 'into': 'confirmationText'},
            ]
          }
        }
      }));
      final s = Session(dir, clock: _now, cloud: _NoCloud());
      await s.init(retrieval: false);
      await s.handle('log a run'); // writes a workout -> onWrite fires (read-only -> delivered)
      expect((lastTurn(dir)['automations'] as Map)['delivered'], 1);
    });
  });

  group('migrate-on-read brings old records forward (Spec 01 §7.4 / Spec 06 D12)', () {
    test('a v1 record gains a v2 type\'s new attribute (default) on open', () async {
      final dir = makeTempDataDir();
      // a custom type at schemaVersion 2 with a newly-added optional attr
      File('$dir/types/widget.json').writeAsStringSync(jsonEncode({
        'typeId': 'widget',
        'displayName': 'Widget',
        'schemaVersion': 2,
        'attributes': [
          {'name': 'name', 'valueType': 'text', 'required': true},
          {'name': 'color', 'valueType': 'text', 'required': false, 'default': 'blue'},
        ]
      }));
      // a record written under v1 (no _schemaVersion, missing `color`), in the on-disk envelope
      Directory('$dir/records').createSync(recursive: true);
      File('$dir/records/w1.json').writeAsStringSync(jsonEncode({
        'id': 'w1', 'typeId': 'widget', 'fields': {'name': 'x'}, '_meta': {'stamps': {}}
      }));

      final s = Session(dir, clock: _now, cloud: _NoCloud());
      await s.init(retrieval: false); // migrate-on-read runs here
      final rec = s.store['w1']!;
      expect(rec['name'], 'x'); // preserved
      expect(rec['color'], 'blue'); // new attr defaulted in
      expect(rec['_schemaVersion'], 2); // stamped forward

      // and it PERSISTED — a reopen sees the migrated record, no re-migration churn
      final s2 = Session(dir, clock: _now, cloud: _NoCloud());
      await s2.init(retrieval: false);
      expect(s2.store['w1']!['color'], 'blue');
      expect(s2.store['w1']!['_schemaVersion'], 2);
    });
  });

  group('schedule automations fire on open (catch-up) and persist lastFired (Spec 01 §4.4)', () {
    void seedWeekly(String dir) {
      Directory('$dir/automations').createSync(recursive: true);
      File('$dir/automations/weekly.json').writeAsStringSync(jsonEncode({
        'automationId': 'weekly-workout-summary',
        'targetType': 'workout',
        'condition': {'kind': 'schedule', 'cronExpression': '0 20 * * 0'}, // Sunday 8pm
        'skillId': 'wsum',
        'description': 'weekly workout summary',
        'skill': {
          'skillId': 'wsum', 'inputs': [], 'reads': ['workout'], 'writes': [],
          'steps': {
            'main': [
              {'op': 'read_many', 'typeId': 'workout', 'into': 'ws'},
              {'op': 'compute', 'fn': 'count', 'args': [{'var': 'ws'}], 'into': 'n'},
              {'op': 'format', 'template': 'This week: {n} workout(s) logged.', 'into': 'confirmationText'},
            ]
          }
        }
      }));
    }

    test('fires once after its cron time, then not again (lastFired persists across opens)', () async {
      final dir = makeTempDataDir();
      final devDir = Directory.systemTemp.createTempSync('plenara-dev').path;
      seedWeekly(dir);
      Session open(String clock) => Session(dir, clock: DateTime.parse(clock), cloud: _NoCloud(), deviceDir: devDir);

      final s1 = open('2026-07-11T09:00:00'); // Sat — first open baselines, no fire
      await s1.init(retrieval: false);
      expect(s1.automations.deliveries, isEmpty);

      final s2 = open('2026-07-13T09:00:00'); // Mon — Sunday 8pm passed -> fires (on-open nudge)
      await s2.init(retrieval: false);
      expect(s2.pendingNudges().any((n) => n.toLowerCase().contains('workout')), isTrue);

      final s3 = open('2026-07-13T10:00:00'); // same day — lastFired persisted -> no re-fire
      await s3.init(retrieval: false);
      expect(s3.automations.deliveries, isEmpty);
    });
  });

  group('generative routing — weekly_review / pattern_insight / draft_message', () {
    // Each routes to GenerativeService and hits its honest no-cloud degrade path (thin data /
    // unknown contact) — so _NoCloud (which throws on generate) proves the route without a cloud call.
    test('"how was my week" -> weekly_review (empty week degrades locally)', () async {
      final s = await _session();
      expect((await s.handle('how was my week')).toLowerCase(), contains('nothing logged this past week'));
    });
    test('"any patterns" -> pattern_insight (thin data degrades locally)', () async {
      final s = await _session();
      expect((await s.handle('any patterns')).toLowerCase(), contains("don't have enough logged data"));
    });
    test('"draft a message to Sam" -> draft_message (unknown contact asks honestly)', () async {
      final s = await _session();
      expect(await s.handle('draft a message to Sam'), contains("don't have Sam as a contact"));
    });
  });

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

    test('a template query skill sums today: water logged today', () async {
      final s = await _session();
      await s.handle('start tracking my water');
      await s.handle('log 500ml of water');
      await s.handle('i drank 300ml of water');
      expect(await s.handle('how much water today'), contains('800'));
    });

    test('a template query answers adherence: meds today (F-16)', () async {
      final s = await _session();
      await s.handle('start tracking my meds');
      expect((await s.handle('did i take my meds today')).toLowerCase(), contains('not yet'));
      await s.handle('took my morning meds');
      expect((await s.handle('did i take my meds today')).toLowerCase(), contains('yes'));
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
    test('"how is Marco doing" routes to last-interaction (dogfood coverage)', () async {
      final s = await _session();
      await s.handle('i talked to Marco about the trip');
      expect(await s.handle('how is Marco doing'), contains('Marco'));
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
    test('F-15: "actually that was 6k" / "that was 30 minutes" (natural correction, live-caught)', () async {
      final s = await _session();
      await s.handle('log a 5k run');
      await s.handle('actually that was 6k');
      await s.handle('that was 30 minutes');
      final w = s.store.values.where((x) => x['typeId'] == 'workout').single;
      expect(w['distance'], 6);
      expect(w['duration'], 30);
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
