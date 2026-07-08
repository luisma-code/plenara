import 'dart:async';

/// Voice input seam (task #18). Push-to-talk: [transcribe] captures speech until the user stops
/// (or a natural pause) and returns the final text — or null if nothing was heard or it was
/// cancelled. The concrete engine (on-device or cloud) is selected at build time; the UI shows a
/// mic button only when [available] is true, and the typed text field is always the fallback, so
/// the app is fully usable with no speech dependency at all.
abstract class SpeechRecognizer {
  bool get available;
  Future<String?> transcribe();
  void cancel();
}

/// The default when no STT engine is wired (or the platform lacks one): voice is simply
/// unavailable — the mic button hides and typing still works. Nothing breaks without speech.
class NoopSpeechRecognizer implements SpeechRecognizer {
  @override
  bool get available => false;
  @override
  Future<String?> transcribe() async => null;
  @override
  void cancel() {}
}
