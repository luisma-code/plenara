# Spec 04 — Architecture

**Status:** v0.4 — July 2026 (Opus 4.8 first draft v0.1 → Opus 4.8 design-level hardening v0.2 → act-then-describe reconciliation v0.3 → generative-request routing v0.4; bones challenged, calls made and recorded — see Decision Record §9 and Appendix B/C/D review logs)  
**Depends on:** Spec 01 — Meta-Schema & Type System (§4.4, §5, §7, §8); Spec 02 — Skill DSL (§2.3, §4, §5, §7.5); Spec 03 — NLU / Intent (§2.3, §2.6, §2.7, §3.5, §5); Research doc §2.5, §8, §9  
**Blocks:** Spec 05 — Functional; Spec 06 — Data & Sync; Spec 07 — UI; Spec 09 — Test

---

## 0. Purpose & Scope

Specs 01–03 each defined one subsystem and, at its edge, named a seam it could not close alone: Spec 01 gave the `SchemaRegistry` and left the `SkillInterpreter`'s formal interface and the `CapabilityIndex` façade "to the Architecture spec" (§5.4); Spec 02 defined resolve/execute semantics and an execution journal but not the component that owns them or how it is driven; Spec 03 defined `route` and named a "dispatch orchestrator" it deliberately did not build (§2.7). This spec is where those seams are welded into one running system. The v0.2 pass additionally homes three subsystems the earlier specs *implied* but placed nowhere — automations (Spec 01 §4.4 / Spec 02 §7.5 → `AutomationRunner`, §3.9), the `undo` command (Spec 03 §2.3 → §3.11), and the paid generative features (`ClaudeClient.generate` → `GenerativeService`, §3.10) — and completes the turn contract so the interactive loop can actually be driven, not merely observed (§3.6).

It specifies four things the research doc (§9, §12) calls for:

1. **The layer model, formalized** — the five layers, the complete interface contract at each boundary (including the two Spec 01 flagged, `SchemaRegistry` and `SkillInterpreter`), the dependency rule, and how the rule is enforced rather than merely hoped for.
2. **The async/threading model** — Flutter's isolate topology, where each stage of a turn runs, cancellation and barge-in, the serial-execute invariant Spec 02 §4.4 requires, and how storage concurrency and cloud rate limits are held.
3. **Error handling** — the sealed error taxonomy, the No-Silent-Failure surfacing contract that maps every failure to a visible, actionable surface, how errors are translated across boundaries, and how repair views and crash recovery consolidate the partial-failure handling scattered across Specs 01–03.
4. **Offline behavior** — what runs with no network (the entire free tier), what requires the cloud and how each cloud dependency degrades to a surface rather than a dead end, and the connectivity/queue model.

It does **not** re-specify subsystem internals: type-file format (Spec 01), primitive-operation semantics (Spec 02), routing and the corpus (Spec 03), STT/TTS (Spec 06 — Voice), sync-protocol conflict resolution (Spec 06 — Data & Sync), or view rendering (Spec 07 — UI). It defines the *contracts and control flow that bind them*, and it is the authority whenever two subsystem specs disagree about a seam.

---

## 1. Governing Principles

**P2.5 — Aggressive layering.** This is the spec that principle exists for. The system is five layers — UI, Business Logic, Storage, Intelligence, Voice — and every dependency between them crosses an interface (a Dart abstract class), never a concrete type. The rule has a direction: dependencies point *toward* the Business Logic layer's contracts, and no layer reaches around an interface to touch another layer's implementation. §2.2 makes the rule precise and §2.3 enforces it.

**P2.4 — Code over AI.** The architecture keeps the model on the narrowest possible ledge. A model is in the loop at exactly two points — NLU classification/extraction (Spec 03) and cloud authoring/generation (Specs 01 §6, 02 §6) — and both produce *data* that deterministic code then validates and executes. Nothing a model returns is executed as code, and nothing on the skill execution path (`SkillInterpreter`, Spec 02) ever calls a model. The layer diagram (§2) shows the Intelligence layer as a leaf that produces intents and definitions, not as a spine the others route through.

**P2.8 — No silent failure.** Every layer boundary is also a failure boundary. A lower layer never throws a raw exception across an interface; it returns or throws a *typed, translated* error the caller can act on (§5.3), and every terminal error class maps to a user-visible, actionable surface (§5.2). "Offline," "rate-limited," "policy-blocked," "type not found," "record changed under you," and "skill needs a newer Plenara" are all outcomes with a surface, never a swallowed null. This is the principle §5 and §6 are built to satisfy end to end.

**Offline-first (a corollary of the free-tier promise, research §1, §11.3).** The default execution environment has no network. The entire free tier — capture, recall, every deterministic skill, local NLU routing, the corpus fast path, migration, storage — runs to completion with the radio off. Cloud is an *enhancement* the paid tier reaches for, never a dependency the base experience blocks on. §6 makes this concrete; it is a principle here because it constrains every contract in §3 (no interface may make a network round-trip mandatory for a base-tier operation).

**Determinism and testability at every seam.** Each contract in §3 is shaped so the layer behind it is testable in isolation against mocks (research §9.3). The seams pass their non-determinism *in* as data — a frozen clock (Spec 02 §4.4, Spec 03 §2.6), a supplied `NluContext`, an injected `ClaudeClient` — so that business logic and the interpreter are pure functions of their inputs and the recorded-pair harnesses (Spec 03 §7, Spec 09) are true regression tests.

---

## 2. The Layer Model

### 2.1 Layer Definitions

Five layers. The research doc §9.1 table is refined here with the concrete components each layer owns (the interfaces are formalized in §3).

| Layer | Responsibility | Owns (components) | Depends on (interfaces) | Must not know |
|---|---|---|---|---|
| **UI** | Render view state; emit user events; map types to view archetypes; host confirmation surfaces | View models, archetype renderers, the confirmation/clarification widgets | Business Logic (via an app-facing façade + an event/state stream) | Storage, Intelligence, Voice internals; business rules |
| **Business Logic** | Validate, transform, apply rules; run the interpreter; own the dispatch turn, automations, generation, and undo; drive migration and reconciliation | `DispatchOrchestrator`, `SkillInterpreter`, `SchemaRegistry`, `MigrationRunner`, `AuthoringService`, `ExecutionJournal`, `AutomationRunner`, `GenerativeService`, `AttentionSurface` | Storage, Intelligence, Voice contracts | How data is stored; how a model works internally |
| **Storage** | Read/write per-record JSON (type-agnostic); own the in-memory decrypted object store; watch files; encryption at rest | `StorageRepository`, the object store/cache, the file watcher, `CryptoBox` | File system / content URIs; the meta-schema shape only | Business rules, UI, AI |
| **Intelligence** | NLU routing & extraction; cloud calls; type/skill authoring; the corrections corpus | `NluRouter`, `ClaudeClient`, the corpus store | Business Logic contracts (intent/type/skill schemas), the `CapabilityIndex` (read-only) | Storage internals, UI |
| **Voice** | STT, TTS, push-to-talk / wake-word; signal a final transcript | `SpeechEngine` | Business Logic (delivers transcripts; receives text to speak) | Storage, UI, business rules |

Two components sit across the Storage↔Business seam and deserve naming now, because Specs 01–03 all leaned on them: the **in-memory object store** (Storage owns it; it is the decrypted, hydrated spine every read is served from, Spec 01 §8.2) and the **`CapabilityIndex`** (a Storage/registry artifact, Spec 01 §5.4, that Intelligence queries read-only, §3.4 here).

### 2.2 The Dependency Rule

The layers form a **directed acyclic dependency graph with the Business Logic layer's *contracts* at the center**. Concretely:

- **Dependencies are on interfaces, never implementations.** Business Logic holds a `StorageRepository`, not a `LocalJsonStorage`; a `ClaudeClient`, not an `AnthropicHttpClient`. Concrete types are constructed once, at the composition root (§2.3), and injected downward.
- **The Intelligence and Voice layers are leaves, not intermediaries.** A turn does not flow UI → Voice → Intelligence → Storage as a pipe. It flows through the **Business Logic layer's `DispatchOrchestrator`**, which calls each contract in turn (§3.5, §4.2). Voice hands a transcript *to* Business Logic; Intelligence returns an `Intent` *to* Business Logic; neither calls the other, and neither calls Storage's implementation. This is the structural expression of "Code over AI": the deterministic orchestrator is the spine, and the model-bearing layers hang off it.
- **No back-references.** Storage never calls Business Logic; Intelligence never calls UI. Where a lower layer must inform an upper one of an asynchronous event (a file changed on disk, a final transcript arrived), it does so by emitting on a **stream the upper layer subscribes to** (`Stream<FileChangeEvent>`, `Stream<Transcript>`), not by holding a reference to the caller. Data flows down through calls and up through streams.
- **The meta-schema is the one shared vocabulary.** Storage is "type-agnostic" (Spec 01 §5) but not schema-ignorant: it knows the *kernel* shape (a record has an `id`, `typeId`, `schemaVersion`, timestamps, a `fields` object, an optional `encryptedPayload`, §3.1, Spec 01 §8.2) so it can persist and index any record without knowing any specific type. Specific type semantics live only in Business Logic's `SchemaRegistry`.

### 2.3 Composition Root and Wiring

Because every dependency is an interface, something must choose the concrete implementations. That is the **composition root**: a single `AppContainer` constructed at launch (`main()`), before any layer runs, which instantiates each concrete component and injects it into the layer above. It is the *only* place in the codebase where concrete implementation types are named. This keeps the dependency rule mechanically checkable: a lint/import rule forbids any file outside the composition root from importing a concrete `*Impl` class across a layer boundary, so a violation is a build failure, not a code-review miss (§5 of the Test spec makes this a CI gate).

Platform-specific implementations (the `SpeechEngine` backed by iOS `SpeechAnalyzer` vs Windows SAPI, the `CryptoBox` backed by Keychain/Secure Enclave vs DPAPI/TPM, Spec 01 §8.7) are selected here by platform channel at construction time. The layers above receive the same interface on every platform; portability is a composition-root concern, never a business-logic one.

**Component inventory** (each maps to exactly one layer; the interface is in §3):

| Component | Layer | Interface (§3) | New here? |
|---|---|---|---|
| `DispatchOrchestrator` | Business | §3.6 | **Yes** (named in Spec 03 §2.7, formalized here) |
| `SkillInterpreter` | Business | §3.3 | **Yes** (semantics in Spec 02, interface here) |
| `ExecutionJournal` | Business | §3.3 | **Yes** (structure in Spec 02 §5, interface here) |
| `SchemaRegistry` | Business | §3.2 | Restated from Spec 01 §5.1 |
| `MigrationRunner` | Business | §3.2 | Restated from Spec 01 §7.2 |
| `AuthoringService` | Business | §3.7 | **Yes** (flows in Spec 01 §6 / 02 §6, interface here) |
| `AutomationRunner` | Business | §3.9 | **Yes** (automations in Spec 01 §4.4 / 02 §7.5, owner here) |
| `GenerativeService` | Business | §3.10 | **Yes** (`generate` had no caller in v0.1) |
| `AttentionSurface` | Business | §3.12 | **Yes** (repair-view pattern made queryable) |
| `NluRouter` | Intelligence | §3.4 | Restated from Spec 03 §2.6 |
| `CapabilityIndex` | Storage/registry | §3.4 | **Yes** (façade choice deferred to here by Spec 01 §5.4) |
| `ClaudeClient` | Intelligence | §3.7 | Restated from research §9.2, formalized |
| `StorageRepository` | Storage | §3.1 | Restated from research §9.2, formalized |
| `CryptoBox` | Storage | §3.1 | **Yes** (encryption boundary in Spec 01 §8, interface here) |
| `SpeechEngine` | Voice | §3.8 | Restated from research §9.2 |

---

## 3. The Formalized Layer Contracts

This section gathers every layer-boundary interface in one place. Contracts already defined in Specs 01–03 are restated in brief (with a pointer to the owning spec); the contracts this spec *owns* — `SkillInterpreter`, `ExecutionJournal`, `DispatchOrchestrator`, `CapabilityIndex`, `AuthoringService`, and the `ClaudeClient`/`StorageRepository`/`CryptoBox` shapes the research doc only sketched — are given in full.

A convention that runs through all of them: **fallible operations return a typed result or throw a typed, translated error** (§5.1), never a raw `Exception` or a bare `null` that means "something went wrong." A `null` in these signatures always means a specific, documented "absent" (no such record, no such type), never a failure.

### 3.1 Storage Layer — `StorageRepository`, `CryptoBox`

The Storage layer is type-agnostic (Spec 01 §5): it persists and serves *records* whose only universal shape is the meta-schema kernel envelope (described below). It owns the in-memory decrypted object store — the spine every read is served from — and the file watcher.

```dart
abstract class StorageRepository {
  /// Hydrate the in-memory object store from disk. Decrypts sensitive
  /// payloads via CryptoBox as records load. Reports invalid files rather
  /// than aborting (§5.4). Idempotent; safe to re-run after a sync event.
  Future<HydrationReport> hydrate();

  /// Read one record by id, served from the in-memory store (decrypted).
  /// Returns null iff no record with that id exists.
  Record? read(String id);

  /// Read all records of a type, optionally filtered. Served from memory;
  /// filters over sensitive attributes work because the store is decrypted
  /// (Spec 01 §8.2). This is the surface the interpreter's read ops use.
  List<Record> readMany(String typeId, {Filter? where});

  /// OWNERSHIP mode of read_related (Spec 02 §3.1): the owned children of
  /// [parentId] of the given child type (Spec 01 §4.5 parentType edge).
  List<Record> readChildren(String parentId, String childTypeId, {Filter? where, String? orderBy, String? orderDir, int? limit});

  /// RELATION mode of read_related (Spec 02 §3.1): the target record(s) of the
  /// named relation on [fromId] (Spec 01 §4.3 entityRef edge). A
  /// cardinality-many relation yields the list. These are Spec 02's two
  /// distinct traversal modes — a `via` traversal has no parent, so it cannot
  /// be expressed as a parentId query (the v0.1 signature's conflation).
  List<Record> readViaRelation(String fromId, String relationName, {Filter? where, String? orderBy, String? orderDir, int? limit});

  /// Upsert one record, write-through: update the in-memory store AND persist
  /// the on-disk envelope (described below). [sensitiveFields] names the attributes to
  /// seal into `encryptedPayload` via CryptoBox — supplied by Business Logic
  /// from the type's `sensitive` flags (Spec 01 §8.1), NOT computed here, so
  /// Storage stays type-agnostic: it is told *which* fields to encrypt, never
  /// *why*. Atomic per record (Spec 01 §7.4); upsert on id makes interpreter
  /// re-issue idempotent (Spec 02 §4.4). If any field is sensitive and
  /// CryptoBox.keyAvailable is false, the write fails with a CryptoError
  /// surface (§5.2) rather than persisting the value in plaintext.
  Future<void> write(Record record, {Set<String> sensitiveFields = const {}});

  /// Delete one record (file + store), writing a tombstone so sync propagates
  /// the removal (Spec 02 §3.2). Idempotent; deleting an absent id is a no-op.
  Future<void> delete(String id);

  /// A cold stream of file-change events observed on the synced folder, so
  /// the Business Logic layer can reconcile after external sync (§4.5,
  /// Spec 01 §7.4). Debounced (§4.5). Never holds a caller reference.
  Stream<FileChangeEvent> watch();
}
```

**Two shapes, one boundary — do not conflate them (a v0.1 modeling gap).** The `Record` that `read`/`readMany`/`readChildren`/`readViaRelation` return and `write` accepts is the **in-memory, fully-decrypted** form — `{ id, typeId, schemaVersion, createdAt, lastModified, parentId?, fields: Map<String,Object?> }`, where `fields` holds *every* attribute value, sensitive or not, in the clear (Spec 01 §8.2: "the in-memory cache always holds fully-decrypted values"). It carries **no** `encryptedPayload` — encryption is a property of the on-disk representation, not the runtime object. The **on-disk envelope** is the split form Spec 01 §8.2 shows: plaintext `fields` (non-sensitive attributes, queryable on disk) plus a single `encryptedPayload` blob (the sensitive attributes, sealed). Storage is the *only* component that crosses between the two: `hydrate`/reads open the payload via `CryptoBox` and merge it into the decrypted `fields`; `write` re-splits `fields` using the caller-supplied `sensitiveFields` set and seals that subset. Every layer above Storage sees only the decrypted `Record`; no other component ever holds an `encryptedPayload` or touches a key (§3.1 `CryptoBox`). Storage still never interprets `fields` against a type — it splits by the names it is handed, not by schema. Filters (`readMany`/`readChildren`/`readViaRelation`) are the Spec 02 §3.6 filter-expression form, evaluated in memory over the decrypted store, which is exactly why a filter over a `sensitive` attribute works (Spec 01 §8.2).

`CryptoBox` isolates all key handling behind one interface so no other component touches a raw key (Spec 01 §8.7 keeps keys in the platform secure store, never in the synced folder):

```dart
abstract class CryptoBox {
  /// Encrypt the sensitive-attribute subset of a record into one payload
  /// blob (Spec 01 §8.2). Key resolved from the platform secure store.
  Uint8List sealFields(Map<String, Object?> sensitiveFields);
  Map<String, Object?> openPayload(Uint8List payload);

  /// Whether a usable key is present on this device (false → sensitive
  /// records are unreadable here; surfaced, not crashed — §5.4, key-recovery
  /// is Spec 01 §8.7's open problem).
  bool get keyAvailable;
}
```

The same `CryptoBox` seals the device-local encrypted stores of the other layers — the execution journal (Spec 02 §5.2) and the sensitive corpus / plan cache (Spec 03 §5) — so there is exactly one crypto surface and one key-availability check in the whole app.

### 3.2 Business Logic — `SchemaRegistry`, `MigrationRunner` (restated)

Both are defined in full in Spec 01 and only summarized here so the layer's surface is complete in one place.

`SchemaRegistry` (Spec 01 §5.1) is the Business Logic layer's single source of truth for type definitions: `hydrate()`, `register(TypeDefinition)` (validates; throws `SchemaValidationError`), `lookup(typeId) → TypeDefinition?`, `all()`, `similarTo(query, {limit}) → List<SimilarityResult>` (the retrieval surface NLU consumes, backed by the `CapabilityIndex`, §3.4), `contains(typeId)`, `deprecate(typeId, {replacedBy})`. It reads the type files as authoritative and holds the parsed forms in memory (Spec 01 §5.2 hydration; §5.3 invariants).

`MigrationRunner` (Spec 01 §7.2) is a deterministic Business Logic component — **never a runtime model call**: `migrate(typeId) → MigrationResult` applies the declarative migration descriptor (renames/defaults/removals/safe coercions) record-by-record, atomically per record, leaving failures at their old version and surfacing them to a repair view (§5.4). `addMigration(typeId, from, to, fn)` registers developer-authored steps for built-in types.

### 3.3 Business Logic — `SkillInterpreter` and `ExecutionJournal` (new)

Spec 02 defined the interpreter's *semantics* (the closed vocabulary, the resolve/execute split, frozen inputs, idempotent resume) and the *journal's structure*, and explicitly left "its formal interface … to the Architecture spec" (Spec 01 §5.4). Here it is.

The interpreter is the pure, deterministic execution engine. It **never calls a model, never renders UI, and never decides whether to confirm** — it exposes the two phases of Spec 02 §4 as separate calls so the orchestrator (§3.6) can interpose an approval gate between them *where one is required*, and it reads through `StorageRepository`. Under act-then-describe (Spec 05 §3.1) the interactive path interposes **no** gate — resolve flows straight into execute and the result is described — but the two calls stay separate because the split still earns its keep: it lets the orchestrator capture the after-the-fact description from the resolved plan, capture before-images for undo (§3.11), resume a killed execution idempotently, and interpose the gate that *does* survive on the unattended-automation and type/skill-deletion paths (Spec 02 §7.1, §7.5). The split into two methods is the interface-level expression of Spec 02's resolve/execute separation:

```dart
abstract class SkillInterpreter {
  /// Compile-on-first-use (Spec 02 §3.0), then run the RESOLVE phase:
  /// walk the step list, execute reads, fully unroll foreach, mint create
  /// ids, validate every pending write against the target type's schema,
  /// and produce an ActionPlan of fully-resolved literal writes. NO side
  /// effects on storage. Freezes system inputs and writes an
  /// `awaiting_confirmation` journal entry (Spec 02 §4.1, §4.4, §5.3).
  /// Throws a typed ResolveError (missing input, unknown type, unresolvable
  /// variable, failed write-validation) — before any confirmation is shown.
  Future<ResolvedExecution> resolve(CompiledSkill skill, SkillInputs inputs, Clock frozen);

  /// Run the EXECUTE phase against a resolved, user-approved execution:
  /// re-verify the read snapshot deterministically (reusing frozen inputs
  /// and minted ids), and if the re-resolved plan structurally matches the
  /// approved plan, apply each pending write via StorageRepository in order,
  /// then mark the journal entry `done`. If the plan differs, returns a
  /// PlanChanged result carrying the new plan for re-approval — it does NOT
  /// execute on a stale approval (Spec 02 §4.2). Bounded by maxReResolves.
  Future<ExecuteOutcome> execute(ResolvedExecution approved);

  /// Resume an in-flight execution found in the journal at startup (§7,
  /// Spec 02 §5.4). Dispatches on `phase`: re-enters resolve, re-shows a
  /// pending confirmation, or continues an interrupted execute idempotently.
  Future<ResumeOutcome> resume(ExecutionRecord journalEntry);

  /// Reverse a completed execution within the undo window (§3.11, the `undo`
  /// system command, Spec 03 §2.3). Computes the inverse of the recorded
  /// action plan from the entry's captured before-images and applies it as a
  /// fresh, journaled, serial execution. Creates are deleted; updates restore
  /// their before-image fields; a deleted record is re-created from its
  /// before-image with a fresh lastModified (undoable — this is what lets
  /// deletion be act-then-describe, Spec 05 §3.1/D8). Cross-device tombstone
  /// revival is a Spec 06 concern (§3.11). Undo is single-level: an undo is
  /// not itself undoable.
  Future<UndoOutcome> undo(String executionId);
}
```

The **execute phase captures a before-image** for each write it applies — the target record's prior state, or a `created` marker when the write mints a new record (Spec 02 §4.4). Before-images are what make `undo` possible and are the one addition this spec asks of Spec 02's execution record (aligned in Spec 02 §5.4). They live only in the device-local, encrypted journal (§3.3, never synced), and are reaped with the entry at the end of the undo window (§3.11), so they add no synced-file or plaintext exposure.

`ResolvedExecution` wraps the `ActionPlan` (the ordered, literal-valued pending writes — the source of both the after-the-fact description and, on a gated path, the review/confirmation payload, Spec 02 §4.1) plus the `executionId` keying its journal entry. `ExecuteOutcome` is one of `Done(confirmationText)`, `PlanChanged(newPlan)`, or a typed `ExecuteError`. Whether an approval gate sits between `resolve` and `execute` is decided by the *orchestrator* from the execution's **origin**, not by the interpreter and no longer by a per-skill `confirmationPolicy` (removed in Spec 02 §7.1): an interactive execution runs straight through and is described (act-then-describe); an unattended-automation execution with writes, or the type/skill-deletion meta-flow, holds for approval (§3.9, Spec 02 §7.5). Keeping `resolve` and `execute` as two calls is what lets the orchestrator interpose that gate where it applies — and, everywhere, capture the plan for the description and the before-images for undo — rather than collapsing to one opaque `run(skill)`.

`ExecutionJournal` is the durable, device-local, encrypted-at-rest store of in-flight executions (Spec 02 §5.2). It is a Business Logic component (the interpreter's private durability), not a storage-layer concern, because its entries are execution *state*, not user records:

```dart
abstract class ExecutionJournal {
  Future<void> put(ExecutionRecord entry);          // encrypted via CryptoBox
  Future<ExecutionRecord?> get(String executionId);
  Future<List<ExecutionRecord>> pending();          // phase != done, for startup resume (§7)

  /// Mark an execution `done` AND record its before-images (§3.3). The entry
  /// is NOT reaped immediately (v0.1/Spec 02 §5.4 reaped at done); it is
  /// retained in a bounded most-recent-completed ring for the undo window so
  /// `undo` (§3.11) has something to reverse. Reaping happens on window
  /// expiry or ring eviction, via reapExpired().
  Future<void> complete(String executionId, List<BeforeImage> beforeImages);

  /// The most recent completed executions still inside the undo window,
  /// newest first — the candidate set for the `undo` command (§3.11).
  Future<List<ExecutionRecord>> recentCompleted({int limit = 1});

  /// Reap: (a) `awaiting_confirmation` entries past their per-entry expiresAt
  /// (Spec 02 §5.4, honoring the longer automation TTL of §7.5), and
  /// (b) completed entries past the undo window. Run at startup and after
  /// each turn (§5.5, §7.1).
  Future<void> reapExpired();
}
```

`ExecutionRecord` is the Spec 02 §5.3 structure (`phase`, `frozenInputs`, `readSnapshot`, `branches`, `foreachProgress`, the compiled `actionPlan`, `skillSchemaVersion`, `compiledFormVersion`), extended by this spec with `beforeImages` (captured at `complete`, for undo) and an `origin` tag (`interactive` | `automation`, so the review feed and the automation TTL of §7.5 are distinguishable from an interactive pending confirmation). One file per execution at `[app-support]/plenara/executions/{executionId}.json`; a `done` file lingers only until its undo window closes.

### 3.4 Intelligence — `NluRouter` (restated) and `CapabilityIndex` (new)

`NluRouter` is defined in full in Spec 03 §2.6 and summarized here: `route(transcript, NluContext) → Intent` (pure w.r.t. storage — reads corpus/index/registry, writes nothing); `resolveFollowUp(pending, slotName, answer, ctx)` for a single missing slot; the two corpus write paths `recordCorrection(...)` / `recordConfirmation(..., {kind})` called *only* by the orchestrator after the user acts; and `testPair(...)`. `Intent` is the sealed hierarchy of Spec 03 §2.5/§2.6; `NluContext` is the read-only per-utterance snapshot the Business Logic layer assembles (frozen clock, `entityNames` resolver, `recentIntents`, `pendingConfirmation`, `tier`).

The one contract this spec owns at this boundary is the **`CapabilityIndex`** — the embedding index Spec 01 §5.4 said the registry owns and NLU only consumes, leaving to the Architecture spec the choice of "whether that is one physical index or two behind a façade." **Decision (§9-AD3): one façade over two physically separate indexes plus a static generative-capability table (§3.10).**

```dart
abstract class CapabilityIndex {
  /// Merged, kind-tagged, ranked nearest matches over the type index, the
  /// skill index (Spec 01 §5.4), and the fixed generative-capability table
  /// (§3.10). NLU's single retrieval surface.
  Future<List<CapabilityHit>> similarTo(String query, {int limit = 5});
}
// CapabilityHit: { id, kind ∈ {skill, type, generative}, score }
```

The façade is one query surface returning `(id, kind, score)`; behind it sit two independently-rebuilt binaries — the type index (keyed on `displayName` + `description` + `examplePhrases`) and the skill index (keyed on the skill's `displayName` + `description` + input labels + its `reads`/`writes` types' phrases). They are *physically* separate because they have different owners and rebuild triggers (a type edit re-embeds one type; a skill edit re-embeds one skill). A **third** source sits behind the same façade: a small **static** table of the fixed built-in generative capabilities (`briefing`, `gift_ideas`, … — §3.10), embedded once from their shipped name + description + example phrases, with no rebuild trigger because the set never changes at runtime. NLU must not care which store a hit came from — it ranks all three kinds together and applies one threshold (Spec 03 §3.3), and each hit is `kind`-tagged so the orchestrator (§3.6) sends a `generative` top-hit to the `GenerativeService` rather than the interpreter. Both live device-local in `[app-support]` (Spec 03 §10 MD9), built with the dedicated ~80 MB retrieval model (Spec 01 §5.1, NLU MD1), never in the synced folder. Keeping them behind one façade means a future consolidation into a single physical index (or a re-split) is invisible to NLU.

**Isolate residency (resolves §11 Q3).** `similarTo` is `Future`-returning because the in-memory vector table and the cosine scan live on the **inference isolate**, co-resident with the embedding model — not on the UI isolate. This is a deliberate call: the query must be embedded (an inference-isolate operation) and then scanned against the table, and a linear cosine scan over a few hundred–thousand vectors is exactly the kind of CPU-bound loop that would drop frames if run on the UI isolate. Co-locating the table with the model makes `similarTo` one inference-isolate round-trip (embed + scan → ranked `(id, kind, score)` list) with no large-payload marshaling of vectors across ports. The `SchemaRegistry`'s *type definitions* stay on the UI isolate for synchronous `lookup`; only the vector table and the scan sit with the model. This keeps Spec 01 §5.4's "registry owns the index" true at the ownership level (the registry drives rebuilds) while the *hot vector data* lives where the query is cheapest — the façade hides the split from both NLU and the registry's callers.

### 3.5 Intelligence — `ClaudeClient` (new/formalized)

The single seam to the cloud. Every network-bearing model call in the app goes through it, which makes offline behavior (§6), the BYOK gate, and the cost guard (Spec 03 §3.5) enforceable in one place rather than scattered across call sites.

```dart
abstract class ClaudeClient {
  /// True iff a usable BYOK key is present AND the network is reachable.
  /// Callers check this before offering a cloud-only affordance (§6.2);
  /// they do not discover unavailability by catching a failed call.
  bool get available;

  /// Classification/extraction escalation (Spec 03 §3.5), Haiku. Returns the
  /// structured intent JSON or a typed CloudError (offline, rateLimited,
  /// policyBlocked, noKey) — every one of which maps to a surface (§5.2, §6.2).
  Future<CloudResult<RawIntent>> classify(ClassificationRequest req);

  /// Authoring (Spec 01 §6, Spec 02 §6), Sonnet. Produces a proposed type or
  /// skill definition + a safety assessment for local validation. Never
  /// returns executable code — only declarative JSON the deterministic
  /// validators check before anything is activated.
  Future<CloudResult<AuthoredArtifact>> author(AuthoringRequest req);

  /// Generative paid features (briefings, gift ideas, reflection — research
  /// §7.2, §10). Results are never cached as procedural plans (project
  /// decision: never cache generative effects).
  Future<CloudResult<GenerativeReply>> generate(GenerationRequest req);
}
```

`CloudResult<T>` is `Ok(T) | CloudError(kind, message)` — a *value*, not an exception, precisely so a caller cannot forget to handle the offline case (§5.1). The cost guard (per-session rate limit, Spec 03 §3.5) and the BYOK check live inside the client, so `available` and a `rateLimited` result are the only things callers reason about.

### 3.6 Business Logic — `DispatchOrchestrator` (new)

Spec 03 §2.7 pinned the *contract* a dispatch orchestrator must satisfy and deliberately did not build it ("that is Architecture/UI"). This is its interface and its place in the layering. It is the **one component that touches both** the interpreter and NLU (Spec 03 §2.7); NLU never drives the interpreter and the interpreter never calls NLU. It owns a single turn end to end and is where the async pipeline of §4.2 is sequenced.

A turn is not a request/response — it is a **conversation with the user in the middle of it**. Under act-then-describe (Spec 05 §3.1) most turns pass straight through — route, resolve, execute, describe — with no pause at all. But the orchestrator must still handle the points where a turn genuinely **pauses for a user decision and must resume with it**: a **clarification** when routing has no reliable best guess (Spec 03 §4, answered by `SelectCandidate`), a **missing-slot follow-up** (Spec 03 §6.3, `ProvideSlot`), a **compound-utterance residual** offer (Spec 03 MD8, `AcceptResidual`), a mid-turn **`"correct"`** (which reverses any prior write, Spec 05 §3.3, then re-routes), and — the one *pre-action* pause left in the system — a **non-undoable type/skill deletion** confirmation (Spec 05 §24, `Approve`/`Decline`). A `Stream<TurnEvent>` alone cannot express any of these: it flows *out* to the UI, and there is no way for the user's select / provide / correct / approve to flow *back in*. The v0.1 interface (`dispatch` + a single `answerClarification`) was therefore not conductable — it could show a surface but could not receive the decision that advances past it. The interface has an outbound stream **and** a matching inbound response path:

```dart
abstract class DispatchOrchestrator {
  /// Begin one turn from a final transcript (Spec 03 §10 MD10 — final only).
  /// Assembles the NluContext, calls NluRouter.route, drives
  /// SkillInterpreter.resolve→execute and describes the result (act-then-
  /// describe); interposes a pause only where one survives — a clarification,
  /// a slot follow-up, a residual offer, or a non-undoable deletion
  /// confirmation (Spec 03 §2.7, Spec 05 §3.1/§24) — and issues AT MOST ONE
  /// corpus write-back per turn (Spec 03 §2.6). Returns the turn's OUTBOUND event
  /// stream; the turn is identified by the TurnStarted.turnId it emits first.
  /// At most one turn is live (§4.3); dispatching while a turn is live cancels
  /// the live turn first (barge-in) unless that turn is past its write barrier,
  /// in which case the new transcript queues behind it (§4.3, §4.4).
  Stream<TurnEvent> dispatch(Transcript transcript);

  /// The INBOUND half of the turn — feed a user decision back in. `promptId`
  /// names the specific ConfirmationRequested / ClarificationRequested /
  /// ResidualOffer event being answered; a response whose promptId is not the
  /// turn's current outstanding prompt is rejected as stale (a superseded or
  /// already-answered surface), never applied to the wrong stage. This is what
  /// makes clarification, a deletion confirmation, "correct", candidate
  /// selection, and the residual offer actually resumable — the gap the v0.1 stream-only
  /// interface left open.
  void respond(String promptId, TurnResponse response);

  /// Cancel the live turn (the `cancel` system command, Spec 03 §2.3, or a UI
  /// dismiss). Clean before any write (§4.3); once the turn is past the write
  /// barrier the in-flight execute is not interrupted and cancel is a no-op.
  /// No corpus write-back on a cancel (Spec 03 §2.7).
  void cancel(String turnId);
}

/// The inbound counterpart to a prompt event. Sealed, so the orchestrator's
/// handling of every surface is exhaustive.
sealed class TurnResponse {}
class Approve         extends TurnResponse {}                          // accept a non-undoable deletion confirmation (Spec 05 §24) — the one surviving pre-action gate
class Decline         extends TurnResponse {}                          // reject with no replacement → turn ends, NO write-back (Spec 03 §2.7)
class Correct         extends TurnResponse { Transcript restatement; } // "no, I meant …" → recordCorrection + re-route the restatement (Spec 03 §2.7)
class SelectCandidate extends TurnResponse { String candidateId; }     // choose one of a clarification candidate set — a skillId for routing clarifications (Spec 03 §2.4), an entity id for pre-dispatch entity disambiguation ("Which Sarah?", Spec 03 §6.1); the promptId's ClarificationRequested defines what the id names
class ProvideSlot     extends TurnResponse { String answer; }         // answer a missing-slot follow-up → NluRouter.resolveFollowUp (Spec 03 §6.3)
class AcceptResidual  extends TurnResponse {}                          // run the queued residual of a compound utterance (Spec 03 MD8); Decline drops it
```

`dispatch` returns a **stream of `TurnEvent`s**, not a single future, because a turn is a sequence of user-visible states, and the UI renders each as it arrives (the up-flow of §2.2). `TurnEvent` is the single UI-facing vocabulary the whole app binds to (AD2, MD-A6); it is a sealed set so the UI's rendering `switch` is exhaustive and a new surface cannot be added without the UI being made to handle it:

```dart
/// Append-only sealed hierarchy. Every event carries its turnId.
sealed class TurnEvent { String get turnId; }

class TurnStarted            extends TurnEvent {}                                  // turn accepted; UI may show a listening→thinking state
class Routing                extends TurnEvent { String skillId; RoutingSource source; } // advisory hint ("logging a meal…"); never itself an approval gate
class ConfirmationRequested  extends TurnEvent { String promptId; PreActionConfirmKind kind;  // nonUndoableDeletion — the only pre-action gate left (Spec 05 §24)
                                                 ConfirmationView view; }          // the UI-renderable payload (§3.6a) — Approve/Decline via respond()
class ClarificationRequested extends TurnEvent { String promptId; ClarificationNeeded clarification; } // ambiguous → SelectCandidate; missingSlots → ProvideSlot (Spec 03 §2.4, §6.3)
class Executing              extends TurnEvent {}                                  // write barrier crossed (§4.3); cancel is now a no-op
class Done                   extends TurnEvent { String confirmationText; }        // terminal-success; also handed to SpeechEngine.speak (§3.8)
class ResidualOffer          extends TurnEvent { String promptId; String summary; } // compound-utterance residual (Spec 03 MD8) — AcceptResidual/Decline via respond()
class Detached               extends TurnEvent { String operationId; DetachedKind kind; } // a long cloud op (authoring/generative) ran in the background (§4.7); turn ends non-blocking
class TurnError              extends TurnEvent { PlenaraError error; }             // terminal-fault; the mapped actionable surface (§5.2)
class TurnCancelled          extends TurnEvent { CancelReason reason; }            // terminal; bargeIn | userCancel | superseded

enum PreActionConfirmKind { nonUndoableDeletion }
```

*(Named `PreActionConfirmKind`, not `ConfirmationKind` — Spec 03 §2.6 already owns the identifier `ConfirmationKind` for the corpus write-back signal (`implicit` | `clarificationSelected`), and the two are unrelated concepts; a shared name would collide in code and, worse, in readers' heads.)*

`ConfirmationRequested` is now a **single-purpose** event: the one pre-action approval the system retains, a non-undoable type/skill deletion (Spec 05 §24). v0.1–v0.2 defined two kinds — a routing pre-confirmation and an action-plan approval — but act-then-describe (Spec 05 §3.1) removed both: an uncertain routing is now surfaced as a `ClarificationRequested` (a genuine `SelectCandidate` choice, not an approve/decline of one guess), and the per-skill action-plan approval is gone with Spec 02's `confirmationPolicy`. The enum is kept (rather than folded into a bare event) so a future non-undoable operation can be added as a named kind and the UI's exhaustive `switch` forced to handle it. Everything else that used to be a "confirmation surface" is either a normal act-then-describe `Done` (no surface) or a `ClarificationRequested`. The orchestrator's obligations to NLU (exactly one of `recordConfirmation`/`recordCorrection`, or neither on a plain cancel/decline) and the compound-utterance residual offer are as specified in Spec 03 §2.7; §4.2 gives the async sequencing. Non-`skill_invocation` intents resolve at the seam exactly as Spec 03 §2.7 lists: `system_command` → the app shell (`undo` via §3.11, `show_pending` → the review feed of §3.9), `clarification_needed` → a `ClarificationRequested` event, `define_*` → `AuthoringService` (§3.7) as a **detached** operation (§4.7) so a 10–30 s Sonnet authoring call never holds the turn lock, tier-gated; `generative_request` → `GenerativeService.produce` (§3.10) as a **detached**, read-only operation (§4.7), tier-gated, delivered through the operation center as a `Detached` event — it writes no records, so it has no confirmation surface and no corpus write-back (Spec 03 §2.2a/§2.7). A `delete_type`/`delete_skill` system command is what raises the `nonUndoableDeletion` `ConfirmationRequested`.

**Mixed free/paid multi-target turn (resolve-stage, `G-23`).** A compound utterance whose fragments resolve to a *mix* of free and paid capabilities — F-13, *"track my mood **and** my energy"*: mood instantiates a built-in template (free), energy has no template (→ paid authoring) — does **not** fail the whole turn. The orchestrator applies the free fragment(s) act-then-describe, then surfaces the paid remainder as a single follow-up offer: *"Your mood tracker's ready — I don't have a template for energy; want me to create a custom one? [PAID]"*. This reuses the compound-utterance residual-offer machinery (Spec 03 §2.7 / MD8) with a per-fragment tier decision, so a partial-free/partial-paid turn degrades gracefully instead of all-or-nothing.

#### 3.6a `ConfirmationView` — the render payload for a confirmation

`ConfirmationView` is the data the `nonUndoableDeletion` `ConfirmationRequested` event carries so the UI can render the deletion confirmation without reaching into a subsystem:

- For `nonUndoableDeletion`: the target type/skill's `displayName`, the count of records that will be destroyed, and the explicit **irreversibility** statement ("Delete 'Mood Log' and all 47 entries? This cannot be undone.", Spec 05 §24). This is the one confirmation the UI must make hard to dismiss accidentally, precisely because it is the one operation `undo` cannot reverse.

(The routing-preconfirm and action-plan render payloads of v0.1–v0.2 are gone with those surfaces; a `Routing` advisory event now carries the transparent-routing hint, and a `Done(confirmationText)` carries the after-the-fact description — neither needs a `ConfirmationView`.)

The UI owns rendering; the orchestrator owns assembling the `ConfirmationView` from registry data so no widget queries the registry directly (P2.5). And the analogue of "what the user approves is exactly what executes" holds in its act-then-describe form (Spec 02 §7.1): the `Done(confirmationText)` the UI speaks is the resolved artifact of the very plan the interpreter applied, so **what the user is told always matches what was written**.

### 3.7 Business Logic — `AuthoringService` (new)

The subsystem that turns a `define_type` / `define_skill` meta-intent (Spec 03 §2.2) into a registered, activated capability. Specs 01 §6 and 02 §6 define the *flows* (reconciliation, safety assessment, validation); this names the component that runs them and its interface, because the orchestrator dispatches to it and offline behavior (§6.2) gates it.

```dart
abstract class AuthoringService {
  /// Author (or draft) a new type from a define_type meta-intent. Online +
  /// paid: calls ClaudeClient.author, runs pre-authoring reconciliation
  /// (Spec 01 §6.1), validates the returned definition, stores the safety
  /// assessment, and registers it. Offline OR free-tier: produces a DRAFT
  /// (Spec 01 decision: offline may draft; activation requires Claude
  /// review) and queues it (§6.3) — never silently fails (P2.8).
  Future<AuthoringOutcome> authorType(DefineType intent, NluContext ctx);

  /// As above for a skill (Spec 02 §6): validate against the closed
  /// vocabulary, verify the reads/writes capability closure, split the
  /// safety assessment into validator-verified facts vs Claude prose
  /// (Spec 02 §7.4), then register.
  Future<AuthoringOutcome> authorSkill(DefineSkill intent, NluContext ctx);

  /// Activate a previously-drafted artifact once the cloud is reachable and
  /// the tier permits (§6.3). Runs the same validation + safety gate.
  Future<AuthoringOutcome> activateDraft(String draftId);
}
```

`AuthoringOutcome` is one of `Activated(id)`, `Drafted(draftId, reason)` (offline or free-tier, with the reason surfaced), or a typed `AuthoringError`. The service is the *only* writer of new type/skill files, and it always routes the model's output through the deterministic validators before anything is registered — the architectural embodiment of "AI authors, code executes" (P2.7).

### 3.8 Voice — `SpeechEngine` (restated)

Defined at research §9.2 and Spec 06; summarized: `startListening()`, `stopListening()`, `speak(text)`, and a `Stream<Transcript>` that signals interim and **final** transcripts. Only the final transcript enters the dispatch pipeline (Spec 03 §10 MD10, §4.2 here). Backed by platform-native STT/TTS selected at the composition root (§2.3). The Voice layer knows only the Business Logic seam; it never touches storage or the model.

### 3.9 Business Logic — `AutomationRunner` and the Review Feed (new)

Spec 01 §4.4 defines automations (a `schedule` or `onWrite` condition that queues a skill) and Spec 02 §7.5 defines how an *unattended* skill confirms (read-only result → deliver; any writes → hold for review; destructive → forbidden). Neither names the component that **evaluates a condition, fires the skill, and owns the pending-review surface** — and the `DispatchOrchestrator` (§3.6) cannot: it is voice-turn-driven and a final-transcript is its only entry point, whereas an automation fires with no transcript and no user watching. This is the architectural home for the *briefing* and *nudge* marquee tasks (research §3, §10), which v0.1 left un-owned. It is a first-class Business Logic component, not a background afterthought.

```dart
abstract class AutomationRunner {
  /// Start the scheduler. Loads the automations/ registry (Spec 01 §4.4),
  /// arms cron conditions on a monotonic timer, and subscribes to the
  /// post-write hook for onWrite conditions (§4.8). Idempotent; re-armed on
  /// foreground and after a reconcile that changed the registry (§4.5).
  Future<void> start();

  /// Fire one automation now: resolve its skill through SkillInterpreter,
  /// then apply the Spec 02 §7.5 rule by the resolved plan's shape —
  ///   • empty action plan (read-only, e.g. a briefing) → deliver the
  ///     formatted result as a notification/digest, no approval;
  ///   • non-empty plan (writes, e.g. nudges) → suspend at the confirmation
  ///     boundary as an `awaiting_confirmation` journal entry tagged
  ///     origin=automation with the longer TTL (§7.5), and push it to the
  ///     review feed — never executed unattended.
  /// Destructive skills are rejected at automation-registration time
  /// (Spec 01 §4.4), so they never reach here.
  Future<void> fire(String automationId);

  /// The pending-review surface: automation-produced plans awaiting the
  /// user's approval. Backs the `show_pending` system command (Spec 03 §2.3)
  /// and the repair/attention surface (§3.12). Approving an item drives the
  /// standard execute (with a fresh re-verify, Spec 02 §4.2, since hours may
  /// have passed); declining reaps its journal entry.
  Stream<ReviewFeed> reviewFeed();
  Future<void> resolveReviewItem(String executionId, TurnResponse response);
}
```

**Automation-config edits are a registry meta-operation, not skill writes.** "Move my briefing to 6:30" (Spec 05 §15 E4, P-19) edits an `automations/` file — automations are not instances of a registered type, so no `write_record` can touch them (Spec 02 §9.2). The orchestrator routes a recognized schedule-edit intent here: the runner rewrites the automation record, re-arms the schedule, and the turn is described act-then-describe like any capability-system change that *is* reversible (re-editing the schedule back is the undo; nothing is destroyed). This is the same boundary `instantiate-template` sits on — voice-invocable, registry-executed, outside the interpreter's ten primitives.

An automation-fired execution reuses the **same interpreter and the same serial-execute queue** (§4.4) as an interactive turn — the only differences are that no `NluRouter` runs (there is no utterance; the skill and its inputs come from the automation binding) and the confirmation boundary is the review feed rather than an in-the-moment modal. Approval of a review item flows through `resolveReviewItem`, which reuses the orchestrator's execute path so the write barrier, re-verify, and journaling are identical. This keeps "no write without approval" true on the unattended path (Spec 02 §7.5) without duplicating the execution machinery. Scheduling reliability under OS background limits is §4.8 and Q1.

### 3.10 Business Logic — `GenerativeService` (new)

The paid, Claude-generated features — daily briefing narrative, gift suggestions, relationship reflection, weekly priority review (research §7.2, §10) — are neither skills nor authoring, and v0.1 named `ClaudeClient.generate` (§3.5) with **no component calling it**. They cannot be skills: a skill may not invoke a model at runtime (Spec 02 §8.4, P2.4). They are their own subsystem:

```dart
abstract class GenerativeService {
  /// Produce a generative artifact (briefing | giftIdeas | reflection |
  /// weeklyReview). Gathers the relevant records deterministically (through
  /// StorageRepository, never handing the model raw sensitive content beyond
  /// what Spec 08's payload rules permit), calls ClaudeClient.generate, and
  /// returns the rendered result. Read-only: it NEVER writes user records
  /// (that would need a skill + confirmation), so it has no confirmation
  /// surface — only a "generated for you" presentation and a dismiss.
  Future<GenerativeOutcome> produce(GenerationRequest req);
}
```

`GenerativeOutcome` is `Produced(artifact)` or a `CloudError` surface (§5.2) — offline/no-key degrades to "needs internet and a key," and never to a fabricated local imitation (§6.2). Because generation is read-only and can take seconds, it always runs as a **detached operation** (§4.7): a user-initiated request (or a scheduled generative automation) returns immediately with a `Detached` handle and delivers through the operation center, so it never holds the turn lock. Results are never cached as procedural plans (the project's "never cache generative effects" rule; Spec 02 §5.5, Spec 03 §5.3).

**Voice routing (resolved — Spec 03 §2.2a, closes Q6).** A user *saying* "give me a briefing" or "what should I get Sarah?" is now routed by the `generative_request` intent category (Spec 03 §2.2a): the built-in generative capabilities are indexed in the `CapabilityIndex` as a third `kind` (§3.4), the router ranks them like any candidate, and a `generative` top-hit above the act band yields a `generative_request` carrying a `generativeKind` + resolved `params`. The orchestrator (§3.6) dispatches it here, detached and read-only; `produce` assembles the cloud `GenerationRequest` DTO from records + those `params` (the DTO is deliberately distinct from Spec 03's `GenerativeRequest` *intent* — the intent is the spoken ask, the DTO is the assembled prompt job). All three entry paths now exist: **voice** (this), a **scheduled generative automation** (§3.9), and an explicit **UI affordance** ("✨ Briefing"). The earlier v0.2 deferral (reachable only by automation/UI) contradicted P2.1 — voice is uncompromising — for seven of the ten paid marquee tasks (Spec 05 §§15–22); reversing it is the flagship of this Spec 05-driven pass (Appendix C, MD-A10).

**Resolve-stage additions (`G-25`, `G-26`, `G-27`).**
- **Addressable results for the generative→act chain (`G-25`).** A `GenerativeOutcome.artifact` carries, alongside its prose + card, a list of **structured, stably-handled items** (e.g. the five gift ideas each with an id). The orchestrator retains the last generative result's items in `recentIntents` (Spec 03 §2.6), so a *following* act-then-describe turn can reference "**the second one**" (P-14: → `write GiftIdea` → `create-reminder`). The generative call itself stays read-only; only the following act reads the structure.
- **Assembly-time journal consent (`G-26`).** Journal text enters a generative prompt only by **re-assembling the prompt** with the journal included under a per-session consent — never by instructing the model to "use the journal." `pattern_insight` (P-11) rebuilds *with* journal on an opt-in; `monthly_reflection` (P-13) requires a mandatory consent card. Consent is per-session state on the assembler (Spec 08), not a model instruction — the privacy bound is at *assembly*, so a declined turn's prompt never contains journal text.
- **`foresight` generativeKind (`G-27`).** Added to the fixed set (Spec 03 §2.2a). Grounded, forward-looking synthesis (P-17): it (1) gathers what's actually upcoming — optionally via an interactive "what's on next week?" step — then (2) looks back at how *similar past situations* moved the log, and (3) returns **evidence-linked, hedged** foresight. Contract: **never a confident fabrication** with no evidence (the honest line vs DP-05's refusal to fabricate the *past* — foresight reasons about the future, it does not invent history).

**Cost note (`findings §10.1`):** the generative kinds default to **Haiku** (usable synthesis at ~$0.0007/briefing, 5–15× cheaper than Opus); Sonnet/Opus are reserved for the heaviest reasoning (`pattern_insight`, `monthly_reflection`).

### 3.11 Undo & Reversal

`undo` is a first-class system command (Spec 03 §2.3) — "reverse the most recent executed skill … within the undo window" — but v0.1 gave it no owner or mechanism, and it silently contradicted Spec 02 §5.4, which **reaps a journal entry the instant it reaches `done`**: if the record is gone, there is nothing to reverse. And even a retained entry only records what was *written*, not the prior state an update overwrote, so reversing an update is impossible without more. Both are fixed here; the pieces are already in §3.3.

- **Retention.** A completed execution is retained in the journal's bounded most-recent-completed ring for the **undo window** (default 5 minutes), then reaped (`reapExpired`, §3.3). This narrows Spec 02 §5.4's "reap at done" to "reap at end-of-undo-window," aligned in Spec 02 §5.4. **The ring must hold more than one entry** (v1 default: the last 5 completed executions, each within its window) — *not* "the last execution only" — because the **correction flow depends on it**: "Log 5k" → "logged water" → *"no, that run was a walk"* must still be able to reverse the run's write (Spec 05 §3.3 reverse-then-redispatch), and a ring of one would have evicted it the moment the water log completed. `undo` (the bare system command) still targets only the most recent entry (Spec 05 §3.5); the deeper entries exist for the orchestrator's correction reversal, which identifies its target by the corrected intent's record, not by recency. A correction arriving after the window has closed gets the honest surface — "that was a while ago; want me to just fix the record?" — an ordinary update, never a stale reversal (P2.8).
- **Before-images.** `execute` captures each written record's prior state (§3.3) — for a delete, that prior state is the **full record**. Undo builds the **inverse plan** from them: a create → `delete_record` of the minted id; an update → `write_record` restoring the captured fields (a field-merge back to the before-image, Spec 02 §3.2); a delete → `write_record` re-creating the record from its captured before-image, stamped with a fresh `lastModified` so the revival wins over its own tombstone on the acting device. Making delete undoable is what lets a record deletion follow act-then-describe (Spec 05 §3.1, D8) rather than needing the pre-action confirmation v0.1 gave it — the before-image was already being captured, so the revival is nearly free. **Carried-forward edge:** the cross-device race — the delete's tombstone syncs to another device before the undo re-creates the record — is a conflict the Data & Sync spec (Spec 06) must resolve under its last-writer-wins-by-`lastModified` model; the fresh `lastModified` on the revival is the intended tiebreaker, but confirming it across the real provider sync is a Spec 06 task. This does not block v1 (same-device undo within minutes is the common case). (*Type/skill* deletion remains genuinely non-undoable — it is a reverse migration, not a record restore — and keeps its pre-action confirmation, §3.6 / Spec 05 §24.)
- **Undo is an ordinary execution.** The inverse plan runs through the same serial-execute queue and is itself journaled (idempotent, resumable). It is **single-level**: an undo is not itself undoable, so there is no undo/redo stack to keep consistent under crash or sync in v1 (deferred, §11 Q5). 
- **Undo vs. routing correction are different signals** (Spec 03 §2.7): `undo` reverses the *action* but does not by itself zero the routing corpus entry; an `undo` followed by a `"correct"` is the negative-routing signal and flows through `recordCorrection`. The orchestrator owns that distinction; the interpreter owns only the reversal.

### 3.12 Business Logic — `AttentionSurface` (new: the queryable repair/review contract)

P2.8 requires every partial fault to reach "a visible, actionable surface" (§5.2, §5.4), and Spec 01/02 scatter repair views across startup, migration, sync, and authoring. §5.4 unifies the *pattern*; a platform also needs the *contract the UI binds to* to actually render it — v0.1 defined the surfaces in prose but gave the UI nothing to query. One read-only Business Logic surface aggregates everything demanding user attention:

```dart
abstract class AttentionSurface {
  /// A live, mergeable view of everything the app needs the user to see or
  /// act on — so the UI has one place to render P2.8's "actionable surface"
  /// rather than polling five subsystems. Cold stream; updates as items
  /// arise or clear.
  Stream<AttentionState> watch();
}
// AttentionState buckets (each item carries a userMessage + the action that clears it):
//   invalidDefinitions   — bad type/skill files (Spec 01 §5.2 / §5.4)
//   unresolvedReferences — degraded refType/parentType/automation targets (Spec 01 §5.3)
//   failedMigrations     — records left at old schemaVersion (Spec 01 §7.4)
//   lockedRecords        — sensitive records unreadable, key unavailable (§3.1, §5.4)
//   typeConflicts        — sync conflicts awaiting human review (Spec 01 §7.5)
//   pendingDrafts        — offline/free-tier authoring awaiting activation (§3.7, §6.3)
//   reviewFeed           — automation plans awaiting approval (§3.9, Spec 02 §7.5)
```

`AttentionSurface` is a *projection*, not a store: it derives from the `HydrationReport`, the registry's degraded set, the `MigrationRunner` results, `CryptoBox.keyAvailable`, the sync-conflict set, the authoring draft queue, and the `AutomationRunner`'s review feed. It owns nothing; it makes the union queryable so the repair-view pattern of §5.4 is one testable, bindable contract (a Spec 09 property: every `PlenaraError` whose surface is a repair view appears here).

### 3.13 Business Logic — `NotificationScheduler` (new: reminder & scheduled-generation delivery, `G-34`/`G-35`)

Fable F-3 surfaced a marquee gap: a `task` with `dueAt` (or an RRULE) must make the phone alert at that time, and no component armed OS notifications — `AutomationRunner` (§3.9) owns only the `automations/` registry, and a task record is not an automation. Worse, **iOS gives no reliable background execution** (BGTaskScheduler is opportunistic), so the app cannot assume it is running at fire time; delivery must be handed to the OS.

```dart
abstract class NotificationScheduler {
  Future<void> sync(RecordRef ref, DueSpec spec);        // arm/refresh; idempotent
  Future<void> cancel(RecordRef ref);
  Future<void> scheduleGenerative(String automationId, Schedule when);
}
// DueSpec = { dueAt: DateTime } | { rrule: String, from: DateTime }
```

- **At write time** a task/reminder write arms an OS-local notification (`UNUserNotificationCenter`) for its `dueAt`. An RRULE **materializes the next N occurrences** (default N = 16; iOS caps pending notifications at 64) as concrete local notifications.
- **On every app open** the scheduler re-derives and refreshes the next N occurrences of every active RRULE — since it cannot roll them forward in the background, drift is bounded to "one app-open behind."
- **Scheduled generation is NOT a background Claude call.** The 7 AM briefing (Spec 05 §15) is an OS-fired local notification whose **tap** triggers generation (detached, §4.7); if untapped, generation runs on next app-open. This is why Spec 05 §15's promise reads "waiting for you at 7 AM," not "spoken at 7 AM." Arming is fully offline; only tap-time *content* needs connectivity (degrades per §6.2). Layer: BL component; the OS calls cross to the platform channel. This is pre-v0 (even the walking skeleton's "local reminder" hits it).

### 3.14 Business Logic — `ContentSearchIndex` (new: record/journal content search, `G-34`)

`search-records` (Spec 05 §12) needs a semantic index over record and journal **content** — a different artifact from the `CapabilityIndex` (§3.4), which embeds type/skill/generative *metadata* only (Fable F-8).

```dart
abstract class ContentSearchIndex {
  Future<List<RecordRef>> search(String query, {int k = 10, Set<String>? typeScope});
  Future<void> upsert(RecordRef ref, String content);   // on record write, off-UI-isolate
  Future<void> remove(RecordRef ref);
}
```

- **Device-local and encrypted at rest** (`[app-support]/plenara/search-index/`, never synced): content embeddings are **invertible enough to leak meaning** — a journal embedding reconstructs approximate topics — so this is the mechanism behind Spec 05 §12 E4's "the embedding is not stored in the cloud." **Journal** content is embedded under the same never-synced rule as the journal itself (§3.10, `G-26`/`G-37`).
- **Incremental, not rebuilt:** `upsert` on each record write; embedding every record ever written at startup is far heavier than the ~hundred capability descriptions in the `CapabilityIndex`. A cold index builds lazily in the background; search degrades to substring match until warm (a *named* temporary degrade, P2.8 — not silence).
- **Reuses the retrieval embedder** (bge-small, §7.3.4/`G-38`) — no second model ships. Owner: a Storage-adjacent BL component; referenced by Spec 05 §12, Spec 01 §5.4.

---

## 4. The Async / Threading Model

### 4.1 The Concurrency Substrate: Isolates, Not Shared-Memory Threads

Dart's concurrency model is not shared-memory threading. A Dart program runs as one or more **isolates**, each with its own single-threaded event loop and its own heap; isolates share no mutable memory and communicate only by message-passing over ports. Within an isolate, `async`/`await` is cooperative concurrency on one thread — it interleaves tasks but never runs two Dart statements truly in parallel. This shapes every decision below: there are no data races to guard inside an isolate, but any *CPU-bound* work (model inference, embedding, crypto over a large payload, a big JSON parse) will freeze that isolate's event loop until it yields, so heavy work must be moved *off* the isolate that renders the UI.

The topology is a small fixed set of isolates, created at the composition root (§2.3):

| Isolate | Runs | Why separate |
|---|---|---|
| **UI isolate** (root) | Flutter rendering, widget tree, view models, the `DispatchOrchestrator`, the `SkillInterpreter`, the `SchemaRegistry`, the in-memory object store | Must stay responsive at 60–120 fps; holds the authoritative in-memory state |
| **Inference isolate** | The retrieval-embedding model (~80 MB, Spec 01 §5.1) — query embedding for `similarTo` and record-content search — **plus the `CapabilityIndex` vector table and its cosine scan** (§3.4). *(After the `G-20` NO-GO, Spec 03 §7.3, there is no per-turn local generative model; if a local LLM is ever reinstated as the retrieval-bounded tie-breaker, it lives here.)* | An embedding pass and a cosine scan are CPU-bound loops that would drop frames on the UI isolate |
| **IO/crypto worker(s)** | File reads/writes, encryption/decryption of large payloads, the startup folder scan, JSON (de)serialization of big batches | Bulk disk + crypto is CPU- and syscall-heavy; short one-off writes may stay inline (§4.5) |

The Business Logic spine — orchestrator and interpreter — deliberately lives **on the UI isolate**. It is not CPU-bound (it awaits IO and inference, it does not compute for long stretches), and keeping it co-resident with the in-memory object store means reads are synchronous in-memory lookups (`StorageRepository.read`/`readMany` return values, not futures — §3.1) with no cross-isolate serialization on the hot path. The expensive, parallelizable work is exactly the model and bulk-IO work, and that is what moves off-isolate. The `SchemaRegistry` also lives on the UI isolate for synchronous `lookup`, but its `similarTo` alone delegates to the inference isolate (where the vectors are, §3.4) — which is why that one registry method is `Future`-returning while `lookup`/`all`/`contains` are synchronous.

### 4.2 The Turn Pipeline as Async Stages

One user turn is a sequence of awaited stages, sequenced by `DispatchOrchestrator.dispatch` (§3.6) and surfaced to the UI as a `Stream<TurnEvent>`. Each stage names the isolate it runs on:

```
[Voice] final Transcript ──► emitted on SpeechEngine.stream          (UI isolate receives)
   │
[BL/UI] assemble NluContext (frozen clock, entityNames, recentIntents, tier)   (UI isolate)
   │
[Intel] NluRouter.route(transcript, ctx) ──► Intent                  (corpus lookup: UI isolate;
   │        corpus miss → embed + similarTo → retrieval-margin        embed/scan: INFERENCE isolate;
   │        decision (Spec 03 §7.3.1); genuine tie → ClaudeClient      cloud: network, off-isolate await)
   │        .classify (Haiku residual, Spec 03 §7.3.2)
   │
   ├─ Routing (advisory hint; transparent-routing caveat if moderate confidence)   (→ UI)
   │  or ClarificationRequested if no reliable best guess → respond(SelectCandidate) (Spec 03 §4)
   │  or (delete_type/delete_skill) ConfirmationRequested(nonUndoableDeletion) → respond(Approve|Decline)
   │        └─ barge-in / cancel possible here (§4.3)
   │
[BL] SkillInterpreter.resolve(skill, inputs, frozen) ──► ActionPlan  (UI isolate; reads = in-memory;
   │                                                                   compile-on-first-use may hop
   │                                                                   to a worker for a large skill)
   │        (no approval pause here on the interactive path — act-then-describe, Spec 05 §3.1)
   │
[BL] SkillInterpreter.execute(plan) ──► writes                       (UI isolate orchestrates;
   │        each StorageRepository.write = file write on IO worker,   IO on WORKER isolate)
   │        in-memory store updated on UI isolate; before-images captured (§3.11)
   │
[BL] exactly one corpus write-back (recordConfirmation|recordCorrection|neither)  (Spec 03 §2.7)
   │
   └─ Done(confirmationText)                                         (→ UI, and SpeechEngine.speak)
```

Two properties make this safe. First, **the frozen clock is captured once, at NluContext assembly, and threaded through** route → resolve → execute (Spec 02 §4.4, Spec 03 §2.6) — no stage re-reads the wall clock, so a slow user or a backgrounded app cannot change the result. Second, **only the final transcript enters the pipeline**; interim STT results update a live subtitle (Spec 06) but never dispatch, so a turn starts exactly once per utterance.

### 4.3 One Active Turn, Cancellation, and Barge-In

Plenara is push-to-talk-first, single-user, voice-led. The interaction model is therefore **one active turn at a time**: the orchestrator holds at most one in-flight `dispatch`, and a new final transcript that arrives while a turn is mid-flight is handled by an explicit policy rather than by racing two turns:

- **Before any write (routing/resolve/awaiting confirmation):** a new utterance, or an explicit "cancel"/barge-in (the user pressing to talk again), **cancels the in-flight turn**. Cancellation is clean because nothing has been written — the resolve phase has no side effects (Spec 02 §4.1), and a discarded `awaiting_confirmation` journal entry is reaped (it expires at `resolvedAt + maxContextAgeSeconds` anyway, Spec 02 §5.3). No corpus write-back occurs on a cancel (Spec 03 §2.7).
- **During execute (writes in flight):** execute is a short, serial sequence of atomic per-record writes (Spec 02 §4.2); it is **not interrupted** by a new utterance. The new transcript queues behind it. Because each write is idempotent on its minted id (Spec 02 §4.4), even an OS kill mid-execute resumes cleanly (§7) rather than corrupting; a mere new utterance simply waits the few milliseconds for the write group to finish.

Cancellation propagates as a cooperative signal (a cancellation token threaded into `dispatch`), not a forced isolate kill: an in-flight inference on the inference isolate is allowed to complete and its result discarded, because a half-killed model call is not worth the complexity for a single-user app, and inference is short.

### 4.4 The Serial-Execute Invariant

Spec 02 §4.4 requires that **the execute phase runs one execution at a time per device** — two concurrent execute phases could interleave writes that invalidate each other's read snapshot. The architecture enforces this with a single **execute queue** owned by the orchestrator: `SkillInterpreter.execute` calls are serialized through it, FIFO. Resolve phases (side-effect-free) may overlap freely — a second utterance can be routed and resolved while the first awaits confirmation — but the moment of *committing writes* is single-file. This is not a scaling constraint (one user, one device, a handful of writes per skill); it is the cheapest correct implementation of the invariant, and it composes with §4.3: the queue is exactly where a new turn "waits behind" an in-flight execute.

Cross-*device* concurrency is not an interpreter or orchestrator concern — it is a sync concern (Spec 06 — Data & Sync), handled by whole-file last-writer-wins plus the reconciliation of §4.5. The execution journal is device-local precisely so resume is always a same-device operation (Spec 02 §5.2).

### 4.5 Storage Concurrency and the File Watcher

The in-memory object store is owned by, and only mutated on, the UI isolate — so there is no intra-app race on it despite the IO happening on worker isolates: a `write` computes and encrypts on a worker, then the store mutation and the completion are applied back on the UI isolate's event loop. The ordering guarantee callers rely on: **a `write` future does not complete until the in-memory store reflects the write**, so a read issued after a completed `write` on the UI isolate always sees it (read-after-write consistency within the app). The file write and the store mutation are applied together before completion; a crash between them is caught by the store being rebuildable from files at next launch (§5.5). Reads never block on IO because they are served from the store (§3.1, §4.1).

**Reads during partial hydration.** The store fills incrementally at launch (§7.1), so for a brief window it is not yet complete. Two read audiences are treated differently, and the distinction is a correctness requirement, not a nicety: *display* reads (the UI browsing records to render) tolerate a partial store and simply re-render as it fills; but the *dispatch pipeline* must never resolve a skill against a half-loaded store (a `read_many` that silently missed un-hydrated records would produce a wrong action plan). The gate is already in the startup sequence — the orchestrator does not accept turns, and the `AutomationRunner` does not fire, until hydration, registry cross-referencing, pending migrations, and execution-resume are complete (§7.1 steps 2–6, before step 7 "Ready"). So every read the interpreter issues is served from a complete store, while the UI can be interactive for browsing sooner.

The one genuinely concurrent writer is **the outside world**: the OS's cloud-sync client (iCloud/OneDrive/Drive) rewrites files under the app at arbitrary times (research §8.1). `StorageRepository.watch()` surfaces those as a **debounced** `Stream<FileChangeEvent>` — debounced because sync clients often rewrite many files in a burst, and reacting per-file would thrash the registry and indexes. On a settled batch the Business Logic layer reconciles: re-hydrate changed records into the store, re-register changed type files (running any needed migration first, Spec 01 §7.4), incrementally patch the affected `CapabilityIndex` entries (Spec 01 §5.4), and — for a type-file *conflict* — surface the review UI rather than auto-merging (Spec 01 §7.5). A file change that arrives mid-turn does not mutate the turn's already-frozen inputs; it is reconciled into the store and caught, if relevant, by the execute-phase re-verify (Spec 02 §4.2).

### 4.6 Backpressure and Rate Limits

The only unbounded-cost resource is the cloud. Two limits, both enforced inside `ClaudeClient` (§3.5) so no call site can bypass them:

- **Cloud NLU escalation** is capped per session (default 20 calls/hour, Spec 03 §3.5). Above the cap, `classify` returns `CloudError(rateLimited)`, which the orchestrator surfaces as a clarification request rather than a silent stall (P2.8, §5.2).
- **Authoring and generative calls** are user-initiated and naturally low-frequency, but they still pass the same BYOK/`available` gate; an offline or keyless call returns a typed result the caller turns into a surface (§6.2), never a hung await.

Local inference has no rate limit but is naturally serialized by the single inference isolate: concurrent `route` requests (rare, since turns are serial) queue on that isolate's port rather than spawning parallel model runs.

### 4.7 Detached Operations: Long Cloud Work Never Holds the Turn Lock

The one-active-turn model (§4.3) is correct for the *interactive* pipeline — route, confirm, resolve, execute are each sub-second. But two operations are **not** sub-second: **authoring** (Sonnet, Spec 01 §6 / 02 §6) and **generation** (`GenerativeService`, §3.10) routinely take 10–30 s. If either ran inside the blocking turn, a `define_*` utterance would freeze all voice interaction for half a minute — the app would appear hung. They are therefore **detached**: the turn that triggers one emits a `Detached(operationId, kind)` event (§3.6) and **completes immediately**, releasing the turn lock; the long work proceeds in the background and reports through a small operation center.

```dart
abstract class OperationCenter {
  Stream<BackgroundOp> watch();          // in-flight + recently-finished detached ops, for a status surface
  void cancel(String operationId);       // cooperative; a cloud call in flight is abandoned on return (MD-A5)
}
// BackgroundOp: { operationId, kind ∈ {authoring, generation}, status ∈ {running, done, failed}, result?, error? }
```

This preserves both invariants at once: the turn queue stays responsive (a new utterance can be spoken while an authoring call runs), and the long operation still reaches a surface — `Detached` tells the UI to watch the operation center, and completion arrives as an `AuthoringOutcome`/`GenerativeOutcome` there (an activated capability, a delivered briefing) or a mapped error surface (§5.2). Authoring's *result* (a new registered skill/type) then flows into the registry and `CapabilityIndex` through the normal registration path, exactly as a synced-in definition would (§4.5). Detachment is why §3.6 lists `define_*` as detached and why `GenerativeService` (§3.10) is always background: neither is ever on the interactive hot path.

### 4.8 The `onWrite` Automation Hook and Cascade Bound

An `onWrite` automation (Spec 01 §4.4) fires after a specified field is written to a target type. The hook lives at exactly one place — **the completion of `StorageRepository.write` on the UI isolate** (§4.5) — where the `AutomationRunner` (§3.9) is notified of the `(typeId, recordId, changedField)` tuple. The runner matches it against registered `onWrite` automations whose `condition.targetType == typeId` and `condition.afterField == changedField` (Spec 01 §4.4) and enqueues each matched automation's skill on the serial-execute queue (§4.4). Automation-origin writes carry `origin: automation`, so their effects land in the **Review Feed** (unattended → never act-then-describe) and can never lower a skill's undoability (CLAUDE.md; Spec 02 §7.5).

**The cascade bound.** An automation's skill may itself write, which could trigger another `onWrite` — an unbounded cascade. Every write therefore carries a **cascade depth**: a user-origin write starts at `0`; a write performed by an automation is `triggering-write-depth + 1`. `onWrite` hooks fire only for writes **below the bound** (`maxCascadeDepth`, default 3); a write already at the bound still completes, but its `onWrite` hooks are **suppressed and logged** to the repair surface (§5.5). Because automations run on the serial-execute queue, a cascade is serialized, never concurrent (§4.4), so it is finite and analyzable — the bound Spec 02 §7.5 requires.

### 4.9 Freshness: no stale caches in the async model

The async model caches exactly one user-facing thing: the corpus **routing** decision (Spec 03 §5) — slot *shapes* and the route, never slot *values*, never a resolved plan, never a generative effect. Everything else is recomputed:
- **Generative outputs are never cached** — regenerated every turn; their whole value is being current (Spec 05 §3.8).
- **The plan cache is deferred** (Spec 02 §5.5) — resolution is re-run each turn (deterministic, cheap).
- **The in-memory object store** (§3.1) is hydrated at startup (§7) and kept coherent by the file watcher (§4.5): a synced-in edit invalidates the cached object, so a read never serves a stale record.

Net: nothing user-facing is served stale. The one cache (routing shape) is correctness-neutral — a wrong shape merely re-routes, it never returns wrong data.

---

## 5. Error Handling — the Sealed Taxonomy and the Surfacing Contract

This section satisfies **P2.8 — no silent failure** end to end (§0 item 3): a sealed error set, a total mapping from every terminal error to an actionable surface, translation across seams, and the crash/repair consolidation.

### 5.1 The sealed error model

Every fallible interface either returns a **value-typed result** for an *expected* outcome or throws a **sealed error** for an exceptional fault — never a raw exception across a boundary. Value results put the failure case in the type so a caller cannot forget it: `CloudResult<T> = Ok(T) | CloudError(kind, message)` (§3.5), and likewise `StorageResult`, `AuthoringOutcome` (§3.7), `GenerativeOutcome` (§3.10). Exceptional faults are a sealed `PlenaraError` hierarchy (Dart `sealed class` → exhaustive `switch`, so a new variant is a compile error until every surface handles it):

| layer | sealed set |
|---|---|
| Intelligence | `CloudError{offline, rateLimited, authFailed, policyBlocked, serverError}` |
| Storage | `StorageError{notFound, conflict, ioFailed, corrupt}` |
| Schema/Interpreter | `SchemaError{typeNotFound, versionTooNew, validationFailed}` · `SkillError{unresolvedRef, opFailed(index)}` |
| NLU | `NluError{ambiguous, noCandidate}` |
| Authoring | `AuthoringError{validationFailed, declined, draftOnly}` |

### 5.2 The surface map — every terminal error is actionable

No error is a swallowed null; each maps to a spoken/text surface plus an offered action:

| error | surface + action |
|---|---|
| `CloudError.offline` | "That needs an internet connection — remind you when you're back?" → reminder (Spec 05 §13) |
| `CloudError.rateLimited` | "I've hit today's limit on Claude." → retry-later |
| `CloudError.authFailed` | "Your API key was rejected." → open settings |
| `CloudError.policyBlocked` | the caring decline (Spec 02 §7.6) — names what and why |
| `StorageError.conflict` | "This changed since I read it — redo with the new version, or keep yours?" (§4.5) |
| `StorageError.corrupt` | routed to the repair surface (§5.5), not an interrupt |
| `SchemaError.typeNotFound` | clarify, or offer to author (Spec 03 meta-intent) |
| `SchemaError.versionTooNew` | "This skill needs a newer Plenara." → update |
| `AuthoringError.validationFailed` | "I couldn't build that cleanly — saved a draft." (Spec 02 §6.4) |
| `NluError.ambiguous` | the clarify surface (`SelectCandidate`, Spec 03 §7.3) |

### 5.3 Translation across boundaries

An error is translated into the *caller's* vocabulary at each seam, never leaked raw. Storage's `ioFailed` becomes a BL `SkillError.opFailed(index)` carrying the failed op index (so undo/repair know where the plan stopped); the UI only ever reasons about the Business-Logic error vocabulary, never a file-system exception. Translation is where the §5.1 sealed sets connect — each layer maps the layer-below's set into its own — and it is what keeps the dependency rule (§2.2) intact under failure.

### 5.4 Crash and mid-execution recovery

The execution journal (Spec 02 §5) makes a partial write recoverable. If the app dies mid-execute, startup (§7) finds the one `ExecutionRecord` in state `executing` (the serial-execute invariant, §4.4, guarantees at most one in flight, so recovery is unambiguous) and uses its before-images (Spec 02 §5.4) to deterministically **roll the partial plan back** to the pre-turn state — or complete it, if every op's before-image is present and the after-images still match. A `done` entry past its undo window is reaped. No partial turn is ever left half-applied and invisible.

### 5.5 The repair surface — consolidating non-fatal inconsistency

Inconsistencies that are not a single turn's failure — a dangling `entityRef` after a tolerate-dangling delete (Spec 02 §3.2), a corrupt record file, a skill referencing a removed type, a suppressed cascade (§4.8) — are **consolidated into the queryable repair surface** (`AttentionSurface`, §3.12), each with a suggested fix, rather than fired as interrupts. This is where §0's promise to "consolidate the partial-failure handling scattered across Specs 01–03" is kept: one review place, act-then-describe repairs, never a modal mid-capture.

---

## 6. Offline Behavior

### 6.1 The offline contract — what runs with the radio off

The entire **free tier** runs offline to completion (§1): capture, recall, every deterministic skill, undo, migration, storage, and **all of NLU routing** — which after the `G-20` NO-GO is fully local in the common path (corpus fast-path + retrieval-margin + deterministic slot extractors, Spec 03 §7.3; no cloud classify step to lose). No base-tier interface makes a network round-trip mandatory. Connectivity is a value the `ClaudeClient` exposes (`available`), not a thing callers poll — offline is a *typed case*, not an exception (§3.10).

### 6.2 Cloud-dependent operations degrade to a surface, never a dead end

There are exactly three cloud touchpoints, each with a defined offline degrade:
- **NLU residual escalation** (Haiku, only the genuine tie, Spec 03 §7.3) → offline: **clarify** (the deterministic floor), so routing still completes — the model was never on the common path.
- **Authoring** (`define_*`) → offline *or* free/keyless: produces a **`Drafted`** outcome (§3.7), not an activation (Spec 01 decision: offline may draft; activation requires Claude).
- **Generation** → offline: the three-surface degrade (Spec 05 §13), never a fabricated local imitation.
Each returns a typed `CloudError` the caller turns into a §5.2 surface.

### 6.3 Drafts and activation on reconnect (the connectivity/queue model)

Offline/free-tier authoring accumulates **`pendingDrafts`** (§3.7) — inert, not registered capabilities. On reconnect with a key, the app does **not** auto-activate: it surfaces the drafts in the Review Feed for the user to activate, and each activation runs the deferred authoring call (validate → safety review §7.6 → register). Connectivity returning never silently changes the capability set — the user stays in control, and "AI authors, code executes" is preserved. There is deliberately **no automatic action-queue** for paid flows (a user may not want to wait, Spec 05 §13); the only "queue" is the explicit draft list plus any reminders the user opts into.

---

## 7. Startup and Resume

### 7.1 Cold start

On launch, before the turn pipeline (§4.2) accepts any utterance, the app runs a fixed, **fully offline** sequence:
1. Open the storage folder; **hydrate the in-memory object store** (§3.1) from the per-record JSON files.
2. Build the `CapabilityIndex` (§3.4) from the registered type/skill definitions.
3. Load the corpus (Spec 03 §5) from device-local encrypted storage.
4. **Journal recovery** (§5.4): roll back or complete any `executing` `ExecutionRecord`; reap `done` entries past their window.
5. Start the file watcher (§4.5) so external/synced edits keep the cache coherent thereafter.

The journal and corpus are device-local/encrypted (never synced), so they load from app-support; records load from the possibly-syncing storage folder. A file that fails to parse during hydration is routed to the repair surface (§5.5) and **does not block startup** — the rest of the store loads, so one corrupt record never bricks the app. No startup step touches the network.