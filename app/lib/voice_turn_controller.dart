// The voice/turn state machine — the one owner of "who is speaking, who is
// listening, and what is on the stage".
//
// This used to be a dozen loose booleans on _ChatState, and every bug that
// mattered lived in the gaps between them: a delivery spoken over a hot mic, a
// delivery clobbered by the turn that was still finishing, a step timer that
// started a turn mid-utterance and ate the transcript. The invariants are:
//
//   1. TTS never starts while the mic is open.
//   2. Speech is never discarded except by an explicit cancel (the ✕, mute, or
//      backgrounding). A stop tap SENDS; a watchdog stop SENDS.
//   3. One owner of the caption at a time — a queued operation delivery waits
//      until no turn and no capture owns the stage.
//
// It is a [ChangeNotifier] with no BuildContext, no Session and no AppLog: the
// screen supplies those as seams, so the rules above are unit-testable with
// plain fakes and no widget tree.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:plenara/operation_center.dart';

import 'plena.dart';
import 'speech.dart';
import 'speech_out.dart';

/// One turn's result, as the controller needs it. The screen's [VoiceTurnController.runTurn]
/// adapts `Session` to this, so the controller never touches the engine.
class TurnOutcome {
  /// The engine's reply, verbatim — what gets SPOKEN.
  final String response;

  /// Automation deliveries (✨) and newly-held writes (📋) appended to the
  /// DISPLAYED text but not to the spoken text.
  final List<String> extras;
  final bool usedCloud;
  final String? source;
  final String? skill;
  final String? tourChapter;

  const TurnOutcome({
    required this.response,
    this.extras = const [],
    this.usedCloud = false,
    this.source,
    this.skill,
    this.tourChapter,
  });
}

class VoiceTurnController extends ChangeNotifier {
  /// Run one turn through the engine and report what came back. Any engine-side
  /// failure is this callback's problem — it must always return an outcome.
  /// It returns null when the screen was torn down mid-turn: the engine's
  /// post-turn state is then left undrained, exactly as before.
  final Future<TurnOutcome?> Function(String utterance) runTurn;

  /// App-layer navigation commands ("open settings"): true means the utterance
  /// opened a window instead of becoming a turn.
  final bool Function(String text) navCommand;

  /// A new turn is starting (before the nav-command check) — cancels the tour's
  /// colour demo.
  final void Function() onTurnStarting;

  /// The reply is on the stage and speech has been started: fire the turn's
  /// glyph / acknowledgement / tour chapter.
  final void Function(TurnOutcome outcome) onTurnPresented;

  /// Re-sync the routine cadence to the run after a turn.
  final void Function() syncRoutineCadence;

  /// A capture session ended (final, done, or cancel) — release any step
  /// advance that was deferred while the mic was open.
  final void Function() onCaptureResolved;

  /// Persist the decaying stop-gesture hint count across launches.
  final void Function(int shown) persistMicHints;

  /// Persist the mute preference between launches.
  final void Function(bool muted) persistMute;

  final void Function(String message) log;
  final void Function(String message) logDebug;

  VoiceTurnController({
    required this.runTurn,
    required this.log,
    required this.logDebug,
    this.navCommand = _noNavCommand,
    this.onTurnStarting = _noop,
    this.onTurnPresented = _ignoreOutcome,
    this.syncRoutineCadence = _noop,
    this.onCaptureResolved = _noop,
    this.persistMicHints = _ignoreInt,
    this.persistMute = _ignoreBool,
  });

  static bool _noNavCommand(String _) => false;
  static void _noop() {}
  static void _ignoreOutcome(TurnOutcome _) {}
  static void _ignoreInt(int _) {}
  static void _ignoreBool(bool _) {}

  // ---- the seams the screen fills in after _init picks them -------------------------------------
  /// Chosen in the screen's `_init`: on-device sherpa_onnx if its model is present, else the OS
  /// engine, else Noop. Tests inject their own. Null until then; the mic hides while null.
  SpeechRecognizer? speech;

  /// Plena's talk-back (Spec 12 §6); chosen in the screen's `_init`.
  SpeechOutput? voice;

  // ---- state -----------------------------------------------------------------------------------
  double _micLevel = 0;
  bool _voiceMuted =
      false; // mute silences her voice; captions still show (Spec 15 §7)
  int _noMatchStreak =
      0; // consecutive tap-to-talks that heard nothing → surface a mic-permission hint
  int _micEpoch =
      0; // bumped on every tap/abort; a listen-start whose epoch went stale bails (race)
  bool _aborting =
      false; // a deliberate ✕/mute abort — its cancel's onDone must not count as no-audio
  // Correlation id for the live capture session: prefixes recognizer log lines
  // and becomes the turn id of the send its final transcript triggers, so the
  // whole voice path shares one grep key. Null while no capture is live.
  String? _captureId;
  String?
  _heard; // the finalized transcript, echoed as "I heard: X" (the listening font), briefly
  Timer? _heardTimer;
  // Capture is user-delimited now (tap to start, tap to stop). These support that:
  bool _transcribing =
      false; // stop tapped, final not back yet → presence shows thinking, not idle
  bool _autoStopped =
      false; // a watchdog ended the session, not a tap → say so on the "I heard" line
  String?
  _micPrompt; // the "tap when you're done" affordance line (decays; see _micHintSessions)
  Timer? _hintTimer;
  static const _micHintSessions =
      5; // teach the gesture, then go quiet (Spec 07 P8)
  int _micHintsShown =
      0; // persisted, so the hint decays across launches rather than per-run
  final input = TextEditingController();
  bool _busy = false, _listening = false;
  // Plena's presence state (Spec 15): derived from the real turn/speech signals. No TTS yet,
  // so "speaking" is a brief flourish while a reply lands; _lastCloud tints it cooler (D2).
  bool _speaking = false, _lastCloud = false, _deepThink = false;
  Timer? _speakTimer, _thinkTimer, _capTimer;
  String?
  _caption; // the current exchange text, materialised over the void (Spec 15 §6.1 / §7.3)
  bool _displayIsList =
      false; // a list-shaped reply eases Plena to a corner (§6.3)
  PresenceExpression _expression = PresenceExpression.neutral;
  bool _disposed = false;

  double get micLevel => _micLevel;
  bool get voiceMuted => _voiceMuted;
  String? get captureId => _captureId;
  String? get heard => _heard;
  bool get transcribing => _transcribing;
  String? get micPrompt => _micPrompt;
  int get micHintsShown => _micHintsShown;
  bool get busy => _busy;
  bool get listening => _listening;
  bool get speaking => _speaking;
  String? get caption => _caption;
  bool get displayIsList => _displayIsList;
  PresenceExpression get expression => _expression;

  /// The live presence signals, before any dev-harness pin.
  PresenceState get presence => _listening
      ? PresenceState.listening
      // Between the stop tap and the final transcript there is real work (flush + transcribe
      // the trailing segment). Showing idle there would make the stop tap look like a dead beat.
      : _busy || _transcribing
      ? PresenceState.thinking
      : _speaking
      ? PresenceState.speaking
      : PresenceState.idle;

  // D1 while a turn is in flight; D2 once it's clearly working (a long/cloud turn), so Plena
  // visibly "reaches" (Spec 15 §4.2). Speaking a cloud-derived answer keeps the cooler tint.
  double get difficulty =>
      _busy ? (_deepThink ? 2 : 1) : (_speaking && _lastCloud ? 2 : 0);

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  // ---- startup-time state the screen restores ---------------------------------------------------
  /// Apply the remembered preferences read at init.
  void restorePreferences({required bool voiceMuted, required int micHints}) {
    _voiceMuted = voiceMuted;
    _micHintsShown = micHints;
  }

  /// Live mic energy, but only while the mic is actually open.
  void setMicLevel(double level) {
    if (_disposed || !_listening) return;
    _micLevel = level;
    _notify();
  }

  /// Put text on the stage directly, bypassing a turn — a routine player
  /// refusal, or the Dev harness driving the display registers by hand.
  void setDisplay(String? caption, bool isList) {
    _caption = caption;
    _displayIsList = isList;
    _notify();
  }

  /// Take the stage down (a nav command moved the user elsewhere; a startup
  /// failure owns the void instead).
  void clearDisplay() => setDisplay(null, false);

  /// A short confirmation over the void that decays on its own ("Opened settings.").
  void showTransientCaption(String text) {
    _caption = text;
    _notify();
    _capTimer?.cancel();
    _capTimer = Timer(const Duration(milliseconds: 1600), () {
      if (_disposed) return;
      _caption = null;
      _notify();
    });
  }

  // ---- operation deliveries ---------------------------------------------------------------------
  /// Operation deliveries drained mid-turn used to be presented immediately —
  /// then the in-flight turn's completion overwrote the caption (and its speech),
  /// so the delivery vanished; a delivery arriving while listening started TTS
  /// against an open mic (see the barge-in barrier in [toggleMic]). Queue them
  /// instead and flush only when nothing else owns the stage.
  final List<OperationRecord> _pendingDeliveries = [];

  /// Deliveries restored at launch: nothing else owns the stage yet, so they
  /// are simply the opening caption (no speech).
  void showRestoredDeliveries(List<OperationRecord> restored) {
    _caption = restored.isEmpty ? null : operationDeliveryText(restored);
    _displayIsList = restored.isNotEmpty;
    _notify();
  }

  /// Queue newly-drained deliveries and present them if the stage is free.
  void enqueueDeliveries(List<OperationRecord> deliveries) {
    _pendingDeliveries.addAll(deliveries);
    maybeFlushDeliveries();
  }

  /// Present queued operation deliveries — but never mid-turn (the turn's
  /// completion would clobber them) and never while the mic is open (TTS over a
  /// hot mic). Re-invoked at turn completion and when a capture session ends.
  void maybeFlushDeliveries() {
    if (_disposed || _pendingDeliveries.isEmpty) return;
    if (_busy || _listening || _transcribing) return;
    final deliveries = List<OperationRecord>.of(_pendingDeliveries);
    _pendingDeliveries.clear();
    _presentOperationDeliveries(deliveries);
  }

  /// How many deliveries are waiting for the stage.
  @visibleForTesting
  int get pendingDeliveryCount => _pendingDeliveries.length;

  void _presentOperationDeliveries(List<OperationRecord> deliveries) {
    final text = operationDeliveryText(deliveries);
    _caption = text;
    _displayIsList = true;
    _speaking = true;
    _notify();
    _speakTimer?.cancel();
    _capTimer?.cancel();
    void finish() {
      if (_disposed) return;
      _speakTimer?.cancel();
      _speaking = false;
      _notify();
      _capTimer = Timer(const Duration(milliseconds: 1600), () {
        if (_disposed) return;
        _caption = null;
        _notify();
      });
    }

    if (!_voiceMuted && (voice?.available ?? false)) {
      voice!.speak(text, onDone: finish);
      final capMs = (3000 + text.length * 75).clamp(4000, 60000);
      _speakTimer = Timer(Duration(milliseconds: capMs), finish);
    } else {
      final ms = (1400 + text.length * 22).clamp(1600, 4200);
      _speakTimer = Timer(Duration(milliseconds: ms), finish);
    }
  }

  String operationDeliveryText(List<OperationRecord> deliveries) => deliveries
      .map(
        (operation) => switch (operation.state) {
          OperationState.succeeded =>
            '✨ ${operation.title} is ready\n${operation.result ?? ''}',
          OperationState.interrupted =>
            '⚠️ ${operation.title} was interrupted by the app closing. It was not retried or charged again.',
          _ =>
            '⚠️ ${operation.title} did not finish: ${operation.error ?? 'cancelled'}',
        },
      )
      .join('\n\n');

  // ---- the turn ---------------------------------------------------------------------------------
  /// Run one turn. With no [utterance] the input box is the source (and is
  /// cleared); an explicit [utterance] — voice finals, the routine player's
  /// control words — bypasses [input] entirely, so a muted user's half-typed
  /// draft is never clobbered and a bailed-out send leaves no ghost text.
  Future<void> send([String? utterance]) async {
    final fromInputBox = utterance == null;
    final t = (utterance ?? input.text).trim();
    if (t.isEmpty || _busy) return;
    if (fromInputBox) input.clear();
    // Correlation id: stamped on this turn's AppLog lines (and inherited from
    // the capture id when a voice final triggered the send) so recognizer
    // lines, AppLog, and the turnlog entry — whose own `at` key is minted by
    // Session.handle milliseconds later — line up from the log alone.
    final turnId = _captureId ?? DateTime.now().toIso8601String();
    _captureId = null;
    onTurnStarting(); // a new turn ends any in-flight colours demo, releasing the pinned presence
    if (navCommand(t)) {
      return; // "open settings" et al. open a window, not a turn
    }
    if (voice?.speaking ?? false) {
      unawaited(voice!.stop()); // a new turn stops any in-flight reply
    }
    _busy = true;
    _deepThink = false;
    _caption = null;
    _expression = PresenceExpression.neutral;
    _notify();
    // after a beat, a still-running turn reads as "reaching" (D2) — long/cloud work
    _thinkTimer?.cancel();
    _thinkTimer = Timer(const Duration(milliseconds: 700), () {
      if (_disposed) return;
      _deepThink = true;
      _notify();
    });
    log('turn [$turnId]: "$t"');
    final outcome = await runTurn(t);
    if (outcome == null || _disposed) {
      return; // widget torn down mid-turn -> don't notify after dispose
    }
    final resp = outcome.response;
    final usedCloud = outcome.usedCloud;
    log(
      'turn [$turnId] -> [${outcome.source}${usedCloud ? ', cloud' : ', offline'}] '
      '${resp.length > 140 ? '${resp.substring(0, 140)}…' : resp}',
    );
    // _busy is always cleared, so the input can never lock up.
    // automation deliveries (✨) + newly-held writes (📋) join the reply over the void
    final extras = outcome.extras;
    final shown = extras.isEmpty ? resp : '$resp\n\n${extras.join('\n')}';
    // Every reply is simultaneous text. Voice is a delivery channel, not the
    // only durable representation of what happened.
    final willSpeak = !_voiceMuted && (voice?.available ?? false);
    final display = shown;
    _busy = false;
    _deepThink = false;
    _speaking = true; // Plena "speaks" the reply — a brief presence flourish
    _lastCloud = usedCloud;
    _caption = display;
    // list-shaped (bullets / several lines) → Plena eases to a corner and it floats (§6.3)
    _displayIsList =
        display.contains('•') ||
        display.split('\n').where((l) => l.trim().isNotEmpty).length > 2;
    _expression = outcome.source == 'clarify'
        ? PresenceExpression.clarification
        : RegExp(
            r"\b(?:couldn't|failed|something went wrong|can't)\b",
            caseSensitive: false,
          ).hasMatch(resp)
        ? PresenceExpression.failure
        : PresenceExpression.neutral;
    _notify();
    _thinkTimer?.cancel();
    _speakTimer?.cancel();
    _capTimer?.cancel();
    // The routine cadence follows the RUN, not the input method. Arming it only from the card's
    // buttons meant a run started the flagship way — by voice — never auto-advanced at all, and a
    // spoken "pause"/"next" left a timer ticking against the step it had already left.
    syncRoutineCadence();
    // End of speaking: clear the flourish AND clear the caption a beat later. Called by the real
    // TTS onDone (or the safety cap), so the caption follows actual speech, not a fixed timer.
    void endSpeak() {
      if (_disposed) return;
      _speakTimer?.cancel();
      _speaking = false;
      _notify();
      _capTimer?.cancel();
      _capTimer = Timer(const Duration(milliseconds: 1600), () {
        if (_disposed) return;
        _caption = null;
        _notify();
      });
      // The turn (and its speech) is over — a delivery queued mid-turn gets the
      // stage now instead of having been silently overwritten.
      maybeFlushDeliveries();
    }

    if (willSpeak) {
      // Plena actually speaks; her "speaking" animation brackets the real audio (onDone ends it).
      // Pass the RAW reply — speak() segments it on blank lines (a silent beat between topics) and
      // speakifies each segment (track 2); the display keeps the original formatting.
      voice!.speak(
        resp,
        onStart: () {
          if (_disposed) return;
          _speaking = true;
          _notify();
        },
        onDone: endSpeak,
      );
      // safety cap only — generous (real speech at rate 0.5 can run ~30 s) so it never fires
      // before the audio actually ends and cuts her off mid-sentence.
      final capMs = (3000 + resp.length * 75).clamp(4000, 60000);
      _speakTimer = Timer(Duration(milliseconds: capMs), endSpeak);
    } else {
      // muted or no voice: a brief silent flourish, timed to the reply length
      final ms = (1400 + resp.length * 22).clamp(1600, 4200);
      _speakTimer = Timer(Duration(milliseconds: ms), endSpeak);
    }
    // apt-or-absent glyph, acknowledgement, and the tour's per-chapter gesture
    onTurnPresented(outcome);
  }

  // ---- the mic ----------------------------------------------------------------------------------
  /// Tap the void to START listening; tap again to STOP, flush the whole capture, and auto-send its
  /// one session final. The explicit ✕ is the discard path. Native finals remain segment boundaries,
  /// while native closure, errors, and watchdog stops converge on the recognizer's same idempotent
  /// flush door. onDone/catch always clear listening, so the surface cannot stay stuck recording.
  Future<void> toggleMic() async {
    if (!(speech?.available ?? false) || _busy) return;
    if (_listening) {
      // THE STOP TAP. The user — not the engine — decides the utterance is over: finalize and send
      // whatever was said. (This used to cancel; abort now lives on the ✕ control, because with
      // no auto-endpointing the common second tap is "I'm done", not "forget it".)
      logDebug('speech: tap -> stop and send');
      _hintTimer?.cancel();
      if (!_disposed) {
        _listening = false;
        _transcribing =
            true; // the presence goes to thinking; the stop tap is never a dead beat
        _micPrompt = null;
        _notify();
      }
      await speech!.stop();
      return;
    }
    // A fresh listen intent — captured so a rapid tap→abort→tap during the awaits below can't leave
    // this (now superseded) call starting a second concurrent recognizer session (Fable review #5).
    final epoch = ++_micEpoch;
    _aborting = false;
    _captureId = DateTime.now().toIso8601String();
    // Set listening BEFORE the barge-in await, so a second tap during it hits the abort branch
    // instead of starting a second recognizer session (reviewer d #2).
    _listening = true;
    _micLevel = 0;
    _heard = null; // a new utterance supersedes the last "I heard: …"
    _notify();
    _heardTimer?.cancel();
    // Mid-conversation the last reply stays until the first spoken word replaces it.
    if (voice?.speaking ?? false) {
      await voice!
          .stop(); // barge-in: cut Plena off the moment you start to speak (Spec 12 §7)
      if (!_disposed) {
        _speaking = false;
        _notify();
      }
      // HARD BARRIER (macOS): AVSpeechSynthesizer (TTS) and Apple Speech's AVAudioEngine (STT)
      // contend for the audio device. Starting capture immediately after TTS stops yields silent
      // input (error_no_match) or a native audio crash. Let the output device fully release first.
      await Future.delayed(const Duration(milliseconds: 300));
      // Bail if aborted OR superseded by a newer tap during the settle (stale epoch) — never start a
      // second concurrent recognizer session.
      if (_disposed || !_listening || epoch != _micEpoch) return;
    }
    logDebug('speech: tap -> start');
    // The learnable-affordance half of removing auto-endpointing: for the first few sessions the
    // status line says HOW to finish. After that it decays to plain "listening…" (quiet by default).
    if (!_disposed) {
      _micPrompt = _micHintsShown < _micHintSessions
          ? "tap anywhere when you're done"
          : null;
      _notify();
    }
    if (_micHintsShown < _micHintSessions) {
      _micHintsShown++;
      persistMicHints(_micHintsShown);
    }
    _autoStopped =
        false; // never carry a previous session's "(stopped on my own)" label forward
    var heard = false; // did this session get ANY audio it could transcribe?
    try {
      await speech!.listen(
        onNotice: (notice) {
          if (_disposed) return;
          switch (notice) {
            case SpeechNotice.longPause:
              // Exactly the moment the old system would have auto-sent — a habituated user is
              // waiting for a send that will never come. Re-show the hint, keep recording.
              _micPrompt = "tap when you're done";
              _notify();
            case SpeechNotice.autoCancelledNoSpeech:
              _listening = false;
              _micPrompt = null;
              _caption = "I stopped listening — I didn't hear anything.";
              _displayIsList = false;
              _notify();
            case SpeechNotice.autoStopped:
              // Stopped on its own after a very long pause, but SENT (never discard real speech).
              // Say so, or an unexplained send is a silent failure.
              _autoStopped = true;
              _micPrompt = null;
              _notify();
          }
        },
        onResult: (text, isFinal) {
          final t = text.trim();
          if (_disposed || t.isEmpty) return;
          heard = true;
          _noMatchStreak = 0;
          if (!isFinal) {
            // Live transcript: materialise words as they're recognized so you can SEE the mic is
            // hearing you (and watch it stall if it isn't). Windows delivers finals only, so this
            // only streams on Apple Speech.
            _caption = t;
            _displayIsList = false;
            _notify();
            return;
          }
          _listening = false;
          _transcribing = false;
          _micPrompt = null;
          // Confirm what was captured, in the listening font, until the reply settles. When a
          // watchdog ended the session rather than a tap, say that too (P2.8).
          _heard = _autoStopped
              ? '(stopped on my own after a long pause) $t'
              : t;
          _autoStopped = false;
          _notify();
          _heardTimer?.cancel();
          _heardTimer = Timer(const Duration(seconds: 5), () {
            if (_disposed) return;
            _heard = null;
            _notify();
          });
          speech!.cancel(); // one utterance per tap
          if (!_busy) {
            // sent directly — never through [input], which may hold a typed draft
            logDebug('speech: auto-send on final result');
            send(t);
          }
          // A step timer that elapsed mid-utterance deferred its advance; the
          // transcript's turn is in flight now, so the 'next' queues behind it.
          onCaptureResolved();
        },
        onDone: () {
          if (_disposed) return;
          _listening = false;
          _transcribing = false;
          _micPrompt = null;
          _notify();
          _captureId = null;
          // Capture over: release anything that was waiting on the mic. The
          // microtask lets a synchronously-nested onDone (cancel() inside the
          // final-result handler) finish sending the transcript first.
          scheduleMicrotask(() {
            if (_disposed) return;
            onCaptureResolved();
            maybeFlushDeliveries();
          });
          if (_aborting) {
            _aborting =
                false; // a deliberate tap-to-abort ended this session — not a no-audio miss
            return;
          }
          // No-silent-failure (principle #7): if tap-to-talk keeps hearing nothing, the mic is
          // almost certainly blocked (macOS revokes it when a debug rebuild re-signs the app) —
          // say so, actionably, instead of just doing nothing.
          if (!heard) {
            _noMatchStreak++;
            if (_noMatchStreak >= 2 && !_busy) {
              _displayIsList = false;
              _caption =
                  "I'm not hearing any audio. Check that Microphone and Speech "
                  'Recognition are ON for Plenara in System Settings → Privacy & '
                  'Security, then tap and talk again.';
              _notify();
            }
          }
        },
      );
    } catch (e) {
      logDebug('speech: listen failed: $e');
      if (!_disposed) {
        _listening = false;
        _notify();
      }
    }
  }

  /// Stop capturing and throw the audio away. Used by the ✕, by mute, and by backgrounding.
  /// THE ONLY path that discards speech — a stop tap and a watchdog stop both send.
  void cancelListening() {
    if (!_listening) return;
    logDebug('speech: cancel (discard)');
    _micEpoch++; // invalidate any in-flight listen-start awaiting the barge-in settle
    _aborting = true; // this cancel's onDone is deliberate, not a no-audio miss
    _hintTimer?.cancel();
    if (!_disposed) {
      _listening = false;
      _transcribing = false;
      _micPrompt = null;
      _notify();
    }
    speech?.cancel();
    _captureId = null;
    // The mic is closed: release a deferred step advance and any queued
    // operation deliveries that were waiting on it.
    onCaptureResolved();
    maybeFlushDeliveries();
  }

  /// Backgrounding is an abandonment signal: drop the capture and say why.
  void abandonForBackground(String message) {
    if (!_listening) return;
    cancelListening();
    _caption = message;
    _notify();
  }

  /// Mute silences her voice; captions still show. Muting also switches to text
  /// mode, so it cuts any live speech AND any hot mic.
  void toggleMute() {
    _voiceMuted = !_voiceMuted;
    _notify();
    // remember the choice between launches
    persistMute(_voiceMuted);
    if (_voiceMuted) {
      if (voice?.speaking ?? false) {
        voice!.stop();
        _speaking = false;
        _notify();
      }
      // muting = switch to text mode — don't leave a hot mic with no way to stop it, and no
      // stray transcript to overwrite/auto-send what the user is about to type (reviewer d #1)
      cancelListening();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    speech
        ?.cancel(); // never leave the recognizer recording after teardown (privacy)
    voice?.stop(); // don't keep talking after teardown
    _speakTimer?.cancel();
    _thinkTimer?.cancel();
    _capTimer?.cancel();
    _heardTimer?.cancel();
    _hintTimer?.cancel();
    input.dispose();
    super.dispose();
  }
}
