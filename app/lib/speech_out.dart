// Plena's voice — talk-back (Spec 12 §6). A pluggable output seam: the on-device engine now
// (WinRT/SAPI on Windows, AVSpeechSynthesizer on Apple — the latter genuinely good), swappable
// for a cloud voice later without touching the app. onStart/onDone bracket each utterance so
// Plena's *speaking* animation anchors to real audio (Spec 15 §3.1 / §4.1).
import 'dart:io' show Platform;

import 'package:flutter_tts/flutter_tts.dart';

abstract class SpeechOutput {
  Future<void> init();
  bool get available;
  bool get speaking;

  /// Speak [text]. [onStart] fires when audio begins; [onDone] fires exactly once when this
  /// utterance ends — whether it finishes naturally OR is stopped by a later speak()/stop() —
  /// UNLESS a newer speak() superseded it first (then the newer call owns the callbacks).
  /// Fire-and-forget: callers don't await completion.
  Future<void> speak(String text, {void Function()? onStart, void Function()? onDone});

  /// Stop the current utterance (mute / barge-in). Resolves its speak() → its onDone fires once.
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
  // Each speak() gets a generation. `awaitSpeakCompletion(true)` makes `_tts.speak()` resolve
  // PER UTTERANCE (on completion or stop), so we drive onStart/onDone from that future — not the
  // shared, un-identified engine handlers — and a stale event from a superseded utterance (gen !=
  // _gen) can never cross-fire a newer utterance's callbacks (reviewer d #4/#5).
  int _gen = 0;
  void Function()? _onStart;

  /// iOS ONLY: force the shared audio session to .playback so Plena is audible **in silent mode**
  /// (like Siri) and through the speaker. AVSpeechSynthesizer otherwise obeys the physical ring/silent
  /// switch, and — critically — Apple Speech (STT) leaves the session in .record/.playAndRecord after
  /// listening, which respects the switch. So we re-assert this before EVERY utterance (not just at
  /// init): the last thing to touch the session before we speak wins. No-op off iOS.
  Future<void> _iosPlaybackSession() async {
    if (!Platform.isIOS) return;
    try {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [IosTextToSpeechAudioCategoryOptions.mixWithOthers],
        IosTextToSpeechAudioMode.defaultMode,
      );
    } catch (e) {
      onLog?.call('tts ios session failed: $e');
    }
  }

  @override
  Future<void> init() async {
    try {
      await _iosPlaybackSession();
      await _tts.awaitSpeakCompletion(true); // speak() resolves when THAT utterance ends/stops
      _tts.setStartHandler(() {
        _speaking = true;
        final s = _onStart;
        _onStart = null;
        s?.call(); // anchor the caller's onStart to real audio onset (reviewer d #9)
      });
      _tts.setErrorHandler((m) => onLog?.call('tts error: $m'));
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
    // Re-assert .playback here: if the mic just listened, the shared session is in record mode and
    // would silence her in silent mode. Doing it right before speak (post-stop) makes us the last
    // writer, so every reply is audible regardless of what STT left behind.
    await _iosPlaybackSession();
    final gen = ++_gen;
    _onStart = onStart;
    _speaking = true;
    try {
      await _tts.speak(text); // resolves when this utterance finishes OR is stopped by a later speak
    } catch (e) {
      onLog?.call('tts speak failed: $e');
    }
    if (gen != _gen) return; // superseded by a newer speak — it owns state now, don't touch anything
    _speaking = false;
    onDone?.call(); // fires exactly once per non-superseded call (natural end or barge-in stop)
  }

  @override
  Future<void> stop() async {
    _onStart = null;
    _speaking = false;
    if (!_ready) return;
    try {
      await _tts.stop(); // resolves the in-flight speak()'s future → its onDone fires once
    } catch (_) {/* best-effort */}
  }
}
