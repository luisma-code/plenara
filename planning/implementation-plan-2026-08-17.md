# Plenara implementation plan — living planner, trustworthy core, coherent presence

**Date:** 2026-08-17  
**Inputs:** [specification and code review](../reviews/2026-08-17-spec-code-review.md), [art and animation review](../reviews/2026-08-17-art-animation-review.md), and [planner UX review](../reviews/2026-08-17-planner-ux-review.md)  
**Status:** approved and in implementation. Increments 0–4 are implemented and repository-gated. Increment 4 passed a schema-v5 migration against a disposable copy of real dogfood data, the host gate, and the local iPhone 17 Pro simulator real-engine gate. Human glance-time, planning-speed, correction-rate, and retrieval-quality measurements wait for ordinary use of a usable deployment, never a test harness on Luis's phone.
**Planning rule:** dependencies and evidence gates determine order. There are no calendar deadlines, and a later increment does not begin merely because an earlier one has code—the earlier increment must pass its user-visible and failure-path gates.

## Executive decision

Plenara will become a **living planner**:

- **Today** is the primary orientation surface.
- **Plan** is the day/week manipulation surface.
- **Library** holds people, goals, routines, trackers, journal, projects, learned phrases, automations, and the full data browser.
- **Plena is global**: full-screen at rest or in deep conversation, compact beside planning work, and a quiet ember on detail surfaces.
- **Voice remains first-class and global**, but it is no longer required to carry persistent state, comparison, or precision editing by itself.
- **Atomic reversible actions act, show, and describe.** Exploratory, ambiguous, or multi-record planning produces an inspectable proposal before it changes the plan.
- **Every consequential state is inspectable without speaking. Every core outcome remains reachable by voice.**

The implementation order protects two things at once: Plenara must become useful as a planner early, and richer planning must not be built on unsafe migrations, volatile undo, or misleading success responses.

## Owner decision: diagnostics during dogfood

The current content-bearing diagnostic logs and manual raw-log export **stay during single-user internal dogfood**. Actual utterances, resolved replies, exception messages, and nearby execution context are necessary to debug routing and stabilize the product. This is an intentional product-stage policy, not an accidental exception.

The boundary is:

| Data class | Internal dogfood build | External beta / release build |
|---|---|---|
| Final utterances and replies | Logged locally; manually exportable | Not written to raw logs by default; not included in export |
| Record/slot values needed to reproduce a failure | May appear in local raw trace | Shape/type only |
| Exception messages and stacks | Kept in raw trace | Error kind + owned code location; content-bearing message removed |
| API keys, auth headers, secure-store values | **Never logged or exported in any build** | **Never logged or exported in any build** |
| Raw audio | Never persisted | Never persisted |
| Interim recognizer hypotheses | Retained only in the content-bearing raw diagnostic trace under Spec 11 | Not captured |
| Automatic upload | None | None unless separately designed and approved |
| Export trigger | Explicit user action with a clear “contains your conversations” warning and file manifest | Explicit user action; safe typed bundle or logging disabled |

Implementation policy:

1. Replace the loose `PLENARA_DEBUG` meaning with one compile-time `BuildChannel` owned in a single file: `development`, `internal`, or `external`.
2. Debug and internal builds use a `ContentDiagnosticPolicy`; external builds use a `SafeDiagnosticPolicy` or no diagnostic capture.
3. `ContentDiagnosticPolicy` keeps raw content for **30 days or 100 MB, whichever comes first**, with oldest-first rotation. Export remains manual.
4. All policies share a code-side secret filter at the logging boundary. The active Anthropic key, authorization headers, config payloads, private-key material, and known credential formats are rejected before serialization.
5. Internal export shows a manifest and explicit warning. It need not scrub user content; it must be honest about containing it.
6. An external build fails its release precheck if content diagnostics, the dev glyph cycle, tuning controls, or another internal-only surface is reachable.
7. TestFlight Internal is treated as `internal`, not as proof of external-release privacy readiness.

This changes the existing rule in [Spec 11](specs/11-feedback-diagnostics.md), research §14, and their restatements. Spec 11 remains the sole authoritative home. When implementation begins, the same documentation change must:

- rewrite Spec 11 §§1, 2.3, 3, 5–7, 9, and its decision record around build-channel policy;
- replace research §14's “no PII, no user content, ever” restatement with a pointer to Spec 11;
- retarget Spec 08's diagnostic registry row and Spec 10's diagnostic threat/Q-1 entries to Spec 11;
- update Spec 12's final-transcript/export statements to point to the policy, while leaving the raw-audio and interim-transcript prohibitions unchanged;
- update `app_log.dart`, Settings copy, release scripts, precheck, and diagnostic tests;
- preserve the three review reports as historical findings rather than rewriting their conclusions after the decision.

## Architecture destination

The product should converge on these owned seams:

```text
Today / Plan / Library / Conversation ledger
                    │
         StructuredTurn + VoiceTurn
                    │
          DispatchOrchestrator
          ├─ local corpus + retrieval
          ├─ proposal coordinator
          └─ detached operation center
                    │
          ExecutionCoordinator
          ├─ schema registry + value codec
          ├─ durable execution journal
          ├─ one undo/change ledger
          └─ automation reconciliation
                    │
     StorageRepository + SyncCoordinator
                    │
       per-record JSON / secure secrets
```

Rules for the destination:

- UI gestures, voice commands, automation approval, and batch proposals all enter the **same business-logic mutation path**.
- The UI never synthesizes English to mutate data.
- One `SchemaRegistry` owns hydration and cross-reference validity.
- One total `ValueCodec` owns every value-type parse, validation, and disk representation.
- One `ExecutionCoordinator` owns ordering, durable before-images, persistence progress, recovery, and undo.
- The planner is a purpose-built projection across tasks, reminders, people, goals, and routines. Generic archetypes remain the fallback for emergent data.
- Conversation history records how current truth was reached; Today and Plan show current truth.
- Plena expresses system state and relationship. Planning objects carry user state.

## Sequencing principles

1. **Repair the instrument before trusting the gate.** Known-bad analyzer, render, migration, secret, and crash-recovery states must fail before their passing results count.
2. **Make writes truthful before multiplying write surfaces.** Direct manipulation and batch replanning wait for durable execution/recovery.
3. **Make migration real before expanding the task schema.** No new planner fields land on the current additive-only migration runner.
4. **Deliver a usable Today vertical slice before completing every backend ambition.** Local routing, full Week, sync, and illustration curation do not block the first durable planner surface.
5. **Use output-level gates.** A passing widget test does not prove a readable iPhone layout; an execution-unit test does not prove restart recovery.
6. **One rule, one home.** Each increment names the specs and restatements it changes; stale prose is fixed in the same change.
7. **Keep verification off Luis's phone.** Automated layout, motion, voice, memory, and log checks run on local iPhone simulators. The physical iPhone is used only to deploy a usable build Luis explicitly asked to receive; ordinary implementation gates never install or run test harnesses there.

## Increment 0 — make the development loop safe and honest

### Outcome

The project can run its full gate without exposing a credential, distinguish internal from external behavior mechanically, and trust its analyzers/render harnesses. This increment does not remove content-bearing dogfood logs.

### Work

**Credential and config safety**

- Rotate the credential exposed during the review. This is the only owner-credential action in the plan.
- Inject an explicit environment map/config source into configuration tests; never inherit a developer's live environment accidentally.
- Change secret-bearing assertions to check source/presence or a one-way test fingerprint, never the value.
- Move the app credential into Keychain/Keystore/DPAPI behind one `CredentialStore` interface; migrate a plaintext value only after a verified secure write, then remove it atomically.
- Keep environment-key support development-only. Internal iOS/TestFlight obtains the key through the app's secure store, not a baked `dart-define`.

**Diagnostic build policy**

- Introduce `BuildChannel` and `DiagnosticPolicy` as described above.
- Preserve raw internal logs and manual raw export; add the honest manifest/warning, rotation, and hard secret boundary.
- Make external builds fail closed if no channel is declared.
- Stamp exported diagnostics with revision, build channel, platform, app/schema versions, and a list of included files.

**Gate repair**

- Clear credential variables inside hermetic precheck steps.
- Fix the false-green existing-contact behavior test so it asserts the turn result and stored state, not only that a seam was called.
- Fail import lint on every unclassified production file and classify routines.
- Generate the conformance pass/skip count rather than maintaining hand-written totals; reconcile Spec 09's stale 20/60 and baseline values.
- Enforce per-tier coverage floors, not only a global percentage.
- Fix the RGBA contact-sheet compositor to render over `#0A0908`; stamp captures with build hash, state, size, text scale, brightness, and reduced-motion mode.
- Keep missing-glyph and known-real-glyph calibration cases.
- Remove or compile-gate production long-press glyph cycling, tuning, and dev harness surfaces.
- Generate Windows package version from the app version.

**Spec/source-of-truth pass**

- Create the living-planner product spec as the authority for Today/Plan/Library, multimodality, proposal semantics, and Plena scaling.
- Amend the superseded research/UI/presence principles to pointers and decision-history notes rather than leaving competing rules.
- Apply the diagnostics rule sweep listed above.
- Reconcile `WORK-CAPSULE.md`, the voice-input bodies, package metadata, and test counts with current behavior.

### Acceptance gate

- A deliberately injected credential never appears in ordinary test failure output, app logs, or exported diagnostics; the canary makes each channel red when the secret boundary is removed.
- Full precheck passes both with and without a live credential present in the parent shell.
- A known unclassified production file fails import lint.
- A known behavior failure makes the corrected behavior test fail.
- The contact-sheet harness distinguishes bad alpha composition from correct dark-ground composition.
- An `external` build containing content diagnostics or dev surfaces fails precheck.
- No report/spec/comment still states the old diagnostics or surface rules as current authority.

## Increment 1 — build the trustworthy mutation and schema spine

### Outcome

Every write is schema-valid, durably recoverable, and described truthfully after storage failure or process death. This is the prerequisite for planner schema expansion, direct manipulation, and batch replanning.

### Work

**Schema authority**

- Build a `SchemaRegistry` hydration boundary: filename/id agreement, positive version, unique ids, attribute/value constraints, enum correctness, reference resolution, presentation eligibility, automation closure, and structured degraded/repair output.
- Use it for startup, seed/template install, capability authoring preview, activation, and synced-definition intake.
- Build a total `ValueCodec` shared by the interpreter and manual UI writes: exact decimal strings, enum membership, ISO date/datetime, integer durations, tag/list/JSON shape, attachment containment, entity ref type/existence, unknown-field rejection, and required-null protection.

**Migration correctness**

- Implement contiguous ordered migration chains with rename, coerce/retype, default/add, and remove.
- Validate the migrated record against the target schema before advancing `schemaVersion`.
- On any failure, preserve the old record/version, exclude it from typed reads where required, and surface a repair item.
- Add backup/rollback semantics for the planner task migration before any planner field ships.

**Durable execution**

- Build a device-local durable execution journal containing frozen inputs, resolved plan, before-images, operation index, origin, and result state.
- Route skill writes, reference corrections, manual edits, delete/undo, routine writes, and automation approval through one serial `ExecutionCoordinator`.
- Persist the execution record before the first data write and checkpoint after each atomic operation.
- On startup, either finish idempotently or reverse the persisted prefix; never silently leave a partial multi-record turn.
- Return a typed `ExecutionResult` that distinguishes applied-in-memory, persisted, recovered, reversed, and failed-before-write.
- Make the visible change ledger and targeted undo read from durable completed executions; keep the in-memory ring only as a cache.

### Acceptance gate

- Kill the app after every operation index of a three-record turn; each restart deterministically completes or restores the full before-state.
- Inject write/delete/logging failures across every mutation origin; the spoken/displayed result matches the durable state.
- Break rename, retype, removal, required-null, enum, date, decimal, and entity-ref cases; each calibration test fails on the old behavior and passes on the new codec/migrator.
- Corrupt or cross-link type files at startup; invalid definitions remain inert and produce a repair surface rather than a later runtime crash.
- Undo survives restart and reverses the exact targeted action after an intervening write.
- Mutation, migration, and recovery tests use the real temporary-filesystem `StorageRepository`, never a mocked database.

## Increment 2 — ship the first useful living-planner slice

### Outcome

Opening Plenara answers “what do I need to know and do now?” without a query. Voice capture remains as fast as it is today, but the result becomes durable visual state.

### Product scope

**One coherent first minute**

- Replace the Flutter icon with a Plena-derived mark tested at App Store, Settings, notification, and Spotlight sizes.
- Redesign onboarding inside the warm constellated identity, inside safe areas, with one promise, one privacy statement, and both primary choices above the fold.
- Let the user meet Plena before detailed voice-download/setup instructions.
- Replace the startup spinner with a still/awakening Plena state.
- Apply one palette, type scale, shape family, and Plena continuity to onboarding, Today, Data, and Settings.
- Fix quiet-text contrast and Dynamic Type clipping.

**Today home**

- Replace the presence-only steady state with a calm Today projection:
  - Now;
  - Next, capped at three meaningful objects;
  - Later/week summary;
  - one genuinely timely relationship nudge;
  - latest Done/change with targeted Undo.
- Plena is full-screen in empty/rest/conversation states and yields compactly when Today content is active.
- Preserve tap-to-speak where it does not collide with interactive objects; add an explicit accessible voice target on populated surfaces.

**Trust and history**

- Show every spoken reply simultaneously as text.
- Keep the current reply visible for the specified linger and retain actions/replies in a durable conversation/action ledger.
- The plan is current truth; the ledger is how it changed. Each action links to its record/execution and undo.
- Fix text arrival/departure so it actually enters and exits, rather than conditionally inserting an always-opaque widget.

**Minimal planner schema**

- Migrate tasks to add `status`, `scheduledStartAt`, `estimatedMinutes`, `priority`, `projectRef`/`areaRef`, `contactRefs`, `notes`, and `completedAt`, while preserving `dueAt` as a deadline.
- The first slice needs only Inbox/Today/Done and deadline versus scheduled-time semantics; Week and advanced fields may remain read-only or collapsed until Increment 3.
- Project reminders and routine commitments into Today without pretending they are tasks.
- Keep dependencies, energy/context, recurrence, and blocked reason as explicit later schema extensions in Increment 3; do not pretend capacity/dependency analysis exists until the fields it needs are represented and migrated.

### Acceptance gate

- On simulated supported iPhone classes, no brand/control intersects the Dynamic Island or home indicator and both onboarding choices are visible without scrolling.
- In a five-second glance across ten scripted states, the next commitment, overdue risk, and latest undoability are identified correctly in at least nine.
- Six mixed voice captures land in the intended semantic place without increasing median capture time by more than 10% from the baseline.
- Every voice write appears visibly in the same response beat and remains findable after relaunch.
- Captions remain visible during TTS and are recoverable from the ledger afterward.
- The task migration round-trips existing real dogfood data and rollback restores the exact pre-migration files.
- Today remains usable at large text, reduced motion, muted mode, no microphone permission, and offline.

## Increment 3 — add real planning, contextual voice, and local understanding

### Outcome

Plenara supports externalizing, comparing, sequencing, editing, and revisiting a day or week. Natural language works locally for common and novel phrasing rather than depending on cloud-first fallback.

### Work

**Plan and Library**

- Add phone Plan: day strip with load/capacity, selected-day agenda, unscheduled queue, deadlines separated from scheduled blocks, and calm conflict presentation.
- Add tablet/desktop Plan: week columns, unscheduled queue, drag/drop/resize, and Plena/conversation rail.
- Add Library summaries for People, Goals, Routines, Trackers, Journal, Projects/Areas, learned phrases, automations, and the generic data browser.
- Keep generic archetypes for emergent data; planner projections are purpose-built binary UI.

**Interaction**

- Add direct complete, schedule/reschedule, resize estimate, defer, inline edit, and multi-select.
  Today task bodies open the shared detail editor; only their explicit leading circles complete.
- Add the observed-need planner fields from the previous increment—dependencies, blocked reason, energy/context, and recurrence—with real migrations and UI only where the benchmark scenarios require them.
- Send each structured action through the same `ExecutionCoordinator`; no English synthesis and no second undo model.
- Put current selection, visible date range, and numbered objects into structured NLU context so “move these two,” “the first one,” and “after school pickup” are deterministic references.

**Local routing**

- Ship an in-process mobile/desktop embedding backend and build the merged capability index at startup.
- Make the routing order corpus → calibrated retrieval top-1/margin → deterministic slot resolution → cloud residual → visible clarify.
- Surface index-unavailable degraded mode; never make localhost service availability a production prerequisite.
- Add the cloud admission controller inside `ClaudeClient`: burst and daily bounds, typed local `rateLimited`, persisted usage, and Settings visibility.

### Acceptance gate

- Compare/sequence benchmark scenarios complete at least 30% faster than the enriched Today-only baseline, with fewer corrective turns.
- Deadline, scheduled time, reminder time, and unscheduled priority are correctly distinguished in comprehension testing.
- Contextual commands over selected/visible objects resolve without restating full titles.
- Held-out natural phrasing meets calibrated local retrieval accuracy/margin thresholds; offline clarify rate is measured and reported.
- No cloud call occurs for a corpus or accepted-retrieval route; rate limits cannot be bypassed through any call site.
- Voice, touch, and keyboard changes produce identical durable execution/undo behavior.

## Increment 4 — collaborative replanning and detached intelligence

### Outcome

Plena can reason about a plan without blocking the assistant or silently rewriting several commitments. Morning/weekly planning becomes a durable proposal, not disappearing prose.

### Work

- Add an operation center with stable ids, progress, cancellation/discard, persistence across background/relaunch, and result delivery.
- Detach capability authoring and long generative/planning work so the interactive turn lock is released immediately.
- Implement deterministic capacity, deadline, dependency, and conflict analysis first.
- Add a proposal/diff model for ambiguous or multi-record changes:
  - proposed positions/values;
  - affected records;
  - capacity/conflict delta;
  - Apply all, Adjust, Dismiss;
  - one atomic execution and undo after apply.
- Support voice refinement against the live proposal.
- Replace the retrospective string-only weekly review with structured open-task/goal keep/defer/drop recommendations, evidence, and a durable editable card.
- Create persistent morning planning and relationship/event-prep artifacts until accepted, dismissed, or superseded.

### Acceptance gate

- A long cloud operation never blocks capture, routine control, or another local command.
- Background/relaunch preserves operation status and does not duplicate delivery or spend.
- At least 80% of accepted benchmark proposals require no immediate correction.
- A reviewer can accurately explain every changed record after apply; one undo restores the complete prior plan.
- Refinement changes only the referenced proposal elements.
- Cloud prompt assemblers include only declared data classes and consented content; secrets remain absent.

## Increment 5 — finish the presence, motion, and routine system

**Implementation status (2026-08-17): complete in code and automated evidence.** Human sound-off
recognition and ordinary-use calibration remain release observations, not substitutes for the
implemented gates; autonomous verification used only host/widget renderers and a local iPhone
simulator, never Luis's physical phone.

### Outcome

The entire product feels authored by the same visual system. Motion explains state change, Plena's expression becomes rarer and more legible, and routines teach movement coherently and accessibly.

### Work

**Presence continuity**

- Implement the full-screen → compact collaborator → detail ember ladder across Today, Plan, Library, Settings, Data, and person/detail surfaces.
- Wire clarification and failure expressions, mic-level listening, and TTS cadence where platform signals exist.
- Tune saturation and thinking-state visibility in simulator render evidence, then incorporate observations from Luis's ordinary use of explicitly deployed builds; automated test harnesses never target his physical phone.
- Either restore an Impeller-safe iOS comet trail through a supported render path or make trail-free iOS an explicit tier decision backed by side-by-side perceptual testing. Do not reintroduce per-frame `toImageSync`.
- Add an independent still-presence setting; make reduced motion use static per-state forms with opacity-only transitions.
- Include muted/text modifier and relevant mode in semantics; never rely on hue alone.

**Semantic motion**

- Tokenize all durations/easing; remove ad-hoc animation constants from widgets.
- Implement real object-continuity motion for create, reschedule, complete, undo, proposal preview/apply, and clarification.
- Keep only one mover-class transition at a time.
- Maintain permanent 11-frame strips for object transitions and full-range strips for every active glyph.

**Expressive curation**

- Keep all 52 glyphs as a development sketchbook but reduce the active production register.
- Everyday writes receive a sub-300ms whole-body acknowledgement, not a traced symbol.
- Retain a small set of rare functional, relational, and milestone glyphs; enforce the real 90-second separation and daily budget.
- Require at least 80% sound-off recognition at the held frame before a glyph becomes active.

**Routine art**

- Define one illustration grammar: proportion, crop, optical line weights, palette, face/equipment policy, and canonical A/B poses.
- Curate highest-use movements first; do not treat inversion as visual unification.
- Render A and B as default instructional stills; optionally play one A→B→A cycle, then stop.
- Freeze GIFs/show labeled stills under reduced motion.
- Verify every tween at 11 keyframes for limb correspondence, pivots, monotonic motion, boundaries, and shape integrity.

### Acceptance gate

- Sound-off reviewers identify create/reschedule/complete/undo in at least 90% of recordings.
- Active presence glyphs meet the 80% recognition threshold and the frequency budget holds across everyday scripts.
- Every Y0/Y1/Y2 transition preserves Plena as the same entity without obscuring actionable information.
- Reduced motion eliminates particle flow, glyph traces, looping routine GIFs, positional text motion, and unverified tweening without losing meaning.
- Normal text meets 4.5:1; large text and meaningful marks meet 3:1; Dynamic Type exposes every action.
- Simulator state-recognition and frame-budget gates pass, supplemented by observations from ordinary use of explicitly deployed builds; short runs are not reported as leak certification.

## Increment 6 — relationship-centered planning and healthy engagement

**Implementation status:** Complete on 2026-08-17. Automated gates pass; the five-day dogfood and human perception measures remain deployment evidence, not code work.

### Outcome

The planner serves Plenara's actual purpose—helping the user show up for people—rather than becoming a generic task manager.

### Work

- Project people-linked commitments, birthdays, event preparation, promises, goals, and routines into Today/Plan at controlled frequency.
- Let a commitment retain multiple meanings: time in the plan, relationship context in the person view, and evidence in review.
- Add deterministic neglect/overload/capacity signals before cloud interpretation.
- Make proactive suggestions durable and explicitly acted on, dismissed, or deferred; never count “shown” as engagement.
- Reserve the largest Plena gestures for a kept promise, reconnection, important birthday, meaningful closure, or self-declared milestone.
- Measure usefulness, control, and follow-through rather than screen time, opens, or generic streaks.

### Acceptance gate

- Relationship context changes actual plans in benchmark and dogfood scenarios without creating dismissal fatigue.
- Proactive items have a terminal accepted/dismissed/deferred state and do not repeatedly reappear unchanged.
- Five-day dogfood shows reduced orientation queries, stale unscheduled items, and forgotten commitments versus the pre-Today baseline.
- Plena's compact planning form retains perceived continuity and character; full-screen expansion restores intimacy for deeper conversation.

### Implemented evidence

- People-linked tasks retain context in Today, Plan, proposals, weekly review evidence, and person detail; equal-risk weekly proposals prefer a commitment to a known person.
- Planned interactions, birthdays/important dates, goals, and active routines enter the relevant Today/Plan projections without flattening their semantic kinds.
- Deterministic overload, stale-queue, and neglect signals are bounded to two; cloud generation is not involved.
- Relationship suggestions persist as versioned planning artifacts with Keep, Dismiss, and Tomorrow states. Deferrals return when due and resolved stable IDs do not respawn.
- Engagement measures explicit outcomes and relationship-task follow-through only. The full gate passes 1,907 engine tests + 36 skips, 138 Flutter tests + one external-channel skip, 94.2% / 90.8% / 68.1% coverage tiers, macOS build, five real-engine tests, secret scan, external isolation, and the 24/60 ratchet.

## Increment 7 — user-controlled sync and loss resilience

**Status: implemented with an explicit iOS degraded mode 17 August 2026.** Device diagnostics established that physical iOS does not support Dart's recursive directory watcher even though simulator/local-provider verification passed. Startup now remains usable and reconciles at cold open; live provider-side edits on iOS require relaunch until a native document-provider event adapter is implemented. The physical phone remains deployment-only and was used only for owner-requested diagnostic retrieval, never as a test target.

### Outcome

The storage claim becomes true: data lives in a user-chosen synced location, reconciles external changes, survives device loss, and does not trade durability for hidden conflict.

### Work

- Until complete, label current iPhone storage honestly as device-local.
- Implement iOS document-provider/folder bookmark flow and corresponding platform choices elsewhere.
- Add record version vectors, watcher/reconcile seam, pure merge, tombstone handling, conflict stash, and repair surfaces.
- Keep the execution journal device-local; sync user records and appropriate user-authored definitions according to the owned specs.
- Add cold-bootstrap, concurrent-edit, offline-edit, deletion, definition-conflict, and interrupted-sync tests using real storage—not a mocked database.
- Treat native watch support as a platform capability: unsupported watching completes empty and can never prevent Ready. Do not replace positive events with a polling timer.

### Acceptance gate

- A fresh device bootstraps from the chosen provider and reaches a coherent plan.
- Concurrent edits deterministically merge or produce an inspectable conflict without silent overwrite.
- Delete/update and definition conflicts preserve recoverable data.
- Offline changes reconcile after reconnect.
- Credential material and device-local execution state never enter the synced folder.
- One rejected user-authored type or dependent skill is parked as visible repair state; it cannot brick unrelated planner capabilities.

## Increment 8 — external-release hardening

**Status: implementation complete 17 August 2026; final clean-revision gate evidence is recorded in the release verification report and generated manifest.** Internal raw diagnostics remain enabled exactly as the owner directed. External AOT artifacts are inspected, not inferred from source policy.

### Outcome

The internal instrumentation and developer affordances cannot accidentally ship to another tester or the public. This is a gate, not a late reminder.

### Work

- Switch external builds to safe typed diagnostics or no diagnostic capture/export.
- Remove content-bearing raw logs from external builds by construction; retain manual consent and exact payload preview for any safe bundle.
- Run the full security/privacy threat-model suite, secret canaries, sync-loss tests, accessibility matrix, supported-device visual matrix, long-run memory/battery soaks, and App Store asset/metadata checks.
- Remove all internal/dev controls from reachability; confirm icon, launch, onboarding, privacy copy, storage copy, and model-cost copy match actual behavior.
- Promote only a revision whose generated release manifest records channel, gate results, build hash, schema version, and migrations.

### Acceptance gate

- Decompiling/launching the external build cannot reach raw content logging/export or dev harnesses.
- Known secret and content canaries make the external build gate fail.
- No placeholder art, stale version, stale privacy claim, or unclassified production file remains.
- Full device/output verification is recorded; no launched app instance or orphan remains after the run.

## Cross-review traceability

Every reviewed item has one implementation home:

| Review item | Owning increment |
|---|---:|
| SC-01 test credential leak | 0 |
| SC-02 raw diagnostic export | Owner override + 0 + 8 |
| SC-03 plaintext credential | 0 |
| SC-04 volatile execution journal | 1 |
| SC-05 unsafe migration | 1 |
| SC-06 incomplete schema registry | 1 |
| SC-07 missing/reversed local retrieval | 3 |
| SC-08 cloud cost/rate guard | 3 |
| SC-09 incomplete value validation | 1 |
| SC-10 mutation/result mismatch | 1 |
| SC-11 blocking cloud work | 4 |
| SC-12 local-only mobile data | 7 |
| SC-13 weak planner model/review | 2–4 |
| SC-14 hidden spoken captions | 2 |
| SC-15 false-green/weak gate edges | 0–1 |
| SC-16 stale docs/metadata | 0, then same-change sweeps throughout |
| Stock icon, split identity, Dynamic Island onboarding defect | 2 |
| Presence displaces planning state | 2–3 |
| Over-broad/frequent glyph vocabulary | 5 |
| Fake/incomplete text and object motion | 2 + 5 |
| Incomplete reduced-motion/accessibility policy | 2 + 5 |
| Inconsistent routine art and unused B pose | 5 |
| Typography/palette/shape/route inconsistency | 2 + 5 |
| Low-contrast routine labels | 2 |
| Capture lacks durable externalization | 2 |
| Missing compare/sequence/revisit/recover loop | 2–4 |
| Deadline conflated with scheduled time | 2–3 |
| Hidden discoverability and brittle novel phrasing | 3 |
| No durable batch proposal/review artifact | 4 |
| Relationship context absent from the plan | 6 |
| No real sync/loss resilience | 7 |
| Internal instrumentation not safe for external distribution | 8 |
| Startup blocked by an unreadable/stale data location | Post-plan dogfood correction |

## Post-plan dogfood correction — recoverable data reset (complete 2026-08-17)

The first authorized physical-phone deployment exposed a storage-startup failure. The implementation now treats that as a product flow, not an owner-operated cleanup:

- startup failure renders the actual error plus a persistent **Reset and start fresh** action;
- Settings exposes the same operation as **Reset data and start fresh**;
- one reset door clears the iOS security-scoped bookmark and selected-folder state, preserves the provider folder unchanged, moves any old device-local root to a timestamped backup, creates a fresh root, and restarts the `Session` in-process;
- a 320×568/2×-text gate keeps the recovery action visible while details scroll;
- the filesystem, Settings, and startup tests were each deliberately broken and observed red;
- the complete failure → native reset → seed → live Today path passed on the local iPhone 17 Pro simulator and macOS real engine. No test ran on the physical phone.

## Baseline and evaluation program

Before Increment 2 changes the product, record the shipped baseline with real dogfood data:

1. Capture six mixed commitments, dated and undated.
2. Identify today/this week.
3. Detect an overloaded day.
4. Move two commitments.
5. Correct one misunderstood capture.
6. Relaunch the next day and reconstruct the plan.
7. Undo an accidental change.

Record time, voice turns, taps, clarify/correction count, backtracking, routing source, final correctness, and confidence. Repeat the same corpus at the gates for Increments 2, 3, 4, and 6.

Healthy success measures:

- time to orientation;
- capture-to-placement correctness;
- replanning cost;
- stale backlog rate;
- overload detection;
- re-entry recall;
- correction and undo success;
- “I know what changed” score;
- natural-phrasing success by routing source;
- relationship commitments planned/completed;
- proactive suggestions accepted/dismissed/ignored;
- perceived helpfulness, calm, control, and Plena continuity.

Do not optimize raw screen time, daily opens, generic completion counts, or notification volume.

## Definition of done for every increment

An increment is complete only when all of the following are true:

1. The user-visible scenario was run on the real target surface, not inferred from code.
2. The primary failure mode was deliberately induced and the gate went red.
3. Restart/background/storage-failure behavior was tested where relevant.
4. Accessibility and reduced-motion variants were exercised for UI/motion changes.
5. Memory was sampled for any launched app, ballooning processes were killed, and every launched instance/orphan was cleaned up.
6. Governing specs were updated in their authoritative home and all stale restatements were removed or converted to pointers.
7. `WORK-CAPSULE.md` reflects the new live truth.
8. The full repository gate passes in a credential-scrubbed environment and in the relevant build channel.
9. The revision is committed and pushed; the evidence names exactly what was proved versus merely implemented.

## Recommended first implementation slice

Begin with Increment 0, then take Increment 1 through a deliberately small but complete vertical path:

1. hermetic config test and secret-safe matcher;
2. secure credential store/migration;
3. build-channel diagnostic policy preserving internal raw logs;
4. calibrated gate fixes and living-planner/diagnostics spec decisions;
5. `SchemaRegistry` + `ValueCodec` for the existing task type;
6. durable execution for one atomic task add, task complete, targeted undo, and restart recovery;
7. generalize that proven path across every mutation origin before adding planner fields.

That sequence removes the immediate hazard, honors the dogfood debugging need, and proves the architecture on the smallest real workflow before it expands. The next delivered product increment is then Today—not another invisible subsystem.
