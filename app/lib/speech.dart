import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:speech_to_text/speech_to_text.dart';

/// Voice input seam (task #18). **The USER delimits the utterance, not the engine** (Spec 12 §3.1,
/// amended): tap to START, tap again to STOP — [stop] finalizes whatever was said and delivers it
/// as one final transcript, which the app auto-sends. Automatic end-of-speech detection was removed
/// because it guesses wrong: a thinking pause mid-command truncated the utterance and sent half of
/// it. Engines now only SEGMENT long speech; they never decide the speaker is finished.
///
/// [cancel] discards (the ✕ / mute paths). [onDone] fires when listening ends for any reason. The
/// typed field is always the fallback; if no engine is available the mic hides.
abstract class SpeechRecognizer {
  Future<void> init();
  bool get available;
  Stream<double> get levels => const Stream<double>.empty();

  /// [onResult] fires with the running transcript; [isFinal] marks the one final transcript for the
  /// session, emitted on [stop] (or a watchdog auto-stop). [onDone] fires when listening ends.
  /// [onNotice] reports out-of-band capture events the UI must surface (P2.8, no silent failure).
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required void Function() onDone,
    void Function(SpeechNotice notice)? onNotice,
  });
  Future<void> stop();
  void cancel();
}

/// Out-of-band things a capture session can report. The mic is user-controlled now, so anything
/// that ends or alters a session WITHOUT a tap has to be visible — an unexplained stop is exactly
/// the silent failure principle #7 forbids.
enum SpeechNotice {
  /// A long pause after speech, while still recording. The old system would have auto-sent here, so
  /// a habituated user is waiting for a send that will never come — re-show the "tap when done" hint.
  longPause,

  /// Watchdog: nothing was ever said. Session cancelled, nothing sent.
  autoCancelledNoSpeech,

  /// Watchdog: a very long trailing silence, or the hard session cap. The session was STOPPED AND
  /// SENT — never discarded, because a truncated command is recoverable and lost speech is not.
  autoStopped,
}

/// The default when no engine is wired: voice unavailable — mic hidden, typing still works.
class NoopSpeechRecognizer implements SpeechRecognizer {
  @override
  Stream<double> get levels => const Stream<double>.empty();

  @override
  Future<void> init() async {}
  @override
  bool get available => false;
  @override
  Future<void> listen({
    required void Function(String, bool) onResult,
    required void Function() onDone,
    void Function(SpeechNotice)? onNotice,
  }) async => onDone();
  @override
  Future<void> stop() async {}
  @override
  void cancel() {}
}

/// One capture session's accumulated transcript. Extracted so the invariant below is testable
/// without a live speech engine.
///
/// THE INVARIANT: real speech is never discarded. Engine finals are collected rather than sent (the
/// user's stop tap decides when an utterance is over), so whatever ends the session — a stop tap, a
/// watchdog, an engine error, the OS closing the mic — must FLUSH what was collected. Only an
/// explicit cancel throws it away. Getting this wrong is silent: the user speaks and nothing at all
/// happens, which is exactly how it shipped in build 13.
class SessionTranscript {
  final List<String> _parts = [];
  bool _done = false;

  void addFinal(String words) {
    final w = words.trim();
    if (w.isNotEmpty) _parts.add(w);
  }

  /// Everything heard so far, for display while still recording.
  String get text => _parts.join(' ').trim();
  bool get isEmpty => _parts.isEmpty;

  /// The session's transcript, exactly once. Null if already taken/discarded or empty.
  String? take() {
    if (_done) return null;
    _done = true;
    final t = text;
    _parts.clear();
    return t.isEmpty ? null : t;
  }

  /// Throw it away — a cancel must never send what was said.
  void discard() {
    _done = true;
    _parts.clear();
  }
}

/// Capture watchdog timings, shared by both engines. The mic no longer closes on its own when you
/// pause, so a forgotten-open mic is a real battery AND privacy problem — these bound it. They are
/// deliberately NOT user-settable: the tunable end-of-speech knob is exactly what this change
/// deleted, and these values are generous enough that no one meets them mid-thought. 30s is 75x the
/// old 0.4s VAD silence, so the watchdog cannot recreate the cut-off complaint.
class CaptureLimits {
  /// Nothing said at all -> cancel quietly (nothing to send).
  static const noSpeech = Duration(seconds: 15);

  /// Trailing silence after real speech -> stop AND SEND.
  static const trailingSilence = Duration(seconds: 30);

  /// A pause this long re-shows the "tap when you're done" hint (recording continues).
  static const longPauseHint = Duration(seconds: 4);

  /// Hard cap on one capture session -> stop AND SEND.
  static const session = Duration(seconds: 120);

  /// Apple's SFSpeechRecognizer is unreliable on very long single requests through the plugin, so
  /// its cap is lower than [session] until measured on-device.
  static const appleSession = Duration(seconds: 60);
}

/// The single speech-engine option builder. Apple treats [onDevice] as
/// `requiresOnDeviceRecognition = true` and fails when the locale/device cannot
/// satisfy it; there is intentionally no server-recognition fallback.
SpeechListenOptions plenaraSpeechOptions({required bool applePlatform}) =>
    SpeechListenOptions(
      partialResults: true,
      cancelOnError: true,
      onDevice: true,
      listenFor: applePlatform
          ? CaptureLimits.appleSession
          : CaptureLimits.session,
    );

/// On-device via the OS speech engine (`speech_to_text` -> Windows built-in recognition; the OS
/// owns the language model). Partial results stream live so the input fills as the user talks.
class SystemSpeechRecognizer implements SpeechRecognizer {
  final SpeechToText _stt = SpeechToText();
  final void Function(String msg)?
  onLog; // diagnostics: the raw engine lifecycle
  bool _ready = false;
  final _levels = StreamController<double>.broadcast();
  double _minLevel = double.infinity;
  double _maxLevel = double.negativeInfinity;

  @override
  Stream<double> get levels => _levels.stream;
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
      if (_ready) {
        // Diagnostic: distinguish "granted but silent" from "denied". macOS revokes mic/speech
        // permission when a debug rebuild re-signs the app, which surfaces as error_no_match.
        try {
          _log('hasPermission -> ${await _stt.hasPermission}');
        } catch (e) {
          _log('hasPermission threw: $e');
        }
      }
    } catch (e) {
      _log('initialize threw: $e');
      _ready = false; // no engine / permission denied -> voice just unavailable
    }
  }

  void _fireDone() {
    // FLUSH FIRST. The session can end without a stop tap — the engine's own listenFor cap, an
    // error with cancelOnError, or the OS closing the mic all land here. Dropping the transcript on
    // those paths meant the user spoke and nothing happened at all.
    _emitSessionFinal();
    final cb = _onDone;
    _onDone = null;
    cb?.call();
  }

  @override
  bool get available => _ready;

  /// Watchdog timers (see [CaptureLimits]). Dart-side here: the engine no longer self-endpoints.
  Timer? _noSpeechTimer, _silenceTimer, _hintTimer, _capTimer;
  bool _sawSpeech = false;
  void Function(SpeechNotice)? _onNotice;

  /// Engine finals accumulated across the session. The OS engine still endpoints on ITS OWN
  /// schedule (SAPI especially self-finalizes at the first end-of-utterance silence and cannot be
  /// told not to). Forwarding those as the session final would mean this platform never got the
  /// change at all — a thinking pause would still truncate and auto-send. So engine finals are
  /// COLLECTED here, and only the user's stop tap emits the session final.
  SessionTranscript _session = SessionTranscript();
  void Function(String, bool)? _emit;

  void _clearTimers() {
    _noSpeechTimer?.cancel();
    _silenceTimer?.cancel();
    _hintTimer?.cancel();
    _capTimer?.cancel();
    _noSpeechTimer = _silenceTimer = _hintTimer = _capTimer = null;
  }

  /// Any recognition activity (partial or final) means the speaker is still going — push the
  /// trailing-silence watchdog and the re-hint back out.
  void _bumpActivity() {
    _sawSpeech = true;
    _noSpeechTimer?.cancel();
    _silenceTimer?.cancel();
    _hintTimer?.cancel();
    _hintTimer = Timer(
      CaptureLimits.longPauseHint,
      () => _onNotice?.call(SpeechNotice.longPause),
    );
    _silenceTimer = Timer(CaptureLimits.trailingSilence, () {
      _onNotice?.call(SpeechNotice.autoStopped);
      // ignore: discarded_futures
      stop(); // stop AND SEND — never discard real speech
    });
  }

  @override
  Future<void> listen({
    required void Function(String, bool) onResult,
    required void Function() onDone,
    void Function(SpeechNotice)? onNotice,
  }) async {
    if (!_ready) {
      onDone();
      return;
    }
    _onDone = onDone;
    _onNotice = onNotice;
    _emit = onResult;
    _sawSpeech = false;
    _session = SessionTranscript();
    _minLevel = double.infinity;
    _maxLevel = double.negativeInfinity;
    _clearTimers();
    _noSpeechTimer = Timer(CaptureLimits.noSpeech, () {
      if (_sawSpeech) return;
      _onNotice?.call(SpeechNotice.autoCancelledNoSpeech);
      cancel(); // nothing was said — nothing to send
    });
    _capTimer = Timer(
      Platform.isIOS || Platform.isMacOS
          ? CaptureLimits.appleSession
          : CaptureLimits.session,
      () {
        _onNotice?.call(SpeechNotice.autoStopped);
        // ignore: discarded_futures
        stop();
      },
    );
    _log('listen: start');
    final started = DateTime.now();
    try {
      await _stt.listen(
        onSoundLevelChange: (level) {
          _minLevel = math.min(_minLevel, level);
          _maxLevel = math.max(_maxLevel, level);
          final span = _maxLevel - _minLevel;
          final normalized = span < .01 ? 0.0 : (level - _minLevel) / span;
          _levels.add(normalized.clamp(0.0, 1.0));
        },
        onResult: (r) {
          // STALE-RESULT GUARD (Windows): the plugin's SAPI backend leaves an undelivered final
          // result queued in the recognition context when a session is stopped before the engine
          // finalizes (its event-pump thread is killed on stop without draining the queue). That
          // stranded result is then delivered ~10-100ms after the NEXT listen() starts. A real
          // utterance needs >1s (speech + the engine's end-of-utterance silence), so anything this
          // early is the previous session's leftovers — drop it.
          // Windows/SAPI ONLY: the stranded-final arrives right after the next listen() starts.
          // Apple Speech streams legitimate early partials, so this guard must not run there or it
          // would drop real words.
          final age = DateTime.now().difference(started);
          if (Platform.isWindows && age < const Duration(milliseconds: 500)) {
            _log(
              "result: DISCARDED stale '${r.recognizedWords}' final=${r.finalResult} "
              '(${age.inMilliseconds}ms after listen start)',
            );
            return;
          }
          _log("result: '${r.recognizedWords}' final=${r.finalResult}");
          final words = r.recognizedWords.trim();
          if (words.isNotEmpty) _bumpActivity();
          if (r.finalResult) {
            // An ENGINE final is a segment boundary, not the end of the utterance.
            _session.addFinal(words);
            onResult(
              _session.text,
              false,
            ); // shown, never sent — no stop tap yet
          } else {
            onResult(
              [_session.text, words].where((w) => w.isNotEmpty).join(' '),
              false,
            );
          }
        },
        // Streams words as recognized (Windows SAPI only delivers finals).
        // `pauseFor` remains absent: the user, not endpointing, ends the turn.
        listenOptions: plenaraSpeechOptions(
          applePlatform: Platform.isIOS || Platform.isMacOS,
        ),
      );
    } catch (_) {
      _fireDone();
    }
  }

  @override
  Future<void> stop() async {
    _log('stop() requested (isListening=${_stt.isListening})');
    _clearTimers();
    try {
      await _stt.stop();
    } catch (e) {
      _log('stop threw: $e');
    }
    // Give the engine a moment to deliver a trailing final it had already decoded, so the last
    // words before the tap are not lost, then emit the WHOLE session as one final.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _emitSessionFinal();
  }

  void _emitSessionFinal() {
    final all = _session.take();
    if (all != null) _emit?.call(all, true);
  }

  @override
  void cancel() {
    _clearTimers();
    _session.discard(); // a cancel DISCARDS: never emit what was said
    try {
      _stt.cancel();
    } catch (_) {}
    _fireDone();
  }
}
