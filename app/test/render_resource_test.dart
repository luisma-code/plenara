// P0 leak net (Fable's review) — a HEADLESS, DETERMINISTIC resource-lifecycle audit over the REAL
// animated presence. The presence renders every frame via a ping-pong trail buffer that creates a
// ui.Picture + a ui.Image per frame; if disposal regresses (the class already seen once: a per-frame
// Picture that wasn't disposed), live counts grow with frame count. dart:ui Picture/Image ARE
// instrumented for FlutterMemoryAllocations in the pinned SDK, so we can assert bounded live counts
// in plain `flutter test` on every OS — no display, no GPU, no timing. `tester.pump(fixed step)`
// runs paint() (incl. toImageSync), so the churn happens headlessly.
//
// NOTE (Shader class): a per-frame ui.Gradient is NOT instrumented and was the real prior leak —
// that's now fixed by removing the per-frame shader (the aura draws the cached sprite). The native
// residual (a reintroduced shader) is guarded by the real-GPU soak in integration_test/soak_test.dart.
//
// MUTATION-VALIDATED: temporarily removing `pic.dispose()` in plena.dart makes this test go red.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/glyphs.dart';
import 'package:plenara_app/plena.dart';

void main() {
  const step = Duration(microseconds: 16667); // one 60 Hz substep per pump — deterministic sim

  testWidgets(
    'animated presence holds bounded live Pictures/Images over sustained frames (no per-frame leak)',
    (tester) async {
      var livePictures = 0, liveImages = 0, maxPictures = 0, maxImages = 0;
      void listener(ObjectEvent e) {
        final o = e.object;
        final d = e is ObjectCreated ? 1 : (e is ObjectDisposed ? -1 : 0);
        if (o is ui.Picture) {
          livePictures += d;
          if (livePictures > maxPictures) maxPictures = livePictures;
        } else if (o is ui.Image) {
          liveImages += d;
          if (liveImages > maxImages) maxImages = liveImages;
        }
      }

      FlutterMemoryAllocations.instance.addListener(listener);
      addTearDown(() => FlutterMemoryAllocations.instance.removeListener(listener));

      Widget host(int nonce) => Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(), // disableAnimations=false → the real ticker runs
          child: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: PresenceView(
                key: const ValueKey('plena'), // stable → a nonce bump fires a glyph via didUpdate
                state: PresenceState.speaking, // the busiest state
                glyph: kGlyphs['heart'],
                glyphNonce: nonce,
              ),
            ),
          ),
        ),
      );

      // ~480 sustained frames, including two glyph flights and the yield transition surface, so the
      // trail buffer, glyph deposits, and the corner-ease path all churn.
      await tester.pumpWidget(host(0));
      for (var i = 0; i < 120; i++) {
        await tester.pump(step);
      }
      await tester.pumpWidget(host(1)); // fire a glyph
      for (var i = 0; i < 240; i++) {
        await tester.pump(step);
      }
      await tester.pumpWidget(host(2)); // and another
      for (var i = 0; i < 120; i++) {
        await tester.pump(step);
      }

      // Per frame the trail path creates+disposes one Picture and ping-pongs one Image, so at rest
      // live Pictures net to ~0 and live Images to the invariant set (sprite + trail). A per-frame
      // leak over ~480 frames would push these into the hundreds — the bound below catches it with
      // enormous headroom while tolerating a couple of in-flight objects.
      expect(
        livePictures,
        lessThan(8),
        reason: 'live Pictures=$livePictures (peak $maxPictures) after ~480 frames — per-frame Picture leak?',
      );
      expect(
        liveImages,
        lessThan(8),
        reason: 'live Images=$liveImages (peak $maxImages) after ~480 frames — Image ping-pong leak?',
      );
    },
  );

  testWidgets(
    'a backgrounded app suspends the presence — zero frames, zero churn (Spec 15 §9.1)',
    (tester) async {
      var createdPictures = 0;
      void listener(ObjectEvent e) {
        if (e is ObjectCreated && e.object is ui.Picture) createdPictures++;
      }

      FlutterMemoryAllocations.instance.addListener(listener);
      addTearDown(() => FlutterMemoryAllocations.instance.removeListener(listener));

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(),
            child: Center(
              child: SizedBox(
                width: 400,
                height: 400,
                child: PresenceView(state: PresenceState.speaking),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(step);
      }
      expect(createdPictures, greaterThan(0), reason: 'the visible presence should be churning frames');

      // Background the app → the director must suspend (the painter only repaints on ticker ticks).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(step);
      final atPause = createdPictures;
      for (var i = 0; i < 60; i++) {
        await tester.pump(step);
      }
      expect(
        createdPictures,
        atPause,
        reason: 'a hidden app produced ${createdPictures - atPause} new frames — it should render ZERO',
      );

      // Foreground again → it resumes.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 30; i++) {
        await tester.pump(step);
      }
      expect(createdPictures, greaterThan(atPause), reason: 'resuming should restart the animation');
    },
  );

  testWidgets(
    'walking away (no input) suspends the presence; any input resumes it — the overnight guard',
    (tester) async {
      // THE incident: the app was left FRONTMOST, the Mac idled, the DISPLAY slept — and
      // AppLifecycleState never changes on display-sleep, so she kept rendering frames that could
      // never be presented, until system RAM was exhausted. Idleness is the signal lifecycle can't
      // give us, so no input for a few minutes ⇒ suspend.
      var createdPictures = 0;
      void listener(ObjectEvent e) {
        if (e is ObjectCreated && e.object is ui.Picture) createdPictures++;
      }

      FlutterMemoryAllocations.instance.addListener(listener);
      addTearDown(() => FlutterMemoryAllocations.instance.removeListener(listener));

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(),
            child: Center(
              child: SizedBox(
                width: 400,
                height: 400,
                child: PresenceView(state: PresenceState.speaking),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(step);
      }
      expect(createdPictures, greaterThan(0), reason: 'an active presence should be churning frames');

      // No pointer/key input for longer than the idle timeout → she suspends.
      await tester.pump(const Duration(minutes: 4));
      await tester.pump(step);
      final atIdle = createdPictures;
      for (var i = 0; i < 60; i++) {
        await tester.pump(step);
      }
      expect(
        createdPictures,
        atIdle,
        reason:
            'an idle (walked-away) app rendered ${createdPictures - atIdle} frames — it must render '
            'ZERO, or it will balloon while the display sleeps',
      );

      // Any input brings her straight back.
      await tester.tapAt(const Offset(20, 20));
      for (var i = 0; i < 30; i++) {
        await tester.pump(step);
      }
      expect(
        createdPictures,
        greaterThan(atIdle),
        reason: 'input should resume the animation immediately',
      );
    },
  );
}
