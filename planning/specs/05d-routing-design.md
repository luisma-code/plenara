# Spec 05d — Routing Layer Redesign: A Slate of Candidate Architectures

**Status:** v1.0 — July 2026 — clean-slate design by Claude Fable 5, commissioned after the measured failure of the current router (findings §11 local-model NO-GO; findings §12 retrieval-router measurement).
**Inputs:** `research/spec-05a-phase3/findings.md` §§11–12; `05c-fable-review.md` (F-1, D-1, D-2); Spec 03 §5/§7.3; Spec 05 §3; research doc §2.1/§7; the 05a-rig (`dataset.json`, `eval_retrieval.py`, `eval_routing.py`).
> **✅ EVALUATED (July 2026 — findings §13).** The E1–E5 experiments below were run on the rig. **Adopted:** `R1` multi-vector + `R2` synthetic anchors (held-out 80% top-1 / 96% recall@5), `R8` Haiku full-inventory for online cold-start (94%), corpus learning (friction 20%→3%, exact/near-exact suffices). **Rejected:** `R3` the act-type gate — **overfit** (held-out −15 pts, gated the correct skill out of 28% of cases). **Deferred/evidence-gated:** `R9b` soft corpus (marginal + false-positive risk), `R4`–`R7`. **Make-or-break unknown:** real per-user phrasing-reuse (offline/free). The verdicts are in findings §13; the slate below stands as the design record.

**This is a design document, not a spec edit.** Nothing here is decided; each candidate carries a test protocol against the existing rig, and §7 ranks which experiments to run first. Small feasibility probes were run on the rig to sanity-check premises (~$0.02 total Claude spend); probe numbers are clearly marked as *probes*, with their limitations stated (§8). No existing file was modified; the only new rig artifact is the throwaway `harness/probe_05d.py` and its cached outputs.

---

## 0. Executive summary

The measured record says: no on-device generative 1–3B model routes (≤49%), single-vector retrieval doesn't route (40–47% top-1, recall@5 ~80%), Haiku routes well (86%) but only when handed a candidate set containing the right answer, and the corpus fast-path routes deterministically but only *after* the user teaches it. Cold-start is therefore clarify-heavy, and the product vision ("within a few weeks the app rarely asks") hangs entirely on the corpus-learning rate.

**The central claim of this document: the 40–47% number is not evidence that on-device retrieval routing is dead. It is evidence that the current retrieval *architecture* is wrong in three specific, fixable ways** — (1) it collapses each skill to a single concatenated embedding vector; (2) it anchors each skill with only ~3 generic hand-written phrases; (3) it is blind to the act-type structure (question vs. command vs. statement vs. "start tracking…") that deterministic code can read off an utterance nearly for free. A one-afternoon probe on the existing rig (§8) that fixes these three things — multi-vector max-sim scoring, ~20 Haiku-generated anchor phrases per skill (cost: **$0.001/skill, one-time**), and a rule-based act-type gate — moves cold-start routing on the same dataset from **47% → 80% top-1**, **91% group-level accuracy**, and **recall@5 from 80% → 100%**. The residual errors are almost entirely *within* the task/reminder twin group, where the dataset's own labels are fuzzy and a deterministic slot-signal tiebreak (recurrence present? explicit time? question form?) resolves the distinction in code.

If those probe numbers survive a proper held-out evaluation (§7, experiments E1–E3), the routing story changes qualitatively: cold-start stops being clarify-heavy *even offline*, the online Haiku path loses its recall@K ceiling (a 100%-recall candidate set restores Haiku's measured 86–96%), and the corpus's job shrinks from "teach the router everything" to "personalize an already-competent router" — which directly attacks the make-or-break learning-rate metric (§6).

Nine candidates are presented (§4), composed into three deployable stacks (§5), with a ranked experiment plan (§7). The cheapest three experiments cost roughly a day each and less than $1 of API spend combined.

---

## 1. The measured starting point (the box)

| Fact | Source |
|---|---|
| 1–3B generative on-device router: ≤49% routing, 0% meta-intent, dead calibration → **cut** | findings §11 |
| Single-vector retrieval (MiniLM/bge-small): 40–47% top-1, recall@5 76–80%, recall@8 91–93% | findings §12 |
| No margin threshold rescues single-vector top-1 (best ~60% acc-on-dispatched at ~50% clarify) | findings §12 |
| Haiku, given a candidate set containing the right answer: 86% overall, 96% class A, ~$0.0006, ~0.8 s p50 | findings §11 |
| Online end-to-end ceiling with real retrieval: recall@5 × Haiku ≈ 0.80 × 0.86 ≈ **~69%** | findings §12 |
| Corpus fast-path: ~deterministic on *learned* phrasings; useless before teaching | Spec 03 §5 |
| Error structure: near-neighbors dominate (`instantiate-template`→`log-*`, task/reminder twins, `search-records`→`log-*`, `recall`→`query-last`) | findings §12, `results/eval-retrieval.json` |
| Vision bar: "within a few weeks the app rarely asks" — delivered only by corpus learning under the current design | research §2.1, findings §12 |

A closer read of the 24 misroutes in `results/eval-retrieval.json` (bge-small, anchored) sharpens the diagnosis beyond "near-neighbors dominate":

- **11 of 24** are *act-type* confusions a grammar-school parse catches: a **question** routed to a **write** skill ("How many steps did I do this week?" → `log-walk`; "Find that note…" → `log-walk`; "What's Mia allergic to?" → `query-last-interaction` is query-vs-query, but `A-agg-*`, `A-streak-2`, `A-search-*`, `D-adv-*` are all interrogatives landing on capture skills).
- **5 of 24** are the task/reminder **twin group** (`create-task` ↔ `create-reminder` ↔ `create-recurring-reminder`) — where the *dataset's own labels* are debatable ("Remind me to email the accountant tomorrow" is labeled `create-task`), i.e. the distinction is not reliably in the utterance surface at all; it is in slot structure (recurrence shape present? explicit time?) and, partly, in convention.
- **3 of 24** are `instantiate-template` ("Start tracking my runs" → `log-run`) — an inchoative-aspect cue ("start/begin/set up/track my X" with no logged value) that rules read trivially.
- The remainder are genuine semantic near-misses (`add-contact-fact` vs `log-interaction` statives, `recall-contact-fact` vs `query-last-interaction`).

**Conclusion: the dominant error mass is structural, not semantic.** A small embedding model is being asked to encode distinctions (interrogative mood, aspect, slot-shape) that deterministic code extracts with near-perfect reliability. That is a *code-over-AI violation in reverse* — the design gave AI a job code should own. Every candidate below exploits this.

---

## 2. Constraints: respected, stretched, or challenged

| Constraint | Position |
|---|---|
| **Offline-capable free tier** | **Respected — and strengthened.** The probe suggests offline cold-start can reach ~80% top-1 / ~91% group-level without any cloud call, which would make the free/offline tier *actually good* rather than clarify-heavy. No candidate below requires the cloud at routing time; two use it at *authoring/ship* time (R2) or as an optional online upgrade (R8). |
| **BYOK Haiku for paid** | **Respected.** Haiku stays the residual disambiguator. R8 proposes *widening* its role for online users at cold-start (full-inventory routing), still BYOK. A shared-key free-tier routing allowance is **rejected**: it re-opens the cost story research §15.2 closed, for a problem R1–R4 appear to solve locally. |
| **Privacy: routing sends no user RECORD content to the cloud** | **Respected by every candidate.** What crosses the wire, ever: the live utterance (already true of the existing escalation path) and *capability metadata* (names/descriptions/slots) — which for authored types was already cloud-visible at authoring time. Anchor phrases are capability metadata, not records. Template-instantiated free-tier trackers never touch the cloud: their anchor packs ship in the template (R2). |
| **Apple 2.5.2 (capabilities are data, interpreter in binary)** | **Respected — and the anchor mechanism reinforces it.** Anchor phrases, act-type tables, tiebreak rules-as-config, ranker *weights*, and corpus entries are all human-readable data recombined by a fixed engine in the binary. The embedder (and optional reranker, R6) are models shipped *in the binary*, like the embedder already is. Nothing fetches executable logic. |
| **On-device latency ~1 s p50 / 1.5 s p95** | **Respected with headroom.** One bge-small embedding of a short utterance is tens of ms on CPU (llama.cpp, desktop); scoring a few thousand anchor vectors (100 skills × 40 anchors × 384-d) is sub-ms dot products; the act-type gate and slot probes are regex/table lookups. The only candidate that spends real time is the cross-encoder reranker (R6): ~8 pairs × ~20–40 ms ≈ 150–350 ms desktop CPU — still inside budget, needs a phone measurement. |
| **~80 MB on-device budget** | **Challenged as the wrong framing, then mostly respected anyway.** The probe shows the leverage is in *architecture* (anchors, scoring shape, gates), not embedder size — bge-small (36 MB) + anchors (~6 MB for 100 skills × 40 phrases) + optional 20–40 MB reranker fits under 80 MB. But the budget should be stated as a *priority ordering* (Usability > Minimalism, per CLAUDE.md), not a cliff: if E5/gte-base (~110 MB) buys 5+ points on the held-out set, take it. The budget defends nothing the priority order doesn't already govern. |
| **Act-then-describe + no-silent-failure** | **Respected, with one refinement argued for (R4): routing-equivalence groups.** Within the task/reminder twin group, a "misroute" produces a record the correction flow converts in one turn and the description makes transparent ("Added as a task for Thursday — say 'make it a reminder' if you want a ping"). Dispatching the group's best member on deterministic slot signals *is* act-then-describe; clarifying between twins the user themselves doesn't distinguish would be exactly the interrogative app the vision forbids. Cross-group ambiguity still clarifies. |
| **"Fully-offline free-tier COLD-START routing must be near-silent" (implicit in the vision)** | **This was the constraint findings §12 declared unmet and the design silently relaxed to "clarify-heavy is the honest floor." The slate's position: don't relax it yet.** R1–R4 are a direct attempt to meet it; only if E1–E3 fail should the spec accept clarify-heavy offline cold-start and lean on R8 (online cloud cold-start) as the compensation. |

---

## 3. What any candidate must produce (shared contract)

All candidates plug into the same seam Spec 03 §2.6 defines: `(transcript, NluContext) → Intent`. Internally, every candidate is a **scorer** over the capability inventory plus a **decision policy** (act / act-with-caveat / clarify / escalate / meta-intent / OOD). The decision policy axes from Spec 03 (corpus trust; retrieval similarity + margin; the rule-owned meta/OOD checks of §7.2) survive unchanged; candidates differ in *what score* feeds the policy and *how good* the top of the ranking is. This means candidates are largely composable (§5) and testable under one harness: rank the inventory for each utterance in `dataset.json` (and its successors, §7), report top-1 / group-top-1 / recall@K / per-class / margin-sweep — exactly the shape `eval_retrieval.py` already has.

**One metric change is proposed for all future evals** (rationale in R4): report **four-way turn outcomes** — *silent-correct* (top-1 right, high band), *caveat-correct* (right, moderate band), *clarify-resolvable* (right answer in the offered 2–3), *wrong-act* (acted on the wrong skill) — plus **group-level accuracy** where the task/reminder twins count as one routing target with a deterministic in-group tiebreak. Wrong-act is the metric to minimize; clarify-rate is the metric the vision caps; plain top-1 undercounts what act-then-describe + one-turn correction actually tolerates.

---

## 4. The candidate slate

### R1 — Multi-vector anchor retrieval (max-sim scoring)

**Mechanism.** Stop collapsing a skill to one embedding of `name + description + " ".join(examplePhrases)`. Instead embed **each anchor separately** — the name+description as one vector, each example phrase as its own vector — and score `score(skill) = max(cos(query, v) for v in skill.vectors)` (optionally mean-of-top-3 for robustness). The index becomes `{skillId → [vec, …]}`; query cost is unchanged (one utterance embedding + N·k dot products, trivially in-memory). This is the retrieval shape ColBERT-style late interaction uses, reduced to its cheapest form.

**Hypothesis.** Concatenating heterogeneous phrases into one vector produces a centroid that is *near nothing* — a known failure of single-vector document embeddings on multi-facet text. Max-sim lets any single phrasing anchor a match. Wins everywhere, but especially recall@K: **probe result (§8): recall@5 80% → 95.6%, recall@8 → 100%, with only the existing 3 hand phrases per skill; top-1 49% → 51%.** Recall is what caps the Haiku online path, so this alone lifts the online ceiling from ~69% toward Haiku's native 86–96%.

**Test protocol.** Trivial: `eval_retrieval.py` already embeds phrases; change the scoring loop (≈15 lines — see `probe_05d.py::score_config`). Metrics: top-1, recall@{3,5,8}, margin sweep, per-class, both embedders. No new data needed for the first pass; rerun on the held-out set (E2) when it exists.

**Tradeoffs.** None material. Index memory ×(k+1) per skill — a few MB at 100 skills. No latency change. No privacy/Apple/offline change. Margin semantics change slightly (margins between max-sims are tighter); `τ` thresholds must be re-fit.

**Risks.** Max-sim is brittle to one *bad* anchor (a single misleading phrase can hijack matches — mitigated by anchor linting, R2). Mean-of-top-k is the fallback. Score distributions per skill vary with anchor count, so a per-skill score normalization (e.g. z-score against the skill's anchor spread) may be needed before thresholds are comparable — measure in E1.

---

### R2 — Synthetic anchor generation (Claude-authored example phrases, at ship time and at authoring time)

**Mechanism.** Every capability carries **~20–40 generated anchor phrases**, not 3 hand-written ones. For the shipped seed skills and template trackers, anchors are generated once at build time (Haiku; probe cost **$0.0165 for 17 skills**) and ship in the binary/template pack — the offline free tier inherits them for free. For authored types/skills (paid), anchor generation is folded into the *existing* authoring call: the author model must emit `examplePhrases[20+]` varying register (terse fragments, full sentences, disfluencies, concrete slot values), and an **anchor linter** runs at authoring time: embed the new anchors, check confusability against every existing skill's anchors (max cross-skill sim, margin distribution), and force regeneration/differentiation when a new anchor lands inside another skill's territory. This resolves Fable review **D-2** (authored `examplePhrases` quality is uncontrolled and a badly-phrased authored type "never works by voice") with a mechanism instead of a hope.

**Hypothesis.** Retrieval quality is anchor-limited, not model-limited. 3 generic phrases cannot span a user's phrasing space; 20–40 diverse ones approximately can. **Probe: +18 points top-1 over the same scorer with 3 phrases (51% → 69% ungated; 67% → 80% gated), recall@5 → 97.8–100%.** Wins hardest at cold-start (this is *pre-teaching the corpus*, §6) and on class B/D-adv (terse and adversarial phrasings match some anchor). Generated anchors also give the OOD/meta boundary a real signal: with dense anchor coverage, a *novel-need* utterance's max-sim is depressed relative to covered utterances (probe: mean top-1 sim 0.776 real vs 0.679 none) — not yet a clean threshold, but a workable feature for the rule-owned §7.2 check.

**Test protocol.** Already probed end-to-end (`probe_05d.py`, `results/probe-synthetic-anchors.json`). Real evaluation needs: (a) the **held-out utterance set** (E2) — generated by a *different* model than the anchors (Sonnet/Opus) plus hand-written cases, so anchor-generator and test-generator biases don't collude; (b) the **near-neighbor stress library** (E3) — synthesize 40–60 plausible capabilities (expense tracker, plant watering, books, blood pressure, gratitude journal, car mileage…) with anchors, and measure degradation vs. the 17-skill floor, since more skills × more anchors = more collision surface; (c) an **anchor-linter prototype**: measure how often naive generation collides and whether lint-and-regenerate fixes it. Metrics: same as R1, plus per-skill anchor-collision stats.

**Tradeoffs.** Cost: negligible ($0.001/skill one-time; free-tier templates pre-paid at build time). Footprint: ~6 MB of vectors at 100 skills × 40 anchors (float32; halve with fp16). Privacy: authoring-time generation sends capability metadata only — already cloud-visible for authored types; shipped seeds are not user data at all. Apple: anchors are human-readable data in the skill file — *improves* auditability. Latency: none.

**Risks.** (1) Generated anchors encode Haiku's phrasing priors, not this user's — they raise the floor, they don't personalize (that stays the corpus's job, §6). (2) Anchor sprawl at 100+ skills could compress margins — exactly what E3 stresses. (3) The twin-group labels are fuzzy even to the generator (probe: Haiku wrote "remind me to call mom" as a `create-task` anchor — matching the dataset's own convention, but showing the distinction isn't surface-expressible; R4 owns that). (4) Free-tier users who *rename* template trackers drift from shipped anchors — the corpus write-back (§6) covers the drift.

---

### R3 — Deterministic act-type gate (factored routing: act-type × domain)

**Mechanism.** Before scoring, classify the utterance's **act type** with deterministic rules (later, optionally, a tiny linear classifier over the same embedding — see R5): `query` (interrogative mood: wh-front, aux-inversion, "find/pull up/search/remind me what"), `prospective` ("remind me to/about/every", "add … to my list", "I need to …", recurrence-fronted), `instantiate` (inchoative: "start/begin tracking", "make me a tracker", "I want to start …"), `capture` (declarative default). Every capability declares its act type in metadata (one enum field: `query-*`/`recall-*`/`search`/`show-streak` → query; `create-*` → prospective; `instantiate-template` → instantiate; `log-*`/`add-contact-fact` → capture). Routing scores only (hard gate) or preferentially (soft bonus, safer) the matching partition. The rule table is data in the binary (Apple-clean), in the same family as the §2.3 system-command pre-filter that already exists.

**Hypothesis.** §1's diagnosis: ~half the misroute mass is act-type confusion. Embeddings encode topic well and mood/aspect poorly; code reads mood/aspect nearly perfectly. Factoring the space also shrinks each decision to 1–5 candidates, widening margins. **Probe: +15.6 points over multi-vector alone (51% → 67%) and +11 on top of synthetic anchors (69% → 80%); zero cases where the gate excluded the correct skill on this dataset.** Wins on classes A (query-vs-log), D-adv (interrogative → search/query partition, which is also the **privacy boundary** — a personal-cue question can never misroute to a write), and E.

**Test protocol.** The probe rules live in `probe_05d.py::act_type` (~20 lines). **Honesty caveat: those rules were written while looking at the 57 test utterances — the probe number is optimistic by construction.** The real test is E2's held-out set with deliberate disfluencies ("um, remind me to, uh, call the plumber I guess, Thursday") and mood-camouflage cases ("I wonder when I last saw Marco" — interrogative semantics, declarative surface). Measure: gate-exclusion rate (correct skill outside the partition — the fatal error, since a hard gate turns it into a guaranteed misroute), top-1 with hard vs. soft gate, and per-act-type confusion. Ship-shape decision: **soft gate (score bonus λ) unless held-out gate-exclusion < 1%.**

**Tradeoffs.** Zero cost/latency/footprint/privacy impact. Adds one enum to capability metadata (authoring must set it; the anchor linter can sanity-check it — a `query` skill whose anchors are all declaratives is mis-tagged).

**Risks.** (1) Rule brittleness on disfluent/ASR-mangled speech — the reason for the soft-gate default and E2's disfluent set. (2) English-specific; a multilingual future re-implements the rule table per language (it is data, so that's contained). (3) Utterances that legitimately span types ("did I log my run this morning? if not add it") — compound-utterance handling (Spec 03 §2.7) owns that, not the gate.

---

### R4 — Slot-signal features and routing-equivalence groups (deterministic tiebreak in code)

**Mechanism.** Two coupled pieces. **(a) Speculative slot probes as routing features:** run the cheap deterministic extractors of Spec 03 §7.3.3 *before* routing commits — does the utterance contain a recurrence shape ("every second Tuesday")? an explicit clock time/date? a number+unit ("5k", "480 calories", "8 hours")? a known contact name? an interrogative? Each capability's `inputs` contract implies a compatibility signature; score candidates on slot-compatibility (a skill requiring `recurrence` gets a large bonus when an RRULE shape is present and a penalty when absent). **(b) Routing-equivalence groups:** declare the task/reminder twins (`create-task`/`create-reminder`/`create-recurring-reminder`) — and any future authored near-twins the anchor linter flags — a **group**: retrieval routes to the group; a deterministic in-group tiebreak picks the member (recurrence shape → recurring; explicit time + "remind" verb → reminder; else task); the description makes the choice transparent and the correction flow converts in one turn ("make it a reminder" is an update, not a reverse-and-redispatch — the records are convertible by design). Misrouting *within* a group is demoted from error to preference.

**Hypothesis.** After R1–R3, the probe's residual errors are: twins ×5 (all in-group; recurrence tiebreak alone fixes `A-recur-1` immediately), `recall-contact-fact` vs `query-last-interaction` ×2 (tiebreak: "when/how long since + person" → last-interaction; "what + person + attribute" → recall), and 2 genuine near-misses. **Probe group-level accuracy: 91.1%** with recall@5 = 100% — i.e. R4 converts most of the remaining top-1 gap into either correct dispatch or harmless in-group choice. This is code-over-AI applied to exactly the distinctions embeddings measurably cannot carry (findings §12: twins dragged even Haiku to 70% on class E).

**Test protocol.** Pure code on the rig: extend `probe_05d.py` with (a) regex/date-resolver-stub slot probes feeding a linear score adjustment, (b) group scoring + tiebreak; report the four-way turn outcomes of §3. Needs a small labeling addition to `dataset.json` successors: per-case *group-acceptable* answers and the slot-signature ground truth (recurrence present? explicit time?). New data: none beyond E2. Also specify + test the convertibility contract (task↔reminder record conversion as a one-turn update) at the trace level — that's a Spec 02/05 seam, flagged not designed here.

**Tradeoffs.** None in cost/latency/privacy/footprint. Design cost: the group + tiebreak tables are new capability metadata that authoring must maintain (the linter can propose groups when a new skill's anchors collide with an existing one's — turning the D-2 sprawl failure into a managed structure). Product cost: accepts that "task vs reminder" is sometimes the app's convention rather than the user's expressed intent — defended by the transparency caveat + one-turn conversion, consistent with act-then-describe.

**Risks.** (1) Group misuse: hiding *real* errors by over-grouping — guard: groups require record-convertibility, not just embedding proximity. (2) Tiebreak rules accrete — keep the table small, data-driven, and measured per E2. (3) The undo/correction contract must treat in-group conversion as an update (Spec 05 §3.3 already distinguishes same-skill slot corrections; extend to same-group).

---

### R5 — Learned lightweight ranker (learning-to-rank over deterministic features)

**Mechanism.** Replace the hand-set combination of R1–R4 signals with a **trained scoring function**: features per (utterance, candidate) = dense max-sim (R1/R2), BM25 lexical score, act-type match (R3), slot-compatibility vector (R4), corpus-neighbor similarity (§6), anchor-count-normalized margin. Model: logistic regression or a ~10-tree GBDT — hundreds of parameters, KBs, human-inspectable, shipped as *data* (weights in a JSON the fixed scorer in the binary consumes). Training data: the synthetic corpus (R2 anchors as positives + E2-style generated utterances), refreshed at build time; optionally fine-tuned on-device from the user's own corpus write-backs (a per-user LR fit over ~384+20 features is trivially on-device).

**Hypothesis.** Hand-tuned λ-bonuses and thresholds (R3's soft gate, R4's slot bonuses, the `τ` bands) interact; a learned combiner squeezes the last points and — more importantly — produces a **calibrated dispatch probability**, which the act/caveat/clarify policy currently lacks (every confidence signal measured so far was dead; a supervised probability over deterministic features is the first shot at a *live* one). Expected win: +3–8 points over hand-tuned R1–R4, and a defensible act/clarify operating curve.

**Test protocol.** Needs E2 (held-out) + E3 (stress library) first — training on synthetic and testing on the 57-case set that inspired the features would be circular. Build: a feature-extraction pass in the rig, scikit-learn LR/GBDT (already Python-side), report the §3 four-way outcomes and a reliability diagram (calibration curve) — the first candidate for which calibration is even measurable. New harness piece: `eval_ranker.py` with train/test split discipline.

**Tradeoffs.** Footprint/latency negligible. Complexity: a training pipeline enters the build; weights need versioning alongside the anchor packs. Apple: weights are data; scorer is fixed code — clean. Explainability drops slightly vs. pure rules (mitigate: LR with monotonic features, log per-feature contributions into the routing trace for the no-silent-failure surfaces).

**Risks.** Synthetic-to-real distribution gap (trained on model-generated utterances, deployed on one human's disfluent speech) — the on-device personalization pass and corpus features are the hedge. Overfitting the 17-skill floor — E3 gates it. This candidate should follow, not precede, the deterministic stack: if R1–R4 already clear the bar, R5 is a tuning pass, not a pillar.

---

### R6 — Tiny cross-encoder reranker over top-K (offline near-neighbor discriminator)

**Mechanism.** After retrieval produces top-K (K=5–8, now at ~100% recall per R1/R2), run a **cross-encoder**: a small encoder (MiniLM-L6-class, 20–40 MB; e.g. a ms-marco MiniLM cross-encoder checkpoint, or one distilled/fine-tuned on the synthetic corpus as (utterance, anchor-set) pairs) that reads *utterance and candidate surface jointly* and outputs a relevance score per pair. Rerank; dispatch policy unchanged. This is the standard retrieve-then-rerank pattern, sized for a phone.

**Hypothesis.** Bi-encoder geometry fundamentally cannot separate pairs whose surfaces share all content words ("note that Ana starts her new job Monday" — capture-about-person vs. reminder); joint attention can. Fills the same slot Haiku fills online (discriminate among ~5 candidates — the task Haiku does at 96% class A) but **offline and free**. Expected win: the residual cross-group near-misses after R1–R4 (`add-contact-fact` vs `log-interaction`, `recall` vs `query-last`), i.e. the last ~5–10 points, without cloud. If it works, the offline tier approaches the online tier and Haiku escalation becomes rare even at cold-start.

**Test protocol.** Rig extension: `pip install sentence-transformers` in the venv (CPU is fine for measurement), rerank the R1/R2 top-5 on E2/E3, report §3 outcomes + per-pair latency. Also test the *distilled* variant: fine-tune the cross-encoder on synthetic pairs (positives from anchors, hard negatives from within-top-K wrong candidates — the collisions E3 produces are exactly the needed hard negatives). Deployment feasibility (ONNX/CoreML export, phone latency) is a later spike; the rig answers "does joint scoring buy accuracy" first.

**Tradeoffs.** +20–40 MB footprint (fits budget with bge-small). +150–350 ms desktop CPU for K=8 (phone TBD — the p95 risk item). Offline, private, Apple-clean (model in binary). Adds a second model to maintain.

**Risks.** Off-the-shelf ms-marco rerankers are tuned for web passages, not voice-intent — may need the distillation pass to shine, which adds pipeline weight. Latency on older phones. Diminishing returns if R4's tiebreaks already claim the same errors — run E4 *after* E1–E3 so the marginal win is measured against the deterministic stack, not against the weak baseline.

---

### R7 — Fine-tuned task-aware embedder (contrastive, SetFit-style)

**Mechanism.** Fine-tune the shipped embedder itself (bge-small / e5-small) with a contrastive objective on the synthetic corpus: pull utterance-paraphrases of the same capability together, push near-neighbor capabilities apart (hard negatives from E3 collisions); optionally multi-task with act-type prediction so mood/aspect enters the geometry. One-time at build; the fine-tuned weights ship as the embedder. Anchors/corpus mechanics unchanged on top.

**Hypothesis.** The base embedder was trained for generic web similarity; intent routing wants a space where "How many steps this week?" is *far* from "log 10,000 steps" despite sharing every content word. Contrastive fine-tuning on exactly our confusion structure reshapes the space instead of compensating downstream. Literature on intent-detection fine-tunes suggests large gains are available; expected win: raises *every* downstream number (retrieval, gate margins, OOD separation) a few points, and may substitute for R6.

**Test protocol.** Heaviest experiment on the slate: build a training pipeline (sentence-transformers, CPU/small-GPU, hours), re-export to GGUF for the rig's llama-server, rerun the full E1–E3 battery with the fine-tuned checkpoint as a drop-in embedder swap. Gate it on E1–E3 results: only worth running if the deterministic stack plateaus below the bar.

**Tradeoffs.** No runtime cost at all (same model size/latency). Build-time complexity: a training pipeline + eval discipline against catastrophic drift (the same embedder serves record-content search F-12 — either accept task-drift there or ship it as a second 36 MB model, which strains the budget with R6 present). New authored types arrive *after* training — the anchor mechanism (R2) must carry them in the fine-tuned space, so E3's authored-type stress must be re-run post-fine-tune.

**Risks.** Overfit to synthetic phrasing style; the dual-use conflict with content search; maintenance (retrain when the seed library changes materially). Medium-term candidate, not a first mover.

---

### R8 — Haiku full-inventory cold-start routing (online users; constraint adjustment)

**Mechanism.** For **online + BYOK** users, drop the top-K truncation for the cloud path at cold-start: send Haiku the utterance + the **entire capability inventory** (compact one-line-per-skill form keyed by id — 100 skills ≈ 2–3 K tokens, trivially within Haiku's context; prompt-cache the inventory block so marginal cost is pennies per hundred calls), enum-constrained to `{ids} ∪ {none}`. Invoke it not only on genuine ties but on any *novel* phrasing below the act band while the corpus is young; every uncorrected result writes back a corpus entry (§6), so the Haiku phase self-extinguishes.

**Hypothesis.** The ~69% online ceiling was an artifact of recall@5 × Haiku — remove the truncation and Haiku's measured 86% (96% class A) *is* the online cold-start number, independent of local retrieval quality. With R1/R2 pushing recall@5 to ~100%, top-K vs full-inventory converge; full-inventory is the robustness backstop for the scales where E3 shows recall decaying. This reframes cold-start for the (majority) online-paid case: **the teaching period is Haiku-assisted, and the corpus graduates phrasings out of it** — the "within a few weeks" promise is delivered by Haiku's accuracy during the weeks the corpus needs to learn.

**Test protocol.** Cheap: one rig run (`eval_routing.py` variant) giving Haiku the full 17-skill inventory (and E3's 60-skill inventory) instead of per-case candidates — ~57 calls ≈ $0.05. Measure routing acc, class C (does full inventory *improve* novel-need detection? Haiku saw 33% on class C with truncated candidate sets — with the whole inventory visible, "none of these" is better grounded), latency with a cached prefix, cost per call. New data: none.

**Tradeoffs.** Cost: ~$0.0006–0.002/call, only during the teaching weeks, only for novel phrasings — self-limiting; the §3.5 rate-limit guard stands. Latency: ~0.8–1.2 s — at the p95 edge, acceptable for *novel* utterances (repeat ones hit the corpus). Privacy: utterance + capability metadata; **no record content** — unchanged envelope, stated honestly in the privacy surface. Offline/free tier: unaffected (falls back to the local stack). Apple: no change.

**Risks.** (1) It can mask local-stack weakness — keep the local stack's numbers gated separately (E1–E3 run offline-only). (2) Class-E twins drag Haiku too (70%) — R4's group semantics apply to Haiku's answer as well. (3) Dependence: a user habituated to Haiku-grade cold-start feels regressions when offline; the transparency caveat should not differ between paths.

---

### R9 — Corpus pre-seeding and soft-corpus generalization (the learning-rate levers)

**Mechanism.** Two changes to the corpus mechanism itself (Spec 03 §5), orthogonal to the scorer. **(a) Pre-seeded corpus:** ship Lane 1 pre-populated with slot-abstracted **templates** generated at build time from the anchor corpus (R2 anchors run through the same normalizer/templatizer the write-back path uses; dedup; mark `source: preseeded`, initial trust just below `θ_corpus_act` so they act with the transparency caveat until confirmed). The user starts with thousands of learned-equivalent phrasings instead of zero. **(b) Soft-corpus generalization:** on every write-back (confirmation *or* correction), also add the utterance's **embedding** to the routed skill's anchor set (a per-user anchor overlay, device-local + synced as data). One correction then improves not just the exact template but the *neighborhood* of phrasings around it — the learning rate becomes multiplicative instead of additive. (A corrected-away skill gets the embedding as a *negative* anchor: a small penalty term in scoring.)

**Hypothesis.** Findings §12 made the corpus-learning **rate** the make-or-break metric. Today the corpus learns one exact template per interaction. (a) collapses the teaching period for common phrasings to zero; (b) makes each genuine teaching interaction count for many future utterances. Combined with R2 (which is (a) at the *retrieval* layer), the question "how many weeks until it rarely asks" becomes "how many corrections until the user's *idiolect divergence* from the synthetic priors is absorbed" — a much smaller quantity. Wins: cold-start and steady-state slope; offline-first (all local).

**Test protocol.** This is the **learning-curve simulator** (E5), the harness extension findings §12 already demanded: generate per-user utterance *streams* (300–500 turns: ~40 distinct intents, Zipf-distributed frequency, phrasing variation within intent, a persona-consistent idiolect, %5 disfluency), replay through the full stack with corpus write-back simulated per Spec 03 §2.7 (uncorrected → boost; simulated correction on wrong-act), and plot **clarify-rate and wrong-act-rate per session index**. Headline metrics: *turns-to-90%-silent-correct* and *corrections-per-learned-pattern*, compared across {no preseed, preseed}, {exact-template only, +soft generalization}, {R2 anchors on/off}. Also verify the negative-anchor mechanic doesn't oscillate. New data: the stream generator (Sonnet-written personas + streams, ~$1–2); new harness: `eval_learning_curve.py`.

**Tradeoffs.** Pre-seeded templates inflate the flow table (thousands of entries — fine; it's a hash/trie lookup) and interact with G-36's sync-format concern (per-entry or per-device files become more clearly right). Soft anchors grow per-user vector state (~KBs); they are earned user data → synced as vectors are *not* portable across embedder versions, so sync the *utterance text* + metadata and re-embed per device (consistent with Spec 03 §3.2's device-local index rule). Privacy: per-user anchors contain utterance text — they are user data, stored like corpus entries already are (template text in the synced root; the §5.6 sensitive-skill exclusions apply unchanged).

**Risks.** (1) Pre-seeded templates that are *wrong for this user* start acting-with-caveat immediately — initial trust must sit in the caveat band, never the silent band, and a single correction must kill the preseed (existing §4.2 mechanics suffice). (2) Soft anchors drift a skill's region over time — cap overlay size, decay like corpus entries. (3) Simulator realism: a synthetic stream can flatter the curve; treat E5 as comparative (mechanism A vs B), not absolute, and confirm with Phase-0 dogfooding telemetry (the spike findings §12 already mandates).

---

## 5. Composite stacks (how the candidates assemble)

The candidates are not rivals; they occupy different slots. Three deployable compositions, in ascending ambition:

**S1 — Deterministic-first local stack (the new baseline): R1 + R2 + R3 + R4 + R9, corpus first, Haiku residual.**
Pipeline: pre-filter (system commands/anaphora, unchanged) → corpus fast-path (now pre-seeded, with soft-anchor overlay) → multi-vector anchored retrieval over act-type-gated candidates with slot-compat scoring → group-aware dispatch policy (act / caveat / clarify by re-fit `τ` bands) → meta/OOD rule check (unchanged §7.2, now with a usable absolute-sim signal) → Haiku residual on genuine ties (online+BYOK) / clarify (offline). *Everything in S1 is code + data + the embedder already in the budget.* Probe-level expectation: ~80% top-1, ~91% group, 100% recall@5 cold, offline — to be confirmed on E2/E3.

**S2 — Learned local stack: S1 + R5 (ranker) and/or R6 (reranker), R7 if plateaued.**
Adds the trained combiner for calibrated dispatch probabilities and the cross-encoder for the last near-neighbor points. Only justified by E2/E3 numbers showing S1 below the bar (or a calibration need the τ-bands can't meet).

**S3 — Cloud-assisted cold-start: S1/S2 + R8.**
Online+BYOK users route novel phrasings through full-inventory Haiku during the teaching period; the corpus graduates them out. The offline/free tier runs pure S1/S2. This is the belt-and-suspenders composition: even if E2 halves the probe gains, online cold-start holds at Haiku-grade (~86–96% class A) while R9 shortens the period in which that matters.

**Recommended posture:** build the rig evidence for S1 first (it is the cheapest and changes the most), hold S3 as the low-risk product answer for v1 online users, and let S2 be data-driven.

---

## 6. The make-or-break metric: corpus-learning rate

Findings §12's sharpest sentence stands: *nothing* in the old design routes novel phrasings well, so the vision lives or dies on how fast the corpus converts novel → learned. This slate attacks the metric from three directions:

1. **Shrink what must be learned (R2, R9a).** Synthetic anchors and a pre-seeded corpus mean the app arrives *pre-taught* on the distributional bulk of phrasings; the corpus's remaining job is the user's personal divergence from those priors. The probe's cold-start 80%/91% is, in corpus terms, a starting point the old design needed weeks of corrections to reach.
2. **Raise the value of each lesson (R9b).** Soft-corpus generalization makes one correction teach a neighborhood, not a string. This changes the curve's *shape* (multiplicative), not just its intercept.
3. **Make the teaching period painless where possible (R8).** For online users, the residual teaching happens behind Haiku-grade routing with implicit confirmations doing the teaching — the user experiences competence, not interrogation, while the corpus fills.

**How to measure the curve (E5, the new harness the rig needs most):** simulate user-months. Persona-conditioned utterance streams (300–500 turns each, ~10 personas: distinct idiolects, Zipf-distributed intent frequency, 5–10% disfluency, occasional novel-need turns), replayed through a candidate stack with the Spec 03 §2.7 write-back loop simulated (uncorrected → boost, wrong-act → correction event + corpus zero/insert, clarify → selection). Plot per-session: silent-correct %, caveat %, clarify %, wrong-act %. **Headline numbers: turns-to-90%-silent-correct; corrections-per-learned-pattern; wrong-act rate in week 1.** Compare stacks and ablations (preseed on/off; soft-anchors on/off; anchors 3 vs 20 vs 40). The absolute values will flatter (synthetic streams are cleaner than life); the *comparisons* are the decision data, and the Phase-0 dogfood spike then anchors the absolute scale with real usage.

**Does any candidate shortcut the teaching period outright?** R2+R9a come closest: they *are* the teaching period, executed at build/authoring time from model priors instead of at run time from the user's patience. R8 shortcuts the *experience* of the period without shortening the corpus's calendar. R9b shortens the tail. If E5 shows turns-to-90% dropping from hundreds to a few dozen with preseed+soft-anchors, the research §2.1 promise is re-grounded in mechanism rather than hope — that is the single most valuable measurement this slate can buy.

---

## 7. Ranked experiment plan — test these first

Ordered by signal-per-cost; each row states what it de-risks. E1 is partially done (the probe); its formalization is still step one because the probe has known optimism (rule leakage, 57-case set, anchor/test same-era generation).

| # | Experiment | Builds on | Build effort | Spend | What it decides |
|---|---|---|---|---|---|
| **E1** | **Formalize the probe** into `eval_routing2.py`: multi-vector scoring (R1), anchor packs (R2), soft/hard act gate (R3), slot-compat + groups + four-way outcomes (R4), τ re-fit + per-skill score normalization. Run both embedders. | probe_05d.py | ~1 day | <$0.05 | Confirms/denies the 47→80 jump under clean harness discipline; picks embedder; sets the S1 baseline numbers. |
| **E2** | **Held-out utterance set** (~200 cases): Sonnet/Opus-generated paraphrases + hand-written + a **disfluent/ASR-noise subset** + mood-camouflage cases; labels include group-acceptable sets + slot signatures. Rerun E1 on it. | E1 | ~1 day | ~$1 | Kills or keeps the probe's optimism — especially the act-gate (leakage risk) and the anchors' generalization. **The go/no-go for S1.** |
| **E3** | **Near-neighbor stress library**: synthesize 40–60 plausible capabilities + anchors (incl. deliberately-confusable authored types); rerun E1/E2 at 60 skills; prototype the **anchor linter** and measure collision → lint → regenerate. | E1 | ~1 day | ~$0.50 | Whether the approach scales past the 17-skill floor (Fable D-2's sprawl risk); whether linting works. |
| **E4** | **Haiku full-inventory routing** (R8): 57-case + E2 + E3 inventories, prompt-cached, enum-constrained; measure acc/class-C/latency/cost. | none | ~½ day | ~$0.20 | The online cold-start ceiling with no recall cap; whether full inventory improves novel-need detection. Cheap enough to run alongside E1. |
| **E5** | **Learning-curve simulator** (R9): persona streams + write-back replay + curve plots; ablate preseed/soft-anchors/anchor-count. | E1–E3 | ~2–3 days | ~$2 | **The make-or-break metric itself.** Decides R9's mechanisms and produces the number the vision depends on. |
| **E6** | **Cross-encoder reranker** (R6): off-the-shelf then distilled, over S1's top-5 on E2/E3; CPU latency measured. | E2, E3 | ~1–2 days | ~$0 | Whether offline can close the last gap to online; feeds the S2 decision. |
| **E7** | **Learned ranker** (R5): feature extraction + LR/GBDT + calibration curves, trained synthetic / tested E2. | E2, E3 | ~2 days | ~$0 | Calibrated dispatch probability; marginal accuracy over hand-tuned S1. |
| **E8** | **Fine-tuned embedder** (R7): contrastive pipeline, GGUF re-export, full battery rerun. | E1–E3 plateau | ~1 week | GPU-hours | Only if S1/S2 plateau below the bar. |

Also carried from the prior record, unchanged in priority: the free-form **text-slot extractor floor** on disfluent speech (05c F-1's unmeasured heuristic) should ride along in E2's disfluent subset — it shares the dataset build.

**Decision gates.** After E2: if S1 ≥ ~75% top-1 / ~90% group / recall@5 ≥ 98% held-out, adopt S1 as the routing baseline and proceed to E5 (learning curve) before any S2 work. After E3: if 60-skill degradation > ~10 points, prioritize E6/E7 (discriminators) and the anchor linter. After E4: fix the online cold-start posture (R8 in/out of v1). E5's output rewrites research §2.1's promise as a measured curve.

---

## 8. Preliminary probe results (full disclosure)

Run 2026-07-06 on the existing rig: bge-small-en-v1.5-q8 via `llama-server --embedding` (:8090), `dataset.json` (57 cases; 45 real-skill), script `harness/probe_05d.py`, anchors cached in `results/probe-synthetic-anchors.json`, summary in `results/probe-05d.json`. Haiku anchor generation: 17 skills × 20 phrases, **$0.0165 total**; zero verbatim overlap with test utterances (checked).

| Config | top-1 | group | recall@5 | recall@8 | per-class (A/B/D/E correct) |
|---|---|---|---|---|---|
| P0 single-vector + 3 phrases (≈ shipped design, replication) | 48.9% | 57.8% | 80.0% | 93.3% | 16/26 · 3/7 · 0/4 · 3/8 |
| P1 + multi-vector max-sim (R1) | 51.1% | 60.0% | **95.6%** | **100%** | 16/26 · 1/7 · 3/4 · 3/8 |
| P2 + act-type gate (R3) | 66.7% | 75.6% | 100% | 100% | 21/26 · 2/7 · 3/4 · 4/8 |
| P4 multi-vector + 20 synthetic anchors (R2) | 68.9% | 80.0% | 97.8% | 100% | 21/26 · 4/7 · 3/4 · 3/8 |
| **P5 anchors + gate (R1+R2+R3)** | **80.0%** | **91.1%** | **100%** | 100% | 23/26 · 5/7 · 3/4 · 5/8 |
| P6 P5 + BM25 RRF fusion | 75.6% | 86.7% | 97.8% | 100% | (BM25 fusion *hurt* at this anchor density — lexical overlap is already inside the anchors; drop or re-weight) |

P5's nine residual misroutes: five are within the task/reminder twin group (four resolved by R4's group semantics, one — `A-recur-1` — by the recurrence tiebreak alone); two are `recall-contact-fact` ↔ `query-last-interaction` (R4 tiebreak targets); two are genuine near-misses (`B-fact-3`, `D-adv-4`), both with the right answer at rank 2 — i.e. inside any clarify or Haiku-residual surface. Mean top-1 similarity separation for none-vs-real cases improved from 0.62/0.64 to 0.68/0.78 — not yet a clean OOD threshold, but a live signal where there was none.

**Why these numbers must not be taken at face value:** (1) the act-type rules were written with the test set visible — E2's held-out set exists to price that in; (2) n=45 real-skill cases; (3) 17-skill floor; (4) anchors and test set are both "reasonable 2026 model English" — a real user's idiolect is the gap R9/E5 measure; (5) group accuracy assumes the record-convertibility contract R4 proposes, which is designed but not yet specced. They are a *premise check*, and the premise — the error mass is structural and fixable with data + code, not a bigger model — checks out strongly.

---

## 9. Risk register (slate-level)

| Risk | Hit | Mitigation |
|---|---|---|
| Probe gains halve on held-out/disfluent speech | S1's bar | E2 first; soft gate; S3 (Haiku cold-start) as the online floor either way |
| Anchor sprawl at 100+ skills compresses margins | R2/R9 | E3 stress + anchor linter; groups absorb convertible collisions; R6/R7 if geometry saturates |
| Act-gate hard-excludes the right skill on odd phrasing | R3 | Soft-gate default; hard gate only if E2 exclusion <1%; margin-based fallback to ungated scoring |
| Groups paper over real errors | R4 | Group membership requires record-convertibility + one-turn conversion; wrong-act metric tracked cross- and in-group separately |
| Pre-seeded corpus acts wrongly for an atypical user | R9a | Preseeds capped at caveat band; one correction kills a preseed; E5 ablation |
| Two-model footprint (embedder + reranker) squeezes budget | R6 | Only via S2 on evidence; budget argued as priority-order, not cliff (§2) |
| Simulator flatters the learning curve | E5 | Comparative use only; Phase-0 dogfood anchors absolutes |
| Twin-label fuzziness contaminates all evals | all | E2 relabels with group-acceptable sets; the metric change (§3) is part of the fix |

---

## 10. What this means for the specs (pointers only — no edits made)

If E1–E3 confirm: Spec 03 §3.2 (index shape → multi-vector), §3.3 (scoring → max-sim + gate + slot-compat), §7.3.4 (retrieval's role upgraded from "candidate generator only" back toward router-with-groups), §5 (corpus preseed + soft-anchor overlay; strengthens the G-36 per-entry-file argument); Spec 01/02 authoring (anchor generation + linter as authoring obligations; act-type + group metadata on skills); Spec 05 §3 (in-group conversion as an update-class correction); research §2.1 (the promise restated over the E5 curve). The metric contract of §3 (four-way outcomes, group accuracy) should become the standard reporting shape for every future routing eval.
