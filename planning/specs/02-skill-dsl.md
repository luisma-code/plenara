# Spec 02 — Skill DSL

**Status:** Draft v0.5 — July 2026 (Sonnet skeleton v0.1 → Opus hardening v0.2 → Opus 4.8 review v0.3 → act-then-describe reconciliation v0.4 — see Appendix A → v0 interaction-suite/due-date convergence v0.5, §3 dialect refresh + §9.3)  
**Depends on:** Spec 01 — Meta-Schema & Type System (§2–§5, §8)  
**Blocks:** NLU spec, Architecture spec, Data & Sync spec, UI spec
**Research-doc precedence (suite-sync CS-26):** where the locked research doc and this spec disagree, this spec is authoritative; the research-doc amendment pass (05c §3, list grown by 05f CS-26) remains queued for Luis.

---

## 0. Purpose & Scope

A skill is a named, multi-step operation that reads and writes typed records in the user's Plenara folder. Skills are the verbs of the system. They are authored once by Claude as data files and then executed forever by a deterministic interpreter — no generated code is ever evaluated at runtime.

This document specifies:

1. The skill file format and its place in the folder hierarchy
2. The primitive-operation vocabulary — the complete, closed set of things a skill step can do
3. Interpreter semantics — how the Skill Interpreter executes a skill from start to finish
4. The resolve/execute split — why parsing and planning are separated from side-effect-producing execution, and what each phase guarantees
5. The execution journal — how an in-flight skill is suspended and resumed safely (and why the plan cache is deferred)
6. The authoring flow — how Claude produces a skill, the constraints it operates under, and what a valid skill looks like
7. Confirmation and safety — how the interpreter surfaces pending actions for user approval, and how it defends against prompt-injection attacks embedded in user data
8. The no-executable-code constraint — the platform and product rationale for the closed-vocabulary approach, and its implications for skill design

It does **not** cover: NLU routing (how an utterance selects a skill to invoke), the automation/trigger mechanism that fires skills on a schedule or after a write (see §4.4 of Spec 01), or the view-archetype rendering that presents skill output to the user.

---

## 1. Governing Principles

The same principles from the research doc that govern the type system apply here with equal force.

**P2.4 — Code over AI.** Skills are authored by Claude (AI). Once authored, a skill is data. All execution — reading records, evaluating conditions, writing records, composing confirmations — is done by the deterministic Skill Interpreter. Claude is never called at runtime to continue, branch, or recover a skill.

**P2.7 — AI authors, code executes.** Claude produces a skill definition file as output. The interpreter consumes it as data. No string in the file is ever passed to `eval`, `dart:mirrors`, or any dynamic dispatch mechanism. This is not a performance choice — it is a correctness and platform-compliance requirement (§8).

**P2.6 — Capabilities are data.** A "log a meal" skill and the built-in task-creation skill are stored and treated identically. There is no privileged code path for built-in skills.

**P2.5 — Aggressive layering.** The Skill Interpreter lives entirely in the Business Logic layer. It calls the StorageRepository for reads and writes and the SchemaRegistry for type resolution. It does not call the UI layer directly — it emits events that the UI layer observes.

**P2.8 — No silent failure.** The interpreter and authoring flow never fail quietly. A skill that fails validation is never written and is returned to the user (via Claude) with a structured error to revise (§6.3); a resolve that hits a missing required input, an unresolvable variable, or a write that fails schema validation halts with a surfaced error *before* any confirmation, never a partial write (§4.1); and an authoring request that falls outside the closed vocabulary is answered not with "I can't" but with an explicit "that would require [network / a timer / model inference]; here is what I can do instead" (§8.4). Blocked and too-complex requests become a conversation, not a dropped action.

---

## 2. File Format

Each skill is a single JSON file in `[plenara-root]/skills/`. The filename is the skill's `skillId` with a `.json` extension.

### 2.1 Top-Level Structure

```json
{
  "skillId": "log-meal",
  "schemaVersion": 1,
  "displayName": "Log a Meal",
  "description": "Captures a meal or food intake event and writes it as a Meal record.",
  "authoredBy": "claude",
  "authoredAt": "2026-07-03T14:22:00Z",
  "safetyAssessmentId": "sa_9a2f...",
  "lastModified": "2026-07-03T14:22:00Z",
  "inputs": [
    { "name": "capturedDescription", "valueType": "text", "source": "slot", "required": true },
    { "name": "capturedCalories", "valueType": "number", "source": "slot", "required": false },
    { "name": "capturedMealType", "valueType": "enum", "enumValues": ["breakfast","lunch","dinner","snack"], "source": "slot", "required": false }
  ],
  "reads": ["meal"],
  "writes": ["meal"],
  "steps": { "main": [ ... ] },
  "dangerLevel": "safe"
}
```

The skill file holds **only the skill's definition** — it is a stable, seldom-changing artifact. In-flight execution state (which branch was taken, how many `foreach` iterations remain, the pending action plan) is **not** stored in the skill file; it lives in a device-local execution journal (§5) that is never synced. This keeps the definition file's `lastModified` meaningful (it changes only on an actual edit), avoids rewriting the file on every execution, and — critically — keeps resolved user-data values out of a file the encryption model treats as always-plaintext (Spec 01 §8.2). See §5 for the rationale.

### 2.2 Top-Level Fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `skillId` | string | yes | Lowercase kebab-case. Globally unique within `skills/`. **Immutable** once created — automations reference it by this ID (Spec 01 §4.4). |
| `schemaVersion` | integer | yes | Starts at 1. Incremented when a change to `steps`/`inputs` would alter execution semantics. Skills have no on-disk instances to migrate (unlike types), so a bump has no data-migration duty — it only invalidates in-flight execution-journal entries resolved against the old version (§5.3, §6.4). |
| `displayName` | string | yes | Shown in skill-management UI. |
| `description` | string | yes | One or two sentences. Used by Claude during reconciliation and to populate the automation-management UI. |
| `authoredBy` | `"claude"` \| `"system"` | yes | `"system"` for seed skills; `"claude"` for all user-defined skills. |
| `authoredAt` | ISO 8601 datetime | yes | When the skill was first authored. |
| `safetyAssessmentId` | string \| null | yes | ID of the stored safety assessment for Claude-authored skills. Null for seed skills only. Required before activation (§7). |
| `lastModified` | ISO 8601 datetime | yes | Updated only when the skill **definition** changes (an author/edit), never on execution — execution state is journaled elsewhere (§5). |
| `inputs` | Input[] | yes | The skill's parameter contract: the named values the caller (NLU or an automation) must/may supply. Defines the NLU→skill boundary and makes variable closure checkable (§2.3, §6.3). May be `[]` for a skill that takes no inputs. |
| `reads` | string[] | yes | The `typeId`s this skill may read. Enforced: every `typeId` in a read op must appear here (§6.3). |
| `writes` | string[] | yes | The `typeId`s this skill may create, update, or delete. Enforced: every write-op `typeId` must appear here. Declaring the write-set explicitly is part of the capability boundary (§8.3) — a skill cannot write a type it did not declare. May be `[]` for a read-only skill. |
| `steps` | object | yes | Label → step-list map. Execution begins at `"main"`. See §3.5. |
| `dangerLevel` | `"safe"` \| `"caution"` \| `"destructive"` | yes | Governs UI treatment, undo semantics, and the static danger classification (§6.3, §7.2). Interactive skills no longer pause for pre-action approval (act-then-describe, Spec 05 §3.1), so there is no per-skill confirmation-policy field; `dangerLevel` remains because it still classifies what a skill can *change*. See §7. |

`reads` and `writes` replace the v0.1 single `targetTypes` list. Splitting read capability from write capability lets the danger classifier and the type-deprecation check reason precisely about what a skill can *change* versus merely *observe*, and it lets the validator reject a skill that touches an undeclared type. The union `reads ∪ writes` is what the registry scans to detect dangling skill references when a type is deprecated (Spec 01 §6.2).

### 2.3 Input Contract

Each entry in `inputs` declares one value the skill expects from its caller.

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | yes | Context-variable name the value is bound to at resolve start. Unique within `inputs`. |
| `valueType` | ValueType | yes | One of the Spec 01 §3 value types. The interpreter coerces/validates the incoming value against it. |
| `source` | `"slot"` \| `"system"` | yes | `"slot"` = extracted by NLU from the utterance; `"system"` = supplied by the runtime (`now`, `today`, `userId`). |
| `required` | boolean | yes | If `true`, resolve halts with a structured "missing input" error when the caller omits it — surfaced to the user as a follow-up question, not a crash. |
| `enumValues` | string[] | if `valueType == "enum"` | Allowed values. |
| `default` | any | no | Literal bound when an optional input is omitted. Mutually exclusive with `required: true`. |

The three system values `now`, `today`, and `userId` are **always ambient** — usable as `{now}`/`{today}`/`{userId}` in any step and treated as bound by variable-closure (§6.3) without an `inputs` entry. A `source: "system"` input is needed only when a skill wants such a value treated as a formal, overridable parameter (e.g. injecting a fixed clock in a test, or a future runtime value like device locale); ordinary use of the ambient trio requires no declaration.

The input contract is the seam between this spec and the NLU spec (which this spec blocks). NLU is responsible for producing a slot-fill map keyed by the `name`s of `source: "slot"` inputs; the interpreter supplies the `source: "system"` values. Because inputs are declared per skill rather than derived from one type's `nluHints.captureIntent`, a multi-type skill (e.g. `log-interaction`, which resolves a contact by name *and* writes an interaction) has a coherent, checkable input surface — which the v0.1 "slot fills come from the target type's captureIntent" rule could not express.

---

## 3. The Primitive-Operation Vocabulary

> **✅ v0 NORMATIVE DIALECT (converged spec↔code, `G-41`, 2026-07).** The v0 interpreter
> (`v0/lib/interpreter.dart`, the reference implementation) uses **structured JSON** forms
> throughout — chosen because a JSON schema can fully constrain them at authoring time,
> which is where the measured authoring drift (`G-29`) lives; a free-form `"expr"` string
> cannot be. **The forms in this block are the normative wire format** and supersede the
> string/label-expression grammars still shown in §3.3, §3.7, and §3.8 (kept as prose intent;
> retire on the next full §3 rewrite). The vocabulary is CLOSED — `validateSkill` rejects any
> op/fn/cond/filter-op/valueType outside these sets:
>
> - **Ops (13, closed):** `read_one, read_many, read_related, read_reference, write_record,
>   delete_record, compute, set, format, branch, foreach, enumerate, ref_mark`.
> - **`enumerate`** (`G-47`, numbered-list corrections) — `{"op":"enumerate","list":{"var":"x"},
>   "label":"<field>","into":"var"[,"line":"{f} — {g}"]}`. Renders a NUMBERED readback string
>   (`\n  1. …\n  2. …`) into `into` AND, from the same single pass, exports the ordered
>   `{id,label}` list to the plan's `enumeration` channel — so a later spoken "delete 2" / "correct
>   1" resolves against EXACTLY what was read back (by recordId, never a re-derived order). `label`
>   is the identity field (what confirmations quote + what "correct" replaces); optional `line`
>   composes a richer per-row string over record fields (omit-if-null). For flat lists.
> - **`ref_mark`** (`G-47`) — `{"op":"ref_mark","typeId":"<t>","id":<idExpr>,"field":"<labelField>"
>   [,"label":<expr>]}`. Captures ONE item's ref into the `enumeration` channel from inside a
>   `foreach`, so a skill that builds rich/conditional/joined readback lines (and owns its own
>   numbering via a counter) still exports numbered references. First mark fixes typeId+labelField.
>   The Session resolves the channel to a conversational context and runs deterministic
>   reference-by-number handlers (complete/delete/correct, journaled for undo) — see Spec 03.
> - **`compute`** — `{"op":"compute","fn":<name>,"args":[…],"into":"var"}`, NOT a string
>   expression. Implemented `fn` set (34): `now, today, format_date, format_time, date_part,
>   time_part, start_of_week, start_of_month, add, mul, div, round, count, concat,
>   next_annual, days_until_annual, years_since, current_streak, longest_streak,
>   days_between, add_days, count_where, sum, avg, min, max, if, ordinal_num,
>   ordinal_suffix, weekday_nums, split_list, dedup_list, position_index, nth`.
>   `format_date`'s second arg is a format token: `"EEEE"` → weekday name ("Saturday"),
>   `"MMMM d"` (the default when omitted) → month-day ("December 25"), anything else →
>   the ISO date. The near/far due-date phrasing rule built on `days_between` +
>   `format_date` is §9.3. (`avg([])` → `null`; decimal exact-base-10 preservation is a
>   follow-on, `G-46`.)
> - **`branch`** — a **structured condition object** (NOT a string, §3.8) plus **inline**
>   `then`/`else` step arrays (`else` optional, NOT label refs into `steps`, §3.4/§3.5).
>   Condition grammar (5 forms): `{"isNull":"var"}`, `{"notNull":"var"}`,
>   `{"gte":[a,b]}` (numeric when both parse as numbers, else lexical),
>   `{"eq":[a,b]}`, `{"contains":[hay,needle]}` (case-insensitive substring; empty
>   needle never matches). This structured cond form is the **only** normative one.
> - **`read_many`** — `filter` is a predicate `{"field","op","value"}` **or a list of
>   predicates (ANDed)** — the list form is how a skill expresses a date range or a
>   description-plus-completed duplicate check without a compound op — with `op` ∈ {`eq,
>   neq, gt, gte, lt, lte, contains, ieq, in, isNull, notNull`} (`ieq` is case-insensitive,
>   whitespace-trimmed string equality, for duplicate detection; a bad op fails loudly,
>   even over an empty set), plus optional `orderBy`/`orderDir` (`asc`|`desc`) and `limit`
>   (top-N). §3.6's `_or` is **not** implemented.
> - **`read_one`** — exact (case-insensitive) match first; with `"partial":true` (people
>   lookups) falls back to case-insensitive substring, then an **alias tier** (a record
>   whose comma-separated `aliases` field holds the match value, `G-24`); with
>   `"resolve":true` (the find-or-create de-duplication tier, `G-12`) a further
>   **whole-word-token tier** reuses a record when one name's token set contains the
>   other's ("Katherine" reuses "Katherine Zinger"; "Sam" never matches "Samantha");
>   `"first":true` tolerates a non-unique match by taking the first (for lookups that are
>   not a user-facing name choice). Otherwise `>1` match raises an ambiguity clarify.
> - **`read_reference`** — `{"op":"read_reference","dataset":"nutrition","key":<expr>,"into":"var"}`,
>   the Spec 13 reference-dataset lookup (opcode 11, appended). A sync, offline Tier-1 lookup
>   in a shipped read-only dataset keyed by name (the Session injects the stores; the
>   interpreter's reference map is empty by default so it stays pure/testable). The key is
>   normalized (lowercase; punctuation → space; articles/quantifiers and bare digit counts
>   dropped) and matched **exactly** against entry keys and aliases — no fuzziness inside the
>   op; that lives in the resolver (Spec 13 §3). A hit binds the entry's fields plus
>   `provenance: "reference"` and the canonical `refKey`; a miss (or an unshipped dataset)
>   binds **null**, so null propagation and `branch {isNull}` give the honest-miss path with
>   no special casing (Spec 13 §3.5). Validated on `dataset` (string) + `key` + `into`;
>   Spec 13 §4.1's `quantity`/`measure` serving-scaling and the namespaced `reads` entry
>   (`"reference:nutrition"`) are **not yet** implemented in v0.
> - **`write_record`** with a `target` (`{"ref":"<recordVar>"}`) **updates** (field-merge);
>   without a target it **creates**. **`delete_record`** (`{"op":"delete_record","id":<expr>}`)
>   tombstones. (`dangerLevel` gating of destructive ops is not yet enforced — `G` open.)
> - **`format`** — bare `{var}` substitution (the stray `{var:name}` slot-syntax spelling
>   is tolerated and renders identically); a null/absent var renders as **empty** (the
>   omitIfNull default, no silent `{var}` leak). The `{var, default:…}`/`suffix` modifiers of
>   §3.11 are **not** implemented.
> - **Steps are validated on `op` + per-op required fields only** — unknown step keys are
>   tolerated and ignored, so an authored skill may carry annotation keys (the seed skills
>   use `"_comment"` for in-file rationale) without failing the gate. The closed sets above
>   constrain what a step can *do*, not what it may say about itself.
> - **Value types** — the accepted set now matches Spec 01 §3 (`text, number, decimal, date,
>   datetime, boolean, duration, enum, entityRef, tag, attachment, json`), with `integer` kept
>   only as a tolerated legacy alias for `number` (`G-40`).
> - Names retained from this spec: entity value type `entityRef`, confirmation slot
>   `confirmationText`, and every skill declares `reads`/`writes`; `validateSkill` enforces
>   capability closure (§6.4 rule 3), the branch-sound entityRef dataflow (`G-17`), and a
>   variable-closure check (rule 4 — every `{var}`/`{field}`/`{ref}`/format-placeholder
>   resolves to a bound name).
>
> Net: the *structure* is normative from the code (reliability); the *names + skill envelope*
> are from this spec. `read_related` and the aggregation/date/streak compute fns are all
> implemented (the earlier "not yet adopted" note is retired).

Every step in a skill is one of the following primitive operations. This set is **closed and fixed**. Adding a new primitive requires a version bump to the interpreter itself — it is not an authoring decision.

The vocabulary is intentionally small. Each primitive maps directly to a safe, auditable action the interpreter can perform without dynamic evaluation. The richness of a skill comes from composition and sequencing, not from primitive complexity.

### 3.0 Two Representations: Symbolic Source, Compiled Execution Form

A skill exists in two forms, and the DSL optimizes each for a different goal — this is the same source-vs-µop split the research doc's §4.9 ISA analogy points at.

**Authored source** (`skills/*.json`, on disk, synced). Every step names its op with a **symbolic** string (`"op": "read_many"`) and its modifiers with symbolic keys, label names, enum literals, and `{variableName}` references. This form is deliberately human-readable and is **never executed directly**. Its readability is load-bearing, not cosmetic:

- **Platform compliance (§8.2).** The Apple 2.5.2 / Microsoft 10.2.6 argument is "skills are *data, not code*." Readable JSON visibly reads as configuration; a file of packed integer opcodes reads, to a reviewer, as downloadable bytecode — exactly the pattern those policies target.
- **Auditability (§8.3) and safety.** A user (or Luis) can open the file and the paired safety assessment (§7.4) and cross-check them. A binary blob defeats this.
- **Portability and sync (§10 Q1, Spec 01 §7.5).** Definition-file conflicts are resolved by human-reviewable diffs; that only works on text.
- **Forward-compat is detectable.** A source skill using a newer primitive *fails to compile* on an older interpreter (unknown symbol → "needs a newer Plenara"), rather than silently mis-executing against a shifted opcode table.

**Compiled form** (in memory; and the persisted *action chain* in the execution journal, §5, and the deferred plan cache, §5.5). At registration/load — **once**, off the hot path — the interpreter compiles each skill into a typed, fully-numeric representation and optimizes it freely:

- `op` symbol → integer **opcode** (table below), dispatched by an integer `switch` (jump table), never string-matched or hashed at runtime.
- Modifier keys → fixed struct slots; `enum` literals → ints; label names → step indices; `{variableName}` references → integer slot indices in a fixed-size context frame (array indexing, not map lookup).

The compiled form needs no readability — it is derived deterministically from the source, regenerated on demand, and never fetched from anywhere. This is where all execution efficiency lives. Nothing on the execution path parses a string.

**When compilation happens.** A skill is compiled **lazily** — on first invocation, or in a low-priority background pass after launch — never eagerly for the whole folder at startup, so a directory of hundreds of skills does not tax cold launch. The compiled form is held in an in-memory session cache and dropped when the skill is edited; it is cheap to regenerate and is **never persisted to disk**. Persisting a skill-wide compiled cache would reintroduce the "compiled bytecode at rest" surface §8.2 warns against; the one on-disk compiled artifact is the execution journal's per-execution action chain (§5.3), which is encrypted and device-local, not a skill library.

**Opcode table (interpreter ISA).** Opcodes are part of the interpreter binary and versioned with it, exactly like the closed vocabulary. Assignment is **append-only**: a new primitive takes the next free integer and numbers are **never reused or renumbered** (syscall-number discipline), so a persisted action chain stays valid across interpreter updates.

| Opcode | `op` symbol | Category |
|---|---|---|
| 1 | `read_one` | read |
| 2 | `read_many` | read |
| 3 | `read_related` | read |
| 4 | `write_record` | write |
| 5 | `delete_record` | write |
| 6 | `compute` | derived |
| 7 | `format` | derived |
| 8 | `set` | derived |
| 9 | `branch` | control |
| 10 | `foreach` | control |
| 11 | `read_reference` | read |

The subsections below define each primitive by its symbolic source form (what an author and a reviewer read); the opcode is the compiled tag for the same primitive.

### 3.1 Read Operations

#### `read_one`
Fetch a single record by its `id` or by a field match.

```json
{
  "op": "read_one",
  "typeId": "contact",
  "match": { "id": "{contactId}" },
  "into": "contact"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `op` | `"read_one"` | yes | |
| `typeId` | string | yes | Must resolve in the SchemaRegistry. |
| `match` | object | yes | Key-value pairs. Values may be literal strings or `{variableName}` references to the skill's execution context. |
| `into` | string | yes | Variable name the result is bound to in the execution context. `null` if the record is not found. |
| `required` | boolean | no | Default `false`. If `true` and no record matches, the skill halts with an error surfaced to the user. |

#### `read_many`
Fetch a list of records matching a filter.

```json
{
  "op": "read_many",
  "typeId": "meal",
  "filter": {
    "loggedAt": { "gte": "{windowStart}", "lte": "{windowEnd}" }
  },
  "orderBy": "loggedAt",
  "orderDir": "desc",
  "limit": 50,
  "into": "recentMeals"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `op` | `"read_many"` | yes | |
| `typeId` | string | yes | |
| `filter` | FilterExpr | no | Declarative filter object. See §3.6. |
| `orderBy` | string | no | Attribute name to sort by. |
| `orderDir` | `"asc"` \| `"desc"` | no | Default `"asc"`. |
| `limit` | integer | no | Maximum records to return. |
| `into` | string | yes | Variable name bound to the result list. |

#### `read_related`
Fetch records reachable from a record you already hold, along one of the two Spec 01 edges: **ownership** (children whose `parentId` is the source) or an explicit **relation** (`entityRef` targets). Exactly one of `parentId` or `via` must be supplied.

```json
{
  "op": "read_related",
  "typeId": "contact_interaction",
  "parentId": "{contact.id}",
  "orderBy": "occurredAt",
  "orderDir": "desc",
  "limit": 10,
  "into": "recentInteractions"
}
```

```json
{
  "op": "read_related",
  "from": "{giftIdea}",
  "via": "forContact",
  "into": "giftRecipient"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `op` | `"read_related"` | yes | |
| `typeId` | string | if `parentId` | Owned child type; must declare `parentType` (Spec 01 §4.5). Omitted in `via` mode (the target type is the relation's `refType`). |
| `parentId` | string | one of `parentId`/`via` | **Ownership mode:** dot-path to the owner's `id`; returns children of that parent. |
| `from` | string | if `via` | **Relation mode:** dot-path to the source record holding the relation. |
| `via` | string | one of `parentId`/`via` | **Relation mode:** the relation `name` on the `from` record to traverse (Spec 01 §4.3). Resolves the referenced `entityRef` target(s). For a `cardinality: "many"` relation, `into` is bound to a list. |
| `filter` | FilterExpr | no | |
| `orderBy` / `orderDir` / `limit` | — | no | Same as `read_many`. |
| `into` | string | yes | |

Relation mode makes the graph edges Spec 01 promises ("independently queryable", §2.1) actually traversable from a skill — needed by the gift/contact marquee tasks (a `gift_idea` reaching its `forContact`). Ownership mode is unchanged from v0.1.

#### `read_reference`
Fetch an entry from a shipped, read-only reference dataset (Spec 13) — a lookup against the ReferenceStore, not the StorageRepository. Side-effect-free, so permitted in the resolve phase like all reads (§4.1). Appended to the vocabulary as opcode 11 under the §3.0 append-only discipline.

```json
{
  "op": "read_reference",
  "dataset": "nutrition",
  "key": "{itemKey}",
  "into": "nutrition"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `op` | `"read_reference"` | yes | |
| `dataset` | string | yes | A shipped `datasetId` (Spec 13 §2), e.g. `nutrition`. Not a `typeId` — reference data is versioned app content, not user records — so it adds nothing to the read capability closure. An unknown dataset behaves as a miss. |
| `key` | string | yes | The lookup name, usually a resolver-supplied slot (Spec 13 §4.2). May be a literal or a `{variableName}` reference. Normalized (case, punctuation, articles/quantifiers, bare digit counts) and matched **exactly** against entry keys and aliases — no fuzzy matching inside the op; fuzziness lives in the NLU-layer reference resolver (Spec 13 §3). |
| `into` | string | yes | Bound to the matched entry's fields plus `provenance` (`"reference"`) and the canonical `refKey`. **`null` on a miss** — null propagation (§3.7) and a null branch give the honest-miss path with no special casing (Spec 13 §3.5). |

Spec 13 §4.1 additionally designs `quantity`/`measure` serving-scaling and a namespaced `reads` declaration (`"reference:nutrition"`, its validator rule 7); neither is implemented in the v0 interpreter yet — v0 ships the deterministic key lookup above.

### 3.2 Write Operations

#### `write_record`
Create a new record, or — if `id` is supplied and the record already exists — **update it by field-level merge**: only the attributes named in `fields` are changed, and every other attribute retains its stored value. A merge, not a replace: an update that sets `completed: true` need not re-supply the record's title. For append-only types (`append: true` in Spec 01 §4.5), only creation is permitted — a supplied `id` matching an existing record is rejected.

```json
{
  "op": "write_record",
  "typeId": "meal",
  "fields": {
    "description": "{capturedDescription}",
    "calories": "{capturedCalories}",
    "mealType": "{capturedMealType}",
    "loggedAt": "{now}"
  },
  "into": "newMeal"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `op` | `"write_record"` | yes | |
| `typeId` | string | yes | |
| `id` | string | no | If omitted, a new UUID is **minted during resolve** and frozen into the action plan (§4.4), so a resumed execution never double-creates. If provided and the record exists, the write is a field-level merge (above). |
| `fields` | object | yes | Attribute values to write. On a **create**, all `required` attributes (Spec 01 §3.1) must be present; on an **update**, only the attributes being changed. Values may be literals or `{variableName}` references. |
| `into` | string | no | If provided, the written record (with its assigned `id`) is bound to this context variable. |

**Required-attribute validation is scoped to the operation.** A create must supply every `required` attribute; an update (merge) validates only the changed attributes against their `valueType` and may not set a `required` attribute to `null` — the stored record was already complete, so a merge need only keep it complete. This is what lets `complete-task` write `{ "completed": true }` against a task `id` without re-reading and re-supplying the whole record. Because a create's `id` is minted at resolve (§4.4), the write validated during resolve and the write applied during execute reference the same identity — the confirmation shows the record's real, final `id`, and a resumed execute re-issues the *same* create rather than a duplicate.

#### `delete_record`
Remove a record by `id`. Only permitted on skills with `dangerLevel: "destructive"`. Deletion is **undoable**: the execute phase captures the record's full before-image into the completing journal entry (§5.4), and `undo` restores it within the undo window (Spec 04 §3.11). Because it is reversible, a record delete follows act-then-describe like any other write — it executes immediately and is described, with undo as the safety net (Spec 05 §3.1); there is no pre-action or secondary confirmation. (Deletion of a *type or skill* is a different, non-undoable operation handled by the deletion meta-flow, Spec 05 §24 / Spec 04 `MigrationRunner`, and that flow does pre-confirm.)

```json
{
  "op": "delete_record",
  "typeId": "meal",
  "id": "{targetMeal.id}"
}
```

Per Spec 01 §12 Q7 (reviewer rec adopted for v1: tolerate dangling, no cascade), the delete does not cascade to owned children or repoint inbound `entityRef`s. Deletion writes a tombstone marker so sync propagates the removal deterministically rather than resurrecting the record on the next merge; any references left dangling are surfaced in the repair view. This firms up the v1 default that Spec 01 left as a recommendation — noted there as a forward dependency.

### 3.3 Derived-Value Operations

#### `compute`
Evaluate a **safe arithmetic or string expression** over context variables and bind the result to a new variable. The expression language is a strict subset — the complete grammar is in §3.7.

```json
{
  "op": "compute",
  "expr": "sum({recentMeals}.calories)",
  "into": "totalCalories"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `op` | `"compute"` | yes | |
| `expr` | string | yes | Expression in the compute grammar (§3.7). |
| `into` | string | yes | Variable the result is bound to. |

#### `format`
Produce a string value from a template, used for confirmation messages, summaries, and notification bodies. A `format` step is the **sole** home of the spoken confirmation (`G-03`; the type-level `nluHints.confirmationTemplate` is retired, Spec 01 §12.1).

```json
{
  "op": "format",
  "template": "Logged {meal.mealType, default: 'a meal'}: {meal.description}. {totalCalories, suffix: ' kcal', omitIfNull: true}",
  "into": "confirmationText"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `op` | `"format"` | yes | |
| `template` | string | yes | Template string. Interpolation tokens: `{varName}`, `{varName, default: 'x'}`, `{varName, suffix: ' unit', omitIfNull: true}`. |
| `into` | string | yes | |

#### `set`
Bind a literal value or copy a context variable to a new variable name. The primary tool for renaming, defaulting, and type-coercing values within the execution context.

```json
{ "op": "set", "var": "windowStart", "value": "{sevenDaysAgo}" }
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `op` | `"set"` | yes | |
| `var` | string | yes | Name of the context variable to set. |
| `value` | any | yes | A literal value (string, number, boolean, null) or a `{variableName}` reference. |

### 3.4 Control Flow Operations

Control flow in the Skill DSL is intentionally limited. There are no general loops or arbitrary `goto` jumps. The interpreter provides two flow constructs.

#### `branch`
Choose between two named step-list labels based on a boolean condition. `branch` is strictly binary (`ifTrue`/`ifFalse`); a multi-way decision is expressed by chaining — the `ifFalse` label's step list begins with another `branch`. (A dedicated multi-way `match` op is deferred, §10 Q11; chaining covers v1 and keeps the vocabulary minimal.) When resolving a `branch`, the interpreter records which label it took in the execution journal (§5) so the condition is not re-evaluated on resume.

```json
{
  "op": "branch",
  "condition": "{capturedCalories} != null",
  "ifTrue": "with_calories",
  "ifFalse": "without_calories"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `op` | `"branch"` | yes | |
| `condition` | string | yes | A boolean expression in the branch-condition grammar (§3.8). |
| `ifTrue` | string | yes | Label of the step list to execute when the condition is true. |
| `ifFalse` | string | yes | Label of the step list to execute when the condition is false. |

Labels reference named step sequences defined at the top level of the `steps` key (see §3.5).

#### `foreach`
Iterate over a list-valued context variable and execute a named step-list label once per element. The current element is bound to a specified variable name for the duration of each iteration. Iteration depth is capped at 1 — a `foreach` inside a `foreach` is a validation error at authoring time and at registration.

```json
{
  "op": "foreach",
  "over": "recentMeals",
  "as": "meal",
  "do": "process_meal"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `op` | `"foreach"` | yes | |
| `over` | string | yes | Name of a list-valued context variable. |
| `as` | string | yes | Name the current element is bound to within each iteration. |
| `do` | string | yes | Label of the step list to execute per element. |
| `limit` | integer | no | Maximum iterations. Default 100. Safety cap — an unconstrained list processed by a `foreach` is a denial-of-service risk on large datasets. If the iterable exceeds `limit`, resolve halts with an error rather than silently truncating (silent truncation would drop writes the user never sees). |

`foreach` is for **per-element operations** — most often producing one write per element (e.g. a reminder for each of several contacts). It is **not** the tool for aggregation: because each iteration re-binds the same context variables, a value computed in the loop body does not accumulate across iterations. Aggregation (totals, averages, counts) is expressed directly with the list functions in the `compute` grammar (§3.7: `sum`, `avg`, `count`, `count_where`) over a list-valued variable, with no loop. During resolve, a `foreach` is fully unrolled and every write in its body is added to the action plan (§4.1), so the confirmation shows all N writes.

### 3.5 Step Lists and Labels

A skill's `steps` field is an object (not a plain array) mapping string labels to arrays of step objects. The interpreter always begins execution at the label `"main"`, which must be present.

```json
{
  "steps": {
    "main": [
      { "op": "read_one", ... },
      { "op": "branch", "condition": "...", "ifTrue": "with_calories", "ifFalse": "without_calories" }
    ],
    "with_calories": [
      { "op": "write_record", ... },
      { "op": "format", ... }
    ],
    "without_calories": [
      { "op": "set", "var": "capturedCalories", "value": null },
      { "op": "write_record", ... },
      { "op": "format", ... }
    ],
    "process_meal": [
      { "op": "compute", ... }
    ]
  }
}
```

A step list may not reference itself (recursion is a validation error). The total number of unique labels is capped at 32 per skill. A label referenced by `branch.ifTrue`, `branch.ifFalse`, or `foreach.do` must exist in the `steps` object — this is checked at registration and at the start of the resolve phase (§4).

### 3.6 Filter Expressions

`read_many` and `read_related` accept a `filter` object. Keys are attribute names (dot-paths for composite attributes); values are either a literal (exact match) or a comparison object:

| Operator key | Semantics |
|---|---|
| `eq` | Equal |
| `neq` | Not equal |
| `gt` / `gte` | Greater than / greater than or equal |
| `lt` / `lte` | Less than / less than or equal |
| `in` | Value is one of a literal array |
| `contains` | String contains substring (case-insensitive) |
| `null` | `true` → must be null; `false` → must be non-null |

Multiple keys at the same level are combined with AND. OR is expressed as `"_or": [filterA, filterB]`. Nesting `_or` inside another `_or` is not permitted — if the filter logic requires that, model it as two separate `read_many` steps and merge in a `compute`.

All values in a filter may be `{variableName}` references, resolved at runtime from the execution context.

**Null-valued filter entries are dropped.** A filter entry whose resolved `{variableName}` value is null is **omitted from the filter** — it matches all records, not records where the field is null. This is what lets one skill serve both the filtered and unfiltered case (`query-last-interaction` with no `medium` slot means "any contact method", Spec 05 §10 E4). To match records where a field *is* null, use the explicit `null` operator (`{"medium": {"null": true}}`) — that intent must be written literally, never expressed through an unbound variable.

### 3.7 Compute Expression Grammar

> **⚠ Superseded by the §3 v0 normative-dialect block (`G-41`).** v0 `compute` is a
> **structured** op — `{"op":"compute","fn":<name>,"args":[…],"into":"var"}` with a closed
> `fn` set — NOT the string-expression grammar below. The prose here is retained as intent;
> the §3 block is the normative wire format.

`compute` expressions are evaluated by a small, deterministic expression engine built into the interpreter. The engine supports:

**Numeric operations:** `sum(list.field)`, `avg(list.field)`, `min(list.field)`, `max(list.field)`, `count(list)`, `count_where(list, "field == value")`, arithmetic operators `+ - * /`, integer division `//`, modulo `%`, and grouping with parentheses. Division by zero yields `null`.

**Decimal preservation.** Arithmetic and aggregation over `decimal` operands (Spec 01 §3 — money and other exact values) is performed in **exact base-10 decimal**, never coerced to IEEE-754 `double`. `sum`/`avg`/`min`/`max` over a `decimal` field return a `decimal`; `+ - * /` on `decimal` operands return a `decimal`. Mixing a `decimal` and a `number` operand **promotes the `number` to decimal** and returns a `decimal` (so an exact ledger total is never silently corrupted by a stray float). This closes the correctness gap that would otherwise undo Spec 01's `decimal` decision at the compute layer: a `ledger` skill summing spending must stay exact. `avg` and `/` that do not terminate in base-10 are rounded to a fixed scale (default 10 fractional digits, half-even) — division is the one place exactness is impossible.

**Empty-list results.** `sum` / `count` / `count_where` over an empty list return `0`; `avg` / `min` / `max` over an empty list return `null` (consistent with division-by-zero yielding `null`).

**String operations:** `concat(a, b, ...)`, `trim(str)`, `upper(str)`, `lower(str)`, `length(str)`.

**Date/time operations:** `now()`, `today()`, `days_between(a, b)`, `add_days(date, n)`, `format_date(date, "YYYY-MM-DD")`. `now()` and `today()` return the **frozen** resolve-start values — the same `{now}` (UTC datetime) and `{today}` (local date, device timezone; Spec 01 §12 Q8) system inputs bound at the top of the resolve phase (§4.1) — **not** wall-clock at call time. Freezing them makes an action plan reproducible: a re-verify (§4.2) that re-resolves the same inputs yields the same plan, and a plan built across many steps cannot straddle a midnight or minute boundary.

**Sequence operations (resolve-stage addition, `G-21`).** `streak(list, dateField) → { current, longest }` computes the current and longest runs of **consecutive calendar days** present in a list of dated records — the basis of `show-streak` (F-18). Consecutive-run logic cannot be expressed as `sum`/`count`, so it is a first-class function, not a composition. *(Anniversary / next-occurrence date math — `next_anniversary`, F-19 — lives in the deterministic date resolver (Spec 03 §6.2), not here, because record-anchored dates are resolved to a literal before a skill runs.)*

**Conditional:** `if(condition, thenValue, elseValue)`. Condition is a boolean sub-expression.

**Null propagation.** A `{variableName}` that is null, or a field access on a null value (e.g. `{contact}.name` when `read_one` bound `{contact}` to null), evaluates to null rather than raising — dereferencing is null-safe throughout. Null operands propagate: arithmetic with a null operand yields null; `concat` skips null operands; a `format` token over a null value uses its `default`/`omitIfNull` behavior (§3.3). This matters because voice capture routinely omits optional fields, and a skill must degrade to a partial result, not an error.

**All operands** are literals, `{variableName}` references, or nested function calls. There are no user-defined functions, no closures, no variable assignment inside an expression, and no access to anything outside the execution context.

The engine is a hand-written recursive-descent parser over this grammar; no `eval` or dynamic code generation is used.

### 3.8 Branch Condition Grammar

> **⚠ Superseded by the §3 v0 normative-dialect block (`G-41`).** v0 branch conditions are a
> **structured object** — one of `{"isNull":"var"}`, `{"notNull":"var"}`, `{"gte":[a,b]}`,
> `{"eq":[a,b]}`, `{"contains":[hay,needle]}` — NOT the string boolean-expression grammar
> below. The `&&`/`||`/`!` composition and comparison operators here are not implemented; the
> §3 block is the normative form.

Branch conditions are boolean expressions:

- Comparison: `{var} == value`, `{var} != value`, `{var} > value`, `{var} < value`, `{var} >= value`, `{var} <= value`
- Null checks: `{var} == null`, `{var} != null`
- List checks: `{var}.length > n`, `{var}.contains({otherVar})`
- Logical: `&&`, `||`, `!`, grouped with parentheses

No function calls or arithmetic inside a branch condition. If derived numeric values are needed for a condition, compute them first with a `compute` step and then branch on the result.

---

## 4. The Resolve/Execute Split

Skill execution is divided into two strictly separated phases: **Resolve** and **Execute**. The split survives the move to act-then-describe (§7.1) unchanged, because its value was never only the pre-action pause. It serves four goals: it makes the interpreter safe to suspend and resume; it produces the fully-resolved, validated plan whose `format` output *is* the after-the-fact description (so what the user is told matches what was written); it is the point at which a **gated** execution (an automation plan held for review, or the deletion meta-flow) shows its complete plan for approval; and it provides the natural checkpoint for safety analysis (§7.3). Where the prose below says "before the confirmation is shown" or "the confirmation-first guarantee," read it as "before the plan is committed and described" — the completeness-and-validation-before-execute discipline is identical whether or not an approval pause follows.

### 4.1 Resolve Phase

The resolve phase reads and plans; it produces no side effects.

1. **Parse and validate** the skill file against the DSL schema. Any structural error halts with an authoring-time error — not a runtime error.
2. **Hydrate the execution context** with the inputs the NLU layer extracted (slot fills from the user's utterance) and system-provided values (`{now}`, `{today}`, user identity). The system values are **frozen at this moment** and recorded in the journal (§4.4); every re-verify and resume reuses them rather than re-reading the clock.
3. **Walk the step list** starting from `"main"`. For each step:
   - For read ops (`read_one`, `read_many`, `read_related` — and `read_reference`, which is served from the shipped ReferenceStore rather than the StorageRepository): execute the read against the StorageRepository (served from the in-memory, decrypted object store — Spec 01 §8.2 — so filters over `sensitive` attributes work). The result is bound into the context. **Reads are permitted in the resolve phase** because they have no side effects and their results are needed to evaluate branch conditions.
   - For `branch`: evaluate the condition, record the resolution in the execution journal (§5), and recursively resolve the chosen label's steps.
   - For `foreach`: resolve the iterable from context (its length is known now, because all reads happen in resolve) and **fully unroll it** — resolve the `do` label's steps once per element, up to the iteration `limit`. Every pending write produced inside the loop body is appended to the action plan. Partial unrolling would break the plan-completeness discipline (§4.3): the *complete* set of writes must be resolved and validated before execute — so the after-the-fact description covers all N writes and a gated path (automation review, §7.5) approves all N, not an extrapolation from the first iteration.
   - For write ops (`write_record`, `delete_record`): **do not execute**. Fully resolve every field value to a literal; for a create, **mint the record `id` now** and freeze it into the plan (§4.4). Then **validate the pending write against the target type's schema** — for a create, all required attributes present (Spec 01 §3.1); for an update (merge), only the changed attributes, and no required attribute set to null; in both cases values conform to their `valueType`, `enum` values are members of `enumValues`, and the append-only-`id` rule (§3.2) holds. A validation failure halts resolve *before* the confirmation is shown, so the user never approves a plan that cannot execute. On success, append the validated pending write to the action plan.
   - For `compute`, `format`, `set`: evaluate and bind. These are safe in the resolve phase (pure functions over context, no I/O).
4. **Produce the action plan**: an ordered list of all pending write operations, with all field values fully resolved into literals (no remaining `{variable}` tokens) and validated against their target types. This is exactly what the confirmation UI displays and what the execute phase applies — nothing is re-derived after approval.

The resolve phase may read from storage but **never writes**. If the resolve phase encounters an unresolvable variable, a type that is not in the registry, a filter the StorageRepository cannot evaluate, or a pending write that fails schema validation, it halts with a structured error.

### 4.2 Execute Phase

The execute phase applies the action plan produced by the resolve phase.

1. **Approval gate (only where one exists).** An **interactive** execution has no approval pause — resolve flows straight into execute and the result is described afterward (act-then-describe, Spec 05 §3.1). An approval gate exists in exactly two cases: an **unattended automation** execution that produced writes is held as an `awaiting_confirmation` entry and proceeds only on the user's Review-Feed approval (§7.5, Spec 04 §3.9); and the **type/skill-deletion** meta-flow pre-confirms (Spec 05 §24). Where a gate exists and the user declines, execution is cancelled — the action plan is discarded, no writes have occurred.
2. **Re-verify the context** has not been invalidated by time or concurrent writes. If more than `maxContextAgeSeconds` (default: 60) has elapsed since the resolve phase, or if any record read during resolve has been modified since (detected by comparing the record's **derived** `lastModified` — `max(stamps).ms`, Spec 06 §4.1 D5; records store no `lastModified` field, so the comparison is over the derived value — semantics unchanged), the resolve phase is re-run — **deterministically**: it reuses the frozen system inputs (`now`, `today`, `userId`) and the minted create-`id`s from the original resolve (§4.4), so only a change in stored *data*, not the passage of time, can change the plan. **If the re-resolved action plan differs from the plan first resolved** — a structural diff over the ordered pending writes, comparing op, `typeId`, target `id` (for updates and deletes) and resolved field values, but **ignoring interpreter-minted create `id`s** (§4.4) — what happens depends on whether this execution is gated. For an **interactive** execution (no approval gate; resolve→execute is immediate, so a differing plan is rare — only a concurrent automation write in the sub-second window could cause it), the freshly re-resolved plan simply executes and is described (act-then-describe): what the user is *told* always matches what was written, which is the interactive form of the source-of-truth rule. For a **gated** execution — an automation plan held for Review-Feed approval (§7.5), or the deletion meta-flow — execution does **not** proceed on the stale approval: the user is re-shown the new plan and must re-approve, so what executes is always exactly what was last approved. Re-resolution is bounded to `maxReResolves` (default 3); exceeding it aborts with a "data is changing faster than it can be confirmed" error rather than looping.
3. **Execute each pending write** in the action plan, in order. Each write is issued to the StorageRepository as a single, atomic operation. (Cross-write atomicity — all-or-nothing over the group — is not yet provided; see §10 Q7.)
4. **Emit the skill-completed event** with the resolved value of the skill's designated `confirmationVar` (default variable name `confirmationText`, produced by a `format` step; §7.1) for the UI to display.

### 4.3 Why Reads Are Permitted in Resolve

Allowing reads in the resolve phase means the interpreter can evaluate branch conditions that depend on stored data (e.g., "has this contact been logged in the last 30 days?") before showing the user a confirmation. The alternative — deferring all reads to execute — would require showing a confirmation before knowing which branch is taken, which produces uninformative confirmations ("this skill will do something, approve?").

The cost is that resolve phase reads are not snapshot-consistent with the execute phase. The re-verify step (§4.2 step 2) mitigates this by catching modifications between the two phases. It does not provide serializable isolation — that is a deliberate trade-off: Plenara is a personal productivity app, not a financial ledger, and the complexity of full snapshot isolation is not warranted.

### 4.4 Resolve Determinism, Frozen Values, and Idempotent Resume

A skill can be suspended between resolve and execute — the user walks away mid-confirmation, or the OS kills the backgrounded app — and must resume without redoing work or duplicating writes (§5). That safety rests on a single property: **resolving the same execution twice produces the same action plan.** Three rules guarantee it, and a fourth handles resume across an interpreter update.

**1. System inputs are frozen once, at the first resolve.** `now`, `today`, and `userId` are captured at the top of the first resolve pass and stored in the execution journal (§5.3). Every later re-resolve of that execution — a re-verify (§4.2) or a resume — reuses those frozen values instead of reading the wall clock again. Without this, a `loggedAt: {now}` write would drift by however long the user took to approve; the re-verify diff would flag a spurious change; and the user would be re-prompted every time they paused past `maxContextAgeSeconds`. Freezing also yields the semantically better answer: a meal is stamped with when it was *captured*, not when the confirmation was finally tapped.

**2. Create-`id`s are minted at resolve and frozen.** When a `write_record` omits `id`, the interpreter mints the UUID during resolve (§4.1) and writes it into the action plan — not at execute time. A resumed or retried execute therefore re-issues each create with the *same* `id`; because the storage write is an upsert on `id`, re-issue is idempotent. An app killed after applying two of five writes resumes and applies the remaining three without recreating the first two (§5.4).

**3. The re-verify diff ignores minted `id`s.** A minted `id` is an interpreter-generated surrogate the user never sees, so the §4.2 structural diff compares op, `typeId`, target `id` (for updates and deletes, which reference a *real* existing record) and resolved field values — but never the minted create-`id`. Otherwise every re-resolve would "differ" by fresh UUIDs and force endless re-approval. A genuine change in stored data still changes a field value or a target `id`, which the diff does catch.

**4. The compiled chain stays decodable; the symbolic source is the fallback.** The action plan is persisted in the compiled numeric form (§3.0, §5.3), tagged with a `compiledFormVersion`. The append-only discipline (§3.0) covers not only opcodes but **operand encodings** — an existing op's packed layout is never changed; only new ops with new encodings are added — so a chain written by one interpreter version is always decodable by the same-or-newer version that resumes it (resume is same-device, and an installed app only moves forward). `compiledFormVersion` is thus a safety assertion, not a routine branch. In the should-never-happen case that a chain fails to decode, the fallback is phase-dependent: in `awaiting_confirmation` (nothing written yet) the execution is re-resolved fresh from the still-present symbolic source and re-approved — fresh minted `id`s are harmless because no records exist yet; in the brief `executing` phase (which does not realistically span an app update, since execute applies a handful of writes in sequence) an undecodable chain is surfaced for repair rather than guessed at. A `skillSchemaVersion` mismatch — the *definition* changed — invalidates the entry outright, since a changed definition cannot be mapped onto an old approval. The symbolic source on disk is the durable source of truth; the compiled chain is a fast-path cache of it.

**Executions are serial per device.** The interpreter runs one execution's execute phase at a time on a given device; a second invocation queues behind it. This is not a scaling limit for a single-user personal app, and it keeps the re-verify model sound — two concurrent execute phases could interleave writes that invalidate each other's `readSnapshot` mid-flight. Cross-*device* concurrency is a sync concern, not an interpreter one (§5.2, §10 Q1).

---

## 5. The Execution Journal (Suspend/Resume)

### 5.1 What This Section Solves — and What It Defers

Two distinct mechanisms were conflated under one "flow table" in v0.1. They are separated here:

1. **Execution journal** (built now). The interpreter must be safe to **suspend mid-execution**: a user may approve a confirmation, dismiss the app, and return hours later; the app may be killed by the OS between resolve and execute. On resume the interpreter must continue exactly where it left off — same branch resolutions, same remaining `foreach` iterations, same approved action plan. That requires a durable record of one in-flight execution's state. This section defines it.

2. **Plan cache** (deferred). Reusing a previously-resolved plan across *different* invocations that share an (intent, type, slot-shape) signature — the research-doc §4.9 flow-table optimization — is a performance feature, not a correctness requirement. Per the locked project decision ("build the resolve/execute split now; defer the actual cache + invalidation until usage justifies"), the cache is **not built in v1**. §5.5 records the hook for it. Collapsing the two — as v0.1 did, with a `contextHash` "cache hit" that skipped resolve — shipped the deferred optimization by accident and, worse, cached user-data-bearing plans in a synced file. Both are undone here.

### 5.2 Storage: Device-Local, Never Synced, Encrypted at Rest

The execution journal does **not** live in the skill file, and it does **not** live in the synced Plenara folder. It lives in **device-local application storage** (platform app-support directory), for three reasons:

- **Sync correctness.** The storage model is per-record JSON files with whole-file, last-writer-wins sync (Spec 01 §8, §7.5) — there is no field-level JSON merge. v0.1's claim that two devices' concurrent journal entries would "merge as independent entries" is false under that model; concurrent writes to one shared file conflict. Keeping the journal device-local removes the conflict entirely: an execution is inherently tied to the device the user is interacting with, and resume is a same-device operation.
- **Privacy.** A resolved action plan contains literal field values lifted from records — including values from `sensitive` attributes (a journal-entry body, private contact notes). The encryption model guarantees skill files are *always plaintext* (Spec 01 §8.2). Writing resolved user data into the skill file would leak sensitive content into a file that is never encrypted. The journal is instead **encrypted at rest** using the same platform key store as sensitive instance records (Spec 01 §8.2).
- **Definition stability.** With execution state out of the skill file, the file changes only when the definition is edited, so `lastModified` stays meaningful and executions no longer generate sync churn (a rewrite of `log-meal.json` on every meal).

Location: `[app-support]/plenara/executions/{executionId}.json` (encrypted). One file per in-flight execution.

> **v1 posture (suite-sync CS-17):** "encrypted at rest" activates when Spec 01 §8.7 ships; until then `CryptoBox` is a pass-through and the journal is **plaintext device-local** (Spec 04 §3.1's posture note). Device-local placement — the sync-correctness and definition-stability arguments above — holds regardless.

### 5.3 Structure

An execution-journal entry records one in-flight execution:

```json
{
  "executionId": "exec_7f3a…",
  "skillId": "add-contact-fact",
  "skillSchemaVersion": 1,
  "compiledFormVersion": 1,
  "origin": "interactive",
  "phase": "awaiting_confirmation",
  "frozenInputs": { "now": "2026-07-05T20:15:00Z", "today": "2026-07-05", "userId": "u_1" },
  "slots": { "subjectName": "Mia", "fact": "allergic to peanuts", "relatedToId": "cnt_sarah", "relationType": "daughter" },
  "readSnapshot": [ { "id": "cnt_sarah", "lastModified": "2026-07-01T09:00:00Z" } ],
  "branches": { "main": "create_subject" },
  "foreachProgress": {},
  "actionPlan": [ "‹compiled numeric writes: create cnt_mia, rel_x, fct_y›" ],
  "beforeImages": [],
  "createdAt": "2026-07-05T20:15:00Z",
  "expiresAt": "2026-07-05T20:20:00Z"
}
```

| Field | Purpose |
|---|---|
| `phase` | `awaiting_confirmation` \| `executing` \| `done` — drives resume (§4.2, Spec 04 §7). |
| `frozenInputs` | `now`/`today`/`userId` captured at first resolve (§4.4); reused on every re-resolve/resume. |
| `slots` | The NLU slot fills that hydrated the context. |
| `readSnapshot` | `(id, lastModified)` of every record read during resolve — the re-verify basis (§4.2). The snapshotted `lastModified` is the record's *derived* value (`max(stamps).ms`, Spec 06 §4.1 D5), captured at resolve time. |
| `branches` / `foreachProgress` | Which label each `branch` took; how far each `foreach` got — so resume doesn't re-decide/re-iterate. |
| `actionPlan` | The compiled numeric write chain (§3.0) — the source of the description and the writes. |
| `beforeImages` | Captured at execute (Spec 04 §3.3); the basis for `undo`. Empty until `executing`→`done`. |
| `origin` | `interactive` \| `automation` — the orchestrator uses this to decide whether an approval gate applies (§4.2, §7.5). |

One entry per in-flight execution at `[app-support]/plenara/executions/{executionId}.json` (encrypted); a `done` entry lingers only until its undo window closes (Spec 04 §3.11).

### 5.4 Before-images and reap-at-done — the undo backbone

Act-then-describe (Spec 05 §3.1) is only safe because undo is reliable, and undo is reliable because every write captures a **before-image** at execute. This is the mechanism `beforeImages` (§5.3) holds.

- **Capture (at `executing`, Spec 04 §3.3).** Each write op records what it will overwrite, keyed by op index + recordId: `write_record` create → a `{absent}` marker (undo = delete the minted id); `write_record`/`set` on an existing record → the prior field value(s); `delete_record` → the **full** prior record. Reads/computes/formats capture nothing (they don't write). Capture happens inside the serial-execute step, so a plan's before-image set is a consistent snapshot.
- **Undo = reverse replay, deterministic, no model.** `undo` (Spec 03 system command) replays the set in reverse op order: a create is deleted, an update is restored to its prior value, a delete is re-written from the captured record. A whole turn's multi-write plan reverses **atomically** — all before-images or none — so a compound turn ("log the run and bump my streak") never half-undoes.
- **Optimistic-concurrency guard.** Before restoring, undo checks the live record still matches the after-image (Spec 04 §4.5 "record changed under you"). If it diverged (a later turn or a synced edit touched it), undo does not clobber — it surfaces "this changed since; undo anyway / keep" (P7, no silent failure).
- **Reap-at-done.** Before-images can hold sensitive prior values, and the journal is device-local/encrypted (§5.2) but still finite. A `done` entry and its before-images are **reaped when the undo window closes** (Spec 04 §3.11) or a newer turn supersedes it — the images exist exactly as long as undo can reach them, no longer. Automation-origin entries (`origin: automation`) follow the Review-Feed retention rule instead (§7.5).

### 5.5 The deferred plan cache (recorded, not built in v1)

A resolved `actionPlan` (the numeric write chain, §3.0) could in principle be cached per `(skillId, slot-shape)` so a repeat invocation skips re-resolution. **This is deliberately deferred — not a v1 mechanism** (the `deferredPlanCache` references elsewhere resolve here):
- Resolution is already deterministic and cheap (no model call), so the cache saves little.
- A cached plan risks **staleness** — a type/skill edit or a changed record can invalidate it; the project's "never cache generative effects" discipline (§5.5-adjacent; Spec 03 §5.3) extends to "never cache a plan whose inputs may have shifted."
- The expensive part — the *routing/inference* decision — is already cached by the corpus fast-path (Spec 03 §5), which stores slot *shapes* and the route, never the resolved plan or slot *values*.

So plan-caching is logged as a future option gated on evidence that resolution latency actually matters, not a launch feature.

---

## 6. The Authoring Flow *(resolve-stage addition)*

*Added by the Phase-3 resolve stage ([`05b-gap-register.md`](../05b-gap-register.md)), resolving **G-06, G-17, G-18**. How Claude produces a type/skill once, and how the deterministic validators gate it before it becomes data. Owned by `AuthoringService` (Spec 04 §3.7); reached from a `define_type`/`define_skill` meta-intent (Spec 03 §2.2).*

### 6.1 Trigger & tier gate
A `define_type` (novel domain) or `define_skill` (existing type, missing operation) meta-intent reaches the orchestrator. Authoring is **BYOK-gated and detached** (Spec 04 §3.7): free tier → the §3.6 upgrade prompt, no call; offline → a **draft** (§6.5). Otherwise the orchestrator calls `AuthoringService.authorType`/`authorSkill`, which returns immediately with a `Detached` handle while the multi-second Claude call runs.

### 6.2 Pre-authoring reconciliation (`define_type` only)
Before authoring a *type*, run the similarity search (Spec 01 §6.1): `similarTo(candidateDescription)` → any hit > 0.85 is surfaced to Claude, which reuses/extends rather than creating a near-duplicate; a strong hit triggers the one allowed clarify ("add to your existing X, or keep separate?"). `define_skill` against an existing type skips this (there is nothing to reconcile — the type is fixed).

### 6.3 The author call and its constraints
`ClaudeClient.author` receives the request + reconciliation candidates + the closed-vocabulary contract — which includes Spec 07's closed archetype id set for `presentation.archetype` (the *real* ids: `ledger`, not the retired `grouped-aggregation` placeholder of `G-31` — Spec 01 §9.1, suite-sync CS-21) — and must return **declarative JSON only** — a `type` and/or `skill` definition + a `safetyAssessment`. The prompt is built from schema/metadata, never from user record content (the §7.3 prompt-injection defense).

**Reliability scales inversely with skill complexity — and the fix is structured output (`G-29`, findings §10.2).** All seven measured models authored a *simple* single-write skill as valid closed-vocabulary DSL (the core P2.7 feasibility result). But on *complex* multi-step skills (a computed-write, a grouped aggregation) all but Opus 4.7/4.8 **drifted the step schema** — right logic, wrong serialization (`{"step":…,"expression":…}` instead of the DSL's `{"op":…,"expr":…,"into":…}`). The vocabulary is not the limit (grouped aggregation *is* expressible); serialization discipline is. So the author call **(a)** uses **structured / JSON-schema-constrained output** pinning the exact step schema, **(b)** **pins a capable authoring model** (Opus 4.7/4.8 — the pin of record, its cost envelope, and the accepted v0 Haiku interim are owned by Spec 08 §3.2/D3), and **(c)** leans on the §6.4 validate→retry loop to catch any residual drift.

### 6.4 Validation — the gate (`G-17`)
The returned artifact is **never registered until it passes deterministic validation** (this is the `validate_authoring.py` gate proven in Phase 3):

1. **Structural** — parses; required fields present; `typeId`/`skillId` well-formed.
2. **Closed-vocabulary** — every step `op` ∈ the fixed set (§3); no invented ops.
3. **Capability closure** — every `write_record`/`delete_record` `typeId` ∈ the skill's declared `writes`; every read type ∈ `reads` (§2.2, §6.3-legacy).
4. **Variable closure** — every `{var}` reference is bound (an input, an ambient system value, or a prior `into`).
5. **Semantic `entityRef` closure (NEW, `G-17`)** — every field written to an `entityRef` attribute must be fed by a **resolved id**: a variable bound by a `read_one`/`read_related`/`write_record` (a *record* reference), or a slot the NLU layer resolves to an id (Spec 03 §6, `G-12`). A skill that writes an `entityRef` from a **raw name** slot is **rejected** — it would parse and pass structural validation yet fail at first use (the P-01 finding). **This must be a *static dataflow* check on the skill definition, not a runtime one — the Phase-0 spike (`spikes/dsl-meta-schema/`) proved a naïve runtime `isinstance(id, String)` check silently passes the bad case, because a resolved id (`contact-0002`) and a raw name (`Mia`) are *both strings* and indistinguishable at runtime.** So §6.4 traces, at authoring time, whether each `entity`-field write's value is a `{ref: recordVar}`/`{field:[recordVar,'id']}` whose source is a read/write step (accept) or a bare input `{var}` (reject). *This is the check the vertical slice proved the old validator lacked, and the spike proved must be static.*
6. **Safety** — the `safetyAssessment` is split into validator-verified facts vs Claude prose (§7.4); stored to `audit/` on activation.

On failure → **one automatic re-author** with the structured error; a second failure → "I saved a draft — try again or refine" (draft stored inert; Spec 05 §14 E3). An invalid artifact is never half-registered.

### 6.5 Preview → refine → activate (`G-18`)
A passing artifact is **previewed, not committed**: the app describes it and waits. The user **refines** across turns ("add a sleep field"); each refinement is a follow-up author call, and the **draft accumulates in memory (not on disk), up to five turns** (Spec 05 §14 E6). **Nothing is registered until the user says "activate."** On activate: the type/skill files are written, the safety assessment stored, and the capability is live — indexed in the `CapabilityIndex` (Spec 01 §5.4) so routing finds it exactly like a seed. This preview/commit boundary is *not* a fourth-wall break (Spec 05 §3.1) — it is a user-driven commit of a collaborative design. Offline or free-tier authoring produces a `Drafted` outcome queued for activation when a key/network is present (Spec 04 §6.3).

---

## 7. Confirmation & Safety

- **Confirmation is act-then-describe** (Spec 05 §3.1): interactive skills do not pause for approval; they execute and describe. The spoken line is the skill's resolved `confirmationText` — produced by a `format` step (§3.3), the **sole** home for it (`G-03`; the type-level `nluHints.confirmationTemplate` is retired, Spec 01 §12.1). The standard construction idiom is `compute` (build any date/number labels via `format_date`, since `format` cannot, `G-05`) → `write_record` → `format`.
- **The two surviving gates** are unattended-automation writes (held for Review-Feed approval, §7.5) and non-undoable type/skill **deletion** (pre-action confirm, Spec 05 §24). Everything else is act-then-describe with `undo` as the net.
- **`dangerLevel`** (`safe`/`caution`/`destructive`) classifies what a skill can change; `destructive` is required for `delete_record` and forbidden for automations.
- **Prompt-injection defense (§7.3):** authoring and classification prompts are assembled from **type/skill metadata**, never from the content of user records, so a malicious value in a note cannot rewrite a capability.
- **The safety gate is the model — but not a *single* model (`G-30`, findings §10.3).** Claude is the authoring safety gate (Spec 05 §14 E2), reliable on egregious requests (covert-surveillance authoring was declined by all seven measured models). But it is **model/version-dependent on borderline cases** — a disordered-eating tracker was declined by five models and *authored* by two. So authoring does not trust one model: it adds **(a)** a **dedicated safety-classification pass** on the request, independent of the authoring model, and **(b)** an **app-side policy layer** that hard-blocks known-sensitive domains — self-harm / disordered eating, covert surveillance of another person, medical diagnosis, financial transactions, impersonation of a third party — regardless of what the authoring model returns. **Record-integrity** (never fabricate the past to inflate a streak, DP-05 — distinct from a legitimate backdated log of a *real* event) and the **non-disablable privacy invariants** (per-session journal consent is not user-disablable, DP-07) live in this layer too.

### 7.6 The safety architecture — defense-in-depth (`G-30`)

> **⚠ BUILD STATUS (suite-sync CS-07 — honesty banner).** The three-layer model below is the **TARGET** architecture, not the shipped state. **Layer 1 + the deterministic invariants: BUILT** (v0 `session.dart`). **Layers 2–3: DESIGNED, deferred** to the v2 authoring build-out (Spec 10 §6.4, R-04; gap G-30) — until they land, the borderline-authoring gate is Layer 1 plus a *single* model's refusal, which is exactly the DP-08 measured failure mode the layers exist to close. **Hard gate (adopting Spec 10 rec 2): no user-facing authoring beyond dogfood ships without Layer 3.** Do not cite this section as a shipped mitigation.

The measurement that forces this (findings §10.3): the authoring model is a *good* safety gate on egregious requests (covert surveillance declined by all 7 models) but **model/version-dependent on borderline ones** (a disordered-eating tracker was declined by 5 and *authored* by 2 — and it was **not monotonic in version**). A single-model gate is therefore not enough. Plenara uses **three layers plus deterministic invariants**, so no single model's blind spot can pass a harmful capability:

**Layer 1 — App-side policy pre-filter (deterministic, before any Claude call).** A fixed, binary-shipped ruleset (recognized by the same local/rule machinery as OOD detection, `G-19`) that hard-blocks a small set of **known-harmful request *shapes*** *before* an authoring call is even spent:
- covert monitoring of another person ("track my partner's location… without them knowing"),
- self-harm / disordered-eating tooling (**punitive** calorie/weight framing — "warn me… so I can cut down harder"),
- medical diagnosis ("what's wrong with me"),
- executing financial transactions (purchases, payments),
- impersonation of a named third party.
On a match → the app declines with a caring surface (Spec 05 §14 E2 shape), no cloud call. This is the **version-independent floor** — the two most dangerous domains (covert surveillance, self-harm) never depend on a model's judgment. **Precision matters:** the rule keys on the harmful *framing*, not the domain — a non-punitive calorie tracker for a stated weight goal is *not* blocked (the DP-08 data shows "cut down harder" + punitive alerts is the signal, not "calorie").

**Layer 2 — The authoring model's `safetyAssessment` (the model gate).** Claude's author call returns `level: safe|caution|decline` (§6.3); a `decline` stops authoring and relays the model's caring message. Catches nuance the ruleset misses — but is **not trusted alone**.

**Layer 3 — An independent safety review (second opinion, before activation).** After validation (§6.4) and before activation (§6.5), a **separate** cheap call (Haiku, or a pinned reliably-refusing model) reviews the *original request + the authored artifact* **independently of the authoring model**. This is exactly the DP-08 failure's antidote: when the authoring model both builds *and* self-clears a borderline capability (opus-4.6 did), a different reviewer that reliably declines provides the veto. **Disagreement → decline.** Cost is negligible (~$0.0003, only on authoring turns).

**Composition with §6:** `Layer 1 (pre-filter)` → author (§6.3) → validate (§6.4) → `Layer 3 (independent review)` → preview → activate (§6.5).

**Deterministic invariants (not model decisions, always enforced):** **record integrity** — the interpreter refuses a write for an event that did not happen to falsify history (DP-05), while a real backdated event (F-17) is fine; **non-disablable privacy** — the per-session journal-to-cloud consent cannot be turned off (DP-07); the app declines requests to weaken it.

**Why layered, not "just a better model":** the finding shows model choice alone is fragile (non-monotonic in version). A deterministic floor (Layer 1) + an independent second opinion (Layer 3) makes the guardrail robust to any single model's blind spot, keeps the worst domains blocked for free, and costs a few hundredths of a cent on the rare authoring turn. The open tuning risk is **false positives** — Layers 1 and 3 must target harmful *intent/framing*, not merely sensitive *topics*, so legitimate health/finance/relationship capabilities still build.

## 8. The No-Executable-Code Constraint

Skills are **data, not code**: the closed vocabulary (§3) is interpreted, never `eval`'d, `dart:mirrors`'d, or dynamically dispatched. This is a correctness *and* platform-compliance requirement (Apple 2.5.2 / Microsoft 10.2.6): the interpreter ships in the binary; capabilities are recombined declarative JSON the reviewer can read (§3.0). Richness comes from **composition** of the primitives, not from primitive complexity — anything the vocabulary cannot express is surfaced as an honest "that would require [network/timer/model]; here's what I can do instead" (§0, P2.8), never smuggled in as code.

---

## 9. Seed Skills *(canonical — resolve-stage addition)*

*Resolves **G-04, G-05, G-13**. The seed set is **defined as the union of the skills the free-tier flows require** (Spec 05 §3.7). Seed skills are `authoredBy:"system"`, `safetyAssessmentId:null`, `schemaVersion:1`. Full JSON for the vertical-set skills is in [`05a-traces.md`](../05a-traces.md); this section is the canonical index + the two shared idioms + the read/query skills.*

### 9.1 Idioms (every seed skill follows these)
- **Confirmation idiom (`G-05`):** `compute` (build labels — `format_date`, `if`/`concat` for optional phrases) → `write_record`(s) → `format` (compose `confirmationText`). `format` never formats a date/number itself.
- **Resolve-or-create-person idiom (`G-12`):** a person-referencing skill takes **both** an optional `…Id` (`entityRef`, NLU-resolved) *and* a `…Name` (`text`). NLU resolves *existing* people (disambiguates >1 before dispatch; passes the id when unique, the name when new). The skill uses the id if present, else `read_one contact{displayName:{…Name}}` → `branch null` → `write_record contact`. After NLU disambiguation a name-`read_one` sees only 0-or-1. Because both id and name are carried, confirmations always have the display name. When one skill resolves *two* people through the fuzzy tier, the idiom adds a de-collision guard before any dependent write (§9.3).
- **Multi-write idiom (`G-13`):** one utterance → N records is sequential `branch`/`write_record` steps in one plan; ids minted at resolve thread across writes (§4.4); the `format` composes one line over the created records; `undo` reverses all N atomically (Spec 05 §3.5).

### 9.2 Canonical seed skills

**The counting rule (suite-sync CS-19).** This table is the canonical *index* of seed-skill shapes, not a headcount: the `log-<tracker>`/`show-streak` rows expand per shipped tracker template (§12.4 lists ten), and the set's membership rule remains "the union the free-tier flows require" (Spec 05 §3.7) — so the concrete skill count varies by snapshot (v0 ships 36 files in `v0/data/skills/` at time of writing). Any spec citing a *number* of seed skills must cite it as test-enumerated against this rule (Spec 09 §4 does), never as a constant of this section.

| skillId | reads | writes | shape |
|---|---|---|---|
| `create-task` | `task` | `task` | capture one or several to-dos (F-01; full JSON in 05a-traces §1A). v0: reads `task` for the open-duplicate check; `dueDate` is future-intent; near/far due-date phrasing — §9.3. |
| `create-reminder` | `contact` | `task` | dated/record-anchored reminder; date resolved by the resolver (Spec 03 §6, `G-14`), skill receives literal `dueAt` (F-19 §3A). |
| `create-recurring-reminder` | — | `task` | writes a `recurrence` RRULE (recurrence parsed by the resolver). |
| `add-contact-fact` | `contact` | `contact`,`contact_fact`,`contact_relationship` | multi-write people fact (F-07; full JSON in 05a-traces §2A). v0 id `remember-person-fact`; fixed write order, de-collision, relationship gating — §9.3. |
| `recall-contact-fact` | `contact`,`contact_fact` | — | read a stored fact (below). |
| `log-interaction` | `contact` | `contact`,`contact_interaction` | dated note on a person (F-02; resolve-or-create person). v0: stores the interaction `kind`; `at` is past-intent, defaulting to today — §9.3. |
| `query-last-interaction` | `contact`,`contact_interaction` | — | "when did I last…" (below). v0 ships the query side as two skills, `last-interaction` + `list-interactions`, both `kind`-aware — §9.3. |
| `instantiate-template` | — | *(system meta-op)* | register a built-in tracker type + bind its bundled skills locally (Spec 05 §6). **Not interpreter-expressible** — see note below. |
| `log-<tracker>` | — | *(tracker type)* | template-bundled log skill (e.g. `log-run`, `log-meal`). |
| `show-streak` | *(tracker type)* | — | compute current/longest streak (read + `compute`). |
| `search-records` | *(all)* | — | system embedding search path, not a per-type skill (Spec 05 §12). |

**`instantiate-template` and `search-records` are system meta-operations, not DSL skills.** The closed vocabulary (§3) writes *records of registered types*; it cannot register a type, bind skills, or run an embedding scan — those are `SchemaRegistry` / retrieval operations. Both entries appear in the seed table because they are **routing targets** (indexed in the `CapabilityIndex` and invoked by voice exactly like a skill), but the orchestrator dispatches them to the registry/search subsystem, not to the interpreter. The same holds for automation-config edits ("move my briefing to 6:30", P-19): editing an `automations/` file is a registry meta-operation the orchestrator performs directly (Spec 04 §3.9), never a `write_record`. Keeping this boundary explicit protects the P2.7 story: the interpreter's capability ceiling stays exactly the eleven primitives of the closed vocabulary (§3), and everything that mutates the *capability system itself* goes through the reviewed registry code paths with their own confirmation rules.

Two read/query skills in full (they exercise `read_related` + the resolve-or-create person idiom for the query side):

```json
// recall-contact-fact — "What's Mia allergic to?"
{ "skillId":"recall-contact-fact","displayName":"Recall a Fact About Someone",
  "inputs":[{"name":"subjectId","valueType":"entityRef","source":"slot","required":false},
            {"name":"subjectName","valueType":"text","source":"slot","required":true},
            {"name":"query","valueType":"text","source":"slot","required":false}],
  "reads":["contact","contact_fact"],"writes":[],
  "steps":{"main":[
    {"op":"read_one","typeId":"contact","match":{"id":"{subjectId}"},"into":"subject"},
    {"op":"read_related","typeId":"contact_fact","parentId":"{subject.id}","filter":{"fact":{"contains":"{query}"}},"orderBy":"createdAt","orderDir":"desc","into":"facts"},
    {"op":"compute","expr":"concat('I don''t have anything on that for ', {subjectName}, '.')","into":"absentLine"},
    {"op":"format","template":"{facts.0.fact, default: '{absentLine}'}","into":"confirmationText"} ]},
  "dangerLevel":"safe" }

// query-last-interaction — "When did I last see Marco?"
{ "skillId":"query-last-interaction","displayName":"When Did I Last…",
  "inputs":[{"name":"contactId","valueType":"entityRef","source":"slot","required":false},
            {"name":"contactName","valueType":"text","source":"slot","required":true},
            {"name":"medium","valueType":"enum","enumValues":["phone","text","in_person","email","note"],"source":"slot","required":false}],
  "reads":["contact","contact_interaction"],"writes":[],
  "steps":{"main":[
    {"op":"read_one","typeId":"contact","match":{"id":"{contactId}"},"into":"c"},
    {"op":"read_related","typeId":"contact_interaction","parentId":"{c.id}","filter":{"medium":"{medium}"},"orderBy":"occurredAt","orderDir":"desc","limit":1,"into":"last"},
    {"op":"compute","expr":"days_between({last.0.occurredAt}, today())","into":"daysAgo"},
    {"op":"compute","expr":"format_date({last.0.occurredAt}, 'MMMM d')","into":"lastLabel"},
    {"op":"format","template":"You last saw {c.displayName} on {lastLabel} — {daysAgo} days ago.","into":"confirmationText"} ]},
  "dangerLevel":"safe" }
```
*(`recall`/`query` skills take the same `…Id`+`…Name` pair as write skills, `G-12`; a query for an unknown person hits the same disambiguation/absent path. A null `medium` filter entry is dropped and matches all — the "any contact method" case, Spec 05 §10 E4; normative rule in §3.6. The full log/streak/template skills are canonicalized as the corpus is traced.)*

### 9.3 The interaction suite and due-date phrasing — v0 convergence (2026-07)

*The shipped v0 skill files (`v0/data/skills/`) converged the interaction, people-fact, and task seed shapes on the behaviors below. v0 naming diverges from this section's design ids: the interaction type is `interaction` (this spec's `contact_interaction`), the query side of `query-last-interaction` ships as two skills (`last-interaction`, `list-interactions`), and `add-contact-fact` ships as `remember-person-fact`. The behaviors, not the ids, are the normative part; the id reconciliation rides the next seed-table pass.*

**Interactions carry a `kind`.** An interaction records what *sort* of contact it was — `dinner`, `lunch`, `coffee`, `call`, `text`, `visit`, `catch-up`, `hangout`, `video call`, … — as an optional `kind` field alongside the note and date. (The attribute itself is a Spec 01 type-definition fact; what follows is the skill contract over it.) `log-interaction` takes an optional `kind` slot and stores it verbatim. `list-interactions` renders it per line — `• 2026-07-05 (Sunday) — dinner — <note>` — omitting the segment when absent, exactly as it omits an absent note. `last-interaction` names the most recent interaction's kind ("Your last dinner with Mia was on 2026-07-05 (Sunday).") and falls back to the generic "You last talked to Mia on …" when that interaction has no kind. All three degrade by omission, never by leaking an empty placeholder (the §3 `format` null rule).

**`log-interaction.at` is a past-event date.** The `at` input is a **past-intent** day slot (`pastday` — slot-type mechanics live in Spec 03): a bare weekday resolves *backward*, so "I had dinner with Mia on Tuesday" lands on the most recent Tuesday — a past interaction never gets a future date. When the slot is omitted, the skill defaults `at` to `{today}` with an explicit `branch isNull → set`: the default is visible in the skill definition, not resolver magic.

**`remember-person-fact`: resolve and de-collide *before* the fact is written.** Both `personName` and `relationTo` go through the fuzzy resolve-or-create tier (§3 `read_one` `resolve:true`), so the two can land on the *same* record when the names token-overlap. The skill therefore resolves the relative and de-collides — if `person.id == relative.id`, `person` is rebound to a freshly created contact — **before** the `contact_fact` write, so the fact attaches to the correct person and a relationship is never a self-loop. The resulting write order is fixed: person contact, relative contact, relationship, fact. (An earlier ordering that wrote the fact before resolving the relative attached it to the collided record.)

**Relationship writes are gated on a captured `relationType`.** A `contact_relationship` record is written only when the `relationType` slot was actually captured. A bare `relationTo` with no type no longer writes a relationship carrying a null `relationType` — the relative contact is still created, and the typed edge can be added later.

**`create-task` due-date labels: weekday near, calendar date far.** The confirmation's due-date label is chosen by `compute days_between({today}, {dueDate})`: within the coming week (fewer than 7 days out) it reads as a bare weekday (`format_date … "EEEE"` → "due Saturday"); at 7+ days out it reads as a calendar date (`format_date … "MMMM d"` → "due December 25") — a bare weekday months away is ambiguous. The branch computes `dueLabel` once, before the single-/multi-item split, so every confirmation phrasing shares it.

**`create-task.dueDate` is a future date.** The `dueDate` input is a **future-intent** slot (`futuredate`, Spec 03): a bare month-day already past this year rolls forward to next year — a task never gets a due date in the past. As with `pastday`, the resolution mechanics belong to the slot-type layer; the skill receives a literal date.