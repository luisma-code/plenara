import 'package:speech_to_text/speech_to_text.dart';

/// Voice input seam (task #18). A START/STOP model with LIVE results so the user sees words appear
/// as they speak and stops on their own terms (tap the mic again) — not a silent-pause guess.
/// [listen] streams the running transcript to [onResult] and calls [onDone] when it ends (user
/// stop, error, or a long timeout). The typed field is always the fallback; if no engine is
/// available the mic hides.
abstract class SpeechRecognizer {
  Future<void> init();
  bool get available;
  Future<void> listen({required void Function(String text) onResult, required void Function() onDone});
  Future<void> stop(); // finalize + keep what was captured
  void cancel(); // discard
}

/// The default when no engine is wired: voice unavailable — mic hidden, typing still works.
class NoopSpeechRecognizer implements SpeechRecognizer {
  @override
  Future<void> init() async {}
  @override
  bool get available => false;
  @override
  Future<void> listen({required void Function(String) onResult, required void Function() onDone}) async => onDone();
  @override
  Future<void> stop() async {}
  @override
  void cancel() {}
}

/// On-device via the OS speech engine (`speech_to_text` -> Windows built-in recognition; the OS
/// owns the language model). Partial results stream live so the input fills as the user talks.
class SystemSpeechRecognizer implements SpeechRecognizer {
  final SpeechToText _stt = SpeechToText();
  final void Function(String msg)? onLog; // diagnostics: the raw engine lifecycle
  bool _ready = false;
  void Function()? _onDone;
  SystemSpeechRecognizer({this.onLog});
  void _log(String m) => onLog?.call(m);

  @override
  Future<void> init() async {
    try {
      _ready = await _stt.initialize(
        onError: (e) {
          _log('error: $e');
          _fireDone();
        },
        onStatus: (s) {
          _log('status: $s');
          if (s == 'done' || s == 'notListening') _fireDone();
        },
      );
      _log('initialize -> $_ready');
    } catch (e) {
      _log('initialize threw: $e');
      _ready = false; // no engine / permission denied -> voice just unavailable
    }
  }

  void _fireDone() {
    final cb = _onDone;
    _onDone = null;
    cb?.call();
  }

  @override
  bool get available => _ready;

  @override
  Future<void> listen({required void Function(String) onResult, required void Function() onDone}) async {
    if (!_ready) {
      onDone();
      return;
    }
    _onDone = onDone;
    _log('listen: start');
    try {
      await _stt.listen(
        onResult: (r) {
          _log("result: '${r.recognizedWords}' final=${r.finalResult}");
          onResult(r.recognizedWords);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true, // stream words as they're recognized
          cancelOnError: true,
          // long windows — the USER decides when to stop (tap the mic), not an 8s silence guess
          listenFor: const Duration(seconds: 120),
          pauseFor: const Duration(seconds: 15),
        ),
      );
    } catch (_) {
      _fireDone();
    }
  }

  @override
  Future<void> stop() async {
    _log('stop() requested (isListening=${_stt.isListening})');
    try {
      await _stt.stop();
    } catch (e) {
      _log('stop threw: $e');
    }
  }

  @override
  void cancel() {
    try {
      _stt.cancel();
    } catch (_) {}
    _fireDone();
  }
}
