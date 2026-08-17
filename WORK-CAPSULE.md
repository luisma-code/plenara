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

## Increment 1 state

- Every persisted field now crosses one total `ValueCodec`: exact decimals, booleans, temporal values, durations, enums, entity references, tags, attachments, JSON, defaults, and cardinality are validated and hydrated consistently.
- `SchemaRegistry` validates built-in and authored schemas, migration-chain continuity, and automation dependency closure before a session can accept work.
- Declarative migrations now take exact backups, advance contiguous versions, restore on failure, and park invalid or future records instead of partially loading them.
- All user, automation, approval, routine, and undo writes pass through the durable device-local `ExecutionCoordinator`. Intent is persisted before mutation, checkpoints permit crash recovery, and undo survives relaunch.
- Targeted undo detects a later edit to the same record and returns a visible conflict instead of clobbering newer data. Corrupt journal bytes are preserved for repair and surfaced through session issues.
- The complete precheck passed after the durable execution work and again after the Today slice below.

## Increment 2 state

- The planner schema now includes task status, scheduled start, estimate, priority, project, area, contacts, notes, and completion time; project and area are first-class record types.
- A deterministic `TodayProjection` creates bounded Now, Next, Later, relationship-nudge, latest-change, and Inbox views across tasks, reminders, routines, dates, and the execution ledger.
- A separate durable product conversation ledger records user-visible exchanges for History. Raw internal beta diagnostics remain enabled exactly as approved; the ledger does not scrub or replace them.
- Flutter has the first living Today board, direct completion through the execution coordinator, persistent reply text alongside speech, and a compact Plena presence when planner state is visible.
- Onboarding, Today, Library, and Settings now share the warm dark Plena identity; onboarding is safe-area/large-text tested and both choices remain reachable on the small-phone fixture. The old Flutter icon is replaced by a generated Plena swarm mark across iOS, macOS, and Windows, with a 16 px legibility check.
- History undo refreshes Today immediately. Storage, schema, migration, execution, and history degradation share a visible bounded repair surface.
- The full gate is green: 1,864 engine tests + 36 skips; 115 Flutter tests + the intentional external-channel skip; tier coverage 94.2% deterministic core / 89.2% product logic / 64.6% transport; macOS build; four macOS real-engine integration tests; external-channel, secret, and 24/60 conformance gates.
- A disposable copy of the real dogfood folder migrated one existing task to schema v3, made one exact rollback backup, and reported zero repair issues. This caught and fixed the legacy `createdAt` timestamp/schema mismatch; live data was never mutated.
- The same four real-engine tests pass on the local iPhone 17 Pro simulator. The iOS harness now reads bundled seed assets rather than assuming a repository working directory. The simulator was shut down and no app/test processes remain.

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
- **Never run tests on the physical iPhone.** All automated, layout, render, motion, and integration verification uses local iPhone simulators. The physical phone is deployment-only, and only for a usable build Luis asked to receive.
- Release environment: `eval "$(/opt/homebrew/bin/brew shellenv)"; export LANG=en_US.UTF-8; export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`

## Hard-won platform facts

- `flutter build ipa` may build the archive and fail its own export for missing Xcode-account signing; `tool/testflight-upload.sh` performs the API-key export/upload path.
- iOS rotates the app container on reinstall. `homeOverride` must be set from Documents before config/log paths are derived.
- iOS Impeller crashes on the old per-frame `toImageSync` trail path; iOS currently omits lingering trail persistence.
- iOS TTS needs the playback audio session reasserted before every utterance.
- `path_provider_foundation` remains pinned to 2.4.1 because a stale Xcode keychain warning corrupts the newer native-assets hook output.
- Any app launched during autonomous verification must have RSS sampled, be killed afterward, and be checked for orphan processes.

## Next implementation order

1. Increment 3: Plan/Library, contextual direct manipulation, in-process retrieval, cloud admission controller.
2. Later increments follow `planning/implementation-plan-2026-08-17.md`; dependencies and evidence gates determine order, not calendar dates.

## Authoritative documents

- `planning/specs/17-living-planner.md` — product information architecture and multimodal rules.
- `planning/specs/11-feedback-diagnostics.md` — sole diagnostic collection/export authority.
- `planning/implementation-plan-2026-08-17.md` — ordered implementation program and acceptance gates.
- `reviews/2026-08-17-*.md` — historical review evidence; do not rewrite their findings after decisions change.
