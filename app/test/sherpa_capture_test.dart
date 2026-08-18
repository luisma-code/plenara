/// The local-Whisper engine's half of the capture contract.
///
/// `SherpaSpeechRecognizer` is the primary Windows engine and had no tests at
/// all, while carrying its own copy of the invariants `speech.dart` states:
/// **real speech is never discarded**, and `onDone` fires exactly once however
/// the session ends. Its copy was the one that dropped an entire dictation when
/// the audio stream errored — the same silent failure class as build 13, on the
/// engine nobody was testing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/sherpa_speech.dart';

/// A capture wired to recorders instead of a microphone.
({
  SherpaCaptureSession session,
  List<String> finals,
  List<String> partials,
  int Function() doneCount,
})
_capture({List<String> tail = const []}) {
  final finals = <String>[];
  final partials = <String>[];
  var done = 0;
  final session = SherpaCaptureSession(
    onResult: (text, isFinal) => (isFinal ? finals : partials).add(text),
    onDone: () => done++,
    drainTail: () => tail,
  );
  return (
    session: session,
    finals: finals,
    partials: partials,
    doneCount: () => done,
  );
}

void main() {
  test('an engine error mid-capture still delivers what was transcribed', () {
    // THE BUG: the audio stream's onError called finish() without a flush, so
    // every completed segment was thrown away. On Windows a device hiccup part
    // way through a long dictation meant the user's words simply vanished —
    // no transcript, no error, nothing sent.
    final c = _capture();
    c.session.addSegment('remind me to call');
    c.session.addSegment('the dentist tomorrow');

    c.session.finish(flush: true); // what the audio onError handler now does

    expect(c.finals, ['remind me to call the dentist tomorrow']);
    expect(c.doneCount(), 1);
  });

  test('the stop tap delivers the accumulated segments joined with the tail',
      () {
    final c = _capture(tail: ['and buy milk']);
    c.session.addSegment('remember to water the plants');

    c.session.finish(flush: true);

    expect(c.finals, ['remember to water the plants and buy milk']);
  });

  test('closed segments publish a running partial as they land', () {
    // Parity with the system recognizer: without this the caption stayed blank
    // for the whole capture on this engine, which reads as "it isn't hearing me".
    final c = _capture();
    c.session.addSegment('what can');
    c.session.addSegment('you do');

    expect(c.partials, ['what can', 'what can you do']);
    expect(c.finals, isEmpty, reason: 'a segment boundary is not the utterance');
  });

  test('onDone fires exactly once when the host cancels from inside its own '
      'final-result handler', () {
    // The host answers a final with cancel() — "one utterance per tap". That
    // re-entrant cancel used to consume the done callback before finish() could
    // read it, so the session never reported that it had ended and the mic
    // state was never released.
    final finals = <String>[];
    var done = 0;
    late final SherpaCaptureSession session;
    session = SherpaCaptureSession(
      onResult: (text, isFinal) {
        if (!isFinal) return;
        finals.add(text);
        session.cancel(); // exactly what the host does
      },
      onDone: () => done++,
      drainTail: () => const [],
    );

    session.addSegment('add buy bread to my list');
    session.finish(flush: true);

    expect(finals, ['add buy bread to my list']);
    expect(done, 1, reason: 'exactly once — not zero, not twice');
  });

  test('an explicit cancel discards and still reports the end once', () {
    final c = _capture();
    c.session.addSegment('something i take back');

    c.session.cancel();

    expect(c.finals, isEmpty, reason: 'cancel is the only discard path');
    expect(c.doneCount(), 1);
    c.session.cancel();
    expect(c.doneCount(), 1, reason: 'a second cancel is a no-op');
  });

  test('a no-speech watchdog cancel reports the end (the seam contract)', () {
    // The watchdog used to have to reach around cancel() and fire onDone
    // itself, because cancel() nulled the callback without calling it.
    final c = _capture();
    c.session.cancel(); // nothing heard — nothing to send
    expect(c.doneCount(), 1);
  });

  test('a session that ends twice emits one final and one done', () {
    final c = _capture();
    c.session.addSegment('only once');
    c.session.finish(flush: true);
    c.session.finish(flush: true); // a watchdog racing the stop tap
    expect(c.finals, ['only once']);
    expect(c.doneCount(), 1);
  });

  test('segments arriving after the door closed are ignored', () {
    final c = _capture();
    c.session.finish(flush: true);
    c.session.addSegment('late words from a dead session');
    expect(c.partials, isEmpty);
    expect(c.session.segments, isEmpty);
  });
}
