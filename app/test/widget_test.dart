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
import 'package:plenara_app/data_location.dart';
import 'package:plenara_app/main.dart';
import 'package:plenara_app/plena.dart';
import 'package:plenara_app/settings_view.dart';
import 'package:plenara_app/speech.dart';
import 'package:plenara_app/speech_out.dart';

class _FakeSpeech implements SpeechRecognizer {
  @override
  Stream<double> get levels => const Stream<double>.empty();

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
    void Function(SpeechNotice)? onNotice,
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
  Stream<double> get levels => const Stream<double>.empty();

  @override
  Future<void> init() async {}
  @override
  bool get available => true;
  @override
  Future<void> listen({
    required void Function(String, bool) onResult,
    required void Function() onDone,
    void Function(SpeechNotice)? onNotice,
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
  final _levels = StreamController<double>.broadcast();
  @override
  Stream<double> get levels => _levels.stream;

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
    void Function(SpeechNotice)? onNotice,
  }) async {
    _onResult = onResult;
    _onDone = onDone;
    _active = true; // holds — no callback fires until the test drives one
  }

  void emitPartial(String t) =>
      _onResult?.call(t, false); // interim (non-final)
  void emitFinal(String t) => _onResult?.call(t, true); // final -> auto-send
  void emitLevel(double value) => _levels.add(value);

  void _finish() {
    if (!_active) return;
    _active = false;
    _onDone?.call();
  }

  /// Happy-path engine model: the user taps STOP and the engine delivers the complete session as a
  /// final transcript. Apple's partial-then-done behavior is covered separately by
  /// `RecognitionSession` tests; `cancel()` still throws pending speech away.
  String? pendingFinal;

  @override
  Future<void> stop() async {
    if (!_active) return;
    final t = pendingFinal;
    if (t != null && t.isNotEmpty) _onResult?.call(t, true);
    _finish();
  }

  @override
  void cancel() => _finish(); // discards pendingFinal — nothing is ever sent
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

/// Seed a routine (one short TIMED step, then a rep step) straight into the
/// store and start the run — the player state the step-timer items exercise.
/// Call AFTER the ChatScreen has initialized the session; the next turn's
/// rebuild shows the overlay and arms the cadence via _syncStepTimer.
///
/// The step duration is 2 REAL seconds: the cadence measures wall-clock
/// elapsed (DateTime.now), so tests elapse it with a short [WidgetTester.runAsync]
/// wait and then pump fake time so the periodic tick actually fires.
void _seedTimedRun(Session session) {
  session.store['routine-1'] = {
    'id': 'routine-1',
    'typeId': 'routine',
    'title': 'Morning loosener',
  };
  session.store['step-1'] = {
    'id': 'step-1',
    'typeId': 'routine_step',
    'routine': 'routine-1',
    'order': 1,
    'name': 'Cat-cow',
    'instruction': 'Round your back up, then let it dip.',
    'durationSeconds': 2,
  };
  session.store['step-2'] = {
    'id': 'step-2',
    'typeId': 'routine_step',
    'routine': 'routine-1',
    'order': 2,
    'name': 'Push-ups',
    'instruction': 'Lower under control, press back up.',
    'reps': 5,
  };
  session.startRoutineRun('routine-1', DateTime.now());
}

/// Let the 2s timed step really elapse (wall clock), then pump enough fake
/// time for the 1s periodic tick to fire and observe it.
Future<void> _elapseTimedStep(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 2400)),
  );
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  testWidgets('no mic → text mode: an input box, no mic button', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session())));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget); // the keyboard path
    expect(find.byIcon(Icons.mic_none), findsNothing);
  });

  testWidgets('Today materialises, and a typed turn gets a reply over it', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session())));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('today-board')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Send'), findsOneWidget);

    await _send(tester, 'add buy milk to my list');
    expect(
      find.textContaining('Added'),
      findsOneWidget,
    ); // the reply, over the void
    expect(find.textContaining('buy milk'), findsWidgets);
  });

  testWidgets(
    'task title opens details while its circle remains the completion action',
    (tester) async {
      final session = _session();
      await session.init(retrieval: false);
      await session.handle('add pack clothes to my list');
      final task = session.store.values.singleWhere(
        (record) => record['typeId'] == 'task',
      );
      expect(
        (await session.editField('${task['id']}', 'status', 'today')).ok,
        isTrue,
      );
      final speech = _HoldingSpeech();
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(session: session, speech: speech),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('pack clothes'));
      await tester.pumpAndSettle();

      expect(session.store[task['id']]!['status'], 'today');
      expect(find.byKey(const Key('record-detail')), findsOneWidget);
      expect(find.byKey(const Key('today-board')), findsOneWidget);
      expect(
        find.byKey(const Key('cancel-listen')),
        findsNothing,
        reason: 'the detail action must win over Today\'s background voice tap',
      );

      Navigator.of(
        tester.element(find.byKey(const Key('record-detail'))),
      ).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Complete pack clothes'));
      await tester.pumpAndSettle();

      expect(session.store[task['id']]!['status'], 'done');
      expect(find.byKey(const Key('record-detail')), findsNothing);
      expect(find.byKey(const Key('latest-change')), findsOneWidget);
    },
  );

  testWidgets('detached operation progress and result arrive without polling', (
    tester,
  ) async {
    final session = _session();
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: session)));
    await tester.pumpAndSettle();
    final began = Completer<void>();
    final result = Completer<String>();

    final operation = session.operations.start(
      kind: 'test-analysis',
      title: 'Test analysis',
      run: (_) {
        began.complete();
        return result.future;
      },
    );
    await began.future;
    await tester.pump();
    expect(find.text('Test analysis'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    result.complete('The detached result');
    await session.operations.wait(operation.id);
    await tester.pump();

    expect(find.textContaining('Test analysis is ready'), findsOneWidget);
    expect(find.textContaining('The detached result'), findsOneWidget);
    expect(session.operations.takeDeliveries(), isEmpty);
    await tester.pump(const Duration(seconds: 6));
    expect(find.textContaining('The detached result'), findsNothing);
  });

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
    await tester.tap(find.byKey(const Key('today-voice')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Added'),
      findsOneWidget,
    ); // transcribed + auto-sent + replied
  });

  testWidgets(
    'a list reply\'s trailing footer renders separately, not glued to the last bullet (Fable #8)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ChatScreen(session: _session())),
      );
      await tester.pumpAndSettle();
      await _send(tester, 'what can you do'); // opens the Tour
      await _send(
        tester,
        'show me everything',
      ); // → the full map (_helpText: bullets + a footer line)
      // The footer "And "undo that" reverses the last thing." must be its OWN Text, not folded into
      // the last bullet — a predicate on exact data catches the glued-in regression.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text && w.data == 'And "undo that" reverses the last thing.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '"open settings" opens the Settings window, not a routed turn (H5)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ChatScreen(session: _session())),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'open settings');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsView), findsOneWidget);
    },
  );

  testWidgets('a startup data failure offers an in-app fresh-start recovery', (
    tester,
  ) async {
    var resets = 0;
    var restarts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(
          session: _session(),
          initializeSession: (_) async =>
              throw StateError('broken data folder'),
          resetData: () async {
            resets++;
            return const DataResetResult(
              dataDir: '/fresh/Plenara',
              backupDir: '/backup/Plenara',
            );
          },
          onDataReset: () => restarts++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('startup-recovery')), findsOneWidget);
    expect(find.textContaining('broken data folder'), findsOneWidget);
    expect(find.byKey(const Key('today-board')), findsNothing);

    await tester.tap(find.byKey(const Key('startup-reset-data')));
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(restarts, 1);
  });

  testWidgets(
    'a settings-mentioning task does NOT hijack to Settings (H5 negative)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ChatScreen(session: _session())),
      );
      await tester.pumpAndSettle();
      await _send(tester, 'add review the settings to my list');
      expect(
        find.byType(SettingsView),
        findsNothing,
      ); // it's a task, not a nav command
      expect(find.textContaining('Added'), findsOneWidget);
    },
  );

  testWidgets(
    'repeated no-audio taps surface the mic hint — no silent failure (H4)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            session: _session(),
            speech: _FakeSpeech(true, null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('today-voice')),
      ); // tap 1 → hears nothing
      await tester.pumpAndSettle();
      expect(
        find.textContaining('not hearing any audio'),
        findsNothing,
      ); // not after ONE
      await tester.tap(
        find.byKey(const Key('today-voice')),
      ); // tap 2 → hears nothing
      await tester.pumpAndSettle();
      expect(
        find.textContaining('not hearing any audio'),
        findsOneWidget,
      ); // hint on the 2nd
    },
  );

  testWidgets(
    'muting keeps planner truth visible and changes the voice control',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(session: _session(), speech: _FakeSpeech(true, 'x')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('today-board')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.volume_up)); // mute
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('today-board')), findsOneWidget);
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
    },
  );

  testWidgets(
    'mute preference persists across launches (H2, via configPath seam)',
    (tester) async {
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
      await tester.tap(
        find.byIcon(Icons.volume_up),
      ); // mute → should persist to cfg
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
      expect(
        find.byIcon(Icons.volume_off),
        findsOneWidget,
      ); // launched already muted
    },
  );

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
    await tester.tap(find.byKey(const Key('today-voice')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('I heard: add milk to my list'),
      findsOneWidget,
    ); // the confirmation, in the listening font
    expect(
      find.textContaining('Added'),
      findsOneWidget,
    ); // and it still auto-sent
  });

  testWidgets('tap-to-talk with no transcript sends nothing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(session: _session(), speech: _FakeSpeech(true, null)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('today-voice')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Added'), findsNothing); // nothing sent
    expect(find.byKey(const Key('today-board')), findsOneWidget);
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
    await tester.tap(find.byKey(const Key('today-voice')));
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

    expect(find.text('Now'), findsOneWidget);
    expect(find.text('call mom'), findsOneWidget);
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

    expect(find.text("Sarah's birthday"), findsOneWidget);
    expect(find.text('In 4 days'), findsOneWidget);
  });

  testWidgets('empty send does nothing', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('today-board')), findsOneWidget);
  });

  testWidgets('undo from the UI reverses the last turn', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session())));
    await tester.pumpAndSettle();
    await _send(tester, 'add buy milk to my list');
    expect(find.textContaining('Added'), findsOneWidget);
    await _send(tester, 'undo that');
    expect(find.textContaining('Undone'), findsOneWidget);
  });

  testWidgets('multi-turn: a task added is shown (bulleted) by "list my tasks"', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session())));
    await tester.pumpAndSettle();
    await _send(tester, 'add buy milk to my list');
    await _send(tester, 'list my tasks');
    // List register: the item renders in the reading column with a mote mark (not an ASCII "•"),
    // so the item text is just "buy milk" (bullet stripped, drawn as a coloured dot).
    expect(find.textContaining('buy milk'), findsWidgets);
    expect(find.textContaining('• buy milk'), findsNothing);
  });

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

  testWidgets(
    'M5 — a live partial transcript materialises mid-listen, then the final replies',
    (tester) async {
      final speech = _HoldingSpeech();
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(session: _session(), speech: speech),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('today-voice')));
      await tester.pumpAndSettle();
      // Before any words: the status line teaches the stop gesture (first sessions only).
      expect(
        find.textContaining("tap anywhere when you're done"),
        findsOneWidget,
      );

      speech.emitPartial('add buy bread'); // interim words stream in
      await tester.pump();
      // The live partial appears as the caption over the void…
      expect(find.textContaining('add buy bread'), findsWidgets);
      // …and the status line is gone the moment a partial takes over (no overlap).
      expect(
        find.textContaining("tap anywhere when you're done"),
        findsNothing,
      );

      speech.emitFinal('add buy bread to my list'); // final → auto-send
      await tester.pumpAndSettle();
      expect(
        find.textContaining('I heard: add buy bread to my list'),
        findsOneWidget,
      );
      expect(find.textContaining('Added'), findsOneWidget); // the reply landed
    },
  );

  testWidgets('platform mic level drives listening presence energy input', (
    tester,
  ) async {
    final speech = _HoldingSpeech();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(session: _session(), speech: speech),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('today-voice')));
    await tester.pump();
    speech.emitLevel(.8);
    await tester.pump();

    final presence = tester.widget<PresenceView>(find.byType(PresenceView));
    expect(presence.state, PresenceState.listening);
    expect(presence.listeningLevel, .8);
    await tester.tap(find.byKey(const Key('cancel-listen')));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'M6 — deliberate ✕-abort never trips the no-audio hint, and clears listening',
    (tester) async {
      final speech = _HoldingSpeech();
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(session: _session(), speech: speech),
        ),
      );
      await tester.pumpAndSettle();

      // Two full start→abort cycles. Each abort's cancel fires onDone; the _aborting guard must keep
      // it from counting as a no-audio miss. Without the guard, two misses would streak to the hint.
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const Key('today-voice'))); // start
        await tester.pumpAndSettle();
        expect(
          find.textContaining('listening'),
          findsOneWidget,
        ); // genuinely listening
        await tester.tap(
          find.byKey(const Key('cancel-listen')),
        ); // abort via ✕ (NOT a second tap)
        await tester.pumpAndSettle();
      }

      expect(
        find.textContaining('not hearing any audio'),
        findsNothing,
      ); // abort ≠ no-audio miss
      expect(
        find.textContaining('listening'),
        findsNothing,
      ); // listener not left stuck
    },
  );

  testWidgets(
    'the SECOND tap stops and sends — it does not discard (user-delimited capture)',
    (tester) async {
      final speech = _HoldingSpeech()
        ..pendingFinal = 'add buy bread to my list';
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(session: _session(), speech: speech),
        ),
      );
      await tester.pumpAndSettle();

      const void_ = Offset(400, 300);
      await tester.tap(find.byKey(const Key('today-voice'))); // start
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('cancel-listen')),
        findsOneWidget,
      ); // ✕ only exists while listening

      await tester.tapAt(
        void_,
      ); // STOP — the engine finalizes and the app sends
      await tester.pumpAndSettle();

      expect(
        find.textContaining('I heard: add buy bread to my list'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Added'),
        findsOneWidget,
      ); // it really was sent, not discarded
      expect(
        find.byKey(const Key('cancel-listen')),
        findsNothing,
      ); // and the ✕ is gone again
    },
  );

  testWidgets('✕ discards what was said — nothing is sent', (tester) async {
    final speech = _HoldingSpeech()..pendingFinal = 'add buy bread to my list';
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(session: _session(), speech: speech),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('today-voice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-listen')));
    await tester.pumpAndSettle();

    expect(find.textContaining('I heard:'), findsNothing);
    expect(
      find.textContaining('Added'),
      findsNothing,
    ); // the pending transcript never reached the turn
  });

  testWidgets(
    'returning from the background re-arms a live timed step cadence',
    (tester) async {
      final session = _session();
      await tester.pumpWidget(MaterialApp(home: ChatScreen(session: session)));
      await tester.pumpAndSettle();
      _seedTimedRun(session);
      // any turn rebuilds (showing the run) and arms the 45s cadence
      await _send(tester, 'add buy milk to my list');
      expect(session.activeRun!.position, 1);

      // background mid-step (cancels the cadence), then come back
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      await _elapseTimedStep(tester);
      await tester.pumpAndSettle();
      expect(
        session.activeRun!.position,
        2,
        reason:
            'the timed step must auto-advance after resume — a cancelled-forever '
            'cadence silently stalls the run',
      );
    },
  );

  testWidgets(
    'an operation delivery landing mid-turn is presented after the turn, not lost',
    (tester) async {
      final gate = Completer<void>();
      final session = Session(
        _tempData(),
        clock: DateTime.parse('2026-07-06T09:00:00'),
        cloud: _GatedCloud(gate),
      );
      await tester.pumpWidget(MaterialApp(home: ChatScreen(session: session)));
      await tester.pumpAndSettle();

      // hold a turn in flight
      await tester.enterText(
        find.byType(TextField),
        'something the corpus cannot match',
      );
      await tester.tap(find.text('Send'));
      await tester.pump();

      // a detached operation completes while the turn is still in flight
      final began = Completer<void>();
      final result = Completer<String>();
      final operation = session.operations.start(
        kind: 'test-analysis',
        title: 'Background research',
        run: (_) {
          began.complete();
          return result.future;
        },
      );
      await began.future;
      result.complete('The detached result');
      await session.operations.wait(operation.id);
      await tester.pump();

      // now the turn completes — its reply owns the stage first…
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining("didn't catch"), findsOneWidget);

      // …and the queued delivery follows instead of having been overwritten.
      var presented = false;
      for (var i = 0; i < 12 && !presented; i++) {
        await tester.pump(const Duration(seconds: 1));
        presented = tester.any(
          find.textContaining('Background research is ready'),
        );
      }
      expect(
        presented,
        isTrue,
        reason:
            'a delivery drained mid-turn must be presented once the turn ends, '
            'not silently clobbered by the turn completion',
      );
      expect(find.textContaining('The detached result'), findsOneWidget);
    },
  );

  testWidgets(
    'a step timer elapsing mid-capture defers: the transcript sends, then the step advances',
    (tester) async {
      final session = _session();
      final speech = _HoldingSpeech();
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(session: session, speech: speech),
        ),
      );
      await tester.pumpAndSettle();
      _seedTimedRun(session);
      // arm the cadence with a voice turn (voice mode has no input box)
      await tester.tap(find.byKey(const Key('today-voice')));
      await tester.pumpAndSettle();
      speech.emitFinal('add buy milk to my list');
      await tester.pumpAndSettle();
      expect(session.activeRun!.position, 1);

      // start a capture, then let the timed step elapse MID-utterance
      await tester.tapAt(const Offset(300, 40)); // the void behind the card
      await tester.pump();
      expect(find.byKey(const Key('cancel-listen')), findsOneWidget);
      await _elapseTimedStep(tester);

      // The advance must WAIT: starting its turn here sets _busy, and the
      // transcript still being spoken is then dropped at `if (!_busy)`.
      expect(
        session.activeRun!.position,
        1,
        reason:
            'the elapsed step must not start its turn while the mic is open — '
            'that is what silently ate the user\'s words',
      );
      expect(
        find.byKey(const Key('cancel-listen')),
        findsOneWidget,
        reason: 'the capture session must survive the elapsed step',
      );

      // the user finishes speaking: the transcript must be sent…
      speech.emitFinal('add call sam to my list');
      await tester.pumpAndSettle();
      expect(
        session.store.values.any(
          (r) => r['typeId'] == 'task' && '${r['description']}' == 'call sam',
        ),
        isTrue,
        reason:
            'the final transcript must not be dropped because the elapsed step '
            'timer started a turn mid-utterance',
      );
      // …and the deferred advance still happens after it.
      expect(session.activeRun!.position, 2);
    },
  );

  testWidgets(
    'a timer-driven routine word never clobbers a typed draft (muted mode)',
    (tester) async {
      final session = _session();
      await tester.pumpWidget(MaterialApp(home: ChatScreen(session: session)));
      await tester.pumpAndSettle();
      _seedTimedRun(session);
      await _send(tester, 'add buy milk to my list'); // rebuild + arm cadence

      await tester.enterText(find.byType(TextField), 'half typed thought');
      await _elapseTimedStep(tester); // step elapses → timer sends 'next'
      await tester.pumpAndSettle();

      expect(session.activeRun!.position, 2); // the advance went through
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'half typed thought',
        reason:
            'the routine control word must bypass the text controller — a '
            'muted user\'s draft is not scratch space',
      );
    },
  );

  testWidgets('a long list reply scrolls by drag to reach the last item', (
    tester,
  ) async {
    final session = _session();
    await session.init(retrieval: false);
    for (var i = 1; i <= 18; i++) {
      await session.handle('add errand number $i to my list');
    }
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: session)));
    await tester.pumpAndSettle();
    await _send(tester, 'list my tasks');

    final scrollView = find.byType(SingleChildScrollView);
    expect(scrollView, findsOneWidget); // the list-register reply column
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: scrollView, matching: find.byType(Scrollable)),
        )
        .position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'the reply must be taller than the viewport for this test',
    );
    await tester.drag(scrollView, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(
      position.pixels,
      greaterThan(0),
      reason:
          'the reply column must receive drags — a long reply was unscrollable '
          'behind the caption overlay\'s IgnorePointer',
    );
  });

  testWidgets('session regeneration clears stale snackbars', (tester) async {
    final dir = Directory.systemTemp.createTempSync('plenara_regen_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final cfg = '${dir.path}/config.json';
    File(cfg).writeAsStringSync('{"dataDir": "${dir.path}/data"}');
    await tester.pumpWidget(
      MaterialApp(home: Home(session: _session(), configPath: cfg)),
    );
    await tester.pumpAndSettle();

    ScaffoldMessenger.of(
      tester.element(find.byType(ChatScreen)),
    ).showSnackBar(
      const SnackBar(
        content: Text('stale undo'),
        duration: Duration(minutes: 1),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('stale undo'), findsOneWidget);

    // the reset flow regenerates the session (ChatScreen is rebuilt with a new
    // key); the queued UNDO closure would fire into a disposed session
    tester.widget<ChatScreen>(find.byType(ChatScreen)).onDataReset!();
    await tester.pumpAndSettle();
    expect(
      find.text('stale undo'),
      findsNothing,
      reason: 'stale UNDO snackbars must not outlive session regeneration',
    );
  });

  testWidgets(
    'Semantics: Plena exposes state while Today exposes planner truth',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ChatScreen(session: _session())),
      );
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();
      final presence = tester
          .widget<PresenceView>(find.byType(PresenceView))
          .state;
      final node = tester.getSemantics(find.byType(PresenceView));
      // The a11y label carries Plena's current state name…
      expect(node.label, contains('Plena — ${presence.name}'));
      expect(node.label, contains('text mode'));
      expect(find.byKey(const Key('today-board')), findsOneWidget);
      handle.dispose();
    },
  );
}
