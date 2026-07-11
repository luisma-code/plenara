// Plenara v0 — Flutter desktop chat UI. A thin front-end over the v0 engine
// (package:plenara/session.dart): the interpreter, router, store, and cloud
// client are the same code the console uses. Text-first for now; voice later.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';
import 'package:plenara/reminders.dart';
import 'package:plenara/session.dart';

import 'app_log.dart';
import 'data_view.dart';
import 'glyphs.dart';
import 'onboarding_view.dart';
import 'plena.dart';
import 'settings_view.dart';
import 'sherpa_speech.dart';
import 'speech.dart';
import 'windows_scheduler.dart';

// Where the SHIPPED built-in capability defs are copied FROM on first run.
const sourceDataDir = r'Z:\code\plenara\v0\data';

/// Build the production Session from user config: the real (synced) data folder,
/// seeded with the built-in capabilities on first run, the BYOK key, and the real
/// Windows toast scheduler (reminders now fire as OS notifications, not just on-open
/// nudges). The scheduler self-inits lazily on first schedule/cancel.
Session buildSession({NotificationScheduler? scheduler}) {
  final cfg = loadConfig();
  ensureSeeded(cfg.dataDir, sourceDataDir);
  // Free mode runs offline-only: hand the Session an EXPLICIT offline client (empty key ->
  // every cloud call returns noKey, zero Anthropic spend). Passing null would NOT work — the
  // Session falls back to a default ClaudeClient() that picks the key up from the environment,
  // so free mode has to inject a deliberately-keyless client. (A real release ships two binaries.)
  final useCloud = cfg.apiKey != null && !cfg.freeTier;
  return Session(
    cfg.dataDir,
    cloud: useCloud
        ? ClaudeClient(apiKeyOverride: cfg.apiKey)
        : ClaudeClient(apiKeyOverride: ''),
    scheduler: scheduler,
    deviceDir:
        defaultDeviceDir(), // deviceId + turnlog stay device-local, off the synced folder
  );
}

void main() {
  final log = AppLog.instance;
  // Print the diagnostics log path so a manual test that goes wrong is one file away.
  stdout.writeln('Plenara diagnostics log: ${log.file.path}');
  log('boot: main() starting');
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      log('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
      FlutterError.presentError(details);
    };
    runApp(const PlenaraApp());
  }, (error, stack) => log('UNCAUGHT: $error\n$stack'));
}

class PlenaraApp extends StatelessWidget {
  const PlenaraApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Plenara v0',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
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
  const Home({
    super.key,
    this.session,
    this.retrieval = false,
    this.configPath,
  });
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late bool _onboarding =
      widget.session == null &&
      loadConfig(configPath: widget.configPath).apiKey == null;
  @override
  Widget build(BuildContext context) => _onboarding
      ? WelcomeScreen(
          onContinue: () => setState(() => _onboarding = false),
          configPath: widget.configPath,
        )
      : ChatScreen(session: widget.session, retrieval: widget.retrieval);
}

class Msg {
  final String text;
  final bool user;
  final bool
  cloud; // this assistant reply consulted the cloud (spent tokens) -> show a green dot
  Msg(this.text, this.user, {this.cloud = false});
}

class ChatScreen extends StatefulWidget {
  /// Tests inject a Session (temp data dir + replay/offline cloud). [retrieval]
  /// defaults OFF — the embed server isn't part of the dogfood setup, and building
  /// the index against a DOWN server costs ~2s per anchor (a minute-long startup
  /// hang). Enable it only alongside a running embed server.
  final Session? session;
  final bool retrieval;
  final SpeechRecognizer?
  speech; // voice input (task #18); Noop by default -> mic hidden
  const ChatScreen({
    super.key,
    this.session,
    this.retrieval = false,
    this.speech,
  });
  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  // Held so we can run a launch-time toast self-test (production only). `late` so an
  // injected test session never constructs the native plugin.
  late final WindowsToastScheduler _scheduler = WindowsToastScheduler();
  late final Session _session =
      widget.session ?? buildSession(scheduler: _scheduler);
  // Chosen in _init(): on-device sherpa_onnx if its model is present, else the OS SAPI engine,
  // else Noop. Tests inject their own. Null until _init picks one; the mic hides while null.
  SpeechRecognizer? _speech;
  final _msgs = <Msg>[];
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _ready = false, _busy = false, _listening = false;
  // Plena's presence state (Spec 15): derived from the real turn/speech signals. No TTS yet,
  // so "speaking" is a brief flourish while a reply lands; _lastCloud tints it cooler (D2).
  bool _speaking = false, _lastCloud = false, _deepThink = false;
  Timer? _speakTimer, _thinkTimer, _capTimer;
  String?
  _caption; // the latest reply, materialised over Plena (Spec 15 §6.1 / §7.3)
  // The glyph Plena should trace next, fired by bumping the nonce (Spec 15 §5A). apt-or-absent:
  // most turns fire none. A short debounce keeps them from stacking during rapid dogfooding.
  GlyphDef? _glyph;
  int _glyphNonce = 0, _glyphPreview = 0;
  DateTime _lastGlyphAt = DateTime.fromMillisecondsSinceEpoch(0);
  PresenceTuning _tuning =
      const PresenceTuning(); // live aesthetic controls (the tune sheet)
  void _fireGlyph(GlyphDef? g, {bool force = false}) {
    if (g == null) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastGlyphAt).inSeconds < 8) return;
    _lastGlyphAt = now;
    setState(() {
      _glyph = g;
      _glyphNonce++;
    });
  }

  PresenceState get _presence => _listening
      ? PresenceState.listening
      : _busy
      ? PresenceState.thinking
      : _speaking
      ? PresenceState.speaking
      : PresenceState.idle;
  // D1 while a turn is in flight; D2 once it's clearly working (a long/cloud turn), so Plena
  // visibly "reaches" (Spec 15 §4.2). Speaking a cloud-derived answer keeps the cooler tint.
  double get _difficulty =>
      _busy ? (_deepThink ? 2 : 1) : (_speaking && _lastCloud ? 2 : 0);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final log = AppLog.instance;
    try {
      log('init: begin (retrieval=${widget.retrieval})');
      await _session.init(retrieval: widget.retrieval, onPhase: log.log);
      _speech =
          await _pickSpeech(); // on-device sherpa if the model's present, else OS SAPI
      log('init: ready (voice=${_speech?.available ?? false})');
      if (!mounted) return; // torn down during init -> don't setState
      // Opt-in diagnostic: set PLENARA_SELFTEST=1 to fire an immediate "notifications are
      // on" toast at launch (proven working; off by default so normal launches are quiet).
      if (widget.session == null &&
          Platform.environment['PLENARA_SELFTEST'] == '1') {
        // ignore: discarded_futures
        _scheduler.selfTest();
      }
      setState(() {
        _ready = true;
        _msgs.add(
          Msg(
            'Hi — I\'m Plenara. Try: "add call the plumber to my list", "log a 3k run", '
            '"remind me to call mom on thursday at 5pm", "what do I know about Mia", '
            '"list my tasks", or "start tracking my water intake". "undo that" reverses the '
            'last thing — and ask "what can you do" any time.\n\n'
            'Diagnostics log: ${log.file.path}',
            false,
          ),
        );
        // On-open nudges (past-due reminders + upcoming birthdays) — each line
        // already carries its own icon, so show it as-is. Nothing silently missed.
        for (final n in _session.pendingNudges()) {
          _msgs.add(Msg(n, false));
        }
      });
      // a greeting on open — a birthday today earns the candle, otherwise a smile
      final onOpen = _session.pendingNudges();
      _fireGlyph(
        onOpen.any((n) => n.toLowerCase().contains('birthday'))
            ? kGlyphs['candle']
            : kGlyphs['smile'],
        force: true,
      );
    } catch (e, st) {
      log('init: FAILED: $e\n$st');
      // no infinite spinner: surface the failure and let the user see it
      setState(() {
        _ready = true;
        _msgs.add(
          Msg(
            "I couldn't start up — there may be a problem reading your data folder.\n\n$e"
            "\n\nDiagnostics: ${log.file.path}",
            false,
          ),
        );
      });
    }
  }

  /// Pick the best available recognizer: on-device sherpa_onnx (private, modern accuracy) if its
  /// model is downloaded; else the OS SAPI engine (rough but built-in); else Noop (mic hidden).
  /// A test-injected recognizer always wins; an injected session means "test" -> Noop.
  Future<SpeechRecognizer> _pickSpeech() async {
    final log = AppLog.instance;
    if (widget.speech != null) {
      await widget.speech!.init();
      return widget.speech!;
    }
    if (widget.session != null) return NoopSpeechRecognizer();
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final modelDir =
        '$home${Platform.pathSeparator}.plenara${Platform.pathSeparator}'
        'models${Platform.pathSeparator}en-whisper';
    final sherpa = SherpaSpeechRecognizer(
      modelDir,
      onLog: (m) => log.debug('sherpa: $m'),
    );
    await sherpa.init();
    if (sherpa.available) {
      log('speech: using on-device sherpa_onnx');
      return sherpa;
    }
    log.debug('speech: sherpa model unavailable -> falling back to OS SAPI');
    final sys = SystemSpeechRecognizer(onLog: (m) => log.debug('speech: $m'));
    await sys.init();
    return sys;
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty || _busy) return;
    _ctrl.clear();
    setState(() {
      _msgs.add(Msg(t, true));
      _busy = true;
      _deepThink = false;
      _caption = null;
    });
    // after a beat, a still-running turn reads as "reaching" (D2) — long/cloud work
    _thinkTimer?.cancel();
    _thinkTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _deepThink = true);
    });
    _jump();
    final log = AppLog.instance;
    log('turn: "$t"');
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
      return; // widget torn down mid-turn -> don't setState after dispose
    }
    final usedCloud = _session.lastTurnUsedCloud;
    log(
      'turn -> [${_session.lastSource}${usedCloud ? ', cloud' : ', offline'}] '
      '${resp.length > 140 ? '${resp.substring(0, 140)}…' : resp}',
    );
    // _busy is always cleared, so the input can never lock up
    // Surface any automation deliveries this turn produced (Spec 02 §7.5 read-only "deliver"),
    // draining them so they don't re-appear as on-open nudges next launch; and prompt on a NEW
    // held write so the user can approve/dismiss it (§7.5 "hold for review").
    final deliveries = _session.automations.takeDeliveries();
    final review = _session.automations.pendingReview;
    final newReviews = review.length > reviewsBefore
        ? review.sublist(reviewsBefore)
        : const [];
    setState(() {
      _msgs.add(Msg(resp, false, cloud: usedCloud));
      for (final d in deliveries) {
        _msgs.add(Msg('✨ ${d.text}', false));
      }
      for (final p in newReviews) {
        _msgs.add(
          Msg('📋 ${p.description} — say "approve it" or "dismiss it".', false),
        );
      }
      _busy = false;
      _deepThink = false;
      _speaking = true; // Plena "speaks" the reply — a brief presence flourish
      _lastCloud = usedCloud;
      _caption = resp; // the words materialise over Plena as she speaks (§6.1)
    });
    _thinkTimer?.cancel();
    // speaking lasts a touch longer for a longer reply (a stand-in for the cadence envelope)
    final speakMs = (1400 + resp.length * 22).clamp(1600, 4200);
    _speakTimer?.cancel();
    _speakTimer = Timer(Duration(milliseconds: speakMs), () {
      if (mounted) setState(() => _speaking = false);
    });
    _capTimer?.cancel();
    _capTimer = Timer(Duration(milliseconds: speakMs + 1400), () {
      if (mounted) setState(() => _caption = null);
    });
    // apt-or-absent: an occasion-appropriate glyph, or nothing (most turns)
    _fireGlyph(glyphForTurn(_session.lastSkill, resp));
    _jump();
  }

  /// Tap the mic to START, speak, then PAUSE — the OS engine's own end-of-utterance detection
  /// delivers the final transcript in-session (~1s after speech ends) and we auto-send it, so
  /// voice is a complete hands-free action. On Windows there are no partial results (the SAPI
  /// backend only delivers finals), so the box fills at the end, not live. Tapping stop ABORTS:
  /// the plugin kills its event pump on stop, so a not-yet-finalized transcript can't be
  /// retrieved — don't rely on the stop tap to finalize. onDone always clears the listening
  /// state, so the UI can never get stuck at "Listening…".
  Future<void> _toggleMic() async {
    final log = AppLog.instance;
    if (!(_speech?.available ?? false) || _busy) {
      log.debug(
        'speech: mic tap ignored (available=${_speech?.available ?? false}, busy=$_busy)',
      );
      return;
    }
    if (_listening) {
      log.debug('speech: mic tap -> stop (abort)');
      await _speech!
          .stop(); // abort; anything not yet finalized by the engine is lost (see above)
      return;
    }
    log.debug('speech: mic tap -> start');
    setState(() => _listening = true);
    try {
      await _speech!.listen(
        onResult: (text, isFinal) {
          final t = text.trim();
          log.debug("speech: result '$t' final=$isFinal");
          if (!mounted || t.isEmpty) return;
          setState(
            () => _ctrl.text = t,
          ); // fill the box; this is also what we'll send
          // Auto-send on the engine's FINAL result, delivered in-session by its own
          // end-of-utterance detection. Then STOP the engine: one utterance per tap — on Windows
          // SAPI dictation otherwise stays active until listenFor and a second utterance would
          // fire another (unwanted) auto-send.
          if (isFinal) {
            setState(() => _listening = false);
            unawaited(_speech!.stop());
            if (!_busy) {
              log.debug('speech: auto-send on final result');
              _send();
            }
          }
        },
        onDone: () {
          log.debug(
            'speech: onDone (listening=$_listening, text="${_ctrl.text}")',
          );
          if (mounted) setState(() => _listening = false);
        },
      );
    } catch (e) {
      log.debug('speech: listen failed: $e');
      if (mounted) setState(() => _listening = false);
    }
  }

  @override
  void dispose() {
    _speech
        ?.cancel(); // never leave the recognizer recording after teardown (privacy)
    _speakTimer?.cancel();
    _thinkTimer?.cancel();
    _capTimer?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A live tuning sheet for Plena — the mockup's knobs in the app, so the feel is dialed by eye
  /// without a rebuild. Changes apply to _tuning immediately (Plena reads it every frame).
  void _openTuning() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget row(
            String label,
            double value,
            double min,
            double max,
            PresenceTuning Function(double) apply,
          ) => Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(label, style: Theme.of(ctx).textTheme.bodyMedium),
              ),
              Expanded(
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: (v) {
                    setState(() => _tuning = apply(v));
                    setSheet(() {});
                  },
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  value.toStringAsFixed(value >= 10 ? 0 : 2),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          );
          final t = _tuning;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tune Plena', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                row('Hue', t.hue, 0, 360, (v) => t.copyWith(hue: v)),
                row('Vibrance', t.sat, .3, 1, (v) => t.copyWith(sat: v)),
                row(
                  'Brightness',
                  t.bright,
                  .4,
                  1.9,
                  (v) => t.copyWith(bright: v),
                ),
                row(
                  'Breadth',
                  t.breadth,
                  .5,
                  1.7,
                  (v) => t.copyWith(breadth: v),
                ),
                row(
                  'Gravity',
                  t.gravity,
                  .25,
                  2,
                  (v) => t.copyWith(gravity: v),
                ),
                row('Looseness', t.loose, .3, 2.6, (v) => t.copyWith(loose: v)),
                row('Trail', t.trail, 0, 1, (v) => t.copyWith(trail: v)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setState(() => _tuning = const PresenceTuning());
                      setSheet(() {});
                    },
                    child: const Text('Reset'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _jump() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plenara'),
        backgroundColor: cs.inversePrimary,
        actions: [
          if (_ready)
            IconButton(
              icon: const Icon(Icons.storage),
              tooltip: 'Your data',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DataView(session: _session)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Tune Plena',
            onPressed: _openTuning,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsView())),
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Plena — the living presence (Spec 15). Reflects idle / listening / thinking /
                // speaking; her "thinking" state replaces the old busy spinner.
                // Plena — the living presence, with the reply materialising over her. Long-press to
                // browse the glyph vocabulary (dev preview, Spec 15 §5A.8).
                Semantics(
                  label:
                      'Plena — ${_presence.name}${_caption != null ? '. $_caption' : ''}',
                  container: true,
                  child: GestureDetector(
                    // Tap Plena to talk; long-press to browse the glyph vocabulary (dev preview).
                    onTap: (_speech?.available ?? false) && !_busy ? _toggleMic : null,
                    onLongPress: () {
                      final all = kGlyphs.values.toList();
                      _fireGlyph(
                        all[_glyphPreview++ % all.length],
                        force: true,
                      );
                    },
                    child: SizedBox(
                      height: 168,
                      width: double.infinity,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            // Static (no ticker) under an injected test session so pumpAndSettle terminates.
                            child: PresenceView(
                              state: _presence,
                              difficulty: _difficulty,
                              animate: widget.session == null,
                              glyph: _glyph,
                              glyphNonce: _glyphNonce,
                              tuning: _tuning,
                            ),
                          ),
                          // Caption is a production-only presence overlay; tests (injected session)
                          // assert on the chat log, and a second copy of the reply would double it.
                          if (widget.session == null)
                            Positioned(
                              left: 20,
                              right: 20,
                              bottom: 12,
                              child: AnimatedOpacity(
                                opacity: _caption == null ? 0 : 1,
                                duration: const Duration(milliseconds: 450),
                                curve: Curves.easeOut,
                                child: _caption == null
                                    ? const SizedBox.shrink()
                                    : Text(
                                        _caption!,
                                        textAlign: TextAlign.center,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFFEAE2D8),
                                          fontSize: 15,
                                          height: 1.35,
                                          shadows: [
                                            Shadow(
                                              blurRadius: 14,
                                              color: Colors.black,
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _msgs.length,
                    itemBuilder: (c, i) {
                      final m = _msgs[i];
                      return Align(
                        alignment: m.user
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          constraints: const BoxConstraints(maxWidth: 520),
                          decoration: BoxDecoration(
                            color: m.user
                                ? cs.primaryContainer
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: m.cloud
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 5,
                                        right: 8,
                                      ),
                                      child: Tooltip(
                                        message:
                                            'Used the cloud (Claude) for this reply',
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF2E7D32),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Flexible(child: SelectableText(m.text)),
                                  ],
                                )
                              : SelectableText(m.text),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      if (_speech?.available ?? false) ...[
                        IconButton(
                          icon: Icon(
                            _listening ? Icons.stop_circle : Icons.mic_none,
                          ),
                          color: _listening ? cs.error : null,
                          tooltip: _listening ? 'Tap to stop' : 'Speak',
                          onPressed: _busy ? null : _toggleMic,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          autofocus: true,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: _listening
                                ? 'Listening — pause a moment when you\'re done…'
                                : 'Say something…',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _busy ? null : _send,
                        child: const Text('Send'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
