// Widget smoke tests for the Plenara chat UI. Inject a Session pointed at a temp
// data dir with an offline (null) cloud so the UI test is hermetic and writes
// nothing to the real data folder.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:plenara_app/main.dart';
import 'package:plenara_app/speech.dart';

class _FakeSpeech implements SpeechRecognizer {
  final bool avail;
  final String? result;
  _FakeSpeech(this.avail, this.result);
  @override
  Future<void> init() async {}
  @override
  bool get available => avail;
  @override
  Future<void> listen({required void Function(String, bool) onResult, required void Function() onDone}) async {
    if (result != null) onResult(result!, true); // deliver as a FINAL result -> auto-send
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
  Future<void> listen({required void Function(String, bool) onResult, required void Function() onDone}) async =>
      throw StateError('engine boom');
  @override
  Future<void> stop() async {}
  @override
  void cancel() {}
}

class _NullCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s, {Set<String> knownContacts = const {}}) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<String>> generate(String k, String c) async => const CloudError(CloudErrorKind.noKey);
}

/// A cloud whose residual routing blocks until [gate] completes — lets a test hold
/// a turn in flight to observe the busy/disabled UI state deterministically.
class _GatedCloud implements CloudClient {
  final Completer<void> gate;
  _GatedCloud(this.gate);
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(String u, Map<String, Map<String, dynamic>> s, {Set<String> knownContacts = const {}}) async {
    await gate.future;
    return const CloudOk(null); // abstain -> clarify
  }
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String d, {String? priorError}) async =>
      const CloudOk(null);
  @override
  Future<CloudResult<String>> generate(String k, String c) async => const CloudError(CloudErrorKind.noKey);
}

/// Enter text + tap Send + settle. A small helper for multi-turn tests.
Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.text('Send'));
  await tester.pumpAndSettle();
}

String _base(String p) => p.replaceAll('\\', '/').split('/').last;

String _tempData() {
  final tmp = Directory.systemTemp.createTempSync('plenara_ui_');
  for (final sub in const ['types', 'skills']) {
    final dst = Directory('${tmp.path}/$sub')..createSync(recursive: true);
    for (final f in Directory('$sourceDataDir/$sub').listSync().whereType<File>()) {
      f.copySync('${dst.path}/${_base(f.path)}');
    }
  }
  File('$sourceDataDir/corpus.json').copySync('${tmp.path}/corpus.json');
  Directory('${tmp.path}/records').createSync();
  return tmp.path;
}

Session _session() => Session(_tempData(),
    clock: DateTime.parse('2026-07-06T09:00:00'), cloud: _NullCloud());

void main() {
  testWidgets('voice: no mic button when speech is unavailable (default Noop)', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session())));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.mic_none), findsNothing); // typing-only, nothing broken
  });

  testWidgets('voice: tapping the mic transcribes AND auto-sends (hands-free)', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ChatScreen(session: _session(), speech: _FakeSpeech(true, 'add milk to my list'))));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pumpAndSettle();
    expect(find.text('add milk to my list'), findsOneWidget); // user bubble — auto-sent, no Send tap
    expect(find.textContaining('Added'), findsOneWidget); // app responded
    expect(find.widgetWithText(TextField, 'add milk to my list'), findsNothing); // field cleared after send
  });

  testWidgets('voice: a null transcript does NOT auto-send pre-typed text', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ChatScreen(session: _session(), speech: _FakeSpeech(true, null))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'my typed note');
    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'my typed note'), findsOneWidget); // still in the box, not sent
  });

  testWidgets('voice: a transcribe error is caught and the mic returns to idle', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session(), speech: _ThrowSpeech())));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.mic_none), findsOneWidget); // idle icon, not stuck listening
  });

  testWidgets('renders greeting + controls, and responds to a turn', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session(), retrieval: false)));
    await tester.pumpAndSettle();

    expect(find.textContaining("I'm Plenara"), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Send'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'add buy milk to my list');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('add buy milk to my list'), findsOneWidget); // user bubble
    expect(find.textContaining('Added'), findsOneWidget); // response bubble
    expect(find.textContaining('buy milk'), findsWidgets); // in both bubbles
  });

  testWidgets('a past-due reminder shows as an on-open nudge bubble', (tester) async {
    final dir = _tempData();
    // seed a reminder for Thursday 5pm from a Monday clock (persists to `dir`)
    final seeder = Session(dir, clock: DateTime.parse('2026-07-06T09:00:00'), cloud: _NullCloud());
    await seeder.init(retrieval: false);
    await seeder.handle('remind me to call mom on thursday at 5pm');

    // open the app AFTER Thursday — the reminder is now past-due -> a nudge
    final reopened = Session(dir, clock: DateTime.parse('2026-07-10T09:00:00'), cloud: _NullCloud());
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: reopened, retrieval: false)));
    await tester.pumpAndSettle();

    expect(find.textContaining("I'm Plenara"), findsOneWidget); // greeting
    expect(find.textContaining('Reminder: call mom'), findsOneWidget); // the nudge bubble
  });

  testWidgets('an upcoming birthday shows as an on-open nudge bubble', (tester) async {
    final dir = _tempData();
    final seeder = Session(dir, clock: DateTime.parse('2026-07-06T09:00:00'), cloud: _NullCloud());
    await seeder.init(retrieval: false);
    await seeder.handle("Sarah's birthday is july 10"); // in 4 days

    final reopened = Session(dir, clock: DateTime.parse('2026-07-06T09:00:00'), cloud: _NullCloud());
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: reopened, retrieval: false)));
    await tester.pumpAndSettle();

    expect(find.textContaining("Sarah's birthday is in 4 days"), findsOneWidget);
  });

  testWidgets('tapping Send with empty input adds no bubble', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session(), retrieval: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsOneWidget); // only the greeting bubble
  });

  testWidgets('undo from the UI reverses the last turn', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session(), retrieval: false)));
    await tester.pumpAndSettle();

    await _send(tester, 'add buy milk to my list');
    expect(find.textContaining('Added'), findsOneWidget);

    await _send(tester, 'undo that');
    expect(find.textContaining('Undone'), findsOneWidget);
  });

  testWidgets('multi-turn: a task added is then shown (bulleted) by "list my tasks"', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session(), retrieval: false)));
    await tester.pumpAndSettle();

    await _send(tester, 'add buy milk to my list');
    await _send(tester, 'list my tasks');

    expect(find.textContaining('You have 1 task'), findsOneWidget);
    expect(find.textContaining('• buy milk'), findsOneWidget); // the rendered list block
  });

  testWidgets('an unrecognized input gets a graceful reply (no silent failure)', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: _session(), retrieval: false)));
    await tester.pumpAndSettle();

    await _send(tester, 'zxcvbnm qwerty asdf');
    expect(find.textContaining("didn't catch"), findsOneWidget);
  });

  testWidgets('the Send button disables and a progress bar shows while a turn is in flight', (tester) async {
    final gate = Completer<void>();
    final session = Session(_tempData(),
        clock: DateTime.parse('2026-07-06T09:00:00'), cloud: _GatedCloud(gate));
    await tester.pumpWidget(MaterialApp(home: ChatScreen(session: session, retrieval: false)));
    await tester.pumpAndSettle();

    // an unrecognized phrase misses the corpus and reaches the (gated) cloud
    await tester.enterText(find.byType(TextField), 'something the corpus cannot match');
    await tester.tap(find.text('Send'));
    await tester.pump(); // process setState(busy=true); the turn is now stuck on the gate

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send')).onPressed, isNull);

    gate.complete(); // release the turn -> clarify
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send')).onPressed, isNotNull);
    expect(find.textContaining("didn't catch"), findsOneWidget);
  });
}
