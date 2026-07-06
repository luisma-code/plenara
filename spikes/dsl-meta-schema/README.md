# Phase-0 Spike: DSL / Meta-Schema Viability

**Throwaway** de-risking spike (CLAUDE.md bring-up order: "Phase 0 → DSL/meta-schema viability first — hand-encode 3 diverse tasks"). Not production code; the goal is to find dead-ends in the DSL / meta-schema design before committing to the real Dart codebase.

## What it proves

The core bet — **"capabilities are data, not code"** — for 3 deliberately diverse tasks, each hand-encoded as JSON and run through a fixed interpreter.

- `types/*.json` — 5 type definitions as data (task, contact, contact_fact, contact_relationship, workout).
- `skills/*.json` — 3 skills as closed-vocabulary DSL data.
- `interpreter.py` — a **two-phase** interpreter (per Spec 02): `resolve()` is a pure function of `(skill, slots, store)` that mints ids, evaluates control flow, validates writes, and returns a flat concrete plan **without mutating the store**; `execute()` applies it.
- `run_spike.py` — drives the tasks and asserts outcomes. **`python run_spike.py` → 4/4 checks pass.**

The 3 tasks were chosen to stress different mechanics:
| Task | Exercises |
|---|---|
| `create-task` | `write_record`, `compute` (now/format_date), `format`, **schema default** (`completed=false`, G-02) |
| `remember-person-fact` (Mia is Sarah's daughter, allergic to peanuts) | `read_one`, `branch`, **resolve-or-create** (G-12), 3× `write_record`, **entityRefs by resolved id** (G-17) |
| `count-runs-this-week` | `read_many`+filter, `set`, `foreach`, `branch` (date ≥ week-start), `compute` accumulate, `format` — **read-only** |

Together they cover **8 of the 10 primitives** (all but `read_related`, `delete_record`) plus schema defaults, resolve-or-create, and entityRefs.

## Findings

1. **✅ Capabilities-as-data holds.** Types and skills are pure JSON; the interpreter is fixed code that never generates or evals anything. The closed vocabulary expressed all three diverse tasks with no "just this once" escape hatch. This is the Apple-2.5.2 load-bearing bet, and it survives contact with real tasks.
2. **✅ The resolve/execute split survives real control flow.** `resolve()` evaluates `branch` and `foreach`, mints ids, and produces a flat, concrete, **inspectable** action plan without touching the store — then `execute()` applies it. This is what makes act-then-describe safe: the plan is reviewable *before* any write, and (for creates) the minted ids + before-images are captured at resolve. Validated end-to-end.
3. **🔑 G-17 must be a *static* check, not a runtime one — the key finding.** The entityRef-integrity rule ("an entity field must be fed by a resolved id, not a raw name") **cannot** be enforced at runtime: a resolved id (`contact-0002`) and a raw name (`Mia`) are **both strings**, indistinguishable by type. The first implementation tried an `isinstance(str)` runtime check and it silently passed the bad case. The correct gate is a **static dataflow check on the skill definition**, run at authoring time: an `entity` field must be fed by a record reference (`{ref: recordVar}` / `{field:[recordVar,'id']}`) whose source is a `read_one`/`write_record`, **never** a bare input `{var}`. This sharpens Spec 02 §6.4 (semantic validation = dataflow analysis of the def, not type-checking of runtime values), and it is now folded back into the spec.

## Limitations (it's a spike)

- Python, not Dart — validates the **data format + interpreter semantics**, not Flutter/platform specifics (a Dart port is a separate spike).
- Creates only; **update-writes, before-images-for-update, the undo journal, and persistence** are not built (in-memory store).
- `read_related` and `delete_record` not exercised; the `compute` expression set is a small structured subset of Spec 02 §3.7.
- Slots are hand-supplied (no NLU) — this spike is the *interpreter* bet, not the *routing* bet (that's the §13 evaluation + the local-routing spike).

## Verdict

**Green on the DSL/meta-schema viability bet.** The closed vocabulary expresses diverse tasks; the two-phase interpreter is deterministic and produces a reviewable plan; the one design refinement it surfaced (G-17 = static) is real and folded back. **Proceed to the remaining Phase-0 spikes** — the iOS file-sync spike (the riskiest infra bet, Fable D-1) and eventually a Dart port to catch platform issues.
