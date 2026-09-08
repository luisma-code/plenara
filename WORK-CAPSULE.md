# Plenara — Work Capsule

_Current working memory. Last updated 2026-09-08 for progressive project instructions._

## Progressive project instructions (2026-09-08)

- Root `AGENTS.md` is now a small always-loaded router rather than a restatement of product,
  architecture, storage, diagnostics, UI, verification, and deployment rules. It retains only the
  product purpose, authority map, task-to-skill routing, physical-phone boundary, and completion
  gate.
- `WORK-CAPSULE.md` is no longer mandatory end-to-end startup reading. Agents list its headings and
  read only the current-state, platform, deployment, or verification sections relevant to their
  task.
- The new `plenara-product-development` skill owns conditional orientation for product behavior,
  architecture, schemas, storage/sync, routing, privacy, voice, and UI work. The existing
  documentation, simulator-verification, and phone-deployment skills remain focused on their own
  workflows.
- `tool/doc_consistency.dart` now guards the root instruction budget, rejects the retired blanket
  capsule-loading rule, requires all four routed project skills, and validates the new skill.
- Calibration restored the actual blanket capsule-loading instruction and produced its named guard
  failure. A second red run broke the new root route and skill folder/name match and named both
  defects. The scoped rule and skill identity were then restored. The official skill validator
  passes all four project skills, and the new `agents/openai.yaml` parses with its expected
  invocation prompt.
- The first full gate caught a real text-mode planner obstruction: at maximum scroll, the Plan chip
  still ended at y=444.22 while the raised input bar required it above y=429. The planner now uses
  the same 168-point trailing clearance as caption lists whenever text input is raised, and the
  integration assertion reports both surface geometry and scroll extent. The focused real-engine
  case then passed; its short macOS sample reached roughly 388 MiB RSS, exited normally, and left no
  app/test process. This is cleanup evidence, not a leak claim.
- Final full precheck is green: 2,065 engine tests + 36 intentional skips; 203 Flutter tests + 4
  channel skips; 95.7% deterministic-core, 89.5% product-logic, and 83.8% transport coverage;
  analyzers, seed sync, documentation consistency, import layering, render guards,
  external-channel checks, macOS build, eight real-engine cases, secret scan, and the 24/60
  conformance ratchet. The full real-engine run moved from roughly 377 to 510 MiB while loading its
  eight surfaces, completed normally, and left no app/test process; it is not a long-soak leak
  claim.

## Proximity-aware Relationships (2026-09-07)

- Proximity was already a stored independent descriptor and already influenced due-contact copy,
  but it was buried in person detail. The Relationships home now exposes a second combinable facet:
  **Local**, **Remote**, **Household**, or **Not set**, with membership and due counts scoped by the
  selected relationship circle. Rows identify both axes explicitly.
- Each row's **Organize** menu and the multi-select Organize sheet can change either circle or
  proximity through the engine's durable undo path. Bulk proximity changes are one atomic execution
  and preserve circle, tracking switches, cadence inheritance, and custom goal overrides.
- Local/Household due guidance and follow-up Todos now lead toward planning time together; Remote
  guidance and follow-ups lead toward a phone call or FaceTime. Voice accepts commands such as “set
  Sam as remote” or “set Mia as local” without changing closeness or goals.
- The new engine check failed when only the first selected person was written and passed after the
  atomic batch was restored. The voice check failed when Local was removed from the proximity
  command boundary. Widget checks rejected the former hidden filter and generic local follow-up;
  the documentation guard likewise rejected the retired circle-only navigation claim.
- The real-engine product journey passed on the local iPhone 17 Pro Max simulator and captured
  `app/build/simulator-check/relationships-proximity-filters.png`. Visual inspection confirmed that
  Local and Remote are simultaneously visible on the phone, proximity counts and due badges read
  clearly, and the denser `Core · Remote` row retains an actionable Organize control. The short run
  produced one Runner RSS sample around 509 MiB, which is not a plateau or leak claim. The app and
  simulator were stopped, no app/test process remained, and the physical phone was not used.
- The first full precheck correctly rejected its old person-row tap after the additional proximity
  row made that card taller: its center sat behind the persistent input bar. The journey now scrolls
  until the whole person card is above both persistent bottom surfaces and asserts that geometry
  before tapping. The focused real-engine macOS rerun passed with one short RSS sample around
  347 MiB; the app exited and no process remained.
- Final full precheck is green: 2,065 engine tests + 36 intentional skips; 203 Flutter tests + 4
  channel skips; 95.7% deterministic-core, 89.5% product-logic, and 83.8% transport coverage;
  analyzers, seed sync, documentation consistency, import layering, render guards,
  external-channel checks, macOS build, eight real-engine cases, secret scan, and the 24/60
  conformance ratchet.

## Actionable Relationships home (2026-09-07)

- Relationships now opens on a bounded **Focus** queue of at most eight people whose touch or
  meaningful-connection goal needs attention. Global search reaches every person, while live
  circle counts, due badges, and Focus/Core/Close/Keep connected/Keep warm/Context only/All filters
  make a large address book navigable without reverting to a flat alphabetical default.
- Filtered and All views remain urgency-first. Every person row exposes a visible **Organize**
  action; multi-select changes a batch's circle or proximity as one durable undoable mutation.
  Moved people inherit the destination circle's goals, while proximity changes preserve goals and
  people already in a destination circle retain custom overrides.
- The newest undo result now replaces an older transient result instead of waiting behind its
  five-second display window. This keeps rapid direct and bulk organization feedback truthful.
- The widget verifier was calibrated against the former flat home, a non-scrolling circle picker,
  queued stale feedback, and the obstructed duplicate Add-person button; each failed before its
  production correction passed. The atomic engine check likewise failed when only one selected
  record was written, then passed after restoring the single coordinated batch. The documentation
  guard rejected the retired circle-grouped-home claim before the active specs were corrected.
- A production-theme iPhone 17 Pro Max simulator passed the complete real-engine product journey
  and the focused Relationships capture. The rendered header, filters, due row, and Move action
  were inspected in `app/build/simulator-check/relationships-header-actions.png`; the app and the
  simulator started for this verification were stopped, and no physical phone was used.
- Final full precheck is green: 2,064 engine tests + 36 intentional skips; 202 Flutter tests + 4
  channel skips; 95.7% deterministic-core, 89.6% product-logic, and 83.8% transport coverage;
  analyzers, seed sync, documentation consistency, import layering, render guards,
  external-channel checks, macOS build, eight real-engine cases, secret scan, and the 24/60
  conformance ratchet.

## Code-to-spec alignment audit (2026-09-07)

- All 17 active specifications were reviewed against the wired engine/Flutter implementation, with
  code taking precedence. Each owning spec now identifies shipped behavior separately from design
  destinations; the historical research and implementation-plan documents point to Spec 17 for
  current product composition.
- Corrected drift included the Relationships/Todos/Habits primary navigation, secondary
  Plan/Library/History tools, iOS native notifications, callback-based voice seams and user-delimited
  capture, the shipped iOS voice picker/fixed rate, the single mute preference, Session/controller/
  ledger UI boundaries, five generic renderer variants, adaptive Plena behavior, and current
  reference-data limits.
- The reference-data spec now records the real 403-entry model-estimated nutrition seed, exact
  production lookup, component-only feature-hash resolver, unscaled `read_reference`, truthful miss
  path, and absence of units/learned aliases/cloud normalization. The presence spec now records its
  private `_Frame`, fixed seed, shipped mic/yield/ember behavior, non-iOS trail buffer, and deliberate
  iOS trail-free path.
- Documentation consistency now rejects 76 concrete retired claims found across prior alignment
  work and this pass. The expanded guard was calibrated red/green by temporarily restoring
  representative retired reference-data, local-model-routing, and fixed-seed-count statements;
  each produced its named failure before the corrected documents passed.
- Final full precheck is green: 2,063 engine tests + 36 intentional skips; 201 Flutter tests + 4
  channel skips; 95.7% deterministic-core, 89.4% product-logic, and 83.8% transport coverage;
  analyzers, seed sync, documentation consistency, import layering, render guards,
  external-channel checks, macOS build, eight real-engine cases, secret scan, and the 24/60
  conformance ratchet.

## Relationship circles and meaningful connection (2026-09-07)

- Relationships now uses one primary intention circle — Core, Close, Keep connected, Keep warm,
  or Context only — while role tags, Household/Local/Remote proximity, and
  Active/Seasonal/Paused/Archived lifecycle remain independent descriptors. The built-in category
  shortcuts set those fields and inherited contact goals atomically, after which any value can be
  tuned per person.
- Circle defaults are two clocks: Core 7-day touch / 14-day meaningful, Close 14/30, Keep connected
  30/60, Keep warm 90/off, and Context only off/off. Every interaction stores a medium and Quick or
  Meaningful depth. In-person, FaceTime, and phone default meaningful; text and email default quick;
  explicit UI or voice choice wins. The due projection, Todos relationship signal, and voice query
  state which clock needs attention and suggest in-person for local people or phone/FaceTime for
  remote people.
- Existing v2 relationship records migrate to contact v3 without an assigned new circle. Their exact
  former 7/21/60 or custom touch cadence remains authoritative and they gain no meaningful clock
  until explicitly recategorized. Legacy interactions migrate to v3 without rewrites and derive
  depth from medium when projected.
- The Relationships home opens on a bounded urgency-first Focus queue, with global search, live
  circle/proximity counts and due badges, combinable filters, per-person Organize actions, and an
  atomic bulk Organize flow. Person detail exposes categories, circle, both goals, roles, proximity,
  lifecycle,
  introducer, facts, contact actions, and depth-aware interaction history. Contacts import includes
  a compact organization step, defaults new people to Context only, and never overwrites an
  existing relationship plan while refreshing contact details.
- Voice can categorize a named person, pause/resume their suggestions, set either goal to an exact
  number of days, ask who is due, and suffix ordinary interaction language with Quick or Meaningful.
- Domain cadence, import-preservation, voice-depth, schema-migration, interaction UI, and import UI
  checks each failed against a deliberate shipping-code regression and passed after restoration.
- Final full precheck is green: 2,063 engine tests + 36 intentional skips; 201 Flutter tests + 4
  channel skips; 95.7% deterministic-core, 89.4% product-logic, and 83.8% transport coverage;
  analyzers, seed sync, documentation consistency, import layering, render guards, external-channel
  checks, macOS build, eight real-engine cases, secret scan, and the 24/60 conformance ratchet. A
  production-theme iPhone 17 Pro Max simulator then passed the focused Relationships journey and
  produced `relationships-header-actions.png`, `relationships-change-notification.png`, and
  `relationship-detail-actions.png`. Its app RSS fell from about 326 MiB to the normal post-test
  exit; the simulator was shut down and no app/test process remained. The physical phone was not
  used for verification.

## Repeatable Contacts import correction (2026-09-07)

- The 09:12 physical-phone diagnostic log was copied read-only after Luis explicitly requested use
  of the detailed logs. It contained no Contacts events at all, proving the native bridge was an
  uninstrumented boundary: denied, limited, cancelled, empty, and failed reads were
  indistinguishable. No app launch, test, probe, reset, or data mutation occurred on the phone.
- iOS import now uses Apple's `CNContactPickerViewController`, which provides one-time snapshots of
  the people the user selects regardless of Plenara's Contacts authorization status. Plenara no
  longer requests ongoing whole-address-book permission, and the redundant second in-app picker is
  gone. A second import can select more people or refresh an existing system-id match without a
  clone.
- Internal diagnostics now record `contacts: picker begin` and a privacy-safe authorization,
  selected-count, cancellation, or error-code outcome. They never duplicate names, phone numbers,
  email addresses, or identifiers into that trace. The Dart logging/decoding and two-import widget
  checks failed against deliberately restored regressions and passed after restoration. Two
  iOS-hosted tests on the local iPhone 17 Pro simulator proved the native picker can finish and open
  again and that selected contact snapshots cross the bridge; the repeat-open test also failed when
  completed picker state was deliberately retained, then passed after restoration.
- The raw Xcode test command exposed ambient provider credential values in its initial verbose
  scheme environment. `tool/safe-xcodebuild.sh` now clears all three provider-key variables and runs
  Xcode quietly; precheck calibrates that boundary with canaries, and release/test scripts clear the
  same environment. The affected provider credentials require rotation in their account consoles;
  their values are never repeated in project artifacts or this capsule.
- The first complete gate also caught a verifier defect in the Relationships → Habits → Todos →
  Plan journey: on text-only hosts the persistent input bar starts above bottom navigation, but the
  test treated navigation as the only obstruction. The old check reproduced the missed tap. The
  corrected check identifies both persistent surfaces, scrolls the Plan action wholly above the
  earlier one, and the focused real-engine journey then passed.
- Final full precheck is green: 2,056 engine tests + 36 intentional skips; 201 Flutter tests + 4
  channel skips; 95.7% deterministic-core, 89.1% product-logic, and 83.8% transport coverage;
  analyzers, seed sync, documentation consistency, import layering, render guards, external-channel
  checks, macOS build, eight real-engine cases, secret scan, and the 24/60 conformance ratchet. The
  two iOS-hosted Contacts tests also passed again on the local iPhone 17 Pro simulator. That
  simulator was shut down, no app/test process remained, the read-only temporary phone-log copy was
  deleted, and the physical phone was never launched or used for verification.

## Relationships / Todos / Habits rework (2026-09-06)

- The primary navigation is now **Relationships / Todos / Habits**, opening on Todos. Plan, Library,
  History, Settings, diagnostics, and repair remain reachable secondary tools; natural voice phrases
  can navigate to each primary root and to Plan/Library.
- Relationships is a purpose-built workspace: add, import from iOS Contacts, edit, and undoably
  remove people; edit/remove facts; log interactions as in-person, FaceTime, phone, text, or email;
  set Close (7-day), Connected (21-day), Light-touch (60-day), or custom contact rhythms; act on
  due-contact suggestions; start phone/FaceTime/email actions; and create a contact-linked follow-up
  Todo. Only completed interactions count toward relationship health.
- Todos is the focused one-off commitment workspace. Fast capture can leave an item undated or put it
  today/tomorrow/on a chosen day; only task/reminder records populate Now/Next/Later. Due relationship
  guidance and habit check-ins appear as explicit cross-workflow cards rather than being recast as
  todos. Relationship signals open the named person directly; stale-queue and capacity signals open
  Plan with the affected tasks selected for immediate scheduling or deferral.
- Habits is a first-class repeated-practice workspace, distinct from routines and quantitative
  trackers. Habits have a 1–7/week target, active/paused lifecycle, one check-in per local day,
  weekly progress, a seven-day strip, and a daily streak. Voice can create, list, check in, and report
  progress using the same records and rules as the UI.
- Contact and interaction schemas are v2. Contact details, relationship goals, habits, and their
  histories follow the existing plaintext JSON sync disclosure. Parent deletion cascades through
  relationship/habit child records, and one targeted undo restores the group.
- The new relationship-health, habit projection, three-pillar navigation, and native Contacts
  checks were calibrated against deliberately broken implementations before passing. An explicitly
  selected local iPhone 17 Pro simulator passed the production-theme Relationships → person detail
  → Habits → Todos → Plan → voice-opened Library journey. The Contacts method-channel check failed
  against a deliberately wrong channel and passed after restoring the real Swift bridge with
  Contacts permission pre-authorized (the permission decision itself was not under test). Phone
  captures are `app/build/simulator-check/relationships-three-pillars.png` and
  `app/build/simulator-check/relationship-detail-actions.png`. A longer stress attempt sampled
  Runner RSS at 448 MiB, 489 MiB, and 488 MiB; the final capture run completed too quickly for a
  multi-sample claim. This is not a long-soak leak claim. The selected simulator and every app/test
  process were terminated; the physical phone was untouched.
- Todo planner-signal routing was calibrated red/green at both widget and real-engine boundaries.
  On the selected local iPhone 17 Pro simulator, the stale-work signal opened Plan with its task
  selected and the Unscheduled queue in view, while the relationship signal opened the exact person
  with Log interaction and contact actions available. Captures are
  `app/build/simulator-check/todo-stale-signal-plan.png` and
  `app/build/simulator-check/todo-relationship-signal-person.png`. The short screenshot run yielded
  one Runner RSS sample at 678 MiB, so it supports no plateau or long-soak claim; the app and
  simulator were terminated and the physical phone was untouched.
- Primary-root header controls now share one layout instead of placing the global More menu in a
  later-painted overlay. The 393-point phone regression measured the shipped Relationships overlap
  (Add person `x=345–393`, More `x=343–383`) and the corrected disjoint targets (Add person
  `x=297–345`, More `x=349–389`), then also checked Habits and Todos. Shared manual-write/UNDO
  notifications explicitly dismiss after five seconds; their prior action-bearing snackbar was
  persistent under Flutter 3.44. Both checks went red against the real old behavior and green after
  restoration. The corrected real-engine journey passed on macOS and twice on the selected local
  iPhone 17 Pro simulator, including an actual Add person write and notification absence at six
  seconds. Captures are `app/build/simulator-check/relationships-header-actions.png` and
  `app/build/simulator-check/relationships-change-notification.png`. The repeated simulator run had
  one Runner RSS sample at 655 MiB and supports no plateau or long-soak claim; the app and simulator
  were terminated and the physical phone was untouched.
- Final full precheck is green: 2,056 engine tests + 36 intentional skips; 199 Flutter tests + 4
  channel skips; 95.7% deterministic-core, 89.1% product-logic, and 83.8% transport coverage;
  analyzers, seed sync, documentation consistency, import layering, render guards, external-channel
  checks, macOS build, eight real-engine cases, secret scan, and the 24/60 conformance ratchet.

## 0.13.0 pre-deployment verification (2026-09-06)

- Release metadata is `0.13.0+19`; the source includes the completed 2026-08-19 code/spec review
  remediation described below.
- The complete precheck is green: 2,046 engine tests + 36 skips; 189 Flutter tests + 4 skips;
  95.7% / 89.8% / 83.8% coverage; macOS build; seven real-engine cases; external-channel,
  secret-scan, and 24/60 conformance gates.
- The production iOS notification integration passed twice on the explicitly selected local iPhone
  17 Pro simulator. The real notification permission sheet was answered **Allow** through a
  disposable XCUITest helper calibrated first against a deliberately nonexistent button. The run
  scheduled, recovered, and cancelled the durable OS request. Runner RSS sampled 437 MiB, 367 MiB,
  and 375 MiB during the short repeat and did not balloon; this is not a long-soak leak claim.
  The app, helper, and simulator were terminated, disposable artifacts removed, and the physical
  phone remained untouched during verification.

## Full code/spec review and remediation (2026-08-19)

- `main` was clean, fast-forward synced, and identical to `origin/main` at `205a02e`. Review:
  `reviews/2026-08-19-full-code-spec-review.md`.
- All nine confirmed findings are resolved. iOS now uses a real `UNUserNotificationCenter` adapter;
  native adapters recover the durable OS queue from versioned payloads, clear legacy/untraceable
  requests, materialize 16 recurring occurrences, and enforce the global iOS queue cap of 64.
- iOS data-folder selection is provisional until Dart validates/copies/probes the destination, then
  the native bookmark and config commit through explicit commit/finalize/rollback phases. Search
  fully rebuilds before each query, evicts deleted ids, orders ties by id, keeps journal bodies off
  speech, and renders full content only in ranked tappable cards.
- Voice cannot re-enter while an asynchronous stop is flushing; recognizer callbacks are epoch
  checked and Sherpa awaits recorder/subscription teardown. History now persists/renders outcome,
  affected-record links, proposal/acceptance state, and safe failure/recovery state. Keep-current
  conflict copy no longer promises an undo that does not exist.
- Specs 04/05/06/09/10/14/17 were aligned with wired behavior. The documentation gate now has 36
  retired-claim guards and was calibrated against a deliberately restored stale voice claim. Project
  instructions and the simulator skill now require agents to keep the host unlocked, detect and
  drive simulator permission dialogs, record the choice, and continue the run.
- Final full precheck is green: 2,046 engine tests + 36 skips; 189 Flutter tests + 4 skips; 95.7% /
  89.9% / 83.8% coverage; macOS build; seven real-engine cases; external, secret, and 24/60
  conformance gates. The iOS simulator artifact also builds. The initial production-notification
  smoke stopped at the iOS Allow sheet because the macOS host was locked; the complete permission,
  schedule, recovery, and cancellation path was subsequently verified on 2026-09-06 as recorded
  above. The simulator and every app/test process were terminated; the physical phone was untouched.

## Full code review and remediation (2026-08-18)

- Nine read-only reviewers covered the whole tree; 63 defects found, every confirmed one fixed with a
  calibrated test. Review: `reviews/2026-08-18-full-code-review-remediation.md`.
- **Records could not be edited after a relaunch** for 13 of 17 shipped types: the loader injects the
  envelope `createdAt`, updates carried it into the write, and the validator rejected it as an unknown
  field. `createdAt` is now structural. Every test missed this by editing inside the creating session.
- **Durable-execution data loss fixed**: recovery replayed a stale `applying` write over a newer
  completed one, and undo skipped conflict detection for non-`completed` records. Both now compare
  before/after images and escalate to a terminal `conflict` phase; replays are capped at three.
- **The record merge was not associative** when a delete met two live branches, so replicas could
  diverge permanently. It is now a true join-semilattice; the randomized property test generates
  deletes, tombstones, vv dominance, stamp ties, and legacy stamp-less fields.
- **The turnlog ignored the build channel.** `v0` had no channel awareness, so external builds would
  have written utterances/responses/diagnostics, and the purge missed inherited turnlogs. The
  repository now takes `enableTurnlog` (external constructs it false), inherited turnlogs are purged,
  and a Class S rejection boundary runs before serialization in every channel. Internal
  content-bearing diagnostics are unchanged and remain enabled as approved.
- **DST recurrence fixed** (2nd Sunday firing Saturday; biweekly drifting an hour for a whole season),
  verified by a 2025–2027 sweep. Feb-29 anniversaries had three different behaviors; `dates.dart` is
  now the single authority (clamp to Feb 28 in common years).
- Also fixed: Settings key-probe bypassing the persisted rate ledger; weekly review including every
  task ever completed; corpus learning able to persist a private name verbatim; unbounded
  `operations.json`; non-total sort comparators making the "deterministic" projection
  filesystem-dependent; cron accepting expressions it silently never fires; shape-corrupt files
  bricking cold start; OneDrive/Syncthing conflict copies never merged; missing fsync before rename;
  routine cadence dying on backgrounding; a timed step discarding the user's in-flight speech;
  operation deliveries lost mid-turn or spoken over a hot mic; unscrollable long replies; the
  local-Whisper engine dropping a whole dictation on an audio error (it had zero tests); and a
  credential-store throw that could brick boot before `runApp`.
- Diagnosability: `ExecutionResult.error` and `CloudError.detail` were read by no call site anywhere
  and now reach the trace; boot sub-phase markers, data-root logging, unreadable-file causes, turn
  correlation ids, and storage-refresh counts added. Mid-run refresh parks failing records as repair
  items instead of dropping them silently.
- Three tests were found unable to fail and were strengthened (an async `returnsNormally` that
  asserted nothing, a defer test that passed against the broken code, and a weekly-review test that
  asserted the bug).
- Gate: 2,034 engine tests + 36 skips; 175 Flutter tests + 4 channel skips; **95.7% deterministic /
  90.0% product / 83.8% transport** (transport was 68.1%); macOS build; seven real-engine cases;
  external, secret, and 24/60 gates. No simulator or physical phone was used; no orphan process
  remains.
## Structural follow-up (2026-08-18)

Luis rejected the three "owner decisions" above as deferrals — none met the bar of a genuine product
call, a spend, an irreversible act, or missing credentials. All three were done:

- **Turn serialization.** Every public entry point — `handle` and the UI mutations a task-row tap
  uses (`completeTask`, `updateTaskPlans`, `scheduleTasks`, `deferTasks`, `resizeTask`,
  `completeTasks`, `editField`, `deleteRecord`, `undoLast`, `undoById`, `applyWeeklyReview`,
  `applyPlanProposal`) — now runs on ONE `_serialized` chain with `*Unlocked` bodies for every
  internal caller, so a queued operation can never await another queued entry point. `_turnInProgress`
  is owned by the chain, so a deferred storage refresh drains exactly once after the LAST operation
  rather than between two of them. Four concurrency tests; two of them go red against unserialized
  turns.
- **`main.dart` decomposed**, 2,281 → 1,185 lines: `bootstrap.dart` (187), `voice_turn_controller.dart`
  (670), `routine_player.dart` (166), `reply_view.dart` (201), `dev_harness.dart` (311). Behaviour
  preserved — `ChatScreen`'s constructor and every widget `Key` are unchanged, so `widget_test.dart`
  needed no edits. The extracted controller carries 8 new unit tests that were impossible before
  (delivery queued while listening, delivery presented after a turn, TTS never over an open mic,
  cancel as the only discard path), each calibrated against six deliberate breakages. The compiled
  external gate was re-proven on a real release artifact, not assumed.
- **Now-cap allocation.** Overdue work stays visible but can no longer take every slot: current items
  reserve up to 2 of 3, overdue fills the remainder, and overdue may still fill the bucket when
  nothing is current. Degrades to the old behaviour at both extremes.
- Gate after the structural work: 2,042 engine tests + 36 skips; 183 Flutter tests + 4 skips;
  95.7% / 90.0% / 83.8% coverage; macOS build; seven real-engine cases; external, secret, and 24/60
  gates. No simulator or phone; no orphan process.
- Still open, and genuinely structural rather than deferred work: `session.dart` remains ~5,000 lines.
  Its seams are mapped (Tour ~350, planner facade ~950, reference-by-number ~320, Library facade
  ~156, routines ~566, regex intent bank ~550) and it is the next decomposition.

## Product direction

- Spec 17 now owns the product model: **Relationships / Todos / Habits + secondary Plan/Library/History + global Plena**.
- Voice remains free-form, global, and capable of every core outcome. It is no longer forced to carry persistent planner state, comparison, sequencing, or precision editing alone.
- Plena scales full-screen at empty rest/deep conversation, compact beside populated Todos, and ember-sized on Relationships/Habits/detail and secondary-tool surfaces.
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

## Credential rotation

- Resolved 2026-09-06: Luis rotated the Anthropic credential that had appeared in an earlier tool
  transcript. The replacement development key is stored in the macOS login Keychain under
  `plenara-anthropic-dev`; `tool/devkey.sh check` confirmed the entry without exposing its value,
  and a read-only, non-billed Anthropic models request authenticated successfully (HTTP 200).

## Latest phone deployment

- Permanent owner authorization, 2026-09-07: every new phone build is installed on **Aluminum
  Monster** after it is complete, simulator-verified, committed, and pushed, without asking again.
  This authorizes installation only—never launch, testing, probes, container inspection, log access,
  reset, uninstall, or TestFlight/App Store distribution. Documentation-only revisions do not
  trigger a redundant build/install.
- On 2026-09-08 at 08:58 PDT, the text-mode planner-clearance correction was installed on
  **Aluminum Monster** as signed internal-channel `0.13.0 (19)`, bundle
  `com.plenara.plenaraApp`, from pushed source revision
  `709b66e7ed88eb425acd12bbbc82f2b3119de9b8`. The development-signed AOT SHA-256 is
  `ed899892369a7d9f53ca98db5d130f1b1aea3968f82ff016fb32c2180c2caaf9`; its signature,
  embedded revision `709b66e7ed88`, approved internal raw-diagnostics surface, absence of provider
  credential patterns, team `7V63BZ39HU`, and provisioning profile
  `9700a183-07f9-4d2b-936c-3176f893ef68` through 2027-07-28 were verified before CoreDevice
  confirmed `App installed`. Deployment only—the physical app was not launched, tested, probed, or
  inspected.
- On 2026-09-07 at 17:43 PDT, proximity-aware Relationships was installed on **Aluminum Monster**
  as signed internal-channel `0.13.0 (19)`, bundle `com.plenara.plenaraApp`, from pushed source
  revision `f1c7f79e79c8040af6adf85bb8ae09d2924a7e07`. The development-signed AOT SHA-256 is
  `27a3e732acd6cae73d6081baff8ee35135f05017555e46099563e6b01a3a8408`; its signature,
  embedded revision `f1c7f79e79c8`, approved internal raw-diagnostics surface, absence of provider
  credential patterns, team `7V63BZ39HU`, and provisioning profile
  `9700a183-07f9-4d2b-936c-3176f893ef68` through 2027-07-28 were verified before CoreDevice
  confirmed `App installed`. Deployment only—the physical app was not launched, tested, probed, or
  inspected.
- On 2026-09-07 at 17:02 PDT, the actionable Relationships home and single/bulk circle movement
  were installed on **Aluminum Monster** as signed internal-channel `0.13.0 (19)`, bundle
  `com.plenara.plenaraApp`, from pushed source revision
  `ea4286cefc1034ce13281e018c4ac8d81069f1a1`. The development-signed AOT SHA-256 is
  `1fe7122cc950528ba8266531a5d94ff73dce11e6275e3bf29fee417c5289f1e6`; its signature,
  embedded revision `ea4286cefc10`, approved internal raw-diagnostics surface, absence of provider
  credential patterns, team `7V63BZ39HU`, and provisioning profile
  `9700a183-07f9-4d2b-936c-3176f893ef68` through 2027-07-28 were verified before CoreDevice
  confirmed `App installed`. The first tunnel-only invocation ended without an installation result;
  the tracked retry completed. Deployment only—the physical app was not launched, tested, probed,
  or inspected.
- On 2026-09-07 at 10:56 PDT, relationship circles and two-clock connection goals were installed on
  **Aluminum Monster** as signed internal-channel `0.13.0 (19)`, bundle
  `com.plenara.plenaraApp`, from pushed source revision
  `3d9bbac819086ebf55f230db1a5cc95b1332c0e9`. The development-signed AOT SHA-256 is
  `6a01fda51ae5ba33a139bacebb5c7e89d08152ac50c8415be042ba28c28630c9`; its signature,
  embedded revision `3d9bbac81908`, approved internal raw-diagnostics surface, absence of provider
  credential patterns, team `7V63BZ39HU`, and provisioning profile
  `9700a183-07f9-4d2b-936c-3176f893ef68` through 2027-07-28 were verified before the single
  CoreDevice install. Deployment only—the physical app was not launched, tested, probed, or
  inspected.
- On 2026-09-07 at 09:57 PDT, the repeatable Contacts-import correction was installed on **Aluminum
  Monster** as signed internal-channel `0.13.0 (19)`, bundle `com.plenara.plenaraApp`, from pushed
  source revision `2f44b737d31f5ab36e5e20a214a8cabe974180db`. The development-signed AOT SHA-256
  is `27ffbd1000f55f7cf43e8e9debf5e157fd031c31082459f2153aa483b3bdb5d4`; its signature,
  embedded revision, approved internal raw-diagnostics surface, absence of an Anthropic API-key
  pattern, team `7V63BZ39HU`, and provisioning profile
  `9700a183-07f9-4d2b-936c-3176f893ef68` through 2027-07-28 were verified before the single
  CoreDevice install. Deployment only—the physical app was not launched, tested, probed, or
  inspected.
- On 2026-09-07 at 09:08 PDT, signed internal-channel `0.13.0 (19)` from source revision
  `c5ce27a8c548269eb0d1e419feb978ebf9f32a23` was installed on **Aluminum Monster** as
  `com.plenara.plenaraApp` through CoreDevice, without launching it. The installed
  development-signed AOT SHA-256 is
  `c50056b533e183dcd8fb0e9ed30b969199b73cdb8e6595c4566462e2ed753048`; its signature,
  team `7V63BZ39HU`, provisioning profile `9700a183-07f9-4d2b-936c-3176f893ef68` through
  2027-07-28, embedded revision, approved internal raw-diagnostics surface, and absence of an
  Anthropic API-key pattern were verified before install. Deployment only—no physical-phone
  launch, test, probe, log collection, or app inspection.
- On 2026-09-07 at 08:32 PDT, signed internal-channel `0.13.0 (19)` from source revision
  `7210b9bf2603c323b59114dcc4e446b258a9dba3` was installed on **Aluminum Monster** as
  `com.plenara.plenaraApp` through CoreDevice, without launching it. The installed
  development-signed AOT SHA-256 is
  `0d633806a8e06430b1cdc5dcbe0733f6bea256219c397823be4932a5adb89263`; its signature,
  team `7V63BZ39HU`, provisioning through 2027-07-28, embedded revision, approved internal raw-
  diagnostics surface, and absence of an Anthropic API-key pattern were verified before install.
  Deployment only—no physical-phone launch, test, probe, log collection, or app inspection.
- On 2026-09-06 at 16:42 PDT, signed internal-channel `0.13.0 (19)` from source revision
  `a49a5e3b46e1841f0e54e5c86d4a1e012f086570` was installed on **Aluminum Monster** as
  `com.plenara.plenaraApp` through CoreDevice, without launching it. The installed development-signed
  AOT SHA-256 is `aaab89da11a1a59ffb8bcb83ea104cec22a16b729ee38d607cca9e2145fc721d`;
  its signature, team `7V63BZ39HU`, provisioning through 2027-07-28, embedded revision, approved
  internal-diagnostics canary, raw-diagnostics surface, and absence of an Anthropic API-key pattern
  were verified before install. The corresponding App Store distribution IPA SHA-256 is
  `c0f0edffb036ccb9d14c4b96e8c49f316cf27d836d3afa9e16840bb342a32a57` (AOT
  `62a18601624a1ae1081753f686728849e7523f39f9e9c7d6dd8a9d7ea79234fd`); Apple validation and
  upload succeeded under delivery UUID `d6a7afa9-b5e8-41a4-8dee-8ff72cafa410`, processing reached
  `VALID`, and build 19 was distributed to the **Internal** TestFlight group. Deployment only—no
  physical-phone launch, test, probe, log collection, or app inspection.
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

## Code/spec/document consistency pass

- Current behavior, destination design, and historical evidence are now explicitly separated.
  Spec 17 owns the living-planner surface; current voice is tap-toggle; production retrieval is the
  Router-owned in-process feature hash; the execution journal is durable, device-local, and
  plaintext; content search is in-memory; and exactly six cloud synthesis kinds are implemented.
- Specs 01–13/15/17, research, AGENTS, DOGFOOD, privacy, implementation, release, and handoff docs
  were reconciled. Historical walking-skeleton/transition/release docs have archive banners rather
  than silently presenting old plaintext-key, localhost-retrieval, volatile-undo, or overlay-only
  instructions as current.
- Internal diagnostics remain content-bearing exactly as approved, including recognizer hypotheses;
  external builds capture none. Raw audio and secrets remain forbidden everywhere. The public
  privacy policy now matches Spec 11.
- `Session.cloudReason` now directs missing/rejected-key users to Settings rather than legacy
  plaintext config. The regression assertions failed against the old copy and pass restored.
- `tool/doc_consistency.dart` is a calibrated precheck gate for active docs, instruction assets,
  retired claims, project-agent schema, and the six cloud kinds compared across engine, assembler,
  Settings, and Spec 08. Deliberately restored stale claims must make it fail before restoration.
- Final precheck is green: 1,922 engine tests + 36 skips; 161 Flutter tests + 3 development skips;
  94.7% / 90.5% / 68.1% coverage; macOS build; seven real-engine cases; external, secret, and
  24/60 gates. No simulator or physical phone was used; no app/test process remains.
- The review is `reviews/2026-08-17-code-spec-doc-consistency-review.md`. Its then-unresolved
  `AGENTS.md` contradiction was resolved with Luis's explicit authorization in the instruction
  package described below.

## Project instruction package

- Root `AGENTS.md` is the tracked, canonical project-specific instruction router. It keeps only
  always-relevant product purpose, authority routing, device safety, and completion rules without
  copying Luis's cross-project working preferences or forcing unrelated context into every task.
- `CLAUDE.md` is intentionally only a compatibility pointer to `AGENTS.md`, preventing two full
  copies from drifting. The obsolete `.claude/settings.json` was removed because its blanket shell
  grant, Windows paths, and retired llama commands were machine policy rather than portable project
  guidance.
- Repo-scoped Codex skills live under `.agents/skills/`: product development, simulator
  verification, documentation alignment, and standing-authorized physical-phone deployment.
  Project agent definitions under `.codex/agents/` cover spec/code review, product/art/motion
  review, and simulator verification. Agent roles do not grant permission to delegate, deploy, or
  take external actions.
- The instruction guard checks all four skills, keeps the root router bounded, requires each
  project agent to route through `AGENTS.md`, rejects blanket capsule loading and retired claims,
  and keeps `CLAUDE.md` as a thin pointer.
- At the earlier three-skill package revision, calibration restored the actual overlay-only claim,
  expanded `CLAUDE.md` into a second authority,
  mismatched a skill name, and removed an agent description; one run named all four defects, and
  the restored run passed. The official Codex skill validator passed all three skills that existed
  at that revision from an isolated temporary environment, which was removed afterward.
- Final precheck is green: 1,922 engine tests + 36 intentional skips; 161 Flutter tests + 3
  development-channel skips; 94.7% deterministic / 90.5% product / 68.1% transport coverage;
  macOS build; seven real-engine cases; external-channel, secret, and 24/60 conformance gates.
  The local integration app reached about 423 MiB in the single process sample and exited normally;
  no app/test process or booted simulator remains. This was not a leak soak and no physical phone
  was touched.

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
- **Never run tests on the physical iPhone.** All automated, layout, render, motion, and integration verification uses local iPhone simulators. The physical phone is deployment-only; ready phone builds install automatically under the standing authorization recorded above and are never auto-launched.
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

- The eight-increment review plan, phone-diagnostic corrections, task-row clarity change,
  three-pillar rework, and header-action correction are complete. The current installed revision is
  recorded under **Latest phone deployment**; future ready phone builds follow the standing
  installation rule above.

## Authoritative documents

- `planning/specs/17-living-planner.md` — product information architecture and multimodal rules.
- `planning/specs/11-feedback-diagnostics.md` — sole diagnostic collection/export authority.
- `planning/implementation-plan-2026-08-17.md` — ordered implementation program and acceptance gates.
- `AGENTS.md` — canonical project instructions and authority routing for coding agents.
- `reviews/2026-08-17-*.md` — historical review evidence; do not rewrite their findings after decisions change.
