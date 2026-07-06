# Plenara v0 — Walking Skeleton

The **real codebase** starts here (not a throwaway spike). A text-first Dart console app that runs a full turn through every layer, on Windows. Voice and the Flutter UI are later layers; this proves the *spine*.

## Run

```
# Dart SDK (this repo uses a local one under .tools/, gitignored):
Z:/code/plenara/.tools/dart-sdk/bin/dart.exe pub get
Z:/code/plenara/.tools/dart-sdk/bin/dart.exe run bin/plenara.dart
# or pass your own utterance:
dart run bin/plenara.dart "add water the plants to my list"
```

## What it proves

Every layer boundary connects, in the production language:

**utterance → route → resolve → execute → persist → describe**

- **Capabilities are data** — 5 types + 3 skills load as JSON from `data/`; the interpreter is fixed Dart code (`lib/interpreter.dart`), ported from the validated Phase-0 spike.
- **Static authoring gate** — every skill passes `validateSkill` at load (Spec 02 §6.4, incl. the static G-17 entityRef check) before it can run.
- **Two-phase resolve/execute** — `resolve()` is pure and returns a concrete plan; `execute()` applies it. Handles `branch`, `foreach`, resolve-or-create, entityRefs by resolved id.
- **Storage = per-record JSON + the CRDT `_meta` block** (`lib/store.dart`) — each write persists as `{id, typeId, fields, _meta:{stamps, conflicts}}` with per-field HLC stamps, the exact format the storage-crdt spike validated. Single-device here; the merge engine is P2.
- **Act-then-describe** — the turn executes and speaks one past-tense sentence.

The three demo turns exercise a simple write, a multi-write resolve-or-create with entityRefs, and a read-only `foreach` aggregation.

## Real vs. stubbed (honest map)

| Layer | State |
|---|---|
| Skill interpreter (Spec 02) | **Real** — two-phase, static-validated, 8/10 primitives |
| Storage + CRDT format (Spec 04 / assessment) | **Real** — per-record files, `_meta` HLC stamps |
| Turn pipeline / act-then-describe (Spec 04/05) | **Real** (thinned) |
| Types + skills as data (Spec 01/02) | **Real** — JSON in `data/` |
| **Router** (Spec 03) | **Real** — corpus fast-path (templates as data, `data/corpus.json`) + deterministic slot extraction + date resolver (§6.2); **retrieval fallback** via bge-small (multi-vector max-sim, top-1-with-margin). Faithful to §13: retrieval is weak, so a low-confidence result **clarifies** rather than mis-acting. |
| **Undo** (Spec 02 §5.4 / 04 §3.11) | **Real** — before-images captured at execute; `undo` reverses the last turn in memory + on disk. Full execution journal + multi-turn ring: later. |
| Voice (STT/TTS) | Not yet — text-first |
| CRDT **merge** engine | P2 (single-device now) |
| Retrieval embedder | Real via local llama-server (bge-small on :8091); in-process model on device later |
| Flutter UI | Console for now |
| Claude authoring (define_*) | v2 |

## Findings so far

- The skeleton immediately surfaced a real skill bug — `create-task` assumed a due date and printed `{dueLabel}` when the utterance had none. Fixed by branching on the optional slot (`data/skills/create-task.json`) — demonstrating the DSL is iterable and the skeleton catches design gaps cheaply, exactly its purpose.

## Next increments (in order)

1. ✅ **Real router** — corpus fast-path + bge-small retrieval + date resolver (done).
2. ✅ **Undo** — before-images + reversal (done).
3. **Corpus learning loop** — an uncorrected turn / a correction appends a corpus entry (§5.2), so a rephrasing that once clarified now fast-paths. This is the §13 make-or-break mechanism, in code.
4. **More seed skills/types** — grow the free-tier surface (e.g. `log-run` to fix the query-vs-log act-type confusion retrieval showed).
5. **Flutter UI** — wrap the console spine; then voice.
6. **First iOS build** — closes the one deferred storage question (dataless-file cold-start).
