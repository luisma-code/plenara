# Spec 07 — UI & Design-Language

**Status:** Active v0.5 — audited against the wired Flutter UI 2026-09-07. Owns the
implemented visual language and the explicitly marked generic-rendering destinations; Spec 17 owns
Relationships/Todos/Habits composition, secondary Plan/Library/History tools, first-party domain
workspaces, and adaptive Plena hierarchy. Voice and direct manipulation are peers.
**Depends on:** Research doc v0.10 (§2.1–2.3, §4.5, §6.2, §12.7, §15.1); Spec 01 — Meta-Schema & Type System (§3 value types, §4.1–4.3 presentation object, §4.5 owned/append, §12.3 seed types); Spec 02 — Skill DSL (§7.1 `confirmationText` via `format`); Spec 03 — NLU / Intent (§2.4, §2.7, §4.3 thresholds, §6.3); Spec 04 — Architecture (§3.6 TurnEvents, §3.6a ConfirmationView, §3.9 Review Feed, §3.10 GenerativeService, §3.11 undo window, §3.12 AttentionSurface, §4.7 detached operations); Spec 05 — Functional (§2 notation, §3 interaction contract, §13 subtitle overlay, §14 authoring preview, §24 deletion).
**Blocks:** no shipped surface. Unimplemented archetypes and visual destinations below require their
own code and widget-test evidence before becoming current contract.
**Builds on:** the current Flutter shell in `app/lib/main.dart`, its first-party workspaces,
`VoiceTurnController`, `ConversationLedger`, `DataView`, and the Session mutation facades.
**Presence sync:** the historical orb is subsumed by **Plena** (Spec 15). Tap-anywhere is restricted
to non-interactive presence space; populated planner surfaces expose an explicit voice control.
**Product-model sync (2026-09-06 — Spec 17 v0.9):** Spec 17 supersedes the overlay-only/no-touch rule, the four-surface/presence-primary steady state, and the interim Today/Plan/Library primary navigation. This document remains authoritative for visual language, value treatments, and generic archetypes; Spec 17 owns Relationships/Todos/Habits, secondary Plan/Library/History tools, multimodal interaction, planner projections, and Plena's adaptive scale.

---

## 0. Purpose & Scope

Plenara's data model is user-defined: any type can appear at any time, authored by Claude, never anticipated by the app's designers (research §4). The obvious failure mode — the one Principle 2.3 exists to forbid — is that user-defined types degrade into auto-generated CRUD forms, "a grid of rectangular buttons." The resolution named in research §4.5 is a small library of curated **view archetypes** that any type maps into. This spec designs that library and everything around it.

This document covers:

1. **The surface anatomy** — the small set of top-level surfaces the whole app is composed of, and how the existing v0 chat UI grows into them (§2).
2. **The view-archetype set** — the finite, closed set of presentation archetypes; their anatomy, their required presentation hints, and which seed types map to which (§3).
3. **Type→archetype mapping** — how an emergent or otherwise unrecognized type lands in an archetype from its structure and presentation hints alone, deterministically, with no per-type UI code; the eligibility validator and the fallback inference function (§4). First-party domain workspaces may compose several built-in types under Spec 17.
4. **Value-type render treatments** — one canonical treatment for each of the twelve value types of Spec 01 §3, plus composites, locked (encrypted-but-keyless) values, and dangling references (§5).
5. **The turn UX** — the visual realization of act-then-describe, clarification, the undo affordance, the one pre-action confirmation, residual offers, and detached/generative results (§6).
6. **The quiet overlay and subtitle behavior** — the text-parity surface of research §2.2/§6.2 and Spec 05 §13 (§7).
7. **The motion language** — tokens, rules, and the listening presence (§8).
8. **Typography, shape, and color** — including the constraints this spec places on the free-form `presentation.color`/`icon` fields of Spec 01 §4.1 (§9).

It does **not** cover: the type-file format that carries the hints (Spec 01 §4), how `confirmationText` is composed (Spec 02 §7.1), when the app asks vs. acts (Spec 05 §3 owns the policy; this spec owns only its rendering), STT/TTS engine selection (Spec 04 §3.8), or notification plumbing (Spec 04 §3.9). Where this spec adds fields or invariants that belong in the type file, they are listed explicitly in §11 as cross-spec additions for Spec 01's planned §9, so the schema spec remains the single home of the file format.

---

## 1. Governing Principles

Restated from the research doc and upstream specs, with their UI-specific consequences. They are the frame, not up for re-debate.

**P1 — Voice is global and first-class (Spec 17 P17.1).** Every core outcome remains reachable by voice. Planner surfaces may also use direct manipulation and spatial comparison suited to touch, pointer, and keyboard; all modalities enter the same typed mutation path. The retired rule treated complex touch interaction as evidence that the view was wrong. Spec 17 replaces it with multimodal parity.

**P2 — Text and captions have full parity (Spec 17 P17.1/P17.3).** Captions remain simultaneous and text input remains globally available. A keyboard may reflow a responsive planner surface when required for usability; state, commands, durable results, and undo semantics stay identical across modalities.

**P3 — Beautiful, organic, quiet (research §2.3).** Fluid animation, organic shape, generous whitespace, typography-led hierarchy, curated context-sensitive display — "more like a well-designed magazine than a productivity dashboard." Concretely enforced in this spec as: no full CRUD list views (§3), the one-mover motion rule (§8.2), the shape language (§9.2), and the ban on raw forms (§4.4). The organic visual layer is an explicit v1+ goal; §10 stages it so v1 ships functional-and-clean on the same skeleton.

**P4 — Generic coverage without forbidding first-party workspaces (amended by Spec 17 D17.4/D17.8).** The shipped generic renderer deterministically chooses one of five views — checklist,
person card, tracker, timeline, or collection — so a hydrated type remains browseable without new
widget code. The fuller vocabulary in §3 is a destination, not a claim of shipped renderers.
Built-in product domains may have purpose-built UI but must mutate through Session/business facades
and preserve Library as the generic fallback. Claude cannot invent executable UI.

**P5 — The UI renders state and calls business facades (research §2.5, Spec 04 §2.2).** Current
voice/text state comes from `VoiceTurnController`; persistent conversation rows come from
`ConversationLedger`; planner projections and precise edits come through Session facades. There is
no concrete sealed `TurnEvent` UI stream today. Widgets must not call storage, routing, or models
directly; a future sealed event vocabulary may formalize the already-centralized boundary.

**P6 — Act-then-describe is the tempo (research §15.1, Spec 05 §3.1).** Undoable direct actions
act and then describe. Manual edits/deletes expose a five-second targeted Undo snackbar; a newer
completed action replaces older transient feedback instead of waiting behind it. Writes remain
recoverable through durable History, and spoken undo uses the same execution journal. Non-undoable
type/skill deletion confirms first. Sheets and dialogs are also used for precise editing, import,
settings, and other bounded workflows, so deletion is not the app's sole modal.

**P7 — No silent failure has a UI corollary: every failure has an address (research §2.8).** Degraded types, locked records, failed migrations, inert automations, stale drafts — all land in the AttentionSurface (Spec 04 §3.12) and are rendered by this spec's repair patterns (§6.7), never dropped, never rendered as a blank.

**P8 — Quiet by default.** Plenara is ambient. The steady state of the screen is *restful*: no badges competing for attention, no unread counts, no red. Attention items surface in one place (§6.7), nudges arrive on the app's schedule (Spec 05 §23), and motion happens only when meaning changes (§8.2).

---

## 2. Surface Anatomy

**Superseded as top-level information architecture by Spec 17 §2.** The current primary surfaces are Relationships, Todos, and Habits, with secondary Plan/Library/History tools and global Plena. The historical Stage/Stream/Collections/Operation-Center anatomy below continues to inform component and transition design where Spec 17 reuses it.

### 2.1 The Stage (home)

The default, ambient surface. Anatomy, top to bottom:

- **The presence** — Plena is full-screen in empty/rest/deep-conversation states, a compact collaborator beside Todos/Plan content, and an ember on Relationships/Habits/detail surfaces (Spec 17 §3). Tap-anywhere speaks only where it cannot collide with interactive objects; populated surfaces expose an explicit accessible voice target.
- **The subtitle region** — the two-slot caption area of §7.3. Always present, mostly empty.
- **The ambient field** — a curated, context-sensitive selection of at most three cards: the most imminent item (next reminder/task due), the most alive tracker (today's streak state), and — only when non-empty — the AttentionSurface summary chip ("2 things need a look"). Which cards appear is a Business Logic projection, not user configuration, and *empty is a valid and common state*: an empty Stage with a resting orb is the design working, not a bug.
- **The threshold to the Stream** — the most recent turn's `Done` line lingers at the bottom of the Stage (with its undo chip, §6.2) and can be pulled up to reveal the full Conversation Stream.

### 2.2 The Conversation Stream

The durable history of turns and actions, now owned as the conversation/action ledger by Spec 17 §2.4. The 2026-07-11 ephemeral-home experiment is retired: every final utterance, reply, execution link, failure, and targeted undo remains findable after relaunch. What remains from this visual design:

- Turns are not symmetric chat bubbles. **User utterances** render as light, quiet text (a transcript, not a "message I composed"); **Plenara's turns** render as typed cards — a `Done` line, a clarification, a result card, a generative card — per §6. The bubble-vs-bubble chat metaphor is retired with the organic pass (§10).
- The v0 greeting and on-open nudges (`_session.pendingNudges()`) become AttentionSurface/Review-Feed entries rendered inline at the top of the Stream on open — same behavior, now specified (§6.7).
- Every `Done` line in the Stream is a **doorway**: tapping it (or "show me that") opens the written record inside its type's archetype view, with a shared-element transition (§8.3).

### 2.3 Collections

The browsing surface: one archetype-rendered home view per *top-level* type (owned types render inside their owner, §3.3; deprecated types are hidden, Spec 01 §4.2). Reached by voice ("show my runs," "open the journal") or from a Stage/Stream doorway. The Collections index itself is a single quiet page listing each type by its `displayNamePlural`, glyph, and a one-line live summary (latest entry / count / streak) — typography-led, not a grid of icons.

### 2.4 The Operation Center & AttentionSurface

One surface, two sections, reachable from the Stage chip and by voice ("what's pending," `show_pending` → Spec 04 §3.9):

- **Working** — live detached operations (authoring in flight, a generating briefing; Spec 04 §4.7), each with its `Detached` handle, a quiet progress shimmer, and delivery-in-place when done.
- **Needs a look** — the rendered `AttentionSurface` (Spec 04 §3.12): repair items, locked records, review-feed writes awaiting approval, inert drafts, consolidation proposals (Spec 01 §6.2). Rendered per §6.7.

### 2.5 The Quiet Overlay

Not a surface — an overlay over any of the four (§7). Nothing beneath it reflows.

### 2.6 Settings

Settings is a secondary destination in the global tools menu and is voice-reachable. It contains
BYOK entry/validation/removal, per-feature cloud disclosures, local admission/spend state, voice
selection where supported, appearance/presence preferences, data location/recovery, Feedback &
Diagnostics, and repair access. It is not a primary navigation root or a section of Operation
Center.

Settings also owns data-location status, **Choose data location**, and **Reset data and start fresh**. Reset copy must say exactly what crosses the boundary: the provider folder is disconnected but not deleted, the old device-local root is retained as a timestamped backup, and credentials/preferences remain. The identical reset action appears on the startup-error surface when storage initialization fails. That surface names the actual failure, stays usable at small-phone/large-text sizes, and restarts the planner in-process after reset; a diagnostics path without an action is not recovery. Spec 06 §3.1 owns the filesystem and bookmark semantics.

---

## 3. The View-Archetype Set

The schema vocabulary contains ten home archetypes, two child archetypes, and three proposed lenses.
The current `DataView` binary implements **five** renderer variants: `checklist`, `person_card`,
`tracker`, `timeline`, and `collection`. It selects them structurally and by known type id; it does
not consume `presentation.archetype`, color, icon, or resolved hint bindings. The additional
archetypes below are the approved design vocabulary but remain destinations until a renderer and
tests land. Schema acceptance of an id does not mean that renderer is shipped.

Every archetype defines: its **anatomy**, its **eligibility** (the structural facts a type must have — enforced by the validator, §4.2), its **required hints** (which `presentation` fields it consumes), and its **canonical instances** (which shipped types use it).

### 3.1 Home archetypes

**A1 — `timeline`.** The chronological log: entries as organic, low-chrome rows flowing down a soft time spine, day-grouped, newest first; sparse metadata right-aligned; infinite scroll windowed by month. The default home of every append-only record type. *Eligibility:* a resolvable `timestampField` of valueType `datetime` or `date`. *Hints:* `primaryField` (required), `secondaryField`, `timestampField` (required). *Canonical:* `interaction`, `meal` (Spec 01 §4.1), every tracker template's log.

**A2 — `checklist`.** Actionable items with a completion state: open items grouped by due horizon (overdue / today / this week / later), completed items folding away into a collapsed "done" seam rather than cluttering the live list. The check interaction is a single organic tick (§8.1 `m-instant`), voice-parallel ("done with the plumber call"). *Eligibility:* a `boolean` attribute with `default: false` (the done-flag; by convention `completed`) and a text `primaryField`. *Hints:* `primaryField` (required), `timestampField` (the due field, optional). *Canonical:* `task`.

**A3 — `ledger`.** The quantitative log: a timeline whose entries carry a dominant numeric value, rendered with a **period summary header** (this week / this month totals or averages, computed at query time — Spec 01 §2.2 computed-fields rule) and a small inline trend spark. This is the archetype for money and measured quantities, and the answer to "monthly breakdown by category" (05a P-16): when a `groupField` hint is present (an `enum` or `tag` attribute), the period summary renders grouped subtotals. *Eligibility:* append-only + a `number` or `decimal` attribute named by `valueField`. *Hints:* `valueField` (required — **new hint field**, §11 X1), `groupField` (optional — new), `timestampField` (required), `primaryField`. *Canonical:* an authored Expense type (05a P-16); Weight, Water templates.

**A4 — `journal`.** Long-form reading: one entry per day, generous measure, serif-leaning text face (§9.1), a date spine for navigation, no chrome inside the reading column. Entries open full-bleed. Locked entries (key absent, Spec 01 §8.7) render the locked treatment of §5.3. *Eligibility:* a required long-text attribute + a `date`/`datetime` timestamp; fully-sensitive types prefer this archetype. *Hints:* `primaryField` (the body), `timestampField`. *Canonical:* `journal_entry`.

**A5 — `person_card`.** The hub-entity profile — named for its canonical instance, but structurally general: a header (name, glyph, key plaintext facts — Spec 01 §8.2 keeps these renderable without decryption), then the entity's **owned types composed inline** — facts as `key_value` rows, relationships as `edge` chips, interactions as an embedded `timeline` (last 3, expandable) — then relations out (gift ideas, events). This is the view behind "what do I know about Mia" (Spec 05 §9) and the recall highlight ("allergy field highlighted"). *Eligibility:* a top-level entity type with a text `primaryField`; owned child types compose automatically by their `parentType` (§3.3 — no configuration needed). *Hints:* `primaryField` (required), `secondaryField`. *Canonical:* `contact`.

**A6 — `progress`.** A goal against its target and horizon: title, an organic fill arc (not a rectangular bar) from current toward `target`, the `horizon` date, status. Current value is a Business-Logic projection (e.g. summing a linked tracker), rendered as supplied by the view model. *Eligibility:* a `decimal`/`number` target attribute or a `date` horizon (either suffices; both is canonical). *Hints:* `primaryField`, `valueField` (target), `timestampField` (horizon). *Canonical:* `goal` (Spec 01 §12.4).

**A7 — `gallery`.** Attachment-forward: a fluid, irregular masonry of media with caption text beneath, opening to a full-screen viewer. *Eligibility:* an `attachment` attribute designated by `mediaField` (new hint, §11 X1). *Hints:* `mediaField` (required), `primaryField` (caption). *Canonical:* none shipped; the archetype exists for authored types (a "plants" or "wine labels" tracker — research §3.1).

**A8 — `collection`.** The universal fallback and the general entity browser: a scrolling column of soft cards, each showing `primaryField` large, `secondaryField` small, up to three more attributes as quiet label:value pairs, opening to a **detail sheet** that renders every attribute via the §5 value-type treatments in a single typographic column — *a composed reading page, not a form*: no input chrome, no field borders, editing happens by voice or per-value tap-to-edit (§5.5). `collection` is deliberately the least distinctive archetype — it is designed to be *adequate and calm* for any type whatsoever, which is what makes "no raw forms, ever" (§4.4) a guarantee rather than a hope. *Eligibility:* any type (that is the point). *Hints:* `primaryField` (required); all else optional. *Canonical:* any authored entity type that matches nothing better (a Restaurant type, 05a DF-01).

**A9 — `counter`.** The glanceable single-number habit surface: today's count/total large in an organic ring, tap or voice to increment ("log a glass of water"), a 14-day dot strip beneath. A deliberate near-twin of the streak lens, but as a *home* for high-frequency, low-ceremony trackers where the log itself is uninteresting. *Eligibility:* append-only + `valueField` (or unit-less count). *Hints:* `valueField`, `timestampField`. *Canonical:* Water, Medication, Habit templates.

**A10 — `event_list`.** Forward-looking dated items that are *not* actionable checkboxes: upcoming birthdays, planned dinners, trips — grouped by proximity ("this week / this month / later"), each row showing countdown phrasing ("in 4 days") rather than raw dates. *Eligibility:* a future-oriented `date`/`datetime` `timestampField` without a done-flag. *Hints:* `primaryField`, `timestampField` (required). *Canonical:* an authored Event type (research §10.2).

### 3.2 Child archetypes (render only inside a parent surface)

**C1 — `key_value`.** Fact rows: quiet label, strong value, one per line, no boxes. Renders inside a `person_card` (or any A5/A8 detail). *Canonical:* `contact_fact`.

**C2 — `edge`.** Relationship chips: "*daughter of* **Sarah**" — the `relationType` as connective text, the endpoints as tappable entity chips (§5.2 `entityRef` treatment). *Canonical:* `contact_relationship`.

A type whose archetype is a child archetype never receives a top-level Collections entry; it always renders within its `parentType`'s view (or, for `edge`, within either endpoint's view). Enforced in §4.2.

### 3.3 Lenses (alternate projections, not homes)

A lens is a second way of looking at data that already has a home archetype. Lenses are invoked by voice or a quiet toggle in the home view's header; they are never a type's primary assignment and never appear in `presentation.archetype`.

**L1 — `streak`.** The streak ring + gap view of Spec 05 §8: current streak count centered in a ring of day cells, longest-streak beneath (05a F-18). Available on any append-only type with a `timestampField`; the payload of the `show-streak` skill's UI event.

**L2 — `calendar`.** A month grid with entry density marks, any type (or all types) with a `date`/`datetime` attribute. Deliberately a lens, not a home: Plenara is not a calendar app, but "show June" is a legitimate way to look at anything dated.

**L3 — `dashboard`.** The composed cross-type summary — the Stage's ambient field is its small form; a fuller "how am I doing" board (streak states, progress arcs, period totals side by side) is its large form. Composition is a Business-Logic projection; the user cannot hand-arrange it in v1 (P8: curated, not configurable).

### 3.4 Conversation cards (turn-scoped, not type-scoped)

Rendered in the Stream, keyed to TurnEvents and detached deliveries rather than to types: the `Done` line, clarification chips, the deletion confirmation, the residual offer, the authoring preview, generative result cards, search results, and repair entries. Specified in §6 — they are part of the design language but not of the archetype registry, because no type maps to them.

---

## 4. How a Type Maps to an Archetype

The designed end state is the three-step hint/eligibility/inference pipeline below. Current behavior
is narrower: `SchemaRegistry.hydrate` validates supplied presentation metadata and records degraded
issues, while `DataView` independently infers one of its five renderer variants from type id and
record structure. Presentation hints are not yet passed through a resolved view model.

### 4.1 Step 1 — the authored hint is authoritative when eligible

`presentation.archetype` (Spec 01 §4.1) names one of the ten home or two child archetypes. If the named archetype's **eligibility predicate** (§3.1/§3.2) holds against the type's actual structure — attributes, `append`, `parentType`, and the hint fields resolving to real attributes of the right value types — the assignment stands. Authoring guidance (the prompt-side of Spec 02 §6.2) instructs Claude to choose from the closed list; the seed types and templates ship with their assignments fixed.

### 4.2 Step 2 — the eligibility validator

The current hydration validator implements the schema checks that can be evaluated from a supplied
presentation block. The following fuller assignment behavior is the destination:

- `presentation.archetype` ∈ the closed archetype id set (home + child only; lens ids are rejected).
- Every hint field the archetype *requires* (§3) is present and names an existing attribute of an eligible value type (`timestampField` → `date`/`datetime`; `valueField` → `number`/`decimal`; `mediaField` → `attachment`).
- A child archetype (`key_value`, `edge`) requires `parentType` (for `edge`: at least two `entityRef` relations instead).
- Violations **degrade, never reject**: the type still registers (capture must not be blocked by a cosmetic error — P2.8), the presentation block is marked degraded, Step 3 assigns the fallback, and the degraded hint surfaces in the AttentionSurface ("The 'Wine' type asked for a gallery view but has no attachment field — showing it as a collection."). This mirrors Spec 01 §5.3's degraded-relation behavior exactly.

### 4.3 Step 3 — the inference function (fallback and default)

When the hint is absent, invalid, or degraded, the destination
`inferArchetype(TypeDefinition) → ArchetypeAssignment` assigns one deterministically. This function
does not exist in the shipped code; the table remains the intended ordered rule list:

| # | Structural condition (in order) | Archetype |
|---|---|---|
| 1 | ≥ 2 required `entityRef` relations and ≤ 2 own attributes | `edge` |
| 2 | `parentType` set and not `append` | `key_value` |
| 3 | every attribute `sensitive` + a required long `text` + a `date`/`datetime` | `journal` |
| 4 | a `boolean` with `default: false` + a required `text` | `checklist` |
| 5 | `append: true` + a `decimal` attribute (or `number` with a currency-like `unit`) | `ledger` |
| 6 | `append: true` + a `number` attribute + high-frequency template class | `counter` |
| 7 | `append: true` + any `date`/`datetime` | `timeline` |
| 8 | a `decimal`/`number` target-shaped attribute + a `date` horizon + a status `enum` | `progress` |
| 9 | an `attachment` attribute | `gallery` |
| 10 | future-oriented `date`/`datetime` + no done-flag | `event_list` |
| 11 | is the target of ≥ 1 registered `parentType` (a hub entity) | `person_card` |
| 12 | anything else | `collection` |

Alongside the archetype, inference fills any missing hint fields by convention: `primaryField` ← first required `text` attribute; `timestampField` ← the `defaultToNow` datetime, else the first `date`/`datetime`; `valueField` ← the first `number`/`decimal`. The resolved `ArchetypeAssignment` (archetype id + resolved field bindings + degraded flag) is what the view-model layer consumes — renderers never re-derive it.

Rules 1–12 are total: **every possible TypeDefinition lands somewhere**, and rule 12's landing (`collection`) is a designed view, which is what discharges research §4.5's risk in full.

### 4.4 The guarantee: no generic raw CRUD forms

There is no code path that renders a type as an auto-generated input form. Creation and editing happen by voice (the primary path), by re-speaking a correction (Spec 05 §3.3), or by per-value tap-to-edit inside a rendered view (§5.5) — which edits one value in place with the value type's own input treatment, never a form page. This is testable (Spec 09): for a fuzzed corpus of valid TypeDefinitions, every render resolves to one of the twelve archetypes and zero form widgets are instantiated.

### 4.5 Lens availability

Lenses attach by the same structural predicates (L1: append + timestamp; L2: any dated attribute; L3: composed) — computed, not authored. A type never declares its lenses.

---

## 5. Value-Type Render Treatments

Each of the twelve value types of Spec 01 §3 has exactly one canonical display treatment and one canonical edit treatment, shared by every archetype (this is what makes archetypes cheap to add and types free to render). Formatting is always locale-aware and always display-side — storage stays canonical (UTC, ISO, plain numbers; Spec 01 §3).

| Value type | Display treatment | Edit treatment (tap-to-edit, §5.5) |
|---|---|---|
| `text` | Body type; long text clamps to 3 lines with a soft-fade expand in lists, full measure in detail | Inline text field, single value |
| `number` | Formatted per locale, trailing `unit` in small caps ("5.2 km"); integers render without decimals (Spec 01 §3 note) | Numeric keypad inline field |
| `decimal` | Exact, currency-formatted when `unit` is a currency code ("$12.34") | Numeric field, decimal keyboard |
| `boolean` | Never the word "true": the checklist tick, or a quiet state word chosen from the label ("Done", "All-day") | The tick / a two-state chip |
| `datetime` | Relative within ±7 days ("yesterday, 2:30 pm", "in 3 days"), absolute beyond ("June 12"); full timestamp on long-press; always local time | Natural-language capture by voice; a date-time sheet by touch |
| `date` | "June 12" / "in 4 days" for future-oriented fields; year only when ≠ current | Date sheet |
| `duration` | Humanized to two units max ("27 min", "1 h 10 min") | Numeric + unit chips |
| `enum` | A small tinted chip with the value's label; enum chips are the one place a type's accent color (§9.3) tints text chrome | Chip row of `enumValues`, single-select |
| `entityRef` | An **entity chip**: glyph + display name, tappable → the target's archetype view. A dangling ref (Spec 01 §4.5) renders as a muted "missing" chip that opens the repair entry, never as a blank or a raw UUID | Entity picker fed by name resolution (Spec 03 §6.1) |
| `tag` | A wrapping row of quiet chips (Spec 01 §3: "rendered as chips") | Chip field, add/remove |
| `attachment` | Thumbnail (media) or file card (other), rounded to the shape language; opens the viewer | System picker |
| `json` | Collapsed by default to a single "structured data" row; expands to a monospace, read-only pretty-print. Never rendered as UI (it is the escape hatch, Spec 01 §3) | Not editable in UI; voice/skill only |

**§5.1 Composite attributes** (Spec 01 §3.2, one level): rendered as a grouped line — the parent label once, children inline separated by middots ("Location — Austin · USA"); in detail views, an indented `key_value` cluster.

**§5.2 Relations** (`relations` array): rendered with the `entityRef` chip treatment; `cardinality: many` renders a wrapping chip row.

**§5.3 Locked values (destination).** No encrypted payload or `CryptoBox.keyAvailable` state exists
today. When Spec 01 §8.7 ships, an unreadable encrypted value uses a soft shimmer block with a lock
glyph and an actionable explanation; plaintext fields of the same record remain readable.

**§5.4 Sensitive values in shared contexts:** the spoken channel never reads a `sensitive` value aloud unless the user asked for that value specifically (matches Spec 05 §12 E4's search behavior: card shows, speech summarizes).

**§5.5 Tap-to-edit:** any rendered value in a detail view accepts a tap → its edit treatment appears in place → commit renders as a normal act-then-describe turn in the Stream ("Updated — allergy: tree nuts"), so touch edits share the voice path's undo, journal, and corpus semantics (Spec 04 §3.6 — the edit is dispatched as a turn, not written by the widget; P5).

> **Current posture — the shipped secondary Library surface.** The editable generic browser exists
> under **Library**, alongside learned phrases and Settings access. Library is a secondary tool,
> while Relationships/Todos/Habits are the primary roots owned by Spec 17. Learned phrases remain
> humanized and forgettable. Two implementation facts define the current boundary:
> 1. **Facade write, not a Stream turn.** A tap-to-edit commit calls a `Session` facade (`editField`/`deleteRecord`) directly rather than dispatching an English turn through the orchestrator (v0 has no structured-turn entry, and synthesizing English for `handle()` would be fragile). The *substance* of §5.5 is preserved — the write shares the **one** journal ring (a spoken "undo that" reverses a manual edit), reminders reconcile, automations fire, telemetry logs — and the confirmation surfaces in-sheet rather than in the Stream (a modal-sheet SnackBar would render behind the sheet; failures show inline as `errorText`, never silently). **End-state:** when a structured-turn entry exists, `editField` becomes its adapter with no UI change.
> 2. **Edit treatments = what v0's value types need.** Per-value tap-to-edit (not a form, §4.4) is honored; `json` is read-only (voice/skill only) and `enum` membership is validated in the facade, matching the §5 table. Delete is act-then-describe with a **targeted** UNDO snackbar (journal + storage tombstone = doubly reversible), not a pre-delete confirm.

---

## 6. The Turn UX — Rendering the Interaction Contract

Spec 05 §3 owns *when* these outcomes occur; this section owns their visual intent. The shipped UI
does not have an exhaustive sealed `TurnEvent` renderer. `VoiceTurnController` exposes capture,
busy, transcript, reply, clarification, error, and undo state, while `ConversationLedger` persists
final utterances, replies, and execution links. Any future event union must adapt those current
sources without creating a second state authority.

### 6.1 `TurnStarted` / listening / thinking

No card. Plena (§8.4) carries listening/thinking/speaking state and the live caption carries the
interim transcript. The conversation ledger gains an entry only for a final submitted utterance or
result.

### 6.2 `Done(confirmationText)` — the act-then-describe line

The workhorse. A single-line assistant turn: the type's glyph in its accent tint, the resolved `confirmationText` (Spec 02 §7.1 — never free text composed by the UI), and a quiet **Undo** chip.

- Current manual edits and deletes show a targeted Undo snackbar for five seconds. A newer result
  replaces the current snackbar so rapid edits never queue stale confirmations. Durable History
  retains targeted undo entries after that transient affordance; spoken “undo that” goes through
  the execution journal. Undo is therefore not limited to a single visible latest line.
- The line is a doorway to the record (§2.2). For multi-write turns (F-07's three writes) there is still **one** line and one undo (atomic per Spec 05 §3.5); the doorway opens the primary record with the side-created records chip-linked.
- An undo's own confirmation ("Undone — removed…") is a normal `Done` line with no undo chip.

### 6.3 `Routing` (advisory) — the transparency hint

In the moderate-confidence band (Spec 05 §3.2), the `Done` line carries a small prefixed **routing chip** naming where the turn landed ("→ Task"). The chip is advisory, never a gate (Spec 04 §3.6); tapping it fans out the near-candidates as chips — choosing one dispatches a `Correct` restatement, which visually runs the reverse-then-redispatch of Spec 05 §3.3 as: old `Done` line gains a struck-through "reversed" state (`m-quick`), new `Done` line arrives beneath. The high-confidence band shows no routing chip at all (quiet by default, P8).

### 6.4 `ClarificationRequested` — one question, spoken, answerable three ways

The question renders as an assistant line (and is spoken); beneath it, the candidates as **choice chips** (2–4, from Spec 03 §2.4's candidate set — "a task, a note about someone, or a journal entry?"). Voice answer, chip tap (`SelectCandidate`), or typed answer in quiet mode are the same `respond()` (P1). Missing-slot follow-ups (`ProvideSlot`) render as the question line alone — free-form answers get no chips. At most one clarification surface is ever live (Spec 04 §3.6 promptId discipline); a superseded one collapses to its resolved state.

### 6.5 `ConfirmationRequested(nonUndoableDeletion)`

Non-undoable type or skill deletion requires explicit pre-action confirmation (Spec 05 §24) with
the affected definition/data explained and no default-highlighted destructive choice. It is the
only confirmation required by act-then-describe policy, but not the only sheet or dialog in the UI:
precise editing, relationship actions, contact import, settings, and recovery legitimately use
bounded modal surfaces.

### 6.6 `ResidualOffer`, `Detached`, and generative results

- **ResidualOffer** (compound utterances, Spec 04 §3.6/`G-23`): the free fragment's `Done` line, then an offer line with Accept/Not-now chips ("…want me to create a custom one? [PAID]"). Declining leaves no debris (05a DF-09).
- **Detached (current):** operation state appears on Todos and is restored from device-local
  operation storage; terminal delivery is recorded exactly once in the conversation ledger and may
  notify through the native adapter. In-place mutation of a Stream card and a combined Operation
  Center remain design destinations.
- **Generative result cards (target).** Use one card grammar for implemented kinds; event prep,
  foresight, and reflection are candidate examples, not current registry members. Provenance stays
  visible, structured rows remain referable, and a read-only generation shows no undo affordance.
- **`TurnError`**: the mapped actionable surface of Spec 04 §5.2 as a calm card — what failed, the action that fixes it (the three distinct paid-unavailable surfaces of Spec 05 §13 each keep their own wording). Never a toast; errors are content, not interruptions.

### 6.7 The AttentionSurface & Review Feed rendering

One list grammar for every item kind (Spec 04 §3.12): glyph, one-sentence plain-language description, one primary action chip, optional dismiss. Kind-specific bodies: *definition* sync conflicts get the diff-style two-column view (Spec 01 §7.5); *record* conflicts (`recordConflicts`, Spec 06 §6.1 — P2) get a two-value picker like the automation case, not the def-diff view — records auto-resolve, so the surface is review/recovery, never a gate; consolidation proposals get the merge framing of Spec 01 §6.2 verbatim ("You have 12 Meal records and 3 Food log records…"); review-feed automation writes get approve/undo per Spec 04 §3.9; locked records get the §5.3 treatment with a count. The Stage chip (§2.1) is the only ambient signal of a non-empty surface — a count in quiet text, never a red badge (P8).

### 6.8 The authoring preview

The Spec 05 §14 flow's `UI: Authoring preview card`: a live, honest **miniature of the actual archetype** the new type will render into — three sample rows of the timeline/collection/etc. with the proposed fields in place — not a schema table. Field list beneath as `key_value` rows; the archetype named in plain words ("Timeline view"). Refinement turns update the miniature in place (`m-settle`). "Activate" is spoken or a chip. This card is the UI's contribution to making authoring feel like design collaboration rather than configuration.

---

## 7. The Quiet Overlay & Subtitle Behavior

### 7.1 Modes, precisely

The current app persists one `voiceMuted` preference. When true it raises text input and suppresses
TTS; when false it enables the voice-first posture. An unavailable recognizer also exposes text
input without pretending capture is available. A separate output-only TTS preference is a future
refinement, not shipped state.

Voice is tap to start and tap again to stop-and-send. The explicit voice affordance is global on
populated planner surfaces; tap-anywhere is limited to non-interactive presence space. Subtitles
remain visible regardless of `voiceMuted`.

### 7.2 The overlay itself

A text field with a send affordance rises from the bottom when muted or STT-less. Submitted text
calls `VoiceTurnController.send`, the same method used by a final speech result; both then call
`Session.handle` and share routing, execution, undo, reply, and ledger behavior. The field may
overlay or participate in the responsive planner layout as needed to remain usable with the
keyboard and accessibility text sizes.

### 7.3 Subtitle behavior

The subtitle region (§2.1) has two slots, and its rules are the contract Spec 04 §4.2 refers to for the live subtitle (that reference currently says "Spec 06" — a miscite to fix; §11 X4):

- **The user slot (interim transcript).** Renders the STT interim stream live, in a dimmed style that visibly means *provisional* — words may rewrite as the engine revises. On the final transcript it solidifies (`m-quick` weight change) and commits to the Stream as the user turn. Only the final transcript ever dispatches (Spec 04 §4.2).
- **The assistant slot (spoken output).** The full reply appears when speech begins, remains through
  speech, then clears after roughly 1.6 seconds. The conversation ledger retains the full reply, so
  the transient caption is not the sole record.
- **Length discipline:** captions prioritize readable current context; longer durable replies remain
  available in History/conversation rather than relying on the fading presence caption.
- **Quiet mode difference:** none, visually. Muting TTS changes only the audio; the assistant slot behaves identically, which is what makes the mode switch cognitively free.

### 7.4 Barge-in, visually

Starting capture stops active TTS before the recognizer listens and Plena snaps to listening. The
current ledger has no explicit `TurnCancelled` row; only final submitted utterances and completed
replies are durable.

---

## 8. The Motion Language

### 8.1 Tokens

All motion in the app draws from five named tokens. No widget defines ad-hoc durations.

| Token | Duration / character | Curve | Used for |
|---|---|---|---|
| `m-instant` | 90 ms | ease-out | State ticks: checkbox, chip select, orb state snap |
| `m-quick` | 200 ms | ease-out-cubic | Chips in/out, subtitle solidify, undo-chip fade, list row changes |
| `m-settle` | 320 ms | emphasized decelerate | Card entrance, sheet/overlay slide, doorway open |
| `m-drift` | 600–900 ms | ease-in-out-sine | Ambient field rearrangement, lens cross-fade, progress-arc fill |
| `m-breathe` | ~4 s loop | sine | Orb idle breathing, locked-value shimmer, working shimmer |

Spatial transitions prefer physics (spring settle) over fixed curves where the framework allows (Flutter's spring simulations); the durations above are their perceptual equivalents.

### 8.2 Rules

1. **Motion means meaning.** Nothing animates unless state changed. No looping decoration except `m-breathe` surfaces, and at most one `m-breathe` surface per screen.
2. **One mover.** At most one `m-settle`-class transition runs at a time; simultaneous changes choreograph as a single composed transition, not competing ones. (This is the "fluid, not busy" line — research §2.3's fluidity read through P8's quiet.)
3. **Enter soft, exit softer.** Entrances may translate + fade; exits fade only. Nothing ever slides off-screen drawing attention to its departure.
4. **Text does not move.** Type may change weight/opacity in place (`m-quick`); it is never animated positionally mid-read — subtitles solidify, they don't slide.
5. **Honor reduced-motion.** The OS accessibility flag collapses `m-settle`/`m-drift` to cross-fades and stops `m-breathe` at a static frame. This is a hard requirement, not a nice-to-have.
6. **State changes are animated, not instant** (research §2.3) — within the tokens above; "animated" never means "slow." The tempo target: a voice turn's `Done` line must be visible within the same beat as the spoken word "Done."

### 8.3 Continuity transitions

The signature move of the app: the **doorway** — a `Done` line, ambient card, or search result opens into its record with a shared-element transition (the glyph and primary text persist and re-seat; `m-settle`). This single mechanism links the Stream, the Stage, and Collections into one continuous space and is the main reason the app feels like one organism rather than screens. Lens switches (home ↔ streak ↔ calendar) are in-place cross-morphs (`m-drift`), never navigations.

### 8.4 The presence (listening orb)

*(Superseded, 2026-07-11 — Spec 15 §6.3 / suite-sync X1: the orb is subsumed by **Plena**, the particle-swarm presence of Spec 15. The four states, the `m-instant` snap, and the visibly-muted rule carry over into the swarm unchanged; the shipped interaction is **tap-anywhere-to-speak** on the presence-primary home, not press-and-hold on an orb widget. This section stands as the seed it was.)*

An organic, softly irregular form (not a perfect circle — §9.2) with four states: **idle** (`m-breathe`, low amplitude), **listening** (amplitude follows mic level — the user *sees* being heard), **thinking** (a slow internal drift; replaces every spinner in the app), **speaking** (gentle pulse synced to TTS cadence). State changes snap at `m-instant` — responsiveness is the one place quickness beats smoothness. This historical orb seed is superseded by Plena; the current tap-toggle gesture and availability/muted semantics are Spec 12 and Spec 17.

---

## 9. Typography, Shape & Color

### 9.1 Typography-led hierarchy (research §2.3)

Two families: a humanist sans for UI/labels/data, and a serif-leaning text face reserved for *the user's own words* — journal bodies, note text, transcribed speech in detail views — so the user's content reads as writing, not as data. A strict five-step scale (display / title / body / label / caption); hierarchy comes from size, weight, and space — never from boxes, rules, or background fills. Numbers in ledgers/counters use tabular figures.

### 9.2 Shape

Organic and continuous: superellipse ("squircle") corners on all cards and sheets, radius scaling with element size; the orb and progress forms are softly irregular closed curves, subtly unique per render seed. No hairline-bordered rectangles; separation comes from spacing and very soft elevation. This is the "not a grid of rectangular buttons" rule made concrete.

### 9.3 Color, and the constraint on `presentation.color`

The base surface is a warm near-neutral field (light and dark variants), with all chrome in low-contrast neutrals — the app's own palette stays out of the way so that **type accent colors** carry identity. Spec 01 §4.1 lets a type carry a free-form hex `color`; unconstrained, that is a clown-suit risk across authored types. This spec constrains it (cross-spec addition, §11 X3):

> **Current boundary:** generic `DataView` does not consume authored `presentation.color` or
> `presentation.icon`. The ramp snapping and glyph fallback below govern future consumption; they
> are not performed by `SchemaRegistry.hydrate` today.

- The binary ships a curated **accent ramp** of 12 hues, each pre-tuned for light/dark and for the tint roles (glyph, enum chip, progress fill, timeline spine).
- An authored `color` is **snapped to the nearest ramp hue** at registration (deterministic, in the same validator pass as §4.2); the file keeps the authored value, rendering uses the snapped one. Claude's authoring guidance names the ramp so snapping is normally the identity.
- Accent colors tint *identity elements only* (glyph, chips, fills) — never body text, never backgrounds of whole cards. `icon` likewise resolves against the shipped glyph set with a per-archetype default glyph as fallback; unknown names degrade quietly (§4.2 pattern).
- Semantic colors are exactly two beyond neutrals: a single attention hue (AttentionSurface, warnings) and a single confirmation-positive tint (the `Done` glyph beat) — and **no red badge culture** (P8). The deletion modal (§6.5) uses weight and words, not alarm color.

### 9.4 Layout

Generous whitespace as a rule with a number: content columns keep ≥ 24 pt side margins on phones and a 640 pt max reading measure on desktop (the v0 `maxWidth: 520` bubble constraint carries this instinct forward); vertical rhythm on an 8 pt base; density is *never* user-configurable (curated, P8). One-handed reach governs the phone layout: the orb and overlay live in the bottom third.

---

## 10. Current Realization and Remaining Design Destinations

The chat-screen staging plan is historical. The current app has:

1. purpose-built Relationships, Todos, and Habits workspaces plus secondary Plan, Library, and
   History;
2. adaptive Plena presence, persistent captions, text parity, and one voice/text controller;
3. five structurally selected generic renderers in `DataView`;
4. direct, actionable edit/import/contact/undo flows and durable operation/conversation state.

The remaining destinations in this document are the additional generic renderers, a resolved
presentation-hint view model, richer continuity transitions, output-only mute, and any future
sealed UI-event vocabulary. They must be described as new implementation work, not assumed
infrastructure.

---

## 11. Cross-Spec Additions & Corrections (for the next reconciliation pass)

- **X1 — New presentation hint fields (✅ landed — Spec 01 §9/§4.2, suite-sync CS-14).** `valueField` (ledger/counter/progress), `groupField` (ledger grouping), `mediaField` (gallery). Optional, additive, non-breaking per Spec 01 §7.1.
- **X2 — Partial.** Hydration validates supplied archetype/hint structure and records degraded
  presentation issues. `DataView` does not yet consume a resolved assignment or surface the issue.
- **X3 — Destination.** Authored color/icon are preserved but currently ignored by generic
  rendering; palette/glyph resolution is not implemented.
- **X4 — Miscite fix (✅ landed — Spec 04 §4.2 now cites §7.3 for rendering, Spec 12 §4.1 for dispatch).** Spec 06 is Data & Sync.
- **X5 — Archetype vocabulary confirmation (✅ landed — Spec 01 §12.3/§12.4).** Seed assignments adopted verbatim; `meal`'s example assignment (`timeline`, Spec 01 §4.1) is eligible under §4.2. `goal`'s `progress` assignment carries its `valueField: "target"`/`timestampField: "horizon"` bindings explicitly in the seed JSON.

---

## 12. Decision Record

### Resolved

- **D1 — The schema vocabulary is closed and finite; the shipped renderer subset is five.** The
  broader vocabulary remains the destination set and can be extended only by an app release.
- **D2 — Current mapping is structural and five-way.** `DataView.archetypeFor` selects checklist,
  contact person-card row, tracker, timeline, or collection. Hint-first resolved assignment remains
  the destination in §4; collection is the current total fallback.
- **D3 — Streak/calendar/dashboard lenses are design destinations.** Purpose-built Habits/Plan
  surfaces provide some equivalent outcomes, but generic lenses do not attach by schema predicate.
- **D4 — Ownership composition is domain-specific today.** The Relationships workspace composes
  facts/interactions around a person; generic `personCard` is a contact row and does not
  automatically embed every `parentType` child.
- **D5 — No generic schema-generated CRUD forms.** Generic detail editing is per-value. Purpose-built
  first-party sheets may group fields when that makes relationship, todo, habit, import, or settings
  workflows clearer; they still use business facades and shared journal semantics.
- **D6 — Generic detail uses shared per-value rendering/editing.** JSON is read-only. Locked-value
  treatment remains an encryption-era destination; dangling-reference repair depends on the
  available repair projection.
- **D7 — Act-then-describe visual contract:** undoable actions expose transient and durable recovery;
  non-undoable type/skill deletion confirms. Other bounded sheets/dialogs are valid (§6.5).
- **D8 — Subtitles are always on; current quiet mode is one persisted `voiceMuted` boolean.** Typed
  and spoken input converge in `VoiceTurnController.send`/`Session.handle`; independent output-only
  mute remains a destination (§7).
- **D9 — Motion is five tokens + six rules** (§8), with reduced-motion as a hard requirement and the doorway shared-element transition as the app's continuity signature.
- **D10 — Authored color/icon remain untrusted metadata.** Current generic rendering ignores them;
  any future consumption must constrain them to the app palette/glyph set (§9.3).
- **D11 — The chat widget tree is retired.** The current shell and conversation ledger are the
  implementation base; a future event renderer must adapt them rather than resurrecting v0 (§10).

### Open

- **Q1 — Grouped aggregation beyond one dimension.** `ledger` + `groupField` covers "monthly breakdown by category" (05a P-16), but a two-dimensional pivot ("by category *and* month, compared") has no archetype. Defer until an authored need hits the wall; the gap probe is P-16's Phase-3 trace.
- **Q2 — The accent ramp and glyph set themselves.** Twelve hues and the glyph inventory are asserted, not designed. A dedicated visual-design pass (with real mockups, outside spec prose) must produce them before the v3 organic rung; §9.3's *mechanism* is decided regardless.
- **Q3 — Wake-word ambient states.** Current tap-toggle opens the mic only for an explicit capture. Wake-word would add always-listening ambiguity — how "idle but armed" reads without feeling surveilled is unresolved and matters (research §6.5).
- **Q4 — Karaoke subtitles.** v1 shows spoken lines whole (§7.3). Word-synced highlighting is deferred pending TTS engines exposing reliable word timings cross-platform.
- **Q5 — Dashboard composition rules.** L3's selection logic ("most imminent, most alive") is named but not specified numerically; needs dogfood data before hard rules are worth writing.
- **Q6 — Windows/desktop idioms.** The current dogfood platform is Windows; §9.4 and §7.2 give desktop accommodations, but the P1 target is iPhone and this spec is phone-first. A short desktop-adaptation appendix should follow once the phone design settles.
- **Q7 — Per-archetype empty states.** §2.1 blesses the empty Stage; each archetype also needs a designed first-run/empty state (Spec 05 §8 E1's "No runs logged yet…" suggests the voice line; the visual needs the Q2 design pass).

---

*End of Spec 07 — UI & Design-Language v0.5*
