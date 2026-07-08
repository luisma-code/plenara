# Spec 13 — Reference Knowledge Bases

**Status:** Draft v0.1 — July 2026 (design memo + decision; written against Specs 01 v0.3, 02 v0.4, 03, 07 v0.x, 08 v0.1)
**Depends on:** Spec 01 — Meta-Schema (§2.2, §5.4, §12.4); Spec 02 — Skill DSL (§3, §6.4, §9.1); Spec 03 — NLU (§5, §6, §7.3); Spec 07 — UI (§3.1 A3/A9, §5); Spec 08 — AI Cost & Privacy (§2 D1, §4.1, §5.5)
**Blocks:** nothing on the critical path (this is a post-vertical-slice capability); adds testable contracts to Spec 09 and one egress row + one seam amendment to Spec 08 when built
**Research-doc precedence (suite-sync CS-26):** where the locked research doc and this spec disagree, this spec is authoritative.

---

## 0. Purpose & Scope

The question this spec decides: should Plenara ship **built-in reference knowledge bases** for common derived-stat domains — the concrete case being nutrition ("I ate mac and cheese" → a calorie figure) — so the app is not leaning on a cloud model for every derived number?

**The verdict, stated up front: yes, but as a scoped, general mechanism — not a nutrition feature.** Ship a small closed registry of read-only reference datasets in the binary, one new DSL read op (`read_reference`), a deterministic name-resolution tier in the NLU slot resolver, and a normalize-once-then-cache cloud fallback that reuses the corpus ratchet's exact economics. v1 ships two datasets (nutrition ~1,500 generic foods; unit conversions) and defers everything else.

One honesty note before the design, because it reframes *why* we are doing this: **the dollar-cost argument is weak and we should not pretend otherwise.** A Haiku estimate for an unknown food costs ~$0.0005 (Spec 08 §3.1's measured envelope), and the learn-after-one-clean-use ratchet (08 §4.1) would amortize even that to near-zero per phrasing. If cost were the only concern, the answer would be "don't bother." The KB earns its place on four other grounds:

1. **The free tier and offline.** `Meals` is a shipped free-tier tracker template (Spec 01 §12.4), and the free tier makes *zero* cloud calls, ever (08 §5.5). Without a shipped KB, free-tier and offline calorie counting is manual-entry-only — the user must speak the number. A ~1 MB dataset turns "log against any tracker conversationally" (research §3.2 task 4) into a stat-producing capability for users who never add a key.
2. **Determinism and trust (P2.4).** A lookup returns the *same* number for the same food every time, with a citable source (USDA). A model estimate drifts call-to-call, and a confidently-varying calorie figure corrodes trust in every other number the app shows.
3. **The hot path stays code (P2.7).** "I had oatmeal" is a routine action; the model must not be in its loop. A per-meal cloud estimate would put it there for every single log.
4. **Latency.** A lookup is microseconds; a cloud estimate is ~1 s on the app's most frequent interaction class.

Scope: the reference-dataset registry and format (§2), the lookup pipeline (§3), the DSL and meta-schema integration (§4), a worked trace (§5), the hard parts stated honestly (§6), cost/privacy deltas to Spec 08 (§7), the generalization rule (§8), and v1 scope (§9). It does **not** cover: barcode scanning, branded-food databases, photo-based food recognition, or user-authored reference datasets — all explicitly rejected or deferred (§8.3, §10).

---

## 1. Governing Principles

**P2.4 — Code over AI.** A calorie figure derivable from a table is a table lookup, not an inference. This spec is the direct application: it moves a whole class of "AI questions" into deterministic data + code, permanently.

**P2.7 — AI authors, code executes — extended to: AI *normalizes*, code *answers*.** The model's only role is mapping an unknown phrase to a canonical key (or supplying a one-time estimate for a genuinely unknown item), at most once per phrase, after which the mapping is cached data and every subsequent occurrence is pure code. This is the corpus ratchet's shape (research §4.9, Spec 03 §5) applied one layer down: the corpus caches *routing* decisions; the reference cache caches *knowledge* resolutions.

**P2.6 — Capabilities are data, but reference data is not user data.** A shipped dataset is not a type, not a record, and lives in neither `types/` nor a record folder. It is versioned app content, like the view archetypes (Spec 07 §3) and the Layer-1 safety ruleset (Spec 02 §7.6): a **closed set, extended only by an app release**. User-specific *learned* mappings (§3.4) are the one synced, user-owned artifact.

**P2.8 — No silent failure, specialized to: no silently-wrong numbers.** A derived stat always carries provenance (`reference` / `user` / `estimate` / absent), estimates render as estimates ("≈ 350 kcal"), and a lookup miss produces a record *without* the stat plus an honest sentence — never a guessed figure presented as fact. A wrong-but-confident calorie number is worse than no number.

**Spec 08's egress discipline is inherited whole.** Any cloud call this spec introduces appears in the §5.5 egress registry before it ships (CS-12), runs behind the single seam, and sends the minimum (§7).

---

## 2. What a Reference Dataset Is

### 2.1 Shape and storage

A reference dataset is a read-only, versioned lookup table shipped as an app resource (bundled asset, not in the synced folder):

```json
// bundled asset: reference/nutrition.json (illustrative entries)
{
  "datasetId": "nutrition",
  "datasetVersion": 3,
  "source": "USDA FoodData Central (FNDDS 2021–2023), public domain",
  "keyKind": "food",
  "entries": [
    {
      "key": "macaroni_and_cheese",
      "name": "Macaroni and cheese",
      "aliases": ["mac and cheese", "mac n cheese", "mac & cheese", "kraft dinner"],
      "per100g": { "kcal": 176, "protein_g": 7.3, "carbs_g": 19.9, "fat_g": 7.6 },
      "serving": { "label": "1 cup", "grams": 200 },
      "measures": [ { "label": "cup", "grams": 200 }, { "label": "bowl", "grams": 350 } ]
    },
    {
      "key": "oatmeal_cooked",
      "name": "Oatmeal, cooked",
      "aliases": ["oatmeal", "porridge", "oats"],
      "per100g": { "kcal": 71, "protein_g": 2.5, "carbs_g": 12.0, "fat_g": 1.5 },
      "serving": { "label": "1 cup", "grams": 234 },
      "measures": [ { "label": "cup", "grams": 234 }, { "label": "bowl", "grams": 300 } ]
    }
  ]
}
```

- **Keys** are stable snake_case identifiers, immutable across dataset versions (same discipline as `typeId`, Spec 01 §4.2). Entries may be superseded, never renamed.
- **Values** are per-100g plus a default serving and a short list of household measures. Composite dishes ("mac and cheese", "chicken salad") are **first-class entries with as-consumed nutrient values** — see §6.3 for why we never decompose recipes.
- **Location:** binary resource only. It is *not* materialized into the synced folder (unlike tracker templates, Spec 01 §12.4 CS-22): it is identical for every user, ~1 MB, and regenerable — syncing it would be pure churn. The embedding index over its keys/aliases (§3.2) is device-local `[app-support]`, exactly like the type/skill index (Spec 01 §5.4), rebuilt from the asset.
- **Size:** ~1,500 foods × ~300 bytes ≈ 0.5 MB raw, ~150 KB compressed in the bundle; the key-embedding index ≈ 1,500 × 384 dims × 4 B ≈ 2.3 MB device-local. Against the ~80 MB retrieval model we already ship as a "size-for-reliability trade" (Spec 01 §5.1), this is noise.

### 2.2 Sourcing and licensing — the reality

- **Nutrition:** USDA FoodData Central is a **U.S. government work — public domain**. Specifically, **FNDDS** (the survey database) is the right base: it contains ~7,000 foods *as consumed* — composed dishes like "Macaroni and cheese, prepared from box mix" with measured nutrients and household portion weights — which is exactly what dissolves the recipe-decomposition problem (§6.3). SR Legacy / Foundation Foods cover raw ingredients. Curating the top ~1,500 by consumption frequency is a one-time offline pipeline job.
- **Branded foods:** USDA's Branded Foods data is also public-domain-dedicated but is a fast-moving, 400k-item, staleness-prone tail. **Rejected for v1** (§8.3) — it is where nutrition apps go to become nutrition apps.
- **Unit conversions:** definitional; no licensing question. Tiny.
- **Exercise MET values (future):** the Compendium of Physical Activities is published research, freely available and universally used; a derived table of ~100 common activities is defensible. Deferred (§9).
- Every dataset carries its `source` string, surfaced in Settings — the provenance is user-visible, not just spec-visible.

### 2.3 Staleness and versioning

Nutrient data barely rots (an apple's kcal is stable on a decade scale). Datasets are refreshed opportunistically with app releases via `datasetVersion`. **Records freeze their values at capture** (§4.4): a dataset update never rewrites history — a meal logged at 350 kcal stays 350 kcal, with the record carrying `datasetVersion` for auditability. This is the same "record what happened" discipline as frozen `{now}` (Spec 02 §4.4).

---

## 3. The Lookup Pipeline

Name → key resolution is the whole game (§6.1), and it is layered exactly like the routing cascade (Spec 03 §7.3): free deterministic tiers first, the model last and at most once per phrase.

### 3.1 Tier 0 — exact and alias match (code, free)

Case/whitespace-normalized match against `key`, `name`, `aliases` of the shipped dataset, then against the user's **learned aliases** (§3.4). Same tiering as `read_one`'s alias tier (Spec 02 §3, `G-24`). Expected to carry the large majority of steady-state traffic — food vocabulary per user is highly repetitive.

### 3.2 Tier 1 — embedding nearest-neighbor (local, free)

The shipped retrieval embedder (bge-small class, Spec 01 §5.1) queries the device-local index over names + aliases. **Conservative by design:** accept only above a high similarity threshold with a clear margin over the runner-up (the retrieval-margin signal of Spec 03 §7.3.1); anything ambiguous is a miss, not a guess. A confidently wrong food mapping ("chicken salad" → "chicken, fried") is the failure mode this tier must not have — precision over recall, because Tier 2 and the honest-miss path both exist.

### 3.3 Tier 2 — cloud normalize-and-cache (Haiku, once per phrase)

On a miss, **keyed + online only**: one constrained call — the food phrase plus the top-k candidate keys — returning either (a) one of the candidate keys, (b) a **new estimated entry** `{name, per100g, serving}` for a genuinely uncovered item ("khachapuri"), or (c) an abstain. Result (a) is cached as a learned alias; result (b) as a learned entry with `source: "estimate"`. Either way, **the model is consulted at most once per phrase per user, ever** — the next "khachapuri" is a Tier-0 hit. Free tier / offline: no call; the honest-miss path (§3.5) applies, and the phrase is queued so the *next* keyed+online session can backfill (same detached posture as authoring drafts, Spec 04 §6.3).

### 3.4 The learned store

`[plenara-root]/reference/learned/{datasetId}/{entryId}.json` — synced, per-entry files (one file per learned alias or entry, avoiding the `G-36` monolithic-file LWW self-conflict that `nlu/corrections.json` still carries). Learned entries are user data: they sync, they are user-visible and correctable ("that's not what khachapuri is"), and a correction updates the entry and — per the corpus discipline — is the only thing that invalidates it. Privacy note: a learned alias contains a food phrase the user spoke. That is the same disclosure class as the synced meal record it accompanies; nothing new leaves the *device* by storing it (the cloud call that produced it is the disclosure, consented per §7).

### 3.5 The honest miss

All tiers miss (or free/offline at Tier 2): the record is written **without** the derived stat, the confirmation says so plainly ("Logged khachapuri — I don't know its calories yet; tell me or I'll look it up when online"), and the record surfaces a backfill affordance. The user can speak a value (`source: "user"` — always highest precedence, never overwritten by any tier).

---

## 4. DSL & Meta-Schema Integration

### 4.1 One new primitive: `read_reference` (opcode 11)

A read-category op against the ReferenceStore (not the StorageRepository). Side-effect-free, so permitted in the resolve phase like all reads (Spec 02 §4.1). Appended to the opcode table under the append-only discipline (Spec 02 §3.0) — this is an interpreter version bump, made once, exactly what the closed-vocabulary rule reserves version bumps for.

```json
{
  "op": "read_reference",
  "dataset": "nutrition",
  "key": "{itemKey}",
  "quantity": "{quantity}",
  "measure": "{measure}",
  "into": "nutrition"
}
```

| Field | Required | Notes |
|---|---|---|
| `dataset` | yes | Must be a shipped `datasetId`. Validated at authoring/registration (Spec 02 §6.4 gains a rule 7: every `read_reference.dataset` ∈ the shipped registry) — the closed-vocabulary discipline extended to datasets. |
| `key` | yes | A canonical key, usually a resolver-supplied slot (§4.2). **Exact/learned match only** — no fuzzy logic inside the op; fuzziness lives in the resolver, keeping the op deterministic and trivially testable. |
| `quantity` / `measure` | no | e.g. `2` + `"bowl"`. The op resolves the measure against the entry's `measures` (fallback: default `serving`) and returns values **scaled** — scaling lives in the op so skills don't hand-roll nutrient arithmetic. Absent → one default serving. |
| `into` | yes | Bound to `{kcal, protein_g, carbs_g, fat_g, grams, source, datasetVersion}`, or **null on a miss** — null propagation (Spec 02 §3.7) and `branch {isNull}` handle the rest. |

Skills using it declare it: `reads` gains namespaced entries (`"reference:nutrition"`), so capability closure (Spec 02 §6.4 rule 3) covers reference access and the skill file honestly discloses what the skill consults.

Two compute-fn additions ride the same interpreter bump: **`mul`** and **`div`** (the closed fn set has `add`/`sum` but no multiplication — needed the moment any skill scales anything, and generally useful). Total mechanism cost: **1 op + 2 fns + 1 validator rule.**

### 4.2 The resolver seam (Spec 03 §6 gains a sibling)

A **deterministic reference resolver** joins the entity and date resolvers: for a slot declared against a dataset, it runs Tiers 0–1 locally and emits — mirroring the `G-12` resolve-or-create contract exactly — **both** an `itemKey?` (canonical key, when resolved) and the raw `itemText` (always). Tier 2 is invoked by the orchestrator on the same residual terms as routing escalation (keyed, online, under the cost guard). The skill never fuzzy-matches; it branches on `{isNull: itemKey}`.

### 4.3 The `log-meal` seed skill, upgraded (sketch)

```json
{ "skillId": "log-meal",
  "inputs": [
    { "name": "itemText",  "valueType": "text",   "source": "slot", "required": true },
    { "name": "itemKey",   "valueType": "text",   "source": "slot", "required": false },
    { "name": "quantity",  "valueType": "number", "source": "slot", "required": false },
    { "name": "measure",   "valueType": "text",   "source": "slot", "required": false },
    { "name": "capturedCalories", "valueType": "number", "source": "slot", "required": false } ],
  "reads": ["reference:nutrition"], "writes": ["meal"],
  "steps": { "main": [
    { "op": "branch", "condition": { "notNull": "capturedCalories" },
      "then": [ { "op": "set", "var": "kcal", "value": "{capturedCalories}" },
                { "op": "set", "var": "kcalSource", "value": "user" } ],
      "else": [
        { "op": "read_reference", "dataset": "nutrition", "key": "{itemKey}",
          "quantity": "{quantity}", "measure": "{measure}", "into": "n" },
        { "op": "set", "var": "kcal", "value": "{n.kcal}" },
        { "op": "set", "var": "kcalSource", "value": "{n.source}" } ] },
    { "op": "write_record", "typeId": "meal",
      "fields": { "description": "{itemText}", "calories": "{kcal}",
                  "caloriesSource": "{kcalSource}", "loggedAt": "{now}" }, "into": "meal" },
    { "op": "format",
      "template": "Logged {itemText}.{kcal, prefix: ' About ', suffix: ' kcal.', omitIfNull: true}",
      "into": "confirmationText" } ] },
  "dangerLevel": "safe" }
```

A null `itemKey` makes `read_reference` bind null; null propagation writes the meal with no `calories` — the honest miss falls out of existing semantics with no special casing. (User-spoken calories always win — first branch.)

### 4.4 Meta-schema: denormalize at capture, with provenance

Spec 01 §2.2 excludes computed *fields*; this does not violate it — the skill **writes a captured value** (like any slot), frozen at log time with the dataset version, per §2.3. The `meal` template gains two optional attributes: `caloriesSource` (`enum: reference|user|estimate`) and `refDatasetVersion` (`number`). Aggregates stay query-time: "calories today" is `read_many` + `sum` — already in the fn set, already how the `ledger`/`counter` archetypes get their period summaries (Spec 07 §3.1 A3/A9). *Proposed cross-spec addition (Spec 07 §5, not edited here):* the numeric render treatment prefixes `≈` when the paired `…Source` is `estimate` — estimates must *look* like estimates on the tracker surface.

---

## 5. Worked Trace — "I ate mac and cheese"

**Known food (steady state — zero model calls):**
1. **Route:** corpus fast-path matches the learned `log-meal` template; slots `{itemText: "mac and cheese"}`. Free, local (Spec 03 §5).
2. **Resolve slot:** reference resolver, Tier 0 — "mac and cheese" is a shipped alias of `macaroni_and_cheese`. Emits `itemKey`. Free, local, deterministic.
3. **Resolve skill:** `read_reference` → per-serving values (no quantity → default 1 cup / 200 g → 352 kcal); `write_record meal {calories: 352, caloriesSource: "reference"}`; `format`.
4. **Act-then-describe:** *"Logged mac and cheese. About 352 kcal."* The ledger/counter home updates its period total by query-time `sum`.

**Cloud calls: zero.** Same for oatmeal, coffee, pizza, and everything else in the top ~1,500 — forever.

**Unknown food ("I ate khachapuri", keyed + online — one model call, once ever):**
Tiers 0–1 miss → one Haiku normalize call (phrase + candidates) → no candidate fits → returns an estimated entry → cached to the learned store → meal written with `calories: ≈520, caloriesSource: "estimate"` → *"Logged khachapuri — roughly 520 kcal, my estimate."* Every future khachapuri is a Tier-0 hit. Cost: ~$0.0005, once.

**Unknown food, free tier / offline — zero calls, zero pretending:**
Tiers 0–1 miss → meal written with no calories → *"Logged khachapuri — I don't know its calories; tell me a number, or I'll look it up when I'm online"* (keyed) / "…you can tell me a number" (free). The record carries the backfill affordance; the phrase queues for the next keyed+online session.

---

## 6. The Hard Parts, Honestly

### 6.1 Name normalization is the actual product
Food language is idiomatic, multilingual, and personal ("mac and cheese" / "kraft dinner" / "the orange pasta"). The three-tier resolver is the best available shape — curated aliases catch the head, embeddings catch paraphrase, the model catches the tail once — but **resolution precision is a make-or-break metric exactly like the corpus learning rate** (research §7.1 caveat), and it must be measured in beta, not assumed. The mitigations are structural: Tier 1 is precision-biased (§3.2); every figure carries provenance; a spoken correction relearns the alias (the same correct-and-learn loop as NLU, P2.1).

### 6.2 Portions dominate the error bar
"A bowl" is 200–400 g; a default serving can be off ~2×. No dataset fixes this — even gram-weighed tracking apps carry large real-world error. Plenara's honest position: shipped household measures + per-food default serving, `≈` labeling, and the framing that the product is **trend-grade, not clinical-grade** — "you're averaging ~2,400 kcal this week, higher than last" is genuinely useful at ±30%; a medical-grade claim would be false at any precision we can reach. (The Layer-1 safety floor already handles the adjacent risk: punitive-framing calorie tooling is hard-blocked regardless of this spec — Spec 02 §7.6.)

### 6.3 Recipe decomposition — refuse the rabbit hole
Decomposing "mac and cheese" → ingredients → sum is combinatorially open-ended (whose recipe? what proportions?) and strictly worse than the alternative: **FNDDS already publishes composed dishes as consumed, with measured nutrients** (§2.2). We ship dishes as atoms. Multi-item utterances ("oatmeal and coffee") are N lookups + the existing multi-write idiom (Spec 02 §9.3), not decomposition. True homemade-recipe modeling ("my lasagna") is deferred — expressible later as a learned entry the user dictates once ("my lasagna is about 600 a slice" → `source: "user"` entry), which needs no new machinery.

### 6.4 The tail is permanent
~1,500 generic foods plausibly cover the large majority of *logged utterances* (food-frequency research consistently shows a few hundred foods dominate individual diets — but this is an assumption to validate in beta, not a fact). Branded items, restaurant meals, and regional dishes are a long tail that no shippable dataset closes. That is why §3.3–§3.5 are part of the design, not an afterthought: **the KB moves ~80% of cases off the fallback path; it does not eliminate the path.** If the KB were rejected outright, §3.3–§3.5 alone *is* the how-we'd-handle-it answer (user values + one-time cached estimates + honest labeling) — workable, but free-tier users would get no derived stats at all, and every keyed user's cold start would be model-touched.

### 6.5 Maintenance
One offline curation pipeline (FDC → our format), rerun opportunistically per release. No server, no live updates, no license renewals. The realistic maintenance risk is scope creep (§8.3), not data rot (§2.3).

---

## 7. Cost & Privacy Deltas (amendments to Spec 08)

- **The seam grows a fourth call.** `normalizeReference(dataset, phrase, candidates)` joins `routeResidual`/`authorCapability`/`generate` — amending 08 D1's "three calls." Same typed `CloudResult` contract, same tier gate and cost guard, Haiku, `max_tokens` ≈ 300, constrained output. It is not a `generativeKind` (those are never cached and always regenerated — 08 §4.2; normalization is the opposite: cached forever, regenerated never).
- **New egress-registry row (08 §5.5, per CS-12), before it ships:**

| Feature | Model | When the cloud is hit | What leaves | Consent |
|---|---|---|---|---|
| Reference normalization (§3.3) | Haiku | Lookup miss after local tiers; keyed + online; once per phrase, under the cost guard | The unresolved item phrase (e.g. "khachapuri") + candidate dataset keys. Never: the rest of the utterance, record content, other slots | a (standing routing consent — same class as the residual utterance, and stated in the tier-(a) onboarding sentence) |

- **Cost envelope:** ~$0.0005/call, self-extinguishing per phrase by construction. A pathological month (300 novel foods) ≈ $0.15, once, then ~$0 — inside the 08 §3.4 envelope's rounding error. The KB's cost contribution is therefore *not* the point (per §0); what it buys is the free-tier/offline capability and hot-path determinism.
- **Zero-spend gates inherited:** free tier and offline never reach Tier 2; the honest miss is local and free (08 D12's "honesty is cheaper than generation," verbatim).

---

## 8. The General Pattern — and Its Admission Rule

### 8.1 The pattern
**Bundled reference dataset + deterministic lookup op + resolver tiers + normalize-once cloud fallback.** Nutrition is the first instance, not a special case: the mechanism (§2 format, §3 pipeline, §4 op) is dataset-agnostic by construction.

### 8.2 Admission rule for a dataset (all five, or it doesn't ship)
1. **Stable facts** — values that don't rot on an app-release timescale (nutrients: yes; prices: no).
2. **Clean license** — public domain or equivalent, source citable in-app.
3. **Bounded head** — a curatable top-N covering most real utterances; a domain that is *all* tail (branded goods) fails.
4. **Feeds a shipped surface** — a tracker template or seed skill actually consumes it (a dataset without a consumer is bloat).
5. **Small** — sub-few-MB including its index.

Qualifying next candidates: **unit conversions** (v1 — trivial, feeds `mul`/`div`-based skills, arguably a compute-fn table more than a dataset but registered uniformly), **exercise METs** (~100 activities, feeds Run/Walk templates' effort estimates — deferred), **caffeine/hydration content** (feeds Water — deferred). Rejected under the rule: branded foods (fails 1, 3), drug interactions (fails the Layer-1 medical-diagnosis floor before it fails anything here), anything requiring live data (fails 1 and the no-backend posture).

### 8.3 The rabbit-hole guard
The registry is **closed the way the archetype set is closed** (Spec 07 §3): extended only by an app release, against the admission rule, with a consuming surface. Plenara is not becoming a nutrition app; it is a personal assistant whose meal tracker produces an honest number most of the time without asking anyone.

---

## 9. v1 Scope & Staging

**Ships in v1 (of this capability):** the ReferenceStore + dataset format; `read_reference` (opcode 11) + `mul`/`div`; validator rule 7; the reference resolver (Tiers 0–1); `nutrition` (~1,500 FNDDS-derived generic foods + aliases + measures) and `units`; the upgraded `log-meal` seed skill + `meal` template attributes; the honest-miss surface.

**Ships with, or immediately after:** Tier 2 normalize-and-cache + the learned store + the 08 amendments (§7) — it is the smaller half of the work and the tail is met on day one, but the local tiers are independently shippable and useful.

**Deferred:** METs and further datasets; user-dictated recipe entries (§6.3); quantity-grammar breadth beyond `{number} × {measure}`; any Spec 07 render work beyond the `≈` treatment.

**Staging:** post-vertical-slice. Nothing on the routing/capture critical path depends on this spec; the tracker templates function without it (calories stay an optional spoken slot). It is the first capability to build once the core loop is proven, because it multiplies the value of a tracker that already works.

---

## 10. Decision Record

### Resolved

- **D1 — Build it, scoped.** Bundled reference KBs are adopted as a general mechanism (registry + one DSL op + resolver tiers + normalize-once fallback), with nutrition and units as the only v1 datasets. Decisive grounds: free-tier/offline capability, determinism/trust, hot-path purity, latency — explicitly *not* API cost, which is negligible either way (§0). *(This is the honest inversion of the question as asked: the KB is justified even though the per-stat model cost it "saves" is a rounding error.)*
- **D2 — Reference data is app content, not user data.** Binary-shipped, versioned, never in the synced folder, never a type; the device-local index mirrors the capability index's placement (Spec 01 §5.4). Learned aliases/entries are the one synced, user-owned, correctable artifact — per-entry files, avoiding `G-36`. *(§2.1, §3.4.)*
- **D3 — One op, exact-match, fuzziness in the resolver.** `read_reference` (opcode 11, read category, resolve-phase-safe) does deterministic key lookup + measure scaling only; all fuzzy resolution lives in the NLU-layer reference resolver, mirroring the entity/date resolver split and the `G-12` id+text slot contract. `mul`/`div` join the closed fn set in the same interpreter bump. *(§4.1–§4.2.)*
- **D4 — Dishes are atoms; no recipe decomposition.** FNDDS as-consumed composites are the dataset base; multi-item utterances are N lookups under the existing multi-write idiom. *(§6.3.)*
- **D5 — Provenance is mandatory and frozen.** Every derived stat carries `…Source` (`reference|user|estimate`); user-spoken values always win; values freeze at capture with `refDatasetVersion`; estimates render as `≈`. No silently-wrong numbers. *(§4.4, P2.8.)*
- **D6 — The model normalizes at most once per phrase.** Tier 2 is keyed+online only, behind the seam as a fourth call (`normalizeReference`, amending 08 D1), added to the 08 §5.5 egress registry under tier-(a) consent, sending the item phrase + candidate keys and nothing else. Its result is cached forever; corrections are the only invalidation. *(§3.3, §7.)*
- **D7 — Trend-grade, said plainly.** Portion ambiguity bounds accuracy at roughly ±30–50%; the product claim is trends and totals, never clinical precision; the Layer-1 floor on punitive framing is unchanged and upstream of everything here. *(§6.2.)*
- **D8 — Closed dataset registry with an admission rule** (stable, licensed, bounded head, consuming surface, small); extended only by app release. *(§8.)*

### Open

- **Q1 — Coverage validation.** The "~1,500 foods ≈ 80% of logged utterances" claim is a literature-shaped assumption. Instrument the resolver-tier hit rates in dogfood/beta (alongside the corpus learning-rate metric it parallels) and resize the dataset from data.
- **Q2 — Resolution-precision bar.** Set the Tier-1 acceptance threshold/margin empirically (a small eval of food-phrase → key pairs, in the Spec 09 harness style); decide the false-accept budget. A mis-mapped food is this spec's worst failure — the eval gates shipping Tier 1, the way the `G-20` eval gated the local router.
- **Q3 — Quantity grammar scope.** v1 parses `{number} {measure}` ("two bowls"); decide how far the deterministic quantity resolver goes (fractions, "half a", grams/ounces) before it becomes the date-resolver's messier sibling — and whether it merges with the existing quantity resolution in Spec 03 §5's slot machinery.
- **Q4 — Learned-entry hygiene.** Whether the weekly consolidation pass (Spec 01 §6.2) should also triage learned reference entries (merge near-duplicate aliases, flag never-used estimates), and whether a learned *estimate* should be upgradeable to a shipped key when a later dataset version covers it.
- **Q5 — Backfill UX.** Where the "N meals are missing calories" affordance lives (AttentionSurface vs the tracker home) and whether backfill may batch multiple queued phrases into one normalize call.
- **Q6 — Cross-spec landings.** On build: the Spec 08 §5.5 row + D1 amendment (§7), the Spec 02 §3 op/fn/validator additions, the Spec 03 §6 resolver sibling, the Spec 07 §5 `≈` treatment, and Spec 09 contracts (op determinism; resolver precision eval; the "no derived stat without provenance" invariant). Recorded here so this spec, not tribal memory, is the checklist.
