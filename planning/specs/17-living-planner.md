# Spec 17 — Living Planner & Multimodal Product Model

**Status:** v1.1 — 2026-09-07, active implementation authority and audited against the current
Flutter/engine tree. Relationships, one-off Todos, and tracked Habits are the three primary product
roots. Plan, the generic Library, and History remain reachable secondary tools. The earlier planner
increments, durable mutation/undo, contextual local routing, relationship assistance, adaptive
presence/routines, user-selected sync/recovery, and build-channel hardening remain wired.
**Supersedes:** research §2.2's overlay-only/no-touch rule; Spec 07 P1–P2 and its four-surface model; Spec 15 D1/D14 where they make full-screen presence or ephemeral exchange the steady-state product. Those documents remain design history and point here for current behavior.
**Depends on:** Specs 01–06 for schema, skills, routing, orchestration, functional behavior, and storage; Spec 07 for visual language and generic archetypes; Spec 12 for voice; Spec 15 for Plena's renderer.

---

## Current realization — through Increment 8 and dogfood corrections

- Opening the app lands on Todos, the focused one-off-commitment projection derived from the earlier Today board. Relationships and Habits are peer primary roots. Plan, Library, History, settings, diagnostics, and repair remain secondary destinations rather than competing navigation pillars.
- Voice and typed capture continue through `Session.handle`; Todos completion calls the typed `Session.completeTask` command directly. Both converge on `ExecutionCoordinator` and its durable device-local journal.
- Todos task rows separate navigation from mutation: tapping the task body opens the shared type-driven detail editor; only the explicit leading circle completes it. Both consume their gesture before the background voice target, and a trailing chevron makes the row's navigation role visible.
- The device-local conversation ledger retains the final utterance, full reply, routing source, derived outcome, affected record ids, proposal/acceptance state, failure state, time, and execution link for 250 turns. It is a user-facing product history distinct from content-bearing internal diagnostic logs. History renders affected records as tappable links and exposes targeted undo for linked executions.
- Task schema v3 introduced `status`, `scheduledStartAt`, `estimatedMinutes`, `priority`, `projectRef`, `areaRef`, `contactRefs`, `notes`, and `completedAt`; v4 added dependency/energy/context/recurrence semantics and v5 added `reviewDecision`. `dueAt` remains deadline-only. Project and area are registered record types.
- Plena remains full-bleed during conversation and yields within the same canvas when a primary workflow is visible. Populated surfaces have an explicit accessible voice target; tap-anywhere remains active only on non-interactive space.
- On primary roots, the global secondary-tools menu participates in the screen header layout rather than overlaying workflow actions. Manual-write confirmations expose Undo for five seconds and then dismiss automatically; newer completed actions replace older transient feedback instead of queuing behind it.
- Onboarding uses the same warm presence and palette, pins both decisions outside its scrollable story area, and states the internal-dogfood diagnostic policy. Platform icons are generated from a deterministic Plena particle mark for iOS, macOS, and Windows.
- Phone Plan now has a week strip, selected-day agenda, deadlines, unscheduled queue, load, conflict state, direct schedule/defer/resize/complete actions, and multi-select. Desktop expands the same semantics into a week/queue workspace with drag-to-day scheduling.
- Library now exposes purpose-built People, Habits, Goals, Routines, Trackers, Journal, Projects & areas, Learned phrases, and Automations summaries while preserving the complete editable data browser. People opens a Relationships workspace where contacts, contact details, facts, and contact history are visible and mutable rather than anonymous schema rows.
- Task schema v4 represents dependencies, blocked reason, energy, contexts, and recurrence. Existing folders receive missing built-ins and newer versioned types without clobbering authored or same-version definitions; exact definition and record backups precede migration.
- Plan and Todos publish structured visible dates, ordered objects, and selection ids. Contextual commands such as “move these to tomorrow at 10am” and “make the first one 45 minutes” resolve against those ids and enter the same durable execution/undo path as touch and pointer actions.
- Production routing now builds an in-process deterministic feature-hash index and orders common work as corpus → bounded accepted retrieval with deterministic slot extraction → cloud residual → visible clarification. Localhost embeddings remain an explicit development experiment, not a runtime dependency.
- Every Anthropic request crosses one persisted admission controller before HTTP: 200 calls per local day and 30 per rolling ten minutes. Corrupt or unwritable usage state fails closed, and Settings shows both counters.
- Task schema v5 adds the explicit weekly-review decision (`keep`, `defer`, or `drop`) through a contiguous 4→5 migration. A structured weekly review persists evidence and editable decisions, revalidates record fingerprints before apply, and commits selected task changes through one durable execution and undo.
- `PlanProposal` is a durable no-write preview with selected items, proposed times, estimates, rationale, conflict delta, and explicit omission reasons. It respects represented capacity, deadlines, dependencies, and blocked state. Voice can move or exclude numbered proposal items; apply revalidates every task fingerprint and commits once.
- Long weekly/pattern synthesis and custom-capability authoring enter one persistent serial `OperationCenter`. The initiating turn returns immediately, Todos renders progress/cancel state, terminal delivery is exactly once, and relaunch marks uncertain in-flight work interrupted rather than risking duplicate provider spend.
- A validated authored-capability preview is persisted device-locally until activation, cancellation, or an unrelated move-on turn. Only activation promotes it to the live type/skill registry.
- Morning plans and relationship/event-preparation cards are deterministic durable artifacts on Todos. A draft remains until accepted, dismissed, or superseded; relationship preparation uses only saved facts, dates, and the latest logged interaction.
- Generative prompt assembly stamps its declared record classes and explicit-invocation consent into every implemented request. The same declarations are visible in Settings; journal is excluded from all current assemblers.
- People-linked task commitments keep their relationship identity in Todos, Plan, weekly proposals/reviews, and person detail. Planned interactions and recurring relationship dates appear in the selected Plan day; goals and active routines remain visible as planning rhythms.
- Upcoming relationship dates produce one durable proactive suggestion with explicit Keep, Dismiss, and Tomorrow outcomes. Deferral survives relaunch and returns when due; a resolved suggestion does not respawn unchanged.
- Each person belongs to one primary intention circle: Core, Close, Keep connected, Keep warm, or Context only. The circle supplies inherited touch/meaningful defaults of 7/14, 14/30, 30/60, 90/off, and off/off days respectively. Roles, proximity, and lifecycle are independent descriptors; per-person goal overrides store only the delta. Existing 7/21/60-day records keep their exact old cadence until the user explicitly chooses a new circle.
- Completed typed interactions — in person, FaceTime, phone, text, or email — advance an “any contact” clock. Each is also Quick touch or Meaningful connection and only the latter advances the second clock. In-person, FaceTime, and phone default meaningful; text and email default quick; the user can always override the default. Planned interactions and launch-button taps do not pretend contact happened.
- The Relationships workspace opens on a bounded Focus list of genuinely due people rather than every saved name. Global search reaches every circle; circle filters show membership and due counts; circle and all-people views remain urgency-first. Every person row exposes a direct Move menu, and Organize mode moves a multi-selection through one durable, undoable execution. A person who actually moves inherits the destination circle's goals; an already-present member keeps custom overrides. A relationship signal on Todos opens the named person's actionable detail workspace directly; overload and stale-queue signals open Plan with the represented tasks selected so schedule/defer actions are immediately available. Deterministic signals run before AI and are capped at two on Todos. Engagement counts explicit suggestion decisions and relationship follow-through, never impressions, opens, animation, or screen time.
- On iOS, each import opens Apple's multi-contact picker for one-time access to the entries the user explicitly selects. It works under denied, limited, full, or not-yet-determined Contacts authorization and does not ask Plenara for ongoing address-book permission. A compact organization step assigns a category before first import and defaults to Context only so bulk import creates no reminder debt. Reopening the picker can import another person or refresh an existing match without cloning it or overwriting the existing relationship plan. Imported contact and relationship-plan fields sync as ordinary plaintext JSON under the current storage model. Call, FaceTime, and email actions launch the corresponding system handler; launching is never logged as a completed interaction.
- Habits are first-class records with a weekly target and active/paused lifecycle. A check-in is a dated child record, limited to one per habit per local day by both typed UI and voice paths. The Habits root shows weekly progress, the last seven days, and a current daily streak; Todos surfaces due habit check-ins without turning them into tasks.
- Relationship follow-ups bridge into Todos as ordinary contact-linked, undoable tasks. Todos likewise links due relationship guidance back to Relationships and due repeated practices back to Habits, preserving each domain's identity while making the combined day actionable.

Increment 3's automated evidence gate is complete: 1,877 engine tests plus 36 declared skips, 118 Flutter tests plus the intentional internal-build external-channel skip, tier coverage of 94.2% deterministic core / 90.3% product logic / 68.1% transport, a macOS build, five macOS real-engine tests, and the same five tests on a local iPhone 17 Pro simulator all pass. A disposable-copy exercise migrated the real task to v4 with one backup, zero repair issues, and byte-identical source data. Human glance-time, compare/sequence speed, correction rate, and local retrieval quality require ordinary use of an explicitly deployed build; automated harnesses never target Luis's physical phone.

Increment 4's automated evidence gate is complete: 1,904 engine tests plus 36 declared skips, 123 Flutter tests plus the intentional external-channel skip, tier coverage of 94.2% deterministic core / 90.5% product logic / 68.1% transport, a macOS build, five macOS real-engine tests, and the same five tests on the explicitly selected local iPhone 17 Pro simulator all pass. The proposal benchmark accepts 10/10 deterministic scenarios without immediate correction (gate ≥80%). A disposable-copy exercise migrated the real task to v5 with one backup, zero repair issues, and byte-identical source data. The simulator run reached roughly 504 MB RSS during its short sample, completed normally, was shut down, and left no app/test process; this is not a long-soak leak claim.

Increment 6's automated evidence gate is complete: 1,907 engine tests plus 36 declared skips, 138 Flutter tests plus the intentional external-channel skip, tier coverage of 94.2% deterministic core / 90.8% product logic / 68.1% transport, a macOS build, five macOS real-engine tests, external-channel isolation, secret scan, and the 24/60 conformance ratchet all pass. New relationship, signal, and durable-suggestion tests were calibrated against deliberate regressions before restoration. Five-day dogfood, perceived continuity, and dismissal-fatigue gates require ordinary use of an explicitly deployed build and are not inferred from automated verification.

Historical increment evidence above remains proof recorded at each boundary. Volatile final-tree
counts, coverage, builds, simulator runs, and deployment state live only in `WORK-CAPSULE.md`; this
product spec does not freeze a second “latest” aggregate that will immediately drift.

## 0. Product decision

Plenara is a focused personal follow-through system organized around three things Luis returns to most: people, one-off commitments, and repeated practices.

- **Relationships** remembers people, relationship rhythms, facts, and actual contact, then suggests an actionable next connection.
- **Todos** holds one-off commitments and the focused current-day view; its secondary Plan surface externalizes time, workload, deadlines, and unscheduled work.
- **Habits** holds repeated practices, weekly targets, dated check-ins, and progress over time.
- **Library** remains the secondary complete browser for goals, guided routines, trackers, journal, projects/areas, learned phrases, automations, and generic data.
- **The conversation/action ledger** preserves how current truth was reached.
- **Plena is global and adaptive:** full-screen at rest or in deep conversation, compact beside planning work, and a quiet ember on detail surfaces.
- **Voice is first-class and global.** It is not forced to carry persistent state, comparison, sequencing, or precision editing alone.

The governing priority is **usability > capability > performance > minimalism**. Sparse UI is not a virtue when it hides the plan.

---

## 1. Governing principles

### P17.1 — Multimodal parity, not modality sameness

Every core outcome is reachable by natural voice, while every consequential state is inspectable without speaking. Voice, touch, pointer, and keyboard may use forms suited to them; they converge on the same business-logic command and durable execution.

This replaces “the visual design is never compromised for touch/keyboard.” A planner necessarily benefits from spatial comparison and direct manipulation. The invariant worth preserving is one mutation path, not one interaction shape.

### P17.2 — User state outranks system presence

Planning objects carry the user's commitments, constraints, and progress. Plena carries system state, relationship, and guidance. Presence yields visual hierarchy whenever user state exists.

### P17.3 — Current truth and history are separate

Relationships, Todos, Habits, and Plan show current truth. The ledger shows the utterance/action, result, failures, and undo that produced it. Neither replaces the other, and neither is ephemeral.

### P17.4 — Atomic actions act; planning proposals are inspectable

An unambiguous, reversible, single-object action executes immediately, appears in the plan, and is described in one past-tense sentence with targeted undo.

Exploratory, ambiguous, capacity-changing, or multi-record planning produces an inspectable proposal. The proposal may be accepted wholly or edited item by item. This is not a generic confirmation dialog; it is the planning artifact the user asked to reason about.

### P17.5 — One mutation door

Voice commands, direct manipulation, inline edits, automation approval, proposals, and undo enter the same typed `ExecutionCoordinator`. UI code never mutates storage and never synthesizes English as an internal command.

### P17.6 — Calm means selective, not empty

Calmness comes from hierarchy, progressive disclosure, limited simultaneous emphasis, and stable placement. It does not come from withholding the information needed to orient or plan.

### P17.7 — Capability claims follow represented data

Plenara does not claim capacity, dependency, conflict, energy, or recurrence reasoning until the relevant fields exist, migrate correctly, and participate in the projection.

---

## 2. Information architecture

### 2.1 Relationships

Relationships provides:

- creation, editing, and undoable deletion of people, with dependent facts/interactions/relationship edges removed atomically and task references unlinked;
- visible, editable facts inside their person rather than anonymous child rows;
- a Focus-first home capped to the eight highest-priority due people, with an explicit expansion for the remainder, global person search, circle filters carrying membership/due counts, and urgency-first circle/all-people views rather than an always-expanded alphabetical address book;
- a visible per-person Move menu and an Organize mode that moves several selected people to a new circle as one undoable action; moving resets inherited goals to the destination defaults while already-present members retain custom overrides;
- a typed interaction timeline whose medium is one of in person, FaceTime, phone, text, or email, whose depth is Quick touch or Meaningful connection, plus optional activity context/note and a past date;
- inherited two-clock relationship goals and deterministic “who to contact next” ranking shared with Todos;
- independent role tags (`Family`, `Friend`, `Neighbor`, `Work`, `Community`, `Second-degree`, or custom), proximity (`Household`, `Local`, `Remote`, `Unknown`), and lifecycle (`Active`, `Seasonal`, `Paused`, `Archived`);
- repeatable selective iOS Contacts import through Apple's one-time system picker and organization step, plus external phone, FaceTime, and email launch actions.

Adding a follow-up emits an ordinary contact-linked task into Todos. Opening a system communication app does not fabricate an interaction; the user logs the completed connection explicitly.

The built-in category shortcuts are Close family, Close local friend, Close remote friend, Friend to keep connected, Old remote friend, Neighbor, Local community, Second-degree connection, Household, and Context only. Assigning one atomically sets its circle, role, proximity, lifecycle, and inherited tracking switches; later edits may tune any axis independently. “Meaningful” means a reciprocal, attentive exchange or shared experience that leaves the user more current with or connected to the person. Medium and duration inform the default but never decide it alone.

Voice reaches the same commands directly: categorize a named person, pause or resume their reminders, set either clock to an exact number of days, ask who is due, and log a Quick or Meaningful interaction. Relationship suggestions name which clock is due and prefer in-person connection for Household/Local people and phone or FaceTime for Remote people; unknown proximity stays channel-neutral.

This separation follows the Social Convoy distinction between closeness circles and role composition, and the evidence that relationship layers, communication mode/proximity, weak ties, and dormant ties serve different functions: [Social Convoy](https://pmc.ncbi.nlm.nih.gov/articles/PMC7283809/), [network layers](https://academic.oup.com/scan/article/11/12/1952/2544446), [proximity and mode](https://pmc.ncbi.nlm.nih.gov/articles/PMC10011020/), [weak ties](https://pubmed.ncbi.nlm.nih.gov/24769739/), and [dormant ties](https://business.gwu.edu/sites/g/files/zaxdzs5326/files/15_FP.SP_Walter.J_15levin_2011a.pdf). These sources motivate the model; the concrete labels and cadences are product defaults, not claims of universal social science thresholds.

### 2.2 Todos

Todos is the default root for one-off commitments. It retains the bounded Now/Next/Later task projection, direct completion, latest targeted undo, operational/repair state, relationship signals, and fast capture. Repeated work does not masquerade as a recurring task: due habits appear in a clearly labeled Habits card with a direct check-in and doorway to the Habits root.

The secondary Plan workspace retains its phone day strip, selected-day agenda, load/capacity, unscheduled queue, deadlines, conflict treatment, direct scheduling/resizing/completion, and multi-select. Tablet/desktop expands those semantics into week columns and a queue.

### 2.3 Habits

Habits owns practices intended to repeat. Each habit carries a title, an active/paused state, and a target of one to seven completions per week. Each completion is a dated `habit_checkin`. The UI exposes creation, correction, pause/resume, undoable deletion, one-tap daily check-in, weekly progress, a seven-day history, and the current consecutive-day streak. At most one check-in per local day counts.

Guided movement routines and quantitative trackers remain distinct secondary capabilities. A routine is a reusable sequence Plena can walk through; a tracker records a measure such as water or weight; neither is silently relabeled a habit.

### 2.4 Secondary tools and the conversation/action ledger

Plan remains the precise task scheduling workspace. Library remains the complete browser for goals, guided routines, quantitative trackers, journal, projects/areas, learned phrases, automations, and all generic data. Generic archetypes remain the fallback for emergent user-authored data.

Each entry carries:

- final user transcript or typed input;
- assistant response;
- routing/outcome state;
- links to affected records and durable execution;
- proposal and acceptance state where relevant;
- failure/recovery state;
- targeted undo/change action when still valid.

The current spoken reply is always visible as text during speech and remains discoverable after relaunch.

### 2.5 Global navigation and voice

Primary navigation is `Relationships / Todos / Habits`. Plan and Library are secondary actions from Todos and remain directly voice-reachable. The ledger is reached from the latest-change/history affordance and by voice. Plena's voice target remains global and accessible, but tap-anywhere applies only where it cannot collide with interactive objects or controls. Natural navigation phrases use product words (“show my habits,” “open relationships,” “go to todos”), while domain actions route to skills rather than navigation.

---

## 3. Plena's adaptive presence

| Context | Form | Role |
|---|---|---|
| Empty/rest/deep conversation | Full-screen | relationship, state, listening/speaking focus |
| Todos/Plan with active content | Compact collaborator | system state and contextual guidance beside user state |
| Relationships/Habits/Library/detail/edit | Ember | continuity and global voice access without owning hierarchy |
| Reduced motion/still preference | Static per-state form | same meaning, no tracing or continuous motion |

Plena never despawns conceptually, but may become visually quiet enough to cease competing. Presence gestures and glyphs are decoration/affect layered on explicit text and state. The extended glyph vocabulary is internally available but routine firing is conservative, semantically fenced, and user-disableable with the still-presence setting.

---

## 4. Planner semantics

### 4.1 Minimal task model

The first useful task schema adds:

- `status`;
- `scheduledStartAt`;
- `estimatedMinutes`;
- `priority`;
- `projectRef` and/or `areaRef`;
- `contactRefs`;
- `notes`;
- `completedAt`.

`dueAt` remains a deadline and is never overloaded as scheduled time. Existing records migrate through a contiguous, reversible migration chain before the UI relies on these fields.

### 4.2 Later planning semantics

Dependencies, `blockedReason`, energy/context, recurrence, and explicit capacity become available only with their migrations, rendering, and benchmark use cases. Unknown is represented as unknown, not inferred as certainty.

### 4.3 Proposals

A `PlanProposal` contains typed candidate operations, rationale facts, conflicts, explicit omission reasons, unchanged items, and record fingerprints. Previewing performs no writes. Acceptance revalidates current record fingerprints, then submits selected operations as one durable execution with one visible undo/change entry. Stale proposals never apply silently.

---

## 5. Interaction contract

### 5.1 Voice context

The NLU context includes the visible date range, selected day, selected records, numbered visible objects, active proposal, and recent execution references. Commands such as “move these two,” “the first one,” and “after school pickup” resolve against structured ids, not screen text scraping.

### 5.2 Direct manipulation

Complete, schedule, reschedule, resize, defer, and inline edit emit typed commands. On Todos, the
task body's row tap is navigation to its shared detail editor; completion belongs only to the
explicit leading circle. A trailing chevron and accessibility hint communicate the row action.
Both controls consume their gestures before the background voice target. Gesture completion waits
for positive mutation/persistence events, never elapsed-time assumptions. Optimistic visuals must
reconcile to a typed execution state and visibly reverse on failure.

### 5.3 Failure and recovery

Every failure has an address:

- routing uncertainty → targeted clarification;
- stale proposal → refresh/rebase surface;
- write/recovery issue → latest-change/attention item with truthful durable state;
- offline/index unavailable → visible degraded mode;
- unavailable mic → explicit text/keyboard path.

---

## 6. Accessibility and engagement

- Dynamic Type may reflow cards and navigation; the product does not preserve a composition by clipping information.
- Screen readers receive ordered Relationships/Todos/Habits/Plan controls and complete text/caption
  meaning. A consolidated announced Plena-state node and automatic TTS deference remain
  accessibility destinations (Specs 12 §6.4 and 15 §8.4).
- Reduced motion and independent still-presence preferences are first-class.
- Quiet text meets WCAG AA contrast on its actual rendered ground.
- Engagement is measured by useful return behavior, plan revisitation, successful capture-to-plan placement, reduced corrective turns, and trusted undo—not glyph frequency or time staring at animation.

---

## 7. Evidence gates

1. Across scripted Todos states, next commitment, overdue risk, and latest undoability are identified in five seconds in at least 9/10 cases.
2. Mixed voice captures land in the intended semantic place without increasing median capture time by more than 10%.
3. Compare/sequence benchmark scenarios are at least 30% faster than the enriched Today-only baseline and require fewer corrective turns.
4. Every mutation origin reaches the same execution journal and undo ledger.
5. Every spoken result appears as simultaneous text and survives relaunch in the ledger.
6. Relationships, Todos, Habits, and Plan remain usable at large text, reduced motion, muted mode, offline, and without microphone permission.
7. Phone safe areas, tablet split layouts, and desktop week layouts pass rendered-output review, not widget-tree inspection alone.

---

## 8. Decision record

- **D17.1:** Living planner is the product model; presence-only home is a historical implementation stage.
- **D17.2:** Relationships/Todos/Habits are primary. Plan, Library, and the durable ledger remain directly reachable secondary tools.
- **D17.3:** Voice is global and first-class, not UI-exclusive.
- **D17.4:** Planner UI may be purpose-built; generic archetypes remain for emergent data.
- **D17.5:** Atomic reversible actions act-then-describe; planning proposals are inspectable artifacts.
- **D17.6:** Plena scales full-screen → collaborator → ember according to information needs.
- **D17.7:** Current truth is never made ephemeral to preserve visual minimalism.
- **D17.8:** First-party domain workspaces may compose built-in types and actions; the no-per-type rule continues to govern emergent authored data, and the generic browser remains the complete fallback.
- **D17.9:** Relationship health uses one primary intention circle plus independent roles, proximity, and lifecycle. Circle defaults feed separate any-contact and meaningful-connection clocks; explicit per-person overrides win. Completed typed interactions advance the appropriate clocks. Launching a communication app or planning contact is not evidence that contact occurred.
- **D17.10:** Habits are first-class repeated practices with weekly targets and dated check-ins. They are distinct from one-off tasks, guided routines, and quantitative trackers.
- **D17.11:** Cross-domain integration creates typed links and doorways, not category collapse: relationship follow-ups become contact-linked todos; due habits remain habit check-ins surfaced from Todos.
- **D17.12:** Relationships is attention-first, search-complete, and circle-navigable. The default does not render the whole address book. Single and bulk circle moves are direct, durable, and undoable; only people who change circles inherit destination defaults.
