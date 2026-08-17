# Spec 17 — Living Planner & Multimodal Product Model

**Status:** v0.3 — 2026-08-17, active implementation authority. Today, phone/desktop Plan, purpose-built Library, the durable conversation ledger, task schema v4, structured planner context, in-process retrieval, cloud admission, and the adaptive full-screen/collaborator presence are wired; proposals, detached operations, and the detail ember remain later increments.
**Supersedes:** research §2.2's overlay-only/no-touch rule; Spec 07 P1–P2 and its four-surface model; Spec 15 D1/D14 where they make full-screen presence or ephemeral exchange the steady-state product. Those documents remain design history and point here for current behavior.
**Depends on:** Specs 01–06 for schema, skills, routing, orchestration, functional behavior, and storage; Spec 07 for visual language and generic archetypes; Spec 12 for voice; Spec 15 for Plena's renderer.

---

## Current realization — Increment 3

- Opening the app renders the deterministic Today projection rather than an ephemeral greeting. It includes bounded Now/Next/Later sections, one relationship date, the latest durable execution with targeted undo, Inbox count, operational notices, and repair state.
- Voice and typed capture continue through `Session.handle`; Today completion calls the typed `Session.completeTask` command directly. Both converge on `ExecutionCoordinator` and its durable device-local journal.
- The device-local conversation ledger retains the final utterance, full reply, routing source, time, and execution link for 250 turns. It is a user-facing product history distinct from content-bearing internal diagnostic logs. History-linked writes expose targeted undo.
- Task schema v3 owns `status`, `scheduledStartAt`, `estimatedMinutes`, `priority`, `projectRef`, `areaRef`, `contactRefs`, `notes`, and `completedAt`; `dueAt` remains deadline-only. Project and area are registered record types.
- Plena remains full-bleed during conversation and yields within the same canvas when Today is visible. The populated surface has an explicit accessible voice target; tap-anywhere remains active only on non-interactive space.
- Onboarding uses the same warm presence and palette, pins both decisions outside its scrollable story area, and states the internal-dogfood diagnostic policy. Platform icons are generated from a deterministic Plena particle mark for iOS, macOS, and Windows.
- Phone Plan now has a week strip, selected-day agenda, deadlines, unscheduled queue, load, conflict state, direct schedule/defer/resize/complete actions, and multi-select. Desktop expands the same semantics into a week/queue workspace with drag-to-day scheduling.
- Library now exposes purpose-built People, Goals, Routines, Trackers, Journal, Projects & areas, Learned phrases, and Automations summaries while preserving the complete editable data browser.
- Task schema v4 represents dependencies, blocked reason, energy, contexts, and recurrence. Existing folders receive missing built-ins and newer versioned types without clobbering authored or same-version definitions; exact definition and record backups precede migration.
- Plan and Today publish structured visible dates, ordered objects, and selection ids. Contextual commands such as “move these to tomorrow at 10am” and “make the first one 45 minutes” resolve against those ids and enter the same durable execution/undo path as touch and pointer actions.
- Production routing now builds an in-process deterministic feature-hash index and orders common work as corpus → bounded accepted retrieval with deterministic slot extraction → cloud residual → visible clarification. Localhost embeddings remain an explicit development experiment, not a runtime dependency.
- Every Anthropic request crosses one persisted admission controller before HTTP: 200 calls per local day and 30 per rolling ten minutes. Corrupt or unwritable usage state fails closed, and Settings shows both counters.

Increment 3's automated evidence gate is complete: 1,877 engine tests plus 36 declared skips, 118 Flutter tests plus the intentional internal-build external-channel skip, tier coverage of 94.2% deterministic core / 90.3% product logic / 68.1% transport, a macOS build, five macOS real-engine tests, and the same five tests on a local iPhone 17 Pro simulator all pass. A disposable-copy exercise migrated the real task to v4 with one backup, zero repair issues, and byte-identical source data. Human glance-time, compare/sequence speed, correction rate, and local retrieval quality require ordinary use of an explicitly deployed build; automated harnesses never target Luis's physical phone.

## 0. Product decision

Plenara is a **living planner with a relational assistant**, not a voice demo with data behind it and not a conventional task manager with a mascot attached.

- **Today** answers what matters now without requiring a query.
- **Plan** externalizes and manipulates time, workload, deadlines, and unscheduled work.
- **Library** holds durable domains: people, goals, routines, trackers, journal, projects/areas, learned phrases, automations, and generic data.
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

Today and Plan show current truth. The ledger shows the utterance/action, result, failures, and undo that produced it. Neither replaces the other, and neither is ephemeral.

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

### 2.1 Today

Today is the default populated state. In order:

1. **Now** — the active or immediately due commitment, if any.
2. **Next** — at most three meaningful objects, ordered by scheduled time and risk rather than record type.
3. **Later** — a compact rest-of-day/week outlook and load signal.
4. **Relationship nudge** — at most one genuinely timely person-oriented prompt.
5. **Latest change** — the most recent durable action and its targeted undo while available.

Tasks, reminders, routines, goals, and relationship nudges retain their semantic identity even when projected together. A reminder is not silently converted into a task.

Empty Today is a legitimate full-screen Plena/rest state with a clear global voice affordance. Populated Today makes Plena compact enough that the plan is identifiable in a five-second glance.

### 2.2 Plan

Phone Plan contains:

- a day strip;
- selected-day agenda;
- visible load/capacity;
- unscheduled queue;
- deadlines separated from scheduled blocks;
- calm conflict and overdue treatment;
- direct schedule, reschedule, duration, completion, defer, and inline-edit actions.

Tablet/desktop Plan expands to week columns, unscheduled queue, drag/drop/resize, and a Plena/conversation rail. Responsive layouts preserve semantics; they do not merely stretch phone cards.

### 2.3 Library

Library provides purpose-built summaries for People, Goals, Routines, Trackers, Journal, Projects/Areas, learned phrases, and Automations, plus a generic data browser. Planner projections are allowed to be product-specific binary UI. Generic archetypes remain the fallback for emergent user-authored data.

### 2.4 Conversation/action ledger

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

Primary navigation is `Today / Plan / Library`. The ledger is reached from the latest-change/history affordance and by voice. Plena's voice target remains globally reachable and accessible, but tap-anywhere applies only where it cannot collide with plan objects or controls.

---

## 3. Plena's adaptive presence

| Context | Form | Role |
|---|---|---|
| Empty/rest/deep conversation | Full-screen | relationship, state, listening/speaking focus |
| Today/Plan with active content | Compact collaborator | system state and contextual guidance beside user state |
| Library/detail/edit | Ember | continuity and global voice access without owning hierarchy |
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

A `PlanProposal` contains typed candidate operations, rationale facts, conflicts, unchanged items, and an expiry/rebase token. Previewing performs no writes. Acceptance revalidates current record versions, then submits selected operations as one durable execution with one visible undo/change entry. Stale proposals never apply silently.

---

## 5. Interaction contract

### 5.1 Voice context

The NLU context includes the visible date range, selected day, selected records, numbered visible objects, active proposal, and recent execution references. Commands such as “move these two,” “the first one,” and “after school pickup” resolve against structured ids, not screen text scraping.

### 5.2 Direct manipulation

Complete, schedule, reschedule, resize, defer, and inline edit emit typed commands. Gesture completion waits for positive mutation/persistence events, never elapsed-time assumptions. Optimistic visuals must reconcile to a typed execution state and visibly reverse on failure.

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
- Screen readers receive ordered Today/Plan semantics and explicit Plena state, never particle descriptions as the sole meaning.
- Reduced motion and independent still-presence preferences are first-class.
- Quiet text meets WCAG AA contrast on its actual rendered ground.
- Engagement is measured by useful return behavior, plan revisitation, successful capture-to-plan placement, reduced corrective turns, and trusted undo—not glyph frequency or time staring at animation.

---

## 7. Evidence gates

1. Across scripted Today states, next commitment, overdue risk, and latest undoability are identified in five seconds in at least 9/10 cases.
2. Mixed voice captures land in the intended semantic place without increasing median capture time by more than 10%.
3. Compare/sequence benchmark scenarios are at least 30% faster than the enriched Today-only baseline and require fewer corrective turns.
4. Every mutation origin reaches the same execution journal and undo ledger.
5. Every spoken result appears as simultaneous text and survives relaunch in the ledger.
6. Today and Plan remain usable at large text, reduced motion, muted mode, offline, and without microphone permission.
7. Phone safe areas, tablet split layouts, and desktop week layouts pass rendered-output review, not widget-tree inspection alone.

---

## 8. Decision record

- **D17.1:** Living planner is the product model; presence-only home is a historical implementation stage.
- **D17.2:** Today/Plan/Library are primary; the ledger is durable history.
- **D17.3:** Voice is global and first-class, not UI-exclusive.
- **D17.4:** Planner UI may be purpose-built; generic archetypes remain for emergent data.
- **D17.5:** Atomic reversible actions act-then-describe; planning proposals are inspectable artifacts.
- **D17.6:** Plena scales full-screen → collaborator → ember according to information needs.
- **D17.7:** Current truth is never made ephemeral to preserve visual minimalism.
