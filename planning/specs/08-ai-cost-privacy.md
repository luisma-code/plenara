# Spec 08 — AI Cost & Privacy

**Status:** Draft v0.1 — July 2026 (first draft against the v0 reference implementation: `v0/lib/claude.dart` / `router.dart` / `generative.dart` / `config.dart`; grounded in the Phase-3 measurements — findings §§10–13 — and current Anthropic pricing as of 2026-07)
**Depends on:** research doc (§7, §12.8, §13, §14, §15); Spec 02 — Skill DSL (§5.5, §6, §7.6); Spec 03 — NLU / Intent (§2.2a, §3.5, §5, §7.3); Spec 04 — Architecture (§3.5, §3.7, §3.10, §5.2, §6); Spec 05 — Functional (§3.6, §3.8, §13)
**Blocks:** Spec 09 — Test (the payload/consent invariants below are testable contracts); Spec 10 — Security & Privacy threat model (this spec draws the data-flow map Spec 10 attacks); Spec 11 — Feedback & Diagnostics (shares the consent ground rules)

---

## 0. Purpose & Scope

Plenara's cloud posture is unusual and worth stating in one sentence: **there is no Plenara server.** The only network endpoint the app ever talks to for intelligence is `https://api.anthropic.com/v1/messages`, authenticated with the *user's own* Anthropic API key (BYOK, research §15.1). Every other byte of the user's life stays in their folder, on their devices, under their own cloud-storage account. This spec makes that posture precise and priced.

Per the research doc's charter for this spec (§12, item 8), it covers exactly four things:

1. **Token budgets per feature** — which model each feature uses, the rough token envelope per call, and what that costs on the user's key (§3)
2. **The caching strategy** — why Plenara's dominant "cache" is the corpus fast-path + learn-after-one-clean-use, where the deferred resolved-plan/flow-table fits, and why API-level prompt caching is mostly *inapplicable* in v1 (§4)
3. **Exactly what leaves the device, and with what consent** — the per-feature table of payloads, the ordering guarantees (safety floors and tier gates run *before* any cloud call), and the three-tier consent model (§5)
4. **The BYOK flow** — key acquisition, storage, validation, the offline/keyless degrade, and key removal (§6)

It does **not** cover: the adversarial threat model (prompt injection depth, key exfiltration attacks, malicious sync peers — Spec 10); at-rest encryption of records (Spec 01 §8.7, deferred); the diagnostics/feedback payloads (Spec 11, though §5.6 restates the shared ground rules); or STT/TTS, which are platform-native and on-device by design (Spec 12 — Voice; its privacy statement is Spec 12 §8) and appear here only as a "never leaves" row in the table.

A note on evidence: unlike the earlier specs, most numbers here are **measured**, not estimated — per-call costs and latencies come from the Phase-3 harness runs (findings §10–§13), and the payload descriptions come from reading the actual v0 prompt-assembly code, not from intent. Where the v0 implementation diverges from the target design, the divergence is stated and logged in the Decision Record.

---

## 1. Governing Principles

**P2.4 — Code over AI is the cost principle.** Every deterministic path is a path that costs zero tokens forever. The routing cascade (Spec 03 §7.3) is deliberately ordered so inference is the *last* resort: corpus template match (free) → local retrieval candidates (free) → deterministic slot resolvers (free) → Haiku residual (fractions of a cent) → clarify (free). Cost control in Plenara is not a budget dashboard bolted on top; it is the architecture.

**Local-first is the privacy principle, and BYOK is its commercial expression.** Because there is no Plenara backend, there is no Plenara-side data handling to trust, audit, or breach — the only third parties in the system are the user's own cloud-storage provider (for sync, Spec 06) and Anthropic (for the paid tier, on the user's own account and under Anthropic's API terms). The free tier involves neither model provider nor any network call (Spec 04 §6.1).

**Minimization at assembly, not at the model.** What a cloud prompt may contain is decided by *deterministic assembler code* before the request is built — never by instructing the model to ignore things it was given. Routing and authoring prompts are assembled from type/skill *metadata*, never from record content (Spec 02 §6.3, the prompt-injection defense); generative prompts contain only the record classes their feature declares (§5.4); journal text enters a prompt only when the assembler re-builds it under a live per-session consent (`G-26`, Spec 04 §3.10). The privacy boundary is a property of code we can unit-test, not of model compliance.

**P2.8 — No silent failure, applied to money and connectivity.** A blocked cloud call is always named for what it is: no key (tier), no network (connectivity), or a rejected/rate-limited key (quota) — three distinct surfaces, never conflated (`G-28`, Spec 05 §13). The cloud seam returns typed results, never exceptions and never bare nulls (Spec 04 §3.5, implemented as `CloudResult`/`CloudErrorKind` in `v0/lib/claude.dart`), precisely so callers *cannot* forget to tell the user the truth.

**The safety floors are upstream of the spend.** The deterministic Layer-1 policy pre-filter (Spec 02 §7.6) runs before an authoring call is even constructed — a hard-blocked request costs zero tokens and leaks zero text. The tier gate and the rate-limit cost guard live inside the single cloud seam (Spec 04 §3.5), so no call site can bypass them.

---

## 2. The Cloud Surface: One Seam, Three Calls

Everything in this spec hangs off one architectural fact (Spec 04 §3.5, realized in `v0/lib/claude.dart`): the app has a **single cloud seam**, the `ClaudeClient`/`CloudClient` interface, with exactly three methods. If a feature is not reachable through one of these three, it does not touch the network:

| Call | Purpose | Caller | Cloud tier |
|---|---|---|---|
| `routeResidual(utterance, skills)` | Residual intent routing — turn a novel phrasing the corpus/retrieval can't decide into a `{skillId, slots}` route, or an honest abstain (`Ok(null)`) | The dispatch orchestrator, only at step 4 of the routing cascade (Spec 03 §7.3) | Haiku |
| `authorCapability(description, priorError?)` | Capability authoring — produce a declarative `{type, skill}` artifact from a described need, revalidated deterministically by the caller (Spec 02 §6.4) | `AuthoringService` (Spec 04 §3.7), after the Layer-1 pre-filter and tier gate | Haiku in v0; capable-model pin targeted (§3.2) |
| `generate(kind, context)` | Grounded free-text synthesis for a fixed, binary-shipped set of generative kinds (Spec 03 §2.2a) | `GenerativeService` (Spec 04 §3.10), which assembles `context` deterministically from the user's own records | Haiku default; Sonnet/Opus reserved for the heaviest kinds |

Properties of the seam, all load-bearing for this spec:

- **Typed outcomes.** Every call returns `CloudOk<T>` or `CloudError(kind, detail)` with `kind ∈ {noKey, offline, timeout, badKey, rateLimited, serverError, malformed}` — the canonical `CloudErrorKind` set, owned by Spec 04 §5.1 (this spec and Spec 11 §2.1 cite it, they do not redefine it). `Ok(null)` from the router is a *real answer* (the model abstained — "not one of my capabilities"), distinct from any failure. The v0 client maps HTTP 401/403 → `badKey`, 429 → `rateLimited`, socket failures → `offline`, and bounds the whole exchange with a 30 s timeout — it **never throws** (`claude.dart`).
- **One endpoint.** The client posts to `https://api.anthropic.com/v1/messages` with the `x-api-key` header. There is no telemetry endpoint, no analytics SDK, no Plenara-operated relay. (The optional local embedding server used by retrieval is `localhost`-only and carries no data off-device — `embed.dart`.)
- **Bounded outputs.** Every call carries an explicit `max_tokens` ceiling (v0: 200 for routing, 900 for authoring, 400 for generation), so a runaway response cannot run away with the user's credit.
- **Injectable.** The seam is an interface so tests inject `ReplayCloud` (the record/replay cassette, `replay_cloud.dart`) — cloud-path tests are deterministic, free, and offline, while exercising *genuine recorded model outputs*. Note the cassette is a **test mechanism**, not a production cache: production never replays a routing decision from a recording; it learns it into the corpus (§4.1).
- **Guards live inside.** The BYOK availability check and the per-session rate-limit cost guard (Spec 03 §3.5) are the client's responsibility, not each caller's, so `available` and a `rateLimited` result are the only things call sites reason about (Spec 04 §3.5).

Everything *not* on this list runs on-device with zero marginal cost: the corpus fast-path router, retrieval over the local embedding model (~36–80 MB, bge-small class), the deterministic date/recurrence/entity resolvers, the skill interpreter, streaks/queries, semantic search over local embeddings, STT/TTS, and all storage and sync plumbing.

---

## 3. Model Assignments & Token Budgets Per Feature

Pricing basis (Anthropic API, 2026-07; the user pays these on their own key): **Haiku 4.5** $1.00 in / $5.00 out per MTok; **Sonnet (4.6/5)** $3.00 / $15.00; **Opus 4.8** $5.00 / $25.00. Batch API: 50% off. Prompt-cache reads ≈ 0.1× input price (writes 1.25×) — but see §4.3 for why caching mostly doesn't apply at these prompt sizes.

The unifying observation, established by measurement (findings §10–§13): **every routine cloud interaction in Plenara costs well under a tenth of a cent, and the expensive interactions (authoring) are rare by design.** The cost problem is not any one call; it would only ever be *frequency* — which is exactly what the corpus ratchet (§4.1) drives toward zero.

### 3.1 Residual routing — Haiku, ~$0.0004–0.0006 per call

The only per-turn cloud call that exists, and only on the residual: a novel phrasing, online + keyed, that the corpus didn't match (steps 1–3 of Spec 03 §7.3 are free and local). Two measured shapes:

- **Full-inventory cold-start routing** (the adopted online design, findings §13): the utterance plus the *entire* capability inventory — for each skill, its id, display name, and input slot names (the v0 `_sys` prompt builds exactly this). At the 17-skill seed inventory: system ~150 tokens + inventory ~350–500 tokens + utterance ~10–30 tokens in; constrained-JSON route out, typically 30–80 tokens against the 200-token cap. **Measured: 94.1% routing accuracy, ~$0.0004/turn, ~0.8–1.2 s.**
- **Tied-candidate disambiguation** (Spec 03 §7.3.2, the narrower job): utterance + ≤5 candidates, output enum-constrained to an id or `none`. **Measured: 96% on class A, ~$0.0006/call, ~0.8 s p50.**

Envelope scaling note: input cost grows linearly with the skill inventory (~20–30 tokens/skill). A power user with 60 authored capabilities pays roughly ~1,800 input tokens ≈ $0.002/residual call — still negligible per call, and §4.3 names the threshold where prompt caching starts paying for this prefix.

The per-session cost guard caps this path (default 20 calls/hour, Spec 03 §3.5 — **flagged for resize**, see Q1: Haiku-as-cold-start-router means a new user's first hour is nearly all residuals). Even at the cap sustained for an hour, spend is ~$0.01.

### 3.2 Capability authoring — the one genuinely "expensive" call, by design rare

Authoring is a slow-path, detached, BYOK-gated operation (Spec 02 §6.1) that happens roughly *once per new capability*, not per use. Its budget has three components:

| Component | Model | Envelope | Cost |
|---|---|---|---|
| The author call | **v0: Haiku** (`claude-haiku-4-5`, `max_tokens: 900`). **Target: a pinned capable model (Opus 4.7/4.8) with JSON-schema-constrained output** — Spec 02 §6.3's `G-29` finding: all seven measured models author *simple* skills as valid DSL, but on complex multi-step skills all but Opus 4.7/4.8 drift the step schema | System contract ~450 tok + described need ~20–80 tok in; artifact out: ~300–900 tok (Haiku/v0 simple skills), ~1,600 tok measured on Opus for complex ones (Opus 4.6-family "overthinks" at 1,839–1,900 tok / 23 s; 4.7/4.8 is faster *and* cheaper at ~1,600 tok / ~16 s) | Haiku: ~$0.003–0.005. Opus 4.8: ~$0.04–0.05 per authored capability |
| Automatic re-author on validation failure | Same model | Same envelope + the structured validator error; at most **one** automatic retry (Spec 02 §6.4), then a draft — the retry loop cannot spiral cost | ≤ 1× the above |
| Layer-3 independent safety review | Haiku (or a pinned reliably-refusing model), Spec 02 §7.6 | Original request + authored artifact in; safe/decline judgment out | **~$0.0003** (measured) |

Pre-authoring reconciliation (`similarTo`, Spec 01 §6.1) runs on the **local** embedding index — free. The Layer-1 policy pre-filter is deterministic rule code — free, and it runs *before* any of the above is spent (§5.2). Refinement turns during preview (Spec 02 §6.5, up to five) are each a follow-up author call at the same envelope.

**Worst-case authoring session** (complex skill, Opus-pinned, one retry, five refinements): still under **$0.50**. Typical (one clean authoring on the target pin): **~$0.05**. On v0's Haiku interim: **under a cent**. The v0-vs-target model divergence is D3 in the Decision Record. *(Suite-sync: Spec 04 §3.5's former "Sonnet" docstring and Spec 03's model mentions now cite this section — the authoring model is named here and nowhere else, so a repin is a one-file edit.)*

### 3.3 Generative kinds — Haiku default, grounded context, output-capped

Every generative kind is one `generate(kind, context)` call. **The table below is the single owner of the closed `generativeKind` set** (suite-sync resolution of CS-09): membership is the union recorded here, including `draft_message` (a shipped P-20 feature, admitted by product decision); Spec 03 §2.2a and Spec 04 §3.10 cite this registry rather than enumerating their own lists. Each call is: a short kind-specific system prompt (~60–90 tokens, shipped in the binary — see `_genSys` in `claude.dart`), a deterministically assembled grounded context, and free text out capped at 400 tokens in v0. Per Spec 04 §3.10's cost note (findings §10.1): **default every kind to Haiku; reserve Sonnet/Opus for the heaviest reasoning** (`pattern_insight`, `monthly_reflection`). Measured anchors: briefing **$0.0007 / 1.9 s** on Haiku vs $0.005 / 8 s on Opus 4.8; gift ideas **$0.0015** vs $0.013.

| Kind | Model | Context envelope (input) | Output | ~Cost/call (Haiku) |
|---|---|---|---|---|
| `briefing` (daily) | Haiku | Date + open tasks + active reminders + upcoming birthdays: ~100–600 tok | ≤400 tok | **$0.0007** (measured) |
| `gift_ideas` | Haiku | One contact's name, stored facts, birthday: ~80–400 tok | ≤400 tok | **$0.0015** (measured) |
| `reconnect_coaching` | Haiku | Contact facts + last-interaction date: ~100–400 tok | ≤400 tok | ~$0.001 |
| `event_prep` | Haiku | Attendee contacts' facts, last-met dates, open threads: ~300–1,200 tok | ≤400–600 tok | ~$0.002 |
| `weekly_review` | Haiku | A week of workouts/moods/interactions/completed tasks: ~200–1,500 tok | ≤400 tok | ~$0.002 |
| `pattern_insight` | Haiku → **Sonnet if quality demands** | Full tracker series (multi-week): ~500–3,000 tok | ≤400 tok | ~$0.003 (Haiku) / ~$0.015 (Sonnet) |
| `meal_suggestion` | Haiku | Logged meals + stated goals/preferences: ~200–1,000 tok | ≤400 tok | ~$0.002 |
| `monthly_reflection` | **Sonnet/Opus** (synthesis quality is the product here) + mandatory journal consent (§5.4) | A month of journal excerpts + interactions: ~2,000–8,000 tok | ~500–1,000 tok | ~$0.02–0.06 (Sonnet) |
| `foresight` (`G-27`) | Haiku | Upcoming events + similar past situations from the log: ~300–1,500 tok | ≤400 tok | ~$0.002 |
| `draft_message` (P-20, v0 addition) | Haiku | Contact facts + last ~3 logged interactions: ~100–400 tok | ≤300 tok | ~$0.001 |

Two deterministic **zero-spend gates** the v0 `GenerativeService` already implements, kept as spec: a generative call is *not made* when the grounding is empty or insufficient — an empty week yields an honest "nothing logged yet" with no cloud call (`weeklyReview`), and a pattern insight requires ≥2 series before spending anything (`patternInsight`). Honesty is cheaper than generation.

### 3.4 The monthly envelope — what BYOK actually costs a real user

Summing a *heavy* steady-state month on the defaults (daily briefing ×30, weekly review ×4, ~3 gift/reconnect/prep asks a week, one monthly reflection on Sonnet, ~150 residual routes while the corpus is still learning, one authored capability):

> 30×$0.0007 + 4×$0.002 + 12×$0.0015 + $0.04 + 150×$0.0004 + $0.05 ≈ **$0.22/month**

Even multiplying by 5 for pessimism, a **$5 minimum credit purchase at console.anthropic.com covers a year or more** of heavy Plenara use. This number belongs *in the onboarding copy* (§6.1): the adoption wall (research §15.2) is the account-creation friction, not the money, and saying so honestly ("a $5 credit will realistically last you a year") is both true and disarming. Steady state trends *cheaper* as the corpus learns residuals away (§4.1); the structural floor is the scheduled generatives (briefing ≈ **$0.02/month**).

---

## 4. The Caching Strategy: Cache Decisions, Not Prompts

Plenara's caching story inverts the usual LLM-app playbook. The dominant cost mechanism is not API-level prompt caching — it is **making the second occurrence of every request free** by converting cloud decisions into local data. Research §4.9 named the pattern (resolve once, replay fast); Spec 03 §5 built it; this section states its cost semantics.

### 4.1 The corpus fast-path + learn-after-one-clean-use: the primary cost cache

The flow-table's Lane 1 (Spec 03 §5) is, economically, a cache of *routing decisions* keyed on slot-abstracted templates. Its cost behavior:

- **A corpus hit costs zero.** Template match + deterministic slot resolution (dates, quantities, entities) — regex and code, no inference of any kind (`router.dart` `route()`).
- **A residual miss costs one Haiku call (~$0.0004) exactly once per phrasing.** On a clean (uncorrected) use, the utterance is templatized against the extracted slots and inserted into the learned corpus (`recordConfirmation`, Spec 03 §5.2; v0's binary ratchet learns at full trust after one clean use, `G-45`). The next similar phrasing is a free corpus hit. **Each learned template permanently retires a recurring cloud cost** — the cache never expires by TTL, only by correction (`forget`) or capability invalidation (Spec 03 §5.5).
- **The learning is also a privacy mechanism**, not just a cost one: `learn()` refuses to persist a template unless *every* non-null slot value was abstracted out of the surface (otherwise a private slot *value* would be written verbatim into the synced corpus — the "store slot shapes, never values" rule, Spec 03 §5.4) and at least one literal word survives (so a degenerate catch-all template can never hijack routing). A phrasing that can't be learned safely simply isn't learned — it stays a per-use residual call rather than a leak.
- **Measured trajectory** (findings §13): friction (clarify-or-cloud rate) falls from ~20% cold to **~3%** as habitual phrasings accrue entries — conditional on real per-user phrasing reuse, the make-or-break unknown a beta must measure. In cost terms: a new user's residual spend is front-loaded into the first weeks and self-extinguishes.

Template instantiation compounds this: a built-in tracker ships *with its corpus entries* (Spec 05 §6, `addLearned` in v0), so a newly instantiated tracker's phrasings are fast-path from the first utterance — zero cold-start cloud calls for the common tracker vocabulary.

### 4.2 The resolved-plan cache (Lane 2 / flow table) — deferred, and cheap to defer

Research §4.9's fuller vision — caching `(intent, slot-shape) → resolved plan` — remains **deferred and not built in v1** (locked decision, research §15.1; Spec 02 §5.5; Spec 03 §5.1). The cost argument for deferral is now stronger than when it was made: after the `G-20` NO-GO removed the local generative model, *resolution is already pure deterministic code* — there is no inference left between a routed intent and an executed plan, so a plan cache saves microseconds, not cents. The expensive step it was designed to skip (routing inference) is already cached by Lane 1. When it is built, its keys and invalidation discipline are as recorded in Spec 03 §5.1/§5.5, and it is device-local + encrypted because resolved plans carry sensitive *values* (Spec 02 §5.2) — a privacy constraint this spec inherits rather than restates.

**Never cache generative effects** (research §4.9, third rule; Spec 04 §4.9): briefings, gift ideas, coaching, reflections are regenerated every time — their whole value is freshness. Correspondingly, generative *routing* is also never corpus-cached (Spec 03 §2.2a): re-classifying a generative request costs a millisecond of local matching against seconds of generation, so a fast-path entry would save nothing.

### 4.3 API-level prompt caching — mostly inapplicable in v1, by arithmetic

The research doc (§7.2) assumed aggressive prompt caching ("a 90% cache-hit rate makes even Sonnet-tier calls affordable"). Checked against current API mechanics, that assumption **does not hold for v1's actual calls, and doesn't need to**:

- **The prompts are below the cacheable minimum.** Prompt caching requires a minimum cacheable prefix — **4,096 tokens on Haiku 4.5** (and Opus 4.8) — below which a `cache_control` marker silently does nothing. The v1 residual-routing prompt is ~500–700 tokens; generative prompts are ~200–2,000; the authoring contract is ~500. Nothing routinely crosses the floor.
- **The calls that would benefit are already sub-cent.** A 90% discount on $0.0004 is not a design driver.
- **Adoption trigger (recorded, not built):** if the capability inventory grows past roughly **~130–150 skills** (≈4K tokens of inventory prefix), or the Sonnet/Opus `monthly_reflection` context assembly stabilizes a large shared prefix, add a `cache_control` breakpoint at the end of the stable prefix (system contract + inventory), keeping volatile content (the utterance, the date) after it. To keep that a flag-flip rather than a refactor, the prompt assemblers observe **stable-prefix discipline now**: system contract first and byte-stable, inventory serialized in sorted order, per-turn content last. This costs nothing today and is the entire migration.
- **Model-choice caveat for later:** caches are model-scoped; pinning different models per feature (Haiku routing, Opus authoring) means no cross-feature cache sharing — another reason per-feature caching only matters once a *single* feature's prefix is both large and hot.

### 4.4 The Batch API — only for genuinely deadline-free work

Batch pricing (50% off) applies where the research doc's amendment (§7.2, Fable review F-11) already landed: **not** for the morning briefing — batch guarantees completion within 24 h, not by 7 AM, and would synthesize from stale data; the briefing is an OS-fired local notification whose **tap** (or the next app-open, if untapped) triggers generation via the `NotificationScheduler` path — never a background Claude call (Spec 04 §3.13, the authoritative account; §3.9). Batch remains right for the **weekly consolidation pass** (Spec 01 §6.2 — merge near-duplicate types, prune dead skills, fold corrections), which has no deadline and whose model-assisted steps can tolerate any completion time. At Plenara's volumes the discount defends fractions of a cent; the real reason to use batch there is rate-limit hygiene, not price.

### 4.5 What is never cached, restated as invariants (testable, Spec 09)

1. No generative output is ever persisted-and-replayed as a response (regenerate every time).
2. No raw utterance → route mapping is cached (only slot-abstracted templates; the raw utterance is the wrong key — research §4.9).
3. The replay cassette (`replay_cloud.dart`) is compiled into tests/tooling only; production code paths never construct a `ReplayCloud`.
4. A learned corpus entry never contains a slot *value* (the `learn()` refusal rules, §4.1).

---

## 5. What Leaves the Device, and With What Consent

This is the section the product's trust rests on, so it is written to be checked against code, not aspirations. §5.1 gives the ordering guarantees, §5.2–§5.4 the mechanics, §5.5 the master table, §5.6 the consent model.

### 5.1 Ordering guarantees — what runs *before* any cloud call

For every cloud-touching path, the following run first, deterministically, on-device — a request stopped by any of them **spends zero tokens and transmits zero bytes**:

1. **The routing cascade's free tiers** (Spec 03 §7.3 steps 1–3): corpus match, retrieval candidate generation, deterministic slot resolution. Most turns end here; the cloud never learns those turns happened.
2. **The Layer-1 safety pre-filter** (Spec 02 §7.6): the deterministic, binary-shipped ruleset hard-blocking known-harmful request *shapes* (covert surveillance, punitive self-harm/disordered-eating framing, medical diagnosis, financial transactions, third-party impersonation) — *before* an authoring call is constructed. The declined text never leaves the device.
3. **The tier gate**: no key → the paid path is never entered; the router still *produces* the intent and the app surfaces the honest upgrade prompt (Spec 05 §3.6) — locally.
4. **The cost guard**: the per-session rate limit inside the seam (Spec 03 §3.5); over the cap, the path degrades to a local clarify that *says* it is rate-limited.
5. **The consent check for journal-bearing prompts** (§5.4): a declined consent means the prompt is assembled *without* journal content — the bound is at assembly (`G-26`), so a declined turn's request body never contained the text at all.

### 5.2 What the routing call sends — and the one disclosure it implies

`routeResidual` transmits exactly two things (v0 `claude.dart`, matching Spec 03 §7.3.2):

- **The live utterance, verbatim.** This is irreducible — routing a phrasing requires the phrasing. It can incidentally contain anything the user said ("remind me to pick up Sarah's antidepressants"), which is why the standing consent for this is made explicit at key setup (§5.6 tier a) and why the free/offline tiers never send it.
- **The capability inventory**: per skill, its id, display name, and input slot *names* — no record content, no slot values, no examples drawn from user data. Subtlety worth stating: once the user has *authored* capabilities, their names are user-generated ("Track Emma's mood") and do disclose the *existence* of that tracking domain on every residual call. This is judged acceptable under tier-a consent — it is metadata the user created for exactly this routing purpose — but Spec 10 should carry it as a known disclosure, and a future option to mark a capability "sensitive" would additionally exclude it from residual-routing inventories exactly as sensitive-skill corpus entries are excluded from escalation context today (Spec 03 §5.6).

What routing **never** sends: correction-corpus *values* (escalation context, where used, is templates-only and excludes sensitive-skill entries entirely — Spec 03 §3.5/§5.6; the v0 implementation sends no corpus context at all, which is strictly less), record content, contact names not present in the utterance, or embeddings.

### 5.3 What the authoring call sends

`authorCapability` transmits the **described need in the user's words** ("I want to track my daughter's mood and what preceded her good and bad days"), plus — on retry — the deterministic validator's structured error, plus reconciliation candidates (existing type *names/descriptions* judged similar, Spec 02 §6.2). Authoring prompts are assembled from schema and metadata, never from record content (Spec 02 §6.3): Claude designs the capability without ever seeing a record. The description itself can of course be deeply personal — that is inherent to describing a personal capability — and authoring is therefore an explicit, user-initiated, preview-gated act (Spec 02 §6.5), never fired by an automation. The Layer-3 safety review re-sends the same description + the authored artifact to the reviewer model — same data class, no new disclosure.

### 5.4 What generative calls send — grounded assembly, feature by feature

Each generative kind's assembler (v0 `generative.dart`; the `GenerationRequest` DTO of Spec 04 §3.10) gathers **only the record classes that feature declares**, renders them as plain-text facts, and instructs the model to use *only* those. The assembly is deterministic and unit-testable; the table in §5.5 enumerates the exact classes per kind. Cross-cutting rules:

- **Journal text is excluded from every assembler by default.** It enters a prompt only under an explicit **per-session** consent: `pattern_insight` re-assembles *with* journal on an opt-in; `monthly_reflection` requires the mandatory consent card (Spec 04 §3.10 `G-26`; Spec 05 §11). The consent is a state on the *assembler*, not an instruction to the model, and it is **not user-disablable into a standing "always allow"** (DP-07) — the ask recurs each session, deliberately.
- **Contact ids are resolved to display names on-device** before assembly (`_contactName`), so the model sees the user's world ("Sarah"), and conversely no internal identifiers leak into prompts.
- **Empty grounding → no call** (§3.3): the honest local response is also the private one.
- Detached execution (Spec 04 §4.7) changes latency, not payload: the same assembled context is sent whether the request came from voice, a scheduled automation, or the UI affordance (Spec 05 §3.8).

### 5.5 The master table: feature → model → when the cloud is hit → what leaves → consent

**Ownership note (suite-sync, CS-12):** this table is the single normative egress registry — a new cloud-touching feature must add its row *here* before it ships; Spec 10 §5 is the threat-annotated view of these rows, and reviews each new row for threat posture rather than maintaining a second registry.

Consent tiers referenced below are defined in §5.6: **(a)** standing BYOK routing consent, **(b)** per-invocation feature consent, **(c)** per-session journal consent, **(–)** nothing leaves / no consent needed.

| Feature | Model | When the cloud is hit | What data leaves the device | Consent |
|---|---|---|---|---|
| Corpus fast-path routing (Spec 03 §5) | — (regex + resolvers) | **Never** | Nothing | – |
| Retrieval candidate generation (Spec 03 §7.3 step 2) | — (local embedder) | **Never** | Nothing | – |
| Deterministic slot resolution: dates, recurrence, quantities, entities (Spec 03 §6) | — | **Never** | Nothing | – |
| STT / TTS (Spec 12 — Voice) | — (platform on-device engines) | **Never** (Plenara-side; platform-native engines are configured on-device per Spec 12 §5.1; voice-privacy statement: Spec 12 §8) | Nothing via Plenara | – |
| All free-tier skills, queries, streaks, undo, semantic search, storage (Spec 04 §6.1) | — | **Never** | Nothing (sync goes to the *user's own* storage provider, not Claude — Spec 06) | – |
| Residual routing (Spec 03 §7.3 step 4) | Haiku | Novel phrasing, online + keyed, corpus/retrieval undecided, under the rate cap | Live utterance verbatim + capability inventory (ids, display names, slot names — incl. authored capability names, §5.2). Never: slot values, corpus values, record content, sensitive-skill entries | a |
| Capability authoring (Spec 02 §6) | v0: Haiku · target: Opus pin (§3.2) | User-initiated `define_*`, after Layer-1 pre-filter + tier gate; offline/free → local draft, no call | The described need in the user's words + validator errors on retry + similar-type names from reconciliation. Never: record content | b (explicit: user asked to build it; preview-gated activation) |
| Layer-3 authoring safety review (Spec 02 §7.6) | Haiku | Immediately after a validated authoring, before activation | Same description + the authored artifact (schema/metadata only) | b (inherited from the authoring act) |
| `briefing` (Spec 05 §15) | Haiku | On ask, or — for the scheduled automation — at notification-tap or next app-open (Spec 04 §3.13; never batch, §4.4) | Date; open task descriptions; active reminder texts; upcoming-birthday nudge lines | b (invocation) / b-standing for the scheduled automation, granted when the user enables the briefing automation |
| `gift_ideas` (Spec 05 §16) | Haiku | On ask | Target contact's display name, stored `contact_fact` texts, birthday | b |
| `event_prep` (Spec 05 §17) | Haiku | On ask | Attendees' names, facts, last-met dates, open-thread notes | b |
| `reconnect_coaching` (Spec 05 §18) | Haiku | On ask | Contact's name, facts, last-interaction date, today's date | b |
| `weekly_review` (Spec 05 §19) | Haiku | On ask, or weekly automation | The week's workouts, mood ratings, interaction entries (+notes), completed-task descriptions | b / b-standing (automation) |
| `pattern_insight` (Spec 05 §20) | Haiku → Sonnet | On ask, ≥2 tracker series present | The compared tracker series (dates + values), interaction dates + names. Journal **only on per-session opt-in** | b, +c if journal included |
| `meal_suggestion` (Spec 05 §21) | Haiku | On ask | Logged meals, stated goals/preferences | b |
| `monthly_reflection` (Spec 05 §22) | Sonnet/Opus | On ask, only after the mandatory consent card | A month of journal excerpts + interaction log | b + **c mandatory** (no consent → no call) |
| `foresight` (`G-27`) | Haiku | On ask | Upcoming events/reminders + similar past log entries | b |
| `draft_message` (P-20) | Haiku | On ask | Contact's name, facts, last ~3 interaction entries. (A draft only — the app never sends messages, DP-03) | b |
| Journal capture & search (Spec 05 §11–§12) | — | **Never** (on-device STT, local embeddings) | Nothing — journal content reaches Claude only via the two c-gated kinds above; it does sync as plaintext to the *user's own* provider (`G-37`, encryption deferred — Spec 01 §8.7), and onboarding says so | – (c for the two generative uses) |
| Functional-gap feedback / diagnostics (Spec 11; research §14) | — (email/manual channel, no endpoint) | Only on explicit user send, after a human-readable manifest | Functional shapes only — intent class, layer, confidence; **no PII, no user content, by construction** | Explicit per-send, opt-in, previewed |
| API key itself | — | On every cloud call | Sent only as the `x-api-key` header to `api.anthropic.com`, over TLS. Never in any record, log, or synced file (§6.2) | a |

Standing summary of the "never leaves" set: records at rest, the journal (absent tier-c), corpus slot values, embeddings, the execution journal, before-images, the key (except to Anthropic as auth), and any form of telemetry — **there is no telemetry**. On the Anthropic side, all of the above is processed under the user's own API account and Anthropic's API data-handling terms (API inputs/outputs are not used for model training by default; retention windows are Anthropic's published policy) — Plenara adds no additional party. Verifying and plainly wording that Anthropic-side statement for onboarding is Q5.

### 5.6 The consent model — three tiers, stated once

- **Tier (a) — standing routing consent, granted at key connection.** Adding an API key *is* the consent for the paid tier's ambient mechanics: residual utterances and the capability inventory may be sent to Anthropic on the user's own account when local routing can't decide. The onboarding flow states this in plain language at the moment the key is entered ("When Plenara can't understand a phrasing on its own, it will send that sentence — and only it — to Claude using your key"). No key → tier (a) does not exist → the app is fully local.
- **Tier (b) — per-invocation feature consent.** Asking for a generative feature ("what should I get Sarah?") is the consent for that feature's declared record classes (the table above) to be assembled and sent, that one time. The feature catalog in Settings shows each kind's "what it sends" line — the table is user-facing, not just spec-facing. Enabling a scheduled automation (daily briefing, weekly review) is the standing form of (b) for that automation's declared classes, revocable by disabling it.
- **Tier (c) — per-session journal consent, never standing.** Journal content is categorically excluded from (a) and (b). The two kinds that can use it ask per session; the mandatory card for `monthly_reflection` cannot be suppressed (DP-07). A "yes" expires with the session.

These tiers are enforceable at the assembler level (a Spec 09 property: no prompt-assembly path can include a record class outside its feature's declared set; no path can include journal text without a live tier-c grant), which is what distinguishes them from a privacy-policy promise.

---

## 6. The BYOK Flow

### 6.1 Acquisition & onboarding honesty

The paid-upgrade flow must state, *before* sending the user to the Anthropic console (research §15.2, learned firsthand):

1. **A Claude subscription (Pro/Max) will not work.** An API key from console.anthropic.com with pre-purchased credit is required — no provider lets a third-party app bill against a consumer subscription.
2. **What it will cost**, concretely: the §3.4 envelope ("typical heavy use is well under $1/month; a $5 credit will realistically last a year").
3. **What the key changes**, concretely: the tier-(a) consent sentence (§5.6), and the reminder that everything the free tier does stays fully local either way.

The wall is accepted for v1 (locked, research §15.1): the free tier is the wall-free on-ramp; BYOK is positioned for advanced users; a managed-key tier would require a backend and a changed privacy posture, and the key-source-agnostic seam means deferring it costs no rework.

**Ownership note (suite-sync, 05f §3 item 3):** the onboarding/consent-copy artifact — the tier-(a) sentence (§5.6), the three-point honesty script above, the Anthropic-terms wording (Q5), and Spec 01 §8.7's plaintext-posture statement — is owned by **this spec**, as a planned appendix (Appendix A — Onboarding & Consent Copy), to be reviewed against Spec 10's checklist (Spec 10 rec 6). It is spec'd copy, not ad-hoc UI text.

### 6.2 Key storage

- **Target (v1 product):** the platform secure store — Keychain/Secure Enclave (Apple), DPAPI/TPM-backed storage (Windows), Keystore (Android) — the same stores Spec 01 §8.7 designates for the CryptoBox master key. The key is device-local: it does **not** sync (each device is keyed independently; a second device asks for the key again rather than reading it from the folder), it never appears in any record, corpus entry, log line (the diagnostic log redacts values to type/shape by construction — research §14.2), or error surface (`CloudError.detail` carries HTTP status text, never the key).
- **v0 (dogfood, as implemented):** `~/.plenara/config.json` (plaintext, gitignored territory, outside the synced folder) with an `ANTHROPIC_API_KEY` environment-variable override (`config.dart`). Additionally a deliberate dev convenience: the rig's `.env` is read via a *relative* path only, so a production binary can never silently borrow the test key and mask a real `noKey` (`claude.dart`). **Accepted for single-user dogfooding; not shippable** — D9 records the migration as a release blocker for any distributed build. Deeper key-threat analysis (malware on-device, secure-store limits per platform) is Spec 10's.

### 6.3 Validation

**v0 posture (kept as the v1 default): no dedicated validation call.** A bad key is discovered on first use — HTTP 401/403 → `CloudErrorKind.badKey` → the distinct actionable surface ("your key was rejected — check it in Settings", Spec 05 §13). This costs nothing and never mislabels the failure.

**One refinement at key entry:** immediately validate the just-pasted key with a minimal probe call (a 1-token Haiku message; cost ≈ $0.00001) so the user gets "key works ✓" feedback *at the moment they can fix a paste error*, rather than at their first paid ask hours later. Failure modes map to the same typed kinds (`badKey` vs `offline` — a network failure during the probe must not report the key as bad). The probe is entry-time-only; the app never re-validates on a schedule (a revoked key surfaces on next use, exactly like any other `badKey`).

### 6.4 The offline / keyless degrade — three surfaces, never conflated

The full contract lives in Spec 04 §6 and Spec 05 §13 (`G-28`); this spec pins the mapping from the seam's typed errors to surfaces, because the mapping *is* the no-silent-failure guarantee at the cost boundary:

| `CloudErrorKind` | Meaning | Surface (per feature class) |
|---|---|---|
| `noKey` | Free tier / key removed | **Tier** surface: "that's a paid feature — add your API key in Settings" + upgrade path (Spec 05 §3.6). Routing: residual degrades to the deterministic clarify. Authoring: local **draft**, activation queued (Spec 04 §6.3). Generative: honest decline, never a fabricated local imitation |
| `offline` / `timeout` | Keyed but unreachable | **Connectivity** surface: "needs internet — I'll remind you when you're back online" (a reminder offer, not an upgrade prompt). Routing → clarify; authoring → draft; generative → "try again online" |
| `badKey` | 401/403 | **Key** surface: "your key was rejected" + Settings deep-link. Never mislabeled as offline |
| `rateLimited` | 429, or the app's own cost guard | **Quota** surface: "I've hit the limit on Claude — try again in a moment"; routing falls to clarify *and says why* (Spec 03 §3.5) |
| `serverError` / `malformed` | Anthropic-side fault or unusable body | Transient-fault surface, retry offered; a `malformed` on authoring feeds the one automatic re-author (Spec 02 §6.4) |
| `Ok(null)` (router abstain) | A real answer, not an error | Normal meta-intent / clarify path — "that's not something I can do yet; want me to build it?" |

The load-bearing invariant: **the free tier and the offline state are fully functional and identical in capability** (Spec 04 §6.1) — every degrade lands on a working local behavior plus an honest sentence, never on a dead end.

### 6.5 Key removal & revocation

Removing the key in Settings returns the app to the free tier instantly: paid affordances re-gate to the §3.6 prompt, scheduled generative automations pause with a visible reason (not silently — P2.8), drafts remain queued, and **no data cleanup is needed or possible server-side because nothing was ever stored server-side**. Revoking the key at the Anthropic console (the user's remedy if a device is lost) has the same effect from the app's perspective: next call → `badKey` → the key surface. This symmetry — the user can sever the only cloud relationship unilaterally, at either end, with zero residue — is a direct dividend of the no-backend posture and belongs in the privacy copy.

### 6.6 Spend visibility

Two mechanisms, neither requiring a backend:

- **Authoritative:** the Anthropic console's own usage/billing page and spend alerts, on the user's account — Settings links to it. Plenara does not duplicate the provider's ledger.
- **Local (proposed, Q3):** every API response carries `usage` token counts; the seam can accumulate them into a device-local, never-synced running tally ("Plenara has used ≈ $0.31 of your credit this month") at zero marginal cost. Deferred until the settings surface exists, but the seam should log `usage` from day one so history isn't lost.

---

## 7. Decision Record

### Resolved

- **D1 — One cloud seam, three calls.** All model traffic flows through `CloudClient.routeResidual` / `authorCapability` / `generate` against `api.anthropic.com` only; the BYOK gate and rate-limit cost guard live inside the seam. No other component may construct a network request to a model provider. *(Spec 04 §3.5; v0 `claude.dart`.)*
- **D2 — Haiku is the default cloud model** for residual routing (~$0.0004/turn, 94% measured) and for every generative kind (briefing $0.0007 measured), with Sonnet/Opus reserved for `pattern_insight` escalation and `monthly_reflection`. *(Findings §10.1, §13; Spec 04 §3.10 cost note.)*
- **D3 — Authoring model: capable-model pin is the target; v0's Haiku is an accepted interim.** Spec 02 §6.3 (`G-29`) requires a pinned Opus 4.7/4.8 + JSON-schema-constrained output for complex-skill serialization discipline; v0 ships Haiku + the deterministic validate→retry gate, acceptable while dogfooding is dominated by simple logging skills. Cost impact of the pin: ~$0.05/authored capability — rare enough to be immaterial. *(This also supersedes Spec 04 §3.5's "Sonnet" docstring — reconcile there.)*
- **D4 — The corpus ratchet is the cost cache; the plan cache stays deferred.** Learn-after-one-clean-use converts each recurring residual (~$0.0004) into a permanent free fast-path hit; post-NO-GO, plan resolution is already inference-free, so Lane 2 saves nothing material and remains unbuilt (locked, research §15.1). Never cache generative effects; the replay cassette is test-only. *(§4.1–§4.2, §4.5.)*
- **D5 — No API-level prompt caching in v1** — v1 prompts sit far below Haiku's 4,096-token cacheable-prefix minimum, and the sub-cent calls don't need the discount. The prompt assemblers keep stable-prefix discipline (byte-stable system + sorted inventory first, volatile content last) so caching is a flag-flip at the recorded adoption trigger (~130+ skills or a large stable Sonnet-reflection prefix). This *amends research §7.2's* prompt-caching assumption with current API mechanics. *(§4.3.)*
- **D6 — Batch API only for deadline-free work** (the weekly consolidation pass); the briefing generates at notification-tap or next app-open, never batch and never a background call (Spec 04 §3.13). *(Reaffirms research §7.2 amendment / Fable F-11; §4.4.)*
- **D7 — Three-tier consent model**: (a) standing routing consent granted at key connection, worded plainly at onboarding; (b) per-invocation feature consent with each generative kind's "what it sends" declared in the user-facing catalog (automations = standing (b), revocable); (c) per-session journal consent, never standing, mandatory card for `monthly_reflection`, not user-disablable (DP-07). Enforced at prompt assembly, testable in Spec 09. *(§5.6.)*
- **D8 — Minimization invariants**: routing sends utterance + capability metadata only (templates-only, sensitive-skill-excluded escalation context); authoring sends the described need + metadata, never record content; generative assemblers send only their declared record classes; the corpus persists slot shapes, never values (the `learn()` refusal rules); safety Layer 1, the tier gate, and the cost guard all run before any bytes leave. *(§5.1–§5.4.)*
- **D9 — Key storage**: platform secure store (Keychain/DPAPI/Keystore), device-local, never synced, never logged — a **release blocker** for any distributed build. v0's plaintext `~/.plenara/config.json` + env override is accepted for single-user dogfood only. *(§6.2.)*
- **D10 — Key validation**: no scheduled validation; first-use 401/403 → the distinct `badKey` surface; plus a one-time ~1-token probe at key entry for immediate paste-error feedback, with `offline` never misreported as `badKey`. *(§6.3.)*
- **D11 — The adoption wall stands as designed** (reaffirming research §15.1/§15.2): BYOK, no billing backend, free tier as the wall-free on-ramp; onboarding must say a Claude subscription won't work *and* quantify the real cost (§3.4's "a $5 credit lasts a year"). Managed keys stay deferrable without rework via the key-source-agnostic seam.
- **D12 — Zero-spend honesty gates**: a generative call is never made on empty/insufficient grounding; the honest local response is both cheaper and more private. *(§3.3, v0 `generative.dart`.)*

### Open

- **Q1 — Rate-cap resize (`G-38` follow-on, owned jointly with Spec 03 §3.5).** The 20/hour escalation cap was sized for rare tie-breaks; Haiku-as-cold-start-router blows through it during onboarding (the worst hour to look limited). Re-derive from the measured ~$0.0004/turn — a per-day cap with a burst allowance is the likely shape — and validate against beta cold-start traffic. Do not ship 20/hour unchanged.
- **Q2 — Final authoring pin + user-visible cost disclosure.** Confirm the Opus pin (or Sonnet, if structured outputs close the `G-29` gap at a third the price) once complex-skill authoring is exercised beyond the harness; decide whether the authoring preview shows an approximate cost line ("building this used ~$0.04 of your credit").
- **Q3 — Local spend tally.** Accumulate per-call `usage` into a device-local monthly total surfaced in Settings (§6.6). Cheap and honest; needs the settings surface. Log `usage` from day one regardless.
- **Q4 — Prompt-caching adoption trigger in practice.** Revisit D5 if beta users' authored inventories grow faster than expected, or when `monthly_reflection` lands on Sonnet with a multi-thousand-token stable prefix.
- **Q5 — Anthropic-side data-handling copy.** Verify and plainly word, for onboarding, Anthropic's current API data terms (training defaults, retention windows) as they apply to a BYOK consumer key; keep the claim dated. Deeper provider-trust analysis belongs to Spec 10.
- **Q6 — "Sensitive" capability flag for routing inventories.** Whether user-authored capabilities can be marked to be excluded from residual-routing inventories (accepting worse cold-start routing for those domains), extending the Spec 03 §5.6 sensitive-skill exclusion from corpus context to the inventory itself. Interacts with routing accuracy; needs a design pass with Spec 03.
- **Q7 — Generative-kind registry drift (membership RESOLVED by suite-sync; prompts still open).** Membership is settled: this spec's §3.3 table is the single owner of the closed set, `draft_message` is admitted (shipped P-20 feature), and Spec 03 §2.2a / Spec 04 §3.10 now cite §3.3 instead of enumerating. Still open: ship a reviewed kind-specific prompt per member (v0 covers only `gift_ideas`, `briefing`, `reconnect`; normalize `reconnect` ↔ `reconnect_coaching` naming in code) — the set is only closed when membership, prompt, and routing anchor all exist for each kind (Spec 09 §6.2 item 2).
