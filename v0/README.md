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

## Tests

**897 tests, hermetic (no network), `dart analyze` clean** — `dart test`.

| Suite | Count | Layer hammered |
|---|---|---|
| `router_test.dart` | 453 | NLU/corpus — hero phrasings × 30 descriptions, all 22 date forms, slot extraction, learning, documented fast-path limits |
| `pipeline_test.dart` | 265 | full route→resolve→execute→persist→reload→undo + 260 **seeded-random fuzz** cases |
| `interpreter_test.dart` | 111 | primitives, every skill via NLU slots, defaults/required, the static gate (accept + reject), error paths |
| `cloud_test.dart` | 33 | residual routing + authoring via the **recorded cassette** (no live Haiku) |
| `session_test.dart` | 25 | end-to-end offline turns, cross-skill write→read, undo/correction, cross-instance persistence |
| `store_test.dart` | 10 | on-disk CRDT shape, per-field HLC stamps, HLC monotonicity, `undoTurn` |

**Cloud cassette (record/replay).** Tests never call Haiku. Real responses for a fixed input set (`lib/fixture_inputs.dart`) are recorded once into `test/fixtures/cloud.json` and replayed via `ReplayCloud` — deterministic and free, yet still exercising the real routing/authoring *code* against genuine model outputs (so it catches real schema drift; a recorded `null` replays as null, an unrecorded input throws loudly). Refresh after changing the inputs:

```
dart run bin/record_fixtures.dart   # one BYOK Haiku pass, then commit the fixture
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
| Voice (STT/TTS) | Not yet — **gated on setup**: Flutter speech plugins (`flutter_tts`, `speech_to_text`) are native plugins that need **Windows Developer Mode** enabled (plugin symlinks) + audio hardware to verify. The text path is the same `Session` seam voice will plug into. |
| CRDT **merge** engine | P2 (single-device now) |
| Retrieval embedder | Real via local llama-server (bge-small on :8091); in-process model on device later |
| **Cloud residual + learning** (Spec 04 §3.5 / §5.2) | **Real** — `ClaudeClient` Haiku full-inventory residual routing (§13 E4); a cloud-routed turn **learns** its template so the next similar phrasing fast-paths with no cloud call (the §13 "gets better" ratchet). BYOK; offline/keyless → clarify. |
| **Flutter UI** (P2) | **Real** — a Flutter **Windows desktop** app (`../app/`) depending on the v0 `plenara` package; a Material chat UI over the shared `Session` engine (`lib/session.dart`). `flutter build windows` → `plenara_app.exe`. Run: `.tools/flutter/bin/flutter run -d windows` in `app/`. |
| **Authoring / emergent types** (Spec 02 §6) | **Real** — "track my X" → Claude authors a type + skill *as data* → the static validators gate it → it registers → it works. The whole "AI authors, code executes, capabilities are data" thesis, live. (Independent safety review `G-30`: v2.) |

## Findings so far

- The skeleton immediately surfaced a real skill bug — `create-task` assumed a due date and printed `{dueLabel}` when the utterance had none. Fixed by branching on the optional slot (`data/skills/create-task.json`) — demonstrating the DSL is iterable and the skeleton catches design gaps cheaply, exactly its purpose.

## Next increments (in order)

1. ✅ **Real router** — corpus fast-path + bge-small retrieval + date resolver (done).
2. ✅ **Undo** — before-images + reversal (done).
3. ✅ **Haiku residual router + corpus learning loop** — the full §13 cascade + the "gets better" ratchet, in code (done).
4. ✅ **More seed skills/types** — `log-run`, `log-mood` (done).
5. ✅ **Authoring / emergent types** (`define_*`) — Claude authors a type+skill, validators gate it, it registers and runs (done).
6. **Correction path** — `recordCorrection` (§5.2): "no, I meant X" zeroes the wrong entry and learns the right one; the strong learning signal.
7. **Structured-output hardening for authoring** — pin the step schema + validate→retry (`G-29`) so complex authored skills don't drift; a `G-30` safety pass before activation.
8. ✅ **Flutter desktop UI** — a real Windows app (`../app/`) over the shared `Session` engine; builds to `plenara_app.exe` (done). *(Flutter accepts the installed VS Build Tools 2019 — the earlier "needs VS 2022" note was wrong.)*
9. **Voice (STT/TTS)** — the P2.1 uncompromising-voice layer. **Gated:** the Flutter speech plugins need **Windows Developer Mode** on (native-plugin symlinks) + audio hardware to verify. Plugs into the same `Session.handle` seam the UI/console already use.
10. **First iOS build** — closes the one deferred storage question (dataless-file cold-start); needs Apple hardware.

**State:** on this Windows box the v0 *logic spine and a desktop GUI* are built and tested — everything except voice and the iOS build. The two remaining leaps are each gated on a real external prerequisite (Windows Developer Mode + audio for voice; an iPhone for iOS), not on unresolved design. Run the console: `dart run bin/plenara.dart`. Run the GUI: `.tools/flutter/bin/flutter run -d windows` from `../app/`.

## The thesis, demonstrated

This v0 already exercises essentially the whole Plenara design end-to-end, in real Dart: capabilities as data, a two-phase static-validated interpreter, the full §13 routing cascade (corpus fast-path → Haiku residual → clarify), the corpus-learning ratchet (the §13 make-or-break), act-then-describe + undo, per-record CRDT-format storage, and **AI authoring of new capabilities that validate, register, and run.** What remains is hardening, voice, the UI, and the iOS build — not unproven bets.
