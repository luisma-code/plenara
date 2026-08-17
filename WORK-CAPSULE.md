# Plenara — Work Capsule

_Current working memory. Last updated 2026-08-17 during approved implementation of the full review plan._

## Product direction

- Spec 17 now owns the product model: **Today / Plan / Library + durable conversation/action ledger + global Plena**.
- Voice remains free-form, global, and capable of every core outcome. It is no longer forced to carry persistent planner state, comparison, sequencing, or precision editing alone.
- Plena scales full-screen at empty rest/deep conversation, compact beside Today/Plan, and ember-sized on detail surfaces.
- Atomic reversible actions act/show/describe. Exploratory or multi-record planning creates an inspectable proposal.
- Current truth is never made ephemeral to preserve visual minimalism.

## Increment 0 state

- Config tests are hermetic: explicit config paths do not inherit the developer shell; precheck clears credential/config environment variables.
- Flutter credentials use one `CredentialStore` backed by platform secure storage. iOS uses Keychain; unsigned macOS dogfood uses the native login Keychain through `/usr/bin/security` because the plugin data-protection path requires a provisioning profile; the native round-trip/delete integration test passes. Legacy plaintext migrates only after verified read-back, then clears atomically. Internal/external ignore `ANTHROPIC_API_KEY`; development may use it for the process lifetime without persisting it.
- Diagnostics use compile-time `BuildChannel`: `development`, `internal`, `external`.
  - development/internal retain content-bearing logs and manual **Share raw diagnostics** export;
  - external writes no raw content, exposes no raw export, and purges raw `.log` files inherited from an internal installation;
  - no automatic uploader exists;
  - secrets are rejected before serialization in every channel;
  - raw audio/interim transcripts remain forbidden;
  - AppLog rotates at 30 days or 100 MB, oldest-first.
- Production long-press glyph cycling, tuning, and dev harness are gated from external builds.
- Import lint now fails every unclassified production file; `routines.dart` is classified.
- The false-green existing-contact cloud-route test now asserts the response and stored mood. Its real typed-map crash is fixed by copying cloud slots into an owned `Map<String, dynamic>`.
- Conformance counts are generated from test-runner JSON (`24 pass / 36 skip of 60`) and ratcheted at 24.
- Coverage is enforced by tier, globally, and for unclassified files. Explicit temporary exclusions: `fixture_inputs.dart`, localhost `embed.dart`, and mixed recorder/replay `replay_cloud.dart` pending the retrieval/replay split.
- The glyph contact-sheet harness now alpha-composites RGBA frames onto the actual `#0A0908` ground; its transparent-pixel test was calibrated against the old false-color conversion.
- MSIX package version is derived from pubspec instead of a stale duplicate.
- Verification is green: the complete precheck passed twice (ordinary shell and hostile parent config/credential environment), the native macOS Keychain test passed, and an internal-channel iOS simulator build succeeded. Launched integration apps plateaued during short samples and all app/helper/orphan processes were removed; this is not a long-soak leak claim.

## Owner action

- Rotate the Anthropic credential that appeared in a non-hermetic test failure before this increment. The repository/reports do not contain it, but the earlier tool transcript did. Credential rotation requires Luis's account authority.

## Live commands

- Keep awake: `pgrep -x caffeinate || nohup caffeinate -dimsu >/dev/null 2>&1 &`
- Full gate: `bash tool/precheck.sh`
- External-channel policy gate: `cd app && flutter test --dart-define=PLENARA_CHANNEL=external test/external_channel_test.dart`
- Generated conformance: `cd v0 && dart run bin/conformance_count.dart`
- Contact-sheet verifier: `python3 -m unittest app/tool/test_gesture_contact_sheet.py`
- TestFlight internal builds must use `--dart-define=PLENARA_CHANNEL=internal`; external/release builds use `external` or the release fail-closed default.
- iPhone: Aluminum Monster, `00008140-000645442862201C`, bundle `com.plenara.plenaraApp`, team `7V63BZ39HU`.
- Release environment: `eval "$(/opt/homebrew/bin/brew shellenv)"; export LANG=en_US.UTF-8; export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`

## Hard-won platform facts

- `flutter build ipa` may build the archive and fail its own export for missing Xcode-account signing; `tool/testflight-upload.sh` performs the API-key export/upload path.
- iOS rotates the app container on reinstall. `homeOverride` must be set from Documents before config/log paths are derived.
- iOS Impeller crashes on the old per-frame `toImageSync` trail path; iOS currently omits lingering trail persistence.
- iOS TTS needs the playback audio session reasserted before every utterance.
- `path_provider_foundation` remains pinned to 2.4.1 because a stale Xcode keychain warning corrupts the newer native-assets hook output.
- Any app launched during autonomous verification must have RSS sampled, be killed afterward, and be checked for orphan processes.

## Next implementation order

1. Increment 1: SchemaRegistry, total ValueCodec, real migrations, durable ExecutionCoordinator/journal, restart-safe targeted undo.
2. Increment 2: first useful Today slice, durable ledger, minimal planner schema, onboarding/icon/identity coherence.
3. Increment 3: Plan/Library, contextual direct manipulation, in-process retrieval, cloud admission controller.
4. Later increments follow `planning/implementation-plan-2026-08-17.md`; dependencies and evidence gates determine order, not calendar dates.

## Authoritative documents

- `planning/specs/17-living-planner.md` — product information architecture and multimodal rules.
- `planning/specs/11-feedback-diagnostics.md` — sole diagnostic collection/export authority.
- `planning/implementation-plan-2026-08-17.md` — ordered implementation program and acceptance gates.
- `reviews/2026-08-17-*.md` — historical review evidence; do not rewrite their findings after decisions change.
