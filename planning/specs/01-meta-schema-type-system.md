# Spec 01 — Meta-Schema & Type System

**Status:** Draft v0.3 — July 2026 (reviewed & revised by Claude — see Appendix A)  
**Depends on:** Research doc v0.8 (§4, §8, §9)  
**Blocks:** Skill DSL spec, NLU spec, Architecture spec, Data & Sync spec, UI spec

---

## 0. Purpose & Scope

This spec defines the type system that sits at the center of everything Plenara does. Every record the app stores — a task, a contact note, a mood log, a nutrition entry — is an instance of a type. Types are not hardcoded into the app; they are data stored in the user's folder, authored by Claude once and then executed forever by deterministic code.

This document covers:

1. The meta-schema kernel — the fixed set of primitives the system is built from
2. The type-definition file format — how a type is represented on disk
3. The type registry — how types are loaded, indexed, and queried at runtime
4. Semantic reconciliation — preventing duplicate types from proliferating
5. Migration — keeping user data valid as types evolve
6. Presentation hints — connecting types to the view-archetype system without coupling schema to UI

It does **not** cover: the Skill DSL (how skills operate on types), NLU routing (how utterances resolve to types), or view-archetype rendering internals (those belong to the UI spec). Cross-references are noted where the boundary is touched.

---

## 1. Governing Principles

These principles from the research doc govern every decision in this spec. They are not up for re-debate here — they are the frame.

**P2.3 — Organic UI.** Types must carry enough presentation information that the UI can render them beautifully without falling back to generic forms. This is the job of presentation hints (§6).

**P2.4 — Code over AI.** Type definitions are authored by Claude (AI), but once authored they are data. All operations on instances — create, query, update, migrate — are executed by deterministic code. Claude is never in the loop at runtime.

**P2.5 — Aggressive layering.** The type system lives entirely in the Storage and Business Logic layers. The UI layer knows only view archetypes and view-model contracts. The Intelligence layer knows the schema well enough to author and reconcile types. No layer bypasses the registry.

**P2.6 — Capabilities are data.** A "Meal" type and a built-in "Task" type are stored and treated identically. There is no privileged class of built-in type at the code level — only seed types loaded at first launch.

**P2.7 — AI authors, code executes.** Claude produces a type definition file as output. The Skill Interpreter, StorageRepository, and SchemaRegistry consume it as data. No generated code is ever evaluated.

**P2.8 — No silent failure.** The type system never drops a problem on the floor. An invalid or unparseable type file is logged and surfaced to the user, not crashed past (§5.2); an unresolved `refType`/`parentType` degrades only the referencing type and is surfaced for repair rather than failing startup (§5.3); a dangling `parentId` or `entityRef` is tolerated and shown in the repair view rather than silently discarded (§4.5); a failed per-record migration leaves the record at its old version and surfaces it for repair (§7.4); and an ambiguous type-file sync conflict is escalated to the user for review rather than auto-merged (§7.5). Every failure mode has a visible, actionable surface.

---

## 2. The Meta-Schema Kernel

The kernel is the fixed vocabulary of concepts the type system is built from. It does not change without a major version bump to the app itself.

### 2.1 Kernel Primitives

| Primitive | What it is |
|---|---|
| **Entity** | A named, persistent object with an identity (UUID). Entities are the nouns of the system: a person, a task, a meal, a journal entry, a logged interaction. An entity may optionally be *owned* by another entity (it declares a `parentType`) and/or *append-only* (`append: true`). These are orthogonal properties, not a separate kind of thing — see §4.5. |
| **Attribute** | A named, typed slot on an Entity. Carries a value of one of the value types listed in §3. |
| **Relation** | A named, directed edge from one Entity instance to another, always typed (e.g. a `knows` edge between two Contacts, a `plannedFor` edge from a GiftIdea to an Event). A Relation reuses the Attribute object schema with `valueType: entityRef`, but is stored in a type's separate `relations` array (§4) so the graph stays explicit and independently queryable. Ownership (`parentType`) is the one privileged edge; every other reference is a Relation. |
| **Trigger** | A named condition that, when met, queues a Skill to run. Triggers are **automations**, not schema: they live in a separate `automations/` registry (§4.4), reference a type by `typeId`, and are evaluated by deterministic code — never by a model. |
| **TypeDefinition** | A meta-level record that defines a type: its name, fields (Attributes), relations, presentation hints, schema version, and authoring metadata. TypeDefinitions are stored as JSON files and managed by the registry. |

### 2.2 What the Kernel Excludes

The kernel deliberately excludes:

- **Inheritance / subtyping.** Types do not extend other types. Inheritance at the schema level creates migration debt without proportional value. Reuse today is by *convention* — when authoring, Claude reuses proven attribute shapes and archetype assignments — not by a runtime composition primitive. A shared-fragment/mixin mechanism is deliberately deferred (§13) until authoring data shows real duplication.
- **Computed fields.** No formula language in the schema. Derived values (e.g., days since last contact) are computed at query time by the Business Logic layer, not stored.
- **Behavioral code and automations.** Types carry neither executable logic nor automation bindings. A skill's steps live in the Skill DSL; the trigger that fires a skill lives in the `automations/` registry (§4.4). A type definition is purely structural.

---

## 3. Value Types

Attributes carry values of the following primitive value types. This set is fixed. Adding a new value type requires a kernel version bump.

| Type name | Dart equivalent | Notes |
|---|---|---|
| `text` | `String` | Arbitrary UTF-8. No length limit in schema; storage limits apply. |
| `number` | `double` | IEEE 754. For *approximate* or continuous quantities (calories, steps, weight); integers render as whole doubles, so format in the UI. Do **not** use for money — see `decimal`. |
| `decimal` | `Decimal` (string on disk) | Exact base-10 decimal, stored as a string (e.g. `"12.34"`) to avoid float error. Use for money and any value where rounding matters; set `unit` to the currency code (e.g. `"USD"`). |
| `boolean` | `bool` | |
| `datetime` | `DateTime` (UTC) | Stored as ISO 8601 string in JSON. Always UTC on disk; displayed in local time. |
| `date` | `String` (YYYY-MM-DD) | Calendar date without time. Used for birthdays, deadlines. |
| `duration` | `int` (seconds) | Stored as integer seconds. |
| `enum` | `String` | Value must be one of a declared `enumValues` list in the Attribute definition. |
| `entityRef` | `String` (UUID) | A typed reference to another entity instance by its `id`; `refType` names the target type. Every instance is an entity, so this covers all cross-references. |
| `tag` | `List<String>` | A set of freeform strings. Rendered as chips. Not semantically constrained. |
| `attachment` | `String` (relative path) | Path relative to the Plenara folder root. Resolution happens at query time. |
| `json` | `Map<String, dynamic>` | Escape hatch for rare structured payloads with no better fit. Use sparingly; blocks structured querying. |

### 3.1 Nullability

Every Attribute is declared either `required` or `optional`. The interpreter enforces this on write; the storage layer does not — storage is type-agnostic.

### 3.2 Composite Attributes

An Attribute may declare `children` — a list of sub-Attributes with their own names and value types. This allows a `location` attribute to carry `{ city: text, country: text }` without needing a separate type. Nesting is limited to one level; deeper structures should be modeled as Relations to a separate Entity type.

---

## 4. Type-Definition File Format

Each type is stored as a single JSON file in `[plenara-root]/types/`. The filename is the type's `typeId` with a `.json` extension. Both built-in seed types and user-defined types live here.

### 4.1 File Anatomy

```json
{
  "typeId": "meal",
  "schemaVersion": 1,
  "displayName": "Meal",
  "displayNamePlural": "Meals",
  "description": "A meal or food intake event.",
  "examplePhrases": [
    "log my lunch",
    "just ate",
    "had a sandwich",
    "track breakfast"
  ],
  "isBuiltIn": false,
  "authoredBy": "claude",
  "authoredAt": "2026-07-03T14:22:00Z",
  "safetyAssessmentId": "sa_7f3a...",
  "lastModified": "2026-07-03T14:22:00Z",
  "attributes": [
    {
      "name": "description",
      "label": "What did you eat?",
      "valueType": "text",
      "required": true
    },
    {
      "name": "calories",
      "label": "Calories",
      "valueType": "number",
      "required": false,
      "unit": "kcal"
    },
    {
      "name": "mealType",
      "label": "Meal type",
      "valueType": "enum",
      "enumValues": ["breakfast", "lunch", "dinner", "snack"],
      "required": false
    },
    {
      "name": "loggedAt",
      "label": "When",
      "valueType": "datetime",
      "required": true,
      "defaultToNow": true
    }
  ],
  "relations": [
    {
      "name": "withPerson",
      "label": "Eaten with",
      "valueType": "entityRef",
      "refType": "contact",
      "required": false,
      "cardinality": "many"
    }
  ],
  "presentation": {
    "archetype": "timeline",
    "primaryField": "description",
    "secondaryField": "mealType",
    "timestampField": "loggedAt",
    "color": "#E8A87C",
    "icon": "fork_knife"
  },
  "nluHints": {
    "captureIntent": "log_meal",
    "queryIntent": "query_meal",
    "confirmationTemplate": "Logged {mealType, default: 'a meal'}: {description}."
  }
}
```

### 4.2 Top-Level Fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `typeId` | string | yes | Lowercase, snake_case. Globally unique within the registry. **Immutable** once created — the filename and all inbound `refType`/`entityRef` links depend on it, so a rename changes `displayName`, never `typeId`. |
| `schemaVersion` | integer | yes | Starts at 1. Incremented when any breaking change is made to `attributes` or `relations`. Non-breaking additions (new optional fields) do not require a bump. |
| `displayName` | string | yes | Singular. Shown in UI. |
| `displayNamePlural` | string | yes | Plural form for lists and summaries. |
| `description` | string | yes | One sentence. Used by Claude during reconciliation and authoring. |
| `examplePhrases` | string[] | yes | At least three utterances a user might say to invoke this type. Used by the NLU router's embedding index. |
| `isBuiltIn` | boolean | yes | `true` only for seed types shipped with the app. Seed types may not be deleted by the user. |
| `authoredBy` | `"claude"` \| `"system"` | yes | `"system"` for seed types; `"claude"` for all user-defined types. |
| `authoredAt` | ISO 8601 datetime | yes | When the type was first authored. |
| `safetyAssessmentId` | string \| null | yes | ID of the stored safety assessment for Claude-authored types. Null for built-in seed types. Required for any user-defined type before activation. |
| `lastModified` | ISO 8601 datetime | yes | Updated on any change. Used for sync and startup scanning. |
| `attributes` | Attribute[] | yes | The type's fields. See §4.3. May be empty only for a type whose data is entirely relations. |
| `relations` | Relation[] | no | Typed edges to other entities; same object schema as attributes (§4.3) with `valueType: entityRef`. Omit or use `[]` if none. |
| `presentation` | object | yes | View-archetype hints. See §9. |
| `nluHints` | object | yes | Intent labels and confirmation template. See §10. |
| `migrations` | Migration[] | no | Declarative migration descriptors; user-defined types only. See §7.2. |
| `parentType` | string | optional | If present, this type is *owned* by the named entity type; its instances carry a `parentId`. See §4.5. |
| `append` | boolean | no | If true, instances are append-only (an event log): written once, never edited inline, indexed by parent/time. Default false. See §4.5. |
| `deprecated` | boolean | no | `true` if superseded via reconciliation (§6). Deprecated types are excluded from NLU routing and the embedding index. Default false. |
| `replacedBy` | string \| null | no | `typeId` of the successor when `deprecated == true`; otherwise null/absent. |

### 4.3 Attribute Object Fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | yes | camelCase. Unique within the type. |
| `label` | string | yes | Human-readable prompt for voice confirmation and display. |
| `valueType` | ValueType | yes | One of the types in §3. |
| `required` | boolean | yes | Whether the field must be present on write. |
| `enumValues` | string[] | if `valueType == "enum"` | The allowed values. |
| `refType` | string | if `valueType == "entityRef"` | The `typeId` of the target type. |
| `cardinality` | `"one"` \| `"many"` | if relation | Default `"one"`. |
| `defaultToNow` | boolean | optional | If true and `valueType` is `datetime` or `date`, default to the current time/date on capture. |
| `unit` | string | optional | Display unit label (e.g. `"kcal"`, `"kg"`, `"min"`). Purely presentational. |
| `children` | Attribute[] | optional | Sub-attributes for composite values. One level only. |
| `sensitive` | boolean | optional | If true, instances of this attribute are subject to at-rest encryption (§8). Default false. |

### 4.4 Automations (Trigger Registry)

Automations bind a condition to a skill. They are **not** part of any type definition — a type stays purely structural (§2.2). Each automation is a JSON file in `[plenara-root]/automations/`, loaded by the registry alongside types. Adding, editing, or removing an automation never touches a type file and never bumps a type's `schemaVersion`.

```json
{
  "automationId": "meal-weekly-summary",
  "targetType": "meal",
  "condition": { "kind": "schedule", "cronExpression": "0 20 * * 0" },
  "skillId": "meal-weekly-summary-skill",
  "pendingSkill": false,
  "description": "Sunday evening summary of the week's meals."
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `automationId` | string | yes | Globally unique. Filename is `{automationId}.json`. |
| `targetType` | string | yes | `typeId` the automation observes. Must resolve in the registry. |
| `condition.kind` | `"schedule"` \| `"onWrite"` | yes | How it fires. (`onQuery` is deferred — §12 Q6.) |
| `condition.cronExpression` | string | if `kind == "schedule"` | Standard 5-field cron. Evaluated by the deterministic scheduler, not a model. |
| `condition.afterField` | string | if `kind == "onWrite"` | Attribute name; fires after that field is written to a `targetType` instance. |
| `skillId` | string | yes | References a skill in `skills/`. Must exist and be valid to fire — unless `pendingSkill` is true. |
| `pendingSkill` | boolean | no | If true, the skill is not yet authored; the automation is registered but inert until it exists. Default false. |
| `description` | string | yes | Why this automation exists. Shown in the automation-management UI. |

Full skill and condition semantics belong to the Skill DSL spec; this section defines only the automation record's shape and storage.

### 4.5 Owned and Append-Only Types

The old entity/record split is replaced by two orthogonal, optional properties on any type:

- **Owned** — the type declares a top-level `parentType` (the `typeId` of its owner). Every instance then carries a structural `parentId` (the owner's UUID), stored in the instance's plaintext metadata (§8.2) so instances index under their parent without decryption. `parentId` is not an author-declared attribute; the StorageRepository requires and validates it on every write. A type without `parentType` is top-level.
- **Append-only** — the type declares `append: true`. Its instances form an event log: written once, never edited inline, indexed by parent/time. A type without `append` is normal read-write.

The two are independent. `contact_interaction` is both owned (by `contact`) and append-only — the classic "record." But a top-level append-only audit log (owned by nothing) and an owned-but-editable sub-object (e.g. an editable `address` owned by a `contact`) are both expressible now, which the old binary could not represent.

`parentType` is the single privileged owning edge. A type may still declare ordinary `relations` to *other* entities (e.g. an interaction that also references a `place`); those are associations, not ownership.

A dangling `parentId` (owner deleted, or not yet synced) is tolerated on write and surfaced by the repair view rather than blocking capture — see the referential-integrity note in §12 (Q7).

---

## 5. The Type Registry

The SchemaRegistry is the Business Logic layer's single source of truth for all type definitions. It is loaded on startup and kept in memory; the on-disk files are the authoritative source.

### 5.1 Interface Contract

```dart
abstract class SchemaRegistry {
  /// Load all type definitions from the types/ folder.
  Future<void> hydrate();

  /// Register a new type (or re-register after edit).
  /// Validates the definition; throws SchemaValidationError if invalid.
  Future<void> register(TypeDefinition typeDef);

  /// Look up by typeId. Returns null if not found.
  TypeDefinition? lookup(String typeId);

  /// All registered types, sorted by displayName.
  List<TypeDefinition> all();

  /// Nearest semantic matches to [query] (name, description, examplePhrases).
  /// Used by NLU routing and the reconciliation step.
  /// Returns up to [limit] results with cosine similarity scores.
  Future<List<SimilarityResult>> similarTo(String query, {int limit = 5});

  /// Whether a type with [typeId] exists.
  bool contains(String typeId);

  /// Mark a type as deprecated and point to a successor.
  Future<void> deprecate(String typeId, {String? replacedBy});
}
```

The concrete implementation — `LocalSchemaRegistry` — reads from `[plenara-root]/types/`, indexes `examplePhrases` and `description` via on-device embeddings, and holds the index in memory. The embedding model is a **dedicated retrieval model** (a compact sentence-transformer, ~80 MB), **not** the 1–3B generation model's embedding endpoint — retrieval quality drives NLU routing accuracy, and a purpose-built model clusters short phrases far better (decided in NLU spec §10 MD1; resolves §12 Q1). The extra bundled binary is a deliberate size-for-reliability trade.

### 5.2 Startup Hydration

1. Scan `types/` for files modified since `lastStartupScan` (stored in `settings.json`).
2. Parse and validate each modified `.json` file.
3. For seed types, verify `isBuiltIn == true` and `schemaVersion` matches the app's expected version (hard-coded in the binary). Mismatched seed types trigger an in-app migration (§7).
4. Build (or incrementally update) the embedding index over `examplePhrases` + `description` for each type.
5. Register all valid types. Invalid files are logged and surfaced to the user, but do not crash startup.
6. After all types are registered, run the cross-reference pass: resolve every `refType` and `parentType`. Unresolved references degrade the referencing type (§5.3) but never block startup.
7. Load the `automations/` registry: parse each automation and resolve its `targetType` and `skillId`. An automation with an unresolved `targetType` is inert and surfaced for repair; one with a missing skill is inert unless `pendingSkill` (§4.4).

Typical startup: < 50ms for 100 types on a mid-range iPhone (parsing + index lookup; the embedding index is a device-local binary in `[app-support]` (§5.4) and only rebuilt incrementally).

### 5.3 Registry Invariants

Most are enforced on every `register()` call; the cross-reference invariants (marked ⁑) run after the full hydration pass, because types load in arbitrary order:

- `typeId` is unique (no two types may share an ID).
- `typeId` matches the filename (`{typeId}.json`).
- ⁑ All `refType` values (in relations) and every `parentType` reference a `typeId` that exists in the registry. Because types load in arbitrary order, this check runs **after** full hydration — a forward reference (A → B where B loads later) is valid once both are present. A reference still unresolved after hydration marks the *referencing* type as degraded (it loads, but the offending relation is inert) rather than failing startup.
- Every automation's `targetType` resolves to a registered type (⁑), and its `skillId` exists in `skills/` **or** is marked `pendingSkill: true` (inert until authored).
- `schemaVersion` is a positive integer.
- `examplePhrases` has at least three entries.
- `safetyAssessmentId` is present and non-null for any type where `authoredBy == "claude"`.
- `parentType`, if present, resolves to a registered entity type (⁑, checked post-hydration). There is no `kind` field — ownership and append are orthogonal optional properties (§4.5).
- `typeId` is immutable: a `register()` that changes an existing type's `typeId` is rejected as a new-type collision, not treated as a rename.

### 5.4 The Embedding Index

The registry maintains a small flat embedding index over the union of `displayName`, `description`, and all `examplePhrases` for each type. This is the artifact the NLU router queries to resolve an utterance to a type (see NLU spec, §3). The index is:

- Stored in device-local `[app-support]` (**not** a dotfile inside the synced Plenara root) — a binary file, not synced, cheaply re-generated on any device from the type files. This location is decided in NLU spec §10 MD9, uniformly for both the type index and the skill index (next bullet), so a sync engine never has to special-case an excluded dotfile. Built with the dedicated retrieval embedding model of §5.1.
- Rebuilt incrementally: only types whose `lastModified` is newer than the index's `builtAt` are re-embedded.
- Queried via cosine similarity. The NLU router receives a ranked list of (typeId, score) pairs and applies a confidence threshold before committing to a type.

**Skills are indexed the same way (forward dependency).** NLU routes an utterance to a *skill*, not only a type (NLU spec §3.2), so it needs the same embedding treatment over the skill library (`displayName`, `description`, input labels, and the `examplePhrases` of the skill's `reads`/`writes` types). That parallel skill index is owned by the skill-registry surface (Spec 02 §2.2 / §6.1; its formal interface lands in the Architecture spec) and shares this section's `similarTo`-shaped contract. NLU treats the two as one logical **`CapabilityIndex`** returning a merged, type-tagged ranked list `(id, kind ∈ {skill, type}, score)`; whether that is one physical index or two behind a façade is an Architecture-spec choice. This registry-owned index is the single source — NLU consumes it and never builds its own (that reconciliation is recorded in NLU spec §3.2).

---

## 6. Semantic Reconciliation of Duplicate Types

Schema sprawl is the primary governance risk of an emergent type system. A user says "log my food" one week and "track what I eat" the next; Claude might create both a `meal` type and a `food_log` type. Without a reconciliation step, the registry fills with near-duplicate types, splitting the user's data across incompatible schemas.

### 6.1 Pre-Authoring Reconciliation (Prevent)

Before Claude authors a new type, the authoring flow **must** execute a similarity search against the registry. The step is:

1. Claude receives the user's request and a candidate type description.
2. The app calls `registry.similarTo(candidateDescription, limit: 5)`.
3. Results with similarity score > 0.85 are presented to Claude as candidates in the authoring prompt.
4. Claude's authoring prompt instructs it to: (a) reuse an existing type if any candidate is a clear match, (b) extend an existing type with new optional fields if the need is close but not identical, (c) create a new type only if no candidate is a reasonable fit.
5. The user sees the final recommendation ("I found your existing Meal type — I'll add a 'mood' field to it instead of creating a new one. Does that work?") and approves before any change is committed.

This is a Claude reasoning task; the threshold and the reuse/extend/create decision are made by the model, not by a fixed rule. The 0.85 figure is a starting heuristic for which candidates to surface — not a hard cutoff for the decision itself.

### 6.2 Periodic Consolidation Pass (Clean Up)

The app runs a weekly background consolidation pass (on-device, local model, when the device is idle and charging). The pass:

1. Queries the registry for pairs of types with similarity score > 0.80.
2. For each high-similarity pair, checks whether both have instance records (data). Types with zero instances are flagged for deletion; types with instances are flagged for potential merge.
3. Checks the skills folder for skills that reference only one type of a duplicate pair — those skills may need updating.
4. Produces a triage list surfaced to the user: "I found two similar types — 'Meal' and 'Food log'. You have 12 Meal records and 3 Food log records. Want to merge them?"

The user must explicitly approve any merge. The merge operation is:

1. Designate one type as the **primary** (user chooses, or the one with more instances).
2. For each instance of the deprecated type, migrate it to the primary type using a field mapping (Claude proposes the mapping; user approves).
3. Repoint all **automations** whose `targetType` is the deprecated type to the primary type (and to skills updated for it).
4. Mark the deprecated type with `deprecated: true` and `replacedBy: "primary_type_id"` in its file. Do not delete the file until all instances are migrated and verified.

The consolidation pass is a background operation. It never mutates data without user approval. It may surface nothing — an empty triage list is the expected steady state for a well-governed registry.

---

## 7. Migration

Every type has a `schemaVersion` integer. Every instance record on disk carries the `schemaVersion` of the type definition that was in effect when it was written. When the type evolves, the app must be able to read old instance records against the new schema.

### 7.1 Breaking vs. Non-Breaking Changes

| Change | Breaking? | Version bump? |
|---|---|---|
| Add a new optional attribute | No | No — old records simply lack the field; readers treat it as null |
| Change an attribute from `optional` to `required` | Yes | Yes |
| Rename an attribute | Yes | Yes |
| Remove an attribute | Yes | Yes |
| Change an attribute's `valueType` | Yes | Yes |
| Add/remove an automation (§4.4) | No | No — automations live outside the type file |
| Change `enumValues` (add new values) | No | No |
| Change `enumValues` (remove values) | Yes | Yes |
| Change `presentation` hints | No | No |
| Change `examplePhrases` | No | No |

Non-breaking changes are written to the type file without a version bump. The instance records remain valid.

Breaking changes require: (a) incrementing `schemaVersion` in the type file, and (b) adding a migration step to the migration runner.

### 7.2 Migration Runner

The migration runner is a deterministic Dart component in the Business Logic layer. It is **not** a Claude call at runtime. Its interface:

```dart
abstract class MigrationRunner {
  /// Run all pending migrations for records of [typeId].
  /// Reads records at their stored schemaVersion, applies each migration
  /// step in sequence, and writes the result at the new schemaVersion.
  Future<MigrationResult> migrate(String typeId);

  /// Register a migration step: typeId × fromVersion → toVersion.
  void addMigration(String typeId, int fromVersion, int toVersion, RecordMigrationFn fn);
}

typedef RecordMigrationFn = Map<String, dynamic> Function(Map<String, dynamic> oldRecord);
```

Migration steps are registered in code (not authored by Claude at runtime) — they are written by the developer when a type's schema is intentionally changed. For **user-defined types**, the migration step is authored by Claude at type-edit time and stored as part of the type definition file under a `migrations` key:

```json
"migrations": [
  {
    "fromVersion": 1,
    "toVersion": 2,
    "fieldRenames": { "cals": "calories" },
    "fieldDefaults": { "mealType": "snack" },
    "fieldRemovals": []
  }
]
```

The runner reads this declarative migration descriptor and applies it without executing any generated code. The supported migration operations are:

| Operation | What it does |
|---|---|
| `fieldRenames` | Renames attribute keys in existing records. |
| `fieldDefaults` | Adds missing keys with a literal default value. |
| `fieldRemovals` | Removes keys from existing records. |
| `fieldTypeCoercions` | Coerces a value from one primitive type to another (e.g. number → text). Only safe coercions are supported (see §7.3). |

This is intentionally constrained. Migration logic that cannot be expressed as a combination of these four operations requires a manual migration (developer-written Dart) or a user-visible data-loss warning before the migration is applied.

**Application order within a step.** Operations are applied in a fixed order so the result is deterministic regardless of how the descriptor is written: (1) `fieldRenames`, (2) `fieldTypeCoercions`, (3) `fieldDefaults` (fills only keys still absent after the above), (4) `fieldRemovals` (last, so an earlier op can still read a value before it is dropped).

**Nested and relation fields.** Keys in these operations use dot paths for composite attributes (e.g. `location.city`) and address the `relations` array by relation `name`, exactly as for attributes. Renaming a composite parent renames the whole subtree; a coercion may not cross a composite boundary (coerce children individually).

### 7.3 Safe Type Coercions

| From | To | Rule |
|---|---|---|
| `number` | `text` | `toString()` |
| `boolean` | `text` | `"true"` / `"false"` |
| `date` | `datetime` | Midnight UTC on that date |
| `enum` | `text` | Value as-is |
| `datetime` | `text` | ISO 8601 string, as stored |
| `date` | `text` | `YYYY-MM-DD`, as stored |
| `duration` | `number` | Seconds as a number |
| Any | `json` | Wrap in `{"value": ...}` |

All other coercions are unsafe and must not be applied automatically.

### 7.4 Migration Trigger Points

- **Startup:** If the type file's `schemaVersion` is greater than the highest version seen in any instance record of that type, a migration is needed. The app detects this during hydration and queues a migration run before the data layer is made available to the rest of the app.
- **After sync:** When incoming sync changes update a type file to a newer `schemaVersion`, the file watcher triggers the same check.
- **After type edit:** When the user (via Claude) edits a type in a way that bumps `schemaVersion`, the new type file is written to disk **first**, then the migration runs over the local store. Ordering matters: because each record carries its own `schemaVersion`, writing the type file first makes the run **idempotent and resumable** — a crash mid-run leaves the type at vN with some records still at vN−1, exactly the condition the startup check detects and finishes. Writing records first would risk records advancing to vN while the type file is stranded at vN−1, which the startup check cannot see.

Migrations are **atomic per record**: each record is read, transformed, and written before moving to the next. A failed migration on a single record is logged and the record is left at its old version; the migration continues for all other records. Failed records are surfaced in a repair view.

### 7.5 Conflict Handling on Type Files

When a sync conflict produces two versions of a type file, the resolution is:

1. If only one version has a higher `schemaVersion`, take that version without asking.
2. If both versions have the same `schemaVersion` but different content (e.g., both devices added a field independently), **do not auto-merge**. Surface to the user: "Two versions of your Meal type definition were changed on different devices. Please review." Show a diff-style view.
3. If both versions have the same content, take either (they are identical).

Type-file conflicts are high-stakes (they affect all instance records) and must never be silently auto-merged in an ambiguous case.

---

## 8. Encryption Scoping for Type Instances

This section defines the encryption rules for instance records of each type. The type definition files themselves (`types/*.json`) are **always plaintext** — they are structural, non-personal data and must be readable across devices and tools without decryption.

### 8.1 Sensitive Flag

An attribute can be declared `"sensitive": true`. Encryption is **selective and per-attribute**: only the values of sensitive attributes are encrypted; non-sensitive attribute values stay plaintext so they remain queryable on disk and portable across tools. A type with no sensitive attributes has fully-plaintext instance records.

For a type where *every* attribute is sensitive (e.g. `journal_entry`), selective encryption degenerates to whole-payload encryption — the common case, shown in §8.2.

Certain built-in types carry a hard-coded sensitivity mapping the app applies regardless of (or in addition to) attribute flags:

- `journal_entry` — every attribute sensitive; the whole payload is encrypted.
- `contact` — private notes and relationship details are sensitive; the display name and the fields the person_card needs (e.g. `relationshipType`, last-contact date) stay plaintext so the card renders and is searchable without decryption.
- `contact_interaction` — the interaction body is sensitive; its `parentId` and timestamp metadata are not.

### 8.2 Encryption Boundary

- **Encrypted:** The JSON values of sensitive attributes, bundled into one `encryptedPayload` blob per record.
- **Plaintext, alongside:** The values of non-sensitive attributes (in a `fields` object), so they stay queryable on disk without keys.
- **Plaintext metadata:** The record's `id`, `typeId`, `schemaVersion`, `createdAt`, `lastModified`, and — for owned types — `parentId`. Needed by the StorageRepository, indexer, and migration runner without decryption.
- **Never encrypted (structural, non-personal):** Type definition files, skill files, `settings.json`, the NLU corrections corpus, the registry embedding index.

A **fully-sensitive** record (e.g. `journal_entry`) — every attribute value sits in the payload:

```json
{
  "id": "a1b2c3...",
  "typeId": "journal_entry",
  "schemaVersion": 1,
  "createdAt": "2026-07-03T08:00:00Z",
  "lastModified": "2026-07-03T08:05:00Z",
  "encryptedPayload": "BASE64_ENCRYPTED_JSON..."
}
```

A **partially-sensitive** record (e.g. `contact`) — name and relationship type stay plaintext and searchable; notes are encrypted:

```json
{
  "id": "d4e5f6...",
  "typeId": "contact",
  "schemaVersion": 1,
  "createdAt": "2026-07-03T08:00:00Z",
