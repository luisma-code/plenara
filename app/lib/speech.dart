import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

/// Voice input seam (task #18). Push-to-talk: [transcribe] captures speech until the user stops
/// (or a natural pause) and returns the final text — or null if nothing was heard or it was
/// cancelled. [init] does any async setup; the UI shows a mic button only when [available] is
/// true, and the typed field is always the fallback, so the app is fully usable with no speech at
/// all.
abstract class SpeechRecognizer {
  Future<void> init();
  bool get available;
  Future<String?> transcribe();
  void cancel();
}

/// The default when no engine is wired (or a platform lacks one): voice unavailable — mic hidden,
/// typing still works. Nothing breaks without speech.
class NoopSpeechRecognizer implements SpeechRecognizer {
  @override
  Future<void> init() async {}
  @override
  bool get available => false;
  @override
  Future<String?> transcribe() async => null;
  @override
  void cancel() {}
}

/// On-device via the OS speech engine (`speech_to_text` -> Windows' built-in recognition; the OS
/// owns the language model, a one-time OS download). Fully offline-capable where the platform
/// supports it; if initialization fails or no recognizer is present, [available] stays false and
/// the mic simply hides.
class SystemSpeechRecognizer implements SpeechRecognizer {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;

  @override
  Future<void> init() async {
    try {
      _ready = await _stt.initialize(onError: (_) {}, onStatus: (_) {});
    } catch (_) {
      _ready = false; // no engine / permission denied -> voice just unavailable
    }
  }

  @override
  bool get available => _ready;

  @override
  Future<String?> transcribe() async {
    if (!_ready) return null;
    final done = Completer<String?>();
    void finish(String? text) {
      if (!done.isCompleted) done.complete((text != null && text.trim().isNotEmpty) ? text.trim() : null);
    }

    try {
      await _stt.listen(
        onResult: (r) {
          if (r.finalResult) finish(r.recognizedWords);
        },
        listenOptions: SpeechListenOptions(
          partialResults: false,
          cancelOnError: true,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3), // a natural pause ends the utterance
        ),
      );
    } catch (_) {
      finish(null);
    }
    // if listening ends (pause/timeout) without ever delivering a final result, don't hang
    return done.future.timeout(const Duration(seconds: 35), onTimeout: () {
      _stt.cancel();
      return null;
    });
  }

  @override
  void cancel() => _stt.cancel();
}
