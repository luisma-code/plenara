# Plenara planner UX review

**Date:** 2026-08-17  
**Scope:** product model, interaction design, voice-first posture, information density, planning, engagement, and the gap between intended/specified/shipped behavior  
**Recommendation:** replace the presence-primary, sparse home with a **living planner**: free-form voice remains globally available and unusually capable, while durable, information-rich Today and Week surfaces become the primary planning workspace. Plena remains the visual and conversational collaborator, but no longer consumes the whole information hierarchy.

## Executive conclusion

Plenara is currently a compelling **capture-and-recall assistant** with the beginnings of a planner. It is not yet a strong planner.

The problem is not simply “too little UI.” It is a mismatch between the medium and the work:

- Voice is excellent for **capture, commands, narration, and asking for synthesis**.
- Planning requires **externalizing, comparing, sequencing, revising, revisiting, and recovering** a set of commitments.
- Those operations depend on persistent spatial state. Spoken lists and disappearing captions force the user to keep the plan in working memory—the exact burden a planner should remove.

The design also overcorrected. The research document says a voice-first interface lets the screen “prioritize information display and aesthetic quality over interactive density.” The shipped home kept the aesthetic opportunity but largely discarded the information-display opportunity. Full-screen Plena is memorable, but the day, week, backlog, conflicts, capacity, and recent changes are usually invisible.

The right correction is not a conventional productivity dashboard pasted behind a microphone. It is a coherent hybrid:

1. **Voice for intent:** capture, query, broad changes, and collaborative replanning.
2. **Vision for state:** what exists, what matters now, where time is going, what conflicts, and what changed.
3. **Touch for precision:** selecting, comparing, dragging, checking, and correcting details.
4. **Plena for collaboration:** listening state, explanations, suggestions, continuity, and character—present throughout, but proportionate to the task.

This requires changing several principles that are currently labeled locked. That is the recommendation, not an accidental side effect. The rules were useful in protecting voice and visual identity from becoming bolted-on features; they now overconstrain planning.

## Review method and evidence

I read the product baseline and the relevant functional, UI, voice, presence, and routine specs, then traced the shipped Flutter surfaces, task schema, skill definitions, generative planner paths, and widget tests.

I also ran the UI-level review suite:

```text
flutter test test/render_invariants_test.dart test/data_view_test.dart test/widget_test.dart
48 tests passed
```

The deterministic presence render produced these output-level measurements:

| State | Mean luminance | Lit-pixel coverage |
|---|---:|---:|
| Idle | 0.0785 | 0.3032 |
| Listening | 0.1000 | 0.3295 |
| Thinking | 0.0584 | 0.2031 |
| Speaking | 0.1581 | 0.3613 |

The states are genuinely distinguishable. The problem diagnosed here is therefore not that Plena fails to render or express state. It is that the product allocates most of the primary surface to presence state and too little to planning state.

A native macOS debug launch was attempted against isolated temporary data. It built, then crashed in macOS TCC with a privacy-violation abort before it could be visually inspected. No app process was left running. Conclusions about complete screens therefore use the real widget/render tests and implemented widget tree rather than a fresh native screenshot.

## What Plenara intends, declares, and actually ships

These three layers need to be kept separate. A declared surface that has not been wired does not help the current user; an implemented behavior contradicted by a spec should not be evaluated as though the spec already exists.

| Capability | Product intent | Declared design | Actually wired |
|---|---|---|---|
| Free-form voice capture | Natural speech, no command vocabulary | Primary input; local recognition; learn corrections | Tap to start / tap to stop-and-send is real. Local speech is wired. Corpus templates are real. The promised on-device retrieval path is disabled in production by default. |
| Home orientation | Calm, context-sensitive “Stage” | At most three ambient cards: imminent commitment, alive tracker, attention summary | Not wired. Home is Plena, current exchange, mute, and overflow menu. |
| Current action and undo | Act, describe, keep user safe | A lingering `Done` line with a visible undo chip | Not wired on the home. Voice can invoke undo, but the visible safety net is absent. |
| Conversation history | Trust through a durable turn record | Conversation Stream rebuilt from turn log | Explicitly removed from the shipped home and still owed. The current exchange disappears. |
| Always-on subtitles | Audio and text parity | Assistant words shown while spoken; captions always on | Contradicted by code: when TTS will speak, the reply display is normally set to `null`. Text clears about 1.6 seconds after speech ends when it is shown. |
| Planner browse surface | Designed archetypes, due grouping, lenses | Ten home archetypes, three lenses, doorway transitions | “Your data” is behind the overflow menu. It implements five simplified archetypes. The task checklist does not group by due horizon. |
| Direct editing | Voice plus per-value touch editing | Type-aware reading surface, no raw forms | Wired in the hidden Data view. Individual fields can be edited, dates picked, tasks checked, records deleted with undo. |
| Daily/weekly planning | Briefing and priority review | Persistent result/review cards; keep/defer/drop recommendations | Cloud strings are produced synchronously and spoken/rendered like any reply. There is no persistent review card or planning proposal workspace. The implemented weekly review is retrospective activity synthesis, not the specified open-task priority review. |
| Planning data model | Tasks, reminders, goals, people and events cooperate | Rich archetypes imply due horizon and alternate projections | Task has only `description`, `dueAt`, `completed`, `createdAt`. It cannot represent duration, scheduled time, priority, project/area, notes, dependencies, or a planning state. |
| Presence continuity | Plena never despawns | Full field → parting → ember across deeper surfaces | Home is implemented. Data and Settings are plain pushed Material routes with no ember. |
| Routine guidance | Voice-first, visually rich when useful | A special guided mode with images, progress, controls, and speech | Wired. This is evidence that a purpose-built visual experience can strengthen voice rather than compromise it. |

Key implementation evidence:

- The home defaults retrieval to false in `app/lib/main.dart`; `Session.init` only builds retrieval when explicitly enabled. The embedding client is a localhost HTTP client, not an in-process mobile model (`v0/lib/embed.dart`).
- The voice home decides that if Plena will speak, ordinary reply text need not render (`app/lib/main.dart`, the `willSpeak` / `display` branch).
- The home renders one ephemeral `_caption`, not a durable collection of turns.
- The only general browse/edit destination is “…” → “Your data.”
- `DataView` groups raw store records by type and renders five simplified structural archetypes.
- `task.json` has four fields. `list-tasks.json` sorts by `createdAt` and enumerates only `description`, so the ordinary list readback drops even the due date.
- The routine player deliberately adds a stable visual mode because the job benefits from it. That same product reasoning should be allowed for planning.

## Why it feels hard to use as a planner

### 1. Capture succeeds, but captured information immediately disappears

Plenara lowers the friction of saying “add X.” That is valuable. But after capture, the item is mostly absent from the primary surface. The user hears a confirmation, may see a brief caption in muted/no-TTS conditions, and returns to the presence.

This creates a weak handoff from **input** to **external memory**. The user still has to wonder:

- Did it understand the date?
- Did it make a task or reminder?
- Where did the item land?
- What else is already due that day?
- Did this make the day unrealistic?

Act-then-describe can make capture fast, but only if the result remains inspectable. Today it acts, describes, and visually evaporates.

### 2. The app stores information without making it available for thought

A database and a planner are not the same product. A planner turns stored commitments into a manipulable model of time and attention.

Plenara’s data can be queried, but the user must know what to ask and ask serially. “List my tasks,” “what is due this week,” “what is overdue,” and “when am I seeing Sarah?” each reveal a slice. The user has to mentally join those slices.

The result is technically capable but cognitively expensive. It makes the user operate a query interface when they need an externalized plan.

### 3. Speech is serial; planning is relational

Speech presents one item after another. Planning often asks relational questions:

- Which of these five things fits before school pickup?
- Are Thursday and Friday both overloaded?
- What can move without missing a deadline?
- Does the dinner plan collide with a reminder or a routine?
- Which tasks support the goals I said mattered?

A visual week can answer several of those questions in one glance. A spoken list requires remembering item one while hearing item six. Longer speech increases listening cost; shorter speech hides necessary detail.

### 4. There is no useful distinction between a deadline and a scheduled commitment

The task model has a date-only `dueAt`. It cannot express:

- “must be done by Friday” versus “I plan to do it Thursday at 3”;
- how long an item is expected to take;
- whether it is in the inbox, planned, in progress, blocked, deferred, or complete;
- which project, person, or life area it serves;
- whether another task must happen first.

Without those distinctions, Plenara can keep a list and issue reminders, but it cannot model a credible plan.

### 5. The primary visual hierarchy shows system state, not user state

The presence makes idle/listening/thinking/speaking legible. That answers “what is Plena doing?” It does not answer “what am I doing today?”

For an assistant demo, system state is central. For a relied-on planner, user state should dominate:

- next commitment;
- current plan;
- free capacity;
- overdue risk;
- important person/moment;
- unscheduled work;
- recent change and its undo.

Plena should interpret and animate around that state, not displace it.

### 6. Discoverability is unusually expensive in a voice-only product

The design says there is no command vocabulary. In practice, the production app defaults local retrieval off. Corpus hits cover known phrasings; novel planner phrasing falls toward a paid cloud residual when keyed or clarification when not.

In a visible UI, the user can recover from a failed phrase by seeing available objects and actions. In a sparse voice UI, the capability itself is hidden. The combination of invisible affordances and an incomplete adaptive routing path makes the promise “say it naturally” fragile at exactly the point where the UI offers no alternative clue.

### 7. Review and recovery are hidden

Planning is revision. Users change their mind, compare scenarios, and need confidence that a rearrangement did not lose anything.

The code has meaningful recovery machinery—journaled writes, corrections, numbered references, targeted undo from Data view—but the home does not expose it well:

- no persistent recent actions;
- no visible undo after a spoken write;
- no before/after view for batch replanning;
- no durable weekly recommendation card;
- no Conversation Stream to inspect what happened.

The safety exists more in mechanism than experience.

## Planning as information work

The product should be evaluated against the full planning loop, not only whether a task can be created.

| Planning operation | What the user needs | Current performance | Product implication |
|---|---|---|---|
| **Capture** | Low ceremony, natural language, quick confirmation | Strong input; weak durable visual confirmation | Keep free-form voice. Show the captured object and parsed fields immediately. |
| **Externalize** | Get commitments out of memory and into a stable place | Records persist on disk but not on the primary surface | A visible Today/Inbox view is essential. Persistence on screen is functional, not decorative. |
| **Compare** | See deadlines, effort, importance, people, and conflicts together | Requires serial queries; no comparable layout | Add day/week spatial views and an unscheduled queue. |
| **Sequence** | Decide order and assign time | Date-only due field; no duration/scheduled slot; no direct arrangement | Separate deadline from scheduled time; support touch and voice rearrangement. |
| **Edit** | Make precise changes cheaply | Voice corrections work; hidden per-value editing works | Promote contextual edit surfaces. Keep voice for broad changes and touch for precision. |
| **Revisit** | Reconstruct state after hours or days | Greeting/nudges only; current exchange vanishes | Home must answer “where was I?” in seconds. Keep a durable action/conversation ledger. |
| **Recover** | Undo mistakes and understand effects | Mechanisms exist; visible safety net mostly absent | Persistent undo and change summaries; preview multi-item changes. |

## Voice-first versus engagement and comprehension

### Voice should be first-class, not sovereign

The strongest version of Plenara does not retreat from voice. It stops asking voice to do jobs where it is the weaker medium.

| Job | Best primary medium | Why |
|---|---|---|
| Capture a thought while walking | Voice | Fast, low ceremony, eyes-free |
| Ask “what matters today?” | Voice + visual answer | Speech gives a summary; the screen preserves the evidence |
| Compare Thursday and Friday | Visual | Parallel inspection and spatial relation |
| Move three tasks | Touch or contextual voice | Touch is precise; voice is efficient when references are visible |
| Explore “what if” schedules | Visual proposal + voice refinement | Scenario stays inspectable while conversation modifies it |
| Hear a routine step | Voice | Eyes may be occupied; pacing is serial by nature |
| Correct one date or duration | Touch or voice | Both are cheap; use the convenient one |
| Re-enter after a day away | Visual | Fast orientation with no need to formulate a query |

“Voice first” should mean:

- Voice is always available.
- Voice can address every meaningful object on screen.
- The user can begin any major workflow in natural speech.
- Speech never traps the user in a command grammar.

It should not mean:

- every state must be summoned by a query;
- all editing must be described aloud;
- useful information disappears to preserve visual emptiness;
- direct manipulation is treated as design failure;
- the presence must be larger than the plan.

### Sparse is not the same as calm

Calm interfaces reduce competition and noise. Sparse interfaces remove information. A good planner can be calm and information-rich through hierarchy:

- one dominant next action;
- a compact day timeline;
- quiet metadata;
- collapsed lower-priority groups;
- progressive disclosure;
- consistent spatial placement;
- typography and whitespace that group information without making every object a card.

The research document’s “well-designed magazine” is a useful model. Magazines are not empty; they make substantial information readable through composition. Plenara should pursue editorial density, not void.

## Engagement: what will make Plena feel more alive and useful

There are two kinds of engagement:

1. **Sensory engagement:** motion, color, voice, glyphs, visual novelty.
2. **Instrumental and relational engagement:** the sense that the app remembers, helps, progresses with the user, and gives control.

Plenara is already investing heavily in the first. Planner retention will depend more on the second.

The most engaging moments would be:

- A spoken capture visibly settles into the right place in Today.
- Plena notices that Thursday is overloaded and explains the conflict with the affected items on screen.
- Moving a task visibly frees capacity rather than producing only a sentence.
- A relationship commitment appears in the same plan as work and routines, reinforcing the app’s actual purpose.
- On reopen, the screen resumes the story: what changed, what is next, and what needs a decision.
- Completing the meaningful last item closes the day with a restrained, earned Plena gesture.
- A weekly review is a durable proposal the user can inspect and refine, not a paragraph that disappears.

The presence remains valuable. It should become a **participant in the information**, not an alternative to information. More motes, more glyphs, or more frequent animation would not solve the planner problem.

## Four coherent product models

These are alternative product structures, not grab-bag feature lists.

### Model A — Presence-first assistant, lightly enriched

Keep the existing home and add the originally specified three ambient cards, lingering Done/undo, and Conversation Stream.

**Strengths**

- Lowest conceptual change.
- Preserves the strongest visual identity.
- Improves trust, re-entry, and basic orientation.

**Weaknesses**

- Still makes planning a visited activity rather than the home’s main job.
- Three cards cannot represent a real day or week.
- Compare/sequence work remains weak.

**Best if:** Plenara is primarily a relationship memory assistant with occasional task capture, not a planner the user expects to organize a week.

### Model B — Durable conversational planner

Make the Conversation Stream the home. Plena narrates, and each turn produces persistent task, plan, result, and review cards. The user plans by conversation with visual artifacts retained in the thread.

**Strengths**

- Strong continuity and trust.
- Natural evolution from voice.
- Suggestions and revisions retain context.

**Weaknesses**

- Chronology is not the same as current state; the important plan can be buried by later conversation.
- Side-by-side comparison and time allocation remain awkward.
- Risks becoming a stylized chat app.

**Best if:** collaboration and explanation matter more than detailed scheduling.

### Model C — Visual planning canvas with voice command layer

Make Today/Week the product. Plena contracts to a voice affordance and assistant rail. The plan is spatial, dense, and directly manipulable.

**Strengths**

- Best comprehension, comparison, sequencing, and direct control.
- Fastest path to becoming a credible planner.
- Makes overload, gaps, and conflicts visible.

**Weaknesses**

- Highest risk of feeling like a conventional planner.
- Plena’s character can become ornamental.
- Requires a richer task/time model and purpose-built UI.

**Best if:** planner utility outranks assistant identity.

### Model D — The living planner (recommended)

Use a visual Today/Week workspace as the durable state, with Plena as a continuous, context-aware collaborator. Voice is global and can act on visible selections and ranges. The conversation/history surface is a sheet, not the state model. Purpose-built planning surfaces coexist with archetype-based data views.

**Strengths**

- Preserves Plena’s differentiator while using the right medium for planning.
- Strong on capture and on compare/sequence/revisit.
- Allows calm editorial design rather than generic dashboard chrome.
- Makes relationship, routine, goal, and task information cooperate.

**Weaknesses**

- Requires revising several declared principles.
- More UI and business-logic work than restoring the original Stage.
- Needs careful hierarchy to avoid visual busyness.

**Best if:** the actual ambition is an assistant the owner relies on for planning and relationships, not only a beautiful voice shell.

### Decision comparison

Scores are relative, 1 (weak) to 5 (strong).

| Model | Character | Capture | Orientation | Compare/sequence | Trust/recovery | Implementation cost |
|---|---:|---:|---:|---:|---:|---:|
| A. Enriched presence | 5 | 5 | 3 | 2 | 3 | 2 |
| B. Conversation planner | 4 | 5 | 3 | 3 | 5 | 3 |
| C. Planning canvas | 2 | 4 | 5 | 5 | 5 | 5 |
| **D. Living planner** | **5** | **5** | **5** | **5** | **5** | **5** |

Cost is not a reason to choose a weaker product prematurely. It is a reason to phase Model D so each rung proves value.

## Recommended product model: the living planner

### Information architecture

Use three durable destinations and one global interaction layer:

1. **Today** — orient and execute.
2. **Plan** — compare, sequence, and revise the week/backlog.
3. **Library** — people, goals, routines, trackers, journal, and all other durable knowledge.
4. **Plena** — a global voice/conversation layer available over every destination.

This is intentionally clearer than “Stage / Stream / Collections / Operation Center.” Those names describe UI machinery. Today / Plan / Library describe user goals.

The current overflow menu can remain for Settings and developer-only tools. “Your data” should no longer be the primary route to seeing commitments.

### Today screen

The home should answer five questions without a spoken query:

1. What is next?
2. What must happen today?
3. Is the day realistic?
4. What is still unscheduled?
5. Is there a person or commitment I am in danger of forgetting?

Suggested phone composition:

```text
MONDAY, AUGUST 17                  Plena · resting
Good morning. 3h 10m planned · 1h 20m open

NOW
  9:30  Call pediatrician                    15m

TODAY
  10:00 School drop-off
  11:00 Review cabin budget                  45m
  15:30 Pick up Ana
  by 5  Send plumber photos                  due

UNSCHEDULED · 3
  Buy gift for Sarah · birthday in 4 days
  Book dentist
  Plan Saturday dinner

RECENT
  Added “Send plumber photos” · Undo

[ Hold or tap to talk to Plena ]
```

The design does not need boxes around each section. It can use the project’s typography, organic dividers, subtle time spine, warm ground, and restrained accent color. Information richness and visual beauty are compatible.

Plena’s presence should occupy a compact but expressive region—perhaps a knot of motes near the date/capacity line or a living edge around the global input. It can expand during listening/thinking/speaking and recede after the exchange.

### Plan screen

This is the manipulation surface for the week.

On phone:

- horizontal day strip with load/capacity indicators;
- selected-day agenda below;
- unscheduled/inbox queue in a collapsible lower sheet;
- deadlines shown separately from scheduled blocks;
- conflicts and over-capacity shown through layout and plain language, not red-badge urgency;
- selection mode so voice can refer to “these three.”

On desktop/tablet:

- week columns;
- unscheduled queue beside them;
- direct drag/drop and resize;
- Plena/conversation rail that explains or proposes changes without obscuring the calendar.

The planning view should be a purpose-built experience, like the routine player. It should not be forced through the generic archetype fallback. Generic archetypes remain useful for emergent data, while planning is a core binary experience keyed to canonical concepts.

### Library screen

Library contains the wider life model:

- People
- Goals
- Routines
- Trackers
- Journal
- Projects/areas
- All data / learned phrases / automations

The existing archetype work fits here. The Library index should show a meaningful live summary rather than raw type names and record counts.

The relationship graph must not become a separate silo. People-linked commitments should project into Today and Plan. A dinner with Sarah is simultaneously time, relationship context, and a chance for preparation.

### Conversation and history

Plena needs a durable conversation/action ledger, but it should not replace the plan.

- A swipe or tap on Plena opens a bottom sheet/side rail with recent utterances, replies, actions, and undo.
- Each action links to the object it changed.
- Generative outputs and planning proposals persist until dismissed or superseded.
- Spoken output is always displayed while spoken. Audio never removes visual evidence.
- The sheet can be closed without losing the current plan state.

This separates **conversation history** from **current truth**. The plan shows what is true now; the ledger shows how it became true.

## Interaction model

### Atomic capture: act, show, and keep soft

For a single understood write, retain the speed of act-then-describe:

> “Add send the plumber photos by five.”

The new task immediately condenses into Today. The parsed time and classification briefly receive emphasis. Plena says, “Added—send the plumber photos, due by five.” A visible undo remains in Recent.

This is act-then-describe made trustworthy at the output, not only in the journal.

### Exploratory and batch planning: propose, inspect, then apply

Planning a day is different from adding one item.

> “Make room for a run and move anything flexible out of Thursday afternoon.”

Plena should not silently rewrite several commitments and narrate afterward. It should produce a visual proposal:

```text
PROPOSED
  Run                              Thu 4:00–4:40
  Review cabin budget              Thu → Fri 11:00
  Book dentist                     remains unscheduled

Thursday: 35m open after changes
[Apply all] [Adjust] [Dismiss]
```

The user can say “keep the budget Thursday but shorten the run,” tap to modify, then apply. This is not timid confirmation. It is supporting an inherently exploratory task where the proposal itself is the useful artifact.

### Contextual voice over visible objects

Voice becomes more powerful when it has a visible reference frame:

- “Move these two to Friday.”
- “Only show things involving Sarah.”
- “What can I drop from Thursday?”
- “Make the first one 30 minutes.”
- “Put this after school pickup.”

Selections, time ranges, and the current view should enter the NLU context as explicit structured references. The user should not have to repeat full titles.

### Direct manipulation is a partner, not a fallback

Support:

- tap to complete;
- drag to schedule/reschedule;
- resize to change estimate;
- swipe or context action to defer;
- tap a value to edit;
- multi-select for batch moves;
- keyboard shortcuts on desktop.

Every direct action should use the same journal, undo, automation, and correction semantics as voice. One business-logic path can still serve multiple UI inputs.

## Required planning model

The present task type cannot support the recommended experience. A planning-capable task needs at least:

| Field | Purpose |
|---|---|
| `description` | What the action is |
| `status` | inbox / planned / in-progress / done / cancelled or equivalent |
| `dueAt` | Deadline; distinct from intended work time |
| `scheduledStartAt` | When the user plans to do it |
| `estimatedMinutes` | Capacity and realistic sequencing |
| `priority` | User importance, not inferred urgency alone |
| `projectRef` or `areaRef` | Context and grouping |
| `contactRefs` | Relationship context and people-centered planning |
| `notes` | Supporting detail without bloating the title |
| `completedAt` | Weekly review and accurate progress history |
| `createdAt` | Audit/order fallback |

Optional later fields include dependencies, energy/context, recurrence, and blocked reason. Do not add all optional complexity before observed need, but do not try to build capacity planning without scheduled time and duration.

Tasks and reminders can remain distinct records. The UI should project them together as commitments while preserving the semantic distinction: a task is work; a reminder is a notification trigger.

## Engagement design in the living planner

### Make motion carry state continuity

The best planning animations show causality:

- capture → item settles into Inbox/Today;
- reschedule → item travels to the new time while old space closes;
- proposal preview → affected items ghost to proposed positions, current state remains readable;
- apply → ghost becomes solid;
- undo → object returns along the reverse relation;
- completion → row resolves into the Done seam, with an earned Plena glyph when appropriate.

This uses the existing “motion means meaning” principle more effectively than disappearing prose.

### Let Plena scale with conversational intensity

- **Resting/planning:** compact presence; plan dominates.
- **Listening:** presence gathers and input transcript remains visible.
- **Thinking over selected items:** affected objects receive subtle relation cues; presence shows effort without obscuring them.
- **Speaking:** full caption remains visible; presence can expand modestly.
- **Deep conversation or empty state:** presence may take the stage.

This preserves the entity without requiring the entity to be the background of every task.

### Reward meaning, not app use

Avoid engagement mechanics based on opening streaks, badges, or arbitrary completion counts. Prefer:

- closure on a day the user intentionally planned;
- progress toward self-declared goals;
- honoring a relationship commitment;
- reducing overload;
- noticing a neglected but important area;
- reflecting accurate patterns in the user’s own data.

The existing apt-or-absent glyph principle fits. The event should earn the gesture.

## Principle conflicts and recommended amendments

Nothing is treated as immovable in this review. These conflicts are explicit so the proposal is not quietly narrowed to fit earlier rules.

| Existing rule | Provenance and original purpose | Conflict | Recommendation |
|---|---|---|---|
| **“Free-form speech is the primary input.”** | Research §2.1; protects natural interaction from command grammars | “Primary” becomes “dominant in every context,” even where planning needs a visual workspace | **Amend:** free-form voice is globally available, first-class, and able to initiate every major workflow. The primary manipulation medium depends on the task. |
| **“The visual design is never compromised to accommodate keyboard or touch-first interaction patterns.”** | Research §2.2; prevents a second-class bolt-on text mode | It frames useful direct manipulation as compromise | **Replace:** design one coherent multimodal system. Voice, touch, keyboard, and vision share the same objects and business rules; none is a degraded alternate. |
| **“Context-sensitive display—what is shown on screen is curated and minimal, not a full CRUD list view.”** | Research §2.3; protects beauty and avoids generic database UI | “Minimal” has drifted into insufficient external memory | **Amend:** curated and information-rich, not exhaustive or CRUD-shaped. Use progressive disclosure and editorial hierarchy. |
| **“No flow may require a tap… If a view seems to need a complex touch interaction, the view is wrong.”** | Spec 07 P1; applies uncompromising voice to all screens | Comparison and spatial arrangement are not naturally serial voice tasks | **Replace:** no core workflow may be voice-inaccessible, but precision workflows may legitimately use direct manipulation. Provide equivalent outcomes, not identical mechanics. |
| **“The presence is the app, not a widget in it.”** | Spec 15 P1; creates a distinctive entity rather than an assistant indicator | It forces system presence above user plan in the hierarchy | **Replace:** Plena is the continuous collaborator, not the entire canvas. She persists across surfaces and changes scale according to the work. |
| **“The app is composed of exactly four top-level surfaces… Plenara is not a tabbed dashboard.”** | Spec 07 §2; reduces navigation and ambient noise | Stage/Stream/Collections/Operation Center are system abstractions, and hiding Today/Plan harms orientation | **Replace:** Today, Plan, Library, plus global Plena. Three clear destinations are lower cognitive cost than a hidden surface model. |
| **“Act, then describe” for all understood writes** | Research §15.1 / Spec 05 §3; eliminates confirmation friction and relies on undo | Multi-record scheduling is exploratory; applying a guess can create cascading plan damage | **Scope:** atomic reversible actions act/show/describe. Batch, ambiguous high-coupling, and what-if planning produces inspectable proposals before commit. |
| **“No forms, ever.”** | Spec 07 D5; avoids auto-generated CRUD interfaces | A blanket ban rejects effective inspectors and structured planning details | **Amend:** no raw schema-generated CRUD as the primary experience. Curated inspectors, inline fields, date/time controls, and direct manipulation are allowed. |
| **Closed archetype set as the whole UI strategy** | Spec 07 P4/D1; guarantees emergent types render without new code | Core planning needs a composite experience across tasks, reminders, people, goals, and time | **Retain for emergent data; add a purpose-built planner projection.** The routine player already demonstrates this boundary. |
| **“Text appears only when it carries something voice alone cannot.”** | Spec 15 P6; protects the living field from text intrusion | Written state aids comprehension, trust, and recall even when audio carries the same words | **Replace:** text persists whenever it reduces memory load or makes an action inspectable. Audio and text may deliberately duplicate. |

The recommendation is to change the rules, not dilute the product proposal. The cost is more interface design and a less absolute voice/presence story. The benefit is a planner that can actually carry planning cognition.

## Phased product plan

### Phase 0 — Establish a planner baseline

Before changing the product, instrument a small set of real tasks and run them on the shipped app:

1. Capture six mixed commitments, some with dates and some without.
2. Determine what is due today and this week.
3. Find an overloaded day.
4. Move two commitments.
5. Correct one misunderstood capture.
6. Reopen the next day and reconstruct the plan.
7. Undo an accidental change.

Measure completion, time, voice turns, taps, clarification/correction count, backtracking, and delayed recall. Record subjective confidence after each scenario.

Also log how often production routing hits corpus, cloud, or clarification with retrieval off. A voice-first design cannot be judged separately from natural-phrasing success.

### Phase 1 — Trust and orientation

Build the smallest version of the new product model:

- Today as the home;
- compact persistent Plena;
- open tasks/reminders projected into today/unscheduled sections;
- persistent spoken captions;
- recent actions with visible targeted undo;
- conversation/action ledger;
- direct task completion;
- voice available over the whole surface.

Do not wait for the full Week canvas. This phase tests whether visible state materially improves use without losing Plena’s identity.

**Gate:** in a five-second glance test, the user can identify the next commitment and whether anything is overdue at least 90% of the time; capture confidence improves without increasing capture time by more than 10%.

### Phase 2 — Real planning primitives

- Migrate the task schema with scheduled time, estimate, status, priority, project/area, contact links, notes, and completion timestamp.
- Separate deadline from scheduled time.
- Add Plan/Week and Inbox.
- Add direct schedule/reschedule and inline editing.
- Put selection and visible-range context into voice routing.
- Project people events and routines into the plan.

**Gate:** users complete compare/sequence scenarios at least 30% faster than the enriched presence baseline, with fewer corrective turns and no loss of successful voice capture.

### Phase 3 — Collaborative replanning

- Code-first capacity and conflict detection.
- Visual proposal/diff model.
- Voice refinement of proposals.
- Atomic apply/undo for a whole proposal.
- Durable morning and weekly review artifacts.
- Cloud reasoning only where judgment genuinely exceeds deterministic rules.

**Gate:** at least 80% of accepted proposals require no immediate correction; users can explain what changed after a batch operation; undo restores the complete prior plan.

### Phase 4 — Relationship-centered engagement

- Bring relationship moments into Today/Week at the right frequency.
- Add event-prep and reconnect proposals as durable, editable artifacts.
- Connect goals/routines to actual scheduled work.
- Tune Plena’s gestures around meaningful completion, overload relief, and kept commitments.
- Expand Library archetypes after real data shows where generic rendering fails.

**Gate:** relationship and goal context changes actual plans without increasing dismissal fatigue; proactive items are acted on or explicitly dismissed rather than ignored.

## Usability experiments

### Experiment 1 — Home model crossover

Prototype three homes with the same data:

- current presence home;
- enriched presence with three ambient cards;
- living-planner Today.

Ask users, after a five-second exposure:

- What is next?
- What is overdue?
- How busy is today?
- What did the app just change?

Measure correctness, confidence, and time. This isolates orientation from deeper feature completeness.

### Experiment 2 — Voice-only versus visible-context voice

Run the same replanning scenario in two conditions:

- spoken lists and follow-up references only;
- week view with visible selections and contextual voice.

Measure number of words spoken, turns, reference errors, completion time, and whether the final plan matches intent.

Hypothesis: visible-context voice will use fewer words and fewer turns even though the screen contains more information.

### Experiment 3 — Commitment model comprehension

Test whether users correctly distinguish:

- due Friday;
- scheduled Thursday at 3;
- reminder Thursday at 3;
- unscheduled but high priority.

The current model cannot represent this distinction fully. Prototype the semantics before finalizing schema names.

### Experiment 4 — Batch action trust

Compare:

- silent act-then-describe for three reschedules;
- proposal/diff then apply.

Measure time, corrections, confidence, and ability to recount the changes. The proposal may take one extra tap and still win if it prevents recovery work and increases trust.

### Experiment 5 — Five-day dogfood re-entry

Use each model for five consecutive days with real commitments. Each morning, record:

- time until the user knows what to do next;
- forgotten or duplicate captures;
- stale unscheduled items;
- number of “list/show/what’s due” orientation queries;
- perceived control (1–7);
- whether Plena felt more or less present.

This catches the difference between a delightful first minute and a relied-on fifth day.

## Metrics that matter

Avoid optimizing raw screen time or daily opens. A good planner may reduce both.

### Planner utility

- **Time to orientation:** open → accurately identify next action and urgent risk.
- **Capture-to-placement success:** item lands in the intended semantic place on the first turn.
- **Plan completion rate:** benchmark scenario completed without external notes.
- **Replanning cost:** turns/taps/time to move a set of commitments coherently.
- **Stale backlog rate:** unscheduled items older than 7/14 days.
- **Overload visibility:** user detects intentionally planted capacity conflicts.
- **Re-entry recall:** accuracy reconstructing plan after 24 hours.

### Trust and control

- Correction rate after capture.
- Undo rate and successful complete restoration.
- Batch proposal acceptance, adjustment, and immediate-reversal rates.
- “I know what changed” score after actions.
- Clarification rate by routing source.
- Rate of commands that work naturally without the user learning a phrase.

### Healthy engagement

- Percentage of planning sessions that end with a concrete plan or completed action.
- Return to previously captured items before they become stale.
- Meaningful relationship commitments planned or completed.
- Morning/weekly review usefulness rating.
- Proactive suggestion acted on versus dismissed versus ignored.
- Perceived helpfulness and calm, measured separately; a visually calm app can still be unhelpful.

## Decision criteria

Choose the living planner if the tests show:

- visible Today materially improves five-second orientation;
- voice capture speed remains essentially unchanged;
- compare/sequence work becomes faster and less error-prone;
- users trust batch changes more when shown a proposal;
- Plena still feels like a continuous collaborator at smaller visual scale;
- information-rich surfaces remain calm under real—not demo—data volumes.

Reject or revise it if:

- the Today screen becomes a maintenance burden users avoid;
- scheduling detail causes capture friction;
- users consistently prefer conversational artifacts over spatial planning;
- Plena’s compact form genuinely loses the product’s emotional identity and expansion-on-conversation does not restore it.

The key comparison is not “beautiful presence versus ugly dashboard.” It is whether Plenara can become both **beautiful and cognitively useful**. The project’s visual ambition is strong enough to design an information-rich planner that does not look conventional.

## Final recommendation

Move forward with Model D, the living planner.

Keep:

- natural, free-form voice;
- local/offline capture;
- act-then-describe for atomic reversible writes;
- Plena’s abstract presence and restrained gesture vocabulary;
- deterministic execution and one journal/undo path;
- archetypes for emergent data;
- the calm, organic editorial design ambition.

Change:

- the presence-primary home;
- ephemeral spoken output;
- minimal-as-sparse information policy;
- voice as the preferred manipulation medium for every task;
- the hidden “Your data” route as the only durable browse surface;
- act-then-describe for exploratory multi-record planning;
- the four-surface system vocabulary;
- the task schema’s inability to model a plan.

Plenara will become more engaging when opening it reveals a living, useful model of the user’s life—not only a beautiful entity waiting to be asked.
