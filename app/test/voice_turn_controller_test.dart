// Unit tests for the voice/turn state machine — no widget tree, no Session, no
// AppLog. These are the checks that were impossible while the invariants lived
// as loose booleans on _ChatState: each one is a rule that a real shipped bug
// broke (a delivery spoken over a hot mic, a delivery clobbered by the turn
// that was still finishing, a transcript discarded by something other than the
// user's own ✕).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/operation_center.dart';
import 'package:plenara_app/speech.dart';
import 'package:plenara_app/speech_out.dart';
import 'package:plenara_app/voice_turn_controller.dart';

/// A recognizer that HOLDS the session open: `listen` captures the callbacks and
/// returns, so a test drives interim/final results (or an abort) with exact
/// timing. `stop` flushes [pendingFinal] and ends the session; `cancel` ends it
/// and throws the pending transcript away — the real engines' two doors.
class _HoldingSpeech implements SpeechRecognizer {
  final _levels = StreamController<double>.broadcast();
  @override
  Stream<double> get levels => _levels.stream;

  void Function(String, bool)? _onResult;
  void Function(SpeechNotice)? _onNotice;
  void Function()? _onDone;
  bool _active = false;
  int cancels = 0;

  /// What the engine would hand back on a stop tap.
  String? pendingFinal;

  @override
  Future<void> init() async {}
  @override
  bool get available => true;

  @override
  Future<void> listen({
    required void Function(String, bool) onResult,
    required void Function() onDone,
    void Function(SpeechNotice)? onNotice,
  }) async {
    _onResult = onResult;
    _onDone = onDone;
    _onNotice = onNotice;
    _active = true; // holds — no callback fires until the test drives one
  }

  void emitFinal(String t) => _onResult?.call(t, true);
  void emitNotice(SpeechNotice n) => _onNotice?.call(n);

  void _finish() {
    if (!_active) return;
    _active = false;
    _onDone?.call();
  }

  @override
  Future<void> stop() async {
    if (!_active) return;
    final t = pendingFinal;
    if (t != null && t.isNotEmpty) _onResult?.call(t, true);
    _finish();
  }

  @override
  void cancel() {
    cancels++;
    _finish(); // discards pendingFinal — nothing is ever sent
  }
}

/// Talk-back that completes instantly, and records whether it was ever asked to
/// speak while the mic was open.
class _FakeVoice implements SpeechOutput {
  _FakeVoice({required this.micOpen});

  /// Read at the moment [speak] is called — the barge-in invariant's witness.
  final bool Function() micOpen;
  final spoken = <String>[];
  bool spokeWithMicOpen = false;
  bool _speaking = false;

  @override
  Future<void> init() async {}
  @override
  bool get available => true;
  @override
  bool get speaking => _speaking;

  @override
  Future<void> speak(
    String text, {
    void Function()? onStart,
    void Function()? onDone,
  }) async {
    if (micOpen()) spokeWithMicOpen = true;
    spoken.add(text);
    _speaking = true;
    onStart?.call();
    _speaking = false;
    onDone?.call(); // the whole utterance lands within the call
  }

  @override
  Future<void> stop() async {
    _speaking = false;
  }
}

/// A turn runner whose completion the test controls.
class _FakeTurns {
  final utterances = <String>[];
  Completer<void>? gate;
  String reply = 'Added buy milk.';

  Future<TurnOutcome?> run(String utterance) async {
    utterances.add(utterance);
    final g = gate;
    if (g != null) await g.future;
    return TurnOutcome(response: reply, source: 'skill', skill: 'add_task');
  }
}

OperationRecord _delivery({
  String id = 'op-1',
  String title = 'Background research',
  String result = 'The detached result',
}) => OperationRecord(
  id: id,
  kind: 'test-analysis',
  title: title,
  input: const {},
  state: OperationState.succeeded,
  createdAt: DateTime(2026, 8, 17),
  updatedAt: DateTime(2026, 8, 17),
  progress: 1,
  result: result,
);

void main() {
  late _FakeTurns turns;
  late _HoldingSpeech speech;
  late _FakeVoice voice;
  late VoiceTurnController controller;
  late List<String> captureResolutions;

  setUp(() {
    turns = _FakeTurns();
    speech = _HoldingSpeech();
    captureResolutions = [];
    controller = VoiceTurnController(
      runTurn: turns.run,
      log: (_) {},
      logDebug: (_) {},
      onCaptureResolved: () => captureResolutions.add('resolved'),
    );
    voice = _FakeVoice(micOpen: () => controller.listening);
    controller.speech = speech;
    controller.voice = voice;
    addTearDown(controller.dispose);
  });

  test(
    'a delivery arriving while listening is queued, not spoken (invariant 1)',
    () async {
      await controller.toggleMic();
      expect(controller.listening, isTrue);
      final captionBeforeDelivery = controller.caption;

      controller.enqueueDeliveries([_delivery()]);

      expect(
        voice.spoken,
        isEmpty,
        reason:
            'TTS over a hot mic is what the barge-in barrier exists to stop',
      );
      expect(controller.pendingDeliveryCount, 1);
      expect(
        controller.caption,
        captionBeforeDelivery,
        reason: 'a queued delivery must not take the stage from the capture',
      );

      // The capture ends with nothing said: the mic is closed, so the delivery
      // may finally have the stage.
      controller.cancelListening();
      await Future<void>.microtask(() {});

      expect(controller.pendingDeliveryCount, 0);
      expect(
        controller.caption,
        '✨ Background research is ready\nThe detached result',
      );
      expect(voice.spoken.single, contains('Background research is ready'));
    },
  );

  test(
    'a delivery arriving mid-turn is presented after the turn completes',
    () async {
      turns.gate = Completer<void>();
      turns.reply = "I didn't catch that.";
      final send = controller.send('something the corpus cannot match');
      expect(controller.busy, isTrue);

      controller.enqueueDeliveries([_delivery()]);
      expect(
        controller.pendingDeliveryCount,
        1,
        reason: 'the in-flight turn still owns the caption',
      );
      expect(voice.spoken, isEmpty);

      turns.gate!.complete();
      await send;

      // The turn's own reply owned the stage first…
      expect(voice.spoken.first, "I didn't catch that.");
      // …and the queued delivery follows instead of having been overwritten.
      expect(controller.pendingDeliveryCount, 0);
      expect(
        controller.caption,
        '✨ Background research is ready\nThe detached result',
      );
      expect(voice.spoken.last, contains('Background research is ready'));
    },
  );

  test('TTS never starts while the mic is open (invariant 1)', () async {
    // A full round: speak a reply, open the mic mid-answer (barge-in), take a
    // delivery while listening, then finish the capture with a transcript.
    await controller.send('add buy milk to my list');
    expect(voice.spoken, isNotEmpty);

    await controller.toggleMic();
    controller.enqueueDeliveries([_delivery()]);
    controller.enqueueDeliveries([_delivery(id: 'op-2', title: 'Second')]);
    speech.emitNotice(SpeechNotice.longPause);
    speech.emitFinal('add call sam to my list');
    await Future<void>.delayed(Duration.zero);

    expect(
      voice.spokeWithMicOpen,
      isFalse,
      reason:
          'starting TTS against an open mic yields silent input or a native '
          'audio crash — nothing may speak while listening is true',
    );
    expect(controller.listening, isFalse);
  });

  group('an explicit cancel is the only path that discards a transcript', () {
    test('the STOP tap sends what was said', () async {
      speech.pendingFinal = 'add buy bread to my list';
      await controller.toggleMic();
      await controller.toggleMic(); // the stop tap
      await Future<void>.delayed(Duration.zero);

      expect(turns.utterances, ['add buy bread to my list']);
      expect(controller.heard, 'add buy bread to my list');
    });

    test(
      'a watchdog auto-stop sends, and says it stopped on its own',
      () async {
        await controller.toggleMic();
        speech.emitNotice(SpeechNotice.autoStopped);
        speech.emitFinal('add buy bread to my list');
        await Future<void>.delayed(Duration.zero);

        expect(turns.utterances, ['add buy bread to my list']);
        expect(
          controller.heard,
          '(stopped on my own after a long pause) add buy bread to my list',
        );
      },
    );

    test('the ✕ discards it — nothing is sent', () async {
      speech.pendingFinal = 'add buy bread to my list';
      await controller.toggleMic();
      controller.cancelListening();
      await Future<void>.delayed(Duration.zero);

      expect(turns.utterances, isEmpty);
      expect(controller.heard, isNull);
      expect(controller.listening, isFalse);
      expect(
        captureResolutions,
        isNotEmpty,
        reason:
            'a cancelled capture must still release a deferred step advance',
      );
    });

    test(
      'muting discards the capture too (it switches to text mode)',
      () async {
        speech.pendingFinal = 'add buy bread to my list';
        await controller.toggleMic();
        controller.toggleMute();
        await Future<void>.delayed(Duration.zero);

        expect(controller.voiceMuted, isTrue);
        expect(controller.listening, isFalse);
        expect(turns.utterances, isEmpty);
      },
    );

    test('backgrounding discards it and says why', () async {
      speech.pendingFinal = 'add buy bread to my list';
      await controller.toggleMic();
      controller.abandonForBackground('I stopped listening.');
      await Future<void>.delayed(Duration.zero);

      expect(turns.utterances, isEmpty);
      expect(controller.caption, 'I stopped listening.');
    });
  });
}
