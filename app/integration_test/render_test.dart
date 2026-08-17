// Real-device (real engine + GPU) render smoke. This is the ONE place the animated presence
// actually rasterizes: the mote swarm, the comet-trail ping-pong offscreen buffer (toImageSync),
// the veilYield corner transition, and a glyph flight all run for real here. Headless flutter_test
// builds PresenceView with animate:false (an ever-moving swarm never lets pumpAndSettle terminate),
// so it never touches this path — which is exactly how the list-reply raster crash shipped
// (resizing the widget reallocated the trail buffer mid-animation → native crash).
//
// Run: flutter test integration_test/render_test.dart -d macos
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:plenara/claude.dart';
import 'package:plenara/config.dart';
import 'package:plenara/session.dart';
import 'package:plenara_app/credential_store.dart';
import 'package:plenara_app/glyphs.dart';
import 'package:plenara_app/main.dart';
import 'package:plenara_app/plena.dart';
import 'package:plenara_app/seed_assets.dart';

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

Future<Session> _session() async {
  final root = Directory.systemTemp.createTempSync('plenara_it_');
  final data = Directory('${root.path}/data')..createSync();
  final device = Directory('${root.path}/device')..createSync();
  ensureSeeded(data.path, await extractSeedAssets());
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  return Session(
    data.path,
    deviceDir: device.path,
    clock: DateTime.parse('2026-07-06T09:00:00'),
    cloud: _NullCloud(),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> runFrames(WidgetTester tester, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  // Re-pumping the SAME widget structure preserves PresenceView's State (Element reuse), so
  // yieldTarget changes flow through didUpdateWidget and the veilYield smoothing animates — the
  // real corner transition, not a fresh mount.
  Widget harness(
    double yieldTarget, {
    GlyphDef? glyph,
    int nonce = 0,
  }) => MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF0A0908),
      body: PresenceView(
        state: PresenceState.speaking,
        animate:
            true, // the REAL ticker + trail buffer — the whole point of this test
        yieldTarget: yieldTarget,
        glyph: glyph,
        glyphNonce: nonce,
      ),
    ),
  );

  testWidgets(
    'animated presence yields to the corner + flies a glyph without a raster crash',
    (tester) async {
      await tester.pumpWidget(harness(0));
      await runFrames(tester, 30);
      // Ease to the corner AND fire a glyph — the exact list-reply moment that used to crash.
      await tester.pumpWidget(harness(1, glyph: kGlyphs['check'], nonce: 1));
      await runFrames(tester, 50);
      await tester.pumpWidget(harness(0));
      await runFrames(tester, 30);
      // Toggle a few more times quickly — stress the transition + buffer reuse.
      for (var i = 0; i < 4; i++) {
        await tester.pumpWidget(
          harness(i.isEven ? 1 : 0, glyph: kGlyphs['heart'], nonce: 2 + i),
        );
        await runFrames(tester, 12);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a real list-reply turn renders with the presence ANIMATING and does not crash',
    (tester) async {
      // forceAnimate:true drives the real animated raster while a real (offline) turn runs — the
      // end-to-end path a "list my tasks" reply takes: reply → _displayIsList → yieldTarget → the
      // animated presence eases to the corner and the trail buffer rasterizes.
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(session: await _session(), forceAnimate: true),
        ),
      );
      await runFrames(tester, 30); // init + live Today projection
      expect(find.byKey(const Key('today-board')), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'add buy milk to my list');
      await tester.tap(find.text('Send'));
      await runFrames(tester, 20);

      await tester.enterText(find.byType(TextField), 'list my tasks');
      await tester.tap(find.text('Send'));
      await runFrames(
        tester,
        80,
      ); // let the yield + trail buffer rasterize a real list reply

      expect(tester.takeException(), isNull);
      expect(find.textContaining('buy milk'), findsWidgets);
    },
  );

  // Resize-crash guard (kept in THIS file, not a separate one: running multiple integration_test
  // files back-to-back on macOS flakes on app relaunch — one file, one launch, is reliable). The
  // ORIGINAL shipped crash was the presence widget being RESIZED mid-animation, reallocating the
  // trail buffer; the veilYield redesign stopped resizing the widget, but this holds the line.
  testWidgets(
    'resizing the animated presence mid-flight never crashes the raster',
    (tester) async {
      Widget sized(double w, double h) => MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0A0908),
          body: Center(
            child: SizedBox(
              width: w,
              height: h,
              child: const PresenceView(
                state: PresenceState.speaking,
                animate: true,
              ),
            ),
          ),
        ),
      );
      const sizes = <List<double>>[
        [420, 320],
        [700, 520],
        [180, 140],
        [900, 680],
        [260, 900],
        [900, 200],
        [420, 320],
      ];
      await tester.pumpWidget(sized(sizes.first[0], sizes.first[1]));
      await runFrames(tester, 30);
      for (final s in sizes.skip(1)) {
        await tester.pumpWidget(sized(s[0], s[1]));
        await runFrames(tester, 30);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('native secure storage really round-trips and deletes', (
    tester,
  ) async {
    final store = PlatformCredentialStore(
      key: 'plenara_integration_test_credential',
    );
    addTearDown(store.deleteApiKey);

    await store.deleteApiKey();
    expect(await store.readApiKey(), isNull);
    await store.writeApiKey('integration-fixture-value');
    expect(await store.readApiKey(), 'integration-fixture-value');
    await store.deleteApiKey();
    expect(await store.readApiKey(), isNull);
  });
}
