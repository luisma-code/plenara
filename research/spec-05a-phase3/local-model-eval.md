# Spec 05a — Local-model trust evaluation (G-20 go/no-go)

**Date:** 2026-07-05 · **Status:** complete — decision input for Luis (this is *data + a recommendation*, not the decision).
**Question (G-20 / Spec 05b §3):** is the small on-device generative model trustworthy for its *narrowed* job — discriminate among ≤5 already-retrieved candidates and extract slots for **known** capabilities — measured against a bar set in advance? Pass → it routes known capabilities (novel/OOD owned by retrieval + rules + Haiku). Fail → cut it from the routing path (deterministic/rule where a code path exists, Haiku fallback where not).

**Verdict up front: NO-GO.** No small model (Qwen2.5-1.5B, Llama-3.2-3B, Gemma-2-2B, Phi-3.5-mini) meets **any** of the three acceptance bars — not routing accuracy, not slot-exact, not p95 latency — in either free-form or constrained decoding. The best small model tops out at **81% on the cleanest class (A)** and **~49% overall**; a hypothetical *perfect 4-model oracle ensemble* still only reaches **70%**. Confidence is uncalibrated (separation ≈ 0), so the model cannot even self-gate. Constrained decoding changed routing accuracy by **0 points**. **Haiku 4.5 (cloud reference) clears the core classes** (A 96%, B 100%, D 100%; 86% overall) at **~$0.0006/call**. → **Cut the on-device generative model as a trusted autonomous router;** route known capabilities via the corpus fast-path + retrieval-margin rules, and escalate the residual discrimination/slot work to Haiku.

---

## 1. Acceptance bar (pinned before running, from Spec 05b §3)

| Metric | Bar |
|---|---|
| Routing accuracy among ≤5 retrieved candidates | **≥ ~95%** |
| Slot extraction, exact | **≥ ~90%** |
| Latency p95 (on-device) | **< ~1.5 s** |
| Calibration | confidence must **separate right from wrong** (else escalation gates on retrieval, never model confidence) |

The decision rule (G-20): meet the bar → small model routes known capabilities; miss → cut it.

## 2. Methodology

**Dataset** (`05a-rig/dataset.json`, 57 labeled cases). Mined from the already-labeled 05a corpus (`05a-functional-examples.md`, `05a-traces.md`) plus paraphrase variants (3–5 phrasings per base case) and adversarial cases. Spread across the five test classes:

| Class | What | n |
|---|---|---|
| **A** | Known-capability routing (the core metric) | 26 |
| **B** | Slot extraction, incl. multi-entity (F-07 nested people-fact) | 7 |
| **C** | Meta-intent — novel need, capability **not** in candidate set (should be retrieval-owned) | 6 |
| **D** | Out-of-domain boundary — true OOD + the G-19 adversarial "what did I say about ‹world-noun›" | 8 |
| **E** | Ambiguous / adversarial — near-miss twins, coordinations, anaphora | 10 |

**Unified task shape.** Every case is a *candidate-discrimination* problem, exactly the small model's narrowed job: the utterance + a realistic ≤5-candidate set (retrieval has already narrowed) → pick **one** candidate `skillId` **or `"none"`** (none fits → escalate / author / delegate) + extract slots + report confidence. This one shape scores all five classes uniformly: for C, true-OOD (D), and anaphora (E), the correct answer is `"none"`; for the G-19 adversarials the correct answer is a records skill (`search-records`) — never `"none"`.

**Models.** Local: Qwen2.5-1.5B, Llama-3.2-3B, Gemma-2-2B, Phi-3.5-mini (all Q4_K_M via `llama-server`, CPU, 8 threads, Ryzen 9 5900XT). Cloud reference: **Haiku 4.5** via the Anthropic SDK. Gemma + Phi were downloaded (bartowski GGUFs) and served on :8083 / :8084 for this pass.

**Conditions.** (i) **free-form** and (ii) **constrained decoding** — a per-case JSON-schema with `skillId` restricted to the candidate-id enum, passed as the top-level `json_schema` field to `llama-server`'s `/v1/chat/completions`. Constrained decoding is **local-only** (the cloud reference runs free-form). **Phi-3.5-mini cannot be constrained in this llama.cpp build** — every `json_schema`-derived grammar is rejected with `400: "Failed to initialize samplers: Unexpected empty grammar stack after accepting piece: | (29989)"` (a tokenizer/grammar interaction, not enum-specific — it fails even for a bare `{"skillId": string}` schema). Documented; Phi is reported free-form only.

**Scoring** (`harness/eval_routing.py`, `harness/analyze_eval.py`):
- *Routing accuracy* — canonical `skillId == expected`. A numeric/positional `skillId` (the findings §5 "candidate number" wart) is mapped to the candidate at that 1-based index before comparison, so a right-pick-wrong-serialization still counts as correct.
- *Format-valid rate* — parseable JSON **and** `skillId` returned as a valid id string (or `none`/null) directly — i.e. not a numeric index, not a hallucinated id.
- *Slot P/R* — micro-averaged, **exact** (same key + equal normalized token set) and **normalized** (key-agnostic value match: token-containment or Jaccard ≥ 0.5). Dates are scored as the *spoken expression* (the model's job is to extract the anchor/offset, not resolve the calendar date — findings §3).
- *Latency* — wall-clock p50/p95 (local server also records prompt+gen ms).
- *Calibration* — mean self-reported confidence on correct vs. wrong picks, their separation, and the count of correct-at-confidence-0.0.

**Caveats (don't over-read).** Local latency is **CPU / Q4 / uncached-prompt on a desktop** — an iPhone ANE/Metal path + warmed prompt cache will differ (treat local latency as *relative*, per findings §8). Candidates are presented **keyed by id** (not numbered), which is the shipped-design recommendation from findings §5. n=1 per (case, model, condition), temperature 0 — these are shape/accuracy findings at the ~dozens-of-cases scale, not tight statistical rates. A handful of class-E cases (`E-twin-1`, `E-coord-1`) have a *defensible alternative* label (the task/reminder twin) that penalizes even Haiku, so class-E numbers slightly understate true quality.

**Cost.** Haiku reference: 57 calls, **$0.033 total** (~$0.00058/call). Local: 399 calls, $0.

## 3. Headline results — model × condition

| model | cond | route acc | slot exact P/R | slot norm P/R | fmt-valid | numeric-idx | p50 ms | p95 ms | conf ✓ / ✗ (sep) |
|---|---|---|---|---|---|---|---|---|---|
| **qwen2.5-1.5b** | free | **49%** | 50% / 48% | 82% / 79% | 100% | 0% | 2110 | 2679 | 0.93 / 0.91 (+0.02) |
| qwen2.5-1.5b | constrained | 49% | 50% / 48% | 82% / 79% | 100% | 0% | 2107 | 2713 | 0.93 / 0.91 (+0.02) |
| **llama-3.2-3b** | free | **49%** | 38% / 49% | 72% / 85% | 100% | 0% | 4771 | 5690 | 0.84 / 0.79 (+0.04) |
| llama-3.2-3b | constrained | 49% | 38% / 49% | 73% / 86% | 100% | 0% | 6800 | 8618 | 0.84 / 0.79 (+0.04) |
| **gemma-2-2b** | free | **49%** | 44% / 40% | 72% / 65% | 100% | 0% | 6241 | 7390 | 0.95 / 0.90 (+0.05) |
| gemma-2-2b | constrained | 49% | 44% / 40% | 72% / 65% | 100% | 0% | 5975 | 7811 | 0.95 / 0.90 (+0.05) |
| **phi-3.5-mini** | free | **46%** | 48% / 47% | 80% / 83% | 100% | 0% | 27561 | **31900** | 0.94 / 0.96 (−0.02) |
| phi-3.5-mini | constrained | — | *unavailable (llama.cpp grammar rejected by tokenizer)* | | | | | | |
| **haiku-4.5** *(cloud ref)* | free | **86%** | 78% / 76% | 92% / 91% | 100% | 0% | 762 | **1638** | 0.89 / 0.88 (+0.01) |

**Against the bar:** routing ≥95% → **all small models fail** (best 49%); slot-exact ≥90% → **all fail** (best 50%); p95 <1.5s → **all fail** on this CPU (best small 2.7s). Haiku misses routing (86%) and slot-exact (78%) but is far ahead of every small model, and its p95 (1.64s, incl. network) essentially sits at the bar.

*(All three ~2B models coincidentally land on exactly 28/57 correct — but on **different** subsets; see §7 overlap.)*

## 4. Per-class routing accuracy (free condition)

| model | A route (26) | B slots (7) | C meta (6) | D OOD (8) | E adversarial (10) |
|---|---|---|---|---|---|
| qwen2.5-1.5b | 65% | 29% | **0%** | 25% | 70% |
| llama-3.2-3b | **81%** | 29% | **0%** | **0%** | 50% |
| gemma-2-2b | 65% | 57% | **0%** | 38% | 40% |
| phi-3.5-mini | 65% | 43% | **0%** | 12% | 50% |
| **haiku-4.5** | **96%** | **100%** | 33% | **100%** | 70% |

Reading:
- **Class A (the real job):** the best small model is **Llama at 81%** — still 14 points under the 95% bar; the ~2B models sit at 65%. Haiku clears it (96%).
- **Class B (multi-entity slots):** small models collapse the F-07 nested people-fact ("Sarah's daughter Mia is allergic to peanuts") — they route it to `recall-contact-fact`/`log-interaction` instead of `add-contact-fact`, and flatten the entities. Haiku 100%.
- **Class C (meta-intent):** **0% for every small model.** They *never abstain* — they always grab a candidate rather than recognize "this needs a capability I don't have." This is the cleanest result in the study and it **confirms meta-intent must be retrieval-owned, not model-owned** (§7).
- **Class D (OOD):** small models 0–38%; the reason is the same non-abstention (they route true-OOD "what's the weather" to `search-records` instead of `none`). Haiku 100%.
- **Class E:** everyone (incl. Haiku) is dragged down by the genuinely-ambiguous task/reminder twins.

## 5. Constrained decoding: a no-op on accuracy (and it can hurt latency)

Routing-accuracy delta free → constrained: **+0 points for all three constrainable models.**

The reason is diagnostic: **format was never the problem here.** Free-form format-valid rate was already **100%**, and the numeric-index ("`skillId: 1`") wart from findings §5 **did not occur at all (0%)** — presenting candidates *keyed by id* instead of as a numbered list already eliminated it. The residual failures are **semantic** (wrong candidate, flattened entities), and an enum grammar cannot fix a confident wrong choice. Worse, constraining **slowed Llama down** (p95 5.7s → 8.6s) as the sampler fought the grammar.

**Implication for G-07:** constrained decoding is a legitimate *format guarantee* and cheap insurance, but it must not be sold as an *accuracy* fix. On this task the id-keyed prompt already delivered valid format; grammar added latency, not correctness.

## 6. Calibration: dead — confidence cannot gate escalation

| model | mean conf ✓ | mean conf ✗ | separation | correct @ conf 0.0 |
|---|---|---|---|---|
| qwen2.5-1.5b | 0.929 | 0.914 | **+0.015** | 1 |
| llama-3.2-3b | 0.836 | 0.792 | **+0.043** | 0 |
| gemma-2-2b | 0.945 | 0.900 | **+0.045** | 0 |
| phi-3.5-mini | 0.940 | 0.956 | **−0.016** | 1 |
| haiku-4.5 | 0.891 | 0.884 | **+0.008** | 3 |

Every model reports ~0.8–0.95 confidence **whether it is right or wrong**; the right-vs-wrong separation is within noise (≤0.045, one model negative). This **confirms the prior finding at scale** (findings §2a): the local model's self-reported confidence is uninformative, and — notably — **Haiku's is no better** (+0.008). Escalation must gate on **retrieval signals** (top-candidate score / margin / corpus trust), **never** on model confidence. This is already the G-07 resolution; the eval hardens it.

## 7. Can rules or an ensemble rescue it? No.

**Non-abstention is the dominant failure shape.** Small models have no reliable "none of these" reflex, which single-handedly zeroes class C and cripples class D. The architecture must *supply* abstention externally (retrieval below θ → don't ask the model at all), which is exactly the retrieval-gated design — so this failure is *expected and contained*, but it means the model cannot be trusted to recognize the boundary of its own knowledge.

**Ensemble ceiling (free, 4 small models):**
- all-4 agree & correct: **17/57 = 30%**
- union — *any one* correct (unachievable oracle): **40/57 = 70%**
- **no model ever correct: 17/57**, dominated by the abstention cases (all 6 class-C, all 4 D-OOD) plus a recurrence phrasing, two nested facts, and the ambiguous twins.

Even a **perfect** router that always picked whichever of the four models was right would hit **70%** — 25 points under the bar. There is no ensemble or voting scheme over these checkpoints that reaches 95%.

**Disjoint strengths (confirms findings §2 at scale):** Qwen leads on D/E, Llama on A, Gemma on B — they fail in partly-opposite ways, but the union still falls far short.

## 8. G-19 privacy boundary: a real (if accidental) reassurance

The G-19 worry: a model that misroutes "what did I say about ‹world-noun›" as OOD would hand a **private-records query to an external assistant** (a leak). On the four adversarial-personal cases:

| model | picked the right records skill | stayed in records (safe) | **leaked to none/OOD (privacy fail)** |
|---|---|---|---|
| qwen2.5-1.5b | 2/4 | 3/4 | **0/4** |
| llama-3.2-3b | 0/4 | 4/4 | **0/4** |
| gemma-2-2b | 3/4 | 4/4 | **0/4** |
| phi-3.5-mini | 1/4 | 4/4 | **0/4** |
| haiku-4.5 | 4/4 | 4/4 | **0/4** |

**No model leaked** a personal query to OOD/none. But note *why* the small models are safe here: it's the **same non-abstention** that ruins class C — they never say "none," so they never route a records query out of domain. (This is the inverse of Llama's earlier findings.md §2 failure, which used a 3-way router prompt with an explicit `out_of_domain` label — give the model that label and it misuses it; in the candidate-discrimination framing where `none` is the only OOD escape, it stays in records.) **Design read:** frame the OOD boundary as *retrieval-threshold + records-bias*, and never present the small model an explicit "out_of_domain" option it can over-trigger. G-19's records-biased resolution (Spec 03 §7.2) holds.

## 9. Latency

On this desktop CPU, p95 wall-clock: **Qwen 2.7s · Llama 5.7s (constrained 8.6s) · Gemma 7.4s · Phi 32s · Haiku 1.64s.** None of the local models meet the 1.5s p95 bar even before accounting for the fact that these are *relative* CPU numbers. **Phi free-form is a latency catastrophe (p95 32s)** — it appends prose commentary after the JSON, generating hundreds of tokens; the one fix (constrained decoding) is unavailable for Phi in this build. **Phi is out** on latency alone. Qwen is the only small model in a plausible-for-voice range and it's still the joint-worst on accuracy-per-class after Gemma.

## 10. Surprises / flags

1. **Constrained decoding did not improve routing at all (+0 pts)** and slowed Llama down. The findings §5 "skillId-as-number" problem was a *presentation* artifact of numbered candidate lists, not something needing a grammar — keying candidates by id fixed it for free (0% numeric-index across all models). Re-scope G-07: constrained decoding = format insurance, not an accuracy lever.
2. **Non-abstention is the master failure mode** — and it's double-edged: it destroys meta-intent/OOD detection (C = 0%, D low) yet *prevents* the G-19 privacy leak. Both point to the same architectural fix: the model must never be the one deciding "is this in-domain / does a capability exist" — retrieval thresholds decide that.
3. **All three ~2B models scored identically (28/57)** by coincidence, on different cases — a neat illustration that "pick the best small model" buys almost nothing; their ceilings are the same and their unanimous-miss set is structural (the abstention classes).
4. **Haiku's confidence is also uncalibrated** (+0.008 separation) — calibration is a property of the task/format, not model size. Don't trust *any* model's self-reported confidence for gating.
5. **Phi-3.5-mini is doubly disqualified:** can't be constrained in this build, and free-form p95 is 32s.

## 11. Recommendation

**NO-GO on the on-device generative model as a trusted autonomous router.** Take the G-20 *fail* branch. Concretely:

1. **Route known capabilities without the generative model on the hot path.** Lean on the deterministic stack that already exists in the design:
   - the **corpus fast-path** (hash lookup, 0 model calls) for repeat phrasings;
   - **retrieval top-1 with a margin rule** — if the best candidate clears θ and beats #2 by a margin, dispatch it directly (no generative discrimination needed);
   - the **deterministic date/recurrence resolver** for all date math (findings §3, already locked).
2. **Escalate the genuine residual to Haiku**, not to a small local model. The residual is exactly the hard slice: retrieval returns ≥2 close candidates *and* the phrasing is novel *and* the corpus misses. Haiku is 96%/100%/100% on A/B/D, ~$0.00058/call, ~0.8s p50 / 1.6s p95. The 20-calls/hr escalation cap (Spec 03 §3.5) more than covers it.
3. **Own meta-intent (C) and OOD (D) in retrieval + rules, never the model.** The 0% class-C result is definitive: a small model will always grab a candidate. "Does a capability exist for this?" must be a retrieval-threshold decision; "is this out-of-domain?" must be retrieval-threshold + records-bias (Spec 03 §7.2 / Appendix A.2), presented to the model — if at all — without an explicit OOD label it can over-trigger.
4. **Gate escalation on retrieval signals, never on model confidence** (calibration is dead for every model incl. Haiku). Bake into Spec 03 §3.4/§7.1.
5. **If a small local model is kept at all**, use it only as a *tie-breaker whose output retrieval verifies/bounds* (it may only pick among the exact retrieved ids; its "none" is ignored; its confidence is ignored) — never as the autonomous router or the escalation gate. On the evidence, even this narrow role buys little over a retrieval-margin rule, and adds 2–8s of CPU latency.

**Net:** the architecture's hedge (Spec 05b §4, G-20 "the small model owns only the discriminate-among-retrieved-known-candidates slot") is *not* earned by these checkpoints — the best does 81% on precisely that slot. The good news is the pipeline was designed to survive this outcome: retrieval + corpus + deterministic resolvers do the reliable work, and Haiku is a cheap, accurate escalation target. Cut the on-device generative model from the trusted routing path.

*Open follow-ups (not blockers):* (a) a larger 7–8B local model was descoped for time — worth a single confirmatory run to establish the on-device ceiling, but 3B→7B is unlikely to clear 95% *and* 1.5s p95 on a phone; (b) re-run the correctness-sensitive classes at n≥3 to tighten the rates before folding into Spec 03; (c) measure the shipped stack end-to-end (corpus + retrieval-margin + Haiku fallback) — this eval isolates the *model*, and the real system's accuracy is the stack's, not the model's.

## 12. Reproduce

```bash
cd planning/specs/05a-rig
bash harness/serve.sh start                         # Qwen:8081, Llama:8082
./bin/llama-server.exe -m ./models/gemma-2-2b-it-q4_k_m.gguf --port 8083 -c 4096 -t 8 --no-webui &
./bin/llama-server.exe -m ./models/phi-3.5-mini-instruct-q4_k_m.gguf --port 8084 -c 4096 -t 8 --no-webui &
./venv/Scripts/python.exe harness/build_dataset.py  # -> dataset.json (57 cases)
./venv/Scripts/python.exe harness/eval_routing.py   # -> results/eval-routing-{raw,summary}.json
./venv/Scripts/python.exe harness/analyze_eval.py   # -> the tables above
```

**Artifacts:** `05a-rig/dataset.json` (labeled set) · `05a-rig/harness/{build_dataset,eval_routing,analyze_eval}.py` (new) · `05a-rig/harness/lib.py` (extended `local_chat` with `json_schema`/`grammar`) · `05a-rig/results/eval-routing-raw.json` (every call) · `eval-routing-summary.json` (aggregates) · `eval-routing-analysis.md` (regenerated tables) · `eval-run.log` (run transcript). New GGUFs: `models/gemma-2-2b-it-q4_k_m.gguf`, `models/phi-3.5-mini-instruct-q4_k_m.gguf` (gitignored).
