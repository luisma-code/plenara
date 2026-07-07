/// People loop (Fable #3): log-interaction + last-interaction. Offline/corpus,
/// hermetic. Proves the contact-reuse, note capture, and — since the DSL has no
/// sort — that "when did I last talk to X" finds the MAX interaction date via the
/// foreach/branch reduction, independent of insertion order.
import 'package:plenara/claude.dart';
import 'package:plenara/people.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

class _NoCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s) async =>
      throw StateError('cloud hit for "$u" — people flows must be pure corpus');
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      throw StateError('unexpected authoring');
}

Future<Session> _session(String dir, {required DateTime clock}) async {
  final s = Session(dir, clock: clock, cloud: _NoCloud());
  await s.init(retrieval: false);
  return s;
}

DateTime _d(String iso) => DateTime.parse('${iso}T09:00:00');

void main() {
  group('log-interaction', () {
    test('creates the contact if absent and logs an interaction dated today', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      final r = await s.handle('talked to Sarah');
      expect(r, contains('Sarah'));
      final contacts = s.store.values.where((x) => x['typeId'] == 'contact').toList();
      expect(contacts.length, 1);
      expect(contacts.single['displayName'], 'Sarah');
      final ints = s.store.values.where((x) => x['typeId'] == 'interaction').toList();
      expect(ints.length, 1);
      expect(ints.single['at'], '2026-07-06');
      expect(ints.single['subject'], contacts.single['id']); // entity ref wired
    });

    test('captures a note and reuses an existing contact (no duplicate)', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle('talked to Sarah');
      await s.handle('spoke to Sarah about the school trip');
      expect(s.store.values.where((x) => x['typeId'] == 'contact').length, 1); // reused
      final ints = s.store.values.where((x) => x['typeId'] == 'interaction').toList();
      expect(ints.length, 2);
      expect(ints.any((i) => i['note'] == 'the school trip'), isTrue);
    });
  });

  group('last-interaction (max date via reduction, not insertion order)', () {
    test('reports the most recent date even when logged out of order', () async {
      final dir = makeTempDataDir();
      // log the LATER interaction first, then an earlier one, over the same folder
      await (await _session(dir, clock: _d('2026-07-08'))).handle('talked to Sarah about the trip');
      await (await _session(dir, clock: _d('2026-07-06'))).handle('talked to Sarah');

      final ask = await _session(dir, clock: _d('2026-07-10'));
      final r = await ask.handle('when did i last talk to Sarah');
      expect(r, contains('2026-07-08')); // the max, not the last inserted (07-06)
      expect(r, contains('Wednesday')); // 2026-07-08 weekday
    });

    test('unknown contact -> says so; known contact with no interactions -> says so', () async {
      final dir = makeTempDataDir();
      final s = await _session(dir, clock: _d('2026-07-06'));
      expect(await s.handle('when did i last talk to Nobody'), contains("don't have"));

      // create a contact via a fact, but never log an interaction
      await s.handle('note that Amir plays the cello');
      final r = await s.handle('when did i last speak to Amir');
      expect(r.toLowerCase(), contains("haven't logged"));
    });
  });

  group('birthdays', () {
    test('set-birthday creates a contact with the birthday (month-name date)', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      final r = await s.handle("Sarah's birthday is july 16");
      expect(r, contains('Sarah'));
      final c = s.store.values.where((x) => x['typeId'] == 'contact').toList();
      expect(c.length, 1);
      expect(c.single['birthday'], '2026-07-16');
    });

    test('set-birthday updates an existing contact without duplicating', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle('talked to Sarah'); // creates the contact
      await s.handle("set Sarah's birthday to march 3");
      final c = s.store.values.where((x) => x['typeId'] == 'contact').toList();
      expect(c.length, 1); // no duplicate
      expect(c.single['birthday'], '2026-03-03');
    });

    test('when-birthday reports the next occurrence + days away', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle("Sarah's birthday is july 16");
      final r = await s.handle("when is Sarah's birthday");
      expect(r, contains('2026-07-16'));
      expect(r, contains('Thursday'));
      expect(r, contains('in 10 days'));
    });

    test('when-birthday: unknown contact / no birthday set', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      expect(await s.handle("when is Nobody's birthday"), contains("don't have"));
      await s.handle('talked to Amir');
      expect(await s.handle("when is Amir's birthday"), contains("don't know"));
    });

    test('upcoming-birthdays lists within 30 days and excludes far-off ones', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle("Sarah's birthday is july 16"); // in 10 days
      await s.handle("Mia's birthday is december 25"); // far off
      final r = await s.handle('whose birthday is coming up');
      expect(r, contains('Sarah'));
      expect(r, contains('in 10 days'));
      expect(r.contains('Mia'), isFalse);
    });

    test('upcoming-birthdays: none coming up', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle("Mia's birthday is december 25");
      expect(await s.handle('any birthdays coming up'), contains('No birthdays'));
    });
  });

  group('list-interactions', () {
    test('lists logged interactions with dates + notes, newest data intact', () async {
      final dir = makeTempDataDir();
      await (await _session(dir, clock: _d('2026-07-06'))).handle('talked to Sarah about the school trip');
      await (await _session(dir, clock: _d('2026-07-08'))).handle('called Sarah');

      final s = await _session(dir, clock: _d('2026-07-10'));
      final r = await s.handle('what have i logged with Sarah');
      expect(r, contains('2 interaction'));
      expect(r, contains('2026-07-06'));
      expect(r, contains('the school trip')); // the note
      expect(r, contains('2026-07-08'));
    });

    test('unknown contact / a contact with no interactions', () async {
      final dir = makeTempDataDir();
      final s = await _session(dir, clock: _d('2026-07-06'));
      expect(await s.handle('my history with Nobody'), contains("don't have"));
      await s.handle('note that Priya loves climbing'); // contact, no interaction
      expect(await s.handle('our history with Priya'), contains("haven't logged any"));
    });
  });

  group('on-open birthday nudges (derived, no new skill)', () {
    test('a birthday within a week nudges on open; a far-off one does not', () async {
      final dir = makeTempDataDir();
      final s = await _session(dir, clock: _d('2026-07-06'));
      await s.handle("Sarah's birthday is july 10"); // in 4 days
      await s.handle("Mia's birthday is december 25"); // far off

      final reopened = await _session(dir, clock: _d('2026-07-06')); // fresh open re-derives
      final nudges = reopened.pendingNudges();
      expect(nudges.any((n) => n.contains('Sarah') && n.contains('in 4 days')), isTrue);
      expect(nudges.any((n) => n.contains('Mia')), isFalse);
      expect(nudges.every((n) => n.startsWith('🎂') || n.startsWith('⏰')), isTrue);
    });

    test('pure helper: today/tomorrow phrasing, skips missing birthdays, sorted soonest-first', () {
      final now = _d('2026-07-06');
      final store = {
        'contact-1': {'id': 'contact-1', 'typeId': 'contact', 'displayName': 'B', 'birthday': '2000-07-07'},
        'contact-2': {'id': 'contact-2', 'typeId': 'contact', 'displayName': 'A', 'birthday': '2000-07-06'},
        'contact-3': {'id': 'contact-3', 'typeId': 'contact', 'displayName': 'C'}, // no birthday
      };
      final n = upcomingBirthdayNudges(store, now);
      expect(n.length, 2);
      expect(n[0], contains('today')); // A, sorted ahead of B
      expect(n[0], contains('A'));
      expect(n[1], contains('tomorrow'));
    });
  });

  group('forget-fact (correcting memories)', () {
    test('forgets a matching fact by substring, leaves the others', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle('note that Mia likes chess');
      await s.handle('note that Mia plays piano');
      final r = await s.handle('forget that Mia likes chess');
      expect(r.toLowerCase(), contains('forgot'));
      final recall = await s.handle('what do i know about Mia');
      expect(recall.contains('chess'), isFalse);
      expect(recall, contains('piano')); // unrelated fact untouched
    });

    test('no matching note -> a clear no-op, nothing removed', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle('note that Mia likes chess');
      final r = await s.handle('forget that Mia likes golf');
      expect(r, contains("don't have a note like"));
      expect(await s.handle('what do i know about Mia'), contains('chess')); // untouched
    });

    test('undo restores a forgotten fact', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle('note that Mia likes chess');
      await s.handle('forget that Mia likes chess');
      await s.handle('undo');
      expect(await s.handle('what do i know about Mia'), contains('chess'));
    });
  });

  group('list-relations', () {
    test('shows a person\'s relationships with the linked contact name resolved', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle("remember that Mia loves art and she is Sarah's daughter");
      final r = await s.handle("who are Sarah's relatives");
      expect(r, contains('daughter: Mia')); // forward: Sarah's daughter is Mia
    });

    test('resolves the reverse direction too ("who is Mia related to")', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle("remember that Mia loves art and she is Sarah's daughter");
      final r = await s.handle('who is Mia related to');
      expect(r, contains('daughter of Sarah')); // reverse: Mia is Sarah's daughter
    });

    test('unknown contact / a contact with no relationships', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      expect(await s.handle('who is Nobody related to'), contains("don't have"));
      await s.handle('talked to Alex'); // a contact, but no relationships noted
      expect(await s.handle("who are Alex's relatives"), contains('any relationships'));
    });
  });

  group('partial name matching + disambiguation (people reads)', () {
    test('a first name resolves to the full-name contact', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle('talked to Sam Rivera about chess');
      final r = await s.handle('when did i last talk to Sam'); // "Sam" -> "Sam Rivera"
      expect(r, contains('2026-07-06'));
      expect(r.contains("don't have"), isFalse);
    });

    test('an ambiguous first name asks which one — candidates listed, no raw error', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle('talked to Sam Rivera');
      await s.handle('talked to Sam Chen');
      final r = await s.handle('when did i last talk to Sam');
      expect(r, contains('more than one'));
      expect(r, contains('Sam Rivera'));
      expect(r, contains('Sam Chen'));
      expect(r.contains('ResolveError'), isFalse); // no internals leak
      expect(r.contains('G-12'), isFalse);
    });

    test('an exact name still wins over a partial one (no false ambiguity)', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle('talked to Sam'); // contact "Sam"
      await s.handle('talked to Sam Rivera'); // contact "Sam Rivera"
      final r = await s.handle('when did i last talk to Sam');
      expect(r.contains('more than one'), isFalse); // exact "Sam" resolves cleanly
    });

    test('write/find-or-create stays EXACT — a partial name makes a new contact, never merges', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle('talked to Sam Rivera');
      await s.handle('talked to Sam'); // exact read_one -> no "Sam" -> creates it
      final names = s.store.values.where((x) => x['typeId'] == 'contact').map((c) => c['displayName']).toList();
      expect(names, containsAll(<String>['Sam Rivera', 'Sam']));
      expect(names.length, 2); // NOT merged into Sam Rivera
    });
  });

  group('people-loop routing', () {
    test('"talked to X about Y" -> log-interaction with a note', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle('talked to Dad about the car');
      final ints = s.store.values.where((x) => x['typeId'] == 'interaction').toList();
      expect(ints.single['note'], 'the car');
    });
    test('"caught up with X" and "called X" both log an interaction', () async {
      final s = await _session(makeTempDataDir(), clock: _d('2026-07-06'));
      await s.handle('caught up with Mia');
      await s.handle('called Grandma');
      expect(s.store.values.where((x) => x['typeId'] == 'interaction').length, 2);
      expect(s.store.values.where((x) => x['typeId'] == 'contact').length, 2);
    });
  });
}
