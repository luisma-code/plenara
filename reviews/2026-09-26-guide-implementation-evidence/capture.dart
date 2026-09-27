// Production implementation capture with synthetic data; no paid model calls.
// From repo root: copy this file to app/test/guide_capture.dart,
// then run: cd app && flutter test test/guide_capture.dart
// Remove the temporary test copy afterward. Uses installed Flutter font paths.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:plenara_app/speech.dart';
import 'package:plenara_app/plenara_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/session.dart';
import 'package:plenara/guide.dart';
import 'package:plenara_app/guide_view.dart';
import 'package:plenara/people.dart';
import 'package:plenara_app/main.dart';

class _NoCloud implements CloudClient {
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
    String utterance,
    Map<String, Map<String, dynamic>> skills, {
    Set<String> knownContacts = const {},
  }) async => const CloudOk(null);

  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(
    String description, {
    String? priorError,
  }) async => const CloudOk(null);

  @override
  Future<CloudResult<String>> generate(String kind, String context) async =>
      const CloudError(CloudErrorKind.noKey);
}

String _base(String path) => path.replaceAll('\\', '/').split('/').last;

Future<Session> _session() async {
  final seed = '${Directory.current.path}/assets/seed';
  final temp = Directory.systemTemp.createTempSync('plenara_three_pillars_');
  for (final sub in const ['types', 'skills']) {
    final destination = Directory('${temp.path}/$sub')
      ..createSync(recursive: true);
    for (final file in Directory('$seed/$sub').listSync().whereType<File>()) {
      file.copySync('${destination.path}/${_base(file.path)}');
    }
  }
  File('$seed/corpus.json').copySync('${temp.path}/corpus.json');
  Directory('${temp.path}/records').createSync();
  addTearDown(() => temp.deleteSync(recursive: true));
  final session = Session(
    temp.path,
    clock: DateTime.parse('2026-09-06T10:00:00'),
    cloud: _NoCloud(),
  );
  await session.init(retrieval: false);
  return session;
}

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

void main() {
  testWidgets('capture production roots with synthetic data', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final entry in {
        'Roboto':
            '/opt/homebrew/share/flutter/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf',
        'MaterialIcons':
            '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(
            Future.value(
              ByteData.sublistView(File(entry.value).readAsBytesSync()),
            ),
          );
        await loader.load();
      }
    });
    final s = await _session();
    await s.createRecord('contact', {
      'displayName': 'Alex',
      ...relationshipPresetFields(RelationshipPreset.closeLocalFriend),
    }, description: 'synthetic review person');
    await s.handle('add task Book the dentist');
    await s.createRecord('habit', {'title':'Walk outside', 'createdAt':'2026-09-01T10:00:00','targetPerWeek':3,'preferredDays':'7','cue':'After lunch','normalVersion':'Ten minutes outside','minimumVersion':'Two minutes','reason':'Clear my head'});
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: PlenaraTheme.dark,
          home: ChatScreen(session: s, speech: _FakeSpeech(true, null)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> snap(String name) async {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await boundary.toImage(pixelRatio: 2);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        img.dispose();
        File(
          '../reviews/2026-09-26-guide-implementation-evidence/$name.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await snap('01-today');
    await tester.tap(find.widgetWithText(NavigationDestination,'People'));
    await tester.pumpAndSettle();
    await snap('02-people');
    await tester.tap(find.widgetWithText(NavigationDestination,'Routines'));
    await tester.pumpAndSettle();
    await snap('03-routines');
    await tester.tap(find.byKey(const Key('message-plena')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('plena-message-input')),'Had lunch with Alex yesterday. I promised to send the guide.');
    await tester.pump();
    await snap('04-conversation');
    s.guideReceipt = GuideReceipt('Your follow-up', [{'operation':'create','type':'task','id':'new:followup','reason':'You promised to send the guide','fields':{'description':'Send Alex the neighborhood guide','contactRefs':[s.store.values.firstWhere((r)=>r['typeId']=='contact')['id']]}}], {});
    await tester.pumpWidget(RepaintBoundary(key:key,child:MaterialApp(debugShowCheckedModeBanner:false,theme:PlenaraTheme.dark,home:GuideConversationView(session:s))));
    await tester.pumpAndSettle();
    await snap('05-receipt');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
