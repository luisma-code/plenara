// ---- the routine player (Spec 16) -----------------------------------------------------------
// The cadence is DEVICE-LOCAL and deterministic — no model, no cloud, so a run needs no network
// and you never have to LOOK at the phone. It is NOT, however, background-capable: this is a Dart
// timer plus foreground TTS, and the app declares no UIBackgroundModes, so
// locking an iPhone suspends it. Face-down-but-awake works; locked does not (Spec 16 §5).
// It lives outside the turn pipeline (the app speaks without a user turn, which the
// one-active-turn model doesn't cover) and is re-synced to the run after every turn.
//
// The screen owns the run and the turn; this owns only the CLOCK, through seams
// it is handed — so the arm/cancel/sync rules and the deferred advance can be
// reasoned about (and driven) without a widget tree.
import 'dart:async';

import 'package:plenara/routines.dart';

class RoutinePlayer {
  /// The live run, or null when none is active.
  final RoutineRun? Function() activeRun;

  /// False once the owning screen is gone — the old `mounted` check.
  final bool Function() alive;

  /// A turn is in flight (`_busy`).
  final bool Function() turnInFlight;

  /// The mic is open or its final transcript is still coming (`_listening ||
  /// _transcribing`) — the window in which an advance must defer.
  final bool Function() capturing;

  /// Run one turn with an explicit control word.
  final Future<void> Function(String word) sendControlWord;

  /// Say the bounded-wait refusal over the void (caption register, not a list).
  final void Function(String message) showCaption;

  /// Repaint the progress ring on each 1s tick.
  final void Function() onTick;

  RoutinePlayer({
    required this.activeRun,
    required this.alive,
    required this.turnInFlight,
    required this.capturing,
    required this.sendControlWord,
    required this.showCaption,
    required this.onTick,
  });

  Timer? _stepTimer;
  DateTime? _stepStartedAt;
  int? _stepSeconds;

  /// Which step the armed timer belongs to, so an unrelated turn mid-hold doesn't restart the
  /// clock and a stale tick can't advance a step the run has already left.
  String? _timedStepId;

  /// When the current step's clock started, and how long it holds — the two
  /// numbers the card's progress ring is drawn from. Null while nothing is armed.
  DateTime? get stepStartedAt => _stepStartedAt;
  int? get stepSeconds => _stepSeconds;

  /// Drive the player from the card's buttons (and the step timer). The control word goes straight
  /// to `_send` as an explicit utterance — never through `_ctrl`, which holds whatever the user may
  /// be typing in muted mode; a Stop tap must not clobber a draft or leave ghost text.
  Future<void> sendRoutine(String word) async {
    if (!alive() || activeRun() == null) return;
    cancelStepTimer();
    if (turnInFlight()) {
      // A turn is mid-flight. Wait for it rather than dropping a control the user physically
      // pressed — losing a Stop is worse than a beat of latency.
      await _turnSettled();
      if (!alive() || activeRun() == null) return;
      if (turnInFlight()) {
        // Still busy after the bounded wait: say so instead of silently
        // dropping the press (no-silent-failure).
        showCaption(
          "I'm still finishing the last thing — tap that again in a moment.",
        );
        return;
      }
    }
    await sendControlWord(word);
  }

  /// Wait (bounded) for the in-flight turn to finish.
  Future<void> _turnSettled() async {
    for (var i = 0; i < 100 && turnInFlight(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Arm or cancel the cadence to match the run's current state. Idempotent — safe to call after
  /// every turn.
  void syncStepTimer() {
    final run = activeRun();
    if (run == null || run.paused || run.currentSeconds == null) {
      cancelStepTimer();
      return;
    }
    // Already counting this same step? Leave it alone, or every unrelated turn mid-hold (the run is
    // sticky, so those happen) would silently restart the clock.
    if (_stepTimer != null && _timedStepId == run.current?['id']) return;
    _armStepTimer();
  }

  void cancelStepTimer() {
    _stepTimer?.cancel();
    _stepTimer = null;
    _stepStartedAt = null;
    _stepSeconds = null;
    _timedStepId = null;
  }

  /// Arm the auto-advance for a TIMED step. A rep-based step never auto-advances — it waits for
  /// "next", because only the user knows when the reps are done.
  void _armStepTimer() {
    cancelStepTimer();
    final run = activeRun();
    if (run == null || run.paused) return;
    final secs = run.currentSeconds;
    if (secs == null || secs <= 0) return;
    _stepStartedAt = DateTime.now();
    _stepSeconds = secs;
    _timedStepId = run.current?['id'] as String?;
    // A 1s tick drives the progress bar; the advance fires once at the end.
    _stepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final live = activeRun();
      // Stop counting if the run ended, was paused (by voice — the tick used to ignore that and
      // complete the paused step), or moved on to a different step.
      if (!alive() ||
          live == null ||
          live.paused ||
          live.current?['id'] != _timedStepId) {
        cancelStepTimer();
        return;
      }
      final elapsed = DateTime.now().difference(_stepStartedAt!).inSeconds;
      if (elapsed >= secs) {
        cancelStepTimer();
        if (capturing()) {
          // Mid-utterance: starting the 'next' turn now would set _busy, and the
          // arriving final transcript is dropped at `if (!_busy)` — the user's
          // speech would vanish. Defer the advance until the capture resolves.
          _advanceAfterCapture = true;
        } else {
          sendRoutine('next');
        }
      } else {
        onTick(); // repaint the ring
      }
    });
  }

  /// A timed step elapsed while the mic was open; advance now that the capture
  /// session has resolved. [sendRoutine] itself queues behind any in-flight turn
  /// (the transcript's), so the spoken words land before the step moves on.
  bool _advanceAfterCapture = false;
  void flushDeferredAdvance() {
    if (!_advanceAfterCapture) return;
    _advanceAfterCapture = false;
    unawaited(sendRoutine('next'));
  }

  /// Never leave a routine cadence ticking after teardown.
  void dispose() => cancelStepTimer();
}
