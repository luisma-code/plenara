// Widget tests for Plena's presence-primary UI (Spec 15). A Session is injected (temp data dir,
// offline cloud) so tests are hermetic. In tests there's no mic (Noop STT) → text mode, so a turn
// is driven by typing into the input box; replies materialise as ephemeral text over the void.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';
import 'package:plenara/session.dart';
import 'package:plenara_app/main.dart';
import 'package:plenara_app/plena.dart';
import 'package:plenara_app/settings_view.dart';
import 'package:plenara_app/speech.dart';
import 'package:plenara_app/speech_out.dart';

class _FakeSpeech implements SpeechRecognizer {
  final bool avail;
  final String? result;
  _FakeSpeech(this.avail, this.result);
  @override
  Future<void> init() async {}
  @override
  bool get available => avail;
  @override
  Future<void> listen({
    required void Function(String, bool) onResult,
    required void Function() onDone,
  }) async {
    if (result != null) {
      onResult(result!, true); // deliver as a FINAL result -> auto-send
    }
    onDone();
  }

  @override
  Future<void> stop() async {}
  @override
  void cancel() {}
}

class _ThrowSpeech implements SpeechRecognizer {
  @override
  Future<void> init() async {}
  @override
  bool get available => true;
  @override
  Future<void> listen({
    required void Function(String, bool) onResult,
    required void Function() onDone,
  }) async => throw StateError('engine boom');
  @override
  Future<void> stop() async {}
  @override
  void cancel() {}
}

/// A recognizer that HOLDS the session open: `listen` captures the callbacks and returns without
/// firing anything, so a test can drive interim/final results (or an abort) with exact timing.
/// `cancel`/`stop` end the session by firing `onDone` once (as a real engine does), which lets a
/// test exercise the deliberate-abort guard in `_toggleMic`'s onDone.
class _HoldingSpeech implements SpeechRecognizer {
  void Function(String, bool)? _onResult;
  void Function()? _onDone;
  bool _active = false;
  @override
  Future<void> init() async {}
  @override
  bool get available => true;
  @override
  Future<void> listen({
    required void Function(String, bool) onResult,
    required void Function() onDone,
  }) async {
    _onResult = onResult;
    _onDone = onDone;
    _active = true; // holds — no callback fires until the test drives one
  }

  void emitPartial(String t) => _onResult?.call(t, false); // interim (non-final)
  void emitFinal(String t) => _onResult?.call(t, true); // final -> auto-send

  void _finish() {
    if (!_active) return;
    _active = false;
    _onDone?.call();
  }

  @override
  Future<void> stop() async => _finish();
  @override
  void cancel() => _finish();
}

class _FakeVoice implements SpeechOutput {
  final spoken = <String>[];
  bool _speaking = false;
  @override
  Future<void> init() async {}
  @override
  bool get available => true;
  @override
  bool get speaking => _speaking;
  @override
  Future<void> speak(
    String text, {
    void Function()? onStart,
    void Function()? onDone,
  }) async {
    spoken.add(text);
    _speaking = true;
    onStart?.call();
  }

  @override
  Future<void> stop() async {
    _speaking = false;
  }
}

class _NullCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
    String u,
    Map<String, Map<String, dynamic>> s, {
    Set<String> knownContacts = const {},
  }) async => const CloudOk(null);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(
    String d, {
    String? priorError,
  }) async => const CloudOk(null);
  @override
  Future<CloudResult<String>> generate(String k, String c) async =>
      const CloudError(CloudErrorKind.noKey);
}

/// A cloud whose residual routing blocks until [gate] completes — lets a test hold a turn in
/// flight to observe the busy/thinking state deterministically.
class _GatedCloud implements CloudClient {
  final Completer<void> gate;
  _GatedCloud(this.gate);
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
    String u,
    Map<String, Map<String, dynamic>> s, {
    Set<String> knownContacts = const {},
  }) async {
    await gate.future;
    return const CloudOk(null); // abstain -> clarify
  }

  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(
    String d, {
    String? priorError,
  }) async => const CloudOk(null);
  @override
  Future<CloudResult<String>> generate(String k, String c) async =>
      const CloudError(CloudErrorKind.noKey);
}

/// Type into the input box + tap Send + settle (text mode, i.e. no mic injected).
Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.text('Send'));
  await tester.pumpAndSettle();
}

String _base(String p) => p.replaceAll('\\', '/').split('/').last;

// Seed data ships bundled at app/assets/seed (mirrored from v0/data by tool/sync_seed.sh). Resolve
// it relative to the package root — flutter test's cwd — so the helper is cross-platform (no dev
// machine path like the Windows `sourceDataDir` fallback).
String get _seedDir => '${Directory.current.path}/assets/seed';

String _tempData() {
  final tmp = Directory.systemTemp.createTempSync('plenara_ui_');
  for (final sub in const ['types', 'skills']) {
    final dst = Directory('${tmp.path}/$sub')..createSync(recursive: true);
    for (final f in Directory('$_seedDir/$sub').listSync().whereType<File>()) {
      f.copySync('${dst.path}/${_base(f.path)}');
    }
  }
  File('$_seedDir/corpus.json').copySync('${tmp.path}/corpus.json');
  Directory('${tmp.path}/records').createSync();
  return tmp.path;
}

Session _session() => Session(
  _tempData(),
  clock: DateTime.parse('2026-07-06T09:00:00'),
  cloud: _NullCloud(),
);

void main() {
  testWidgets('no mic → text mode: an input box, no mic button', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session())));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget); // the keyboard path
    expect(find.byIcon(Icons.mic_none), findsNothing);
  });

  testWidgets(
    'greeting materialises, and a typed turn gets a reply over the void',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ChatScreen(session: _session())),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining("I'm Plena"), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Send'), findsOneWidget);

      await _send(tester, 'add buy milk to my list');
      expect(
        find.textContaining('Added'),
        findsOneWidget,
      ); // the reply, over the void
      expect(find.textContaining('buy milk'), findsWidgets);
    },
  );

  testWidgets('tap-to-talk transcribes and auto-sends (hands-free)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          session: _session(),
          speech: _FakeSpeech(true, 'add milk to my list'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 300)); // tap the void → talk
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Added'),
      findsOneWidget,
    ); // transcribed + auto-sent + replied
  });

  testWidgets('a list reply\'s trailing footer renders separately, not glued to the last bullet (Fable #8)', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session())));
    await tester.pumpAndSettle();
    await _send(tester, 'what can you do'); // opens the Tour
    await _send(tester, 'show me everything'); // → the full map (_helpText: bullets + a footer line)
    // The footer "And "undo that" reverses the last thing." must be its OWN Text, not folded into
    // the last bullet — a predicate on exact data catches the glued-in regression.
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.data == 'And "undo that" reverses the last thing.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('"open settings" opens the Settings window, not a routed turn (H5)', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'open settings');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsView), findsOneWidget);
  });

  testWidgets('a settings-mentioning task does NOT hijack to Settings (H5 negative)', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session())));
    await tester.pumpAndSettle();
    await _send(tester, 'add review the settings to my list');
    expect(find.byType(SettingsView), findsNothing); // it's a task, not a nav command
    expect(find.textContaining('Added'), findsOneWidget);
  });

  testWidgets('repeated no-audio taps surface the mic hint — no silent failure (H4)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(session: _session(), speech: _FakeSpeech(true, null)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 300)); // tap 1 → hears nothing
    await tester.pumpAndSettle();
    expect(find.textContaining('not hearing any audio'), findsNothing); // not after ONE
    await tester.tapAt(const Offset(400, 300)); // tap 2 → hears nothing
    await tester.pumpAndSettle();
    expect(find.textContaining('not hearing any audio'), findsOneWidget); // hint on the 2nd
  });

  testWidgets('the intro clears on MUTE, not only on tap-to-talk (M7)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(session: _session(), speech: _FakeSpeech(true, 'x')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining("I'm Plena"), findsOneWidget);
    await tester.tap(find.byIcon(Icons.volume_up)); // mute
    await tester.pumpAndSettle();
    expect(find.textContaining("I'm Plena"), findsNothing); // intro cleared on mute
  });

  testWidgets('mute preference persists across launches (H2, via configPath seam)', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('plenara_mute_');
    final cfg = '${dir.path}/config.json';
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          session: _session(),
          speech: _FakeSpeech(true, 'x'),
          configPath: cfg,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.volume_up)); // mute → should persist to cfg
    await tester.pumpAndSettle();
    expect(loadConfig(configPath: cfg).voiceMuted, isTrue);
    // relaunch pointing at the same config → inits muted (the volume_off icon)
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          session: _session(),
          speech: _FakeSpeech(true, 'x'),
          configPath: cfg,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_off), findsOneWidget); // launched already muted
  });

  testWidgets('voice echoes "I heard: <transcript>" as a confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          session: _session(),
          speech: _FakeSpeech(true, 'add milk to my list'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 300)); // tap the void → talk
    await tester.pumpAndSettle();
    expect(
      find.textContaining('I heard: add milk to my list'),
      findsOneWidget,
    ); // the confirmation, in the listening font
    expect(find.textContaining('Added'), findsOneWidget); // and it still auto-sent
  });

  testWidgets('tap-to-talk with no transcript sends nothing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(session: _session(), speech: _FakeSpeech(true, null)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(find.textContaining('Added'), findsNothing); // nothing sent
    expect(
      find.textContaining("I'm Plena"),
      findsNothing,
    ); // the intro clears the moment you tap to interact
  });

  testWidgets('a transcribe error is caught and listening clears', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(session: _session(), speech: _ThrowSpeech()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(find.text('listening…'), findsNothing); // not stuck listening
  });

  testWidgets('a past-due reminder surfaces on open', (tester) async {
    final dir = _tempData();
    final seeder = Session(
      dir,
      clock: DateTime.parse('2026-07-06T09:00:00'),
      cloud: _NullCloud(),
    );
    await seeder.init(retrieval: false);
    await seeder.handle('remind me to call mom on thursday at 5pm');

    final reopened = Session(
      dir,
      clock: DateTime.parse('2026-07-10T09:00:00'),
      cloud: _NullCloud(),
    );
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: reopened)));
    await tester.pumpAndSettle();

    expect(find.textContaining("I'm Plena"), findsOneWidget);
    expect(find.textContaining('Reminder: call mom'), findsOneWidget);
  });

  testWidgets('an upcoming birthday surfaces on open', (tester) async {
    final dir = _tempData();
    final seeder = Session(
      dir,
      clock: DateTime.parse('2026-07-06T09:00:00'),
      cloud: _NullCloud(),
    );
    await seeder.init(retrieval: false);
    await seeder.handle("Sarah's birthday is july 10");

    final reopened = Session(
      dir,
      clock: DateTime.parse('2026-07-06T09:00:00'),
      cloud: _NullCloud(),
    );
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: reopened)));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Sarah's birthday is in 4 days"),
      findsOneWidget,
    );
  });

  testWidgets('empty send does nothing', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining("I'm Plena"),
      findsOneWidget,
    ); // greeting still there, no reply
  });

  testWidgets('undo from the UI reverses the last turn', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session())));
    await tester.pumpAndSettle();
    await _send(tester, 'add buy milk to my list');
    expect(find.textContaining('Added'), findsOneWidget);
    await _send(tester, 'undo that');
    expect(find.textContaining('Undone'), findsOneWidget);
  });

  testWidgets(
    'multi-turn: a task added is shown (bulleted) by "list my tasks"',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ChatScreen(session: _session())),
      );
      await tester.pumpAndSettle();
      await _send(tester, 'add buy milk to my list');
      await _send(tester, 'list my tasks');
      // List register: the item renders in the reading column with a mote mark (not an ASCII "•"),
      // so the item text is just "buy milk" (bullet stripped, drawn as a coloured dot).
      expect(find.textContaining('buy milk'), findsWidgets);
      expect(find.textContaining('• buy milk'), findsNothing);
    },
  );

  testWidgets('an unrecognized input gets a graceful reply', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session())));
    await tester.pumpAndSettle();
    await _send(tester, 'zxcvbnm qwerty asdf');
    expect(find.textContaining("didn't catch"), findsOneWidget);
  });

  testWidgets(
    'Send disables and Plena enters "thinking" while a turn is in flight',
    (tester) async {
      final gate = Completer<void>();
      final session = Session(
        _tempData(),
        clock: DateTime.parse('2026-07-06T09:00:00'),
        cloud: _GatedCloud(gate),
      );
      await tester.pumpWidget(MaterialApp(home: ChatScreen(session: session)));
      await tester.pumpAndSettle();

      PresenceState plenaState() =>
          tester.widget<PresenceView>(find.byType(PresenceView)).state;
      expect(plenaState(), PresenceState.idle);

      await tester.enterText(
        find.byType(TextField),
        'something the corpus cannot match',
      );
      await tester.tap(find.text('Send'));
      await tester.pump();

      expect(
        plenaState(),
        PresenceState.thinking,
      ); // Plena is the busy indicator
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'))
            .onPressed,
        isNull,
      );

      gate.complete();
      await tester.pumpAndSettle();

      expect(plenaState(), PresenceState.speaking);
      expect(find.textContaining("didn't catch"), findsOneWidget);
    },
  );

  testWidgets('Plena speaks the reply out loud, and muting silences her', (
    tester,
  ) async {
    final voice = _FakeVoice();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(session: _session(), voice: voice),
      ),
    );
    await tester.pumpAndSettle();

    await _send(tester, 'add buy milk to my list');
    expect(voice.spoken, isNotEmpty);
    expect(voice.spoken.last, contains('Added'));

    await tester.tap(find.byTooltip("Mute Plena's voice"));
    await tester.pumpAndSettle();
    final before = voice.spoken.length;
    await _send(tester, 'list my tasks');
    expect(voice.spoken.length, before); // silent while muted
  });

  testWidgets('M5 — a live partial transcript materialises mid-listen, then the final replies', (
    tester,
  ) async {
    final speech = _HoldingSpeech();
    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(session: _session(), speech: speech)),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(400, 300)); // tap the void → start listening
    await tester.pumpAndSettle();
    // Before any words: the italic status line reads "listening…" (intro cleared on tap).
    expect(find.text('listening…'), findsOneWidget);

    speech.emitPartial('add buy bread'); // interim words stream in
    await tester.pump();
    // The live partial appears as the caption over the void…
    expect(find.textContaining('add buy bread'), findsWidgets);
    // …and "listening…" is gone the moment a partial takes over (no overlap).
    expect(find.text('listening…'), findsNothing);

    speech.emitFinal('add buy bread to my list'); // final → auto-send
    await tester.pumpAndSettle();
    expect(find.textContaining('I heard: add buy bread to my list'), findsOneWidget);
    expect(find.textContaining('Added'), findsOneWidget); // the reply landed
  });

  testWidgets('M6 — deliberate tap-to-abort never trips the no-audio hint, and clears listening', (
    tester,
  ) async {
    final speech = _HoldingSpeech();
    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(session: _session(), speech: speech)),
    );
    await tester.pumpAndSettle();

    const void_ = Offset(400, 300);
    // Two full start→abort cycles. Each abort's cancel fires onDone; the _aborting guard must keep
    // it from counting as a no-audio miss. Without the guard, two misses would streak to the hint.
    for (var i = 0; i < 2; i++) {
      await tester.tapAt(void_); // start
      await tester.pumpAndSettle();
      expect(find.text('listening…'), findsOneWidget); // genuinely listening
      await tester.tapAt(void_); // abort (barge-in cancel)
      await tester.pumpAndSettle();
    }

    expect(find.textContaining('not hearing any audio'), findsNothing); // abort ≠ no-audio miss
    expect(find.text('listening…'), findsNothing); // listener not left stuck
  });

  testWidgets('Semantics: the presence exposes an accessible label with Plena\'s state and caption', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session())));
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    final presence = tester.widget<PresenceView>(find.byType(PresenceView)).state;
    final node = tester.getSemantics(find.byType(PresenceView));
    // The a11y label carries Plena's current state name…
    expect(node.label, contains('Plena — ${presence.name}'));
    // …and the current caption (here, the greeting) so screen readers hear what's on the void.
    expect(node.label, contains("I'm Plena"));
    handle.dispose();
  });
}
