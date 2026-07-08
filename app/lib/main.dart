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
import 'onboarding_view.dart';
import 'settings_view.dart';
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
  return Session(
    cfg.dataDir,
    cloud: cfg.apiKey != null ? ClaudeClient(apiKeyOverride: cfg.apiKey) : null,
    scheduler: scheduler,
    deviceDir: defaultDeviceDir(), // deviceId + turnlog stay device-local, off the synced folder
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
  const Home({super.key, this.session, this.retrieval = false, this.configPath});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late bool _onboarding = widget.session == null && loadConfig(configPath: widget.configPath).apiKey == null;
  @override
  Widget build(BuildContext context) => _onboarding
      ? WelcomeScreen(onContinue: () => setState(() => _onboarding = false), configPath: widget.configPath)
      : ChatScreen(session: widget.session, retrieval: widget.retrieval);
}

class Msg {
  final String text;
  final bool user;
  Msg(this.text, this.user);
}

class ChatScreen extends StatefulWidget {
  /// Tests inject a Session (temp data dir + replay/offline cloud). [retrieval]
  /// defaults OFF — the embed server isn't part of the dogfood setup, and building
  /// the index against a DOWN server costs ~2s per anchor (a minute-long startup
  /// hang). Enable it only alongside a running embed server.
  final Session? session;
  final bool retrieval;
  final SpeechRecognizer? speech; // voice input (task #18); Noop by default -> mic hidden
  const ChatScreen({super.key, this.session, this.retrieval = false, this.speech});
  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  // Held so we can run a launch-time toast self-test (production only). `late` so an
  // injected test session never constructs the native plugin.
  late final WindowsToastScheduler _scheduler = WindowsToastScheduler();
  late final Session _session = widget.session ?? buildSession(scheduler: _scheduler);
  late final SpeechRecognizer _speech = widget.speech ?? NoopSpeechRecognizer();
  final _msgs = <Msg>[];
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _ready = false, _busy = false, _listening = false;

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
      log('init: ready');
      // Opt-in diagnostic: set PLENARA_SELFTEST=1 to fire an immediate "notifications are
      // on" toast at launch (proven working; off by default so normal launches are quiet).
      if (widget.session == null && Platform.environment['PLENARA_SELFTEST'] == '1') {
        // ignore: discarded_futures
        _scheduler.selfTest();
      }
      setState(() {
        _ready = true;
        _msgs.add(Msg(
            'Hi — I\'m Plenara. Try: "add call the plumber to my list", "log a 3k run", '
            '"remind me to call mom on thursday at 5pm", "what do I know about Mia", '
            '"list my tasks", or "start tracking my water intake". "undo that" reverses the '
            'last thing — and ask "what can you do" any time.\n\n'
            'Diagnostics log: ${log.file.path}',
            false));
        // On-open nudges (past-due reminders + upcoming birthdays) — each line
        // already carries its own icon, so show it as-is. Nothing silently missed.
        for (final n in _session.pendingNudges()) {
          _msgs.add(Msg(n, false));
        }
      });
    } catch (e, st) {
      log('init: FAILED: $e\n$st');
      // no infinite spinner: surface the failure and let the user see it
      setState(() {
        _ready = true;
        _msgs.add(Msg(
            "I couldn't start up — there may be a problem reading your data folder.\n\n$e"
            "\n\nDiagnostics: ${log.file.path}",
            false));
      });
    }
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty || _busy) return;
    _ctrl.clear();
    setState(() {
      _msgs.add(Msg(t, true));
      _busy = true;
    });
    _jump();
    final log = AppLog.instance;
    log('turn: "$t"');
    final reviewsBefore = _session.automations.pendingReview.length;
    String resp;
    try {
      resp = await _session.handle(t); // already catch-all internally; belt-and-suspenders here
    } catch (e, st) {
      log('turn FAILED: $e\n$st');
      resp = 'Something went wrong: $e';
    }
    log('turn -> ${resp.length > 140 ? '${resp.substring(0, 140)}…' : resp}');
    // _busy is always cleared, so the input can never lock up
    // Surface any automation deliveries this turn produced (Spec 02 §7.5 read-only "deliver"),
    // draining them so they don't re-appear as on-open nudges next launch; and prompt on a NEW
    // held write so the user can approve/dismiss it (§7.5 "hold for review").
    final deliveries = _session.automations.takeDeliveries();
    final review = _session.automations.pendingReview;
    final newReviews = review.length > reviewsBefore ? review.sublist(reviewsBefore) : const [];
    setState(() {
      _msgs.add(Msg(resp, false));
      for (final d in deliveries) {
        _msgs.add(Msg('✨ ${d.text}', false));
      }
      for (final p in newReviews) {
        _msgs.add(Msg('📋 ${p.description} — say "approve it" or "dismiss it".', false));
      }
      _busy = false;
    });
    _jump();
  }

  /// Push-to-talk: capture speech and drop the transcript into the input for the user to review
  /// and send. The typed field is always available, so voice is purely additive.
  Future<void> _listen() async {
    if (_listening || _busy || !_speech.available) return;
    setState(() => _listening = true);
    try {
      final text = await _speech.transcribe();
      if (!mounted) return;
      if (text != null && text.trim().isNotEmpty) _ctrl.text = text.trim();
    } catch (e) {
      AppLog.instance.log('speech: transcribe failed: $e');
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  void _jump() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
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
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsView()),
            ),
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _msgs.length,
                  itemBuilder: (c, i) {
                    final m = _msgs[i];
                    return Align(
                      alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        constraints: const BoxConstraints(maxWidth: 520),
                        decoration: BoxDecoration(
                          color: m.user ? cs.primaryContainer : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SelectableText(m.text),
                      ),
                    );
                  },
                ),
              ),
              if (_busy) LinearProgressIndicator(minHeight: 2, color: cs.primary),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  if (_speech.available) ...[
                    IconButton(
                      icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                      color: _listening ? cs.error : null,
                      tooltip: _listening ? 'Listening…' : 'Speak',
                      onPressed: _busy ? null : _listen,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      autofocus: true,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                          hintText: _listening ? 'Listening…' : 'Say something…',
                          border: const OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _busy ? null : _send, child: const Text('Send')),
                ]),
              ),
            ]),
    );
  }
}
