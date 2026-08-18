/// The capture invariant that build 13 broke: **real speech is never discarded.**
///
/// Engine finals are collected rather than sent (the user's stop tap decides when an utterance is
/// over), so whatever ends the session must FLUSH what was collected — a stop tap, a watchdog, an
/// engine error, or the OS closing the mic. Only an explicit cancel throws it away.
///
/// The failure mode is completely silent — you speak and nothing happens — which is exactly how it
/// reached the phone. These tests exist so it can't return.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/speech.dart';

void main() {
  test('speech recognition is forced on-device with no server fallback', () {
    final apple = plenaraSpeechOptions(applePlatform: true);
    final other = plenaraSpeechOptions(applePlatform: false);
    expect(apple.onDevice, isTrue);
    expect(other.onDevice, isTrue);
    expect(apple.listenFor, CaptureLimits.appleSession);
    expect(other.listenFor, CaptureLimits.session);
  });

  test('collects engine finals and hands them over once, joined', () {
    final t = SessionTranscript()
      ..addFinal('what can')
      ..addFinal('you do');
    expect(t.text, 'what can you do');
    expect(t.take(), 'what can you do');
    expect(
      t.take(),
      isNull,
      reason: 'exactly once — a second flush must not double-send',
    );
  });

  test('an ended session flushes what was heard — the build-13 bug', () {
    // The engine ends the session on its own (listenFor cap, an error, the OS closing the mic).
    // Before the fix this path dropped everything and the user saw nothing at all.
    final t = SessionTranscript()..addFinal('what can you do');
    expect(t.take(), 'what can you do');
  });

  test('a cancel discards — nothing said is ever sent', () {
    final t = SessionTranscript()..addFinal('forget this');
    t.discard();
    expect(t.take(), isNull);
  });

  test(
    'empty and whitespace-only input yield nothing rather than an empty turn',
    () {
      final t = SessionTranscript()
        ..addFinal('   ')
        ..addFinal('');
      expect(t.isEmpty, isTrue);
      expect(t.take(), isNull);
    },
  );

  test('partial text is visible while recording without being sent', () {
    final t = SessionTranscript()..addFinal('remind me');
    expect(t.text, 'remind me', reason: 'shown live');
    t.addFinal('to buy milk');
    expect(t.text, 'remind me to buy milk');
    expect(t.take(), 'remind me to buy milk', reason: 'only the flush sends');
  });

  test(
    'Apple partial followed by done flushes the visible words exactly once',
    () {
      final emissions = <({String text, bool finalResult})>[];
      final capture = RecognitionSession(
        (text, finalResult) =>
            emissions.add((text: text, finalResult: finalResult)),
      );

      capture.addEngineResult('This', finalResult: false);
      capture.addEngineResult('This work is complete', finalResult: false);
      capture.finish(); // Apple's `done` can arrive without an engine final.
      capture
          .finish(); // stop() returning is a second completion signal: no duplicate.

      expect(emissions, [
        (text: 'This', finalResult: false),
        (text: 'This work is complete', finalResult: false),
        (text: 'This work is complete', finalResult: true),
      ]);
    },
  );

  test('cancel is the only completion path that discards an Apple partial', () {
    final emissions = <({String text, bool finalResult})>[];
    final capture = RecognitionSession(
      (text, finalResult) =>
          emissions.add((text: text, finalResult: finalResult)),
    );

    capture.addEngineResult('do not send this', finalResult: false);
    capture.finish(discard: true);

    expect(emissions, [(text: 'do not send this', finalResult: false)]);
  });
}
