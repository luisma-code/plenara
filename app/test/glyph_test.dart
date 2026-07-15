import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/glyphs.dart';
import 'package:plenara_app/plena.dart';

void main() {
  group('glyphForTurn — apt-or-absent (Spec 15 §5A.1)', () {
    test('a meaningful completion → check', () => expect(glyphForTurn('complete-task', "Nice — that's done.")?.id, 'check'));
    // Everyday writes now get an apt mark (previously most fired nothing — the app felt inert).
    test('a task add → a "got it" nod', () => expect(glyphForTurn('create-task', 'Added milk to your list.')?.id, 'nod'));
    test('a reminder set → the bell', () => expect(glyphForTurn('set-reminder', "I'll remind you tomorrow at 8.")?.id, 'bell'));
    test('a person fact → a spark', () => expect(glyphForTurn('remember-person-fact', "Got it — Mia is Sarah's daughter.")?.id, 'spark'));
    test('a logged run → a quiet nod', () => expect(glyphForTurn('log-run', 'Logged a 3k run.')?.id, 'nod'));
    test('a logged interaction → a quiet nod', () => expect(glyphForTurn('log-interaction', 'Logged that you talked to Sam.')?.id, 'nod'));
    test('closeness with a partner → the heart', () => expect(glyphForTurn('remember-relationship', 'Noted Vanessa is your wife.')?.id, 'heart'));
    test('a streak in the reply → the star', () => expect(glyphForTurn('goal-progress', 'Seven days running — a streak!')?.id, 'star'));
    test('goal set → target', () => expect(glyphForTurn('set-goal', 'Goal set.')?.id, 'target'));
    test('no skill → nothing', () => expect(glyphForTurn(null, 'anything'), isNull));
  });

  group('glyph library', () {
    test('the core set is present', () {
      for (final id in ['smile', 'check', 'heart', 'wave', 'spark', 'question', 'ellipsis', 'sunrise', 'crescent', 'star', 'candle', 'nod', 'ripple', 'settle', 'quill']) {
        expect(kGlyphs[id]?.core, isTrue, reason: id);
      }
    });
    test('every glyph has geometry and a positive lastFill', () {
      for (final g in kGlyphs.values) {
        expect(g.strokes.isNotEmpty || g.dots.isNotEmpty, isTrue, reason: g.id);
        expect(g.lastFill, greaterThan(0), reason: g.id);
      }
    });
  });

  testWidgets('a glyph flies (and rejoins) without throwing', (tester) async {
    Widget build(int nonce) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 220,
              width: 320,
              child: PresenceView(
                  state: PresenceState.speaking, animate: true, glyph: kGlyphs['check'], glyphNonce: nonce),
            ),
          ),
        );
    await tester.pumpWidget(build(0));
    await tester.pump();
    await tester.pumpWidget(build(1)); // bump the nonce → didUpdateWidget starts the flight
    for (var i = 0; i < 60; i++) { await tester.pump(const Duration(milliseconds: 16)); } // ~1s of flight
    expect(tester.takeException(), isNull);
  });
}
