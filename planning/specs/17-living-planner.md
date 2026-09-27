# Spec 17 — Living Planner & Multimodal Product Model

**Status:** v2 — 2026-09-26. Approved Astra first-principles redesign: Today, People, Tasks, and Routines, with a continuing conversation as the guiding interaction. Approval and rationale: [design review](../../reviews/2026-09-26-first-principles-review.md). Typed validation, durable execution, undo, local storage, and precise task scheduling remain foundations.
**Supersedes:** research §2.2's overlay-only/no-touch rule; Spec 07 P1–P2 and its four-surface model; Spec 15 D1/D14 where they make full-screen presence or ephemeral exchange the steady-state product. Those documents remain design history and point here for current behavior.
**Depends on:** Specs 01–06 for schema, skills, routing, orchestration, functional behavior, and storage; Spec 07 for visual language and generic archetypes; Spec 12 for voice; Spec 15 for Plena's renderer.

---

## Current realization — guiding conversation redesign

- Today is the default integrated landing page. It offers a person to make space for, one actionable commitment, and a practice that fits the chosen rhythm, without manufacturing missing evidence. People, Tasks, and Routines are peers; Plan, Library, History, settings, diagnostics and repair remain secondary tools.
- A host above Navigator provides labeled Talk to Plena and Message Plena controls on roots and pushed details. Both enter one resumable conversation; voice and typing remain available together. Root navigation remains available after returning. Detail focus follows the named record.
- Production conversation uses `Session.converse`: recent device-local dialogue, current focus, time, and permitted read/propose tools enter a GPT Responses loop. `Session.handle` remains the explicit local command/capability engine. Selected unambiguous local commands remain available offline; expressive feelings never become implicit mood logs in the guide path.
- GPT proposes an editable receipt. Applying selected changes validates schemas, typed references, record fingerprints, past completion dates and duplicate practice days, then enters one durable `ExecutionCoordinator` mutation with undo. Receipt identity in the execution journal prevents replay after restart. Conversation itself needs no confirmation ritual.
- The device-local ledger retains up to 250 turns, full replies, outcomes, affected record ids and execution links. The last 16 relevant guide exchanges provide continuing context. It is a bounded memory window, not indefinite model memory. Guide turns omit input/reply/record content from turn diagnostics; voice recognizer diagnostics retain their independently disclosed internal-channel policy.
- Task schema v3 introduced `status`, `scheduledStartAt`, `estimatedMinutes`, `priority`, `projectRef`, `areaRef`, `contactRefs`, `notes`, and `completedAt`; v4 added dependency/energy/context/recurrence semantics and v5 added `reviewDecision`. `dueAt` remains deadline-only. Project and area are registered record types.
- Plena’s presence accompanies explicit text, controls, and listening/thinking state. Guided routine playback and internal renderer tools retain the full-bleed presence surface; it no longer hides the everyday conversation entrance.
- On primary roots, the global secondary-tools menu participates in the screen header layout rather than overlaying workflow actions. Manual-write confirmations expose Undo for five seconds and then dismiss automatically; newer completed actions replace older transient feedback instead of queuing behind it.
- Onboarding uses the same warm presence and palette, pins both decisions outside its scrollable story area, and states the internal-dogfood diagnostic policy. Platform icons are generated from a deterministic Plena particle mark for iOS, macOS, and Windows.
- Phone Plan now has a week strip, selected-day agenda, deadlines, unscheduled queue, load, conflict state, direct schedule/defer/resize/complete actions, and multi-select. Desktop expands the same semantics into a week/queue workspace with drag-to-day scheduling.
- Library now exposes purpose-built People, Habits, Goals, Routines, Trackers, Journal, Projects & areas, Learned phrases, and Automations summaries while preserving the complete editable data browser. People opens a People workspace where contacts, contact details, facts, and contact history are visible and mutable rather than anonymous schema rows.
- Task schema v4 represents dependencies, blocked reason, energy, contexts, and recurrence. Existing folders receive missing built-ins and newer versioned types without clobbering authored or same-version definitions; exact definition and record backups precede migration.
- Plan and Tasks publish structured visible dates, ordered objects, and selection ids. Contextual commands such as “move these to tomorrow at 10am” and “make the first one 45 minutes” resolve against those ids and enter the same durable execution/undo path as touch and pointer actions.
- Production routing now builds an in-process deterministic feature-hash index and orders common work as corpus → bounded accepted retrieval with deterministic slot extraction → cloud residual → visible clarification. Localhost embeddings remain an explicit development experiment, not a runtime dependency.
- Every Anthropic request crosses one persisted admission controller before HTTP: 200 calls per local day and 30 per rolling ten minutes. Corrupt or unwritable usage state fails closed, and Settings shows both counters.
- Task schema v5 adds the explicit weekly-review decision (`keep`, `defer`, or `drop`) through a contiguous 4→5 migration. A structured weekly review persists evidence and editable decisions, revalidates record fingerprints before apply, and commits selected task changes through one durable execution and undo.
- `PlanProposal` is a durable no-write preview with selected items, proposed times, estimates, rationale, conflict delta, and explicit omission reasons. It respects represented capacity, deadlines, dependencies, and blocked state. Voice can move or exclude numbered proposal items; apply revalidates every task fingerprint and commits once.
- Long weekly/pattern synthesis and custom-capability authoring enter one persistent serial `OperationCenter`. The initiating turn returns immediately, Tasks renders progress/cancel state, terminal delivery is exactly once, and relaunch marks uncertain in-flight work interrupted rather than risking duplicate provider spend.
- A validated authored-capability preview is persisted device-locally until activation, cancellation, or an unrelated move-on turn. Only activation promotes it to the live type/skill registry.
- Morning plans and relationship/event-preparation cards are deterministic durable artifacts on Tasks. A draft remains until accepted, dismissed, or superseded; relationship preparation uses only saved facts, dates, and the latest logged interaction.
- Generative prompt assembly stamps its declared record classes and explicit-invocation consent into every implemented request. The same declarations are visible in Settings; journal is excluded from all current assemblers.
- People-linked task commitments keep their relationship identity in Tasks, Plan, weekly proposals/reviews, and person detail. Planned interactions and recurring relationship dates appear in the selected Plan day; goals and active routines remain visible as planning rhythms.
- Upcoming relationship dates produce one durable proactive suggestion with explicit Keep, Dismiss, and Tomorrow outcomes. Deferral survives relaunch and returns when due; a resolved suggestion does not respawn unchanged.
- Each person belongs to one primary intention circle: Core, Close, Keep connected, Keep warm, or Context only. The circle supplies inherited touch/meaningful defaults of 7/14, 14/30, 30/60, 90/off, and off/off days respectively. Roles, proximity, and lifecycle are independent descriptors; per-person goal overrides store only the delta. Existing 7/21/60-day records keep their exact old cadence until the user explicitly chooses a new circle.
- Completed typed interactions — in person, FaceTime, phone, text, or email — advance an “any contact” clock. Each is also Quick touch or Meaningful connection and only the latter advances the second clock. In-person, FaceTime, and phone default meaningful; text and email default quick; the user can always override the default. Planned interactions and launch-button taps do not pretend contact happened.
- People opens on a bounded list of connection opportunities, with alphabetized displayed lists and search/filter access to everyone. Actual logged cadence can suggest follow-through, but no history is neutral “Last update unknown,” never an unhealthy relationship verdict. A recent acknowledgement suppresses reminders for the chosen rhythm without fabricating an interaction date. Circle, roles, proximity and lifecycle remain independent and undoable. Communication app launches are not evidence that contact happened.
- On iOS, each import opens Apple's multi-contact picker for one-time access to the entries the user explicitly selects. It works under denied, limited, full, or not-yet-determined Contacts authorization and does not ask Plenara for ongoing address-book permission. A compact organization step assigns a category before first import and defaults to Context only so bulk import creates no reminder debt. Reopening the picker can import another person or refresh an existing match without cloning it or overwriting the existing relationship plan. Imported contact and relationship-plan fields sync as ordinary plaintext JSON under the current storage model. Call, FaceTime, and email actions launch the corresponding system handler; launching is never logged as a completed interaction.
- Routines combines repeated practices with a doorway to guided sequences. Habit v2 adds reason, cue, normal version, minimum version and optional preferred weekdays. Habit-checkin v2 records completed, minimum, or deliberately skipped; missing updates remain unknown. Minimum versions count, skips do not. There is one update per local day; correcting it edits the same record with undo. The daily streak is no longer a UI success criterion.
- Calendar and Reminders offer user-initiated read-only browsing under separate EventKit permissions. Selected items enter a draft, not planner writes. Calendar attendance and task completion always remain unconfirmed until Luis says otherwise. Paste selected text and Shortcuts Capture with Plenara provide deliberate evidence intake. No message-history or call-log access is claimed.
- App Shortcuts open Plena or retain a selected capture in this device’s unlock-only keychain until review. Notification tap/Discuss opens the relevant conversation. Reminder lock-screen text omits names/details and is silent by default. No daily engagement campaign is introduced.
- GPT uses a separate secure OpenAI credential and explicit context consent. A persisted monthly USD budget reserves every request’s full possible output cost before HTTP, settles measured usage, and retains uncertain reservations. Zero disables requests; malformed/rollback/unwritable state fails closed. See Spec 08 for provider boundaries.


Increment 3's automated evidence gate is complete: 1,877 engine tests plus 36 declared skips, 118 Flutter tests plus the intentional internal-build external-channel skip, tier coverage of 94.2% deterministic core / 90.3% product logic / 68.1% transport, a macOS build, five macOS real-engine tests, and the same five tests on a local iPhone 17 Pro simulator all pass. A disposable-copy exercise migrated the real task to v4 with one backup, zero repair issues, and byte-identical source data. Human glance-time, compare/sequence speed, correction rate, and local retrieval quality require ordinary use of an explicitly deployed build; automated harnesses never target Luis's physical phone.

Increment 4's automated evidence gate is complete: 1,904 engine tests plus 36 declared skips, 123 Flutter tests plus the intentional external-channel skip, tier coverage of 94.2% deterministic core / 90.5% product logic / 68.1% transport, a macOS build, five macOS real-engine tests, and the same five tests on the explicitly selected local iPhone 17 Pro simulator all pass. The proposal benchmark accepts 10/10 deterministic scenarios without immediate correction (gate ≥80%). A disposable-copy exercise migrated the real task to v5 with one backup, zero repair issues, and byte-identical source data. The simulator run reached roughly 504 MB RSS during its short sample, completed normally, was shut down, and left no app/test process; this is not a long-soak leak claim.

Increment 6's automated evidence gate is complete: 1,907 engine tests plus 36 declared skips, 138 Flutter tests plus the intentional external-channel skip, tier coverage of 94.2% deterministic core / 90.8% product logic / 68.1% transport, a macOS build, five macOS real-engine tests, external-channel isolation, secret scan, and the 24/60 conformance ratchet all pass. New relationship, signal, and durable-suggestion tests were calibrated against deliberate regressions before restoration. Five-day dogfood, perceived continuity, and dismissal-fatigue gates require ordinary use of an explicitly deployed build and are not inferred from automated verification.

Historical increment evidence above remains proof recorded at each boundary. Volatile final-tree
counts, coverage, builds, simulator runs, and deployment state live only in `WORK-CAPSULE.md`; this
product spec does not freeze a second “latest” aggregate that will immediately drift.

## 0. Product decision

Plenara is a focused personal follow-through system organized around three things Luis returns to most: people, one-off commitments, and repeated practices.

- **People** remembers people, relationship rhythms, facts, and actual contact, then suggests an actionable next connection.
- **Tasks** holds one-off commitments and the focused current-day view; its secondary Plan surface externalizes time, workload, deadlines, and unscheduled work.
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

Today, People, Tasks, Routines, and Plan show current truth. The ledger shows the utterance/action, result, failures, and undo that produced it. Neither replaces the other, and neither is ephemeral.

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

### 2.1 People

People provides:

- creation, editing, and undoable deletion of people, with dependent facts/interactions/relationship edges removed atomically and task references unlinked;
- visible, editable facts inside their person rather than anonymous child rows;
- a Focus-first home whose bounded set is capped to the eight highest-priority due people, with an explicit expansion for the remainder, global person search, and combinable circle/proximity filters carrying membership/due counts; every displayed list is alphabetized by name after the Focus set is selected, while labeled badges distinguish within-rhythm, approaching, due, overdue based on actual logs, unknown-history, acknowledged, and untracked people and state overdue age relative to each person's goal;
- a visible per-person Organize menu and multi-select Organize mode that change circle or proximity as one undoable action; moving circles resets inherited goals to the destination defaults while already-present members retain custom overrides, while proximity changes never touch goals;
- a typed interaction timeline whose medium is one of in person, FaceTime, phone, text, or email, whose depth is Quick touch or Meaningful connection, plus optional activity context/note and a past date;
- inherited two-clock relationship goals and deterministic “who to contact next” ranking shared with Tasks;
- independent role tags (`Family`, `Friend`, `Neighbor`, `Work`, `Community`, `Second-degree`, or custom), proximity (`Household`, `Local`, `Remote`, `Unknown`), and lifecycle (`Active`, `Seasonal`, `Paused`, `Archived`);
- repeatable selective iOS Contacts import through Apple's one-time system picker and organization step, plus external phone, FaceTime, and email launch actions.

Adding a follow-up emits an ordinary contact-linked task into Tasks and uses proximity to make the action concrete: make plans for Local/Household people, plan a call or FaceTime for Remote people, and use a neutral reach-out for unknown proximity. Opening a system communication app does not fabricate an interaction; the user logs the completed connection explicitly.

The built-in category shortcuts are Close family, Close local friend, Close remote friend, Friend to keep connected, Old remote friend, Neighbor, Local community, Second-degree connection, Household, and Context only. Assigning one atomically sets its circle, role, proximity, lifecycle, and inherited tracking switches; later edits may tune any axis independently. “Meaningful” means a reciprocal, attentive exchange or shared experience that leaves the user more current with or connected to the person. Medium and duration inform the default but never decide it alone.

Voice reaches the same commands directly: categorize a named person, mark them Local/Remote/Household/unknown without changing their circle, pause or resume their reminders, set either clock to an exact number of days, ask who is due, and log a Quick or Meaningful interaction. Relationship suggestions name which clock is due and prefer in-person connection for Household/Local people and phone or FaceTime for Remote people; unknown proximity stays channel-neutral.

This separation follows the Social Convoy distinction between closeness circles and role composition, and the evidence that relationship layers, communication mode/proximity, weak ties, and dormant ties serve different functions: [Social Convoy](https://pmc.ncbi.nlm.nih.gov/articles/PMC7283809/), [network layers](https://academic.oup.com/scan/article/11/12/1952/2544446), [proximity and mode](https://pmc.ncbi.nlm.nih.gov/articles/PMC10011020/), [weak ties](https://pubmed.ncbi.nlm.nih.gov/24769739/), and [dormant ties](https://business.gwu.edu/sites/g/files/zaxdzs5326/files/15_FP.SP_Walter.J_15levin_2011a.pdf). These sources motivate the model; the concrete labels and cadences are product defaults, not claims of universal social science thresholds.

### 2.2 Tasks

Tasks is the root for one-off commitments; Today is the default integrated landing page. It retains the bounded Now/Next/Later task projection, direct completion, latest targeted undo, operational/repair state, relationship signals, and fast capture. Repeated work does not masquerade as a recurring task: due habits appear in a clearly labeled Routines card with a direct check-in and doorway to the Routines root.

Persistent navigation and the raised text-input surface may overlay the planner, but every Tasks action remains reachable and can scroll wholly above those surfaces with visible clearance. The text path must not make Plan, Library, or the final item in any planner section partially obscured or untappable.

The secondary Plan workspace retains its phone day strip, selected-day agenda, load/capacity, unscheduled queue, deadlines, conflict treatment, direct scheduling/resizing/completion, and multi-select. Tablet/desktop expands those semantics into week columns and a queue.

### 2.3 Routines

Habits owns practices intended to repeat. Each habit carries a title, an active/paused state, and a target of one to seven completions per week. Each completion is a dated `habit_checkin`. The UI exposes creation, correction, pause/resume, undoable deletion, one-tap daily check-in, weekly progress, a seven-day history, and flexible weekly progress. Reason, cue, normal/minimum versions, preferred opportunities, and distinct completion/minimum/skip outcomes support starting and restarting. No report is unknown. At most one check-in per local day counts.

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

Primary navigation is `Today / People / Tasks / Routines`. Plan and Library are secondary actions from Tasks and remain directly voice-reachable. The ledger is reached from the latest-change/history affordance and by voice. Plena's voice target remains global and accessible, but tap-anywhere applies only where it cannot collide with interactive objects or controls. Natural navigation phrases use product words (“show my habits,” “open relationships,” “go to todos”), while domain actions route to skills rather than navigation.

---

## 3. Plena's adaptive presence

| Context | Form | Role |
|---|---|---|
| Empty/rest/deep conversation | Text thread with compact presence | relationship, state, listening/speaking focus |
| Tasks/Plan with active content | Compact collaborator | system state and contextual guidance beside user state |
| People/Routines/Library/detail/edit | Ember | continuity and global voice access without owning hierarchy |
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

Complete, schedule, reschedule, resize, defer, and inline edit emit typed commands. On Tasks, the
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
- Screen readers receive ordered Today/People/Tasks/Routines/Plan controls and complete text/caption
  meaning. A consolidated announced Plena-state node and automatic TTS deference remain
  accessibility destinations (Specs 12 §6.4 and 15 §8.4).
- Reduced motion and independent still-presence preferences are first-class.
- Quiet text meets WCAG AA contrast on its actual rendered ground.
- Engagement is measured by useful return behavior, plan revisitation, successful capture-to-plan placement, reduced corrective turns, and trusted undo—not glyph frequency or time staring at animation.

---

## 7. Evidence gates

1. Across scripted Tasks states, next commitment, overdue risk, and latest undoability are identified in five seconds in at least 9/10 cases.
2. Mixed voice captures land in the intended semantic place without increasing median capture time by more than 10%.
3. Compare/sequence benchmark scenarios are at least 30% faster than the enriched Today-only baseline and require fewer corrective turns.
4. Every mutation origin reaches the same execution journal and undo ledger.
5. Every spoken result appears as simultaneous text and survives relaunch in the ledger.
6. People, Tasks, Habits, and Plan remain usable at large text, reduced motion, muted mode, offline, and without microphone permission.
7. Phone safe areas, tablet split layouts, and desktop week layouts pass rendered-output review, not widget-tree inspection alone.

---

## 8. Decision record

- **D17.1:** Living planner is the product model; presence-only home is a historical implementation stage.
- **D17.2:** Today/People/Tasks/Routines are primary. Plan, Library, and the durable ledger remain directly reachable secondary tools.
- **D17.3:** Voice is global and first-class, not UI-exclusive.
- **D17.4:** Planner UI may be purpose-built; generic archetypes remain for emergent data.
- **D17.5:** Atomic reversible actions act-then-describe; planning proposals are inspectable artifacts.
- **D17.6:** Plena scales full-screen → collaborator → ember according to information needs.
- **D17.7:** Current truth is never made ephemeral to preserve visual minimalism.
- **D17.8:** First-party domain workspaces may compose built-in types and actions; the no-per-type rule continues to govern emergent authored data, and the generic browser remains the complete fallback.
- **D17.9:** Relationship health uses one primary intention circle plus independent roles, proximity, and lifecycle. Circle defaults feed separate any-contact and meaningful-connection clocks; explicit per-person overrides win. Completed typed interactions advance the appropriate clocks. Launching a communication app or planning contact is not evidence that contact occurred.
- **D17.10:** Habits are first-class repeated practices with reasons, cues, normal/minimum versions, flexible opportunities and dated completed/minimum/skipped check-ins. Missing check-ins remain unknown. They are distinct from one-off tasks, guided routines, and quantitative trackers.
- **D17.11:** Cross-domain integration creates typed links and doorways, not category collapse: relationship follow-ups become contact-linked todos; practice outcomes remain habit check-ins, surfaced from Today and Routines.
- **D17.12:** People presents bounded opportunities, remains search-complete, and faceted by independent circle and proximity axes. The default does not render the whole address book. Single and bulk organization is direct, durable, and undoable; only circle changes affect inherited goals, while proximity changes the suggested mode and follow-up wording.
