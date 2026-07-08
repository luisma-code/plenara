# Spec 09 — Test

**Status:** v0.1 — July 2026 (first draft, written *after* the suite it governs: the v0 engine ships **1363 Dart tests + 8 Flutter widget tests, all green** as of 2026-07-07, `dart analyze` clean. This spec therefore mostly **documents and formalizes an architecture the code already realizes** — each section says so and cites the file — and then specifies the gaps to close: coverage instrumentation + CI thresholds (research §9.3), the missing E2E paths, and the dogfooding measurement plan. Scope per research §12 item 9.)
**Depends on:** Spec 02 — Skill DSL (§3, §4, §9); Spec 03 — NLU/Intent (§2.6, §5, §7, the recorded test-pair methodology); Spec 04 — Architecture (§3.1, §3.5, §3.10, §3.13, §5); Spec 05a — Functional Examples (the 60-example corpus); research §9.3, §12.9
**Blocks:** nothing structurally — but the CI gate (§8) is the enforcement arm of every other spec's "tested" claim, so release-candidate hardening (research §11.4) blocks on it.

---

## 0. Purpose & Scope

Every other spec makes claims — "deterministic," "offline," "never silently fails," "the corpus learns." This spec defines how those claims are *checked*, continuously and mechanically, so they stay true as the code changes. It covers:

1. The testing pyramid — which tier owns which claim, and the harness each tier runs on (§2)
2. The seam-and-fake discipline — the standing directive that makes product logic CI-testable at all (§3)
3. Interpreter and primitive coverage (§4)
4. The recorded NLU + authoring test pairs — the replay cassette, and when a re-record is forced (§5)
5. The E2E critical paths — built and target (§6)
6. The 05a conformance harness as the spec-completeness metric (§7)
7. Code-coverage instrumentation with CI thresholds — research §9.3, currently the largest gap (§8)
8. Property/fuzz and adversarial robustness (§9)
9. The dogfooding plan — what dogfooding measures, and what it is forbidden to validate (§10)

It does **not** cover: the routing-accuracy eval rig (`planning/specs/05a-rig/`, a research instrument with its own harness — findings §11–§13), or the diagnostic/feedback export format (Spec 11).

Unlike Specs 01–05, most of this document describes running code. Where a section is *specification of future work* rather than documentation of the shipped suite, it is marked **[GAP]**.

---

## 1. Governing Principles

**P9.1 — Automated tests must give real product-level validation; nothing is validated only by manual dogfooding.** Luis's standing directive #1 (HANDOFF.md), verbatim in spirit: anything whose only validation is a human trying it *will* regress. The unit under test is product behaviour — "saying X creates the record, arms the toast, and survives an app restart" — not a function's return value in isolation. Dogfooding *measures* (clarify rate, learning rate, §10); it never *validates*. A capability is not done until CI proves it.

**P9.2 — Seam with a fake.** The corollary discipline, already the codebase's dominant pattern: every OS- or network-facing capability ships behind a thin adapter interface with an in-memory fake, so all decision logic is CI-tested deterministically and only a razor-thin "call the real API" shim needs a one-time human smoke. Realized today by `StorageRepository` (+ in-memory fake), `CloudClient` (+ a whole taxonomy of fakes, §3.2), and `NotificationScheduler` (+ `FakeScheduler`) — see §3. Every future OS surface (speech, calendar, contacts) enters the codebase the same way or not at all.

**P9.3 — Offline determinism is proven, not asserted — by a fake that throws.** The free tier's "fully offline" claim (research §6, Spec 04 §6) is enforced by the `_NoCloud` pattern: a `CloudClient` whose every method **throws** (`v0/test/session_test.dart`, `spec05a_test.dart`, `reminders_test.dart`, `people_test.dart`, `f07_nested_fact_test.dart`). Any offline flow that so much as touches the cloud seam fails the suite loudly. This is P2.8 (no silent failure) applied to the tests themselves: an accidental cloud dependency cannot hide behind a stub that quietly returns null.

**P9.4 — Recorded reality over hand-faked shapes.** Where a model *is* in the loop, tests replay **genuine recorded model outputs** (the cassette, §5), not hand-written imitations — so they catch real schema drift in what Haiku actually returns, which a hand-faked response never would. Hand-built fakes are reserved for the cases where recorded output is the wrong tool: scripted *failures* (`_ErrCloud`), adversarial malformed output (`_ScriptCloud`), and context-echo assertions (`_GenCloud`, §3.2).

**P9.5 — Measured, not assumed.** Research §9.3's phrase, and the project's repeated lesson (the `G-20` NO-GO, the `G-38` retrieval measurement, the `G-47` conformance harness — all cases where an assumed number was wrong). Two standing measurements: spec-completeness is the 05a conformance count **N/60** (§7, currently 20/60), and untested production code is made visible by coverage instrumentation with a CI gate (§8). "The suite is green" is necessary, never sufficient — green over 40 skips, or green over uncovered code, is a different fact than it appears.

**P9.6 — Hermetic and reproducible.** Every test builds its own world: an isolated temp data dir (`makeTempDataDir()`, `v0/test/helpers.dart` — a copy of types/skills/corpus with an empty `records/`), a **frozen clock** injected into `Session`/`Interpreter`/`Router` (`DateTime.parse('2026-07-06T09:00:00')`, a Monday — mirroring Spec 02 §4.4 frozen inputs and Spec 03 §2.6 `NluContext.now`), and seeded randomness for fuzz sweeps (§9). No test reads the wall clock, the network, the real data folder, or another test's state; the suite runs in parallel and gives the same answer on any machine.

**P9.7 — Integration-first; fakes prove seams, they are not the default harness.** The project rule "don't mock the database — use real storage" (CLAUDE.md) is honored as a *default*: the bulk of the suite runs `Session` against real per-record JSON files in a temp dir, exercising the actual persistence path (hydrate → mutate → flush → reload). The in-memory `StorageRepository` fake appears in a deliberately small set of tests whose *point* is the seam itself ("nothing about Session depends on the filesystem backend", `session_test.dart` `'StorageRepository seam'` group). The reconciliation with P9.2: fakes replace the **OS/network boundary** (toast, cloud), never the layer whose correctness is under test (storage is tested *as storage*, on disk).

---

## 2. The Testing Pyramid

Strict layering (research §9.2, Spec 04 §2) is what makes a clean pyramid possible; the v0 suite realizes it as follows. Each tier states the claim it owns and the harness that checks it.

| Tier | Claim owned | Harness / doubles | Realized in |
|---|---|---|---|
| **1. Unit — interpreter & primitives** | Every DSL primitive, every seed skill, schema validation, the authoring gate behave per Spec 02 — no NLU, no storage backend, no cloud. | `Interpreter` driven by simulated NLU output `{skillId, slots}`; plain in-memory store map; frozen clock. | `v0/test/interpreter_test.dart` (§4) |
| **2. Unit — NLU corpus routing** | The corpus fast-path routes hundreds of phrasings + every date form deterministically; `route()` mutates nothing (Spec 03 §2.6 purity). | `Router.load` over the real seed `corpus.json`; frozen clock; no cloud, no embedder. | `v0/test/router_test.dart` |
| **3. Integration — storage** | Per-record file shape, `_meta` HLC block, round-trips, tombstones, `undoTurn` — against a **real temp directory** (research §9.3, verbatim). | `dart:io` temp dirs; both memory and disk paths. | `v0/test/store_test.dart` |
| **4. Integration — turn engine (E2E offline)** | The full turn pipeline — route → resolve → execute → persist → describe → undo/correct — over the offline corpus, plus cross-skill integration and persistence across `Session` instances. | Real `Session` + real temp-dir storage + **`_NoCloud` (throws)**. | `v0/test/session_test.dart`, `pipeline_test.dart`, `people_test.dart`, `reminders_test.dart`, `f07_nested_fact_test.dart` (§6) |
| **5. Integration — cloud paths (recorded)** | Residual routing, corpus learning, and authoring against **genuine recorded Haiku outputs** — deterministic, free, offline (research §9.3 "recorded pairs"). | `ReplayCloud` over the committed cassette `v0/test/fixtures/cloud.json` (§5). | `v0/test/cloud_test.dart` |
| **6. Integration — typed failure surfaces** | Every `CloudError` kind degrades to an honest, named user surface (Spec 04 §3.5/§5); date/datetime slot normalization; live-client wire behaviour. | `_ErrCloud` (scripted failure kinds), local stub HTTP server for the real `ClaudeClient`. | `v0/test/cloud_result_test.dart`, `claude_test.dart`, `hardening_test.dart` |
| **7. Integration — generative grounding** | A generative prompt is assembled from the user's *real records*, never invented, and tier/connectivity failures degrade honestly (Spec 04 §3.10). | `_GenCloud` — a fake that **echoes the assembled context** so grounding is assertable. | `v0/test/generative_test.dart` |
| **8. Conformance — spec completeness** | Each of the 60 worked examples (Spec 05a) passes with its exact utterance, or carries an explicit skip-reason. The measured N/60. | Real offline `Session` + `_NoCloud`. | `v0/test/spec05a_test.dart` (§7) |
| **9. Property / fuzz + adversarial** | Randomized inputs survive the whole pipeline; hostile input never crashes or mis-interpolates. | Seeded `Random`; injection-shaped/unicode/huge inputs. | `v0/test/pipeline_test.dart`, `robustness_test.dart` (§9) |
| **10. UI — widget** | Each user-visible surface renders and reacts against a hermetic injected `Session` (research §9.3 "widget tests against mock state"). | `flutter_test` + `Session` on a temp dir + `_NullCloud`/`_GatedCloud`. | `app/test/widget_test.dart` — 8 tests (§6.3) |
| **11. Human smoke — one-time, razor-thin** | "Does the real OS actually render it" — the only tier a human owns, and only for the thin shim (P9.2). | The real device. | e.g. the one real Windows toast smoke after `WindowsToastScheduler` wiring |

Two supporting instruments sit beside the pyramid: the **dogfood turnlog** (`turnlog.jsonl` + `bin/turnlog_report.dart`, unit-tested in `turnlog_test.dart`) — a *measurement* instrument, tier-10-adjacent but not a validator (§10) — and the **fixture recorder** (`bin/record_fixtures.dart`), the tool that refreshes tier 5's cassette (§5.3).

The pyramid's shape is honest: tiers 1–4 carry the overwhelming majority of the 1363 tests; tier 10 is the thinnest surface (8 tests) and is the designated growth area (§6.3, HANDOFF "grow these per directive #1").

---

## 3. The Seam-and-Fake Discipline

### 3.1 The catalog of seams

Every boundary where Plenara touches something non-deterministic (OS, network, clock, randomness) has a named interface and at least one in-memory double. This table is normative: a new OS-facing capability MUST add its row before it ships.

| Seam | Interface | Double(s) | Real impl | Human smoke needed |
|---|---|---|---|---|
| Storage | `StorageRepository` (`v0/lib/storage_repository.dart`) | in-memory map impl (`_MemStorage`, `session_test.dart`) | per-record JSON files (`store.dart`) | no — real impl is itself CI-tested on temp dirs (P9.7) |
| Cloud AI | `CloudClient` (`v0/lib/claude.dart`) | the fake taxonomy, §3.2 + the cassette, §5 | `ClaudeClient` (live HTTP; wire-tested against a stub server in `claude_test.dart`) | no — recorder run doubles as the live smoke |
| OS notifications | `NotificationScheduler` (`v0/lib/reminders.dart`) | `FakeScheduler` (in `lib/`, deliberately — it is also the safe production default until a platform shim is smoked) | `WindowsToastScheduler` | yes — one real toast, once |
| Clock | constructor-injected `DateTime` on `Session`/`Interpreter`/`Router` | frozen `2026-07-06T09:00:00` | `DateTime.now()` at the composition root only | no |
| Speech (future) | `SpeechInput`/`SpeechOutput` (planned, DOGFOOD.md item 3) | **[GAP]** — must exist before any voice logic lands | platform STT/TTS | yes — thin shim only |

The `NotificationScheduler` is the reference execution of the discipline and worth stating as the pattern (from `v0/lib/reminders.dart`): the OS shim is **three methods** (`schedule`/`cancel`/`armed`) mapping 1:1 to platform APIs; *everything worth testing* — which reminders arm, dedupe on re-open, cancel on undo, reschedule detection, past-due nudges — is pure reconciliation logic over the record store, derived (never imperatively tracked), and exhaustively CI-tested against `FakeScheduler` (`reminders_test.dart`, 30+ tests). The human owes the project exactly one smoke of the shim, ever.

### 3.2 The `CloudClient` fake taxonomy

The cloud seam has not one fake but a **taxonomy**, each encoding a distinct test intent. This is deliberate and normative — collapsing them into one configurable mega-fake would blur what each test proves:

| Fake | Behaviour | Proves | Home |
|---|---|---|---|
| `_NoCloud` | **throws** on any call | the flow under test is *fully offline* — an accidental cloud touch fails loudly (P9.3) | `session_test`, `spec05a_test`, `reminders_test`, `people_test`, `f07_nested_fact_test` |
| `_NullCloud` | returns `CloudOk(null)` (genuine abstain) | adversarial/unroutable input degrades to clarify, not a crash | `robustness_test`, `app/test/widget_test` |
| `_ErrCloud` | always fails with a fixed `CloudErrorKind` | every named failure kind reaches its honest user surface + turnlog entry (Spec 04 §5) | `cloud_result_test` |
| `_ScriptCloud` | scripted (possibly malformed/throwing) authoring + routing payloads | hardening: hostile or broken model output cannot crash a turn or clobber built-ins | `hardening_test` |
| `_GenCloud` | **echoes the assembled context** back | generative grounding — the prompt contains the user's real records and nothing invented | `generative_test` |
| `_GatedCloud` | blocks on a `Completer` until released | in-flight UI state (disabled Send, progress bar) is observable deterministically | `app/test/widget_test` |
| `ReplayCloud` | replays the recorded cassette; **throws on a missing key** | real `Session` code against genuine Haiku outputs — schema-drift detection (§5) | `cloud_test` |

The distinction between `_NoCloud` (throws — "this path must never get here") and `_NullCloud` (abstains — "this path may get here and must degrade") maps exactly onto Spec 04 §3.5's insistence that "the model abstained" and "we never heard back" are different values. The fakes preserve the type-level honesty of the seam they double.

---

## 4. Interpreter & Primitive Coverage

**Status: built.** `v0/test/interpreter_test.dart` (the largest single file in the suite) is the tier-1 harness for Spec 02, and its structure is the coverage contract:

- **The primitive vocabulary, exhaustively.** Every primitive op (Spec 02 §3) is exercised directly — including the query fidelity work (ordering/limit/filter-ops), the compute grammar (aggregation, date math, `next_annual`, streaks per `G-21`/`G-42`), `format`, branching, and `foreach` reduction. A primitive without a test is treated as unshipped: the vocabulary is closed (Spec 02 §3, P2.4), so its test set is *enumerable and complete* by construction — the deliberate payoff of "capabilities are data, not code." There is no authored-code surface to test, only a fixed instruction set.
- **Every seed skill across many inputs.** The full Spec 02 §9 seed set — test-enumerated, per its counting rule (36 shipped in `v0/data/skills/` at time of writing) — runs through resolve + execute against varied slots — the "recorded request → expected artifact" idea of research §5 applied to the deterministic side.
- **The resolve/execute split** (Spec 02 §4): resolve is pure and write-free; execute returns before-images that `undoTurn` consumes (asserted again at the store tier, `store_test.dart`).
- **Schema defaults + required-validation, `read_one` ambiguity** (Spec 01 §4, `G-12` invariant), and **error paths**.
- **The static authoring gate**: one passing case and *many* rejections — the validator that keeps a cloud-authored skill inside the closed vocabulary (Spec 02 §6.3) is itself regression-tested against a catalogue of invalid shapes, and `hardening_test.dart` adds the adversarial cases (path traversal, built-in clobbering, malformed steps).

Driving the interpreter with simulated NLU output (`{skillId, slots}`) rather than through `Session` is the layering payoff (P2.5): tier 1 needs no router, no storage backend, no cloud — so it is fast enough to run on every change and precise enough that a failure names the primitive at fault.

**[GAP — measurement, not construction]:** "exhaustively" is asserted by review today, not measured. The §8 coverage gate turns it into a number: `interpreter.dart` is Tier-A code with a ≥90% line bar, and the per-op checklist becomes auditable from the lcov report.

---

## 5. Recorded NLU & Authoring Pairs — the Replay Cassette

**Status: built.** This is the v0 realization of two spec commitments at once: research §9.3's "intelligence layer tested with recorded utterance/intent pairs and recorded request/type-definition pairs — deterministic even though the underlying model is not," and Spec 03 §7's recorded test-pair methodology. The v0 cut records at the **cloud seam** (the one place a model actually sits post-`G-20`), which is exactly where Spec 03's pipeline is non-deterministic.

### 5.1 The mechanism (VCR/cassette)

`v0/lib/replay_cloud.dart`:

- **`RecordingCloud`** wraps the live `ClaudeClient` and captures every result into a keyed map. It runs **once, online, with a valid BYOK key** — and because a recording run must be clean, a `CloudError` mid-record **throws** ("fix the key/network and re-record") rather than baking an outage into the fixture.
- **`ReplayCloud`** serves the captured results with no network. Every recorded value replays as `CloudOk` — a recorded `null` is a *genuine model abstain*, preserved as data. **A missing key throws** ("no cloud fixture for key … add the input to `lib/fixture_inputs.dart` and re-run `bin/record_fixtures.dart`") so a gap fails loudly instead of masquerading as "offline" — P2.8 applied to fixtures.
- The cassette is `v0/test/fixtures/cloud.json`, committed. Tests are deterministic, free, and fast, yet run the **real `Session` code** against **genuine recorded Haiku outputs** — catching real schema drift in routing responses and authored capabilities, which hand-faked shapes structurally cannot (P9.4).

### 5.2 The key schema and the forced re-record (`invSig`)

A cassette key is `method + extra + primary`:

- **Residual routing:** `route` + `invSig(skills)` + utterance. `invSig` is the sorted, comma-joined list of all `skillId`s — a stable **signature of the capability inventory**. Routing *depends* on what capabilities exist (the candidate space), so the inventory is part of the key. The consequence is the methodology's most important property: **adding, removing, or renaming any skill changes `invSig`, every routing key misses, and `ReplayCloud` throws — a re-record is forced, mechanically.** A stale cassette cannot silently vouch for routing decisions made against a different capability inventory. (Authoring *during* a recorded flow grows the inventory mid-run, which is why it must be a new key — noted in the source.)
- **Authoring:** `author` + (`priorError` or empty) + description. The recorder drives the **real `Session` authoring path including its validate→retry loop**, so a first-attempt out-of-vocab flake (a known Haiku failure mode, `G-29`) is recorded *together with* its `priorError`-corrected retry — the cassette captures the loop the product actually runs, not an idealized single shot.
- **Generative is deliberately NOT cassette-backed.** Generative output is grounded in dynamic per-session context (the user's records at that moment), so a recorded answer would be a lie about determinism; `ReplayCloud.generate` **throws** rather than fake it. Generative flows are tested with the `_GenCloud` echo fake instead (§3.2, tier 7) — asserting the *grounding contract*, which is the deterministic part.

### 5.3 The single source of inputs

`v0/lib/fixture_inputs.dart` is the canonical input set — novel phrasings grouped **by the skill they SHOULD resolve to** (so `cloud_test.dart` asserts routing correctness against recorded reality) plus the authoring descriptions. Both the recorder and the tests import it, so **every input a test replays is one the recorder captured — no drift by construction.** The maintenance loop: add an input there → `dart run bin/record_fixtures.dart` (one BYOK Haiku pass) → commit the refreshed cassette.

### 5.4 Relation to Spec 03 §7, and what remains **[GAP]**

Spec 03's full methodology specifies `NluRouter.testPair(pair, context)` over `(transcript, NluContext)` pairs, with `route`'s referential transparency (Spec 03 §2.6) as the property that makes replay a true regression harness. The v0 engine has that purity (frozen clock, pure `Router.route`, cassette-keyed cloud) but not the formal `TestPair` shape or a corpus of *context-bearing* pairs (anaphora over `recentIntents`, `pendingConfirmation` interpretation) — because those context features are themselves v0-partial. **Decision:** the cassette + `fixture_inputs.dart` is the v1 methodology of record; the `TestPair`-with-`NluContext` harness lands together with the context features it would test, and dogfood turnlog entries become candidate pairs for it (§10.3). Additionally, `routingSource` feeding a test-pair *recorder in production* (Spec 03 §2.5) is unbuilt — the turnlog's `source` field is its v0 stand-in.

---

## 6. E2E Critical Paths

Research §9.3: "End-to-end tests are narrow and high-value: the full voice → intent → action → storage round-trip, plus one capability-authoring round-trip, on a small number of critical paths."

### 6.1 Built (and where)

- **Utterance → intent → action → storage → reload → undo** — the core round-trip, minus voice (which does not exist yet; the transcript IS the current entry boundary). `pipeline_test.dart` runs route → resolve → execute → persist → **reload from disk** → undo per seed skill; `session_test.dart`'s `'multi-turn story (the full offline pipeline)'` and `'realistic day — broad cross-skill integration'` groups run long conversational sequences (capture, query, correction, undo, persistence across `Session` instances) — all under `_NoCloud`, so the whole path is proven offline.
- **The capability-authoring round-trip** — research §9.3's "describe → type created → log against it" — is realized in `cloud_test.dart` against the cassette: `'"start tracking $desc" previews, then "activate" registers it'` and `'an authored capability previews, then "activate" registers + persists its files'`, with the authored capability's files landing on disk and the schema-drift guard implicit in replaying genuine authored JSON through the real validator.
- **Novel phrasing → cloud route → execute → corpus learns → correction forgets** — the learning loop (Spec 03 §5.2, v0 binary ratchet `G-45`): `cloud_test.dart` asserts both the graduation into the fast path and that a correction removes the learned template.
- **Reminder arming E2E** — utterance → record → `reconcileReminders` → armed toast set, plus dedupe on re-open, cancel on undo, reschedule re-arm, past-due nudges (`reminders_test.dart` against `FakeScheduler`).
- **Failure-path E2E** — each `CloudErrorKind` from utterance to honest surface + turnlog (`cloud_result_test.dart`).

### 6.2 Target paths not yet covered **[GAP]**

1. **Voice round-trip.** Blocked on voice existing; the moment `SpeechInput`/`SpeechOutput` land (behind seams, §3.1), the critical path becomes *recorded-audio-or-fake-transcript → intent → action → storage* with the STT shim faked, and one human smoke of the real mic. The suite's current text entry point remains a permanent tier (it IS the deterministic core), not a placeholder.
2. **Generative request routed from a spoken/typed turn.** `GenerativeService` kinds are built and grounded-tested (tier 7), but session-level routing of the newer kinds (weekly_review/pattern_insight/draft-message) is not wired (HANDOFF); when it is, each kind owes one `Session.handle` → tier-gate/degrade → echo-grounding E2E.
3. **Automation → Review Feed.** `AutomationRunner` is unbuilt (Spec 04 §3.9); when built, the E2E is: automation fires (fake clock) → write held for review → approve/decline — with the *no act-then-describe for unattended writes* invariant asserted (CLAUDE.md locked principle).
4. **Multi-device merge.** Deferred with the CRDT engine (P2, `G-36`); the store tier's HLC tests are the down payment.
5. **Restart-surviving undo.** Undo is in-memory in v0 (DOGFOOD.md known edge); the persisted-journal path (Spec 04 §3.11) owes a kill-and-relaunch E2E when built.

### 6.3 The widget tier **[GAP — thinnest surface, designated growth]**

`app/test/widget_test.dart` (8 tests) covers: greeting + a full turn, past-due-reminder and birthday nudge bubbles, empty-input no-op, undo from the UI, multi-turn list rendering, graceful unrecognized-input reply, and the in-flight busy state (via `_GatedCloud`). All hermetic — an injected `Session` on a temp dir. This is real product-level validation of the shell, but it is 8 tests against a growing UI; per research §9.3, the target is **each view archetype renders a representative type** once Spec 07 defines the archetype set, plus one widget test per user-visible failure surface (Spec 04 §5's mapping). Growth here is explicitly directed by P9.1 (HANDOFF: "thinnest-covered surface; grow these").

---

## 7. The 05a Conformance Harness — Spec-Completeness as a Number

**Status: built** (`v0/test/spec05a_test.dart`, resolving `G-47`). The origin is instructive: "47/60 fail" was a hand audit that **drifted within hours** of being written (05b `G-47`). The fix is the defining application of P9.5 — turn "complete per spec" into a regression-checked number.

**Mechanism.** Each of the 60 worked examples (Spec 05a: F-01…F-20 free, P-01…P-20 paid, DF-01…DF-10 free-tier denials, DP-01…DP-10 paid denials) is one test that runs the example's **exact utterance(s)** through the real offline `Session` (`_NoCloud`, frozen Monday clock, temp dir) and asserts the specified outcome — records created with the right fields, the specified refusal text, the graph query answer. An example that cannot yet pass is `skip:`ed **with a reason that names the blocker** (the gap ID, the cloud dependency, or the exact phrasing that doesn't route offline). Three disciplines keep the number honest:

1. **The skips ARE the worklist.** Every skip reason is an actionable statement (e.g. F-03: "interval RRULE unbuilt — G-8"; F-08: "filtered fact query needs cloud"; DF-05: "needs an offline-returning cloud — `_NoCloud` throws"). The harness is simultaneously the metric and the backlog.
2. **The tally comment is kept in sync with runs** (bottom of the file): currently **20 pass / 40 skip of 60** — F-tier 11/20, P-tier 0/20 (all BYOK-gated), DF 2/10, DP 7/10 (the deterministic safety/scope/OOD/medical/impersonation floors) — up from ~1/60 at the audit and 9/60 at harness creation.
3. **Equivalent-utterance passes stay skipped.** Where the *capability* is built but the exact 05a wording doesn't route offline (F-14/F-15), the test body asserts the mechanism via an equivalent phrasing **and still carries `skip:`** — the metric counts exact-utterance conformance only, so a pass is never softened by paraphrase.

**Semantics of the number.** N/60 measures *offline exact-utterance conformance of the v0 engine*. It is deliberately conservative: P-tier examples will pass only with a replay-backed (cassette, §5) or live-keyed harness variant, and several F-tier skips are corpus-phrasing gaps rather than missing capability. **[GAP — specified here]:** (a) a **paid-tier harness variant** running P-01…P-20 against `ReplayCloud` so the paid 20 stop being structurally unreachable (target: P-tier conformance measured, not skipped-by-definition); (b) a **skip-audit rule** — any skip whose stated reason has been resolved elsewhere (its gap ID closed) fails a periodic review pass, so skips cannot rot into permanent exemptions; (c) the tally comment is replaced by a **generated count** asserted in-suite, so the sync-by-hand discipline in (2) becomes mechanical.

**Release meaning.** The research roadmap's "v1.2 usable / v1.5 uncrippled free tier" (research §11.3) gets its objective definition here: free-tier-complete ⇔ F-tier + DF-tier pass rate at 30/30 minus explicitly-deferred examples (each deferral recorded in the Decision Record of the owning spec). No release milestone may cite conformance except by this number.

---

## 8. Code-Coverage Instrumentation & CI Thresholds **[GAP — the largest one]**

Research §9.3 is unambiguous: "Coverage is measured, not assumed. The project adopts standard code-coverage instrumentation (`flutter test --coverage` producing lcov) **from the first commit**, with a CI gate that fails the build below an agreed threshold and reports per-layer coverage… Generated code and platform glue are excluded from the denominator; the interpreter, business logic, and storage layers are held to the highest bar."

**Status (updated 2026-07-07): instrumentation + the coverage GATE now exist; the CI *pipeline* and import-lint gate remain.** `v0/bin/coverage_check.dart` reads the lcov report, prints per-file coverage worst-first, and exits non-zero below a floor (default 80%). First measured global: **91.4% (1617/1770 lines), above the §8.3 global floor** — the "assumed, not measured" state §9.3 forbids is now closed for the numerator. Tier-A core is strong (`interpreter.dart` 91%, `store.dart` 91%, `automations.dart` 93%); `session.dart`/`people.dart`/`generative.dart` (Tier B) sit 90%+. The measurement immediately surfaced **two tiering refinements to fold in:** (a) `replay_cloud.dart` reads **44%** because its *recorder* half runs only under `record_fixtures` (operator tooling) — it should move from Tier A to the §8.2 operator exclusions, split from the replay half; and (b) `router.dart` reads **80.6%**, sitting right at — not comfortably above — its Tier-A ≥90% target, flagging the real gap the closed vocabulary hides. `embed.dart` (0%, needs the embed server) and `fixture_inputs.dart` (0%, recorder input) are likewise exclusion candidates. **Still unbuilt:** the hosted CI pipeline (`.github/`), per-tier enforcement wired into a pre-push/CI step, and the import-lint layering gate (§8.4 steps 5–7). Run: `dart test --coverage=coverage` → `dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib --packages=.dart_tool/package_config.json` → `dart bin/coverage_check.dart`.

### 8.1 Instrumentation

- **Engine:** `dart test --coverage` → lcov (`package:coverage` format_coverage) in `v0/`.
- **App:** `flutter test --coverage` in `app/`.
- Reports merged and stored as a CI artifact per run; a per-layer summary (one line per `lib/*.dart`) printed in the job log so untested code is *visible*, not discovered late.

### 8.2 Denominator exclusions (per §9.3)

Excluded: `v0/bin/**` (operator tools — the recorder, `turnlog_report`, the console entry), `app/windows/**` and generated plugin registrants (platform glue), and the razor-thin real OS shims (`WindowsToastScheduler` and successors — they are validated by the one-time human smoke, P9.2, and counting them would penalize the seam discipline that makes everything else testable). **Nothing else.** Fakes that live in `lib/` (`FakeScheduler`, `ReplayCloud`) stay in the denominator; they are product-adjacent code and are exercised anyway.

### 8.3 Thresholds — per-layer, held highest where the specs are strictest

Launch values; the gate fails the build below them. Tiering follows §9.3's "interpreter, business logic, and storage held to the highest bar":

| Tier | Files (current names) | Line-coverage floor |
|---|---|---|
| **A — deterministic core** | `interpreter.dart`, `router.dart`, `store.dart`, `reminders.dart` (logic), `dates.dart`, `replay_cloud.dart` | **≥ 90%** |
| **B — business logic & seams** | `session.dart`, `people.dart`, `generative.dart`, `claude.dart`, `storage_repository.dart`, `turnlog.dart`, `config.dart` | **≥ 80%** |
| **C — app shell / widgets** | `app/lib/**` | **≥ 60%** at adoption, ratcheting with §6.3 growth |
| **Global** | everything in the denominator | **≥ 80%** |

**Ratchet-only rule:** thresholds may rise as measured coverage rises (set to `measured − 2pts` after a quarter of stability) and are never lowered to admit a change; a PR that cannot meet the bar changes the code or adds the tests, not the number. Rationale for not demanding 100% on Tier A: the closed vocabulary makes *op-level* completeness the real bar (§4), and line coverage is its detector, not its definition — defensive unreachable-by-construction branches shouldn't force test theater.

### 8.4 The CI gate (specified; adopt with the first remote/shared workflow)

One pipeline, failing on any step: (1) `dart analyze` (both packages, zero issues — already the local norm); (2) `dart test` in `v0/`; (3) `flutter test` in `app/`; (4) coverage thresholds per §8.3; (5) **import-lint layering gate** — the research §9 dependency rule (UI → BL → Storage → Intelligence, no upward or skipping imports) enforced mechanically, closing the standing CLAUDE.md promise; (6) `flutter build windows --debug` (the "it still builds" floor HANDOFF already checks by hand); (7) the 05a conformance count regenerated and compared — a *decrease* in N/60 fails the build (conformance is ratchet-only too). Solo-project note: until a hosted runner exists, steps 1–7 run as a local pre-push script with identical semantics — the gate's authority comes from its content, not its host; but §9.3 says CI, and CI it becomes the moment the repo has a remote pipeline. **BUILT (2026-07-08): `tool/precheck.sh` runs steps 1–6 + a secret scan — v0 `analyze`, the **import-lint layering gate** (step 5, `bin/import_lint.dart`: no `lib/` file may import a higher layer per the util<storage=intelligence<business-logic ranking; catches upward imports, unit-tested), the v0 test + coverage gate (`bin/coverage_check.dart`, incl. the 05a conformance suite), app `analyze`/`test`, the Windows build, and a tracked-file `sk-ant-` scan — failing on any. The ratchet-only conformance-count compare (step 7) and the hosted runner remain.**

---

## 9. Property/Fuzz & Adversarial Robustness

**Status: built.** Two complementary harnesses, both hermetic and both reproducible:

- **Property/fuzz (`pipeline_test.dart`):** seeded randomized sweeps through the *entire* pipeline — 200 random task descriptions and 60 random run distances survive route → resolve → execute → persist → reload with the value intact. Seeded `Random` keeps failures reproducible (P9.6); the sweeps catch the edge cases enumerated tests structurally miss (the research §9.3 spirit of "arbitrary user-defined types to prove type-agnosticism" applied to arbitrary user *values*).
- **Adversarial (`robustness_test.dart`):** the router, interpreter, and `Session` must never crash or mis-interpolate on empty, whitespace-only, unicode, huge, or **injection-shaped** input — the test-side companion to Spec 02 §7.3's prompt-injection posture and `hardening_test.dart`'s hostile-model-output cases (together they cover both directions: hostile user input and hostile cloud output). Under `_NullCloud`, hostile input degrades to a clarify, never a throw — P2.8 asserted at the fuzz tier.

**[GAP — modest]:** the fuzz corpus targets tasks/runs; extend the seeded sweeps to the people-graph skills (random names/relations — unicode names especially) and to authored-capability slot shapes once the paid harness variant (§7) exists.

---

## 10. The Dogfooding Plan

Research §11.3: "Dogfooding begins the moment v1.2 is usable." The Windows build is dogfood-ready (DOGFOOD.md); this section defines dogfooding's *role in the test architecture* — which is deliberately narrow.

### 10.1 What dogfooding is for (measurement)

Dogfooding exists to measure the things CI *cannot*: the make-or-break unknowns that depend on a real human's phrasing distribution against real data (Spec 03 §7.3.4; 05d §6). The instrument is already built and tested: every turn appends `{at, utterance, source, skill, cloud?}` to the device-local `<deviceDir>/turnlog.jsonl` (`source ∈ corpus | cloud | undo | correction | authored | help | clarify | error`; `cloud` records health per Spec 04 §3.5 kinds; at v1 the conflated `source` splits into `routingSource` + `outcome` per Spec 11 §2.1 — suite-sync CS-13 — and the metrics below read off `outcome`), and `bin/turnlog_report.dart` aggregates it (unit-tested in `turnlog_test.dart` — the instrument itself obeys P9.1). The tracked metrics, in priority order:

1. **Clarify rate** — the fraction of turns ending in `clarify`. The research §2.1 "within weeks it rarely asks" promise, operationalized; the 05d simulation says ~20% cold → ~3% learned, *conditional on phrasing reuse* — the conditional only dogfood can test.
2. **Corpus-learning rate** — the *curve* of `cloud`-sourced turns converting to `corpus`-sourced for repeated intents (Spec 03 §7.3.4: "its rate, not point accuracy, is the make-or-break metric").
3. **Correction rate + what was corrected** — feeds the binary-ratchet failure-mode watch (`G-45`: over-eager learning, stale entries) that gates building the graded decay model.
4. **Cloud health mix** — how often the cloud path is degraded and by what `CloudErrorKind`, validating that the offline floor is a lived experience, not a spec claim.
5. **Emergent-types held-up-ness** — which authored/instantiated capabilities get *reused* (the research §4 bet).

### 10.2 What dogfooding is forbidden to be (validation)

P9.1, restated as policy because it is the standing directive: **no capability's correctness may rest on "Luis tried it and it worked."** The sequencing memory (`spec-complete-before-dogfood`) encodes the same discipline at project scale: build to spec — with the CI proof — first. When dogfooding surfaces a defect, the fix protocol is: (1) reproduce it as a failing automated test at the lowest tier that can express it (usually a new corpus phrasing in `router_test`/`session_test`, or a cassette input per §5.3); (2) fix; (3) the test stays forever. A dogfood bug that cannot be reproduced in the harness is a *seam gap* (some behaviour lives outside a fake's reach) and triggers a §3.1 seam review, not a shrug.

### 10.3 Dogfood → fixture feedback loop **[GAP — specified]**

The turnlog is a stream of *real* `(utterance → routed skill, corrected?)` pairs — precisely the recorded test-pairs Spec 03 §7 wants. Specified loop, to build alongside the beta: a periodic pass promotes (a) corrected turns and (b) novel `cloud`-routed phrasings from the turnlog into `fixture_inputs.dart` / the router corpus tests (utterances only — never slot values or record content, per the slot-shapes-only privacy rule and Spec 03 §5.6's sensitive-skill exclusion, which applies to test fixtures exactly as it does to escalation context). Real usage thereby hardens the regression suite instead of evaporating.

---

## 11. Decision Record

Consensus and code-realized decisions first, then what remains genuinely open.

### 11.1 Resolved

- **D1 — The standing directive is the first principle: automated tests give real product-level validation; nothing is validated only by manual dogfooding (P9.1).** Source: Luis, HANDOFF directive #1. Realized project-wide; dogfooding is scoped to measurement only (§10.2).
- **D2 — Every OS/network-facing capability ships behind a seam with a fake (P9.2).** Realized: `StorageRepository`, `CloudClient` (+ taxonomy §3.2), `NotificationScheduler`/`FakeScheduler` (`v0/lib/reminders.dart` — the reference execution). Normative for all future surfaces (speech next). Only the razor-thin real shim gets a one-time human smoke.
- **D3 — Offline determinism is proven by throwing fakes.** The `_NoCloud` pattern is the required harness for any flow claimed offline (§3.2). Realized across `session_test`/`spec05a_test`/`reminders_test`/`people_test`/`f07_nested_fact_test`.
- **D4 — Cloud-path tests replay recorded reality; the cassette's re-record trigger is `invSig`.** The VCR pattern (`v0/lib/replay_cloud.dart` + `v0/test/fixtures/cloud.json` + `bin/record_fixtures.dart`), with the capability-inventory signature in every routing key so an inventory change mechanically forces a re-record, and missing fixtures throwing rather than faking an outage (§5). Realized. Generative output is deliberately **not** cassette-backed (dynamic grounding) — tested via the `_GenCloud` echo fake instead.
- **D5 — Spec completeness is the measured 05a conformance count N/60**, exact utterances, skips carrying actionable reasons, equivalent-phrasing passes still counted as skips (§7). Realized (`v0/test/spec05a_test.dart`, `G-47` closed); currently **20/60**. Release milestones cite this number and nothing else.
- **D6 — Integration-first storage; fakes prove seams only (P9.7).** Reconciles CLAUDE.md's "don't mock the database" with the seam discipline: the default harness is real temp-dir storage; the in-memory `StorageRepository` fake appears only in seam-proof tests. Realized (`session_test.dart`).
- **D7 — Hermeticity mechanics are fixed:** `makeTempDataDir()` isolation, frozen `2026-07-06T09:00:00` clock, seeded fuzz (§1 P9.6). Realized (`v0/test/helpers.dart` et al.).
- **D8 — The cassette is the v1 recorded-test-pair methodology of record;** the fuller Spec 03 §7 `TestPair`-with-`NluContext` harness lands with the context features it exercises, seeded from dogfood turnlog pairs (§5.4, §10.3).
- **D9 — Coverage tiers and gate content are as §8.3/§8.4:** Tier A ≥90 / Tier B ≥80 / Tier C ≥60 / global ≥80, ratchet-only, §9.3's exclusions; the gate additionally runs analyze, both suites, import-lint layering, the debug build, and a ratchet-only conformance-count check. (Decision made here; construction is O1.)

### 11.2 Open

- **O1 — Build the coverage instrumentation + gate (§8).** The research §9.3 "from the first commit" commitment is ~1300 tests overdue; the biggest documented gap in this spec. Includes the import-lint gate and the local-pre-push-vs-hosted-CI bridge. Log in 05b.
- **O2 — Paid-tier conformance harness variant (§7):** run P-01…P-20 against `ReplayCloud` so 20 of the 60 stop being skipped-by-definition; plus the generated (not hand-synced) tally and the skip-audit rule.
- **O3 — Missing E2E paths (§6.2):** voice round-trip (blocked on the voice spike + `SpeechInput`/`SpeechOutput` seams), session-routed generative kinds, automation → Review Feed, restart-surviving undo, multi-device merge (P2). Each becomes a tier-4/10 harness the moment its feature lands — features and their E2E arrive together (P9.1).
- **O4 — Widget-tier growth (§6.3):** from 8 tests to one-per-archetype (pending Spec 07) + one-per-failure-surface. The designated thinnest area.
- **O5 — Turnlog → fixture promotion loop (§10.3):** the mechanism that converts dogfood reality into permanent regression pairs, under the slot-shapes-only privacy rule. Needs a beta's worth of data to be worth automating.
- **O6 — Fuzz-corpus extension (§9):** people-graph and authored-shape sweeps.
- **O7 — Threshold recalibration cadence:** first ratchet review after one quarter of measured coverage (per §8.3); ties to O1.
- **O8 — Cross-spec reconciliations for a later pass:** (a) ✅ **resolved (suite-sync CS-13):** the v1 turnlog carries two fields — `routingSource` (Spec 03 §2.5's enum verbatim, membership owned there) and `outcome` (`dispatched | clarified | corrected | undone | refused | error | out_of_domain`); Spec 11 §2.1 is the landing zone and §10.1's metrics read off `outcome`; (b) research §9.3's "mock StorageRepository and mock IntentClassifier" phrasing vs D6's integration-first rule — the research sentence should read as *seams exist*, not *mocks are the default*; (c) 05a-rig eval harnesses (`eval_routing.py`, `eval_retrieval.py`) sit outside this spec's pyramid — decide whether their datasets feed the §5 cassette inputs or stay research-only.
