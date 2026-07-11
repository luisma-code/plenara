// Plena's voice — talk-back (Spec 12 §6). A pluggable output seam: the on-device engine now
// (WinRT/SAPI on Windows, AVSpeechSynthesizer on Apple — the latter genuinely good), swappable
// for a cloud voice later without touching the app. onStart/onDone bracket each utterance so
// Plena's *speaking* animation anchors to real audio (Spec 15 §3.1 / §4.1).
import 'package:flutter_tts/flutter_tts.dart';

abstract class SpeechOutput {
  Future<void> init();
  bool get available;
  bool get speaking;

  /// Speak [text]. [onStart] fires when audio begins, [onDone] when it finishes OR is stopped by
  /// a later speak/stop — exactly once per call. Fire-and-forget: callers don't await completion.
  Future<void> speak(String text, {void Function()? onStart, void Function()? onDone});

  /// Stop any current utterance (mute / barge-in). Does NOT fire the pending onDone.
  Future<void> stop();
}

/// Silent output — tests, muted mode, and platforms without a voice. speak() completes immediately.
class NoopSpeechOutput implements SpeechOutput {
  @override
  Future<void> init() async {}
  @override
  bool get available => false;
  @override
  bool get speaking => false;
  @override
  Future<void> speak(String text, {void Function()? onStart, void Function()? onDone}) async {
    onStart?.call();
    onDone?.call();
  }
  @override
  Future<void> stop() async {}
}

/// On-device TTS via flutter_tts. Completion is driven by the engine's handlers (not by awaiting
/// speak), so it works the same whether or not a platform blocks on synthesis.
class FlutterTtsSpeechOutput implements SpeechOutput {
  final void Function(String msg)? onLog;
  FlutterTtsSpeechOutput({this.onLog});

  final FlutterTts _tts = FlutterTts();
  bool _ready = false, _speaking = false;
  void Function()? _onDone;

  void _finish() {
    _speaking = false;
    final d = _onDone;
    _onDone = null;
    d?.call();
  }

  @override
  Future<void> init() async {
    try {
      _tts.setStartHandler(() => _speaking = true);
      _tts.setCompletionHandler(_finish);
      _tts.setCancelHandler(() => _speaking = false); // stop() manages its own onDone
      _tts.setErrorHandler((m) {
        onLog?.call('tts error: $m');
        _finish();
      });
      await _tts.setSpeechRate(.5); // engine-normalised-ish; tune later
      await _tts.setPitch(1.0);
      _ready = true;
      onLog?.call('tts ready');
    } catch (e) {
      onLog?.call('tts init failed: $e');
      _ready = false;
    }
  }

  @override
  bool get available => _ready;
  @override
  bool get speaking => _speaking;

  @override
  Future<void> speak(String text, {void Function()? onStart, void Function()? onDone}) async {
    if (!_ready || text.trim().isEmpty) {
      onStart?.call();
      onDone?.call();
      return;
    }
    await stop(); // one utterance at a time
    _onDone = onDone;
    _speaking = true;
    onStart?.call();
    try {
      await _tts.speak(text);
    } catch (e) {
      onLog?.call('tts speak failed: $e');
      _finish();
    }
  }

  @override
  Future<void> stop() async {
    _onDone = null; // an explicit stop is not a completion — don't fire onDone
    _speaking = false;
    if (!_ready) return;
    try {
      await _tts.stop();
    } catch (_) {/* best-effort */}
  }
}
