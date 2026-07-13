// Widget tests for Plena's presence-primary UI (Spec 15). A Session is injected (temp data dir,
// offline cloud) so tests are hermetic. In tests there's no mic (Noop STT) → text mode, so a turn
// is driven by typing into the input box; replies materialise as ephemeral text over the void.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:plenara_app/main.dart';
import 'package:plenara_app/plena.dart';
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
}
