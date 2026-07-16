/// Numbered-list corrections (reference-by-number over the last spoken readback).
/// A misheard item ("Zpack my clothes") is re-targetable by the number Plena spoke —
/// no fuzzy text match. Covers the `enumerate`/`ref_mark` DSL channel, the session
/// context, all three actions (complete/delete/correct incl. two-turn re-speak), undo
/// round-trips, and every failure surface. Real storage per the project's no-mock rule.
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _now = DateTime.parse('2026-07-06T09:00:00');

class _NoCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s,
          {Set<String> knownContacts = const {}}) async =>
      const CloudOk(null); // offline: corpus/regex only
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<String>> generate(String k, String c) async => const CloudError(CloudErrorKind.noKey);
}

Future<Session> _s() async {
  final s = Session(makeTempDataDir(), clock: _now, cloud: _NoCloud());
  await s.init(retrieval: false);
  return s;
}

void main() {
  group('numbered readback + reference-by-number', () {
    test('a task list reads back numbered (1. / 2.), not bulleted', () async {
      final s = await _s();
      await s.handle('add zpack my clothes to my list');
      await s.handle('add call mom to my list');
      final list = await s.handle('list my tasks');
      expect(list, contains('1. zpack my clothes'));
      expect(list, contains('2. call mom'));
      expect(list, isNot(contains('•')));
    });

    test('"delete 1" removes the exact item spoken as 1, and undo restores it', () async {
      final s = await _s();
      await s.handle('add zpack my clothes to my list');
      await s.handle('add call mom to my list');
      await s.handle('list my tasks'); // arms the enumeration context
      final del = await s.handle('delete 1');
      expect(del.toLowerCase(), contains('zpack my clothes'));
      final after = await s.handle('list my tasks');
      expect(after, isNot(contains('zpack my clothes')));
      expect(after, contains('call mom'));
      final undo = await s.handle('undo that');
      expect(undo.toLowerCase(), contains('zpack my clothes'));
      expect(await s.handle('list my tasks'), contains('zpack my clothes'));
    });

    test('"complete todo 2" marks the second item done', () async {
      final s = await _s();
      await s.handle('add zpack my clothes to my list');
      await s.handle('add call mom to my list');
      await s.handle('list my tasks');
      final done = await s.handle('complete todo 2');
      expect(done.toLowerCase(), contains('call mom'));
      final open = await s.handle('list my tasks');
      expect(open, isNot(contains('call mom'))); // completed drops off the open list
      expect(open, contains('zpack my clothes'));
    });

    test('two-turn correct: "correct 1" → re-speak replaces the misheard text', () async {
      final s = await _s();
      await s.handle('add zpack my clothes to my list');
      await s.handle('list my tasks');
      final ask = await s.handle('correct 1');
      expect(ask.toLowerCase(), contains('what should it say'));
      final fixed = await s.handle('pack my clothes');
      expect(fixed.toLowerCase(), contains('pack my clothes'));
      final list = await s.handle('list my tasks');
      expect(list, contains('pack my clothes'));
      expect(list, isNot(contains('zpack')));
    });

    test('one-turn inline correct: "change 1 to buy oat milk"', () async {
      final s = await _s();
      await s.handle('add buy milk to my list');
      await s.handle('list my tasks');
      final fixed = await s.handle('change 1 to buy oat milk');
      expect(fixed.toLowerCase(), contains('buy oat milk'));
      expect(await s.handle('list my tasks'), contains('buy oat milk'));
    });

    test('correct accepts a command-shaped replacement verbatim (no command misroute)', () async {
      final s = await _s();
      await s.handle('add zpack the car to my list');
      await s.handle('list my tasks');
      await s.handle('correct 1');
      final fixed = await s.handle('call the mechanic'); // command-shaped, but it's dictation
      expect(fixed.toLowerCase(), contains('call the mechanic'));
      final list = await s.handle('list my tasks');
      expect(list, contains('call the mechanic'));
      // and it did NOT create a second task from the "call" phrasing
      expect(RegExp('call the mechanic').allMatches(list).length, 1);
    });

    test('cancel mid-correction leaves the item unchanged', () async {
      final s = await _s();
      await s.handle('add zpack my clothes to my list');
      await s.handle('list my tasks');
      await s.handle('correct 1');
      final out = await s.handle('never mind');
      expect(out.toLowerCase(), contains('stays'));
      expect(await s.handle('list my tasks'), contains('zpack my clothes'));
    });

    test('reference survives an intervening non-list turn', () async {
      final s = await _s();
      await s.handle('add zpack my clothes to my list');
      await s.handle('add call mom to my list');
      await s.handle('list my tasks');
      await s.handle('remember that Sarah loves hiking'); // unrelated turn
      final del = await s.handle('delete 2');
      expect(del.toLowerCase(), contains('call mom'));
    });

    test('out-of-range reference is admitted, not silent', () async {
      final s = await _s();
      await s.handle('add only task to my list');
      await s.handle('list my tasks');
      final out = await s.handle('delete 5');
      expect(out.toLowerCase(), contains('only had 1 item'));
    });

    test('a reference with no active list points the user at a readback', () async {
      final s = await _s();
      await s.handle('add a task to my list');
      final out = await s.handle('delete 2'); // no list was read back
      expect(out.toLowerCase(), contains('no numbered list'));
    });

    test('the last readback wins across different types', () async {
      final s = await _s();
      await s.handle('add buy milk to my list');
      await s.handle('list my tasks');
      await s.handle('remind me to call the dentist tomorrow at 3pm');
      final rem = await s.handle('list my reminders'); // now reminders are the active list
      expect(rem, contains('1. call the dentist'));
      final del = await s.handle('delete 1');
      expect(del.toLowerCase(), contains('call the dentist')); // targets the reminder, not the task
      expect(await s.handle('list my tasks'), contains('buy milk')); // task untouched
    });

    test('"last" resolves to the final item', () async {
      final s = await _s();
      await s.handle('add first to my list');
      await s.handle('add middle to my list');
      await s.handle('add final one to my list');
      await s.handle('list my tasks');
      final del = await s.handle('delete the last one');
      expect(del.toLowerCase(), contains('final one'));
    });

    test('complete on a type with no done-field refuses with an actionable message', () async {
      final s = await _s();
      await s.handle('remember that Sarah loves hiking');
      await s.handle('remember that Sarah is into pottery');
      final facts = await s.handle('what do you know about Sarah');
      expect(facts, contains('1. ')); // knowledge lists are numbered too
      final out = await s.handle('complete 1');
      expect(out.toLowerCase(), contains("isn't something i mark done"));
      expect(out.toLowerCase(), contains('delete')); // offers the actionable alternatives
    });

    test('correcting a knowledge item rewrites the fact', () async {
      final s = await _s();
      await s.handle('remember that Sarah loves hiiking'); // typo'd fact
      await s.handle('what do you know about Sarah');
      final fixed = await s.handle('change 1 to Sarah loves hiking');
      expect(fixed.toLowerCase(), contains('hiking'));
      expect(await s.handle('what do you know about Sarah'), contains('loves hiking'));
    });

    test('an empty readback clears a stale reference context', () async {
      final s = await _s();
      await s.handle('add buy milk to my list');
      await s.handle('list my tasks'); // context = the task
      final rem = await s.handle('list my reminders'); // zero reminders — an empty readback
      expect(rem.toLowerCase(), contains('0 reminder'));
      final out = await s.handle('delete 1'); // must NOT hit the stale task
      expect(out.toLowerCase(), contains('no numbered list'));
      expect(await s.handle('list my tasks'), contains('buy milk')); // task untouched
    });
  });
}
