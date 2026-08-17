# Plenara external-release hardening verification

Date: 17 August 2026
Scope: implementation-plan Increment 8 and final cross-review release boundary

## Verdict

External-release hardening is implemented. Internal dogfood keeps the
content-bearing diagnostics Luis explicitly approved; external builds compile
without raw logging/export, tuning, the developer harness, or the long-press
glyph cycle. The promotion gate inspects actual macOS and unsigned iOS AOT
artifacts and generates a revision-bound manifest rather than treating a widget
policy test as binary proof.

No physical phone was selected, installed to, launched, inspected, or cleaned.
Phone-shaped layout and accessibility checks used local widget render surfaces.
The iOS release artifact was compiled locally with code signing disabled and was
never deployed.

## Product and privacy corrections

- One compile-time `isExternalBuild` boundary now guards logging, raw export,
  menu construction, menu dispatch, and the glyph preview gesture. Release AOT
  tree shaking therefore removes the internal implementation, not only its
  visible controls.
- Internal **Share raw diagnostics** still includes real exchanges and record
  values. It now shows the included filenames, exact payload size, revision,
  content warning, and share-sheet consequence before the user can continue.
- External startup captures no raw log, exports none, and purges inherited raw
  files. An injected internal policy cannot override the compile boundary.
- The settings claim that notes “stay private” and cloud typically costs “a few
  cents a month” was replaced with the actual boundary: requested cloud features
  send disclosed text/record categories to Anthropic and cost varies by use.
- The Apple speech plugin had been left at its server-capable default despite the
  spec's on-device-only rule. The one options builder now sets `onDevice: true`;
  Apple maps that to `requiresOnDeviceRecognition = true` and failure degrades to
  text instead of server recognition.
- iOS and macOS now ship privacy manifests declaring no tracking, optional
  app-functionality user-content processing, app-only `UserDefaults`, and file
  metadata access for app-container and explicitly selected folders. The public
  [privacy policy](../../PRIVACY.md) and
  [App Store metadata](../app-store-metadata.json) describe the same behavior.
- Flutter's stock blue launch orb was replaced by deterministic Plena-derived
  launch art. The existing Plena app icon and the launch image now share the warm
  dark identity and have pixel-level regression checks.
- Both repository READMEs were rewritten from stale Flutter/desktop scaffolding
  to the current iPhone-first living-planner architecture, secure credential
  path, data-folder model, and physical-phone rule.

Apple's current guidance requires a bundled `PrivacyInfo.xcprivacy` and approved
reasons for covered APIs; the implemented entries follow the official
[privacy-manifest](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
and [required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
documentation. App Store Connect also requires public privacy details; the
metadata follows Apple's [App privacy reference](https://developer.apple.com/help/app-store-connect/reference/app-privacy/).

## Calibrated verification

The new gates were shown known-bad and known-good states before being trusted:

- The compiled-binary scanner rejected an injected
  `PLENARA_INTERNAL_RAW_CONTENT_CANARY`. Before the final reachability fix, it
  also found real `Dev harness` and `Tune Plena` strings in an external AOT
  build; after the menu dispatch and construction references were compile-gated,
  both macOS and iOS AOT binaries were clean.
- The soak analyzer rejects a steadily rising 8 MiB/sample series and accepts a
  bounded plateau with GC sawteeth. The live soak reevaluates every 15 seconds
  after warm-up and aborts immediately if both upward slope and trailing growth
  indicate ballooning.
- The speech regression test reads the actual options object and fails if either
  Apple or other-platform recognition loses `onDevice: true`.
- The launch-art test reads shipped PNG pixels and fails the old blue Flutter
  placeholder as well as transparent or illegible icon output.

## Verification results

### Complete project gate

`bash tool/precheck.sh` passed after its ordinary integration invocation was
narrowed to the explicit `render_test.dart` target:

- 1,920 pure-Dart engine tests passed; 36 intentional Spec 05a cases skipped;
- deterministic-core coverage 94.7%, product-logic coverage 90.1%, transport
  coverage 68.1%;
- 154 Flutter widget/render tests passed; 3 external-only cases skipped in the
  ordinary development-channel run;
- all 3 external-channel policy/reachability tests passed under the external
  compile define;
- macOS debug build passed;
- all 5 normal real-engine/GPU/native-secure-storage integration tests passed;
- seed synchronization, layer import classification, RGBA verifier,
  per-frame-shader guard, tracked-secret scan, and the 24/60 conformance ratchet
  passed.

The first full-gate attempt found that a skipped soak inside `integration_test/`
still caused Flutter to launch a second app and hit the known macOS foreground
failure. The ordinary gate was narrowed to its explicit five-test
`render_test.dart` target; the soak remains a separately invoked integration
target. The entire gate was rerun from the beginning. This was a diagnosed
harness bug, not a rerun accepted as evidence.

### Device and accessibility matrix

The real onboarding widget rendered without overflow and kept both decisions
visible at 320×568, 393×852, 430×932, 852×393, and 768×1024. The small-phone and
tablet cases also passed at 2× text scaling. Plena exposes an image semantic label;
existing planner semantics, Reduce Motion, still-presence, visible captions, and
complete text-mode checks remained green.

### Resource soak

The guard-equipped three-minute animated-presence soak completed 180 one-second
RSS samples and 18 CPU samples on the local macOS real engine: 294.9 MiB peak,
3.1 MiB final-window spread, 3.6 MiB trailing growth, 0.051 MiB/sample trailing
slope, and 4.4% average CPU. A second invocation through the separated target
also passed at 216.3 MiB peak and 2.4% average CPU. A three-minute plateau is evidence against the known
rapid ballooning class, not a claim that an hours-long slow leak is impossible.
CPU is the local energy proxy; physical-phone battery measurement is deliberately
not claimed because the phone is deployment-only.

### Compiled release artifacts

- macOS external AOT build: 134.4 MB app bundle; bundled privacy manifest valid;
- unsigned iOS external AOT build: 58.9 MB app bundle; bundled privacy manifest
  valid;
- both AOT binaries contain the external diagnostics-disabled copy and contain
  none of the raw-content canary, raw-export action, raw warning, tuning sheet,
  or developer harness markers;
- the promotion script records external channel, git revision, app version,
  artifact SHA-256, every shipped type schema version, and migration chains in
  `app/build/release/release-manifest.json`. Its migration validator was
  calibrated against and rejected the initial malformed `null→null` output;
  the final manifest records the contiguous task chain `1→2→3→4→5`.

## Deliberate boundary

No signed archive was uploaded to App Store Connect and no build was installed on
a physical phone. Uploading changes external state and requires an explicit
deployment request; it is not part of local verification. Real iCloud/OneDrive/
Google Drive behavior on a fresh physical device likewise remains an owner-use
observation under the deployment-only rule, not a reason to violate that rule.
