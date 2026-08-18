// Plenara — the presence-primary home. A thin front-end over the v0 engine
// (package:plenara/session.dart): the interpreter, router, store, and cloud
// client are the same code the console uses.
//
// This file owns the WIDGET TREE and the screen-level state around it (the
// presence pins, glyphs, the colour demo, the planner tab, startup recovery).
// The pieces with rules of their own live beside it:
//
//   bootstrap.dart             startup order + the production Session
//   voice_turn_controller.dart the voice/turn state machine (mic, TTS, caption,
//                              the delivery queue) — unit-tested on its own
//   routine_player.dart        the Spec 16 step cadence
//   reply_view.dart            the caption / list / prose reply registers
//   dev_harness.dart           INTERNAL-ONLY sheets, gated by isExternalBuild
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:plenara/config.dart';
import 'package:plenara/operation_center.dart';
import 'package:plenara/reminders.dart';
import 'package:plenara/session.dart';
import 'package:plenara/planner.dart';

import 'app_log.dart';
import 'attention_view.dart';
import 'bootstrap.dart';
import 'build_channel.dart';
import 'credential_store.dart';
import 'data_location.dart';
import 'data_view.dart';
import 'dev_harness.dart';
import 'glyphs.dart';
import 'glyph_policy.dart';
import 'library_home.dart';
import 'onboarding_view.dart';
import 'plan_view.dart';
import 'plena.dart';
import 'plenara_theme.dart';
import 'reply_view.dart';
import 'routine_player.dart';
import 'routine_view.dart';
import 'settings_view.dart';
import 'sherpa_speech.dart';
import 'speech.dart';
import 'speech_out.dart';
import 'today_view.dart';
import 'motion.dart';
import 'voice_turn_controller.dart';

/// The Dart entrypoint. Startup ORDER lives in `bootstrap.dart`
/// ([bootstrapAndRun]); this file owns the widget tree it runs.
Future<void> main() => bootstrapAndRun(const PlenaraApp());

class PlenaraApp extends StatelessWidget {
  const PlenaraApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Plenara v0',
    debugShowCheckedModeBanner: false,
    theme: PlenaraTheme.dark,
    home: const Home(),
  );
}

/// Chooses the first screen: a new user with no key set gets the [WelcomeScreen] (which invites,
/// but never blocks — offline works without a key); everyone else goes straight to chat. Tests
/// inject a Session, which always skips onboarding so the existing chat tests are unaffected.
class Home extends StatefulWidget {
  final Session? session;
  final bool retrieval;
  final String? configPath; // injectable for tests; null = the real user config
  const Home({super.key, this.session, this.retrieval = true, this.configPath});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late bool _onboarding =
      widget.session == null &&
      loadAppConfig(configPath: widget.configPath).apiKey == null;
  int _sessionGeneration = 0;

  void _restartAfterDataReset() {
    // Session regeneration invalidates every queued UNDO closure (each captures
    // the old Session); a stale snackbar must not fire into a disposed session.
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _sessionGeneration++);
  }

  @override
  Widget build(BuildContext context) => _onboarding
      ? WelcomeScreen(
          onContinue: () => setState(() => _onboarding = false),
          configPath: widget.configPath,
        )
      : ChatScreen(
          key: ValueKey('session-$_sessionGeneration'),
          session: widget.session,
          retrieval: widget.retrieval,
          configPath: widget.configPath,
          onDataReset: _restartAfterDataReset,
        );
}

class ChatScreen extends StatefulWidget {
  /// Tests inject a Session (temp data dir + replay/offline cloud). [retrieval]
  /// defaults ON in production through [Home]. The backend is in-process and
  /// offline; focused widget tests may still disable index construction.
  final Session? session;
  final bool retrieval;
  final SpeechRecognizer?
  speech; // voice input (task #18); Noop by default -> mic hidden
  final SpeechOutput?
  voice; // talk-back; tests inject a fake, injected session -> Noop
  /// Force the presence animation on/off regardless of [session]. Tests inject a session (→ animate
  /// OFF so pumpAndSettle terminates); the real-device integration test sets this true to exercise
  /// the real animated raster path. Null = default (animate iff no session injected).
  final bool? forceAnimate;

  /// Redirect the mute-pref read/write to a temp config file. Lets a test exercise mute PERSISTENCE
  /// (otherwise gated on `session == null` and thus dogfood-only). Null = the real `~/.plenara`.
  final String? configPath;
  final Future<void> Function(Session session)? initializeSession;
  final Future<DataResetResult> Function()? resetData;
  final VoidCallback? onDataReset;
  const ChatScreen({
    super.key,
    this.session,
    this.retrieval = false,
    this.speech,
    this.voice,
    this.forceAnimate,
    this.configPath,
    this.initializeSession,
    this.resetData,
    this.onDataReset,
  });
  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Backgrounding cancelled the routine cadence below; a live timed step
      // must resume counting when the app comes back, or the run silently
      // stalls forever on that step. syncStepTimer is idempotent and re-arms
      // (with a fresh clock) only when a timed, unpaused step is current.
      _player.syncStepTimer();
      return;
    }
    // Backgrounding is an abandonment signal. Never keep a hot mic while hidden (Spec 12 §3.5's
    // mic-lifecycle invariant), and never let a watchdog stop-and-SEND a turn — with TTS answering
    // — while the user is in another app.
    _turn.abandonForBackground(
      'I stopped listening when Plenara went to the background — tap and say it again.',
    );
    _player
        .cancelStepTimer(); // a routine cadence must not tick (or speak) while hidden
  }

  // Held so we can run a launch-time toast self-test (production only). `late` so an
  // injected test session never constructs the native plugin.
  // Real OS toasts per platform; anything else reconciles reminders in memory via FakeScheduler
  // (on-open nudges still work). Constructed lazily (only in the real app, never under a test).
  late final NotificationScheduler _scheduler = platformScheduler();
  late final Session _session =
      widget.session ?? buildSession(scheduler: _scheduler);

  /// The voice/turn state machine (voice_turn_controller.dart): mic epochs,
  /// listen/stop/cancel, TTS orchestration, the caption + speak timers, the
  /// delivery queue, and the busy/listening/transcribing/speaking rules that
  /// relate them. This screen supplies the engine, the log, and the surfaces.
  late final VoiceTurnController _turn = VoiceTurnController(
    runTurn: _runTurn,
    log: AppLog.instance.log,
    logDebug: AppLog.instance.debug,
    navCommand: _maybeNavCommand,
    onTurnStarting: _cancelColorDemo,
    onTurnPresented: _presentTurn,
    syncRoutineCadence: () => _player.syncStepTimer(),
    onCaptureResolved: () => _player.flushDeferredAdvance(),
    // Same guard the mute pref uses: only touch the real config for the real app (or a test that
    // injected a configPath). An injected session must never write the user's ~/.plenara.
    persistMicHints: (shown) {
      if (widget.session == null || widget.configPath != null) {
        saveConfig(micHintsShown: shown, configPath: widget.configPath);
      }
    },
    // Persist ONLY the pref — no dataDir, so a PLENARA_DATA env override isn't baked in.
    persistMute: (muted) {
      if (widget.session == null || widget.configPath != null) {
        saveConfig(voiceMuted: muted, configPath: widget.configPath);
      }
    },
  );
  StreamSubscription<OperationRecord>? _operationSub;
  StreamSubscription<void>? _storageSub;
  StreamSubscription<double>? _micLevelSub;
  bool _stillPresence = false;
  bool _ready = false;
  String? _startupError;
  String? _resetError;
  bool _resettingData = false;
  // The tour's "colours" chapter drives a scripted presence-colour demo (idle → listening → thinking
  // → the cooler AI shade) while Plena narrates it. Timers held so a new turn / teardown cancels it.
  final List<Timer> _colorDemoTimers = [];
  bool _colorDemoActive =
      false; // true while the demo owns the _forceState/_forceDifficulty pins
  int _plannerTab =
      0; // Today / Plan / Library, the three primary roots (Spec 17)
  // The glyph Plena should trace next, fired by bumping the nonce (Spec 15 §5A). apt-or-absent:
  // most turns fire none. The persistent rarity gate keeps the register scarce across relaunches.
  GlyphDef? _glyph;
  int _glyphNonce = 0, _glyphPreview = 0;
  int _acknowledgementNonce = 0;
  late final GlyphRarityGate _glyphGate = GlyphRarityGate(
    path: widget.configPath == null
        ? '${defaultDeviceDir()}/glyph-budget.json'
        : '${File(widget.configPath!).parent.path}/glyph-budget.json',
  );
  PresenceTuning _tuning =
      const PresenceTuning(); // live aesthetic controls (the tune sheet)
  // Dev harness overrides (the Dev harness sheet): pin the presence state / difficulty so you can
  // watch Plena in any mood without driving a real turn. Null = follow the live turn signals.
  PresenceState? _forceState;
  double? _forceDifficulty;
  bool _fireGlyph(GlyphDef? g, {bool force = false}) {
    if (g == null) return false;
    if (!force && !_glyphGate.admit(g.id)) return false;
    setState(() {
      _glyph = g;
      _glyphNonce++;
    });
    return true;
  }

  void _acknowledge() => setState(() => _acknowledgementNonce++);

  /// The tour's "colours" chapter: pin the presence through its palette while Plena narrates it, so
  /// the user SEES what each colour means (the deterministic tour never actually reaches the cloud, so
  /// the cooler AI shade would otherwise never show). Timings roughly track the spoken sentences; the
  /// pin releases at the end. Any new turn (or teardown) cancels it via [_cancelColorDemo].
  void _runColorDemo() {
    _cancelColorDemo();
    _colorDemoActive = true; // we now own the _forceState/_forceDifficulty pins
    // (delayMs, state, difficulty) — difficulty cools the hue (0 warm amber … ~4 pre-dawn blue).
    const beats = <(int, PresenceState, double)>[
      (0, PresenceState.idle, 0), // "warm amber is me at rest"
      (3800, PresenceState.listening, 0.6), // "I brighten … listening"
      (7000, PresenceState.thinking, 1.6), // "… working something out"
      (10500, PresenceState.thinking, 3.6), // "a cooler, bluer shade … the AI"
    ];
    for (final (ms, st, diff) in beats) {
      _colorDemoTimers.add(
        Timer(Duration(milliseconds: ms), () {
          if (!mounted) return;
          setState(() {
            _forceState = st;
            _forceDifficulty = diff;
          });
        }),
      );
    }
    _colorDemoTimers.add(
      Timer(const Duration(milliseconds: 14500), _cancelColorDemo),
    );
  }

  /// Stop the colour demo and release the presence back to the live signals — but ONLY the pins the
  /// demo itself set. Guarding on [_colorDemoActive] means a plain turn no longer clobbers a Dev-harness
  /// pin the user set by hand (both use _forceState/_forceDifficulty).
  void _cancelColorDemo() {
    final wasActive = _colorDemoActive;
    _colorDemoActive = false;
    if (_colorDemoTimers.isEmpty && !wasActive) return;
    for (final t in _colorDemoTimers) {
      t.cancel();
    }
    _colorDemoTimers.clear();
    if (wasActive && mounted) {
      setState(() {
        _forceState = null;
        _forceDifficulty = null;
      });
    }
  }

  // The dev-harness pins win over the live turn/speech signals the controller derives.
  PresenceState get _presence => _forceState ?? _turn.presence;
  double get _difficulty => _forceDifficulty ?? _turn.difficulty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The controller is the source of truth for the turn/voice state; the
    // screen just repaints whenever it moves.
    _turn.addListener(_turnChanged);
    _init();
  }

  Future<void> _init() async {
    final log = AppLog.instance;
    try {
      log('init: begin (retrieval=${widget.retrieval})');
      if (widget.initializeSession != null) {
        await widget.initializeSession!(_session);
      } else {
        await _session.init(
          retrieval: widget.retrieval,
          watchStorage: widget.session == null,
          onPhase: log.log,
        );
      }
      _operationSub = _session.operations.changes.listen(_operationChanged);
      _storageSub = _session.storageChanges.listen((_) {
        if (mounted) setState(() {});
      });
      final restoredOperations = _session.operations.takeDeliveries();
      _turn.speech =
          await _pickSpeech(); // on-device sherpa if the model's present, else OS SAPI
      _micLevelSub = _turn.speech?.levels.listen(_turn.setMicLevel);
      // Talk-back: on-device TTS in production; a fake in tests; Noop under an injected session.
      _turn.voice =
          widget.voice ??
          (widget.session == null
              ? FlutterTtsSpeechOutput(onLog: (m) => log.debug('tts: $m'))
              : NoopSpeechOutput());
      await _turn.voice!.init();
      // Remembered mute pref (real app, or a test that injects a configPath). No first-run
      // audio-blast risk: the greeting is never spoken, so muted just defaults to false.
      if (widget.session == null || widget.configPath != null) {
        final cfg = loadConfig(configPath: widget.configPath);
        _turn.restorePreferences(
          voiceMuted: cfg.voiceMuted ?? false,
          // the stop-gesture hint decays ACROSS launches
          micHints: cfg.micHintsShown,
        );
        _stillPresence = cfg.stillPresence;
        _session.confirmCloudSpend = cfg.confirmCloudSpend;
      }
      log(
        'init: ready (stt=${_turn.speech?.available ?? false}, tts=${_turn.voice?.available ?? false})',
      );
      if (!mounted) return; // torn down during init -> don't setState
      // Opt-in diagnostic: set PLENARA_SELFTEST=1 to fire an immediate "notifications are
      // on" toast at launch (proven working; off by default so normal launches are quiet).
      // Guard on session==null FIRST so a test (injected session) never touches _scheduler —
      // constructing the native scheduler under flutter_tester would throw. selfTest() is on the
      // seam now, so it fires on whichever backend this platform picked (Windows/macOS/Fake).
      if (widget.session == null &&
          Platform.environment['PLENARA_SELFTEST'] == '1') {
        // ignore: discarded_futures
        _scheduler.selfTest();
      }
      final nudges = _session.pendingNudges();
      _turn.showRestoredDeliveries(restoredOperations);
      setState(() => _ready = true);
      // A birthday today earns the candle; otherwise Plena acknowledges arrival.
      _fireGlyph(
        nudges.any((n) => n.toLowerCase().contains('birthday'))
            ? kGlyphs['candle']
            : kGlyphs['smile'],
        force: true,
      );
    } catch (e, st) {
      log('init: FAILED: $e\n$st');
      if (!mounted) {
        return; // torn down during a failing init -> don't setState after dispose
      }
      // no infinite spinner: surface the failure over the void
      _turn.clearDisplay();
      setState(() {
        _ready = true;
        _startupError = '$e';
      });
    }
  }

  void _turnChanged() {
    if (mounted) setState(() {});
  }

  void _operationChanged(OperationRecord operation) {
    if (!mounted) return;
    if (!operation.terminal) {
      setState(() {});
      return;
    }
    _turn.enqueueDeliveries(_session.operations.takeDeliveries());
  }

  /// Pick the best available recognizer for the platform.
  ///
  /// **Apple (macOS/iOS): the built-in Speech framework, always.** Apple's on-device recognizer is
  /// the same engine as system dictation — accurate, naturally-cased, private, zero-download — so
  /// there's no reason to ship a Whisper model here (sherpa/onnxruntime was a *Windows* workaround
  /// for inaccurate SAPI). **Windows:** on-device sherpa_onnx Whisper if its model is downloaded,
  /// else the built-in engine. Then Noop (mic hidden) as the floor.
  /// A test-injected recognizer always wins; an injected session means "test" -> Noop.
  Future<SpeechRecognizer> _pickSpeech() async {
    final log = AppLog.instance;
    if (widget.speech != null) {
      await widget.speech!.init();
      return widget.speech!;
    }
    if (widget.session != null) return NoopSpeechRecognizer();
    SpeechRecognizer sys() {
      // The capture correlation id (when a session is live) joins these lines to
      // the AppLog `turn` lines and, approximately, the turnlog entry.
      final s = SystemSpeechRecognizer(
        onLog: (m) => log.debug(
          'speech${_turn.captureId == null ? '' : ' [${_turn.captureId}]'}: $m',
        ),
      );
      return s;
    }

    // Apple platforms: go straight to the built-in recognizer (skip the Whisper probe entirely).
    if (Platform.isMacOS || Platform.isIOS) {
      log('speech: using the built-in Apple Speech recognizer');
      final s = sys();
      await s.init();
      return s;
    }
    // Windows (and any other): prefer on-device sherpa_onnx Whisper if its model is present.
    final modelDir =
        '${modelsDir()}/en-whisper'; // config.dart owns the ~/.plenara path layout
    final sherpa = SherpaSpeechRecognizer(
      modelDir,
      onLog: (m) => log.debug('sherpa: $m'),
    );
    await sherpa.init();
    if (sherpa.available) {
      log('speech: using on-device sherpa_onnx');
      return sherpa;
    }
    log.debug(
      'speech: sherpa model unavailable -> falling back to the built-in OS engine',
    );
    final s = sys();
    await s.init();
    return s;
  }

  /// App-layer navigation commands ("open settings") — handled by the UI, not the engine, so they
  /// open the corresponding window instead of being routed (and mis-answered) as a turn. Covers
  /// both typed and voice input, since voice auto-sends through [_send].
  bool _maybeNavCommand(String t) {
    final s = t.toLowerCase().trim().replaceAll(RegExp(r'[.!?]+$'), '');
    final plannerDestination = switch (s) {
      'today' || 'open today' || 'show today' || 'go to today' => 0,
      'plan' || 'open plan' || 'show plan' || 'go to plan' => 1,
      'library' || 'open library' || 'show library' || 'go to library' => 2,
      _ => null,
    };
    if (plannerDestination != null) {
      _turn.clearDisplay();
      setState(() => _plannerTab = plannerDestination);
      return true;
    }
    if (RegExp(
      r'^(?:(?:open|show|go to|take me to|open up)\s+)?(?:the\s+)?settings$',
    ).hasMatch(s)) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => _settingsView()));
      _turn.showTransientCaption('Opened settings.');
      return true;
    }
    return false;
  }

  SettingsView _settingsView() => SettingsView(
    configPath: widget.configPath,
    resetData: widget.resetData,
    onDataReset: () {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      widget.onDataReset?.call();
    },
    onStillPresenceChanged: (value) {
      if (mounted) setState(() => _stillPresence = value);
    },
  );

  Future<void> _resetAfterStartupFailure() async {
    setState(() {
      _resettingData = true;
      _resetError = null;
    });
    try {
      final result =
          await (widget.resetData ??
              () => resetDataToDeviceLocal(configPath: widget.configPath))();
      AppLog.instance.log(
        'recovery: reset to ${result.dataDir}; backup=${result.backupDir ?? 'none'}',
      );
      if (!mounted) return;
      setState(() => _resettingData = false);
      if (widget.onDataReset != null) {
        widget.onDataReset!.call();
      } else {
        setState(() {
          _resetError =
              'Fresh local data is ready. Reopen Plenara to continue.';
        });
      }
    } catch (error, stack) {
      AppLog.instance.log('recovery: reset FAILED: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _resettingData = false;
        _resetError = 'Reset failed: $error';
      });
    }
  }

  Widget _startupRecovery(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      key: const Key('startup-recovery'),
      children: [
        const Positioned.fill(
          child: PresenceView(
            state: PresenceState.idle,
            animate: false,
            expression: PresenceExpression.failure,
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Card(
                          color: const Color(0xEE15120F),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "I couldn't open your data",
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Start fresh uses a new device-local folder. A selected iCloud, OneDrive, or Google Drive folder is disconnected but never deleted; old local bytes are retained as a backup.',
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _startupError ?? 'Unknown startup error',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.outline,
                                  ),
                                ),
                                if (_resetError != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    _resetError!,
                                    style: TextStyle(
                                      color:
                                          _resetError!.startsWith(
                                            'Reset failed',
                                          )
                                          ? cs.error
                                          : cs.primary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('startup-reset-data'),
                      onPressed: _resettingData
                          ? null
                          : _resetAfterStartupFailure,
                      icon: _resettingData
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.restart_alt),
                      label: const Text('Reset and start fresh'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Run one turn through the engine for [VoiceTurnController], and report
  /// what it left behind. Returns null when the screen was torn down mid-turn —
  /// nothing is drained and nothing is presented in that case.
  Future<TurnOutcome?> _runTurn(String t) async {
    final log = AppLog.instance;
    final reviewsBefore = _session.automations.pendingReview.length;
    String resp;
    try {
      resp = await _session.handle(
        t,
      ); // already catch-all internally; belt-and-suspenders here
    } catch (e, st) {
      log('turn FAILED: $e\n$st');
      resp = 'Something went wrong: $e';
    }
    if (!mounted) {
      return null; // widget torn down mid-turn -> don't setState after dispose
    }
    // Surface any automation deliveries this turn produced (Spec 02 §7.5 read-only "deliver"),
    // draining them so they don't re-appear as on-open nudges next launch; and prompt on a NEW
    // held write so the user can approve/dismiss it (§7.5 "hold for review").
    final deliveries = _session.automations.takeDeliveries();
    final review = _session.automations.pendingReview;
    final newReviews = review.length > reviewsBefore
        ? review.sublist(reviewsBefore)
        : const [];
    return TurnOutcome(
      response: resp,
      // automation deliveries (✨) + newly-held writes (📋) join the reply over the void
      extras: <String>[
        for (final d in deliveries) '✨ ${d.text}',
        for (final p in newReviews)
          '📋 ${p.description} — say "approve it" or "dismiss it".',
      ],
      usedCloud: _session.lastTurnUsedCloud,
      source: _session.lastSource,
      skill: _session.lastSkill,
      tourChapter: _session.lastTourChapter,
    );
  }

  /// The presence flourishes a completed turn earns: an apt-or-absent glyph, an
  /// acknowledgement when no glyph fired, and the tour's per-chapter gesture.
  void _presentTurn(TurnOutcome outcome) {
    // apt-or-absent: an occasion-appropriate glyph, or nothing (most turns)
    final marked = _fireGlyph(glyphForTurn(outcome.skill, outcome.response));
    if (!marked && outcome.skill != null && outcome.source != 'clarify') {
      _acknowledge();
    }
    // Tour: each chapter opens with an apt gesture (force past the debounce), and the "colours"
    // capstone drives a live palette demo while Plena describes it.
    final chapter = outcome.tourChapter;
    if (chapter != null) {
      const chapterGlyph = {
        'reminders': 'bell',
        'tasks': 'check',
        'people': 'heart',
        'tracking': 'flower',
        'colors': 'sun',
      };
      _fireGlyph(kGlyphs[chapterGlyph[chapter] ?? 'spark'], force: true);
      if (chapter == 'colors') _runColorDemo();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Stops the recognizer (privacy), stops any live speech, and kills the
    // caption/speak/think/heard timers and the input controller.
    _turn.removeListener(_turnChanged);
    _turn.dispose();
    _operationSub?.cancel();
    _storageSub?.cancel();
    if (widget.session == null) unawaited(_session.dispose());
    _micLevelSub?.cancel();
    _player.dispose(); // never leave a routine cadence ticking after teardown
    for (final t in _colorDemoTimers) {
      t.cancel();
    }
    super.dispose();
  }

  /// How the INTERNAL-ONLY dev sheets (dev_harness.dart) reach this screen's
  /// state. Only ever built inside a `!isExternalBuild` branch, so an external
  /// AOT build drops this getter, the sheets, and their strings entirely.
  DevHarnessBinding get _devHarnessBinding => DevHarnessBinding(
    applyToScreen: setState,
    readTuning: () => _tuning,
    writeTuning: (value) => _tuning = value,
    readForceState: () => _forceState,
    writeForceState: (value) => _forceState = value,
    readForceDifficulty: () => _forceDifficulty,
    writeForceDifficulty: (value) => _forceDifficulty = value,
    readCaption: () => _turn.caption,
    readDisplayIsList: () => _turn.displayIsList,
    writeDisplay: _turn.setDisplay,
    readVoice: () => _turn.voice,
    fireGlyph: (glyph) => _fireGlyph(glyph, force: true),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0A0908),
    body: !_ready
        ? const Stack(
            children: [
              Positioned.fill(
                child: PresenceView(
                  state: PresenceState.thinking,
                  animate: false,
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 28),
                    child: Text(
                      'Waking up…',
                      style: TextStyle(color: Color(0x99EAE2D8)),
                    ),
                  ),
                ),
              ),
            ],
          )
        : _startupError != null
        ? _startupRecovery(context)
        // A live routine run takes the screen (a Y1 guest surface, Spec 16): Plena stays alive in
        // her corner within _presenceHome, and the step hovers over the void.
        : _routineStep() != null
        ? Stack(children: [_presenceHome(context), _routineOverlay(context)])
        : _presenceHome(context),
  );

  // ---- the routine player (Spec 16) -----------------------------------------------------------
  // The cadence itself lives in routine_player.dart; this screen supplies the
  // run, the turn/capture state it must respect, and the surfaces it drives.
  late final RoutinePlayer _player = RoutinePlayer(
    activeRun: () => _session.activeRun,
    alive: () => mounted,
    turnInFlight: () => _turn.busy,
    capturing: () => _turn.listening || _turn.transcribing,
    sendControlWord: _turn.send,
    showCaption: (message) => _turn.setDisplay(message, false),
    onTick: () => setState(() {}),
  );

  RoutineStepView? _routineStep() {
    final run = _session.activeRun;
    final step = run?.current;
    if (run == null || step == null) return null;
    final key = step['exerciseKey'] as String?;
    final img = key == null ? null : _session.exercises.byKey[key]?.image;
    return RoutineStepView(
      routineTitle: run.title,
      name: '${step['name']}',
      instruction: '${step['instruction'] ?? ''}',
      position: run.position,
      total: run.total,
      side: '${step['side'] ?? 'both'}',
      durationSeconds: num.tryParse(
        '${step['durationSeconds'] ?? ''}',
      )?.toInt(),
      reps: num.tryParse('${step['reps'] ?? ''}')?.toInt(),
      imageAsset: img == null ? null : 'assets/exercises/$img',
      // Fallback tier: only consulted when the catalogue had no illustration for this movement.
      figureSvg: img == null ? step['figureA'] as String? : null,
      figureSvgB: img == null ? step['figureB'] as String? : null,
    );
  }

  Widget _routineOverlay(BuildContext context) {
    final step = _routineStep()!;
    final started = _player.stepStartedAt;
    final secs = _player.stepSeconds;
    final progress = (started == null || secs == null || secs <= 0)
        ? null
        : DateTime.now().difference(started).inMilliseconds / (secs * 1000);
    return RoutineStepCard(
      step: step,
      progress: progress,
      onNext: () => _player.sendRoutine('next'),
      onStop: () => _player.sendRoutine('stop'),
    );
  }

  // ---- the presence-primary home (Spec 15): only Plena + the current exchange over the void ----
  Widget _presenceHome(BuildContext context) {
    final hasStt = _turn.speech?.available ?? false;
    final showInput =
        _turn.voiceMuted ||
        !hasStt; // keyboard path when muted, or when there's no mic
    final caption = _turn.caption;
    final hasContent = caption != null && caption.trim().isNotEmpty;
    final listMode =
        hasContent && _turn.displayIsList; // a list eases Plena to a corner
    final showPlanner =
        !hasContent &&
        !_turn.listening &&
        !_turn.busy &&
        !_turn.transcribing &&
        _session.activeRun == null;
    final systemReducedMotion = MediaQuery.disableAnimationsOf(context);
    final crossfadeStaticPresence = _stillPresence || systemReducedMotion;
    final animatePresence =
        (widget.forceAnimate ?? (widget.session == null)) &&
        !_stillPresence &&
        !systemReducedMotion;
    final presenceMode = _turn.voiceMuted
        ? 'muted, text mode'
        : hasStt
        ? 'voice mode'
        : 'text mode, microphone unavailable';

    return Stack(
      children: [
        // Tap anywhere to talk (behind everything). Not while muted (text mode) or busy.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: (hasStt && !_turn.voiceMuted && !_turn.busy)
                ? _turn.toggleMic
                : null,
            onLongPress:
                !isExternalBuild && activeBuildChannel.allowsInternalTools
                ? () {
                    final all = kGlyphs.values.toList();
                    _fireGlyph(all[_glyphPreview++ % all.length], force: true);
                  }
                : null,
          ),
        ),
        // Plena — always full-bleed. (She used to shrink to a 260px corner box in list mode, but
        // resizing the widget reallocated her comet-trail offscreen buffer mid-animation and crashed
        // the native raster on every list reply. Fable's redesign moves the *entity* to the corner
        // within a full-bleed canvas via veilYield; until then she just stays full-screen — no crash.)
        Positioned.fill(
          child: IgnorePointer(
            child: Semantics(
              container: true,
              label:
                  'Plena — ${_presence.name}, $presenceMode, ${_turn.expression.name}${hasContent ? '. $caption' : ''}',
              child: AnimatedSwitcher(
                duration: PlenaraMotion.standard,
                switchInCurve: PlenaraMotion.enter,
                switchOutCurve: PlenaraMotion.leave,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: PresenceView(
                  key: crossfadeStaticPresence
                      ? ValueKey(
                          'still-${_presence.name}-${_turn.expression.name}',
                        )
                      : const ValueKey('continuous-presence'),
                  state: _presence,
                  difficulty: _difficulty,
                  animate: animatePresence,
                  expression: _turn.expression,
                  listeningLevel: _turn.micLevel,
                  acknowledgementNonce: _acknowledgementNonce,
                  glyph: _glyph,
                  glyphNonce: _glyphNonce,
                  tuning: _tuning,
                  // A list/prose reply eases her to the upper-right corner (within the full-bleed
                  // canvas) so the text reads beside her; a short caption keeps her centered.
                  yieldTarget: (listMode || showPlanner) ? 1 : 0,
                ),
              ),
            ),
          ),
        ),
        if (showPlanner)
          Positioned.fill(
            child: switch (_plannerTab) {
              1 => PlanBoard(
                session: _session,
                onChanged: () => setState(() {}),
                onVoice: (hasStt && !_turn.voiceMuted && !_turn.busy)
                    ? _turn.toggleMic
                    : null,
              ),
              2 => LibraryHome(
                session: _session,
                onVoice: (hasStt && !_turn.voiceMuted && !_turn.busy)
                    ? _turn.toggleMic
                    : null,
                onOpen: (title, typeIds) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DataView(
                      session: _session,
                      title: title,
                      typeIds: typeIds,
                    ),
                  ),
                ),
              ),
              _ => TodayBoard(
                session: _session,
                onChanged: () => setState(() {}),
                onVoice: (hasStt && !_turn.voiceMuted && !_turn.busy)
                    ? _turn.toggleMic
                    : null,
                onOpenLibrary: () => setState(() => _plannerTab = 2),
                onOpenAttention: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AttentionView(
                      session: _session,
                      onChanged: () {
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ),
              ),
            },
          ),
        if (showPlanner)
          Positioned(
            left: 12,
            right: 12,
            bottom: 6,
            child: SafeArea(
              top: false,
              child: NavigationBar(
                key: const Key('planner-navigation'),
                selectedIndex: _plannerTab,
                height: 68,
                backgroundColor: const Color(0xEE15120F),
                indicatorColor: const Color(0x33E9A58B),
                onDestinationSelected: (index) => setState(() {
                  _plannerTab = index;
                  if (index == 2) {
                    _session.setPlannerContext(const PlannerContext());
                  }
                }),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.today_outlined),
                    selectedIcon: Icon(Icons.today_rounded),
                    label: 'Today',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_view_week_outlined),
                    selectedIcon: Icon(Icons.calendar_view_week_rounded),
                    label: 'Plan',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: 'Library',
                  ),
                ],
              ),
            ),
          ),
        // The current exchange, materialising over the void. Keep this
        // transition mounted so clarification and failure text visibly arrives
        // and resolves instead of teleporting with an `if` branch.
        // Short captions stay fully tap-through (the void behind is the voice
        // target). A list/prose reply is a SingleChildScrollView that can be
        // taller than the viewport, so it must receive drags — plain taps still
        // fall through to the translucent voice-tap layer behind it, and taps
        // outside the reply column are unaffected.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !listMode,
            child: AnimatedSwitcher(
              duration: PlenaraMotion.deliberate,
              switchInCurve: PlenaraMotion.enter,
              switchOutCurve: PlenaraMotion.leave,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: hasContent
                  ? KeyedSubtree(
                      key: ValueKey(
                        'caption-${_turn.expression.name}-$caption',
                      ),
                      child: voidText(
                        caption,
                        list: listMode,
                        tuning: _tuning,
                        bottomInset: showInput ? 168 : 0,
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('caption-empty')),
            ),
          ),
        ),
        // The status line, in the italic "listening" font: "listening…" until your words appear
        // (then the live caption takes over, no overlap); once input ends, "I heard: <what you
        // said>" as a confirmation, until the reply settles.
        if ((_turn.listening && !hasContent) || _turn.heard != null)
          Positioned(
            bottom: 150,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    // While listening: "listening…", or the decaying/just-in-time affordance line
                    // that teaches the stop gesture. The presence already says THAT it's listening;
                    // only "how do I finish?" needs words.
                    _turn.heard != null
                        ? 'I heard: ${_turn.heard}'
                        : (_turn.micPrompt == null
                              ? 'listening…'
                              : 'listening — ${_turn.micPrompt}'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0x99EAE2D8),
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
          ),
        // ABORT, only while listening. The second tap now means "done, send it", so discarding needs
        // its own control — the mirror of the mute button, and deliberately a small corner target:
        // with numbered corrections and "undo that", a wrong SEND is cheap, so abort is the rare path.
        if (_turn.listening)
          Positioned(
            right: 14,
            bottom: 14 + MediaQuery.of(context).padding.bottom,
            child: _cancelListenButton(),
          ),
        // Muted / no-mic → the two-line input box rises from the bottom
        AnimatedPositioned(
          duration: PlenaraMotion.standard,
          curve: PlenaraMotion.enter,
          left: 0,
          right: 0,
          bottom: showInput ? (showPlanner ? 78 : 0) : -180,
          child: _inputBar(context),
        ),
        // Offset the corner controls by the safe-area insets: at top:6 the menu button sat UNDER the
        // status bar / Dynamic Island, where iOS eats the touch (that's why "…" didn't react); the
        // mute button likewise clears the home indicator.
        Positioned(
          left: 14,
          bottom:
              (showPlanner ? 84 : 14) + MediaQuery.of(context).padding.bottom,
          child: _muteButton(),
        ),
        Positioned(
          right: 6,
          top: 6 + MediaQuery.of(context).padding.top,
          child: _menuButton(context),
        ),
      ],
    );
  }

  Widget _inputBar(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      // Left inset clears the mute button (Positioned left:14, ~48px wide) which is drawn on top of
      // this bar — otherwise it obscures the first characters typed.
      padding: const EdgeInsets.fromLTRB(70, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xF0100E0C),
        border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _turn.input,
              minLines: 1,
              maxLines: 2,
              style: const TextStyle(color: voidInk),
              onSubmitted: (_) => _turn.send(),
              decoration: InputDecoration(
                hintText: 'Type to Plena…',
                hintStyle: const TextStyle(color: Color(0x66EAE2D8)),
                filled: true,
                fillColor: const Color(0x14FFFFFF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _turn.busy ? null : _turn.send,
            child: const Text('Send'),
          ),
        ],
      ),
    ),
  );

  /// Discard the live capture without sending (the abort path the second tap used to be).
  Widget _cancelListenButton() => Material(
    color: Colors.transparent,
    child: IconButton(
      key: const Key('cancel-listen'),
      icon: const Icon(Icons.close, color: Color(0x88FFFFFF)),
      tooltip: 'Cancel without sending',
      onPressed: _turn.cancelListening,
    ),
  );

  Widget _muteButton() => Material(
    color: Colors.transparent,
    child: IconButton(
      icon: Icon(
        _turn.voiceMuted ? Icons.volume_off : Icons.volume_up,
        color: const Color(0x88FFFFFF),
      ),
      tooltip: _turn.voiceMuted
          ? 'Plena is muted — tap to unmute'
          : "Mute Plena's voice",
      onPressed: _turn.toggleMute,
    ),
  );

  Widget _menuButton(BuildContext context) => Theme(
    data: Theme.of(
      context,
    ).copyWith(iconTheme: const IconThemeData(color: Color(0x66FFFFFF))),
    child: PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz),
      onSelected: (v) {
        if (v == 'data') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DataView(session: _session)),
          );
        } else if (v == 'settings') {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => _settingsView()));
        } else if (!isExternalBuild && v == 'tune') {
          openTuningSheet(context, _devHarnessBinding);
        } else if (!isExternalBuild && v == 'harness') {
          openDevHarnessSheet(context, _devHarnessBinding);
        }
      },
      itemBuilder: (_) => isExternalBuild
          ? const [
              PopupMenuItem(value: 'data', child: Text('All data')),
              PopupMenuItem(value: 'settings', child: Text('Settings')),
            ]
          : [
              for (final action in menuActionsFor(activeBuildChannel))
                PopupMenuItem(
                  value: action,
                  child: Text(switch (action) {
                    'harness' => 'Dev harness',
                    'tune' => 'Tune Plena',
                    'data' => 'All data',
                    _ => 'Settings',
                  }),
                ),
            ],
    ),
  );
}
