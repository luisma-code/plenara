/// AutomationRunner + Review Feed (Spec 04 §3.9/§4.8, Spec 01 §4.4, Spec 02 §7.5).
/// Hermetic and deterministic: the onWrite path needs no timers and no OS, so the
/// whole product behaviour — registration/validation, firing, the §7.5 gating
/// (read-only delivers / writes are held / destructive is refused), review
/// approve/decline with the stale-plan re-verify, the cascade bound, and the
/// worked example (`data/automations/workout-encouragement.json`) end-to-end
/// through Session — runs against in-memory maps and a fixed clock.
import 'dart:convert';
import 'dart:io';

import 'package:plenara/automations.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00'); // a Monday, 09:00

/// Cloud that must never be hit (all flows here are corpus/offline).
class _NoCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s, {Set<String> knownContacts = const {}}) async =>
      throw StateError('cloud hit for "$u" — automation flows must be pure corpus');
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      throw StateError('cloud authoring hit — unexpected');
  @override
  Future<CloudResult<String>> generate(String kind, String context) async =>
      throw StateError('cloud generate hit — unexpected');
}

// ---- pure-runner fixtures ---------------------------------------------------

final Map<String, Map<String, dynamic>> _types = {
  'workout': {
    'typeId': 'workout',
    'attributes': [
      {'name': 'activity', 'valueType': 'text', 'required': true},
      {'name': 'distance', 'valueType': 'decimal', 'required': false},
      {'name': 'date', 'valueType': 'date', 'required': true},
    ],
  },
  'task': {
    'typeId': 'task',
    'attributes': [
      {'name': 'description', 'valueType': 'text', 'required': true},
      {'name': 'completed', 'valueType': 'boolean', 'required': false, 'default': false},
      {'name': 'createdAt', 'valueType': 'date', 'required': true},
    ],
  },
};

Map<String, dynamic> _workout(String id, String date) =>
    {'id': id, 'typeId': 'workout', 'activity': 'run', 'date': date};

/// Read-only: counts workouts. An empty action plan → deliver (Spec 02 §7.5).
Map<String, dynamic> _summarySkill() => {
      'skillId': 'workout-summary',
      'inputs': <dynamic>[],
      'reads': ['workout'],
      'writes': <dynamic>[],
      'steps': {
        'main': [
          {'op': 'read_many', 'typeId': 'workout', 'into': 'ws'},
          {'op': 'compute', 'fn': 'count', 'args': [{'var': 'ws'}], 'into': 'n'},
          {'op': 'format', 'template': 'You have {n} workout(s) logged.', 'into': 'confirmationText'},
        ]
      },
    };

/// Writes a task whose description depends on the store (so a store change
/// between hold and approve produces a genuinely different plan).
Map<String, dynamic> _followupSkill() => {
      'skillId': 'workout-followup',
      'inputs': <dynamic>[],
      'reads': ['workout'],
      'writes': ['task'],
      'steps': {
        'main': [
          {'op': 'read_many', 'typeId': 'workout', 'into': 'ws'},
          {'op': 'compute', 'fn': 'count', 'args': [{'var': 'ws'}], 'into': 'n'},
          {'op': 'compute', 'fn': 'concat', 'args': ['Stretch — workout #', {'var': 'n'}], 'into': 'desc'},
          {'op': 'compute', 'fn': 'today', 'into': 'td'},
          {
            'op': 'write_record',
            'typeId': 'task',
            'fields': {'description': {'var': 'desc'}, 'createdAt': {'var': 'td'}},
            'into': 't'
          },
          {'op': 'format', 'template': '{desc} added to your tasks.', 'into': 'confirmationText'},
        ]
      },
    };

/// Read-only over tasks — the second hop of the cascade test.
Map<String, dynamic> _taskCountSkill() => {
      'skillId': 'task-count',
      'inputs': <dynamic>[],
      'reads': ['task'],
      'writes': <dynamic>[],
      'steps': {
        'main': [
          {'op': 'read_many', 'typeId': 'task', 'into': 'ts'},
          {'op': 'compute', 'fn': 'count', 'args': [{'var': 'ts'}], 'into': 'n'},
          {'op': 'format', 'template': 'You now have {n} task(s).', 'into': 'confirmationText'},
        ]
      },
    };

/// Destructive in effect (delete_record) — must never run unattended.
Map<String, dynamic> _purgeSkill() => {
      'skillId': 'purge-workouts',
      'inputs': [
        {'name': 'recordId', 'required': false}
      ],
      'steps': {
        'main': [
          {'op': 'delete_record', 'id': {'var': 'recordId'}},
          {'op': 'format', 'template': 'Purged.', 'into': 'confirmationText'},
        ]
      },
    };

Map<String, dynamic> _auto(String id,
        {String target = 'workout',
        String after = 'date',
        String? skillId,
        Map<String, dynamic>? inline,
        bool pending = false,
        Map<String, dynamic>? condition,
        String? description}) =>
    {
      'automationId': id,
      'targetType': target,
      'condition': condition ?? {'kind': 'onWrite', 'afterField': after},
      'skillId': skillId ?? inline?['skillId'],
      if (pending) 'pendingSkill': true,
      if (inline != null) 'skill': inline,
      'description': description ?? 'test automation $id',
    };

AutomationRunner _runner(List<Map<String, dynamic>> autos,
    {Map<String, Map<String, dynamic>>? skills,
    Map<String, Map<String, dynamic>>? store,
    List<Map<String, dynamic>>? persisted}) {
  final r = AutomationRunner(
      types: _types,
      skills: skills ?? {},
      store: store ?? {},
      clock: () => _now,
      persist: persisted?.add);
  r.register({for (final a in autos) a['automationId'] as String: a});
  return r;
}

AutomationStatus _st(AutomationRunner r, String id) =>
    r.statuses.firstWhere((s) => s.automationId == id);

// ---- Session fixtures --------------------------------------------------------

/// Temp data dir INCLUDING data/automations (makeTempDataDir deliberately omits
/// it so the pre-automation suites are byte-for-byte unaffected).
String _dirWithAutomations() {
  final dir = makeTempDataDir();
  final src = Directory('data/automations');
  final dst = Directory('$dir/automations')..createSync(recursive: true);
  for (final f in src.listSync().whereType<File>()) {
    f.copySync('${dst.path}/${basename(f.path)}');
  }
  return dir;
}

Future<Session> _open(String dir) async {
  final s = Session(dir, clock: _now, cloud: _NoCloud());
  await s.init(retrieval: false);
  return s;
}

void main() {
  group('registration & validation (Spec 01 §4.4 / §5.2 step 7)', () {
    test('a valid onWrite automation with an inline skill registers active', () {
      final r = _runner([_auto('a1', inline: _summarySkill())]);
      expect(_st(r, 'a1').state, 'active');
      expect(_st(r, 'a1').reason, isNull);
    });

    test('a valid onWrite automation with a shared-registry skill registers active and fires', () {
      final store = {'workout-1': _workout('workout-1', '2026-07-06')};
      final r = _runner([_auto('a1', skillId: 'workout-summary')],
          skills: {'workout-summary': _summarySkill()}, store: store);
      expect(_st(r, 'a1').state, 'active');
      r.notifyWrites([store['workout-1']!]);
      expect(r.deliveries.single.text, 'You have 1 workout(s) logged.');
    });

    test('pendingSkill registers as pending and stays inert (no fire, no refusal)', () {
      final store = {'workout-1': _workout('workout-1', '2026-07-06')};
      final r = _runner([_auto('a1', skillId: 'not-yet-authored', pending: true)], store: store);
      expect(_st(r, 'a1').state, 'pending');
      r.notifyWrites([store['workout-1']!]);
      expect(r.deliveries, isEmpty);
      expect(r.pendingReview, isEmpty);
      expect(r.refusals, isEmpty);
    });

    test('a pendingSkill automation goes live the moment its skill is authored', () {
      final store = {'workout-1': _workout('workout-1', '2026-07-06')};
      final skills = <String, Map<String, dynamic>>{};
      final r = _runner([_auto('a1', skillId: 'workout-summary', pending: true)],
          skills: skills, store: store);
      r.notifyWrites([store['workout-1']!]);
      expect(r.deliveries, isEmpty); // not authored yet
      skills['workout-summary'] = _summarySkill(); // authoring lands the skill
      r.notifyWrites([store['workout-1']!]);
      expect(r.deliveries.single.text, contains('1 workout(s)'));
    });

    test('a missing skill without pendingSkill is inert and surfaced', () {
      final r = _runner([_auto('a1', skillId: 'nope')]);
      expect(_st(r, 'a1').state, 'inert');
      expect(_st(r, 'a1').reason, contains('not found'));
    });

    test('an unresolved targetType is inert and surfaced', () {
      final r = _runner([_auto('a1', target: 'no_such_type', inline: _summarySkill())]);
      expect(_st(r, 'a1').state, 'inert');
      expect(_st(r, 'a1').reason, contains('unresolved targetType'));
    });

    test('an afterField that is not an attribute of the target type is inert', () {
      final r = _runner([_auto('a1', after: 'heartRate', inline: _summarySkill())]);
      expect(_st(r, 'a1').state, 'inert');
      expect(_st(r, 'a1').reason, contains('not an attribute'));
    });

    test('a schedule automation registers ARMED and fires on a due tick (catch-up on open)', () {
      final store = {'workout-1': _workout('workout-1', '2026-07-06')};
      final r = _runner([
        _auto('a1',
            inline: _summarySkill(),
            condition: {'kind': 'schedule', 'cronExpression': '0 20 * * 0'}) // Sunday 8pm
      ], store: store);
      expect(_st(r, 'a1').state, 'active');
      r.notifyWrites([store['workout-1']!]); // a schedule never fires onWrite
      expect(r.deliveries, isEmpty);
      r.tick(DateTime.parse('2026-07-11T09:00:00')); // Sat: first sight -> baseline, no back-fill
      expect(r.deliveries, isEmpty);
      r.tick(DateTime.parse('2026-07-13T09:00:00')); // Mon: Sunday 8pm passed -> read-only delivery
      expect(r.deliveries, isNotEmpty);
      r.takeDeliveries();
      r.tick(DateTime.parse('2026-07-13T10:00:00')); // same window, no new cron time -> no re-fire
      expect(r.deliveries, isEmpty);
    });

    test('a schedule automation without a cronExpression is inert', () {
      final r = _runner([
        _auto('a1', inline: _summarySkill(), condition: {'kind': 'schedule'})
      ]);
      expect(_st(r, 'a1').state, 'inert');
      expect(_st(r, 'a1').reason, contains('cronExpression'));
    });

    test('an unknown condition kind is inert', () {
      final r = _runner([
        _auto('a1', inline: _summarySkill(), condition: {'kind': 'onQuery'})
      ]);
      expect(_st(r, 'a1').state, 'inert');
      expect(_st(r, 'a1').reason, contains('unknown condition kind'));
    });

    test('a destructive skill is rejected at registration (Spec 01 §5.3 / Spec 02 §7.5)', () {
      final r = _runner([_auto('a1', skillId: 'purge-workouts')],
          skills: {'purge-workouts': _purgeSkill()});
      expect(_st(r, 'a1').state, 'inert');
      expect(_st(r, 'a1').reason, contains('destructive'));
    });

    test('a dangerLevel:destructive skill is rejected even without a delete op', () {
      final skill = _summarySkill()..['dangerLevel'] = 'destructive';
      final r = _runner([_auto('a1', skillId: 'workout-summary')],
          skills: {'workout-summary': skill});
      expect(_st(r, 'a1').state, 'inert');
      expect(_st(r, 'a1').reason, contains('destructive'));
    });

    test('an invalid inline skill (no confirmation) is inert with the validation reason', () {
      final bad = {
        'skillId': 'bad-skill',
        'inputs': <dynamic>[],
        'steps': {
          'main': [
            {'op': 'read_many', 'typeId': 'workout', 'into': 'ws'},
          ]
        },
      };
      final r = _runner([_auto('a1', inline: bad)]);
      expect(_st(r, 'a1').state, 'inert');
      expect(_st(r, 'a1').reason, contains('failed validation'));
    });

    test("an inline skill whose skillId doesn't match the automation's is inert", () {
      final r = _runner([_auto('a1', skillId: 'other-id', inline: _summarySkill())]);
      expect(_st(r, 'a1').state, 'inert');
      expect(_st(r, 'a1').reason, contains('must match'));
    });

    test('a def missing its description is inert (the automation UI needs the why)', () {
      final def = _auto('a1', inline: _summarySkill())..remove('description');
      final r = _runner([def]);
      expect(_st(r, 'a1').state, 'inert');
      expect(_st(r, 'a1').reason, contains('description'));
    });
  });

  group('onWrite firing & the §7.5 gate', () {
    test('a matching write fires a read-only skill and DELIVERS (no approval)', () {
      final store = {'workout-1': _workout('workout-1', '2026-07-06')};
      final persisted = <Map<String, dynamic>>[];
      final r = _runner([_auto('a1', inline: _summarySkill())], store: store, persisted: persisted);
      r.notifyWrites([store['workout-1']!]);
      final d = r.deliveries.single;
      expect(d.automationId, 'a1');
      expect(d.text, 'You have 1 workout(s) logged.');
      expect(r.pendingReview, isEmpty);
      expect(persisted, isEmpty); // read-only: nothing written, nothing persisted
      expect(r.refusals, isEmpty);
    });

    test('a write of a non-matching type does not fire', () {
      final r = _runner([_auto('a1', inline: _summarySkill())]);
      r.notifyWrites([
        {'id': 'task-1', 'typeId': 'task', 'description': 'x', 'createdAt': '2026-07-06'}
      ]);
      expect(r.deliveries, isEmpty);
      expect(r.pendingReview, isEmpty);
    });

    test('a write without the afterField does not fire (afterField respected)', () {
      final r = _runner([_auto('a1', inline: _summarySkill())]);
      r.notifyWrites([
        {'id': 'workout-1', 'typeId': 'workout', 'activity': 'run'} // no date
      ]);
      expect(r.deliveries, isEmpty);
      expect(r.pendingReview, isEmpty);
    });

    test('a writing skill is HELD for review — never applied unattended', () {
      final store = {'workout-1': _workout('workout-1', '2026-07-06')};
      final persisted = <Map<String, dynamic>>[];
      final r = _runner([_auto('a1', inline: _followupSkill())], store: store, persisted: persisted);
      r.notifyWrites([store['workout-1']!]);
      expect(r.deliveries, isEmpty);
      final item = r.pendingReview.single;
      expect(item.automationId, 'a1');
      expect(item.pendingWrites.single['typeId'], 'task');
      expect(item.pendingWrites.single['description'], 'Stretch — workout #1');
      expect(item.preview, 'Stretch — workout #1 added to your tasks.');
      // the store and disk are untouched until the user approves
      expect(store.values.where((x) => x['typeId'] == 'task'), isEmpty);
      expect(persisted, isEmpty);
    });

    test('a skill that turned destructive after registration is refused at fire time', () {
      final store = {'workout-1': _workout('workout-1', '2026-07-06')};
      final skills = <String, Map<String, dynamic>>{};
      final r = _runner([_auto('a1', skillId: 'purge-workouts', pending: true)],
          skills: skills, store: store);
      skills['purge-workouts'] = _purgeSkill(); // authored later — and destructive
      r.notifyWrites([store['workout-1']!]);
      expect(r.refusals.single, contains('destructive'));
      expect(r.deliveries, isEmpty);
      expect(r.pendingReview, isEmpty);
      expect(store.length, 1); // nothing deleted
    });

    test('a skill that fails to resolve is a surfaced refusal, not a crash', () {
      // read_one with an unresolvable ambiguity is hard to fake here; simplest
      // resolve failure: a shared skill with an unknown compute fn.
      final store = {'workout-1': _workout('workout-1', '2026-07-06')};
      final broken = {
        'skillId': 'broken',
        'inputs': <dynamic>[],
        'steps': {
          'main': [
            {'op': 'compute', 'fn': 'no_such_fn', 'into': 'x'},
            {'op': 'format', 'template': 'x', 'into': 'confirmationText'},
          ]
        },
      };
      final r = _runner([_auto('a1', skillId: 'broken')], skills: {'broken': broken}, store: store);
      r.notifyWrites([store['workout-1']!]);
      expect(r.refusals.single, contains('failed to resolve'));
      expect(r.deliveries, isEmpty);
      expect(r.pendingReview, isEmpty);
    });

    test('takeDeliveries drains the outbox', () {
      final store = {'workout-1': _workout('workout-1', '2026-07-06')};
      final r = _runner([_auto('a1', inline: _summarySkill())], store: store);
      r.notifyWrites([store['workout-1']!]);
      expect(r.takeDeliveries().length, 1);
      expect(r.deliveries, isEmpty);
    });
  });

  group('the review feed (Spec 04 §3.9)', () {
    test('approve re-verifies, executes, persists, and reaps the item', () {
      final store = {'workout-1': _workout('workout-1', '2026-07-06')};
      final persisted = <Map<String, dynamic>>[];
      final r = _runner([_auto('a1', inline: _followupSkill())], store: store, persisted: persisted);
      r.notifyWrites([store['workout-1']!]);
      final res = r.approve(r.pendingReview.single.id);
      expect(res.kind, 'applied');
      expect(res.message, 'Stretch — workout #1 added to your tasks.');
      final task = store.values.singleWhere((x) => x['typeId'] == 'task');
      expect(task['description'], 'Stretch — workout #1');
      expect(task['completed'], false); // schema default applied
      expect(persisted.single['id'], task['id']); // write-through persisted
      expect(r.pendingReview, isEmpty);
    });

    test('decline reaps the item and writes nothing', () {
      final store = {'workout-1': _workout('workout-1', '2026-07-06')};
      final persisted = <Map<String, dynamic>>[];
      final r = _runner([_auto('a1', inline: _followupSkill())], store: store, persisted: persisted);
      r.notifyWrites([store['workout-1']!]);
      final id = r.pendingReview.single.id;
      expect(r.decline(id), isTrue);
      expect(r.pendingReview, isEmpty);
      expect(store.values.where((x) => x['typeId'] == 'task'), isEmpty);
      expect(persisted, isEmpty);
      expect(r.decline(id), isFalse); // already reaped
    });

    test('a stale approval never executes: data moved → planChanged → re-approve applies the NEW plan',
        () {
      final store = {'workout-1': _workout('workout-1', '2026-07-06')};
      final r = _runner([_auto('a1', inline: _followupSkill())], store: store);
      r.notifyWrites([store['workout-1']!]);
      final item = r.pendingReview.single;
      expect(item.pendingWrites.single['description'], 'Stretch — workout #1');
      // hours pass; another workout lands before the user reviews
      store['workout-2'] = _workout('workout-2', '2026-07-06');
      final res = r.approve(item.id);
      expect(res.kind, 'planChanged'); // the held (stale) plan did NOT execute
      expect(store.values.where((x) => x['typeId'] == 'task'), isEmpty);
      expect(r.pendingReview.single.pendingWrites.single['description'],
          'Stretch — workout #2'); // the item now carries the fresh plan
      final res2 = r.approve(item.id);
      expect(res2.kind, 'applied');
      expect(store.values.singleWhere((x) => x['typeId'] == 'task')['description'],
          'Stretch — workout #2');
    });

    test('approving an unknown review id is notFound', () {
      final r = _runner([]);
      expect(r.approve('review-999').kind, 'notFound');
    });

    test('an approved write cascades onWrite at depth+1 (and stays bounded)', () {
      final store = {'workout-1': _workout('workout-1', '2026-07-06')};
      final r = _runner([
        _auto('a-write', inline: _followupSkill()), // workout → writes a task (held)
        _auto('b-read', target: 'task', after: 'description', inline: _taskCountSkill()),
      ], store: store);
      r.notifyWrites([store['workout-1']!]);
      expect(r.deliveries, isEmpty); // b has not fired: the task is only HELD
      final res = r.approve(r.pendingReview.single.id);
      expect(res.kind, 'applied');
      // the approved task write fired b-read at depth 1 → a delivery
      expect(r.deliveries.single.text, 'You now have 1 task(s).');
      expect(r.pendingReview, isEmpty);
    });

    test('the cascade bound suppresses (and surfaces) hooks at maxCascadeDepth', () {
      final store = {'workout-1': _workout('workout-1', '2026-07-06')};
      final r = _runner([_auto('a1', inline: _summarySkill())], store: store);
      r.notifyWrites([store['workout-1']!], depth: AutomationRunner.maxCascadeDepth);
      expect(r.deliveries, isEmpty);
      expect(r.refusals.single, contains('suppressed at cascade depth'));
    });
  });

  group('Session end-to-end — the worked example (data/automations/)', () {
    test('logging a run delivers the encouragement out-of-band; the turn response is unchanged',
        () async {
      final s = await _open(_dirWithAutomations());
      expect(_stOf(s, 'workout-encouragement').state, 'active');
      final r = await s.handle('log a 3k run');
      expect(r, contains('Logged a 3 km run')); // the normal act-then-describe line
      expect(r, isNot(contains('Nice work'))); // the automation never edits the response
      final d = s.automations.deliveries.single;
      expect(d.automationId, 'workout-encouragement');
      expect(d.text, contains("1 workout(s) this week"));
      expect(d.text, contains('1-day streak'));
      expect(s.automations.pendingReview, isEmpty); // read-only → nothing held
      expect(s.store.length, 1); // exactly the workout — no extra records
    });

    test('a second run the same day updates the derived numbers', () async {
      final s = await _open(_dirWithAutomations());
      await s.handle('log a 3k run');
      await s.handle('i ran 4k');
      expect(s.automations.deliveries.length, 2);
      expect(s.automations.deliveries.last.text, contains('2 workout(s) this week'));
    });

    test('deliveries surface in pendingNudges until drained', () async {
      final s = await _open(_dirWithAutomations());
      await s.handle('log a 3k run');
      expect(s.pendingNudges().where((n) => n.startsWith('✨')).length, 1);
      s.automations.takeDeliveries(); // the UI showed them
      expect(s.pendingNudges().where((n) => n.startsWith('✨')), isEmpty);
    });

    test('undo of the triggering write still works exactly as before', () async {
      final s = await _open(_dirWithAutomations());
      await s.handle('log a 3k run');
      final r = await s.handle('undo that');
      expect(r.toLowerCase(), contains('undone'));
      expect(s.store.values.where((x) => x['typeId'] == 'workout'), isEmpty);
    });

    test('no automations folder → empty registry → zero behavior change', () async {
      final s = await _open(makeTempDataDir()); // the standard dir has no automations/
      await s.handle('log a 3k run');
      expect(s.automations.statuses, isEmpty);
      expect(s.automations.deliveries, isEmpty);
      expect(s.automations.pendingReview, isEmpty);
      expect(s.pendingNudges().where((n) => n.startsWith('✨')), isEmpty);
    });

    test('a WRITING automation through a real turn is held, then approve applies + persists',
        () async {
      final dir = makeTempDataDir();
      Directory('$dir/automations').createSync(recursive: true);
      File('$dir/automations/workout-followup.json').writeAsStringSync(jsonEncode(
          _auto('workout-followup', inline: _followupSkill(), description: 'adds a stretch task')));
      final s = await _open(dir);
      await s.handle('log a 3k run');
      // held, not applied: no task exists, and the pending item is surfaced
      expect(s.store.values.where((x) => x['typeId'] == 'task'), isEmpty);
      final item = s.automations.pendingReview.single;
      expect(s.pendingNudges().any((n) => n.startsWith('📋')), isTrue);
      // approve → executed and persisted through the repository
      expect(s.automations.approve(item.id).kind, 'applied');
      expect(s.store.values.singleWhere((x) => x['typeId'] == 'task')['description'],
          contains('Stretch'));
      final s2 = await _open(dir); // fresh process over the same folder
      expect(s2.store.values.where((x) => x['typeId'] == 'task').length, 1,
          reason: 'the approved write was persisted, not memory-only');
    });

    test('declining a held automation write leaves no trace', () async {
      final dir = makeTempDataDir();
      Directory('$dir/automations').createSync(recursive: true);
      File('$dir/automations/workout-followup.json').writeAsStringSync(jsonEncode(
          _auto('workout-followup', inline: _followupSkill(), description: 'adds a stretch task')));
      final s = await _open(dir);
      await s.handle('log a 3k run');
      expect(s.automations.decline(s.automations.pendingReview.single.id), isTrue);
      expect(s.automations.pendingReview, isEmpty);
      expect(s.store.values.where((x) => x['typeId'] == 'task'), isEmpty);
      final s2 = await _open(dir);
      expect(s2.store.values.where((x) => x['typeId'] == 'task'), isEmpty);
    });

    test('a pendingSkill automation in the folder registers pending and never fires', () async {
      final dir = makeTempDataDir();
      Directory('$dir/automations').createSync(recursive: true);
      File('$dir/automations/future.json').writeAsStringSync(jsonEncode(
          _auto('future', skillId: 'not-yet-authored', pending: true)));
      final s = await _open(dir);
      expect(_stOf(s, 'future').state, 'pending');
      await s.handle('log a 3k run');
      expect(s.automations.deliveries, isEmpty);
      expect(s.automations.pendingReview, isEmpty);
      expect(s.automations.refusals, isEmpty);
    });
  });
}

AutomationStatus _stOf(Session s, String id) =>
    s.automations.statuses.firstWhere((a) => a.automationId == id);
