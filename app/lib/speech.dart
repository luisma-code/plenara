import 'package:speech_to_text/speech_to_text.dart';

/// Voice input seam (task #18). Tap to START; the ENGINE finalizes the utterance when the speaker
/// pauses (its own end-of-utterance detection) and delivers the final transcript in-session; tap
/// again to ABORT. [listen] streams the transcript to [onResult] (finals only on Windows) and
/// calls [onDone] when it ends (user stop, error, or a long timeout). The typed field is always
/// the fallback; if no engine is available the mic hides.
abstract class SpeechRecognizer {
  Future<void> init();
  bool get available;
  /// [onResult] fires with the running transcript; [isFinal] marks the engine's final result for
  /// an utterance (which some engines — e.g. Windows — deliver with noticeable latency, even after
  /// listening has stopped). [onDone] fires when listening ends.
  Future<void> listen({required void Function(String text, bool isFinal) onResult, required void Function() onDone});
  Future<void> stop();
  void cancel();
}

/// The default when no engine is wired: voice unavailable — mic hidden, typing still works.
class NoopSpeechRecognizer implements SpeechRecognizer {
  @override
  Future<void> init() async {}
  @override
  bool get available => false;
  @override
  Future<void> listen({required void Function(String, bool) onResult, required void Function() onDone}) async =>
      onDone();
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
  Future<void> listen({required void Function(String, bool) onResult, required void Function() onDone}) async {
    if (!_ready) {
      onDone();
      return;
    }
    _onDone = onDone;
    _log('listen: start');
    final started = DateTime.now();
    try {
      await _stt.listen(
        onResult: (r) {
          // STALE-RESULT GUARD (Windows): the plugin's SAPI backend leaves an undelivered final
          // result queued in the recognition context when a session is stopped before the engine
          // finalizes (its event-pump thread is killed on stop without draining the queue). That
          // stranded result is then delivered ~10-100ms after the NEXT listen() starts. A real
          // utterance needs >1s (speech + the engine's end-of-utterance silence), so anything this
          // early is the previous session's leftovers — drop it.
          final age = DateTime.now().difference(started);
          if (age < const Duration(milliseconds: 500)) {
            _log("result: DISCARDED stale '${r.recognizedWords}' final=${r.finalResult} "
                '(${age.inMilliseconds}ms after listen start)');
            return;
          }
          _log("result: '${r.recognizedWords}' final=${r.finalResult}");
          onResult(r.recognizedWords, r.finalResult);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true, // stream words as they're recognized (no-op on Windows: the SAPI
          // backend never registers for hypothesis events, so ONLY finals arrive)
          cancelOnError: true,
          listenFor: const Duration(seconds: 45),
          // NO pauseFor: it's a Dart-side timer reset by results, and Windows delivers no partial
          // results — so it fires exactly pauseFor after start and kills the session while the
          // user is mid-sentence, before the engine finalizes. The engine's own end-of-utterance
          // silence detection delivers the final result in-session instead; listenFor is the cap.
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
