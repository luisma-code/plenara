# Plenara

Technology Research, Vision & Architecture Baseline

Version 0.10 · July 2026

## 1. Vision & Constraints

Plenara is a voice-driven, AI-augmented personal assistant whose purpose
is to help its user be a better friend, husband, and parent --- by
remembering what matters about the people and commitments in their life,
surfacing the right nudge at the right moment, and helping plan the
small acts that sustain relationships. It is a passion project first:
the goal is that it exists, works, and is genuinely used, not that it is
profitable.

The north star is that Plenara should feel intuitive and, at its best,
sci-fi level helpful --- the user speaks a need in plain language and
the app quietly does the right thing, learns their vocabulary, and
anticipates rather than waits. Section 3 makes that ambition concrete
through twenty marquee user tasks; Section 4 derives the central
architectural consequence: that Plenara's capabilities should grow as
data authored on the fly, not as features hard-coded ahead of time.

Target platforms, in strict priority order:

-   **P1:** iPhone

-   **P2:** Windows desktop

-   **P3:** Android

-   **P4:** macOS desktop

All four remain in the framework comparisons (Section 5) so the
architecture never accidentally closes the door on a lower-priority
target. This reorders an earlier draft that grouped the desktops with
iPhone: iPhone is now the sole first release target, with the macOS
desktop last.

The document is organized so that vision and principles drive the
technology choices, which in turn drive the roadmap, the specifications
to write next, and the operational concerns --- safety, feedback, and
diagnostics --- that follow. It is intended as the stable baseline that
later specs --- architecture, functional, schema, skill, and test ---
build on.

## 2. Core Design Principles

These principles are fixed constraints that inform every technical and
product decision. They are listed here so that trade-offs in later
sections can be evaluated against them explicitly. Principles 2.1--2.5
are locked in. Principles 2.6--2.7 fall out of the Section 4 analysis;
because that direction (Option C) is now confirmed (Section 15.1), they
are adopted with it. Principle 2.8 is a cross-cutting robustness rule
--- added directly rather than derived --- governing how every layer
behaves when it cannot proceed.

### 2.1 Voice Is Uncompromising

Principle: Free-form speech is the primary input. The app figures out
what the user meant --- not the other way around.

There is no voice command vocabulary the user needs to learn. Users say
what they naturally want to say, and Plenara maps that utterance to
intent using its NLU layer. When the mapping is wrong or ambiguous, the
app asks a clarifying question, then records the correction --- updating
its internal model so the same phrasing is understood correctly in the
future. Over time the app gets better at understanding how a specific
user talks.

This adaptive NLU is a core differentiator. The interaction loop is:

-   **Hear:** transcribe the utterance on-device.

-   **Understand:** classify intent and extract entities (task, person,
    > date, etc.) using the local NLU model.

-   **Act, describe, or clarify:** on an understood or best-guess
    > intent, act immediately and describe what was done in one line
    > (act-then-describe, §15.1); only when there is no reliable guess,
    > ask one targeted question. Reliable undo is the safety net, not a
    > pre-action prompt.

-   **Learn:** store the corrected mapping in a user-specific intent
    > corpus (a JSON file in the Plenara folder). This corpus is sent as
    > context to the NLU model on subsequent calls, gradually reducing
    > clarification frequency.

The goal is that within a few weeks of use, the app rarely asks for
clarification because it has learned the user's vocabulary and phrasing
patterns.

### 2.2 Text Is an Overlay, Not an Alternative UI

Principle: The UI is designed for voice. Text input and subtitles are
surfaced as a quiet-mode overlay without compromising the visual design.

Because users sometimes need to interact in situations where speaking
aloud is not practical (a meeting, a library, a shared space), Plenara
provides a text input path. However, this is implemented as an overlay
on top of the voice-first UI --- a text field slides in when activated
--- rather than a separate keyboard-centric layout. Similarly, the app's
spoken output is simultaneously displayed as subtitles, so the user can
read rather than listen when needed.

The visual design is never compromised to accommodate keyboard or
touch-first interaction patterns. If a feature requires a complex touch
interaction to drive, that is a signal to reconsider whether voice can
carry it instead.

### 2.3 Beautiful, Organic UI

Principle: Plenara's visual identity is fluid, organic, and
intentionally beautiful --- not a grid of rectangular buttons.

A voice-first interface is a rare opportunity: because the user is not
constantly tapping buttons, the screen can prioritize information
display and aesthetic quality over interactive density. The UI should
feel more like a well-designed magazine than a productivity dashboard.

Characteristics to pursue:

-   **Fluid animations and transitions** --- state changes are animated,
    > not instant.

-   **Organic shapes** --- rounded, flowing forms rather than hard-edged
    > rectangular cards.

-   **Generous whitespace** --- information is given room to breathe.

-   **Typography-led hierarchy** --- readable, well-considered type does
    > most of the organizational work.

-   **Context-sensitive display** --- what is shown on screen is curated
    > and minimal, not a full CRUD list view.

This is an explicit v1+ goal. The v1 UI will be functional and clean;
the organic/fluid visual language is layered on as the product matures.
Choosing a framework that supports this from day one is important (see
Section 5). This principle is in productive tension with the emergent
type system of Section 4: user-defined types must not degrade into
auto-generated forms. The resolution --- a small library of curated view
archetypes that any type maps into --- is described in 4.5.

### 2.4 Code Over AI

Principle: If a task can be solved reliably with deterministic code, it
should be. AI fills the gaps where code cannot.

AI --- whether local or cloud --- is powerful but non-deterministic,
harder to test, and consumes resources. The bar for reaching for AI is:
would a reliable, maintainable code-based implementation be
significantly more complex or impossible to write? If the answer is no,
write the code.

Concretely: if choosing between (a) a local or cloud model that follows
a skill script and makes 10 MCP calls to accomplish a task, and (b) a
deterministic code implementation that does the same thing reliably and
repeatably, we choose (b) every time.

AI is reserved for tasks that are genuinely hard to solve with code ---
tasks that require reasoning over unstructured or highly variable
inputs, or that benefit from knowledge that cannot be encoded in rules:

-   Natural language understanding of free-form voice input --- this is
    > the core case.

-   Gift suggestions for a friend given their likes, dislikes, and
    > recent activities together.

-   Reasoning about calendar conflicts, priority trade-offs, or life
    > goals.

-   Generating a personalized briefing from heterogeneous data.

This principle also keeps the local model percentage high --- and that
percentage will grow over time as local models improve, making the app
more capable while spending fewer cloud tokens.

### 2.5 Aggressive Layering

Principle: Business logic, storage, UI, and intelligence are separate
layers. No layer knows the internals of another.

Every major architectural decision in Plenara should be reversible
without rewriting the application. This requires strict layer separation
from the first commit:

-   **UI layer:** renders state, emits events. Has no knowledge of
    > storage or AI.

-   **Business logic layer:** owns rules, state transitions, and
    > workflows. Has no knowledge of how data is persisted or how the UI
    > renders.

-   **Storage layer:** reads and writes records. Today this is JSON
    > files on a cloud-synced folder; tomorrow it could be a database or
    > a cloud API. The rest of the app is insulated from this choice.

-   **Intelligence layer:** handles NLU, intent classification, and
    > Claude API calls. By design the local model handles \~95% of
    > calls; the split can shift without touching other layers.

If we decide folder-based JSON sync is not working, we replace the
storage layer. If a better local model emerges, we swap it in the
intelligence layer. Neither change should cascade into the UI or
business logic.

### 2.6 Capabilities Are Data, Not Code

Principle: Plenara's feature surface grows by writing data --- type
definitions and skills --- not by shipping new binaries. A capability
the team did not anticipate should be expressible as declarative
artifacts stored in the user's folder, not as a code change that must
pass through an app-store review.

This is the principle that makes "sci-fi helpful" tractable without
trying to predict every use case in advance (see Section 4). It is a
direct extension of 2.4: the durable artifact the model produces is
data, and deterministic code interprets it.

### 2.7 AI Authors, Code Executes

Principle: AI is allowed to compose new capabilities, but only as
declarative artifacts drawn from a fixed vocabulary of primitives that
the app's compiled, reviewed code executes. The model is never in the
hot path of a routine action, and never ships executable code to the
device.

So AI may, once, author a "Meal" type and a "log a meal" skill; from
then on every "I had oatmeal" runs through deterministic code. This
keeps non-determinism at the authoring boundary, preserves testability,
and --- critically --- keeps the app compliant with mobile store rules
that forbid downloading and running new code (see 4.7).

### 2.8 No Silent Failure

Principle: Plenara never fails silently. When it cannot act, it engages
the user rather than dropping the request, guessing, or degrading
quietly. Three failure modes share one response --- bring the person in.
When the app fails to understand an utterance, it asks the user to
clarify instead of guessing. When an instruction is too complex to carry
out as a single step, it works with the user to break it down rather
than doing a partial job. When a request is blocked by model policy (on
the cloud and authoring surfaces), it tells the user plainly what was
blocked and why, rather than quietly discarding it.

This is a product-robustness rule as much as a safety one. It is why the
NLU layer emits a clarification request instead of a silent
low-confidence guess, why the interpreter surfaces a structured error
--- and, for an out-of-vocabulary request, an authoring "here is what I
can do instead" --- rather than a dead end, and why invalid data lands
in a visible repair view instead of vanishing. Every failure has an
address the user can act on.

## 3. The Sci-Fi Helpful Vision & Marquee User Tasks

This section imagines Plenara at its best and states, as concrete user
tasks, what it should feel effortless to do. The list is deliberately
split along the free/paid line because that line is also an
architectural line: the free tier is everything deterministic code and a
small on-device model can do reliably and privately; the paid tier is
everything that genuinely needs Claude's reasoning and synthesis.
Section 4 then derives what the data and intelligence layers must look
like to deliver all twenty without hard-coding each one.

### 3.1 What "Sci-Fi Helpful" Means Here

Three qualities separate a merely useful assistant from one that feels
like science fiction:

-   **Zero ceremony:** the user states a need in whatever words come
    > naturally and the right thing happens --- no menus, no forms, no
    > learning the app's vocabulary. The app adapts to the person, not
    > the reverse (Principle 2.1).

-   **It grows with you:** when the user invents a use the designers
    > never imagined --- tracking a toddler's naps, logging which wines
    > a friend liked --- Plenara can take it on without an update,
    > because capability is data (Principle 2.6).

-   **It anticipates:** the highest-value moments are unprompted --- the
    > nudge that arrives before you would have thought to ask. This is
    > where Claude earns its place (paid tier).

### 3.2 Ten Free-Tier Marquee Tasks

These run entirely on-device: deterministic code plus the local 1--3B
model, no cloud call, fully offline, data in the user's own folder. They
constitute a genuinely useful product on their own --- the free tier is
never a crippled demo.

-   **1. Capture anything hands-free and have it filed correctly.**
    > "Remind me to call the plumber Thursday," "note that Ana starts
    > her new job Monday" --- the utterance lands as the right record
    > type with the right fields, no menu.

-   **2. Set natural, relative, and recurring reminders.** "Every second
    > Tuesday, take the bins out," "in three weeks nudge me about the
    > tickets" --- parsed and scheduled by deterministic date/recurrence
    > code.

-   **3. Spin up a personal tracker by voice from a template.** "Start
    > tracking my runs / water / reading / mood" instantiates a built-in
    > type template locally --- no cloud needed for the common cases.

-   **4. Log against any tracker conversationally.** "Had oatmeal and
    > coffee," "ran 5k," "read 20 pages" --- once a type exists,
    > appending an entry is pure code.

-   **5. See habit streaks and get gentle, on-time nudges.** Streaks,
    > gaps, and time-based reminders to keep a habit alive, computed
    > locally.

-   **6. Remember and recall facts about people.** "Sarah's daughter Mia
    > is allergic to peanuts" is stored on the contact; "what's Mia
    > allergic to?" is answered instantly from local data.

-   **7. Answer "when did I last...".** "When did I last see Marco?",
    > "how long since I called Mum?" --- computed from the interaction
    > log.

-   **8. Keep a private 60-second daily voice journal.** Transcribed
    > on-device, stored as one file per day, never leaves the device.

-   **9. Find any past note or entry by meaning.** "Find that note about
    > the cabin trip" works via on-device semantic search, not
    > exact-match.

-   **10. Do all of it silently and offline.** The text/subtitle overlay
    > gives full input and output parity when speaking aloud is not
    > possible --- with everything above still working with no network.

### 3.3 Ten Paid-Tier Marquee Tasks

These need Claude because they require reasoning over unstructured or
heterogeneous data, synthesis into natural language, or judgement about
priorities and relationships --- exactly the cases Principle 2.4
reserves for AI. Cost is controlled with Haiku-for-most, batch pricing
for anything asynchronous, and aggressive prompt caching (Section 7).

-   **1. Describe a brand-new capability and have Plenara build it.** "I
    > want to track my daughter's mood and what preceded her good and
    > bad days" --- Claude authors a bespoke type, a logging skill, and
    > a suitable view (Section 4).

-   **2. A synthesized spoken morning briefing.** One digest across
    > tasks, calendar, people, and trackers, delivered as natural speech
    > --- generated once a day on the batch API for a fraction of a
    > cent.

-   **3. Thoughtful gift suggestions.** "What should I get Sarah for her
    > birthday?" reasoned over her likes, dislikes, recent shared
    > activities, and a budget.

-   **4. Full prep for a social event.** "Dinner with the Garcias
    > Saturday" → who's coming, what we know about them, when we last
    > met, open threads to follow up, topics to raise or avoid, and what
    > to cook given their preferences.

-   **5. Relationship re-connect coaching.** "I've drifted from Marco
    > --- help me reconnect" yields context-aware suggestions and a
    > drafted opener in the user's own voice.

-   **6. Weekly priority review.** Claude scans tasks and goals and
    > recommends what to drop, defer, or escalate, with a short
    > rationale for each.

-   **7. Cross-tracker pattern insight.** "What tends to precede my
    > bad-sleep nights?" --- correlation across trackers narrated in
    > plain language.

-   **8. What-to-eat and recipe recommendations.** Drawn from logged
    > nutrition, stated goals and preferences, and optionally what's on
    > hand.

-   **9. Monthly narrative reflection.** A synthesis across journal
    > entries and interactions that no deterministic code could
    > meaningfully produce.

-   **10. Proactive, unprompted nudges.** "You see Sarah on Friday and
    > her birthday is in three weeks --- want to capture a gift idea?"
    > The assistant reaches out at the right moment rather than waiting
    > to be asked.

### 3.4 The Question These Tasks Force

Look at tasks like nutrition tracking, mood-and-antecedent logging, or
"which wines did this friend like." None of these were in the original
data model of tasks, contacts, and journal entries. The design question
is sharp: do we try to anticipate every such use case and ship a fixed
type for each, or do we build a system where the model can define new
kinds of things on the fly and the rest of the app simply understands
them?

The first path does not scale --- there will always be a use we did not
foresee, and a fat fixed schema bloats the app while still missing
cases. The second path is the one that matches the vision. Section 4
works out how to do it without sacrificing determinism, testability, or
the store-compliance and aesthetic constraints.

## 4. Capabilities as Data: The Emergent Type System

This is the architectural heart of the document and the piece that most
changes the current design. The current data layer defines a fixed
hierarchy --- tasks, contacts, journal --- with fixed types. The marquee
tasks show that this is not flexible enough. The proposal is to keep a
small fixed foundation and make the type system itself extensible data.

### 4.1 Three Options, and the Synthesis

-   **Option A --- anticipate everything.** Ship a record type for every
    > use we can imagine. Rejected: it never covers the long tail, and
    > it bloats the app and violates the learn-the-user ethos.

-   **Option B --- fully emergent.** Let the model invent arbitrary
    > types, folders, and fields at runtime. Maximum flexibility, but it
    > pushes non-determinism into the storage layer, makes testing and
    > migration hard, and invites five subtly different "food" schemas.

-   **Option C --- fixed meta-schema, emergent types (recommended ---
    > confirmed as the direction).** Define a minimal kernel of
    > primitives that everything decomposes into, and let user-defined
    > types be authored on top of that kernel as data. "Task,"
    > "contact," and "journal entry" become built-in seed types
    > expressed in the very same meta-schema --- not special cases in
    > code.

Option C reframes Plenara: it is a personal, typed object store --- a
small knowledge graph --- with a voice front-end, where the type system
is user-extensible, AI-authored, and code-executed.

### 4.2 The Meta-Schema (the fixed kernel)

A handful of primitives is enough to express every marquee task. These
are the only concepts the storage and business-logic layers hard-code;
everything else is built from them:

-   **Entity:** a noun the user cares about --- a person, a food item, a
    > book, a plant, a workout routine.

-   **Record / Event:** a timestamped occurrence --- ate X, ran 5k, met
    > Z, logged a mood.

-   **Attribute:** a typed field on an entity or record (text, number,
    > date, enum, reference).

-   **Relation:** a typed edge between entities --- Mia is-child-of
    > Sarah.

-   **Trigger / Reminder:** a rule that fires on a time or a condition.

-   **Type Definition:** a user- or AI-authored class ("Meal,"
    > "Workout," "GiftIdea") with its fields, its default reminders, and
    > a presentation hint (4.5). Stored as a JSON file in types/.

Because the storage layer operates on the meta-schema rather than on
hard-coded "task" logic, adding a "Meal" type is just writing
types/meal.json plus a folder of meal records. Persistence, the
in-memory cache, sync, and conflict handling all work unchanged --- they
were never type-specific to begin with.

### 4.3 How a New Capability Is Drafted On the Fly

Take the nutrition example end to end:

-   **1.** User: "I want to start tracking what I eat."

-   **2.** The local model recognizes this as a capability-definition
    > meta-intent, not an ordinary record intent. Because it is rare and
    > reasoning-heavy, it is gated to Claude --- this is precisely the
    > 5% case of Principle 2.4.

-   **3.** Claude proposes a Type Definition ("Meal": datetime, items,
    > optional calories, notes), sensible default reminders ("log dinner
    > around 8pm?"), and optionally a skill (4.4) for how logging should
    > behave.

-   **4.** The user confirms by voice. The type and skill are persisted
    > as durable JSON artifacts in the folder.

-   **5.** From then on, "I had a chicken salad" routes to the Meal type
    > deterministically, with no further cloud call. The UI renders the
    > new type through a curated view archetype (4.5).

The payoff: the capability surface grows without an app update, because
a capability is data the model wrote, not a binary the store had to
review. This is what Principles 2.6 and 2.7 codify.

### 4.4 The Skill DSL: Declarative, Not Executable

A "skill" is Plenara's durable, reusable recipe --- but it is
emphatically not generated code. It is a data structure: an ordered
sequence of steps drawn from a fixed vocabulary of primitive operations
the app already implements, for example: create a record of type T, set
a field, schedule a reminder, query records matching a condition, ask
the user one question, or call Claude with a named template. A compiled,
reviewed interpreter runs these steps identically on every platform.

The model composes skills from existing primitives; it never authors
code that ships to the device. This is the reconciliation with Code Over
AI: the AI produces a declarative artifact once, and deterministic code
executes it forever after. It is also what keeps skill-building testable
--- you exhaustively test the interpreter and the primitive vocabulary,
and composed skills are then correct by construction to the degree the
primitives are.

Who does what matters here, because it is where Code-Over-AI is enforced
concretely. The local model's job ends at producing a structured intent
--- it classifies, routes to a type/skill (4.6), extracts slots, and
scores confidence. It never invokes operations itself. The deterministic
Skill Interpreter then executes the skill's steps, binding those slots
as parameters to primitive operations. This is deliberately different
from letting the model call operations at runtime: for routine actions
the skill already encodes the operation sequence, so the model stays out
of the hot path.

There is essentially one architecture with two paths, which map exactly
onto the fast/slow split of 4.9. Fast path --- a skill already exists
and confidence is high: load the skill and run it in pure code, no cloud
call. Slow path --- a novel request, no skill, or low confidence:
escalate to Claude, which either authors a new type/skill or returns a
one-off resolved plan, stores its safety assessment (13.2), and persists
the skill so the next occurrence takes the fast path.

![](media/image1.png){width="6.3in" height="5.071353893263342in"}

*Figure 4.4 --- High-level request flow. The local model produces intent
only; deterministic code executes every operation. The fast path avoids
the cloud; the slow path authors and caches a skill (4.9). Detail is
deferred to the Architecture and Skill DSL specs.*

### 4.5 Keeping It Beautiful: View Archetypes

The obvious risk to Principle 2.3 is that user-defined types produce
ugly auto-generated CRUD forms --- exactly the grid of rectangles the
design forbids. The resolution is to invest in a small set of genuinely
beautiful, reusable view archetypes --- for example a timeline, a streak
ring, a ledger, a gallery, and a person card --- and to have each type
carry a presentation hint that maps it to an archetype. A new "Meal"
type is not rendered as a raw form; it is assigned the timeline
archetype and inherits its polish. Designing this archetype set is a
first-class UI task, not an afterthought. The specific initial set is
deferred to the UI and functional specs (Section 12), where it can be
designed against the concrete marquee tasks.

### 4.6 The Skill Layer's Effect on NLU

A growing, user-defined type space is harder for a small local model
than a fixed intent set. The recommended approach is two-tier routing:
first route the utterance to a type using retrieval over the type
registry (embedding similarity against type names, fields, and example
phrasings), then extract fields for that type. Retrieval-augmented
routing scales as new types appear without retraining a fixed classifier
head, and it dovetails with the corrections corpus of Principle 2.1.

The knowledge Plenara accumulates --- types, skills, the corrections
corpus, relationship notes --- will need maintenance, or it decays into
clutter the way any long-lived store does. Plan for a periodic, largely
model-assisted consolidation pass (say weekly, on-device where
possible): merge near-duplicate types, prune skills that never fire,
fold redundant corrections into general rules, and flag stale or
contradictory data for the user. This is the housekeeping counterpart to
the reconciliation step of 4.8 and should be a named background
capability, not an afterthought.

One consequence of running both a small local model and larger backend
models is that a single skill or slice of context may warrant two tuned
representations: a compact form sized to the local model's limited
window and capabilities, and a richer form for the backend models.
Keeping these as two projections of the same underlying artifact ---
rather than two sources of truth --- avoids drift, and is a detail for
the Skill DSL and AI specs.

### 4.7 Platform Feasibility --- Why Declarative Wins

Luis's instinct is correct: generating and running arbitrary code on the
device is trivial on a full OS but effectively a non-starter on mobile.
Apple's guideline 2.5.2 forbids apps that download and execute code
which changes their features; there is no reliable third-party JIT, and
shipping generated Dart or native to the device would not survive
review. So the escape hatch of "the model writes a script we save and
run" is viable on macOS and Windows but not on iOS or Android.

The declarative Skill DSL sidesteps this entirely: it ships data, not
code, and interprets it with a fixed interpreter that is compiled into
the reviewed app. This keeps behavior identical across all four
platforms and keeps the app compliant. True native scripting on desktop
remains a conceivable far-future power-user hatch, but it forks behavior
across platforms and breaks the "same everywhere" promise, so it is
explicitly out of scope for parity and should not be relied on for any
core capability.

### 4.8 Risks and Governance This Introduces

-   **Schema sprawl and duplicates.** The model might create both "Meal"
    > and later "Food log." Mitigation: a type registry plus a
    > reconciliation step --- before creating a type, check for a
    > semantically close existing one (embedding similarity) and reuse
    > or extend it. This reconciliation is itself a reasoning task for
    > Claude.

-   **Migration.** User-defined types need the same schemaVersion
    > discipline and migration runner as built-ins --- arguably more,
    > since their shapes are less predictable.

-   **Testability.** Test the interpreter and primitive vocabulary
    > exhaustively; snapshot-test that specific natural-language
    > requests produce the expected type and skill (recorded request →
    > artifact pairs, analogous to the NLU utterance/intent pairs).

-   **Local-model capacity.** A growing type space argues for the
    > retrieval-augmented routing in 4.6 rather than a fixed classifier.

-   **Cost and consent.** Capability authoring is a cloud call. It is
    > rare per user, but the free/paid boundary (authoring novel types
    > is paid; instantiating built-in templates is free) must be
    > explicit and honest.

-   **Safety.** Because skills can be triggered by user data that Claude
    > reads, the skill and NLU specs must address prompt-injection.
    > Interactive actions follow **act-then-describe** --- an understood
    > request executes immediately and the app describes what it did,
    > with reliable undo as the safety net rather than a pre-action
    > prompt (§15.1; the one retained pre-action confirmation is
    > non-undoable type/skill deletion). The confirmation/clarification
    > UX is owned by the functional spec (§12).

### 4.9 Resolve Once, Replay Fast

The Skill DSL invites a natural optimization. The first time a request
is handled, it goes through the full stack --- transcription, local NLU,
and possibly a Claude call --- to produce a resolved plan: an ordered,
parameter-bound list of primitive actions. That resolution is the
expensive part, and for a given kind of request it produces the same
plan every time. So it need only be done once: resolve the request
through the full stack the first time, cache the resolved plan against a
key that identifies the kind of request, and thereafter map matching
requests straight to the cached plan and execute it in cheap
deterministic code. The mapping onto our design is direct:

-   **The action vocabulary** = the Skill DSL's primitives (create
    > record, set field, schedule, query, ask, call-Claude): the fixed
    > alphabet every resolved plan is written in.

-   **Slow path (first time)** = utterance → local NLU → possibly Claude
    > → a fully resolved plan.

-   **Fast path (repeat)** = a matching request maps straight to the
    > cached plan and executes in pure deterministic code, with no
    > inference call. Because that path is entirely code, it is also the
    > Code-Over-AI fast path (Principle 2.4) --- there is no cheaper
    > tier to reach for.

This also unifies two mechanisms that would otherwise be separate: the
corrections corpus (Principle 2.1) already caches utterance → intent.
The plan cache generalizes it one layer deeper, to intent → resolved
plan. They are the same idea and should be one mechanism, not two.

Three things must not be applied naively, because language is fuzzy
where these keys are usually exact:

-   **The key cannot be the raw utterance.** "Log my lunch," "just ate,"
    > and "had a sandwich" should all hit the same plan. The cache
    > therefore sits below classification, keyed on the resolved intent
    > plus an entity template --- the cheap local parse still runs every
    > time; only the expensive resolution is skipped.

-   **Never cache generative effects.** Some effects are the
    > non-deterministic reasoning itself --- gift suggestions,
    > briefings, coaching --- whose entire value is freshness. Caching
    > applies only to procedural skills (log a meal, create a task,
    > schedule a reminder), never to the paid reasoning features. Cache
    > the plumbing; always re-run the judgment.

-   **Invalidation is real work.** A cached plan goes stale when a type
    > definition, schemaVersion, or user preference changes. Keying the
    > cache on schemaVersion plus a type-definition hash covers most of
    > it, but it is a design item, not free.

Recommendation: build the resolve/execute split now --- resolve(intent,
context) → Plan, kept separate from execute(Plan) --- because it costs
nothing extra, keeps resolution independently testable, and makes the
flow cache a drop-in addition later. Defer the actual cache and its
invalidation until real usage shows repeated expensive resolutions worth
eliminating. Building the full flow table with invalidation before there
is usage data is premature optimization. In short: adopt the model and
shape the interfaces for it now; build the table when the data says it
earns its keep.

This resolve-once/replay pattern is well established across computing,
which is why it is a safe foundation and not a novelty lifted from one
field. Close analogues:

-   **SQL query planners.** A declarative query is compiled into a
    > physical plan of operators (scan, join, filter); prepared
    > statements cache the compiled plan and re-execute it ---
    > declarative intent → resolved plan → cache, exactly our shape.

-   **CPU instruction sets and µop / trace caches.** Complex work
    > decomposes into a small fixed instruction set, and decoded
    > micro-ops are cached so hot paths skip re-decoding --- the
    > primitive-vocabulary-plus-replay idea in silicon.

-   **eBPF.** Restricted, verified bytecode over a fixed operation set
    > runs safely in the kernel and cannot do arbitrary harm --- a
    > strong precedent for both the DSL and the capability boundary of
    > Section 13.

-   **Networking siblings (OpenFlow, P4).** Match-action pipelines
    > generalize the same decomposition well beyond NDIS/GFT; this is
    > the norm in packet processing, not one vendor's trick.

Defining the "flow" precisely is the key deferred question. The
equivalence class --- the analogue of the 5-tuple --- is the (normalized
intent, target type, slot shape) signature: all utterances that resolve
to the same plan modulo parameter values. The cache key would be that
signature plus the skill id and its schemaVersion / type-definition
hash; the cached value is a plan template with parameter placeholders,
and specific slot values are bound at execution, never part of the key.
This is what the resolved-plan cache would key on if and when it is
built.

## 5. Framework Options

Four paths exist for covering the target platforms from a single
codebase. Principle 2.3 (organic UI) and Principle 2.5 (layering) both
influence this choice.

### 5.1 Flutter

Google's framework uses Dart and its own Impeller rendering engine.
Critically for Plenara's UI goals, Flutter draws every pixel itself ---
it does not delegate to native UI widgets. This gives it unmatched
flexibility for custom, organic visual designs.

-   **UI flexibility:** Flutter's CustomPainter, AnimationController,
    > and the Impeller renderer make fluid animations and organic shapes
    > achievable without fighting the framework. React Native renders to
    > native components, which are harder to reshape. This is a
    > meaningful differentiator for Principle 2.3.

-   **Platform coverage:** iOS, Android, macOS, Windows from one
    > codebase.

-   **Voice bridge:** liquid\_speech bridges Apple SpeechAnalyzer
    > directly. Android SpeechRecognizer and TTS via speech\_to\_text
    > and flutter\_tts plugins.

-   **Weaknesses:** Dart is a niche language; bundle size larger than
    > native; on-device LLM ecosystem slightly behind React Native's
    > ExecuTorch.

### 5.2 React Native

Meta's framework uses TypeScript with React and renders via native UI
components. Strong on-device AI story, but the native-component
rendering model limits deep UI customization.

-   **UI flexibility:** React Native renders to native OS components.
    > Creative layouts require Reanimated + Skia (react-native-skia),
    > which adds a custom rendering layer comparable to Flutter's ---
    > but it is an add-on, not the default.

-   **On-device AI:** react-native-executorch is the strongest
    > cross-platform on-device AI option available today (Llama 3.2,
    > Qwen 3, Whisper on iOS and Android).

-   **Weaknesses:** macOS and Windows desktop support lag Flutter.
    > Custom UI requires additional dependencies.

### 5.3 .NET MAUI

Microsoft's C\# framework. Strong on Windows and Android; macOS lags.
Less suited to the organic UI goal without significant custom rendering
work.

-   **UI flexibility:** MAUI renders to native controls. Custom organic
    > shapes require custom handlers or SkiaSharp --- achievable but not
    > the path of least resistance.

-   **Voice:** Azure Speech SDK is seamless in C\# --- the strongest
    > cross-platform voice story of any framework option.

-   **Weaknesses:** macOS desktop behind Flutter; organic UI requires
    > extra effort; smaller community.

### 5.4 Native (Swift + Kotlin + WinUI 3 / C\#)

Three codebases. SwiftUI for iOS/macOS, Jetpack Compose for Android,
WinUI 3 for Windows. Best platform integration, highest maintenance
cost.

-   **UI flexibility:** SwiftUI + Compose both support fluid animations
    > natively; WinUI 3 is more constrained. Full control on Apple
    > platforms.

-   **Weaknesses:** Three codebases; business logic triplicated or
    > requires a shared layer (Swift Package + Kotlin Multiplatform +
    > C\#).

### 5.5 Framework Comparison

  **Criterion**         **Flutter**   **React Native**   **.NET MAUI**   **Native**
  --------------------- ------------- ------------------ --------------- ------------
  iOS support           ★★★★★         ★★★★★              ★★★★☆           ★★★★★
  Android support       ★★★★★         ★★★★★              ★★★★★           ★★★★★
  macOS desktop         ★★★★☆         ★★★☆☆              ★★★☆☆           ★★★★★
  Windows desktop       ★★★★☆         ★★★☆☆              ★★★★★           ★★★★★
  Custom / organic UI   ★★★★★         ★★★☆☆              ★★☆☆☆           ★★★★☆
  Fluid animations      ★★★★★         ★★★★☆              ★★★☆☆           ★★★★★
  Voice bridge ease     ★★★★☆         ★★★★☆              ★★★★★           ★★★★★
  On-device AI          ★★★☆☆         ★★★★★              ★★★☆☆           ★★★★☆
  Dev velocity          ★★★★★         ★★★★★              ★★★★☆           ★★★☆☆

### 5.6 Recommendation

Flutter is the recommended framework. Its pixel-level rendering engine
is the clearest path to the organic, fluid visual language described in
Principle 2.3 --- this is Flutter's most significant advantage over
React Native for Plenara specifically. It also covers all four target
platforms from one Dart codebase.

The one trade-off is on-device AI: React Native ExecuTorch is ahead of
Flutter's LLM bridging today. This gap is managed by keeping the
Intelligence layer behind a clean interface (Principle 2.5) --- the
on-device model implementation can be swapped as the Flutter ecosystem
catches up.

## 6. Voice Technology

Voice is the primary and uncompromising interaction channel (Principle
2.1). Platform-native STT/TTS is the default choice --- free, offline,
private, and tightly integrated with the OS.

### 6.1 The Adaptive NLU Layer

Raw transcription from the platform STT engine is just text. The NLU
layer sits above it and does the real work of converting free-form
speech into structured intent. This layer has two jobs:

-   **Intent classification and entity extraction:** determine what the
    > user wants (add task, set reminder, ask about a contact, define a
    > new tracker, etc.) and extract the relevant data. With the
    > emergent type system (Section 4), this now includes routing to
    > user-defined types via retrieval (4.6). Handled by the local model
    > (see Section 7).

-   **Learning:** when the user corrects a misunderstood intent, record
    > the original utterance, the wrong mapping, and the correct one in
    > a user-specific corrections file (plenara/nlu/corrections.json).
    > On subsequent requests, this corrections corpus is included as
    > context. Over weeks of use, clarification frequency should fall
    > significantly.

The confidence threshold for asking a clarifying question is tunable.
Early in the app's use with a new user, the threshold should be lower
(ask more often, learn faster). As the corrections file grows, the
threshold rises.

### 6.2 Text Overlay for Quiet Mode

Rather than a separate keyboard-centric mode, quiet mode is an overlay
on the existing voice UI:

-   A text input field slides up from the bottom of the screen when the
    > user taps a microphone-off icon or the app detects via the OS that
    > a mute is active.

-   All spoken output is simultaneously displayed as subtitles in a
    > persistent text area --- always on, whether or not quiet mode is
    > active.

-   The text input path goes through the same NLU pipeline as voice
    > input --- it is not a separate command system.

-   The visual design of the main UI is never altered to accommodate
    > text input. The overlay sits on top.

### 6.3 Speech-to-Text (STT) APIs

iOS 26+ / macOS 26+

-   **SpeechAnalyzer (Apple, iOS 26 / macOS 26)** --- on-device, no
    > network, no cost, long-form audio, automatic language detection,
    > 2× faster than Whisper Large V3 Turbo on Apple Silicon --- trading
    > a little accuracy for that speed (a higher word-error rate than
    > Whisper), which the correct-and-learn NLU loop (Principle 2.1) is
    > designed to absorb over time. Primary recommendation.

-   **SFSpeechRecognizer (iOS 10+)** --- fallback for devices below
    > iOS 26. Supports contextualStrings for Plenara-specific
    > vocabulary. Useful for the corrections-corpus vocabulary the user
    > has established.

-   **Flutter bridge:** liquid\_speech (pub.dev) for SpeechAnalyzer;
    > speech\_to\_text for SFSpeechRecognizer.

Android

-   **Android SpeechRecognizer** --- built-in, uses Google STT by
    > default (requires network). On-device mode available Android 10+.

-   **Offline fallback:** Whisper.cpp via Flutter platform channel ---
    > no Google dependency, works offline.

Windows

-   **WinRT SpeechRecognizer** --- built-in, offline, good for short
    > commands.

-   **Whisper.cpp** --- open-source fallback for longer dictation or
    > offline use.

### 6.4 Text-to-Speech (TTS) APIs

  **Platform**   **API**                    **Quality**                       **Offline?**
  -------------- -------------------------- --------------------------------- --------------
  iOS / macOS    AVSpeechSynthesizer        High (Siri voices via download)   Yes
  Android        Android TextToSpeech API   Good (Google TTS engine)          Yes
  Windows        WinRT SpeechSynthesizer    Good (Neural voices on Win 11+)   Yes

### 6.5 Interaction Model

-   **v1: Push-to-talk** --- simplest, battery-efficient, no always-on
    > audio. Tap to speak, release to process.

-   **v2: Wake word** --- "Hey Plenara" via Porcupine (covers iOS,
    > Android, macOS, Windows). low single-digit CPU overhead. The
    > corrections corpus feeds into a more accurate interpretation even
    > with wake-word.

-   **OS integration:** Siri Shortcuts / Google Assistant App Actions /
    > Cortana deep links as optional supplement --- zero battery cost
    > but limited NLU control.

## 7. AI Architecture

The governing principle is Principle 2.4: code is always preferred over
AI for tasks a deterministic implementation can handle reliably. AI is
not a shortcut --- it is the answer to problems that code cannot solve
well. The emergent type system (Section 4) adds one new AI
responsibility: authoring types and skills, which is rare per user but
reasoning-heavy, and therefore a Claude task.

### 7.1 The Local Model (95% of AI calls)

A small on-device model handles intent classification, entity
extraction, and adaptive NLU. This is the workhorse of the Intelligence
layer.

-   **Model size target:** 1B--3B parameters. Sufficient for NLU
    > classification tasks. Runs on mid-range phones (iPhone 14+,
    > mid-range Android with 6+ GB RAM).

-   **Flutter path:** llama.cpp via a Flutter platform channel (Dart FFI
    > or method channel). The Intelligence layer interface is defined in
    > Dart; the native implementation is swappable.

-   **Benchmark to match:** react-native-executorch (Core ML on iOS,
    > XNNPACK/QNN on Android) is today's strongest cross-platform
    > on-device runner and sets the bar the Flutter bridge is measured
    > against. The Intelligence-layer interface (Principle 2.5) lets
    > that implementation be swapped as Flutter closes the gap (Section
    > 5.6).

-   **Over time:** local model capability will increase faster than
    > cloud model costs will decrease. The 95% local / 5% cloud split is
    > a floor, not a ceiling. As better 3B and 7B models emerge and
    > devices improve, more tasks migrate to local, reducing cloud spend
    > without product changes --- because the Intelligence layer is
    > isolated.

What the local model handles:

-   Intent classification from raw transcription, including
    > retrieval-augmented routing to user-defined types (4.6).

-   Entity extraction: task name, person, date/time, priority, and the
    > fields of user-defined types.

-   Confidence scoring to determine whether to act or ask for
    > clarification.

-   Applying the user's corrections corpus to improve accuracy over
    > time.

### 7.2 Claude API (the 5%)

Claude handles tasks that require reasoning over unstructured or highly
variable inputs --- things where a deterministic code implementation
would be impractical to write and maintain.

Concrete cases where Claude is justified:

-   **Capability authoring.** Defining a new type and skill from a
    > described need (Section 4) --- reasoning over intent, reconciling
    > against existing types, and proposing a schema.

-   **Gift and activity suggestions.** "What should I get Sarah for her
    > birthday?" --- requires reasoning over her likes, dislikes, recent
    > activities, and budget. No deterministic code can do this well.

-   **Daily digest (Batch API).** Once per day: Claude synthesizes
    > tasks, deadlines, and relationship notes into a spoken morning
    > briefing. \~2,000 tokens at Haiku 4.5 batch pricing ≈ \$0.003.

-   **Ambiguous intent fallback.** When the local model's confidence is
    > below threshold AND the clarifying question doesn't resolve it,
    > Claude is the escalation path.

-   **Relationship coaching.** "I haven't talked to Marco in three
    > months --- what should I catch up on?" Requires understanding of
    > shared history and social context.

-   **Weekly priority review.** Claude scans the task list and suggests
    > what to drop, defer, or escalate based on deadlines and stated
    > priorities.

What Claude is not used for: date parsing, reminder scheduling, sorting
tasks, marking complete, filtering lists, calculating deadlines,
checking recurrence rules, or executing an already-authored skill. All
of these are code.

Prompt caching: the user profile, task list summary, relationship graph,
and the type registry should always be in the cached prefix. A 90%
cache-hit rate makes even Sonnet-tier calls affordable.

  **Model**               **Input \$/1M**   **Output \$/1M**   **Best For**
  ----------------------- ----------------- ------------------ ----------------------------------------------------------
  Claude Haiku 4.5        \$1.00            \$5.00             Fast, cheap NLU fallback, task extraction
  Claude Sonnet 4.6 / 5   \$3.00            \$15.00            Reasoning, planning, relationship advice, type authoring
  Batch API (any model)   50% off           50% off            Async: nightly digests, weekly reviews
  Prompt caching (any)    90% off hits      ---                Repeated system prompts, user profile, type registry

### 7.3 The No-AI-for-Code Rule in Practice

A useful test when evaluating a new feature: could a junior engineer
write a reliable, testable implementation of this in a week? If yes, it
is a code feature. Examples:

  **Feature**                                   **Code or AI?**   **Reason**
  --------------------------------------------- ----------------- ---------------------------------------------------------------------
  Parse "remind me tomorrow at 9"               Code              Date/time NLP libraries (e.g. Chrono) handle this deterministically
  Sort tasks by priority + deadline             Code              Straightforward comparison function
  Mark a task complete                          Code              State mutation --- no reasoning needed
  Route an utterance to a type/skill            Local model       Retrieval over the type registry (4.6)
  Execute an authored skill                     Code              Fixed interpreter over a primitive vocabulary (4.4)
  Replay a resolved plan for a repeat request   Code              Flow-table fast path (4.9)
  "What gift would Sarah like?"                 AI (Claude)       Requires reasoning over unstructured personal data
  Generate morning briefing                     AI (Claude)       Synthesis of heterogeneous data into natural language
  Author a new "Meal" type                      AI (Claude)       Reasoning over intent + reconciliation against existing types
  Detect "done with that" = complete task       Local model       Intent classification from free-form input
  Suggest which tasks to drop                   AI (Claude)       Requires judgment about priorities and life context
  Recurrence scheduling                         Code              Rule-based; deterministic; well-understood algorithms

## 8. Data Layer

### 8.1 Strategy: User-Owned Folder with Existing Cloud Sync

Plenara stores its data in a user-chosen folder and recommends the user
point it at a location already managed by their cloud storage client
(iCloud Drive, OneDrive, Google Drive, Dropbox). Sync happens
transparently through infrastructure the user already pays for and
trusts --- Plenara has no sync backend.

Advantages: zero backend cost, user owns their data completely, works
with any cloud provider, files are portable and readable without
Plenara, privacy-friendly.

### 8.2 File Layout: Aggressive Granularity

The on-disk format is individual JSON files. The guiding principle is
that files should be split as granularly as the data model allows, for
three reasons: faster startup (load only what is needed), minimal cloud
sync traffic (a change to one task re-uploads one small file, not a
whole database), and clean conflict isolation (a conflict on one record
does not affect others).

Proposed folder structure (note that types/ and skills/ make the schema
itself data, per Section 4):

Plenara/

**types/** ← one JSON file per type definition, including the built-in
seeds

**skills/** ← one JSON file per authored skill (declarative step
recipes)

**tasks/** ← one file per task (UUID filename)

**contacts/** ← one file per person

**journal/** ← one file per day (YYYY-MM-DD.json)

**meals/** ← records of a user-defined type live in their own folder

**nlu/** ← corrections.json: the user's learned intent mappings

**settings.json**

Each file carries a schemaVersion field (set to 1 from day one) and a
lastModified timestamp. The app never needs to read a file it hasn't
changed --- only files whose lastModified is newer than the last startup
scan are re-parsed on reload. Crucially, tasks, contacts, and journal
are not privileged in code; they are just the built-in seed types,
stored exactly like any type the user later defines.

### 8.3 Why Not SQLite

SQLite is a single binary file. Any write rewrites portions of the file,
causing cloud clients to re-upload the entire database. Concurrent
writes from two synced devices produce unresolvable binary conflicts.
SQLite survives as an in-memory query cache (built from the JSON files
on startup), but it is never the source of truth on disk.

### 8.4 In-Memory Cache

-   **On startup:** scan the Plenara folder, parse JSON files modified
    > since last scan, hydrate an in-memory object store. 10,000 small
    > JSON files parse in well under a second on modern hardware.

-   **On write:** write the JSON file first (source of truth), then
    > update the in-memory cache.

-   **On sync:** a file watcher (FSEvents / inotify /
    > ReadDirectoryChangesW, abstracted by Flutter's file\_watcher
    > package) detects incoming changes from the cloud client and
    > re-reads only the changed files.

### 8.5 Platform Path Access

  **Platform**   **Access mechanism**                      **Notes**
  -------------- ----------------------------------------- --------------------------------------------------------------------------------------------------------------
  macOS          NSOpenPanel / file\_picker plugin         Full filesystem access. Store security-scoped bookmark.
  Windows        Windows folder picker / file\_picker      Full filesystem access. Store path in app settings.
  iOS            UIDocumentPickerViewController (Files)    Sandbox restricts direct access. iCloud Drive, On My iPhone, and third-party providers appear in the picker.
  Android        Storage Access Framework (content URIs)   Persistent URI permission, not a file path. Handled by file\_picker or flutter\_document\_file.

Can the user point Plenara at a third-party cloud provider --- say,
storing an iPhone's data on Google Drive? On the desktops, yes and
cleanly: OneDrive, Google Drive, and Dropbox all mount into the Windows
Explorer and macOS Finder filesystem, so Plenara just sees a normal
folder path. On mobile it is possible but provider-dependent: iOS
surfaces third-party providers through the Files app and document picker
only if that provider ships a File Provider extension, and Android
exposes them through the Storage Access Framework only if the provider
implements a DocumentsProvider. Coverage --- and especially reliable
background sync --- varies by provider; Google Drive in particular has
historically had weak or absent support here. The safe defaults are
therefore the platform-native provider (iCloud Drive on iOS) with
Dropbox/OneDrive as generally-working options, and arbitrary providers
treated as best-effort. The continuous file-watching the sync model
relies on (8.4) is the fragile part on mobile and must be validated per
provider --- see the Phase 0 spikes (Section 11) and the open questions
(Section 15).

### 8.6 Conflict Handling

-   Cloud clients create conflict copies with recognizable suffixes
    > (e.g. "a1b2c3 (conflicted copy).json"). Plenara detects these on
    > startup and surfaces a lightweight resolver.

-   **For tasks:** last-modified-timestamp wins automatically.

-   **For contacts:** non-conflicting fields are merged (e.g. both
    > versions added a tag --- keep both). Conflicting fields surface a
    > picker.

-   **For type and skill files:** treat as append-mostly and prefer the
    > newer schemaVersion; a conflict on a type definition is
    > high-stakes and should surface to the user rather than
    > auto-resolve.

### 8.7 Encryption at Rest

Records hold the user's inner life --- journal entries, notes about the
people they love --- and the product only works if they feel safe enough
to be candid. That argues for encrypting user content at rest so a stray
sync copy or a lost device does not expose plain-text thoughts, and it
may itself encourage the openness that makes Plenara valuable. It also
collides with an advantage claimed in 8.1: that the files are portable
and readable without Plenara. Both cannot be fully true, so the
resolution is scoped encryption. Content-bearing records (journal, and
any type flagged sensitive) are encrypted; structural, non-personal
files (type definitions, skills, settings) stay plain-text and portable.
Keys live in the platform secure store --- Keychain / Secure Enclave on
Apple, DPAPI / TPM on Windows, Keystore on Android --- never in the
synced folder, and encryption is transparent to the app so the local
model still reads decrypted content in memory. The hard part is key
backup and recovery: losing the key means losing the data, so key escrow
(for example to iCloud Keychain) and the portability trade-off are
decisions for the Data & Sync and Security specs. Recommended default:
encrypt journal and sensitive types; keep everything else portable.

## 9. Architecture & Layering

Principle 2.5 mandates strict layer separation. This section defines the
layer boundaries concretely so they can be enforced from the first
commit. The emergent type system (Section 4) adds two components --- a
Schema Registry and a Skill Interpreter --- that must sit in
well-defined layers rather than leaking across them.

### 9.1 Layer Definitions

  **Layer**        **Responsibility**                                                                        **Knows about**                                      **Does NOT know about**
  ---------------- ----------------------------------------------------------------------------------------- ---------------------------------------------------- -----------------------------------------------
  UI               Render state; emit user events; map types to view archetypes                              View models / state                                  Storage, AI, business rules
  Business Logic   Validate/transform/apply rules; run the Skill Interpreter over the primitive vocabulary   Storage + Intelligence interfaces; Schema Registry   How data is stored or how AI works internally
  Storage          Read/write JSON (type-agnostic); in-memory cache; watch files                             File system / content URIs; meta-schema              Business rules, UI, AI
  Intelligence     NLU, routing, Claude calls, type/skill authoring, corrections corpus                      BL contracts (intent types, entity + type schemas)   Storage internals, UI
  Voice Pipeline   STT, TTS, push-to-talk / wake-word                                                        Intelligence layer                                   Storage, UI, business logic

### 9.2 Interface Contracts

Each layer boundary is defined by an interface (abstract class in Dart),
not an implementation. This makes layers independently testable and
swappable:

-   **StorageRepository** --- defines read(id), write(record),
    > watch(folder). Type-agnostic: it persists records of any type.
    > Today backed by local JSON files; could be swapped for a cloud DB
    > without touching business logic.

-   **SchemaRegistry** --- defines register(typeDef), lookup(typeName),
    > and similarity search over types. Owns the built-in seed types and
    > any user-defined ones. New in this revision.

-   **SkillInterpreter** --- defines run(skill, context) over the fixed
    > primitive-operation vocabulary. Deterministic and fully testable;
    > never executes model-authored code. New in this revision.

-   **IntentClassifier** --- defines classify(utterance) → Intent, now
    > including retrieval-augmented routing to registered types. Today
    > backed by llama.cpp; swappable.

-   **ClaudeClient** --- defines ask(prompt, cachedContext) → Response,
    > and authorType/authorSkill helpers. BYOK today; could add managed
    > keys later.

-   **SpeechEngine** --- defines startListening(), stopListening(),
    > speak(text). Backed by platform-native APIs; swappable per
    > platform.

### 9.3 Testing Strategy

Strict layering enables a clean testing pyramid:

-   Business logic and the Skill Interpreter are unit-tested against
    > mock StorageRepository and mock IntentClassifier --- no files, no
    > models, no API calls needed.

-   Storage layer is integration-tested against a real temp directory,
    > exercising arbitrary user-defined types to prove type-agnosticism.

-   Intelligence layer is tested with recorded utterance/intent pairs
    > and recorded request/type-definition pairs --- deterministic even
    > though the underlying model is not.

-   UI layer uses widget tests against mock state, including that each
    > view archetype renders a representative type.

End-to-end tests are narrow and high-value: they cover the full voice →
intent → action → storage round-trip, plus one capability-authoring
round-trip (describe → type created → log against it), on a small number
of critical paths.

Coverage is measured, not assumed. The project adopts standard
code-coverage instrumentation (Flutter/Dart's flutter test \--coverage
producing lcov) from the first commit, with a CI gate that fails the
build below an agreed threshold and reports per-layer coverage so
untested production code is visible rather than discovered late.
Generated code and platform glue are excluded from the denominator; the
interpreter, business logic, and storage layers are held to the highest
bar.

## 10. Feature Domains as Type-System Instances

With Section 4 in place, the feature domains below are no longer special
subsystems to be built one by one; they are instances of the general
type system. Each is a set of seed types, some default skills, and a
view archetype. They are described here to show the type system is
expressive enough to carry the product vision.

### 10.1 Relationship Graph

-   **People:** name, relationship type, preferences (likes, dislikes,
    > hobbies) --- a Contact entity with typed attributes.

-   **Interaction log:** last contacted date, medium, notes --- Record
    > events related to the contact.

-   **Gift and activity ideas:** per person, tagged by occasion and
    > budget --- a GiftIdea type related to a Contact.

-   **Claude (justified):** gift suggestions, conversation starters,
    > check-in nudges based on relationship notes and recent activities.

### 10.2 Activity Planning

-   Events linked to people: birthday reminders, dinner plans, trips ---
    > an Event entity with relations to Contacts.

-   Preference-aware suggestions and full event prep via Claude.

-   Budget tracking per event or relationship as typed attributes.

### 10.3 Life Journaling

-   **Daily voice memo:** 60 seconds auto-transcribed on-device. Stored
    > as journal/YYYY-MM-DD.json.

-   **Local semantic search:** using on-device embeddings.

-   **Claude (justified):** monthly reflection --- synthesis across
    > entries that code cannot meaningfully produce.

### 10.4 Ambient Intelligence (Longer Term)

-   Wake-word gated note capture auto-filed to the correct type.

-   Calendar integration for deadline-based time blocking.

-   Proactive nudges based on relationship, task, and tracker data ---
    > the anticipation quality of 3.1.

## 11. Bring-Up Strategy & Roadmap

The question is not "versioned features" versus "architecture first" ---
it is how to prove the riskiest bets before writing a lot of code that
might have to be thrown away. The earlier draft jumped from a single
task flow to all ten free-tier tasks in one version, which hides exactly
the risk we most want to expose early: whether the meta-schema and Skill
DSL are genuinely sound, or whether they hit a wall two capabilities in.
So the plan is front-loaded with cheap, throwaway experiments that
de-risk the core bets, then a granular capability ladder where each rung
exercises a new architectural muscle, and only then a hardening push
toward a shareable candidate. Expect to experiment and reassess between
rungs rather than march straight to a release.

### 11.1 Phase 0 --- De-Risking Spikes (throwaway, prove the bets)

Before committing to the real codebase, build small, disposable spikes
for the highest-risk, highest-complexity pieces. They run on whatever
platform iterates fastest (a desktop), independent of release priority,
and their code is expected to be discarded.

-   **DSL & meta-schema viability.** Hand-encode three very different
    > marquee tasks (a task, a nutrition tracker, a relationship note)
    > as declarative skills over a draft primitive vocabulary and run
    > them through a minimal interpreter. The bet is validated only if
    > all three express cleanly without special-casing. This is the
    > single most important spike --- the dead-end we most want to find
    > now, not after reams of code.

-   **Capability authoring.** Prompt Claude to author a new type + skill
    > from a described need and confirm it produces valid, interpretable
    > artifacts and a usable safety assessment (13.2).

-   **Local-model routing.** Measure whether a 1--3B model can route
    > utterances to the right user-defined type via retrieval (4.6) at
    > acceptable accuracy, and how fast the corrections corpus improves
    > it.

-   **Storage + sync reliability.** Exercise the per-record JSON +
    > file-watcher model against real cloud providers on iOS and Android
    > --- the fragile case flagged in 8.5 --- before betting the data
    > layer on it.

Gate: proceed to v0 only once these four spikes are green, or the design
is adjusted until they are. This is the reassessment point.

### 11.2 v0 --- Walking Skeleton (prove the stack end to end)

-   **Scope:** one narrow path on one platform --- create and complete a
    > task by voice → typed JSON storage → in-memory cache → local
    > reminder → spoken confirmation --- built on the real layer
    > interfaces (StorageRepository, IntentClassifier, SchemaRegistry,
    > SkillInterpreter, SpeechEngine).

-   **Goal:** prove the layer contracts hold and the seams fit. UI can
    > be ugly; meta-schema present with the Task seed type only.

### 11.3 v1 --- The Capability Ladder (local-only, one muscle at a time)

Rather than "all ten tasks at once," add capabilities in rungs, each
chosen to stress a new part of the architecture. Deliberately, the
second rung is a user-defined type, not another built-in --- because
that is what validates the emergent-type bet in real use as early as
possible.

-   **v1.1 ---** natural, relative, and recurring reminders (stresses
    > the deterministic date/recurrence code and the fast path).

-   **v1.2 ---** one user-defined tracker end to end from a built-in
    > template: define, log, view (stresses meta-schema + interpreter +
    > a first view archetype --- the core bet).

-   **v1.3 ---** people facts and "when did I last..." recall (stresses
    > relations and queries).

-   **v1.4 ---** voice journal + on-device semantic search (stresses
    > capture, embeddings, and encryption at rest, 8.7).

-   **v1.5 ---** the remaining free-tier tasks, the corrections-corpus
    > learning loop, and the quiet-mode overlay; begin the aesthetic
    > pass and further view archetypes.

Still local-only, no Claude. Dogfooding begins the moment v1.2 is
usable. This is the honest, uncrippled free tier.

### 11.4 v2 --- Paid Layer (the sci-fi assistant)

-   **Scope:** Claude integration (BYOK): morning briefing, gift
    > suggestions, event prep, relationship coaching, weekly review, and
    > --- proven in Phase 0 --- the capability-authoring flow. Batch API
    > and prompt caching for cost control; the safety-assessment audit
    > trail (13.2) is live.

-   **Goal:** deliver the reasoning that justifies a paid tier and prove
    > the emergent type system under real authoring load.

### 11.5 v3 --- Ambient, Anticipatory & Broadened

-   **Scope:** wake word; proactive unprompted nudges; calendar
    > integration; cross-tracker insight; a mature view-archetype set
    > and the full organic UI; and platform breadth per priority
    > (Windows, then Android, then macOS).

-   **Goal:** the anticipation quality of 3.1, with platform coverage
    > completed once the core is proven.

Release-candidate hardening --- coverage thresholds (9.3), the
diagnostics and feedback loop (Section 14), migration runners, and
conflict/sync validation --- runs continuously from v1 and gates the
first shared build. Productization order follows the P1--P4 priority;
Phase 0 and v0 may use a desktop purely for iteration speed.

## 12. Recommended Deep-Dive Specifications

This document is the vision-and-technology baseline. Before any code is
written, the following specs should be produced and reviewed, roughly in
this order. Each should be a session of its own, and each should end
with an explicit decision record so consensus is captured (matching
Luis's intent to think from many angles before implementing).

-   **1. Meta-Schema & Type System spec (highest priority).** The
    > primitives, the type-definition file format, the registry,
    > semantic reconciliation of duplicate types, migration, and
    > presentation hints. Everything else depends on this.

-   **2. Skill DSL spec.** The primitive-operation vocabulary,
    > interpreter semantics, the authoring flow, the resolve/execute
    > split and deferred flow-table cache (4.9), confirmation and safety
    > (prompt-injection), and the explicit no-executable-code platform
    > constraint.

-   **3. NLU / Intent spec.** The intent taxonomy including
    > capability-definition meta-intents, retrieval-augmented routing
    > over a growing type space, confidence-threshold policy and decay,
    > the corrections-corpus format (unified with the resolved-plan
    > cache as one flow-table mechanism, 4.9), and the recorded
    > test-pair methodology.

-   **4. Architecture spec.** The layer contracts formalized (including
    > SchemaRegistry and SkillInterpreter), the async/threading model,
    > error handling, and offline behavior.

-   **5. Functional spec.** For each free and paid marquee task, the
    > exact interaction flow, edge cases, and the
    > confirmation/clarification UX.

-   **6. Data & Sync spec.** Extends Section 8 for user-defined types:
    > conflict handling on type/skill files, the migration runner, and
    > the startup-scan performance budget.

-   **7. UI & Design-Language spec.** The view-archetype set, how types
    > map to archetypes, the motion language, the quiet overlay, and
    > subtitle behavior --- the concrete realization of Principle 2.3.

-   **8. AI Cost & Privacy spec.** Token budgets per feature, the
    > caching strategy, exactly what leaves the device and with what
    > consent, and the BYOK flow.

-   **9. Test spec.** Interpreter and primitive coverage, recorded NLU
    > and authoring pairs, layer mocks, the E2E critical paths,
    > code-coverage instrumentation with CI thresholds (9.3), and the
    > dogfooding plan.

-   **10. Security & Privacy threat model.** Local data at rest,
    > encryption of sensitive types (8.7), what Claude sees,
    > prompt-injection via user data, and App Store compliance of the
    > skill system. Builds on the misuse boundaries defined in
    > Section 13.

-   **11. Feedback & Diagnostics spec.** The privacy-preserving
    > functional-gap report and the diagnostic-log format (Section 14):
    > exactly what is collected, the human-readable manifest shown
    > before anything is sent, the redaction guarantees (no PII, no user
    > content), and the opt-in submission flow.

## 13. Safety, Guardrails & Misuse Boundaries

Plenara must avoid enabling harm --- planning harm to others or oneself,
or plans that break the law --- where "bad" is often a
know-it-when-you-see-it judgment that a frontier model makes better than
any hand-written rule. The instinct to lean on model guardrails is
correct, but only for the layers a model is actually in. A large share
of Plenara runs with no model in the loop --- the deterministic fast
path, the local NLU, and the entirely offline free tier --- so a cloud
model's guardrails cannot be the whole answer. Safety must therefore be
layered.

### 13.1 The Capability Boundary Is the Primary Control (all tiers)

The Skill DSL's primitive vocabulary is the ceiling on what the app can
do. Those primitives --- create a record, set a field, schedule a
reminder, query data --- are mundane by construction; none can effect
harm in the world. A fixed, reviewed action vocabulary simply cannot
express a genuinely dangerous action, unlike a general agent with shell,
web, or payment access. This is the load-bearing control precisely
because it holds on the offline, local, and pure-code paths that model
guardrails never see. Keeping the primitive set provably benign is a
safety decision, not just a design one. Because "benign" is easier to
assert than to prove, the review gate should be adversarial: once the
vocabulary is drafted, red-team it with a model (for example Fable)
tasked with finding the most harmful compositions of primitives, and
lock the set only once that search comes up empty.

### 13.2 Model Guardrails for Generative and Authoring Surfaces (cloud tier)

For everything Claude generates --- briefings, suggestions, coaching,
reflections --- and for capability authoring, inherit the frontier
model's built-in alignment rather than building a custom moderation
layer. If Claude declines to author a harmful skill or to produce a
harmful plan, that is the guardrail, and it will be better than anything
hand-rolled. This is exactly the layer where "good enough for Claude is
good enough for us" holds. Because the model is BYOK, the provider's
usage policy is enforced on the key directly, so this alignment is
partly automatic and even contractual. Capability authoring is already a
Claude call, so routing it through Claude with an explicit instruction
to refuse harmful capabilities is nearly free.

Two refinements make this auditable and closed. First, whenever Claude
authors or reviews a type or skill, it also produces a short safety
assessment --- why the capability is acceptable --- stored in a separate
audit record (for example under an audit/ folder), deliberately not
inside the skill definition itself so it is never reloaded as runtime
context. If someone later finds a way to elicit harmful behavior, these
assessments are the diagnostic trail for improving the gate. Second,
this resolves the offline-authoring gap: the local model may draft a
type or skill offline, but a draft is inert --- it is never integrated
into the app's behavior until the Claude backend reviews it and emits
that stored assessment. Authoring can be local; activation cannot.

### 13.3 Private Storage Is Not Policed

Plenara does not scan, classify, or moderate the user's own notes,
journal, or records. This is a deliberate, principled line: the folder
is the user's, local and private (the storage principle), and policing
it would both betray that promise and be technically futile offline. The
boundary is clear --- Plenara will never generate or actively assist a
harmful plan, and its actions cannot themselves do harm, but it does not
surveil what a user privately writes, any more than a notes app or
spreadsheet does.

### 13.4 Wellbeing, Handled With Care

For self-harm or acute distress, refusal is the wrong frame for
someone's private journal. In model-mediated surfaces --- briefing,
coaching, reflection --- where Claude is already reasoning over content,
Claude's own wellbeing behavior applies and can gently surface support.
Do not build keyword-based crisis detection over the journal: it is
inaccurate, invasive, and off-brand. Distress handling belongs in the
model layer, not in storage scanning.

### 13.5 An Honest Limitation

No local-first, private, offline tool can be made incapable of misuse as
a filing cabinet by a determined actor --- the same is true of a notes
app, a spreadsheet, or a paper notebook. The design goal is bounded and
defensible: Plenara never actively assists or generates harmful content,
its action surface cannot itself do harm, and private storage is
respected. This matches how comparable tools, and the law, treat the
distinction between a tool and its misuse.

### 13.6 App Store Compliance of the Skill System

Because the skill system is the most novel part of the app, its App
Store standing was checked directly. Apple's guideline 2.5.2 requires
apps to be self-contained and prohibits downloading, installing, or
executing code that introduces or changes features; its 2026 enforcement
has escalated from blocking updates to pulling apps outright --- Apple
removed the "Anything" app in March 2026 and blocked Replit and Vibecode
updates, all under 2.5.2. The common thread is apps that fetch
executable code or dynamic behavior from a server after review:
vibe-coding platforms, dynamic UI engines, and JavaScript-to-native
bridges.

The declarative Skill DSL is designed to sit clearly on the compliant
side of that line, and it is worth stating why. The interpreter and its
entire capability set ship inside the reviewed binary; skills are
declarative data, not code, and can only recombine primitives that
already exist and were already reviewed; no new native functionality is
introduced; and nothing executable is downloaded from a server ---
skills are authored locally by the user's own model calls and stored in
the user's folder. This is the same category as an app that reads a JSON
configuration, a rules file, or a game level. The risk to actively avoid
is drifting into a "dynamic behavior engine" framing; the mitigations
are to keep the primitive vocabulary fixed and reviewed and to never
fetch skills from a remote Plenara service. This should still be
confirmed with a pre-submission review, and if useful a
developer-relations inquiry, before the system is built out (Section
15).

## 14. Feedback & Diagnostics (Privacy-Preserving)

Plenara should improve from real-world use without ever compromising the
privacy that makes it trustworthy. Two channels do this, and both rest
on the same non-negotiable rule: nothing leaves the device without the
user seeing, in plain English, exactly what is being sent --- and
neither channel ever contains personal information or the content of the
user's data.

### 14.1 Functional-Gap Feedback

When Plenara hits a real gap --- a request it could not map to any
capability, a skill that failed to resolve, an activity the architecture
or DSL did not anticipate --- it records the shape of that failure: the
class of intent, which layer fell short, and why, but never the words
the user said or the data involved. The user can then submit these gaps.
Submission is maximally transparent: an email (or equivalent) is
composed and shown for review, with the payload written out in readable
English so there is zero ambiguity about what is shared. It reads like
"could not route a request in the 'nutrition' area to any known type; no
matching skill; local-model confidence 0.31" --- a functional gap, not a
diary entry. This is what tells us where to extend the primitive
vocabulary, the templates, or the routing.

### 14.2 Diagnostic Logging

For the rare case where something goes badly wrong, Plenara maintains a
robust diagnostic log --- code-level tracing detailed enough to
post-debug a logic error: call paths, layer transitions, interpreter
steps, error states, timings. It is engineered from the start to hold no
PII and no user content --- identifiers are opaque and values are
redacted to their type and shape ("string\[12\]", "date"), never their
contents. The user can attach and submit this log when reporting a
serious failure, and again it is shown in readable form, with the
redaction guarantees stated, before anything is sent.

### 14.3 Ground Rules

-   **Explicit, reviewable consent.** Nothing is transmitted silently;
    > the user sees the exact payload and chooses to send.

-   **Human-readable manifest.** Both channels present what is shared in
    > plain English, not opaque blobs --- so there is no fear it might
    > be leaking private thoughts.

-   **No PII, no user content, ever.** By construction, both payloads
    > carry only functional and code-level facts. This is a design
    > constraint to be tested (Section 12, item 11), not merely a
    > promise.

-   **Opt-in.** Feedback and diagnostics are off until the user chooses
    > to send, consistent with the local-first, private posture and the
    > safety boundaries of Section 13.

## 15. Decisions & Open Questions

Consensus reached in review is recorded here so later specs can rely on
it, followed by what remains genuinely open.

### 15.1 Decisions Confirmed

-   **Framework:** Flutter.

-   **Schema model:** meta-schema kernel + emergent, user-defined types
    > (Section 4, Option C) --- and with it Principles 2.6 (capabilities
    > are data) and 2.7 (AI authors, code executes).

-   **Flow-table caching:** build the resolve/execute split now; defer
    > the resolved-plan cache. Its key, when built, is the (normalized
    > intent, type, slot-shape) signature plus skill id and
    > schemaVersion (4.9).

-   **Free/paid line:** built-in template instantiation and all
    > deterministic capture/recall are free; novel type authoring and
    > Claude reasoning are paid.

-   **Local routing:** retrieval-augmented routing over a fixed
    > classifier, to avoid information bloat. Skills and context may
    > carry two tuned representations --- a compact one for the local
    > model and a richer one for the backend models (4.6).

-   **Minimum OS:** target the latest major OS versions to use
    > state-of-the-art APIs (e.g. SpeechAnalyzer), accepting reduced
    > reach on older devices.

-   **Platform priority:** P1 iPhone, P2 Windows desktop, P3 Android, P4
    > macOS desktop.

-   **Interaction model:** push-to-talk first; wake word is later
    > polish.

-   **Confirmation model:** **act-then-describe** --- an understood
    > request executes immediately and the app describes what it did in
    > one past-tense line, with reliable undo as the safety net; no
    > pre-action "are you sure?" on the interactive path. The sole
    > exception is non-undoable type/skill deletion, which keeps a
    > pre-action confirmation. Locked by Luis (July 2026); owned by the
    > functional spec (§12) and propagated across the skill-DSL, NLU,
    > architecture, and functional specs. Reverses the earlier "confirm
    > before any non-trivial action" note in §4.8.

-   **API keys / cloud-access model:** BYOK --- the user supplies their
    > own Anthropic API key; no billing backend, consistent with the
    > local-first, privacy, and no-profit posture. The free tier runs
    > fully on-device and needs no key (the wall-free on-ramp); the paid
    > tier is BYOK and positioned for advanced users. This is a deliberate
    > consequence of having no backend, not an oversight --- see the
    > adoption-wall risk in §15.2. An app-funded/managed-key tier is
    > deferrable without rework (the ClaudeClient seam is
    > key-source-agnostic) but requires a backend and a changed
    > privacy/commercial posture, so it is out of scope for v1.

-   **Migration:** a versioned migration runner for built-in and
    > user-defined types, defined before production data exists.

-   **Offline authoring:** the local model may draft types/skills, but
    > activation requires Claude backend review plus a stored safety
    > assessment (13.2).

### 15.2 Still Open

-   **Cloud-access adoption wall (store distribution):** BYOK forces every
    > paid-tier user to create an Anthropic API account and pre-purchase
    > credits before any Claude feature works, and they will intuitively
    > (wrongly) expect a Claude Max/Pro subscription to cover it --- a real
    > friction wall for wide adoption once the app ships in stores. This is
    > **not** Anthropic-specific: no LLM provider lets a third-party app
    > bill inference against an end user's consumer subscription; the only
    > zero-friction alternative for any AI app is an app-funded key behind a
    > backend, monetized via in-app purchase, which contradicts Plenara's
    > no-backend / local-first / journal-never-leaves-device foundations.
    > **v1 stance:** accept the wall, keep the free tier fully on-device as
    > the wall-free on-ramp, position paid as advanced-user BYOK.
    > **Mitigations that lower the wall without a backend:** (a) push more
    > capability onto on-device models (llama.cpp now; platform-native Apple
    > Foundation Models / Gemini Nano next) so the paywall is hit rarely,
    > not on every cloud-ish feature; (b) keep minimizing cloud dependence
    > per "code over AI." **Onboarding requirement:** the paid-upgrade flow
    > must state plainly that a Claude subscription will not work and an API
    > key is required, *before* sending the user to the console. Surfaced
    > July 2026 when Luis's own testing hit the subscription-vs-API
    > confusion firsthand.

-   **Flow definition & key:** validate the (intent, type, slot-shape)
    > signature as the right equivalence class before building any cache
    > (4.9).

-   **View archetypes:** the initial set is deferred to the
    > UI/functional spec (Section 12), designed against the concrete
    > marquee tasks.

-   **Confidence threshold:** initial value and decay as the corrections
    > corpus grows --- plan in the functional spec, calibrate in early
    > experimentation.

-   **Third-party cloud sync reliability:** validate per-provider
    > background sync on iOS and Android before relying on non-native
    > providers (8.5, Phase 0 spike).

-   **Encryption at rest:** confirm scoped encryption of sensitive types
    > and the key backup/recovery approach versus the "readable without
    > Plenara" trade-off (8.7).

-   **Capability-boundary review gate:** red-team the primitive
    > vocabulary with a model (e.g. Fable) to surface harmful
    > compositions before locking it (13.1).

-   **App Store compliance:** confirm the declarative-interpreter
    > approach with a pre-submission review before building it out
    > (13.6). Assigned to Claud