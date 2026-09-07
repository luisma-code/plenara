# Spec 05 — Functional

**Status:** Active v0.6 — audited 2026-09-07. This remains the behavior-flow catalog; Spec 17
supersedes its surface model and makes Relationships, one-off Todos, and tracked Habits the three
primary roots. Six generative kinds are implemented. Deterministic one-person relationship prep is
wired separately from the still-candidate multi-attendee `event_prep` generative flow; meal
suggestion, monthly reflection, and foresight also remain candidates.
**Depends on:** Spec 01 — Meta-Schema & Type System; Spec 02 — Skill DSL; Spec 03 — NLU / Intent; Spec 04 — Architecture
**Blocks:** Spec 07 — UI & Design-Language; Spec 09 — Test
**Precedence:** wired behavior is current truth; this active spec records its contract. The research
document and 05a–05f artifacts preserve rationale and evaluation history.

---

## 0. Purpose & Scope

Specs 01–04 define what the system *is* — types, skills, intents, and the architectural seams between them. This spec defines what the system *does from the user's point of view*: the exact interaction flow for each of the twenty marquee tasks, the edge cases that arise within each, and the UX rules that make the experience feel seamless rather than mechanical.

This spec is the authority for:

1. **The intended interaction flow for each marquee task** — voice in, spoken/visual response out,
   including prompts and branches. Explicit current-realization notes and the implementation take
   precedence where an older worked flow still describes a destination.
2. **Edge cases and failure paths** — what happens when input is ambiguous, records are missing, the user corrects mid-flow, the tier doesn't permit a feature, or the network is absent.
3. **The interaction contract** — the rules governing when the app acts immediately vs. asks first, how corrections feed the corpus, and what "undo" covers.
4. **The free/paid boundary, stated interaction-by-interaction** — exactly which flows require a BYOK key and what the user sees if they don't have one.

It does **not** re-specify the internal mechanisms: type-file format (Spec 01), skill step semantics (Spec 02), routing and the corpus (Spec 03), layer interfaces (Spec 04), view rendering details (Spec 07), or sync conflict resolution (Spec 06). Where this spec names a component or interface, it refers to the definitions in those specs.

---

## 1. Governing Principles for Interaction Design

These principles derive directly from the research doc and the four upstream specs. They are restated here because they govern every flow in §§4–23.

**Voice is uncompromising (P2.1), and UI is equally responsible.** The examples use utterances for
compactness, but current Relationships, Todos, Habits, Plan, Library, and History workflows expose
purpose-built touch/keyboard actions. Both modalities converge on business commands; voice is not a
prerequisite for inspecting, editing, or completing work.

**No silent failure (P2.8).** Every flow has a named exit for every failure mode. There is no "the request was dropped." If the system cannot proceed, it says so and tells the user what to do next.

**Code over AI (P2.4).** Clarification prompts from the interpreter are deterministic — they do not use Claude. Generative synthesis (briefing, coaching, gift suggestions) is explicitly labeled as such in the flows.

**One clarification at a time.** A routing or missing-slot clarification asks one targeted question.
Purpose-built sheets/forms are valid for deliberate multi-field editing, contact organization,
relationship setup, and settings; they are not routing clarifications.

**Act, then describe (the canonical interaction model).** The app never asks permission for an action it understood. When the user makes a request, the app executes immediately and describes what it did in a single concise sentence. The user then either accepts the outcome and moves on, or corrects it by voice (§3.3). Breaking the fourth wall — asking the user anything before acting — is reserved exclusively for the case where the app genuinely cannot determine what was requested (§3.2), plus the single non-undoable operation (type/skill deletion, §24). Reliable undo (§3.5) is the safety net for misunderstandings, not pre-action confirmation.

This principle is the authority for confirmation behavior. `Session` resolves and validates before
calling `ExecutionCoordinator`; the resulting confirmation string is delivered through
`VoiceTurnController` and the conversation ledger. The older `Done(confirmationText)` event name is
destination vocabulary from Spec 04, not a current UI stream. The retired per-skill
`confirmationPolicy` and routing pre-confirmation band remain retired.

**Corrections repair first and may teach routing.** Current correction paths reverse or update the
affected write and can update/forget learned corpus templates. Automatic structural-gap detection
and background type/skill re-authoring are destinations (§3.3), not current behavior.

**The free tier is never a crippled demo.** All ten free-tier marquee tasks work fully offline with no BYOK key. The paid tier is a genuine upgrade, not a gate on basics.

---

## 2. Notation

Flows in §§4–23 use the following notation:

- `U:` — the user's utterance
- `A:` — Plenara's spoken response (simultaneously shown as subtitles)
- `UI:` — a change to the visual overlay (results card, insight card, etc.)
- `[System action]` — a deterministic background step, never shown to the user
- `→ Edge N` — branch to a named edge case in the same section's "Edge Cases" subsection
- `→ §X` — branch to another spec section
- `[PAID]` — this step or branch requires a BYOK key

Normal write flows do not include a pre-action confirmation step. The app executes and describes. A pre-action confirmation card (`UI: Confirmation card`) appears only in capability deletion flows (§24), where the operation is explicitly non-undoable.

When a clarification is needed, the app asks by voice and waits. The user responds by voice (or tap in text mode). Both are always available.

---

## 3. The Interaction Contract

This section defines the rules that apply to every flow in the spec. Individual flows reference these rules by number rather than repeating them.

### 3.1 Act-Then-Describe

The default interaction pattern for all writes is:

1. **Resolve.** The interpreter resolves the action plan (Spec 02 §4.1): system inputs are frozen, record ids are minted, any `foreach` is fully unrolled, every pending write is validated against its target type's schema, and the before-image of every record the plan will touch is captured (Spec 04 §3.3). A resolve that hits a missing required input, an unresolvable variable, or a write that would fail schema validation halts here with a surfaced error (P2.8) — before anything is written. This is the same resolve that a pre-action confirmation would have run; act-then-describe removes the *pause* after it, not the checking inside it.
2. **Execute.** The interpreter applies the validated plan immediately, with no approval pause. Because a create's id was minted at resolve and the before-images were captured, the write is both idempotent on resume (Spec 02 §4.4) and reversible (§3.5).
3. **Describe.** The app presents the skill's resolved `confirmationText` in the controller reply
   and conversation ledger and speaks it when voice output is active. No sealed `Done` event stream
   exists in the current UI.
4. **User continues or corrects.** If the app misunderstood, the user says so and the app corrects immediately (§3.3). If the app understood correctly, the user moves on.

There are no pre-action confirmation cards in the normal write path, and the Skill DSL no longer carries a per-skill `confirmationPolicy` field to configure one (Spec 02 §7.1). The app does not ask "Should I do this?" before acting.

**When pre-action confirmation still applies:** exactly one operation retains it — deletion of a *type or skill* (§24), which is a schema migration and cannot be undone (restoring a deleted type means restoring its definition, all its records, and its skills, then re-registering — a reverse migration, not a record restore; D6). Its confirmation card states explicitly that the deletion is permanent. This is the only *app-initiated* pre-action confirmation in the entire write path, and it is owned by the deletion meta-flow (Spec 04 `MigrationRunner`), not by any skill. (Capability authoring, §14, also shows a design before the user says "activate," but that is a *user-driven* commit of a collaborative design — the app is not asking permission for something it decided to do — so it is a different category, not a fourth-wall break in a write the user already requested.)

**Destructive record writes are undoable and therefore act-then-describe.** Deleting a single *record* is reversible: the interpreter captures the record's full before-image at execute (Spec 02 §5.4, Spec 04 §3.11), and `undo` restores it. So the app deletes the record, describes it ("Deleted — dentist appointment"), and the user can undo via §3.5. There is no secondary "are you sure?" confirmation for record deletion; the description plus guaranteed undo is the safety net. (This overturns Spec 02 v0.3's "destructive ⇒ pre-action confirmation" rule and Spec 04 v0.2's "record delete is not undoable in v1" — both reconciled to act-then-describe in this pass; see D8.)

The `[PAID]` gate (§3.6) is not a confirmation; it is an inability to proceed. The app cannot act, so it reports the blocker.

### 3.2 When to Ask Before Acting

The app breaks the fourth wall only when it genuinely cannot determine what was requested. It never pre-confirms a routing it can act on — a moderate-confidence best guess is acted on and made transparent, not surfaced as "did you mean X? — proceed?" (this collapses the routing pre-confirmation band that Spec 03 v0.3 defined; see D2 and the reconciliation in Spec 03 §2.7/§4). The thresholds below are Spec 03's (§4.3), used here by their real names. *(Post-`G-20`, the quantities behind these names are **retrieval-similarity and margin** signals, not classifier confidence — Spec 03 §7.3.1; the interaction behavior in this section is unchanged, only what the numbers measure.)*

**Unusable or empty recognition.** The current recognizer exposes no numeric confidence floor.
Empty/no-match captures remain outside routing and repeated empties surface a microphone/text hint
(Spec 12 §4.6).

**Missing required slot with no default.** A required field cannot be extracted from the utterance and has no fallback (e.g., no `{now}` default). The app asks exactly one question for the most-blocking missing slot, answered via `ProvideSlot` (Spec 04 §3.6 → `NluRouter.resolveFollowUp`, Spec 03 §6.3). After the answer, it acts. At most two clarification rounds per turn; after two, the app acknowledges it is confused and offers to start over.

**Genuinely ambiguous routing — no reliable best guess.** When classification confidence is below `θ_cloud_escalate` with no dominant candidate (free tier), or a cloud attempt still lands below `θ_minimum` (paid), the app has no basis for a choice and surfaces the two most likely candidates: "Did you mean X or Y?" — a `ClarificationRequested` event answered by `SelectCandidate` (Spec 03 §2.4, §4.3). This is distinct from a moderate-confidence best guess, which is acted on (below).

**A pattern the app keeps getting wrong.** A corpus template flagged `requiresPreConfirm` by the repeated-correction rule (Spec 03 §4.2) has *evidence* of genuine ambiguity, so even at high surface confidence it is surfaced as a clarification between the contested candidates rather than acted on silently — acting-then-describing would just repeat a mistake the user has already corrected more than once.

**No type exists for the domain.** The app understood the intent but has nowhere to store the data. "I don't have a type for that yet. Want me to create one?" This is a capability gap, not a write decision.

**When the app has a reliable interpretation or a moderate-confidence best guess** (classification ≥ `θ_cloud_escalate`, or a corpus hit at or above `θ_corpus_drop`): the app acts. At or above the act thresholds (`θ_act` / `θ_corpus_act`) it simply describes the result; in the moderate band below them it acts on its best guess *and makes the routing transparent in the description* — "Logged that as a task — let me know if you meant something else" — carried by the advisory `Routing` turn event (Spec 04 §3.6). The user corrects in one turn if needed (§3.3). There is no pre-action disambiguation prompt for this case. Acting on the moderate band is also what lets the corpus learn: a best guess the user does not correct records an implicit confirmation (Spec 03 §2.7) and graduates toward the fast path, so the app needs the interrogative surface less over time, not more.

**Conflicting type detected during authoring.** When a `define_type` meta-intent triggers and the similarity search finds a candidate above 0.85, the authoring flow pauses and asks "I found a type for [X] — should I add to it, or create something new?" (Spec 01 §6.1). This is a clarification before designing, not before writing, and it is appropriate because designing the wrong thing wastes a cloud call.

### 3.3 Corrections

Every correction is a learning opportunity — not just a fix for the current turn, but a signal to improve the underlying model so the same mistake doesn't recur.

**Immediate correction.** When the user corrects the app after it has acted — by saying "actually," rephrasing the intent, or providing the right value — the app executes the correction immediately, describes what changed, and moves on. It re-runs the full flow from the corrected intent; it does not patch a single slot in isolation.

Because act-then-describe means the (possibly wrong) write has *already happened*, a correction is a two-part operation, and the order matters: the orchestrator first **reverses the prior turn's write** using its before-images (§3.5) — the same inverse plan `undo` would run — and only then dispatches the corrected intent. This prevents the misroute from leaving an orphan: "Ran 5k" misrouted to `log-meal` and corrected to `log-run` must not leave both a meal record and a run record. A correction that only changes a slot value on the *same* skill (e.g., "actually, 28 minutes") is an update to the record just written, not a reverse-then-redispatch — the orchestrator distinguishes the two by whether the corrected intent resolves to the same `skillId` and target record. Both paths are within the undo window, so the reversal is always available.

**NLU corpus update.** The correction is recorded as a correction pair in the flow table (Spec 03 §5): `(utterance, context_hash) → corrected_intent`. This raises confidence on the corrected routing for future identical utterances. The user never sees this process.

**Structural gap detection (destination).** Current correction code does not analyze a correction
and automatically re-author a type or skill. The following remains a future design, not shipped
behavior:

- **Routing miss:** The skill definition was correct, but the routing weights were off. The corpus update alone is sufficient. Example: "log a run" routed to `log-meal` — the `log-run` skill exists and is correct, the corpus just underweighted it.
- **Definitional gap:** The skill or type definition doesn't reflect how the user actually communicates, or is missing a field/pattern the user naturally expects. Example: the user says "ran 5k on the trail by the river" and the correction reveals the RunWorkout type has no `route` field — a field the user will expect to exist on every log. The skill definition itself needs updating.

A single correction is not enough to trigger a schema change — one data point can mislead, and re-authoring a type on every stray correction would be both expensive and destabilizing. The definitional-gap path is therefore gated on a concrete, conservative signal, not on an attempt to infer intent from one utterance:

- **Repeated correction of the same normalized pattern.** When the corpus's repeated-correction rule (Spec 03 §4.2) fires — the same pattern corrected more than once within the correction window — the orchestrator has evidence that routing weights alone are not the problem, and it queues a background authoring review of the implicated skill/type.
- **The user names the gap explicitly.** "…and there's no field for the route" or "add a route field to my running tracker" is a direct definitional signal and routes straight to a skill/type edit (Spec 02 §6.4), not through inference.

If implemented, either signal could start a detached authoring review and send any proposal through
the same deterministic validator as explicit capability authoring. It must remain BYOK-gated and
must never silently activate a schema change.

Any future structural update must instead surface a validated preview for explicit activation, like
current capability authoring; the app must not quietly commit it from correction evidence.

### 3.4 Cancellation

Current cancellation has three concrete homes: voice capture cancel discards the active capture;
`OperationCenter.cancel` cancels queued/detached work where its operation state permits; and pending
authoring/review/proposal surfaces can be dismissed through their explicit command. Synchronous
skill execution is serialized and checkpointed but is not interruptible mid-`foreach`; the spec
must not promise a “Done X of Y” live-cancellation surface that the runtime does not provide.

### 3.5 Undo

The spoken `undo` command reverses the latest eligible write. UI confirmations and History retain
execution ids and may request targeted undo of an older retained entry, subject to after-image
conflict checks. What it covers:

- `write_record` (create or update) → the created record is deleted; the updated record is restored to its pre-update before-image (captured at execute, Spec 02 §5.4 / Spec 04 §3.11).
- `delete_record` → the record is restored from its before-image with new HLC field stamps so the
  reversal can supersede its tombstone under Spec 06's merge rules.
- Multi-step skills → the coordinator reverses operations in a durable, checkpointed sequence.
  A process interruption resumes on launch; a persistence failure may surface an
  applied-in-memory/repair state rather than claiming cross-file atomicity.

Spoken undo targets the latest eligible execution; UI Snackbar/History actions can target a
specific execution. The durable journal retains at most 25 terminal executions. The five-second UI
Snackbar is only the transient affordance lifetime, not journal expiry; Spec 07 owns the rule that
a newer completed action replaces older transient feedback instead of queuing behind it.

What undo does not cover:
- Generative outputs (briefing text, gift suggestions, coaching) — these have no persistent side effects to reverse; the content simply vanishes from the response surface.
- Skill authoring (type/skill definitions) — undoing a type creation is a migration, not a record delete. The user must say "delete the [type] type" explicitly, which triggers the deletion flow (§24).
- Automations that fired in the background — the user must undo those from the Review Feed (Spec 04 §3.9).

Undo is itself act-then-describe. The app identifies what it is about to reverse, executes the reversal, and confirms: "Undone — removed your 2:30 pm run log."

### 3.6 The Free/Paid Boundary

When a user triggers a paid-tier flow without a BYOK key configured, the app responds:

> A: "That needs Claude — it's a paid feature. You can add your API key in Settings to unlock it. Want me to remind you?"

The app offers to set a reminder (invoking the reminder flow, §5). It never silently degrades — it explains what was blocked and what to do. This is the same on every paid-tier edge in §§14–23.

### 3.7 The Free Tier's Shipped Capability Surface

The free tier must work end to end with **no Claude call and no authoring**, because authoring is itself a paid capability (§14, Spec 02 §6). That is only true if every free-tier flow in §§4–13 maps to a capability that ships *inside the app binary*. This section states the invariant that makes the free tier a real platform rather than a promise, and it is a testable contract for Spec 09.

**The free-tier capability surface = seed types + built-in templates + the skills bound to them, all shipped in the binary.** Concretely:

- **Seed types** (Spec 01 §12, always present): `task`, `contact`, `contact_fact`, `contact_relationship`, `interaction`, `habit`, `habit_checkin`, `journal_entry`, plus the `goal` seed (Spec 01 §12.4, `G-32`). The people-knowledge flows (§9) depend on `contact_fact`/`contact_relationship` specifically — a facts capture that only had `contact` would have nowhere to put "Mia is Sarah's daughter." Habit progress likewise depends on keeping the repeated practice and its dated completions as separate parent/child records.
- **Built-in tracker templates** (§6): Run, Walk, Water, Reading, Mood, Sleep, Weight, Meals, Habit, Medication. Instantiating one registers its type locally with no cloud call.
- **Seed skills** (Spec 02 §9): the capture, log, query, streak, and recall skills that operate over the above. A template is not shipped as a bare type — it ships **bundled with its skills** (a log skill and, where relevant, a streak/summary skill), so that the moment a tracker exists the user can log against it and query it by voice. A type with no skill is inert; the free tier ships neither.

**The invariant.** Every canonical flow and every non-authoring edge in §§4–13 resolves to a skill in the shipped seed set or a template-bundled skill. No free-tier flow may depend on a skill that only Claude could author. The seed set in Spec 02 §9 is therefore *defined as the union of the skills these flows require* — it is not an illustrative sample. The free-tier flows and their required shipped skills:

| Flow | Required shipped skill(s) |
|---|---|
| F1 capture (§4) | `create-task`, `add-contact-fact`, `log-interaction` |
| F2 reminders (§5) | `create-reminder`, `create-recurring-reminder` |
| F3 spin up tracker (§6) | `instantiate-template` |
| F4 log against tracker (§7) | the target template's bundled log skill (e.g. `log-run`, `log-meal`) |
| F5 streaks & nudges (§8) | `show-streak`, `create-recurring-reminder`, gap-detection automation |
| F6 people facts (§9) | `add-contact-fact`, `recall-contact-fact` |
| F7 "when did I last…" (§10) | `query-last-interaction`, `log-interaction` |
| F8 voice journal (§11) | `add-journal-entry` |
| F9 semantic search (§12) | `search-records` (system query path, not a per-type skill) |

Spec 02 §9's seed table is expanded to cover this union. Anything a free-tier flow needs that is *not* shippable as a fixed skill — a novel user-defined domain (§6 E3), a custom field on capture (§6 E4) — is exactly where the flow branches to paid authoring (§14), and the app says so.

### 3.8 Generative Requests (Paid, Voice-Invocable)

Six paid synthesis requests are implemented: briefing (§15), gift ideas (§16), reconnect coaching
(§18), weekly review (§19), pattern insight (§20), and message drafting. They are **generative
requests**, not skills: a deterministic assembler selects declared record classes, then a fixed
cloud prompt produces text. Event prep (§17), meal suggestion (§21), monthly reflection (§22), and
foresight are retained below as candidate flows only; they are not runtime kinds until Spec 08's
closed registry, assembler, consent surface, and tests add them.

- **Voice-invocable.** A generative request is reached by speaking, exactly like capture. Current
  recognition uses binary-shipped rules, learned templates, and the closed-set residual; a future
  merged `CapabilityIndex` may rank these kinds as data (Spec 03 §2.2a).
- **Read-only — no act-then-describe write, and nothing to undo.** A generative request writes no records, so it has no `confirmationText` and no undo entry. The app presents the synthesized result (a spoken opener + an on-screen card). If the user then acts on it — "save the second one," "remind me to text Marco Friday" — that is a *separate, following* turn, an ordinary act-then-describe skill invocation (§3.1).
- **Detached, so voice stays live.** Generation is a multi-second Claude call and always runs detached (Spec 04 §3.7/§4.7): the turn returns immediately, the app says it is working ("…one moment"), and the result is delivered through the operation center when ready — a slow generation never freezes the next utterance.
- **Paid, and it says so when blocked.** Every generative kind needs a BYOK key; with none, the app gives the standard §3.6 response — never a silent no-op or a fabricated local imitation (Spec 04 §6.2).
- **Never cached.** The output is regenerated every time — its whole value is being current (Spec 04 §4.9) — and the *routing* is re-derived each turn too, not corpus-cached: a request that already costs seconds of generation saves nothing by skipping a millisecond of classification (Spec 03 §2.2a).
- **Privacy is bounded at assembly.** What records a generative prompt may include is decided at prompt-assembly time (Spec 08); journal text is excluded by default and included only under an explicit per-session consent prompt (D3; §§20, 22).

---

## 4. Free-Tier Task F1: Capture Anything and Have It Filed Correctly

**Summary:** The user states something — a reminder, a note about a person, a task — in natural language, and it lands as the correct record type without any menu.

**Canonical flow:**

```
U: "Remind me to call the plumber Thursday."
[System: NLU routes to `create-task` skill; slots: description="call the plumber", dueDate=next Thursday; execute write_record for Task type]
A: "Done — task added: call the plumber, Thursday."
```

```
U: "I FaceTimed Ana about her new job Monday."
[System: NLU routes to `log-interaction` (Spec 02 §9); resolves Contact=Ana (creates the contact record if absent); slots: personName=Ana, medium=facetime, note="her new job", at=the most recent Monday; execute write_record → `interaction`]
A: "Logged FaceTime with Ana — her new job."
```

**Edge cases:**

*E1 — No matching type exists for the domain.*
> A: "I don't have a type for that yet. Want me to create one?"
→ If yes, branches to capability authoring flow (§14). [PAID]
→ If no, the turn is abandoned.

*E2 — Ambiguous person reference.* ("Note that she's allergic to peanuts" with no recent contact in context.)
> A: "Who is allergic to peanuts?"
The user answers; NLU extracts the contact name; routing continues and the app acts.

*E3 — Empty/unusable recognition.* No turn is routed. Repeated empty captures surface the current
microphone/text-mode hint; there is no numeric ASR-confidence threshold.

*E4 — No dominant candidate (multiple plausible skills, none reliable; §3.2).* ("Add a note" could mean task, contact note, or journal, and the app has no reliable basis for a guess.)
> A: "Did you mean a task, a note about someone, or a journal entry?"
The user picks (`SelectCandidate`); routing commits to that skill and the app acts.

---

## 5. Free-Tier Task F2: Set Natural, Relative, and Recurring Reminders

**Summary:** The user sets a time-based or recurrence-based reminder in natural language. Date/recurrence parsing is deterministic code; no model call.

**Canonical flow (one-off, relative):**

```
U: "In three weeks, nudge me about the concert tickets."
[System: NLU routes to `create-reminder`; date resolver computes: today + 21 days; execute write_record: Task type, description="Concert tickets", dueAt=<date>]
A: "Set — concert ticket reminder for <date>."
```

**Canonical flow (recurring):**

```
U: "Every second Tuesday, take the bins out."
[System: NLU routes to `create-recurring-reminder`; recurrence parser produces RRULE: FREQ=WEEKLY;INTERVAL=2;BYDAY=TU; execute write_record with recurrence rule]
A: "Done — recurring reminder every other Tuesday: take the bins out. First one's <date>."
```

**Edge cases:**

*E1 — Ambiguous recurrence.* ("Every few days" has no canonical parse.)
> A: "How often exactly — every two days, three days?"
User specifies; the app acts on the answer.

*E2 — Past date.* ("Remind me last Thursday.")
> A: "That date already passed. Did you mean next Thursday?"
If yes, proceeds with corrected date.

*E3 — Reminder with no due date.* ("Remind me to stretch.")
> A: "When should I remind you — morning, a specific time, or daily?"
User answers; the app acts on the answer.

*E4 — Undo a recurring reminder.*
Undo cancels the recurring rule entirely, not just one instance. The app says: "Undone — removed recurring reminder: take the bins out. All future instances removed."

---

## 6. Free-Tier Task F3: Spin Up a Personal Tracker from a Template

**Summary:** The user names a built-in tracker template; it is instantiated locally with no cloud call.

**Built-in templates available at launch:** Run, Walk, Water Intake, Reading, Mood, Sleep, Weight, Meals, Habit (generic), Medication. (The Meals tracker is what the `log-meal` skill in §7 logs against — a meal entry with an optional calorie value; it was called "Calories" in an earlier draft, reconciled here so the F3 template list and the F4 log skill name the same type.)

**Canonical flow:**

```
U: "Start tracking my runs."
[System: NLU routes to `instantiate-template`; template resolver matches "runs" → RunWorkout built-in template; execute — registers RunWorkout type from built-in seed definition; creates tracker home view]
A: "Running tracker ready — distance, time, and notes. Say 'ran 5k' to add an entry."
```

**Edge cases:**

*E1 — Template ambiguity.* ("I want to track my mood and my energy.")
The app instantiates both in a single operation. "Done — two trackers set up: mood and energy. Both are ready."

*E2 — Template already exists.* ("Start tracking my runs" when a RunWorkout type already exists.)
> A: "You already have a running tracker. Want to start a new entry instead?"

*E3 — No built-in match — user-defined domain.* ("Start tracking which restaurants I visit.")
> A: "I don't have a built-in template for that. Want me to create a custom one?" [PAID]
→ Branches to capability authoring flow (§14).

*E4 — Customization at instantiation.* ("Start tracking my runs but I also want to note the route.")
The app instantiates the template with the extra field included. "Running tracker ready — distance, time, notes, and route. Say 'ran 5k' to add an entry."

---

## 7. Free-Tier Task F4: Log Against a Tracker Conversationally

**Summary:** Once a type exists, the user appends an entry in natural language. The slot extraction is the only variable; the write is deterministic.

**Canonical flow:**

```
U: "Had oatmeal and coffee."
[System: NLU routes to `log-meal` skill if a Meal/Food type exists; slots: description="oatmeal and coffee", loggedAt=now; execute]
A: "Logged — oatmeal and coffee."
```

**Canonical flow (multiple entities):**

```
U: "Ran 5k in 27 minutes."
[System: slots: distance=5km, duration=27min, loggedAt=now; execute]
A: "Logged — 5k in 27 minutes."
```

**Edge cases:**

*E1 — Missing required field with no default.* If a type has a required field with no default and no slot, the app asks once: "When was this?" Then acts on the answer.

*E2 — No dominant type candidate (§3.2).* ("Logged 30 minutes" — could be exercise, reading, or sleep, with no reliable basis for a guess.)
> A: "30 minutes of what — exercise, reading, or sleep?"

*E3 — Numeric unit ambiguity.* ("Ran 5 miles" when type expects km.)
The app logs what it understood and makes it explicit: "Logged — 5 miles." The user can say "that should be kilometres" to correct.

*E4 — Correction after logging.* The user says "Actually, it was 28 minutes."
[System: execute correction — update record] A: "Updated — 28 minutes."

*E5 — Offline with no connectivity.* Logging is fully local; this flow always works offline.

---

## 8. Free-Tier Task F5: First-Class Habits, Tracker Streaks, and Gentle Nudges

**Summary:** A habit is a repeated practice with a weekly target and dated check-ins. It is distinct from a quantitative tracker such as water or running, and from a reusable guided routine. Weekly progress, streaks, and gaps are computed locally; no cloud call.

**First-class habit flow:**

```
U: "Track strength training three times a week."
[System: NLU routes to `create-habit`; creates habit {title:"strength training", targetPerWeek:3, status:"active"}; execute]
A: "Started tracking strength training — 3 times a week."
UI: Habits root shows 0 of 3 this week and a seven-day check-in strip.

U: "I did my strength training habit."
[System: NLU routes to `log-habit`; writes one habit_checkin for today; execute]
A: "Checked in strength training for today."

U: "How is my strength training habit going?"
[System: NLU routes to `habit-progress`; computes week-to-date count and current streak]
A: "Strength training: 1 of 3 this week, with a 1-day streak."
```

The Habits UI provides the same create, check-in, progress, edit, pause/resume, delete, and targeted-undo outcomes without voice. Todos may surface a due habit with a one-tap check-in, but it remains a habit check-in rather than being copied into the task list.

**Quantitative tracker streak flow:**

```
U: "How's my running streak?"
[System: NLU routes to `show-streak`; reads RunWorkout records for the past N days; computes streak]
A: "Your running streak is 6 days. Last entry was yesterday."
UI: Streak ring view for RunWorkout type
```

**Nudge scheduling flow (at tracker creation or on explicit request):**

```
U: "Remind me to log my water every morning at 8."
[System: NLU routes to `create-recurring-reminder` bound to Water type; recurrence: FREQ=DAILY;BYHOUR=8; execute — AutomationRunner schedules the reminder (Spec 04 §3.9)]
A: "Set — daily reminder at 8 AM: log water intake. First one tomorrow."
```

**Gap detection nudge (automatic):**

When the `AutomationRunner` detects that a tracker has not had a new entry within its configured nudge window (set at template instantiation, or defaulting to the tracker's `nudgeInterval`), it pushes a notification: "You haven't logged a run in 3 days. Want to add one now?" Tapping or saying "Yes" opens a pre-filled log-entry flow (§7).

**Edge cases:**

*E1 — No habit check-ins yet.*
> A: "Meditation: 0 of 7 this week, with a 0-day streak."

*E2 — Duplicate habit check-in today.*
> A: "Meditation is already checked in for today."

*E3 — Requested habit target is outside 1–7 per week.*
> A: "Choose a weekly target from 1 to 7 for meditation."

*E4 — Tracker streak broken.*
> A: "Your running streak ended yesterday — you had 4 days going. Want to log today's run?"

*E5 — Multiple trackers, ambiguous.*
> U: "What's my streak?" (no type mentioned)
> A: "Which one — running, water, or reading?"

---

## 9. Free-Tier Task F6: Remember and Recall Facts About People

**Summary:** The user stores a fact about a contact; later, they recall it by voice. Both are fully local.

**Store flow:**

```
U: "Sarah's daughter Mia is allergic to peanuts."
[System: NLU routes to `add-contact-fact`; resolves Contact for Sarah (or creates if absent); resolves or creates child relation for Mia]
[System: execute — (1) Contact record for Mia if not exists, (2) contact_relationship record {Mia →daughter→ Sarah} (Spec 01 §12.2), (3) contact_fact record {attribute: allergy, value: peanuts} owned by Mia]
A: "Got it — added Mia as Sarah's daughter, noted peanut allergy."
```

**Recall flow:**

```
U: "What's Mia allergic to?"
[System: NLU routes to `recall-contact-fact`; resolves Mia (possibly via Sarah's relationship records); reads Mia's contact_fact records filtered on the query]
A: "Mia is allergic to peanuts."
UI: Contact card for Mia with allergy field highlighted
```

**Edge cases:**

*E1 — Contact not found.* ("What do I know about Tom?" — no Tom in contacts.)
> A: "I don't have anyone named Tom. Want to add them?"

*E2 — Ambiguous contact.* (Two contacts named "Sarah".)
> A: "Which Sarah — Sarah Mitchell or Sarah Chen?"

*E3 — Fact update.* ("Mia's allergy is actually tree nuts, not peanuts.")
[System: NLU detects update intent; execute update] A: "Updated — Mia's allergy: tree nuts (was peanuts)."

*E4 — Sensitive contact data.* The schema may mark the fact sensitive, but current records remain
plaintext and may sync through the chosen provider. Encrypted payload handling is deferred to
Spec 01 §8.7.

---

## 10. Free-Tier Task F7: Answer "When Did I Last…"

**Summary:** Time-since queries over interaction logs and tracker entries. Fully local, no cloud.

**Canonical flow:**

```
U: "When did I last see Marco?"
[System: NLU routes to `last-interaction`; slot: contact=Marco; reads `interaction` records for Marco, orders by date descending, takes first]
A: "You last saw Marco on June 12th, 11 days ago."
UI: Timeline of recent Marco interactions (last 3 entries)
```

```
U: "How long since I called Mum?"
[System: reads `interaction` records for Mum, filtered by medium=phone, orders by date, takes first]
A: "Your last call with Mum was 3 weeks ago, June 10th."
```

**Edge cases:**

*E1 — No interaction log entries for this contact.*
> A: "I don't have any logged interactions with Marco. Want to add one now?"

*E2 — Multiple people with same name:* → disambiguation (same as §9 E2).

*E3 — "Last time I exercised" (tracker query):*
[System: reads RunWorkout or Exercise records, takes most recent]
> A: "Your last run was 2 days ago — 5k on Wednesday."

*E4 — Ambiguous action.* ("When did I last contact Sarah?" — phone, text, in-person all exist.)
> A: "Last contact with Sarah was a text on June 28th. Her last in-person was June 15th."
(All methods are shown if multiple exist in the log.)

---

## 11. Free-Tier Task F8: Private Daily Journal

**Current realization:** ordinary typed or tap-to-talk input can create a `journal_entry` through
the normal turn pipeline. There is no dedicated 60-second continuous capture mode, stop-word
session, duration reply, or journal-specific speech UI. The record syncs as plaintext through the
chosen provider and no current Claude assembler reads journal content.

**Current canonical flow:**

```
U: "Journal that today was a good day."
[System: ordinary on-device speech capture finalizes and routes to `log-journal`; the skill writes
an ordinary `journal_entry` record in `records/`]
A: "Saved to your journal."
UI: Journal entry card with transcribed text
```

**Privacy invariants (stated explicitly, testable):**

- The audio recording is discarded immediately after transcription. It is never written to disk.
- The transcribed text is stored as an ordinary private `journal_entry` in the synced flat `records/` folder. Its globally unique id is date-prefixed, so `records/<date-prefixed-id>.json` remains chronologically navigable without creating the per-day filename collision that a separate `journal/` layout caused (Spec 06 §3.1 D4; the date is also an `entryDate` field). This survives device loss (Spec 01 §12.3). The earlier "excluded from sync / never leaves the device" invariant is **dropped**: no provider offers a reliable per-subfolder sync exclusion (it was unimplementable, `G-37`), *and* device-local storage would lose the journal on device loss (the worse failure). Keeping journal content unreadable by the *cloud provider* is a json-privacy hardening **deferred to a later version** (at-rest encryption, Spec 01 §8.7, itself deferred); until then it is plaintext JSON in the user's own synced folder, protected by their provider-account security, and onboarding says so.
- The transcribed text is never sent to Claude by any current assembler. A future journal-based
  feature must add an explicit, non-persistent per-session opt-in at assembly time; pattern insight
  and the other implemented kinds currently have no journal access at all.

**Edge cases:**

*E1 — More than one entry on a day.* Each entry receives its own id; current behavior does not
append into a single date-keyed file.

*E2 — User stops before any speech (0 seconds).*
The flow is abandoned silently; no file is written.

*E3 — Recognition fails.* The ordinary voice failure path clears capture and preserves text-mode
entry; no partial journal record is written (Spec 12 §9).

*E4 — Entry search (covered in §12) uses on-device embeddings; the text is never sent anywhere.*

---

## 12. Free-Tier Task F9: Find Any Past Note or Entry by Meaning

**Summary:** The user describes something they remember; on-device semantic search finds it. Fully local, no cloud.

**Canonical flow:**

```
U: "Find that note about the cabin trip."
[System: NLU routes to `search-records`; query="cabin trip"; embedding model runs on-device; cosine similarity search over all records and journal entries]
UI: Ranked search results card (top 3–5 matches)
A: "Found a few things — a task about cabin packing from June 3rd, and a journal entry from May. Which one?"
U: "The journal entry."
[System: opens the entry in the journal view]
```

**Edge cases:**

*E1 — No results above threshold.*
> A: "Nothing close to that in your notes. Try different words?"

*E2 — Only one strong match:*
> A: "Found it — a note from June 4th about the cabin trip. Here it is."
(No disambiguation needed; the result is presented directly.)

*E3 — Search across types.* ("Find anything about sleep") searches all types — journal, tracker entries, tasks, contact notes — and the results are grouped by type in the UI.

*E4 — Sensitive records in search.* Encrypted records (journal entries marked sensitive) are decrypted in the in-memory store before embedding; the embedding itself is not stored in the cloud. The search result card shows the record but does not expose the full text in the spoken response (only the title/date).

---

## 13. Free-Tier Task F10: Offline-First and Subtitle Overlay

**Summary:** All nine free-tier tasks above work fully offline. The subtitle overlay provides full text parity for situations where speaking aloud is not possible.

**Offline behavior contract:**

All free-tier flows function identically with no network, because:
- STT/TTS is on-device (Spec 04 §3.8).
- NLU routing is local (Spec 03 §3).
- All record reads and writes go to local storage (Spec 04 §3.1).
- No free-tier skill invokes the cloud.

When the user initiates a paid-tier flow while offline, the response is:
> A: "That feature needs an internet connection. I'll remind you to try again when you're back online."
The app offers to set a reminder (§5 flow). The request is not queued automatically because the user may not want to wait.

**Three distinct "paid unavailable" surfaces, never conflated (`G-28`).** A paid flow can be blocked for three different reasons, each with its own honest surface (P7 — no silent failure) — the app names the *actual* reason so the user knows what would fix it:
- **Tier** (free user, no key): "That's a paid feature — it uses Claude. Add your API key in settings and it's yours." → offers the upgrade path (Spec 03 §2.2a).
- **Connectivity** (keyed user, offline): the message above — a *reminder* offer, not an upgrade prompt; the capability exists, only the network is missing. On reconnect the app silently re-enables cloud features (E1) but does **not** auto-run the earlier request.
- **Key/quota** (keyed but the call returns `CloudError(rateLimited)` or an auth failure): "I've hit today's limit on Claude" / "your key was rejected" — a distinct, actionable surface (Spec 04 §6, §5.2), never mislabeled as "offline."

**Subtitle overlay:**

At any point, the user can toggle the quiet overlay (a system command: "text mode" / "quiet mode"). In this mode:
- All of Plenara's spoken responses are displayed as text only (no TTS).
- The user's input is typed, not spoken.
- All flows work identically. Clarification questions become text prompts.
- The mode persists until toggled off ("voice mode").

**Edge cases:**

*E1 — Network comes back online mid-session.* The app silently enables cloud features for the remainder of the session. Any queued draft capabilities (from offline authoring) are submitted for review (Spec 04 §6.3).

*E2 — STT not available (e.g. privacy setting revoked).* Subtitle mode is automatically engaged. The user is told: "Microphone access isn't available — switching to text mode."

---

## 14. Paid-Tier Task P1: Describe a New Capability and Have Plenara Build It

**Summary:** The user describes a need with no existing type or skill; Claude authors a bespoke type, skill, and view mapping.

**Canonical flow:**

Authoring is the one flow where the app presents a design before writing it to disk. This is not pre-action confirmation — it is the output of the design step, described to the user before the registration step executes. The user either refines the design or activates it.

```
U: "I want to track my daughter's mood and what preceded her good and bad days."
[System: NLU raises define_type meta-intent; similarity search finds no match above 0.85]
[System: Session starts a durable capability_authoring operation (Spec 04 §4.7)]
A: "Got it — designing a mood tracker for her. This takes a moment…"
[System: ClaudeClient.author called (Spec 02 §6.2); pre-authoring reconciliation (Spec 01 §6.1); Claude produces ChildMoodLog type + log-child-mood skill + safety assessment]
[System: validator runs — schema, type resolution, capability closure, variable closure (Spec 02 §6.3)]
UI: Authoring preview card — type name, fields, view archetype
A: "Here's what I built: a 'Mood Log' for your daughter with fields for mood (happy/neutral/sad/upset), what led up to it, and the time. Timeline view. Say 'activate' to turn it on, or tell me what to change."
U: "Add a field for her sleep the night before."
[System: Claude re-authors with the additional field]
A: "Updated — added 'Sleep (hours)' as optional. Say 'activate' when you're ready."
U: "Activate."
[System: type and skill registered; safety assessment stored in audit/; capability is live]
A: "Done. Say 'log Mia's mood' to start."
```

**Edge cases:**

*E1 — Authoring produces a type similar to an existing one (>0.85 similarity).*
> A: "I found a similar type — your existing 'Mood Tracker.' Should I add to it instead of creating a new one, or keep them separate?"

*E2 — Claude declines to author (safety refusal).*
> A: "I wasn't able to build that capability. [Reason from Claude's response, if available.] Want to try describing it differently?"

*E3 — Validation fails (malformed skill output).*
The validator rejects the output; a re-authoring prompt is sent automatically (one retry). If the second attempt also fails:
> A: "I had trouble building that cleanly. I've saved a draft — you can try again later or refine the request."
The draft is stored inert (Spec 04 §6.2) and surfaced in the `AttentionSurface`.

*E4 — No BYOK key.*
→ §3.6 standard response. The user's description is preserved for when they add a key.

*E5 — Network lost during authoring (mid-Claude call).*
The in-flight request is abandoned; the user is told authoring failed; the request is not auto-retried (Spec 04 §6.3 — authoring requires explicit user intent). A draft marker is stored.

*E6 — User leaves before activation.* The validated draft is persisted device-locally by
`CapabilityDraftStore` and restored after relaunch. `activate` revalidates collisions before
promotion; `never mind` or an unrelated move-on turn discards it. Multi-turn re-authoring and a
five-refinement cap are not current behavior.

---

## 15. Paid-Tier Task P2: Synthesized Morning Briefing

**Summary:** Once daily, Claude synthesizes a spoken digest across tasks, calendar, people, and trackers. Delivered via an OS-local notification at the configured time; generation runs at **notification-tap or next app-open** (Spec 04 §3.13, the authoritative account) — never via the Batch API, never as a background Claude call. The promise is "waiting for you at 7 AM," not "spoken at 7 AM."

**Scheduling and delivery flow:**

```
[System: NotificationScheduler has armed an OS-local notification for the user's configured time (default: 7:00 AM) — arming is fully offline (Spec 04 §3.13)]
[System: the OS fires the notification at 7:00 AM — "Your briefing is waiting for you"]
[System: on TAP (or next app-open, if untapped): GenerativeService produces generativeKind=`briefing` (§3.8) — assembles the prompt: today's tasks due, upcoming reminders in the next 48 hours, people with upcoming events or overdue contact, recent tracker summary]
[System: ClaudeClient.generate called (Haiku, detached — generated at tap/open time from CURRENT data; see freshness note below)]
[System: response validated: text only, no write ops]
UI: Briefing card with the full text
A: (TTS reads the briefing aloud)
```

**The briefing is read-only.** It never writes records. The `AutomationRunner` applies Spec 02 §7.5: a read-only result is delivered without approval gating.

**Freshness over batch pricing.** The research doc's Batch-API costing (research §7.2) predates the measured numbers: an immediate Haiku briefing costs ~$0.0007 and takes ~2 s (findings §10.1), so the 50% batch discount saves a third of a tenth of a cent while introducing a real staleness problem — a batch submitted overnight completes "within 24 hours," is not guaranteed done by 7:00 AM, and is assembled from *yesterday's* data (a task added at 11 PM would be missing). The briefing therefore generates **on demand — at notification-tap or next app-open — with an immediate call** (Spec 04 §3.13: scheduled generation is *not* a background Claude call; the OS fires a local notification and the tap triggers generation, because iOS offers no reliable background execution); the Batch API remains appropriate only for genuinely asynchronous, non-deadline work (e.g. the weekly consolidation pass).

**Canonical response example (not verbatim — Claude generates this fresh each day):**

> "Good morning. You have three things due today: the plumber call, Ana's welcome note, and reviewing the cabin trip budget. Sarah's birthday is in four days — no gift idea logged yet. Your running streak is at 6 days. That's it."

**Edge cases:**

*E1 — No data to brief on.*
> (A short briefing: "Nothing pressing today. Enjoy the quiet.")

*E2 — Briefing fails (Claude call fails, offline, or API error).*
> UI notification: "Your morning briefing couldn't be generated today." No crash; the day proceeds normally.

*E3 — User asks for briefing on demand (voice).*
> U: "Give me my briefing."
NLU routes to `generative_request`, generativeKind=`briefing` (Spec 03 §2.2a — the same kind the scheduled automation uses), dispatched detached to GenerativeService (§3.8). The result is delivered immediately, not on the overnight batch.

*E4 — User wants briefing at a different time.*
> U: "Set my briefing for 6:30 AM."
[System: execute — updates the AutomationRunner schedule for the briefing automation]
> A: "Briefing moved to 6:30 AM."

*E5 — Briefing mentions sensitive data.* What Claude sees is bounded by what the prompt assembler includes — and the briefing assembler's declared record classes (task descriptions, reminder texts, birthday nudge lines — Spec 08 §5.5 row) contain no `sensitive`-flagged fields, and journal text is categorically excluded outside tier-c consent (Spec 08 §5.4). That class-scoping — not a blanket "sensitive fields excluded" rule, which Spec 08 does not state — is the actual privacy contract (suite-sync CS-18).

---

## 16. Paid-Tier Task P3: Thoughtful Gift Suggestions

**Summary:** The user asks for gift ideas for a named contact; Claude reasons over their stored preferences, recent interactions, and stated budget.

**Canonical flow:**

```
U: "What should I get Sarah for her birthday?"
[System: NLU routes to `generative_request`, generativeKind=`gift_ideas` (Spec 03 §2.2a); param contactRef resolved to Sarah; dispatched detached to GenerativeService (Spec 04 §3.6/§3.10) — read-only, §3.8]
[System: GenerativeService assembles prompt: Sarah's likes, dislikes, hobbies, recent interactions, upcoming birthday, any existing gift ideas]
[System: ClaudeClient.generate called (Haiku or Sonnet depending on prompt size)]
UI: Gift suggestions card with 3–5 ideas, each with a brief rationale
A: "For Sarah, here are a few ideas: [top suggestion read aloud]. I've got four more on screen."
```

**Edge cases:**

*E1 — No preference data for the contact.*
> A: "I don't have much on Sarah's preferences yet. Here are some general ideas — you can say 'Sarah likes hiking' to help me do better next time."

*E2 — Budget specified.*
> U: "Under $50."
The prompt includes the budget constraint; suggestions are filtered by the model.

*E3 — Existing gift idea logged.*
> A: "You already have an idea saved for Sarah — the hiking boots. Want new ideas anyway, or refine that one?"

*E4 — User wants to save a suggestion.*
> U: "Save the second one."
[System: execute — writes GiftIdea record linked to Sarah]
A: "Saved — hiking poles for Sarah."

---

## 17. Paid-Tier Task P4: Full Prep for a Social Event

**Summary:** The user names an upcoming event; Claude synthesizes everything Plenara knows about the people involved into a pre-event briefing.

**Canonical flow:**

```
U: "Dinner with the Garcias Saturday."
[System: NLU routes to `generative_request`, generativeKind=`event_prep` (Spec 03 §2.2a); param resolves the "Garcias" contact group; dispatched detached to GenerativeService — read-only, §3.8]
[System: GenerativeService assembles prompt: each Garcia contact's preferences, last interaction, open threads, dietary notes, any logged gift ideas or planned topics]
[System: ClaudeClient.generate]
UI: Event prep card — who's coming, what's known, suggested topics, items to avoid, food notes
A: "For Saturday's dinner with the Garcias: you last saw them in April. Carlos mentioned he started running. Elena is vegetarian. You have an open thread about the school project. I've got more on screen."
```

**Edge cases:**

*E1 — Event not in Plenara's data.* ("Dinner with the Garcias" — no Garcia contact exists.)
> A: "I don't have the Garcias in your contacts. Want to add them first?"

*E2 — Sparse data for some attendees.*
The prep card notes where data is thin: "Limited notes on Marco — consider what to ask."

*E3 — User wants to log outcomes after the event.*
> U: "Log that dinner with the Garcias happened."
[System: execute — `log-interaction` write for each contact, batched into a single operation]
A: "Logged — interaction with Carlos, Elena, and Marco, Saturday."

---

## 18. Paid-Tier Task P5: Relationship Reconnect Coaching

**Summary:** The user identifies a relationship they've drifted from; Claude provides context-aware suggestions and an optional drafted opener.

**Canonical flow:**

```
U: "I've drifted from Marco — help me reconnect."
[System: NLU routes to `generative_request`, generativeKind=`reconnect_coaching` (Spec 03 §2.2a); param contactRef resolved to Marco; dispatched detached to GenerativeService (§3.8), which assembles the prompt: last interaction date, shared history, Marco's noted interests, any open threads]
[System: ClaudeClient.generate — coaching + drafted opener]
UI: Coaching card — context summary, 2–3 reconnection suggestions, a draft message opener
A: "You last saw Marco 3 months ago. He mentioned he was starting a new project — that might be a good opening. I've drafted a message on screen. Want me to read it?"
U: "Yes."
A: (reads the drafted opener)
```

**Edge cases:**

*E1 — No interaction history with Marco.*
> A: "Not much history with Marco yet. Here are some general reconnection ideas based on what I know about him."

*E2 — User wants to log that they reached out after coaching.*
> U: "Log that I texted Marco."
[System: execute — `log-interaction` write] A: "Logged — text to Marco, today."

*E3 — Coaching suggests an action the user approves.*
> U: "Good idea — remind me to text Marco Friday."
[System: execute — `create-reminder`] A: "Set — remind you to text Marco, Friday."

---

## 19. Paid-Tier Task P6: Weekly Priority Review

**Summary:** Claude scans tasks, trackers, and goals and recommends what to drop, defer, or escalate — with brief rationale for each.

**Canonical flow (on demand):**

```
U: "Weekly review."
[System: NLU routes to `generative_request`, generativeKind=`weekly_review` (Spec 03 §2.2a); dispatched detached to GenerativeService (§3.8), which assembles: all open tasks, due dates, recurrence patterns, any overdue entries, stated goals]
[System: ClaudeClient.generate — structured list: keep / defer / drop, with one-sentence rationale each]
UI: Review card — tasks grouped by recommendation
A: "You have 8 open tasks. I'd suggest dropping the gym research — you've had a tracker for 3 weeks and haven't logged anything; might not be the right time. Defer the budget spreadsheet to next month. The plumber call is overdue — that's urgent. Full list on screen."
```

**Automation (optional, paid):**

The user can set the weekly review to run automatically (e.g. every Sunday morning), delivered as a push notification and briefing card — same `AutomationRunner` pattern as P2 (§15), read-only, no approval gating.

**Edge cases:**

*E1 — User acts on a recommendation.*
> U: "Move the budget spreadsheet to August."
[System: execute — task update] A: "Done — budget spreadsheet due date moved to August."

*E2 — No tasks.*
> A: "Nothing open to review. Clean slate."

---

## 20. Paid-Tier Task P7: Cross-Tracker Pattern Insight

**Summary:** The user asks about correlations across trackers; Claude narrates a pattern in plain language.

**Canonical flow:**

```
U: "What tends to precede my bad-sleep nights?"
[System: NLU routes to `generative_request`, generativeKind = `pattern_insight` (Spec 03 §2.2a).
 Tier/key gate passes (paid). GenerativeService.produce runs DETACHED and READ-ONLY (Spec 04 §3.10):
 it reads the sleep tracker plus the candidate correlate trackers/logs over a window
 (caffeine, exercise, screen-time, mood/stress), assembles a metadata-framed prompt, and calls Claude.]
A: "Over the last two months, your worse-sleep nights most often followed days with
    late caffeine (after ~3pm) and little movement — and a couple clustered around
    high-stress journal days. It's a pattern, not a certainty, but caffeine timing is
    the one you have the most direct handle on."
```

**What makes this safe and honest:**
- **Read-only, no writes, no undo** — a `pattern_insight` produces a narrative artifact, never a record; it is not act-then-describe (Spec 04 §3.10).
- **Evidence-linked and hedged** — the narration cites the actual logged signals and explicitly frames correlation, not causation (the same discipline as `foresight`, `G-27`); it never manufactures a pattern the data doesn't show.
- **Journal enters only under consent** — if stress/journal signals are used, they are included at prompt *assembly* under the per-session consent (`G-26`, Spec 04 §3.10), never by instructing the model to "read the journal."
- **Delivered off the turn lock** — detached; returns immediately with a handle and narrates through the operation center (Spec 04 §4.7), so a multi-second synthesis never blocks capture.

**Edge cases:**

*E1 — Not enough data.* Fewer than a usable window of entries across the relevant trackers → the app says so plainly rather than inventing a pattern: "I don't have enough logged yet to see a reliable pattern — a few more weeks of sleep and caffeine entries and I can look again."

*E2 — Offline or no key.* `generative_request` is recognized but tier/connectivity-gated (§13) → the three-surface degrade, not a fabricated local imitation (Spec 04 §3.10).

---

## 21. Paid-Tier Task P8: Meal Suggestion

**Summary:** The user asks what to cook or eat; Claude suggests options grounded in logged preferences, dietary restrictions, and recent meals. `generativeKind = meal_suggestion` (Spec 03 §2.2a); read-only, detached (Spec 04 §3.10). *Full canonical flow: pending — see the completeness backlog (05b §5).*

## 22. Paid-Tier Task P9: Monthly Reflection

**Summary:** A monthly narrative over journal + trackers + interactions; `generativeKind = monthly_reflection` (Spec 03 §2.2a). Requires the **mandatory journal-consent card** (`G-26`, Spec 04 §3.10) before any journal text enters the prompt. Read-only, detached. *Full canonical flow: pending — see the completeness backlog (05b §5).*

## 23. Gentle Nudges

**Summary:** Proactive, low-frequency surfacing (streak encouragement, reconnect prompts, upcoming anniversaries) delivered via the **Review Feed / AttentionSurface** (Spec 04 §3.12), never interrupting a live turn. Mechanism: automations (Spec 01 automations registry) writing to the attention surface, subject to act-then-describe's automation rule (automation writes never lower undoability). *Full canonical flow: pending — see the completeness backlog (05b §5).*

---

## 24. Capability Deletion — the one pre-action confirmation (`G-09`)

**Summary:** Deleting a user-authored type or skill is the **single exception** to act-then-describe (P2; CLAUDE.md). Everything else executes then describes, because reliable undo is the safety net — but a capability deletion is **not** recoverable by the record-undo mechanism, so the app confirms *before* doing it. This app-initiated confirm is what lets everything else be fearless.

**Why it's the exception.** Record writes reverse via before-images (Spec 02 §4). A *definition* is different: removing a type can orphan many records and drop a capability the corpus and automations depend on; there is no before-image that "un-deletes a type and re-links 200 records." So deletion gets a genuine "this can't be undone" gate — not the retired routing pre-confirm (D2), but a real destructive-action confirmation.

**Trigger & flow — type with records:**
```
U: "Delete the mood tracker."
[System: NLU → system_command(delete_type, target=mood). The orchestrator does NOT execute;
 it raises ConfirmationRequested(nonUndoableDeletion) with an impact summary.]
A: "Deleting the Mood type also affects 87 mood entries — this can't be undone.
    Delete the type and its entries, keep the entries as read-only history, or cancel?"
U: "Keep the entries."
[System: type marked deleted; its records retained as read-only orphans (archived typeRef);
 the log-mood skill + its corpus entries are deactivated (§5.5).]
A: "Done — removed the Mood tracker. Your 87 entries are kept as read-only history."
```

**The three choices on a type with records:** (a) **delete type + records**; (b) **keep records as read-only orphans** — the capability goes, the history stays viewable but not writable; (c) **cancel**. A type with *no* records skips the choice → a single "Delete the X type? This can't be undone." confirm.

**Skill deletion** is lighter — a skill is behavior, not data: deleting it removes the capability and its corpus entries but touches no records, and it is re-authorable (paid). Still confirmed ("Delete the X skill? This removes the capability; your records stay."), because it isn't record-undoable and may break an automation.

**Guards:**
- **Seeds cannot be deleted** — seed type definitions, built-in tracker templates, and seed skills (Spec 01 §12, Spec 02 §9) are binary, not user data. A delete against a seed definition → "That's built-in — I can't remove it, but I can stop suggesting it." Individual user records—including contacts, facts, interactions, habits, and check-ins—remain undoably editable/deletable through their workspaces.
- **Dependency check** — if an automation or another skill references the target, the impact summary names it ("the 'weekly mood review' automation uses this") so nothing breaks silently (P7).
- **Never automation-initiated** — deletion is a `system_command` only; an unattended automation has no path to this confirm and can never delete a capability (Review Feed writes can't lower undoability, CLAUDE.md).
