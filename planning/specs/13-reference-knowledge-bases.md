# Spec 13 — Reference Knowledge Bases

**Status:** Active v0.2 — audited against the wired implementation 2026-09-07. The nutrition
dataset, exact lookup, optional feature-hash resolver, `read_reference`, `mul`/`div`, and honest
meal logging are implemented. Dataset verification, units, quantity scaling, production fuzzy
resolution, learned aliases, and cloud normalization are explicitly marked destinations.
**Depends on:** Spec 01 — Meta-Schema (§2.2, §5.4, §12.4); Spec 02 — Skill DSL (§3, §6.4, §9.1); Spec 03 — NLU (§5, §6, §7.3); Spec 07 — UI (§3.1 A3/A9, §5); Spec 08 — AI Cost & Privacy (§2 D1, §4.1, §5.5)
**Blocks:** nothing on the critical path (this is a post-vertical-slice capability); adds testable contracts to Spec 09 and one egress row + one seam amendment to Spec 08 when built
**Research-doc precedence (suite-sync CS-26):** where the locked research doc and this spec disagree, this spec is authoritative.

---

## 0. Purpose & Scope

The question this spec decides: should Plenara ship **built-in reference knowledge bases** for common derived-stat domains — the concrete case being nutrition ("I ate mac and cheese" → a calorie figure) — so the app is not leaning on a cloud model for every derived number?

**The verdict, stated up front: yes, as a scoped mechanism — and its current realization is
narrower than the original design.** Plenara seeds one `nutrition.json` dataset with 403 generic
entries into the chosen data root, uses exact normalized key/alias lookup in production, and exposes
one DSL read op (`read_reference`). A component-tested feature-hash resolver exists but is not used
by meal routing. Units, learned mappings, and cloud normalize-and-cache do not exist.

### 0.1 Current implementation map

- `ReferenceStore.load(dataDir, 'nutrition')` reads `reference/nutrition.json`; missing or malformed
  data degrades to an empty store.
- `lookup` normalizes case, punctuation, articles, and bare counts, then matches a canonical key or
  alias. `resolve` adds conservative feature-hash nearest-neighbor lookup and is component-tested,
  but no production caller invokes it.
- `read_reference` performs exact lookup and returns the entry plus `provenance`/`refKey`; it does
  not scale quantities or measures.
- `log-meal` records a hit's calories and `reference` provenance. A miss records no calorie value,
  uses `user` provenance, and says no estimate was made.
- The checked-in seed declares `provenance: model-estimated` and says its serving values await USDA
  FNDDS verification. It must not be described as USDA-verified or clinical-grade.

One honesty note before the design, because it reframes *why* we are doing this: **the dollar-cost argument is weak and we should not pretend otherwise.** A Haiku estimate for an unknown food costs ~$0.0005 (Spec 08 §3.1's measured envelope), and the learn-after-one-clean-use ratchet (08 §4.1) would amortize even that to near-zero per phrasing. If cost were the only concern, the answer would be "don't bother." The KB earns its place on four other grounds:

1. **The free tier and offline.** `Meals` is a shipped free-tier tracker template (Spec 01 §12.4), and the free tier makes *zero* cloud calls, ever (08 §5.5). Without a shipped KB, free-tier and offline calorie counting is manual-entry-only — the user must speak the number. A ~1 MB dataset turns "log against any tracker conversationally" (research §3.2 task 4) into a stat-producing capability for users who never add a key.
2. **Determinism and trust (P2.4).** A lookup returns the *same* number for the same food every time, with a citable source (USDA). A model estimate drifts call-to-call, and a confidently-varying calorie figure corrodes trust in every other number the app shows.
3. **The hot path stays code (P2.7).** "I had oatmeal" is a routine action; the model must not be in its loop. A per-meal cloud estimate would put it there for every single log.
4. **Latency.** A lookup is microseconds; a cloud estimate is ~1 s on the app's most frequent interaction class.

Scope: the reference-dataset registry and format (§2), the lookup pipeline (§3), the DSL and meta-schema integration (§4), a worked trace (§5), the hard parts stated honestly (§6), cost/privacy deltas to Spec 08 (§7), the generalization rule (§8), and v1 scope (§9). It does **not** cover: barcode scanning, branded-food databases, photo-based food recognition, or user-authored reference datasets — all explicitly rejected or deferred (§8.3, §10).

---

## 1. Governing Principles

**P2.4 — Code over AI.** A calorie figure derivable from a table is a table lookup, not an inference. This spec is the direct application: it moves a whole class of "AI questions" into deterministic data + code, permanently.

**P2.7 — Code answers; any future AI normalization must cache.** Current lookup makes no model
call. If cloud normalization is ever added, its only permitted role is mapping an unknown phrase or
producing an explicitly estimated entry once, then caching that user-correctable result.

**P2.6 — Reference data is seeded app content, not a user record.** It is not a type or record, but
the current seed is materialized under `reference/` in the chosen Plenara data root by
`ensureSeeded`. A provider-backed root can therefore sync that file like other root content.
User-specific learned mappings are a destination and have no storage format in the current app.

**P2.8 — No silent failure, specialized to: no silently-wrong numbers.** A derived stat always carries provenance (`reference` / `user` / `estimate` / absent), estimates render as estimates ("≈ 350 kcal"), and a lookup miss produces a record *without* the stat plus an honest sentence — never a guessed figure presented as fact. A wrong-but-confident calorie number is worse than no number.

**Spec 08's egress discipline is inherited whole.** Any cloud call this spec introduces appears in the §5.5 egress registry before it ships (CS-12), runs behind the single seam, and sends the minimum (§7).

---

## 2. What a Reference Dataset Is

### 2.1 Shape and storage

A reference dataset is seeded JSON lookup data. The following richer versioned shape is a design
example, not the current file format:

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
- **Current location:** the Flutter bundle mirrors `v0/data/reference/nutrition.json`, and bootstrap
  copies it into `<data-root>/reference/nutrition.json` if absent. Existing reference files are not
  overwritten by seed reconciliation. A user-selected provider root may sync it.
- **Current size/content:** 403 entries with flat per-serving fields (`serving`, `grams`, `kcal`,
  macros, category). There is no unit-conversion dataset and no persistent embedding index. The
  feature-hash vectors used by `ReferenceStore.resolve` are built lazily in memory.

### 2.2 Sourcing and licensing — the reality

- **Current nutrition seed:** model-estimated typical serving values, explicitly pending USDA FNDDS
  verification. It may support personal trend logging but cannot claim USDA provenance.
- **Approved source destination:** USDA FoodData Central/FNDDS is public-domain U.S. government
  data and remains the intended verification/replacement source for as-consumed foods.
- **Branded foods:** USDA's Branded Foods data is also public-domain-dedicated but is a fast-moving, 400k-item, staleness-prone tail. **Rejected for v1** (§8.3) — it is where nutrition apps go to become nutrition apps.
- **Unit conversions:** definitional; no licensing question. Tiny.
- **Exercise MET values (future):** the Compendium of Physical Activities is published research, freely available and universally used; a derived table of ~100 common activities is defensible. Deferred (§9).
- The current dataset carries top-level `provenance` and `note`, but Settings does not yet surface
  them. Per-record lookup provenance is stored on meal records.

### 2.3 Staleness and versioning

Captured meal values are frozen and seed reconciliation never rewrites records. The current dataset
does not carry `datasetVersion`, and meal records do not store one; adding versioned provenance is a
destination that requires a data migration, not an existing audit guarantee.

---

## 3. The Lookup Pipeline

Name → key resolution is the whole game (§6.1), and it is layered exactly like the routing cascade (Spec 03 §7.3): free deterministic tiers first, the model last and at most once per phrase.

### 3.1 Tier 0 — exact and alias match (code, free)

`ReferenceStore.lookup` normalizes case, punctuation, common articles/quantifiers, and bare numeric
counts, then matches `key` or `aliases`. The current entries have no `name` field and there is no
learned-alias store.

### 3.2 Tier 1 — local similarity lookup (implemented component, not production path)

`ReferenceStore.resolve` first calls exact lookup, then lazily builds in-memory feature-hash vectors
over canonical keys and accepts the best cosine match above a configurable threshold (default
0.6). It is covered by component tests. `Session` and `read_reference` currently call `lookup`, not
`resolve`, so meal logging does not use fuzzy resolution. Wiring it requires precision/margin
evidence because a confidently wrong food mapping is worse than an honest miss.

### 3.3 Tier 2 — cloud normalize-and-cache (destination, not implemented)

No cloud normalization call, queued backfill, or learned-entry creation exists. If this destination
is implemented, it must be keyed+online, constrained to the phrase and candidate keys, explicitly
estimated when it creates a value, cached after one clean use, and added to Spec 08's egress
registry before release.

### 3.4 The learned store (destination)

No learned reference store exists. The proposed per-entry path remains a storage design only and
must be reconciled with Spec 06 before implementation.

### 3.5 The honest miss

An exact lookup miss writes the meal **without** calories, stores `provenance: "user"`, and says
“I don't have calorie data for that, so no estimate.” There is no automatic backfill queue.

---

## 4. DSL & Meta-Schema Integration

### 4.1 Shipped primitive: `read_reference`

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
| `dataset` | yes | Validator requires a dataset name; current runtime resolves it from the injected `references` map. Unknown names yield an honest null rather than an authoring-time dataset-registry error. |
| `key` | yes | A canonical key, usually a resolver-supplied slot (§4.2). **Exact/learned match only** — no fuzzy logic inside the op; fuzziness lives in the resolver, keeping the op deterministic and trivially testable. |
| `quantity` / `measure` | no | Destination fields only; current validator/runtime do not consume or scale them. Seed values are already per typical serving. |
| `into` | yes | Bound to the raw entry plus `provenance` and `refKey`, or **null on a miss**. |

The current `log-meal` skill leaves `reads` empty; reference-dataset closure in skill metadata is a
destination and must not be treated as enforced disclosure today.

The closed compute set includes **`mul`** and **`div`**, although `log-meal` does not use them for
portion scaling.

### 4.2 The resolver seam (Spec 03 §6 gains a sibling)

No reference resolver is wired into NLU. The `food` slot remains raw text and `log-meal` passes it
directly to exact `read_reference`. `ReferenceStore.resolve` is the candidate local resolver but is
not a Session/orchestrator dependency; Tier 2 does not exist.

### 4.3 Current `log-meal` seed skill

The checked-in skill is simpler than the historical sketch below: inputs are `food` and optional
`mealType`; it looks up `food`, copies only `kcal`, writes `reference` provenance on a hit, and
writes no calories with `user` provenance on a miss. Quantity, measure, user-supplied calorie
precedence, macro copying, and dataset version are not implemented. The sketch is retained only as
a possible evolution:

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

The current meal schema stores optional `kcal` and `provenance`; it does not store a dataset
version or distinguish seed data that was itself model-estimated. “Calories today” aggregates
captured values at query time. Versioned source metadata and an `≈` treatment remain destinations.

---

## 5. Worked Trace — "I ate mac and cheese"

**Known food (steady state — zero model calls):**
1. **Route:** corpus fast-path matches the learned `log-meal` template; slots `{itemText: "mac and cheese"}`. Free, local (Spec 03 §5).
2. **Resolve skill:** `read_reference` exact-matches the canonical key `mac and cheese` (aliases
   include “macaroni and cheese” and “mac n cheese”). Free, local, deterministic.
3. **Write:** the current typical-serving entry is 1 cup / 200 g / 390 kcal; `log-meal` writes
   `{kcal: 390, provenance: "reference"}`.
4. **Act-then-describe:** *“Logged mac and cheese — about 390 calories.”* The calorie-total skill
   sums captured `kcal` values at query time.

**Cloud calls: zero.** The current lookup never makes a network call and covers its 403-entry seed.

**Destination example — unknown food with future keyed normalization:**
Tiers 0–1 miss → one Haiku normalize call (phrase + candidates) → no candidate fits → returns an estimated entry → cached to the learned store → meal written with `calories: ≈520, caloriesSource: "estimate"` → *"Logged khachapuri — roughly 520 kcal, my estimate."* Every future khachapuri is a Tier-0 hit. Cost: ~$0.0005, once.

**Current unknown-food behavior — zero calls, zero pretending:** exact lookup misses → meal written
with no calories → *“Logged khachapuri — I don't have calorie data for that, so no estimate.”*
There is no backfill queue.

---

## 6. The Hard Parts, Honestly

### 6.1 Name normalization is the actual product
Food language is idiomatic, multilingual, and personal ("mac and cheese" / "kraft dinner" / "the orange pasta"). The three-tier resolver is the best available shape — curated aliases catch the head, embeddings catch paraphrase, the model catches the tail once — but **resolution precision is a make-or-break metric exactly like the corpus learning rate** (research §7.1 caveat), and it must be measured in beta, not assumed. The mitigations are structural: Tier 1 is precision-biased (§3.2); every figure carries provenance; a spoken correction relearns the alias (the same correct-and-learn loop as NLU, P2.1).

### 6.2 Portions dominate the error bar
"A bowl" is 200–400 g; a default serving can be off ~2×. No dataset fixes this. The current
`read_reference` path performs no quantity/measure scaling and the meal skill uses the matched
entry's fixed calorie value, so it must not imply portion precision. Household measures, serving
scaling, and explicit `≈` presentation are destinations. The product posture remains
**trend-grade, not clinical-grade**, and the Layer-1 safety floor continues to hard-block punitive
calorie framing (Spec 02 §7.6).

### 6.3 Recipe decomposition — refuse the rabbit hole
Decomposing "mac and cheese" → ingredients → sum is combinatorially open-ended (whose recipe? what proportions?) and strictly worse than the alternative: **FNDDS already publishes composed dishes as consumed, with measured nutrients** (§2.2). We ship dishes as atoms. Multi-item utterances ("oatmeal and coffee") are N lookups + the existing multi-write idiom (Spec 02 §9.3), not decomposition. True homemade-recipe modeling ("my lasagna") is deferred — expressible later as a learned entry the user dictates once ("my lasagna is about 600 a slice" → `source: "user"` entry), which needs no new machinery.

### 6.4 The tail is permanent
The shipped seed has **403 entries** and no measured coverage claim. Branded items, restaurant
meals, regional dishes, and personal shorthand remain a long tail. Exact misses currently take the
honest local path: log the meal with no calorie value. The fuzzy resolver and normalize/cache tiers
described in §3 remain candidate mechanisms, but neither is wired into production and no “80%”
coverage claim has been validated.

### 6.5 Maintenance
One offline curation pipeline (FDC → our format), rerun opportunistically per release. No server, no live updates, no license renewals. The realistic maintenance risk is scope creep (§8.3), not data rot (§2.3).

---

## 7. Proposed Cost & Privacy Deltas (not current behavior)

- **Current state:** no reference-normalization cloud call exists, and Spec 08 must not list one as
  active egress.
- **Required before any future implementation:** add a typed
  `normalizeReference(dataset, phrase, candidates)` seam, consent/cost guard, and this egress row:

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

## 9. Current Scope and Destinations

**Shipped:** `ReferenceStore`, a 403-entry model-estimated nutrition seed, exact normalized
key/alias lookup, component-tested feature-hash `resolve`, `read_reference`, `mul`/`div`, the
`log-meal` integration, calorie totals, and honest misses.

**Not shipped:** USDA verification/versioning, a units dataset, production fuzzy resolution,
quantity/measure scaling, learned mappings, cloud normalization/backfill, source display in
Settings, METs, user recipes, and estimate-specific UI.

---

## 10. Decision Record

### Resolved

- **D1 — Build it, scoped.** One nutrition dataset and one deterministic read op are current. Units
  and normalize-once fallback are destinations, not shipped scope.
- **D2 — Reference data is seeded app content.** It is bundled and copied to `reference/` under the
  chosen data root, where a provider-backed root can sync it. It is not a type or user record.
- **D3 — One production exact-match op; optional fuzzy component.** `read_reference` performs exact
  lookup only and no measure scaling. `ReferenceStore.resolve` is separately implemented/tested but
  not wired to the meal flow. `mul`/`div` are shipped.
- **D4 — Dishes are atoms; no recipe decomposition.** The current seed includes typical composite
  dishes as single entries. FNDDS as-consumed data is the verification destination. *(§6.3.)*
- **D5 — Current provenance is `reference` on hits and `user` on misses.** Captured values freeze,
  but dataset versioning and estimate-specific presentation are not implemented.
- **D6 — No model normalization exists.** The one-use/cache/egress rules in §§3.3 and 7 govern any
  future implementation.
- **D7 — Trend-grade, said plainly.** Portion ambiguity bounds accuracy at roughly ±30–50%; the product claim is trends and totals, never clinical precision; the Layer-1 floor on punitive framing is unchanged and upstream of everything here. *(§6.2.)*
- **D8 — Closed injected dataset map with an admission rule** (stable, licensed, bounded head,
  consuming surface, small). Current bootstrap seeds nutrition only and preserves an existing local
  file rather than overwriting it on every release. *(§8.)*

### Open

- **Q1 — Coverage validation.** Measure exact-hit and honest-miss rates for the current 403-entry
  seed before resizing it or wiring fuzzy resolution; no coverage percentage is assumed.
- **Q2 — Resolution-precision bar.** Set the Tier-1 acceptance threshold/margin empirically (a small eval of food-phrase → key pairs, in the Spec 09 harness style); decide the false-accept budget. A mis-mapped food is this spec's worst failure — the eval gates shipping Tier 1, the way the `G-20` eval gated the local router.
- **Q3 — Quantity grammar scope.** v1 parses `{number} {measure}` ("two bowls"); decide how far the deterministic quantity resolver goes (fractions, "half a", grams/ounces) before it becomes the date-resolver's messier sibling — and whether it merges with the existing quantity resolution in Spec 03 §5's slot machinery.
- **Q4 — Learned-entry hygiene.** Whether the weekly consolidation pass (Spec 01 §6.2) should also triage learned reference entries (merge near-duplicate aliases, flag never-used estimates), and whether a learned *estimate* should be upgradeable to a shipped key when a later dataset version covers it.
- **Q5 — Backfill UX.** Where the "N meals are missing calories" affordance lives (AttentionSurface vs the tracker home) and whether backfill may batch multiple queued phrases into one normalize call.
- **Q6 — Cross-spec landings.** On build: the Spec 08 §5.5 row + D1 amendment (§7), the Spec 02 §3 op/fn/validator additions, the Spec 03 §6 resolver sibling, the Spec 07 §5 `≈` treatment, and Spec 09 contracts (op determinism; resolver precision eval; the "no derived stat without provenance" invariant). Recorded here so this spec, not tribal memory, is the checklist.
