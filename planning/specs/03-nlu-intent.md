# Spec 03 — NLU / Intent

**Status:** v0.5 — July 2026 (Sonnet skeleton v0.1 → Opus hardening v0.2 → Opus 4.8 design-level review v0.3 → act-then-describe reconciliation v0.4 → generative-request routing v0.5; bones challenged, calls made and recorded — see Decision Record §11 and review-logs Appendix B/C/D/E)  
**Depends on:** Spec 01 — Meta-Schema & Type System (§4.1, §5.4, §6, §8.2, §8.7); Spec 02 — Skill DSL (§2.2, §2.3, §4.4, §5.5, §7.1, §7.3)  
**Blocks:** Architecture spec, UI spec

---

## 0. Purpose & Scope

The NLU layer is the boundary between a raw voice utterance and the deterministic skill execution system. It receives the transcript of what the user said and must produce — as its only output — a structured intent object: which skill (or meta-intent) to invoke, with what slot values, at what confidence. The interpreter takes it from there.

This document specifies:

1. The intent taxonomy — the complete, closed set of intent categories the NLU layer may produce
2. The retrieval-augmented routing architecture — how an utterance is routed to a skill over a growing, open-ended type space
3. The confidence-threshold policy — when to act, when to clarify, when to escalate to cloud
4. Confidence decay — how stale or repeatedly-corrected routing entries lose authority
5. The flow table — the single on-disk structure that unifies the corrections corpus (utterance → intent, built in v1) with the deferred plan cache (intent → plan, hooked but not built)
6. Slot extraction — how the NLU layer fills the `source: "slot"` inputs declared in a skill's `inputs` contract
7. The recorded test-pair methodology — how NLU correctness is measured and regressed against

It does **not** cover: speech-to-text transcription (Spec 06 — Voice), skill execution (Spec 02), type and skill authoring flows (Spec 01 §6, Spec 02 §6), or view rendering (Spec 07 — UI).

---

## 1. Governing Principles

**P2.4 — Code over AI.** The NLU layer is the narrowest point where a model is in the loop. Its job is classification and extraction — discrete, verifiable outputs that deterministic code then executes. A model is never called to *execute* a skill step, evaluate a branch condition, or write a record. The output of NLU is a structured data object; everything downstream of it is pure code.

**P2.1 — Voice is uncompromising and free-form.** The user does not learn Plenara's vocabulary; Plenara learns theirs. The NLU layer must accommodate natural, varied phrasing — including incomplete sentences, filler words, corrections mid-utterance, and time-relative expressions ("the usual", "again", "like yesterday"). The corrections corpus (§5) is how the system accumulates this knowledge over time.

**P2.4 — Code over AI, applied to routing.** Routing a known utterance against the corrections corpus is a hash-lookup, not an inference call. The local model is invoked only when the corpus has no match. Cloud escalation is invoked only when the local model is below threshold. Inference is the slow path, not the default.

**P2.5 — Aggressive layering.** The NLU layer is a pure function from `(transcript, NluContext)` to an intent object (the `NluRouter` interface, §2.6; `NluContext` defined there). It calls no storage APIs directly and emits no UI events. It **reads** the capability embedding index and the corrections corpus, and it reads skill and type metadata from the `SchemaRegistry`, all read-only. Critically, it does **not own or build** the embedding index: that index is a `SchemaRegistry`-layer artifact (Spec 01 §5.4), extended to cover skills as well as types (§3.2), and the router only queries it. The NLU layer *owns* one piece of mutable state — the corrections corpus (§5) — and even that it mutates only through an explicit write path, never as a side effect of routing. It is invoked by the Business Logic layer after transcription completes (Spec 06 signals a final transcript, §10 MD10) and before skill dispatch begins.

**P2.8 — No silent failure.** The NLU layer is the sharpest test of this principle, because guessing is always the tempting shortcut. It never takes it. When confidence is genuinely low it returns a `clarification_needed` intent rather than a silent guess (§2.4); when a required slot is missing it asks a follow-up rather than dispatching a partial intent (§6.3); when an utterance needs a capability that does not exist it raises a `define_*` meta-intent (and, on the free tier, an explicit upgrade prompt) rather than dropping the request (§2.2); and when the cloud is unreachable it flags `cloudUnavailable` so the app can tell the user and queue, rather than degrading quietly (§10 MD6). Every low-confidence or blocked path in this spec ends at a user-visible surface, never a dead end.

---

## 2. Intent Taxonomy

Every NLU output is one of the following intent categories. The set is closed at the category level; individual skill-invocation intents grow with the user's skill library. No code may dispatch on a category not listed here without an NLU spec version bump.

### 2.1 Skill-Invocation Intents

The normal case. The user's utterance maps to an existing skill in the skill library. The NLU layer produces a `skillId` and a slot-fill map.

```json
{
  "category": "skill_invocation",
  "skillId": "log-meal",
  "slots": {
    "capturedDescription": "chicken salad",
    "capturedCalories": 480,
    "capturedMealType": "lunch"
  },
  "confidence": 0.91,
  "routingSource": "corpus_hit"
}
```

`routingSource` records how the intent was derived — one of the values enumerated in §2.5. For a skill invocation it is typically `corpus_hit` (flow-table fast path), `local_model` (local inference), `cloud_model` (Haiku escalation), or `anaphora` (resolved from `recentIntents`, §5.4a). This field is never shown to the user; it feeds the test-pair recorder (§7), the confidence-decay model (§4.2), and the boost-vs-create choice in the write paths (§2.6).

### 2.2 Capability-Definition Meta-Intents

Intents that operate on the capability system itself — type authoring and skill authoring — rather than on user data. These are the bridge between an utterance that has no matching skill and the authoring flow defined in Spec 01 §6 and Spec 02 §6.

There are two capability-definition meta-intents:

**`define_type`** — The user's utterance expresses a need that cannot be served by any existing type or skill, and the NLU layer judges that the domain is novel enough to warrant a new type definition. Control passes to the cloud (Haiku or Sonnet) to author the type, then optionally the skill.

```json
{
  "category": "define_type",
  "inferredDomain": "sleep tracking",
  "seedPhrases": ["track my sleep", "log how long I slept"],
  "confidence": 0.78
}
```

`inferredDomain` is a best-effort label for the authoring prompt; it is not persisted anywhere. `seedPhrases` primes the new type's `examplePhrases` array (Spec 01 §4.1).

**`define_skill`** — A type exists for the domain, but no skill handles the requested operation on that type. The NLU layer resolves the type but cannot match a skill. Control passes to the cloud to author a skill against the existing type.

```json
{
  "category": "define_skill",
  "resolvedTypeId": "meal",
  "requestedOperation": "delete my last meal entry",
  "confidence": 0.83
}
```

Both meta-intents are cloud-only paths — the local model can raise them, but execution always escalates. They are BYOK-gated (paid tier). On the free tier, a `define_type` or `define_skill` result surfaces a "this would create a new capability — upgrade to unlock" prompt rather than initiating authoring.

**When to produce a capability-definition meta-intent vs. a low-confidence skill invocation.** The threshold is whether the NLU layer's retrieval step returns any skill in the candidate set with cosine similarity above `θ_meta` (see §4.1). If no candidate clears `θ_meta`, the utterance is treated as potentially novel and the confidence decay and cloud-escalation steps (§4.3) are skipped in favour of the simpler "does any type match?" check:

- Top retrieved type has similarity ≥ `θ_type` → `define_skill`
- Nothing clears `θ_type` → `define_type`
- Everything below `θ_type` AND the utterance is very short or is a recognized system command → consider `system_command` (§2.3)

### 2.2a Generative-Request Intents (Paid)

Intents that ask Plenara to *synthesize* something over the user's records rather than capture or query a single fact — a spoken morning briefing, gift ideas for a contact, social-event prep, reconnect coaching, a weekly priority review, a cross-tracker pattern insight, a meal suggestion, a monthly reflection (research §7.2, §10; the marquee paid tasks P2–P9, Spec 05 §§15–22). They are **not** skill invocations: a skill may not invoke a model at runtime (Spec 02 §8.4, P2.4), so these features are produced by the `GenerativeService` (Spec 04 §3.10), not the interpreter. Giving them their own category is what lets a *spoken* request reach them — closing the routing gap Spec 04 §3.10 surfaced and left open as its Q6 (a generative feature had no home in this taxonomy, reachable only by a scheduled automation or a UI affordance — a direct contradiction of P2.1, "voice is uncompromising," for seven of the ten paid marquee tasks).

```json
{
  "category": "generative_request",
  "generativeKind": "gift_ideas",
  "params": { "contactRef": "sarah-mitchell", "budget": 50 },
  "confidence": 0.88,
  "routingSource": "local_model"
}
```

`generativeKind` is one of a **fixed, binary-shipped set** — `briefing`, `gift_ideas`, `event_prep`, `reconnect_coaching`, `weekly_review`, `pattern_insight`, `meal_suggestion`, `monthly_reflection` — closed like the primitive-op vocabulary, because each maps to a reviewed `GenerativeService` prompt assembler (Spec 04 §3.10), never to authored or fetched code. `params` carries whatever that kind needs, resolved by the **same slot machinery as a skill invocation** (§6): an `entityRef` for the target contact ("what should I get **Sarah**"), a temporal window ("the last two weeks"), a budget. A required param that is absent takes the normal missing-slot follow-up (§6.3) — "prep for dinner with whom?" — and is never silently guessed (P2.8).

**Recognition.** Generative capabilities are indexed in the `CapabilityIndex` as a third candidate kind (`kind: generative`, Spec 04 §3.4), embedded over the same human-readable surface a skill uses (name, description, example phrases). Routing ranks them alongside skills and types (§3.3–§3.4); when the top candidate is `kind: generative` and clears `θ_act` (or the moderate band, acted on with transparent routing like any other), the router emits a `generative_request`. The built-in set is small and fixed, so its example phrases ship in the binary and are strong retrieval anchors.

**Tier, cloud, and why there is no fast path.** Every generative kind requires Claude, so `generative_request` is BYOK-gated exactly as the capability-definition meta-intents are (§2.2): on the free tier the router still *produces* the intent and the orchestrator surfaces the paid-upgrade prompt (Spec 05 §3.6) rather than spending a shared key. Generation is always a multi-second **detached** cloud call (Spec 04 §3.10, §4.7), so a corpus fast-path entry would save nothing — the corpus exists to skip *inference* on high-frequency capture, and a generative request pays seconds of generation latency regardless. The fast path (§5) is therefore scoped to skill invocations; a generative request re-routes each turn at the cost of one cheap local classification, negligible beside the generation it triggers. (This is also why the corpus write paths, §2.6, are typed to `SkillInvocation` and are never called on a generative turn.)

### 2.3 System Meta-Intents

Out-of-band commands that control Plenara itself rather than creating or querying user records. These are handled by the app shell, not by the skill interpreter.

| `systemCommand` | Meaning |
|---|---|
| `undo` | Reverse the most recent executed skill (if the skill's action plan is still in the journal's `done` state within the undo window). |
| `correct` | The most recent routing or slot-fill was wrong; open the correction flow (§5.2). |
| `cancel` | Dismiss the current pending confirmation without executing. |
| `show_pending` | Surface the review feed of awaiting-confirmation automation-originated plans. |
| `help` | Open the capability-discovery UI ("what can Plenara do?"). |

```json
{
  "category": "system_command",
  "systemCommand": "undo",
  "confidence": 0.97
}
```

System commands are seed intents recognized by a simple rule-based pre-filter before the retrieval step, so they do not consume a model call. The pre-filter matches normalized lemmas ("undo", "cancel", "go back", "never mind", "that's wrong", "wait") against a fixed phrase table. A match short-circuits to a system-command intent; a near-miss that does not clear the pre-filter's threshold falls through to the normal retrieval pipeline.

### 2.4 Clarification Request

When the NLU layer cannot produce any intent at sufficient confidence — and cloud escalation has been used and returned a score still below threshold — the result is a clarification request rather than a guess.

```json
{
  "category": "clarification_needed",
  "candidates": [
    { "skillId": "log-meal", "confidence": 0.54, "summary": "log a meal" },
    { "skillId": "log-interaction", "confidence": 0.48, "summary": "record a conversation" }
  ],
  "prompt": "Did you mean to log a meal, or record a conversation?"
}
```

`candidates` are the top-K retrieval results; each `summary` is the candidate skill's `displayName` (Spec 02 §2.2), not its `captureIntent` label (§8.1). `prompt` is a generated disambiguation question. The NLU layer never guesses silently when confidence is genuinely low.

### 2.5 The Intent Object

Every NLU output is a single intent object. It is never a list. The category determines which other fields are present.

| Field | Type | Always present | Notes |
|---|---|---|---|
| `category` | enum | yes | One of: `skill_invocation`, `define_type`, `define_skill`, `system_command`, `clarification_needed`, `generative_request`. |
| `confidence` | float [0, 1] | yes | The NLU layer's confidence in this intent. See §4. |
| `routingSource` | enum | yes | The `RoutingSource` enum, closed: `corpus_hit`, `local_model`, `cloud_model`, `rule_match` (system commands, §2.3), `anaphora` (resolved from `recentIntents`, §5.4a). Feeds the test-pair recorder, the decay model, and the write-path boost-vs-create choice (§2.6). |
| `skillId` | string | if `skill_invocation` | The `skillId` of the skill to invoke. |
| `slots` | object | if `skill_invocation` | Key-value map of slot names (matching `source: "slot"` input names in the skill's `inputs` contract, Spec 02 §2.3) to extracted values. Partial fills are permitted for optional slots. |
| `systemCommand` | enum | if `system_command` | |
| `candidates` | object[] | if `clarification_needed` | |
| `prompt` | string | if `clarification_needed` | |
| `resolvedTypeId` | string | if `define_skill` | |
| `requestedOperation` | string | if `define_skill` or `define_type` | |
| `inferredDomain` | string | if `define_type` | |
| `seedPhrases` | string[] | if `define_type` | |
| `generativeKind` | enum | if `generative_request` | One of the fixed set in §2.2a. |
| `params` | object | if `generative_request` | Resolved slots for the generative assembler — contact `entityRef`, temporal window, budget (§2.2a). |

The intent object is immutable once produced. The NLU layer does not modify it after handing it to the Business Logic layer. If the user makes a correction, a new intent is produced from the correction flow (§5.2), not by patching the old one.

### 2.6 The NLU Interface Contract

Spec 01 gives the type system a `SchemaRegistry` interface and Spec 02 gives the DSL an interpreter seam; this spec owes the same — the single function the Business Logic layer calls, and the shapes it passes and receives. Everything else in this document is the *implementation* behind this contract. Downstream specs (Architecture, UI) bind to this signature, not to the pipeline internals.

```dart
abstract class NluRouter {
  /// Route a final utterance transcript to exactly one Intent.
  /// Pure with respect to storage: reads the corpus, the capability index,
  /// and the SchemaRegistry; performs no writes. Corpus mutation happens
  /// only via [recordCorrection] / [recordConfirmation], never here.
  Future<Intent> route(String transcript, NluContext context);

  /// A targeted second-pass extraction answering a follow-up question for
  /// a single missing slot (§6.3). Skips routing; does not re-classify.
  Future<Intent> resolveFollowUp(
      ClarificationNeeded pending, String slotName, String answer, NluContext context);

  /// Write paths — the only ways the corpus changes (§5.2). These are
  /// explicit calls from the dispatch orchestrator after the user acts
  /// (§2.7), not side effects of [route]. Each takes the original
  /// [transcript] because the corpus key is a template built by normalizing
  /// and slot-abstracting that transcript (§5.4); the router cannot
  /// reconstruct it from an [Intent] alone (the Intent carries resolved
  /// slot values, not the surface phrasing or its spans).
  Future<void> recordCorrection(
      String transcript, SkillInvocation corrected, NluContext context);
  Future<void> recordConfirmation(
      String transcript, SkillInvocation accepted, NluContext context,
      {required ConfirmationKind kind});

  /// Test-mode entry point (§7.3): runs the full pipeline against one pair
  /// and returns the actual intent without mutating the corpus or dispatching.
  Future<Intent> testPair(TestPair pair, NluContext context);
}

/// How a confirmed routing was earned — selects the new entry's `source`
/// and initial confidence (§4.2), and (with [SkillInvocation.routingSource])
/// whether an existing corpus entry is boosted or a new one is created.
/// Under act-then-describe (Spec 05 §3.1) `implicit` — the user left the
/// result uncorrected — is the common case; `clarificationSelected` is the
/// user explicitly picking this routing at a clarification prompt (§4.3).
enum ConfirmationKind { implicit, clarificationSelected }
```

**Why the write paths take a transcript, not just an `Intent`.** The v0.1/v0.2 signature `recordConfirmation(Intent, {viaPreConfirm})` could not do its job: building or finding the corpus entry requires the *normalized template* of what the user actually said (§5.4), and an `Intent` carries only the resolved `skillId` + slot **values**, not the surface phrasing or the spans templating needs. Passing the transcript (and `NluContext`, for the entity/temporal placeholders) makes both write paths self-contained. Whether a call **boosts** an existing entry or **creates** a new one is decided from `accepted.routingSource`: a `corpus_hit` re-normalizes, re-matches (§5.4), and boosts the matched entry; a `local_model`/`cloud_model` routing templatizes the transcript against `accepted.slots` and inserts a new entry. `recordCorrection` always zeroes any entry currently matching the transcript's template and inserts a fresh `explicit_correction` entry (§4.2).

**`Intent` is a sealed hierarchy**, not a bag of nullable fields. The flat table in §2.5 documents the wire/JSON form (what is persisted and logged); in code it is a sum type so the dispatcher's `switch` is exhaustive and the illegal states of §2.5 (a `skill_invocation` with no `skillId`, a `clarification_needed` with no `candidates`) are unrepresentable:

```dart
sealed class Intent { double get confidence; RoutingSource get routingSource; }
class SkillInvocation   extends Intent { String skillId; Map<String,Object?> slots; }
class DefineType        extends Intent { String inferredDomain; List<String> seedPhrases;
                                         String requestedOperation; bool cloudUnavailable; }
class DefineSkill       extends Intent { String resolvedTypeId; String requestedOperation;
                                         bool cloudUnavailable; }
class SystemCommand     extends Intent { SystemCmd command; }
class GenerativeRequest extends Intent { GenerativeKind kind; Map<String,Object?> params; } // paid; → GenerativeService (Spec 04 §3.10), never the interpreter
class ClarificationNeeded extends Intent { ClarificationKind kind;   // ambiguous | missingSlots
                                           List<Candidate> candidates;
                                           SkillInvocation? partialIntent;
                                           List<MissingSlot> missingSlots; String prompt; }
```

**`NluContext`** is the read-only snapshot the router needs to be a pure function. Naming it here settles what §1's "context" actually contains — the draft used the word without defining it, and two of these fields (`recentIntents`, `pendingConfirmation`) are load-bearing for behaviour the governing principles demand but the pipeline otherwise dropped (anaphora, §5.4a; and interpreting `undo`/`correct`/`cancel`, §2.3):

| Field | Purpose |
|---|---|
| `now`, `today`, `zone` | Frozen capture-time clock for temporal-slot resolution (§6.2). Passed in — never read from the system clock inside the router — so routing is reproducible and testable (mirrors Spec 02 §4.4 frozen inputs). |
| `entityNames` | An **entity-name resolver** keyed by `refType`: `resolve(refType, token) → List<(id, displayName)>` over the in-memory instances of that type, backed by the registry/storage layer (not built by NLU). Used both for name tokenization during normalization (`{e:refType}` placeholders, §5.4) and `entityRef` slot resolution (§6.2) — one resolver, two uses. v1 populates `contact` (the dominant case — most `entityRef` slots point at people) and extends to any entity type a skill actually references by name (§10 MD7); the router is not contact-hardcoded. |
| `recentIntents` | A short bounded ring (default last 5) of successfully-dispatched intents this session, with their skill and resolved slots. The antecedent store for anaphoric utterances — "again", "the usual", "like yesterday" (§5.4a). Session-scoped, never persisted. |
| `pendingConfirmation` | The routing/plan currently awaiting the user's yes/no, if any. Lets the pre-filter interpret a bare "yes"/"no"/"that's wrong" as `cancel`/`correct` against a specific target rather than as a fresh utterance (§2.3). |
| `tier` | `free` or `paid` (BYOK key present). Gates cloud escalation (§3.5) and capability-definition authoring (§2.2) without the router calling into settings. |

The router never mutates `NluContext`; the Business Logic layer assembles a fresh snapshot per utterance. This keeps `route` referentially transparent, which is what makes the recorded test-pair methodology (§7) a true regression harness — the same `(transcript, context)` always yields the same `Intent`.

### 2.7 The Dispatch Seam & Corpus Write-Back Lifecycle

`route` produces an `Intent`; something must then *drive* it — resolve and execute the skill (Spec 02 §4), act-then-describe (or, where the routing is genuinely ambiguous, clarify first), catch a mid-flight `"correct"`, and call the write paths (§2.6) so the corpus learns. The draft left this orchestration scattered across "a UI concern" (§5.2), "the Business Logic layer" (§1), and "the Architecture spec" (§3.2), which meant the `recordCorrection`/`recordConfirmation` calls had **no defined caller, timing, or precondition** — the corpus could not actually be written. This section pins the seam. It does not build the orchestrator (that is Architecture/UI); it states the contract the orchestrator must satisfy so NLU's write paths are well-defined and the whole "utterance → action → learned routing" loop closes.

**Ownership.** A **dispatch orchestrator** in the Business Logic layer owns the turn. NLU exposes only `route` + the write paths and never drives the interpreter; the interpreter (Spec 02) never calls NLU. The orchestrator is the one component that touches both. Its concrete interface is the Architecture spec's `DispatchOrchestrator` (§3.6): the turn's user-visible states flow **out** as a sealed `TurnEvent` stream, and the user's decisions at each surface below — approve / decline / **correct** / candidate-select / accept-residual — flow **back in** via `respond(promptId, TurnResponse)` (with `cancel(turnId)` for barge-in). The lifecycle prose here is the contract that interface satisfies.

**One conditional surface, not two (v0.4).** v0.3 defined two approval surfaces — an NLU *routing* pre-confirmation before resolve and a *skill-plan* confirmation after. Act-then-describe (Spec 05 §3.1) removes both from the interactive path: the skill-plan pre-approval is gone with `confirmationPolicy` (Spec 02 §7.1), and a routing that can be acted on is acted on and described, not pre-confirmed. What survives is a single **conditional** surface — a **clarification**, shown *before* resolve only when the app has no reliable best guess (no dominant candidate below `θ_cloud_escalate`/`θ_minimum`, or a `requiresPreConfirm` pattern, §4). It is answered by `SelectCandidate` (a genuine choice), not by an Approve/Decline of a single guess. After it (or immediately, when it is not shown), the skill resolves, executes, and is described; a `"correct"` at any point re-routes.

**Turn lifecycle for a `skill_invocation`** (other categories resolve at the seam: `system_command` → app shell; `clarification_needed` → prompt then `resolveFollowUp`; `define_*` → authoring subsystem, tier-gated; `generative_request` → `GenerativeService` as a detached, read-only, tier-gated operation, Spec 04 §3.6/§3.10 — no resolve/execute pass and no corpus write-back, since it writes no records and re-routes each turn, §2.2a):

```
route() → SkillInvocation
   │
   ├─ clarify? (no reliable best guess / requiresPreConfirm)
   │        ├─ "correct" (+ restatement) ─────────► recordCorrection ─► re-route
   │        ├─ candidate selected ──────────────────┐  (clarificationSelected noted)
   │        ├─ declined, no restatement ───────────► cancel (no write-back)
   │        └─ not shown (reliable / best-guess) ───┤
   ▼                                                ▼
Spec 02 resolve → action plan
   │   (no approval pause on the interactive path — act-then-describe)
   ├─ "correct" before write commits ─────────────► recordCorrection ─► reverse + re-route
   ▼
Spec 02 execute → done → describe(confirmationText) ─► recordConfirmation(kind)
```

An unattended **automation** invocation is the exception: its writes are held for Review-Feed approval (Spec 02 §7.5, Spec 04 §3.9) rather than described — no user is watching to catch and undo. That path does not run `route` (there is no utterance) and does not touch the corpus.

**Write-back rules (the orchestrator's obligation to NLU).** Per dispatched `skill_invocation` turn, the orchestrator calls **at most one** write path:

- **`recordCorrection(transcript, corrected, ctx)`** — the moment the user issues `"correct"` (§2.3) against the produced routing, whether at the clarification surface or after the app has acted-and-described (in which case the orchestrator also reverses the prior write, Spec 05 §3.3, before re-routing). The restatement is re-routed (cloud/model, no corpus lookup — the corpus is being corrected, §5.2), and the *corrected* `SkillInvocation` is what is dispatched.
- **`recordConfirmation(transcript, accepted, ctx, kind)`** — when the skill reaches `done` without a `"correct"` (i.e., the user let the act-then-describe result stand). `kind = clarificationSelected` if a clarification was shown and the user picked this candidate this turn; otherwise `kind = implicit` (the common case — a best guess left uncorrected). Combined with `accepted.routingSource` (§2.6), this boosts the matched corpus entry (a `corpus_hit`) or creates one (a `local_model`/`cloud_model` routing) — the mechanism by which a model-routed utterance graduates into the fast path.
- **Neither** if the user merely *cancels* — declines a clarification without restating (a bare "no"), or says `undo` for a reason unrelated to routing. A cancel is not evidence the routing was *wrong*, only that the user changed their mind, so the corpus is left untouched. (A `"correct"` is different: it supplies the right target, so it goes to `recordCorrection`. A decline gives no replacement to learn.)

**Undo is the interactive safety net, not a routing signal by itself.** Because act-then-describe means most skills execute with no approval surface at all (Spec 02 §7.1), the net for a wrong result is the `undo` system command (§2.3) over its post-completion window (Spec 04 §3.11). `undo` reverses the *action* but does **not** by itself zero the routing entry (a user may undo for reasons unrelated to routing); an `undo` *followed by* a `"correct"` is the negative-routing signal and flows through `recordCorrection`. Until corrected, a completed skill records `implicit` confirmation like any other.

**Compound utterances (§10 MD8).** Before dispatch, the orchestrator checks for a coordinator ("and", "also", "then") splitting the transcript into two fragments that **each** independently route above their act threshold. If found, it dispatches the primary through the lifecycle above and **queues the residual** — offering it right after the primary completes ("Done — you also said remind you to call Sam; do that now?") — so the second intent is never silently dropped. `route` stays single-intent (§2.5): the orchestrator simply calls it again on the residual segment. The conservative "both fragments must independently route" test avoids false splits ("salt and pepper"). Simultaneous multi-intent (one confirmation spanning both) remains deferred.

This is the seam every Plenara action is built on: `route` classifies, the orchestrator drives Spec 02, and exactly one write-back per turn feeds the corpus so the next identical utterance is faster and surer.

---

## 3. Retrieval-Augmented Routing

### 3.1 The Routing Problem

A 1B–3B parameter local model cannot hold the definition of every type and skill in its context window. As the user's library grows — adding custom types for sleep tracking, gift ideas, expense logging, and more — the set of possible targets for any utterance grows with it. A naïve "put all skills in the prompt and classify" approach hits the context limit after a handful of skills and degrades gracefully to nothing.

The solution is two-stage retrieval: use a compact embedding to narrow the search space to a small candidate set, then use the local model only to discriminate among the candidates. The model sees a few definitions, not dozens. The search is fast and scales with the library size.

### 3.2 The Capability Embedding Index

Each skill and each type has an embedding vector derived from its human-readable metadata. The embedding captures the semantic space of phrases a user might say to invoke that skill or describe that type.

**Ownership — this index already exists; the NLU layer does not build a second one.** Spec 01 §5.4 defines an embedding index owned by the `SchemaRegistry`, built over each type's `displayName + description + examplePhrases`, held in memory, and exposed to NLU via `SchemaRegistry.similarTo(query)` returning ranked `(typeId, score)` pairs. The v0.1 draft of this section re-invented that index as an NLU-owned artifact with its own file (`nlu/embeddings.bin`) and its own rebuild triggers — a duplicated owner for the same data, and a direct violation of P2.5. **Resolved (v0.2): there is one capability index, owned by the registry layer, and the router only queries it.** What v0.1 got right is that the index must also cover **skills**, which Spec 01's type-only index does not yet do. The resolution is symmetric extension, not a parallel index:

- The `SchemaRegistry` index over **types** stands as specified in Spec 01 §5.4.
- A parallel **skill** index is owned by the skill-registry surface (the component that owns `skills/`, Spec 02 §2.2 / §6.1 — its formal interface is defined in the Architecture spec). It is built over the same fields the draft identified, and NLU queries it through the same `similarTo`-shaped call.
- The router treats these as one logical **`CapabilityIndex`** with a single query returning a merged, kind-tagged ranked list `(id, kind ∈ {skill, type, generative}, score)` — the third kind covering the fixed built-in generative capabilities (§2.2a, Spec 04 §3.4). Whether that is one physical index or several behind a façade is an Architecture-spec implementation choice; the NLU contract is the merged query.

This is a **[RECONCILE]** with Spec 01, not a new mechanism: it deletes an ownership conflict and adds the one genuinely missing piece (skills in the index).

**Sources for the embedding.** Per Spec 01 §5.4 for types (`displayName + description + examplePhrases`), extended for skills to:
- `displayName` and `description` (Spec 02 §2.2)
- `inputs[*].label` strings (Spec 02 §2.3) — the domain vocabulary the skill's slots name
- the union of `examplePhrases` from every type in the skill's `reads ∪ writes` (Spec 01 §4.1)

A skill is a verb; its types supply the domain nouns. Together they define the semantic region the skill occupies. (Note: the draft cited `nluHints.captureIntent` as an embedding source. That field is a snake_case *intent label*, not natural-language surface text — see §8.1 — so it is a poor embedding input and is not used here.)

**Embedding model.** A single, **dedicated retrieval embedding model** is used for both indexing and query in v1 (§3.6; decided in §10 MD1) — a purpose-built sentence-transformer (default the `all-MiniLM-L6-v2` family, ~80 MB), **not** the 1–3B generation model's own embedding endpoint. Retrieval quality is the dominant driver of routing accuracy (§3.1), and a decoder-LLM's embeddings cluster short paraphrases worse; the small extra binary buys materially better routing. Integration is the Architecture spec's; NLU depends only on the `similarTo` contract, so the exact checkpoint can change (e.g. a multilingual model) without touching this spec.

**When the index is updated, storage, and format** are all owned by the registry layer, not by NLU — see Spec 01 §5.4 (types) and its skill-registry analogue (Architecture spec). Both indexes are device-local and not synced: each device may run a different embedding model, so the vectors are not portable and are cheaply re-derived on any device from the (synced) type/skill definition files. The registry rebuilds incrementally (only entries whose source `lastModified` is newer than the index `builtAt`) off the main thread; until a new entry is ready the previous vector is used. NLU inherits all of this by consuming the index rather than maintaining it.

> **Index location (decided, §10 MD9):** both the type index and the skill index live in device-local `[app-support]`, not a dotfile inside the *synced* Plenara root. This expresses "not synced" honestly and spares a sync engine from special-casing an excluded dotfile; the vectors are cheaply rederived per device either way. Spec 01 §5.4 is updated to match. It does not affect the NLU contract.

### 3.3 Retrieval Step

Given a normalized utterance transcript, the router:

1. **Embeds the query.** Pass the normalized transcript through the embedding model. This is a single forward pass over a short input — the cheapest inference call in the system.
2. **Query the `CapabilityIndex`** (§3.2) for the merged, kind-tagged ranked list of skill, type, and generative candidates by cosine similarity — via the registry's `similarTo` contract, not a hand-rolled scan inside NLU.
3. **Retrieve the top-K skill candidates** above `θ_retrieval` (default K = 5). `θ_retrieval` is purely a **candidate-set membership floor** — it caps how many definitions the local model is shown, nothing more. It does **not** decide skill-vs-meta-intent; that decision is owned solely by `θ_meta` (§4.1), which is strictly higher, so a set that is non-empty at `θ_retrieval` but whose best skill is below `θ_meta` still routes to the meta-intent check. Collapsing these two into one gate (setting `θ_retrieval = θ_meta`) is a legitimate simplification and the recommended default until tuning shows a reason to separate them (§4.1).

Cosine similarity is computed in pure Dart over the in-memory vector table. With N ≤ a few hundred skills (realistic ceiling for a personal app), a linear scan is fast enough; an HNSW index can be added later if the library reaches thousands.

**Generative candidates.** Because the index is kind-tagged (§3.2), the top candidate may be a built-in generative capability. When it is, and it clears the act band (§4), the router emits a `generative_request` (§2.2a) rather than running skill classification — the local model's job on that turn is param slot-extraction (§6), not `skillId` selection. The skill-vs-`define_*` meta boundary (§4.1, `θ_meta`) is unchanged; `generative` simply adds one more kind the top candidate can be, and a generative capability is only offered on the paid tier (§2.2a).

### 3.4 Classification Step (Local Model)

The local model (llama.cpp 1B–3B, called via Flutter platform channel) receives a structured classification prompt containing:

- The normalized utterance.
- The top-K candidate skill definitions (displayName, description, examplePhrases, input labels) — not the full step list.
- A structured output schema: produce a JSON object with `skillId` (one of the candidates or `null`), `slots` (key-value map), and `confidence` (float).

The model is asked to choose among the candidates, not to classify against the whole library. The classification prompt is templated and fixed; it does not include live user data (the prompt-injection defense from Spec 02 §7.3 applies here too — the prompt is built from type/skill metadata, not from user record content).

**Output parsing.** The model's output is parsed with a strict JSON schema validator. A malformed output is treated as a `null` classification and falls through to cloud escalation (§3.5). The local model is never retried on parse failure — retrying a malformed output wastes latency and rarely yields a different result.

**Structured output constraints.** The model must select a `skillId` from the candidate set (or produce `null`). It may not invent a `skillId`. If the model produces a `skillId` not in the candidate set, the output is treated as `null`. This keeps the local model's role narrow: choose among a presented list, extract slots — not generate free-form decisions.

**Slot extraction.** The model fills the slot map in the same pass as classification. Slots are declared in the skill's `inputs` contract (Spec 02 §2.3); the classification prompt lists the required and optional slot names, their `valueType`s, and their `label`s. The model is asked to extract each slot value from the utterance or leave it as `null` if not present. Type coercion (string-to-datetime, string-to-enum normalization) is performed by the NLU layer's post-processor, not by the model.

### 3.5 Cloud Escalation Path

If the local model returns a confidence below `θ_cloud_escalate` (§4.1), the NLU layer escalates to Claude Haiku 4.5. The cloud call receives the same classification prompt as the local model, plus the user's correction history for the utterance pattern (from the flow table, §5 — a few recent corrections, not the full corpus). That history is **templates only** — literal patterns with typed placeholders, never `fixed` values and never entries routed to a `sensitive` skill (§5.6) — so escalation leaks no stored user content beyond the live utterance itself. Haiku returns the same structured intent JSON.

**Cost guard.** A cloud call costs real money. The escalation path is guarded by:
- A per-session rate limit (default: max 20 cloud NLU calls per hour). Above the limit, the NLU layer surfaces a clarification request rather than escalating.
- BYOK: the cloud path requires a valid API key. Free-tier users without a key fall back to the clarification-request path rather than calling a shared key at Luis's cost.

**Cloud-escalated capability-definition.** If even Haiku returns a confidence below `θ_minimum` after escalation, and the utterance passes the capability-definition meta-intent check (§2.2), the result is a `define_type` or `define_skill` intent — which itself triggers another cloud call, this time to Sonnet for authoring (Spec 01 §6, Spec 02 §6). The NLU layer produces the meta-intent; control passes to the authoring flow, which is a separate subsystem.

### 3.6 Two-Representation Decision (Local vs Cloud Embeddings)

The embeddings index is shared between the local retrieval step (§3.3) and any cloud-assisted retrieval. A small local embedding model (e.g. MiniLM) may produce a different vector space than a larger cloud model (e.g. `text-embedding-3-small`). A skill that clusters well in MiniLM's space may not cluster as well in the larger space, and vice versa.

**v1 decision: one representation.** The v1 embeddings index uses a single model for both retrieval and cloud path. The cloud path (Haiku classification) receives the same top-K retrieval set produced by the local embeddings. With MD1's dedicated retrieval model the local top-K is strong, so the cloud path re-ranks that top-K with Haiku's reasoning rather than maintaining a second embedding space. Building dual representations (one index per model family, cloud calls re-ranked against Haiku's embedding) is declined for v1 and gated on a concrete metric (§10 MD2): the rate at which the correct candidate is absent from the local top-K on cloud-escalated test-pairs.

---

## 4. Confidence-Threshold Policy

### 4.1 Thresholds

All values are floats in [0, 1] and are configurable (stored in `[app-support]/plenara/nlu/config.json`); the defaults below are launch values. The v0.1 draft put everything in one table, which hid a real design smell the draft itself flagged for review: **the thresholds live on two different axes measuring two different quantities**, and mixing them invites comparing a cosine similarity against a classifier confidence as if they were the same number. They are not. Splitting the table is the fix.

**Axis 1 — Retrieval similarity** (produced by §3.3; cosine similarity of the query embedding against a candidate's embedding). Governs *which candidates exist* and *skill-vs-meta routing* — geometry of the embedding space, decided before any classifier runs.

| Threshold | Default | Meaning |
|---|---|---|
| `θ_retrieval` | 0.50 | Candidate-set **membership floor** only — the minimum similarity to be shown to the classifier as one of the top-K. Mechanical, not a routing decision. Defaults equal to `θ_meta` (see §3.3); raise it above `θ_meta` only if tuning shows the classifier is hurt by weak candidates. |
| `θ_meta` | 0.50 | The skill-vs-meta boundary. If the top-1 skill candidate is below `θ_meta`, the utterance is treated as potentially novel → meta-intent check. |
| `θ_type` | 0.45 | Within the meta-intent check: minimum type-entry similarity to resolve the domain as a known type. Top type ≥ `θ_type` → `define_skill`; nothing above → `define_type`. |

**Axis 2 — Classifier confidence** (produced by §3.4/§3.5; the local or cloud model's self-reported confidence in the intent it chose). Governs *act / escalate / give up* once a candidate has been chosen.

| Threshold | Default | Meaning |
|---|---|---|
| `θ_act` | 0.80 | Confidence at/above which the app dispatches and simply describes the result. In the moderate band `[θ_cloud_escalate, θ_act)` the app **still dispatches on its best guess** but makes the routing transparent in the description ("Logged that as a task — let me know if you meant something else", the advisory `Routing` event) rather than pre-confirming (act-then-describe, Spec 05 §3.2). It is no longer a pre-confirmation gate; it only decides whether the description carries the transparency caveat. |
| `θ_cloud_escalate` | 0.60 | Minimum **local**-model confidence to skip cloud *and* to act on a best guess at all. Below this, on the paid/BYOK tier call Haiku; on the free tier, if there is no dominant candidate, clarify (§3.5). |
| `θ_minimum` | 0.40 | Absolute floor. Below this even after Haiku (or with no cloud available), produce a clarification request rather than a guess. |

`θ_minimum` (0.40, confidence) and the old `θ_retrieval` (0.40, similarity) shared a numeric value in the draft purely by coincidence — a coincidence that made the one-table form read as if a single 0.40 gate governed both. Separating the axes removes that trap; `θ_retrieval` is now 0.50 and lives on the other axis entirely.

**Axis 3 — Corpus trust** (the `confidence` on a Lane 1 entry, §5.2). This is neither a cosine similarity nor a model's self-report: it is *earned trust* — how well a learned template has held up across uses, corrections, and decay (§4.2), produced by the confirmation ratchet rather than by any one classification. The v0.2 pass split similarity from classifier-confidence but then still compared this earned score against `θ_act`/`θ_minimum` — the same category error, one level down. It gets its own axis, defaulted equal so launch behaviour is unchanged.

| Threshold | Default | Meaning |
|---|---|---|
| `θ_corpus_act` | 0.80 | Entry trust at/above which a corpus fast-path hit dispatches and simply describes. In `[θ_corpus_drop, θ_corpus_act)` a hit still routes on its best guess but with the transparent-routing caveat in the description (act-then-describe), not a pre-confirmation. Defaults to `θ_act`; tune independently once corpus-quality data exists. |
| `θ_corpus_drop` | 0.40 | Trust floor. Below it an entry is dropped from the fast path (marked `active: false`, §5.5); a model call supersedes it. Defaults to `θ_minimum`. |

Keeping the defaults equal to their Axis-2 counterparts means no new tuning burden at launch — the split is about *what the number means* (so the three can diverge when data warrants), not about adding knobs to turn on day one.

The progression for any utterance is therefore:
1. **Corpus hit?** (§5.4 template match) → recover slots (§6.4) and gate on **Axis 3**: trust ≥ `θ_corpus_act` and not `requiresPreConfirm` → dispatch and describe, no model call; `θ_corpus_drop` ≤ trust < `θ_corpus_act` → dispatch on the best guess with the transparent-routing caveat in the description (no pre-confirm); `requiresPreConfirm` set → the entry has *evidence* of genuine ambiguity (§4.2), so clarify between the contested candidates rather than act; trust < `θ_corpus_drop` → not a hit, fall through to retrieval. A `span`/`fixed`-only template is inference-free; a `model`-recipe slot adds one scoped extraction (§6.4), never full classification.
2. **Retrieval.** Top-1 skill candidate below `θ_meta` → meta-intent check (§2.2). (`θ_retrieval` only bounds K; it does not make this call.)
3. **Local classification.** Confidence ≥ `θ_act` → dispatch and describe. `θ_cloud_escalate` ≤ confidence < `θ_act` → dispatch on the best guess with transparent routing (no pre-confirm). Confidence < `θ_cloud_escalate` → escalate to cloud (paid tier); free tier, if no dominant candidate, clarify (§3.5).
4. **Cloud classification.** Confidence ≥ `θ_act` → dispatch and describe. `θ_minimum` ≤ confidence < `θ_act` → dispatch on the best guess with transparent routing. Confidence < `θ_minimum` → clarification request.

**The NLU surface that survives is clarification, not routing pre-confirmation.** Under act-then-describe (Spec 05 §3.1, the confirmation-UX authority) the app does not stop to approve a routing it can act on — a moderate-confidence best guess is acted on and made transparent in the description (the `Routing` event, Spec 04 §3.6), and an uncorrected best guess records an implicit confirmation (§2.7) that graduates the phrasing toward the fast path. The one time the app asks *before* acting is when it has **no reliable best guess** — no dominant candidate below `θ_cloud_escalate`/`θ_minimum`, or a pattern flagged `requiresPreConfirm` by repeated correction — where it surfaces the top candidates as a `ClarificationRequested` event answered by `SelectCandidate` (Spec 04 §3.6). This is the v0.4 reconciliation: the v0.3 "dispatch with a *did you mean X? — proceed?* pre-confirm" band is collapsed into act-then-describe (see Decision Record and Spec 05 D2). The skill-plan approval surface (former Spec 02 §7.1 `confirmationPolicy`) is likewise gone from the interactive path; a candidate the user selects at a clarification, or a best guess they leave uncorrected, becomes a corpus entry (§5.2), improving future routing.

### 4.2 Confidence Decay

A flow-table entry (§5) has a confidence score that may be lower than the confidence of the intent it records. Decay adjusts that score downward over time or across repeated corrections, so the fast path does not blindly trust stale or wrong routing.

**Temporal decay.** A corpus entry that has not been used or confirmed in `decayWindow` days (default: 30) has its confidence multiplied by `decayFactor` (default: 0.85) per week of disuse after `decayWindow`. An entry that drops below `θ_corpus_act` is no longer a definitive "act silently" signal; it still routes on its best guess but with the transparent-routing caveat in the description (act-then-describe), so a decayed-but-still-plausible entry keeps working while inviting correction. An entry that drops below `θ_corpus_drop` is removed from the fast path (it becomes dead weight, not a wrong answer — a model call supersedes it), i.e. marked `active: false` (§5.5).

Decay is not computed continuously; it is applied lazily at lookup time by comparing `lastUsedAt` to `now`. No background job is required.

**Named initial-confidence parameters.** New corpus entries do not start at a magic number buried in an example. Three named config values (in the same `config.json`) set where an entry begins, by how it was earned:

| Parameter | Default | Applied when |
|---|---|---|
| `initConfExplicitCorrection` | 0.90 | The user explicitly said "no, I meant X" (§5.2). Strong evidence → starts just below `θ_act`, so the corrected routing acts on the very next identical utterance. |
| `initConfImplicit` | 0.70 | A model-classified routing the user left uncorrected after act-then-describe. Below `θ_act` → routes with the transparent-routing caveat until the ratchet earns trust. |
| `initConfClarificationSelected` | 0.72 | The user explicitly selected this routing at a clarification prompt (§4.3) — a stronger signal than an uncorrected best guess, weaker than an explicit correction. |

**Correction-triggered decay.** When the user corrects a routing (§5.2), the corrected entry's confidence is set to 0 — it is immediately removed from the fast path regardless of its prior score. The replacement entry starts at `initConfExplicitCorrection` rather than inheriting the old entry's authority. A repeated correction of the same normalized pattern (corrected more than once within `correctionWindow` days, default 30) signals genuine ambiguity; the replacement is tagged `requiresPreConfirm: true`. Under act-then-describe this tag no longer means "pre-confirm the single best guess" (nothing else does) — it means the app has *evidence* the pattern is genuinely contested, so instead of acting-then-describing (which would just repeat a mistake the user has already corrected more than once) it surfaces a **clarification** between the contested candidates even at high surface confidence. The field name is retained for continuity; its behavior is "clarify, don't guess."

The tag clears after `preConfirmClearUses` (default 5) **consecutive uncorrected uses** — not after a wall-clock window. The v0.1 "cleared after 14 days" rule introduced a second bespoke time horizon and rewarded mere elapsed time; keying the clear to clean *use count* unifies it with the same evidence unit the confirmation ratchet already counts (below), so the whole trust model runs on one currency — uncorrected uses — rather than a mix of days and counts.

**Implicit confirmation boost.** A corpus entry that is used and the user does not correct the result after act-then-describe has its confidence boosted by `confirmationBoost` (default: 0.02, capped at 0.98). This is a slow ratchet — from `initConfImplicit` it takes five clean uses to reach `θ_act` — and an explicit correction immediately zeroes it out. A single correction thus outweighs many uncorrected uses, which is the intended asymmetry: acting wrongly is worse than carrying the transparent-routing caveat one more time. (Under act-then-describe this ratchet is *more* effective than under a pre-confirm model — every uncorrected best guess is evidence, not just the ones a user bothered to approve at a modal.)

### 4.3 Escalation Flow

The complete utterance → dispatch flow, including all decision points:

```
utterance (transcript)
    │
    ▼
Pre-filter (rule-based, no model): system commands (§2.3) + anaphora (§5.4a)
    │ system-command match → system_command intent
    │ anaphora match → resolve against recentIntents → dispatch (or clarify if no antecedent)
    │ no match
    ▼
Normalize utterance → template-match Lane 1 (§5.4)
    │ hit, trust ≥ θ_corpus_act, not requiresPreConfirm → recover slots (§6.4) → dispatch + describe (no model)
    │ hit, θ_corpus_drop ≤ trust < θ_corpus_act → recover slots (§6.4) → dispatch on best guess + transparent routing
    │ hit flagged requiresPreConfirm → clarify between contested candidates (evidence of ambiguity, §4.2)
    │ no match / trust < θ_corpus_drop
    ▼
Embed query → query CapabilityIndex (§3.2) for top-K skill candidates
    │ top-1 skill ≥ θ_meta → proceed to local classification
    │ top-1 skill < θ_meta → meta-intent check (§2.2) → define_type or define_skill
    ▼
Local model classification (top-K candidates, slot extraction)
    │ confidence ≥ θ_act → dispatch + describe
    │ θ_cloud_escalate ≤ confidence < θ_act → dispatch on best guess + transparent routing
    │ confidence < θ_cloud_escalate → escalate to cloud (paid) / clarify if no dominant candidate (free)
    ▼
Cloud model (Haiku) classification (same prompt + recent corrections, templates only)
    │ confidence ≥ θ_act → dispatch + describe
    │ θ_minimum ≤ confidence < θ_act → dispatch on best guess + transparent routing
    │ confidence < θ_minimum → clarification_needed intent
    ▼
User picks from candidates → resolveFollowUp → dispatch + describe
```

Every branch that reaches "dispatch" hands the orchestrator (§2.7) a `skill_invocation`; the orchestrator drives Spec 02 and writes the corpus back (§2.6) — `route` itself never mutates the corpus. Every branch that reaches a meta-intent produces the appropriate meta-intent object. The Business Logic layer never sees a partial or tentative intent — it receives one complete intent object or nothing.

---

## 5. The Flow Table

### 5.1 The Flow Table: One Model, Two Homes

The flow table is the mechanism from research doc §4.9 that unifies the NLU fast path with the deferred plan cache. It has two lanes:

**Lane 1 — Utterance → Intent** (the corrections corpus). Maps a slot-abstracted **template** (§5.4) to a `(skillId, slotRecipes, confidence)` record. This is the routing fast path: a template match skips the routing model call (and, for `span`/`fixed` slots, all inference). Built and used in v1.

**Lane 2 — Intent → Plan** (the plan cache). Maps a `(skillId, typeIds, slotShape)` signature to a previously-resolved action plan — the optimization deferred in Spec 02 §5.5. Per the locked project decision it is **not built in v1**; the invalidation model is recorded here so it has a clear home when usage justifies building it.

**The unification is at the *model* level, not the *file* level — and the v0.1 draft got this wrong.** v0.1 put both lanes in a single synced `flow-table.json` ("one file makes the §4.9 relationship explicit in the schema"). That is elegant and incorrect: the two lanes have incompatible storage requirements that Spec 02 §5 spent its entire redesign establishing.

- **Lane 1** is *earned user data* — learned phrasing that should survive a device swap — so its non-sensitive part belongs in the **synced** folder.
- **Lane 2** holds *fully-resolved action plans*. Those plans carry concrete field values, including `sensitive`-typed content (journal bodies, private notes). Spec 02 §5.2/§5.5 is explicit that resolved execution state must be **device-local, non-synced, and encrypted at rest** — precisely to keep `sensitive` values out of the always-plaintext synced files (Spec 01 §8.2) and to avoid whole-file last-writer-wins conflicts on volatile data. Spec 02 §5.5 states the cache must be a "separate, device-local, non-synced structure."

A single file cannot be simultaneously synced-plaintext (Lane 1) and device-local-encrypted (Lane 2). **Resolved (v0.2): the two lanes live in two homes.** What they share is the §4.9 *signature* `(normalized-intent, type, slot-shape)` and one *invalidation discipline* (§5.5) — a shared schema of keys, not a shared byte stream. This is a **[RECONCILE]** with Spec 02 §5.5; keeping one file would have re-imported the exact privacy-and-sync defect Spec 02 removed from the skill file.

The resulting layout (detailed in §5.2–§5.3):

| Store | Home | Encryption | Lane | Status |
|---|---|---|---|---|
| `nlu/flow-table.json` | synced Plenara root (non-sensitive templates only) | plaintext | 1 — corrections corpus | **built in v1** |
| `[app-support]/plenara/nlu/plan-cache` | device-local | encrypted at rest | 2 — plan cache | deferred (§5.1) |

Lane 1 carries *earned phrasing* (slot-abstracted templates → intents) that should survive a device swap, so its non-sensitive part syncs. Lane 2 would carry fully-resolved plans with `sensitive` values, so it is device-local + encrypted (Spec 02 §5.2) and is **not built in v1**.

---

## 6. Slot Extraction & Resolution *(resolve-stage addition)*

*Added by the Phase-3 resolve stage ([`../05b-gap-register.md`](../05b-gap-register.md)), resolving **G-12, G-14, G-15, G-16**. How the NLU layer fills the `source:"slot"` inputs a skill declares, and — the parts the traces proved were unspecified — how it resolves people and dates.*

### 6.1 Entity resolution & the resolve-or-create contract (`G-12`)
`NluContext.entityNames.resolve(refType, token) → List<(id, displayName)>` (read-only, §2.6). For every person a skill references, the NLU layer:
- **0 matches** → pass the **name** (text slot); the skill creates the contact (a write, so it must be in execute — Spec 02 §9.1 resolve-or-create idiom).
- **exactly 1** → pass **both** the `…Id` (entityRef) *and* the `…Name` (text).
- **> 1** → emit a `ClarificationRequested` **before dispatch** ("Which Sarah — Mitchell or Chen?", `SelectCandidate`); the chosen id is then passed.

Person-referencing skills therefore declare **both** a `…Id?` and a `…Name` slot (Spec 02 §9.1). Consequences: (a) creation never happens in the read-only NLU layer; (b) confirmations always have the display name (fixes the F-07 `G-12` defect); (c) **invariant:** after disambiguation, a skill's `read_one contact{displayName}` sees only 0-or-1, so `read_one` on a non-unique field is never exercised with an ambiguous result (if it somehow is — stale sync — it returns the most-recent and flags a repair item).

### 6.2 The deterministic date / recurrence resolver (`G-14`, `G-15`, `G-16`)
A **pure-code** component in the NLU post-processor — **never the model** (models hallucinate the actual date; findings §3). It takes the temporal *expression* the model extracted plus the frozen `now`/`today`, and returns a resolved `datetime`/`date`/RRULE (+ `allDay`). It owns **all** date math so skills receive a literal `dueAt`:
- **Relative** ("Thursday", "in three weeks") → concrete date; `date→datetime` coercion + `allDay` (Spec 01 §7.3).
- **Recurring** ("every second Tuesday") → RRULE (`FREQ=WEEKLY;INTERVAL=2;BYDAY=TU`).
- **Anniversary / next-occurrence** (`G-15`) → `next_anniversary(date)` / `next_occurrence` — the MM-DD logic the compute grammar lacks; it lives **here**, not in the DSL.
- **Record-anchored** (`G-14`) → given a *structured* anchor `(contactRef, field, offsetDays)` — NLU resolves the contact via §6.1 and maps the field word ("birthday" → the `birthday` attribute) — the resolver does a **scoped graph-read** of that field, applies `next_anniversary` + offset, and returns the literal `dueAt`. **This supersedes the skill-side anchor branch sketched in 05a-traces §3A:** `create-reminder` receives a resolved `dueAt` and needs no `read_one`/`compute` anchor logic in the common case.
- **Missing anchor data** (`G-16`) → if the anchor field is null (Sarah's birthday unknown), the resolver cannot produce a date → it raises a **missing-slot follow-up** (§6.3): *"When's Sarah's birthday?"* The answer resolves this reminder (and the app may offer to save it to the contact — a separate act).

### 6.3 Missing-slot follow-up (the `ProvideSlot` loop)
When a required slot (or a date the resolver needs) cannot be filled, resolve halts *before any write* (Spec 02 §4.1) and the orchestrator emits `ClarificationRequested(kind: missingSlots)`. The app asks **one** targeted question (P2.1); the answer returns via `ProvideSlot` → `NluRouter.resolveFollowUp(pending, slotName, answer, ctx)` runs a **scoped second-pass extraction** (no re-classification, §2.6) → resolve resumes. At most two rounds per turn (Spec 05 §3.2), then the app offers to start over.

---

## 7. Routing-Reliability Amendments *(resolve-stage addition)*

*Resolving **G-07, G-19, G-20** (the last via the completed eval, findings §11 → NO-GO). These amend the confidence policy (§4), the out-of-domain path, and the routing cascade in light of the Phase-3 measurements ([findings §2](../../research/spec-05a-phase3/findings.md), [§11](../../research/spec-05a-phase3/findings.md)).*

### 7.1 Constrained decoding + escalation gated on retrieval, not model confidence (`G-07`)
- The local classification step (§3.4) uses **grammar / JSON-schema constrained decoding**: `skillId` is constrained to the enum of *retrieved candidate ids* (it cannot emit a list index like `1`, a hallucinated id, or a non-committal `null`), and slots to their declared shapes. This is a **format guarantee, not a correctness one** — it does not fix a wrong choice (findings §5).
- **The local model's self-reported `confidence` is not trusted** (measured uncalibrated — correct labels at 0.0, wrong ones at 0.9; findings §2). The **escalate/clarify/act decision gates on *retrieval* signals** — the top-1 similarity, the top-1↔top-2 margin, and the `θ` thresholds (§4.1) — plus the repeated-correction/`requiresPreConfirm` rules, **never** on the generative model's confidence field. This amends Axis-2 (§4.1): "classifier confidence" from a 1–3B local model is treated as advisory-only for logging, not as the escalation gate.
- **`G-20` — RESOLVED: the eval failed the bar → the local generative model is cut from the trusted routing path** (findings §11; ≤49% routing across four small models, meta-intent 0%, uncalibrated). The classify step is *not* a trusted router. Constrained decoding is retained only as **optional format insurance** where a local model is used at all (it changed routing accuracy by 0 points — the `skillId`-as-number wart was an artifact of *numbering* candidates; keying them by id removes it without a grammar). See **§7.3** for the deterministic replacement.

### 7.2 Out-of-domain detection: conservative and records-biased (`G-19`)
Out-of-domain is decided **locally, by rule + retrieval — not the generative model's guess** (Llama-3.2-3B misroutes the hard case; findings §2). A turn is tagged `out_of_domain` only when **all** hold: (a) the best `CapabilityIndex` hit across every kind is below `θ_retrieval`; (b) the utterance matches a small built-in **world-knowledge shape** (weather, sports, news, definitions, "what is / who is / when did ‹public entity›"); and (c) it carries **no personal cue**. **Personal cues force `records_query`** even when a world-noun appears: first-person/possessive references to the user's own data — "what did **I** say…", "on **our** trip", "**my** …", "last time **I** …". This is a **privacy boundary**, not just UX: a records-cued query is **never** delegated to an external OS/web assistant (the leak `G-19` names). Only (a)+(b)+(c) → the tiered delegation policy (Appendix A §A.3); anything with a personal cue stays in-app. *(The eval showed small models never leak here — 0/4 — but only as a side effect of never abstaining, `G-20`; so OOD stays rule+retrieval-owned and the model is never handed an explicit `out_of_domain` label it could over-trigger.)*

### 7.3 Routing without the on-device generative model (`G-20` NO-GO → `G-33`)

The eval (findings §11) cut the generative model from the trusted path. Known-capability routing is now a **deterministic cascade**, no per-turn local LLM:

1. **Corpus fast-path (§5)** — hash/slot-template hit → route directly, no inference. Owns high-frequency capture; offline; free.
2. **Retrieval top-1-with-margin** — `CapabilityIndex` (the dedicated embedding model, not the generative one) ranks candidates; **accept top-1 iff it clears `θ_retrieval` AND beats top-2 by margin `τ`.** This is the escalation gate (§4.1), on *retrieval* signals only — never model confidence (dead for every model, findings §11).
3. **Deterministic slot extraction** — dates/recurrence via the §6.2 resolver, entities via §6.1 `entityNames.resolve` (`G-24` aliases), quantities/durations by pattern, corpus recipes for known templates. Replaces the cut model's slot job (which even Haiku did at only 78% exact). A missing required slot → the §6.3 one-question follow-up.
4. **Residual** — only when ≥2 candidates are close **and** phrasing is novel (steps 1–2 can't decide): **online + keyed → Haiku** (measured 86% routing / 96% on known-capability class A, ~$0.0006, ~0.8 s p50 — the reliable escalation, findings §11); **offline or free → clarify** (deterministic "did you mean X or Y?", the honest floor, P7).
5. **Meta-intent (novel need → author) and OOD** stay **retrieval + rule owned** (§7.2) — small models scored 0% on meta-intent, so this was never theirs to do.

**Offline/free is preserved:** steps 1–3 need no cloud; only the genuine residual wants Haiku, and its absence degrades to a clarify, not a failure. The local-first hedge holds because the generative model was only ever the last-resort discriminator.

#### 7.3.1 The routing signal is retrieval margin, not classifier confidence (amends §4.3)

Cutting the generative model removes **Axis 2** entirely (the "local classification" step of the §4.3 escalation flow, and its `confidence` field — dead anyway, findings §11). The retrieval score that §3.3 already computes *becomes* the routing decision. Define, over the ranked candidate set:
- `s₁` = top-1 similarity, `s₂` = top-2 similarity, **`margin = s₁ − s₂`**.

The §4.3 flow's step 3 ("Local classification") is **replaced** by a pure retrieval-margin decision (Axis 3 corpus and the §2.2 meta/OOD checks are unchanged):

| condition | action |
|---|---|
| `s₁ ≥ θ_act` **and** `margin ≥ τ_act` | **dispatch + describe** — a clear, dominant winner |
| `s₁ ≥ θ_meta` **and** `margin ≥ τ_clarify` (but not the row above) | **dispatch on best guess + transparent routing** (act-then-describe moderate band, §4.1) |
| `s₁ ≥ θ_meta` **and** `margin < τ_clarify` | **genuine tie** → residual: online+keyed → Haiku disambiguation (§7.3.2); else **clarify** (`SelectCandidate` between the tied candidates) |
| `s₁ < θ_meta` | **meta-intent check** (§2.2) — novel need → `define_*`; unchanged |

Two new margin thresholds join the §4.1 table — **`τ_act` (default 0.08)** and **`τ_clarify` (default 0.03)** — on the *retrieval* axis. They are **calibration targets, not guesses:** the eval harness (`eval_routing.py`) re-scores the labeled dataset to pick the `τ` that maximizes correct-dispatch while holding the clarify-rate acceptable; ship the defaults, tune on data. This is strictly simpler than the old two-axis model (retrieval similarity *and* a separate classifier confidence): one axis, one dominant-winner test.

#### 7.3.2 Haiku as the residual disambiguator (not a router)

Haiku is invoked **only** on the genuine-tie residual (`margin < τ_clarify`) when online and BYOK-keyed. Its job is deliberately narrow — the exact task it measured **96%** on (findings §11, class A): *given the utterance + the ≤5 tied candidates keyed by id, return one id or `none`.* Output is enum-constrained to `{candidate ids} ∪ {none}` (~$0.0006, ~0.8 s p50). `none`, or a pick below `θ_meta`, falls to the meta-intent check or a clarify. This is the same escalation slot the old §4.3 "cloud classification" step held — Haiku now owns the disambiguation the local model did badly, and only for the residual, so the per-turn cloud rate stays low.

#### 7.3.3 Deterministic slot extraction (the extractor inventory)

Slots are filled by **typed deterministic extractors**, not a model (which even Haiku did at only 78% exact — so this is *more* reliable, not a downgrade):

| valueType | extractor |
|---|---|
| `date` / `datetime` / `recurrence` | the §6.2 deterministic date/recurrence resolver (`G-14/15/16`) |
| `entity` / contact ref | §6.1 `entityNames.resolve` — aliases (`G-24`), resolve-or-create (`G-12`) |
| `decimal` / `integer` / quantity | numeric + unit pattern (regex + unit table) |
| `duration` | duration pattern ("for 30 min", "a couple hours") |
| `enum` | keyword/synonym match against the type's `enumValues` |
| `tag` | token match against the known tag vocabulary |
| `boolean` | polarity keywords |
| `text` (free-form) | span heuristic — the residual after removing the matched trigger + other slots; or the whole utterance for a capture skill |

Corpus `span`/`fixed` recipes (§6.4) handle known templates with zero inference. A required slot the extractors cannot fill → the §6.3 one-question follow-up (unchanged). Only a free-form slot on a *novel* phrasing that the span heuristic can't isolate **and** is online+paid piggybacks on the §7.3.2 Haiku residual call for extraction; offline/free → the follow-up question. So slot quality no longer rides on a 48%-exact local model.

#### 7.3.4 What this removes, and what it preserves

**Removed:** the on-device generative model, Axis 2 (classifier confidence), the local-classify escalation step, and the 2–8 s CPU inference cost per turn (findings §11). **Preserved:** the corpus fast-path (Axis 3, untouched — the primary offline/high-frequency path), retrieval (Axis 1, now load-bearing for the decision rather than only candidate-set membership), the `θ_*` thresholds (reused with retrieval-similarity semantics), meta-intent + OOD (rule+retrieval, §7.2), act-then-describe, the single clarify surface, and full offline/free operation (steps 1–3 + clarify need no cloud). **Net:** fewer moving parts, nothing unreliable in the hot path, and lower latency — the NO-GO made routing *simpler*, not weaker. *(Follow-on for a tuning pass: fit `τ_act`/`τ_clarify` on the eval dataset and add a `margin`-sweep report to `eval_routing.py`.)*