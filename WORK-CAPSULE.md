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
  - raw audio remains forbidden; internal recognizer hypotheses are retained under Spec 11 because
    they are required to reconstruct native capture failures, while external captures none;
  - AppLog rotates at 30 days or 100 MB, oldest-first.
- Production long-press glyph cycling, tuning, and dev harness are gated from external builds.
- Import lint now fails every unclassified production file; `routines.dart` is classified.
- The false-green existing-contact cloud-route test now asserts the response and stored mood. Its real typed-map crash is fixed by copying cloud slots into an owned `Map<String, dynamic>`.
- Conformance counts are generated from test-runner JSON (`24 pass / 36 skip of 60`) and ratcheted at 24.
- Coverage is enforced by tier, globally, and for unclassified files. Explicit temporary exclusions are only fixture inputs and mixed recorder/replay code; the production in-process retrieval backend is counted product logic.
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

## Increment 3 state

- Task schema v4 represents dependencies, blocked reason, energy, contexts, and recurrence through a contiguous 3→4 migration. A reusable `v0/bin/migration_smoke.dart` operator check installs current built-ins into a disposable copy, runs migration, checks task versions and repairs, proves the configured source folder stayed byte-identical, and removes the copy.
- Built-in installation now runs upgrade-aware on every launch: missing definitions are added to populated folders; legacy unversioned definitions are backed up and normalized as v1 without replacing their content; newer shipped type versions receive exact definition backups before atomic promotion; authored and same-version edited definitions remain untouched.
- Phone Plan has a week strip, agenda, deadlines, unscheduled queue, load/conflicts, direct complete/schedule/defer/resize, and multi-select. Desktop adds week/queue composition and drag-to-day scheduling. Every mutation enters `ExecutionCoordinator` and one durable undo history.
- Today and Plan publish structured planner context. Contextual voice resolves selected and numbered visible ids for “move these…,” “the first one…,” completion, deferral, and resizing rather than scraping UI labels.
- Library now provides purpose-built People, Goals, Routines, Trackers, Journal, Projects & areas, Learned phrases, Automations, and All data entries; the full editable archetype browser remains directly reachable.
- Production routing always builds an in-process 384-dimensional deterministic feature-hash index. A bounded retrieval action lane accepts only high-margin create-task candidates with explicit task/todo cues and deterministic slot extraction; corpus and accepted retrieval routes never call cloud.
- Every Anthropic request crosses one persisted admission controller before HTTP: 200/local-day and 30/rolling-ten-minute defaults. Reservations persist before network use, relaunch cannot reset them, corrupt/unwritable state fails closed, and Settings shows daily/burst counters.
- The full gate is green: 1,877 engine tests + 36 skips; 118 Flutter tests + the intentional internal-build external-channel skip; tier coverage 94.2% deterministic core / 90.3% product logic / 68.1% transport; macOS build; five macOS real-engine integration tests; external-channel, secret, and 24/60 conformance gates.
- The same five real-engine tests pass on the explicitly addressed local iPhone 17 Pro simulator. The small-phone run caught and fixed an off-screen Library test path. RSS was sampled during the short run, which completed normally; this is not a long-soak leak claim. The simulator was shut down and no app/test/build process remains.
- A disposable copy of the real dogfood folder migrated its one real task to schema v4, made one record backup, reported zero repair issues, and proved the live source stayed byte-identical. It also exposed and drove the built-in-upgrade fix above; live data was never mutated.

## Increment 4 state

- One device-local `OperationCenter` persists queued/running/terminal long work, serializes by completion events, delivers results exactly once, supports local cancellation, and marks uncertain relaunch work interrupted instead of risking duplicate provider spend. Today renders live operation progress and cancellation.
- Weekly review and pattern synthesis detach immediately so capture/planning remain usable. Completion/error/token-cost diagnostics are written as operation-completion traces without changing the approved content-bearing internal-log policy.
- Custom capability authoring is detached through the same operation door. A validated preview persists device-locally across relaunch; only `activate` promotes it into live definitions, and cancel/move-on clears it.
- Plan proposals persist selected task moves, rationale, estimates, conflict delta, and explicit blocked/dependency/capacity omissions. Voice can move/exclude numbered items. Apply revalidates fingerprints, then uses one durable execution and undo. The deterministic benchmark passed 10/10 scenarios (gate ≥80%).
- Task schema v5 adds `reviewDecision` through a contiguous 4→5 migration. Structured weekly review cards expose evidence and editable keep/defer/drop decisions; stale reviewed records fail before any write; accepted decisions apply and undo atomically.
- Morning orientation and relationship/event-prep are durable Today artifacts until accepted, dismissed, or superseded. Relationship prep is grounded only in saved facts, birthdays, and the latest logged interaction.
- Every implemented generative assembler declares its allowed record classes and explicit-invocation consent in the outgoing context. Settings renders the same content catalog; a journal canary proves current assemblers never include journal text.
- The full gate is green: 1,904 engine tests + 36 skips; 123 Flutter tests + the intentional external-channel skip; tier coverage 94.2% deterministic core / 90.5% product logic / 68.1% transport; macOS build; five macOS real-engine integration tests; external-channel, secret, and 24/60 conformance gates.
- A disposable real-data copy migrated the one task to schema v5 with one backup, zero repair issues, and byte-identical source. The same five integration tests passed on the explicitly selected local iPhone 17 Pro simulator; RSS was about 504 MB during the short sample, the simulator was shut down, and no app/test process remained.

## Increment 5 state

- Plena now has explicit neutral, clarification, and failure expressions that alter geometry and
  luminance as well as color. The system recognizer feeds normalized live mic level into listening
  energy; the local Whisper path retains the calm no-level fallback.
- OS Reduce Motion and the independent persisted **Still presence** preference both use fixed
  per-state forms with opacity-only transitions. Presence semantics name input mode, muted state,
  and expression.
- Today and Plan use one shared identity-preserving continuity transition for durable objects;
  durations and easing live in `PlenaraMotion`. The permanent 11-frame harness distinguishes a
  correct create transition from a deliberately broken instant insertion and shows monotonic
  growth/fade without disturbing the existing row.
- The 52-glyph corpus remains an internal sketchbook. Production admits 12 consequential marks
  through a fail-closed persisted 90-second/3-per-day gate; routine writes and ordinary actions use
  a sub-300 ms whole-body acknowledgement. Forced preview is internal-channel only.
- Settings and Data carry a Y2 ember, and record detail carries an inline ember. iOS is an explicit
  trail-free tier; no per-frame image-buffer workaround is used there.
- Routine-generated figures render labeled START/FINISH A/B stills. The three animated catalogue
  payloads are decoded to their first frame and held; no unverified tween or looping instructional
  art ships. First-frame loading is generation-guarded when a reused widget changes assets.
- Verification is green: 1,904 engine tests + 36 intentional conformance skips; 134 Flutter tests
  plus the intentional external-channel skip; tier coverage 94.2% deterministic core / 90.5%
  product logic / 68.1% transport; macOS build; five macOS real-engine integration tests; external,
  secret, and 24/60 ratchet gates. The same five integration tests pass on the explicitly selected
  local iPhone 17 Pro simulator. The simulator was shut down and no app/test process remains. No
  physical phone was touched.

## Increment 6 state

- People-linked tasks now carry exact known-person context into Today, Plan, weekly proposals,
  weekly-review evidence, and person detail. Planned interactions and recurring relationship dates
  appear on the selected Plan day; goals and active routines remain visible as distinct rhythms.
- Equal-risk weekly proposal ordering prefers a commitment to a known person, while deadlines and
  explicit priority still outrank it. Voice refinement continues to address the visible proposal
  order, and its regression test no longer encodes the retired generic-first ranking.
- Today derives deterministic overload, stale-queue, and relationship-neglect signals before AI and
  caps the surface at two signals.
- Upcoming relationship dates create stable durable suggestion artifacts. Keep, Dismiss, and
  Tomorrow are explicit; deferral persists and returns when due, and terminal suggestions never
  respawn unchanged. Impressions do not count as engagement.
- The relationship/UI tests distinguish deliberate disabled-output regressions from the restored
  implementation. The complete gate is green: 1,907 engine tests + 36 skips; 138 Flutter tests +
  the intentional external skip; 94.2% deterministic-core / 90.8% product-logic / 68.1%
  transport coverage; macOS build; five macOS real-engine tests; external-channel, secret, and
  24/60 conformance gates. No simulator was booted and no physical phone was touched for this
  increment.

## Increment 7 state

- Settings now distinguishes **Device-local only** from a user-selected location. Desktop uses the system folder chooser; iOS uses a native document-provider folder picker and persists a security-scoped bookmark that is resolved before config on each boot.
- Folder changes copy through a sibling staging directory, validate before switching config, preserve the old root as rollback, adopt a coherent existing Plenara root without overwriting it, and reject partial/unrelated roots.
- Record envelopes now carry write-once `createdAt`, per-device version vectors, field tombstones, HLC receive semantics, and canonical conflict stashes. The pure merge is commutative, associative, and idempotent under 100 randomized three-way schedules.
- Every locally persisted/reconciled record has a device-local observed-state shadow. Provider overwrites and recognized conflict-copy siblings reconcile against it; corrupt/misnamed inputs remain on disk and become repair items.
- Positive file-system events drive live reconciliation. Events that arrive during a turn wait for the durable turn to finish, then update the shared in-memory store, search index, reminders, and planner UI; no polling timer sequences the refresh.
- Today’s repair card opens an inspectable attention view. Record conflicts show current/other values with **Keep current** and undoable **Restore other**; definition conflict copies show both documents and require an explicit choice. Definition conflicts never activate by directory enumeration order.
- New real-filesystem tests cover cold/live bootstrap, concurrent/offline branches, deletion versus update, field removal, provider overwrite recovery, conflict copies, corrupt/interrupted input, definition choice, HLC receive, folder copy/adoption/interruption, and UI conflict recovery. The merge, watcher, and folder-copy tests were calibrated against deliberate broken implementations and turned red.
- An iOS simulator build compiles the security-scoped bookmark bridge. No physical phone was touched.

## Increment 8 state

- Internal content-bearing diagnostics remain enabled exactly as Luis directed. Raw export now previews included filenames, exact payload size, revision, and content classes before opening the share sheet; nothing uploads automatically.
- External policy is compile-time and fail-closed. Logging, export, menu construction/dispatch, tuning, the developer harness, and long-press glyph preview are AOT-tree-shaken. The binary scanner was calibrated against a known content marker and caught the pre-fix harness/tuning strings before both macOS and unsigned iOS AOT artifacts passed.
- Speech recognition now sets the plugin's real `onDevice` option on every platform; on Apple this becomes `requiresOnDeviceRecognition = true`, so unsupported recognition degrades to text rather than a server path.
- iOS/macOS privacy manifests, a public privacy policy, and checked App Store metadata match actual storage, BYOK egress, voice, diagnostics, and tracking behavior. Settings no longer claims all notes “stay private” or predicts a fixed monthly model cost.
- The stock Flutter launch orb is gone. Deterministic Plena launch assets and app icons are generated and pixel-checked together.
- The supported-device/large-text matrix covers five phone/tablet geometries plus 2× text cases. The guard-equipped three-minute real-engine soak samples RSS each second and CPU every ten seconds, aborting on a rising trend; the final measured result is recorded in the release-hardening report.
- Full precheck is green: 1,920 engine tests + 36 skips; 154 Flutter tests + 3 development-channel skips; 94.7% deterministic / 90.1% product / 68.1% transport coverage; macOS build; five real-engine tests; external, secret, and 24/60 gates.
- External promotion uses `tool/external_release_gate.sh`, which builds and inspects macOS and unsigned iOS AOT artifacts and writes the clean revision's channel, artifact SHA-256, app version, schema versions, and migrations to `app/build/release/release-manifest.json`.
- No physical phone was touched. No simulator was booted for this increment; all phone geometry used local widget render surfaces, and the unsigned iOS bundle was compiled but never installed or launched.

## Owner action

- Rotate the Anthropic credential that appeared in a non-hermetic test failure before this increment. The repository/reports do not contain it, but the earlier tool transcript did. Credential rotation requires Luis's account authority.

## Latest phone deployment

- On 2026-08-17 at 17:36 PDT, the task-row/Apple-partial correction was installed on **Aluminum
  Monster**: signed internal-channel `0.12.0 (18)`, revision `c26560f7a149`, bundle
  `com.plenara.plenaraApp`. The verified AOT SHA-256 is
  `031d438eda3c29bdda44b99cd59271a4fd58dabfbdff4ff5a0ea5bd487b5473f`; signature, team,
  provisioning, embedded revision, internal raw diagnostics, both reset surfaces, and absence of an
  API-key pattern were checked before install. Deployment only—no physical-phone launch or test.
- On 2026-08-17 at 17:16 PDT, the phone-diagnostic correction was installed on **Aluminum Monster**: signed internal-channel `0.12.0 (18)`, revision `472587a3c4c8`, bundle `com.plenara.plenaraApp`. The locally verified AOT SHA-256 is `8651797bfe02c173da7cf8de95343869634ed3ca9e67083ca36d958734020723`; code signing, embedded revision, both reset actions, internal diagnostics, and absence of an API-key pattern were checked before install. The first wireless tunnel attempt timed out before installation; CoreDevice returned to paired/available and the retry succeeded. Deployment only—no physical-phone launch or test.
- On 2026-08-17 at 16:49 PDT, the recovery build replaced the earlier install on **Aluminum Monster**: signed internal-channel `0.12.0 (18)`, revision `ecbd0ee`, bundle `com.plenara.plenaraApp`. The locally verified AOT SHA-256 is `3f3491e45c9a1f136714b5f3c5f5c2c4e40feb2f4ab045bc5dda652770ccac8f`; it contains both reset actions and the approved internal-diagnostics canary. Deployment only—no physical-phone launch, test, probe, log collection, or inspection.
- On 2026-08-17 at 16:25 PDT, after Luis explicitly requested a phone deployment, the signed internal-channel iOS release `0.12.0 (18)` from revision `aca107a78a31c04fdcb3a8b99374fe044b9ae06f` was installed wirelessly on **Aluminum Monster** as `com.plenara.plenaraApp`.
- The exact installed source bundle passed local code-signature verification and contained both the internal raw-diagnostics canary and embedded revision. Its AOT binary SHA-256 is `4f41cc46c4ba6f3cfefe769f1e6bed753dc989c9ac9eb1eebe936fca48cf1502`.
- Deployment only: no test, probe, log collection, app inspection, or automated launch ran on the physical phone.

## Post-deployment data recovery state

- The first phone launch reported a data-folder read failure. Startup now has a dedicated **Reset and start fresh** surface, and Settings has **Reset data and start fresh**. Both use `resetDataToDeviceLocal`; there is no second reset implementation.
- Reset clears the iOS security-scoped bookmark and selection flag, never deletes or modifies the provider folder, moves any old device-local root to a timestamped `.reset-backup-*` sibling, preserves credentials/preferences, reseeds, and replaces the failed `Session` in-process.
- The filesystem, Settings callback, and startup surface tests were calibrated with deliberate mutations and each failed. The 320×568/2×-text case caught an offscreen action; recovery now keeps the action in a safe-area footer while details scroll.
- Local iPhone 17 Pro simulator real-engine verification reproduced failure and reached a live fresh Today after the native reset bridge. Six integration cases passed; Runner was about 467 MiB in the short sample and was terminated with the simulator. This is not a long-soak leak claim. No physical phone was used for testing.
- Full precheck is green: 1,920 engine tests + 36 intentional skips; 158 Flutter tests + 3 development-channel skips; 94.7% deterministic / 90.1% product / 68.1% transport coverage; macOS build; six real-engine tests; external, secret, and 24/60 gates.

## Phone-diagnostic startup correction

- After Luis reported that **Start fresh** also failed, he explicitly authorized reading Plenara's phone logs. Only `Documents/plenara-logs` was copied from the app container; the phone was not launched, tested, probed, reset, or otherwise inspected.
- The 16:57 device log proves reset itself succeeded and created timestamped backups. The restarted session then failed because physical iOS rejects Dart recursive `Directory.watch` with “File system watching is not supported on this platform.” The prior launch had a separate failure: custom `back_stretch_session.json` was rejected for missing `schemaVersion`, and its dependent `log_back_stretch` skill then aborted all startup validation.
- `FileStorageRepository` now treats native watch support as a platform capability. Physical iOS returns an empty watch stream and continues to Ready; it reconciles provider changes at cold open until a native document-provider event adapter exists. Specs 01, 04, 06, research, and the implementation plan all state the same limitation; no polling timer was added.
- Session startup now validates each skill before automations and parks only invalid skills as visible repair state. A rejected user-authored type/capability can no longer make unrelated planner capabilities unavailable, and the on-disk definitions remain available for repair.
- Both regression tests were calibrated by disabling the new guard/parking behavior: the watch test timed out and the invalid-capability test reproduced the exact `ResolveError`; both pass restored. Full precheck is green: 1,922 engine tests + 36 skips, 158 Flutter tests + 3 development-channel skips, 94.7% / 90.5% / 68.1% coverage tiers, macOS build, six macOS real-engine tests, secret scan, and 24/60 ratchet.
- A clean local iPhone 17 Pro simulator run passed the exact recovery flow. The production `main()` entrypoint then loaded 17 types / 82 active skills, built retrieval, and logged `reminders reconciled — READY` in 123 ms with neither device failure. Debug RSS stayed in the established bounded range. One run started against a stale already-booted simulator and stalled between animation tests while the Runner was idle and plateaued; after a simulator shutdown/boot, the same two-case boundary passed in 46 seconds. The simulator was shut down and no app/test process remains.

## Phone task/voice incident

- The 17:17 physical-phone diagnostic trace was copied read-only after Luis reported the failure; no
  phone launch or test occurred. It shows that tapping the `pack clothes` row reached Today’s
  background voice gesture, then Apple produced visible partial words followed by native `done`
  without an engine-final result. There was no crash.
- The first diagnostic correction made the entire task row complete so it could not bubble into
  voice. Luis correctly found that hidden completion contract unclear. The current rule supersedes
  it: the task body opens the shared editable record sheet (signaled by a chevron); only the explicit
  leading circle completes. Both controls consume their gesture before Today’s background voice
  target.
- Recognition now retains the latest Apple partial alongside completed segments. Native `done`,
  error, watchdog stop, and `stop()` completion converge on one idempotent finalization door; the
  fixed 350 ms guess is removed. Any real words flush exactly once, while explicit cancel remains
  the only discard path.
- The focused 44-test speech/Today/widget set passes. Both new guards were calibrated: dropping the
  Apple partial made the exact transcript test fail with no emissions; removing the row action left
  the task in `today` and made the exact widget test fail. The real-render integration guard was
  independently calibrated against the same removed row action and failed on the local simulator.
- Final-tree precheck is green: 1,922 engine tests + 36 skips; 161 Flutter tests + 3 development
  skips; 94.7% / 90.5% / 68.1% coverage tiers; macOS build; seven macOS real-engine cases; external,
  secret, and 24/60 conformance gates. All seven cases also passed on the local iPhone 17 Pro
  simulator, including title → detail editor, circle → completion feedback, and zero speech calls.
  The simulator guard failed against the deliberately restored whole-row completion behavior, then
  passed restored. RSS rose from about 529 MiB to a roughly 558 MiB plateau during the short run;
  the run ended normally, the simulator was shut down, and no app/test orphan remains. This is not
  a long-soak leak claim.
- The diagnostic trace also proved the old cross-doc “interim transcripts are forbidden in every
  channel” restatement was stale. Spec 11 v0.4 is the sole authority: internal dogfood may retain
  recognizer hypotheses for post-hoc diagnosis; external captures none; raw audio and secrets stay
  forbidden everywhere. Research, Voice, Security, the implementation plan, and this capsule now
  point to that boundary. The corrected signed build was installed deployment-only at 17:36 PDT.

## Live commands

- Keep awake: `pgrep -x caffeinate || nohup caffeinate -dimsu >/dev/null 2>&1 &`
- Full gate: `bash tool/precheck.sh`
- External-channel policy gate: `cd app && flutter test --dart-define=PLENARA_CHANNEL=external test/external_channel_test.dart`
- Compiled external promotion gate: `bash tool/external_release_gate.sh`
- Explicit three-minute local soak: `cd app && flutter test integration_test/release_soak_test.dart -d macos --dart-define=PLENARA_CHANNEL=external`
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
- Flutter does not support iOS release mode for simulators. External phone-shaped behavior stays on simulator/widget renderers; release AOT inspection uses a local unsigned `flutter build ios --release --no-codesign` and never installs or launches it.
- Any app launched during autonomous verification must have RSS sampled, be killed afterward, and be checked for orphan processes.

## Implementation queue

- The eight-increment review plan, phone-diagnostic startup correction, and task-row/Apple-partial
  correction are complete. The follow-up task-row clarity change is also implemented and verified:
  body → shared detail editor, explicit circle → complete, neither → voice. The full gate and seven
  local-iPhone-simulator cases pass; the old whole-row-completes behavior made both widget and
  simulator guards fail as intended. Revision `c26560f7a149` remains on the deployment-only physical
  phone; this follow-up has not been installed because Luis did not request another phone deployment.

## Authoritative documents

- `planning/specs/17-living-planner.md` — product information architecture and multimodal rules.
- `planning/specs/11-feedback-diagnostics.md` — sole diagnostic collection/export authority.
- `planning/implementation-plan-2026-08-17.md` — ordered implementation program and acceptance gates.
- `reviews/2026-08-17-*.md` — historical review evidence; do not rewrite their findings after decisions change.
