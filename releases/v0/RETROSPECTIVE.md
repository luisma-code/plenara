# v0 — The Box Demo

**Release point:** `920a836` — 2026-07-06 ("docs: record v0 built + tested")
**Runnable:** console only (`v0/bin/plenara.dart` — REPL / `--demo` / one-shot). No GUI yet.
**Span:** `c5dacbe` (2026-06-07) → `920a836` (2026-07-06), 28 commits.

## What this version is

v0 is the walking skeleton: a pure-Dart console program in which the *entire* Plenara design
runs end to end for the first time. One typed utterance travels through every layer boundary —
route → resolve → execute → persist → describe — against real seed data on real disk. At the
release point it has:

- **The Skill Interpreter** — two-phase resolve/execute over a closed 10-op DSL vocabulary,
  with the static G-17 entityRef dataflow validator gating every skill at load. Skills and
  types are pure JSON ("the boxes"): capabilities are data, not code.
- **The routing cascade of Spec 03 §7.3** — corpus fast-path (slot-abstracted templates
  compiled to typed regexes, deterministic date/quantity/entity resolvers), a bge-small
  retrieval fallback (multi-vector, margin-gated, clarify-on-weak), a Haiku residual router
  (full-inventory, BYOK), and the corpus-learning ratchet: a phrasing that cost a cloud call
  once is free forever after.
- **Act-then-describe with its safety net** — undo via before-images, and the correction path
  ("no, I meant to X") that undoes and redoes through the normal cascade.
- **Authoring / emergent types** — "start tracking my water intake" makes Claude author a
  {type, skill} pair in the closed vocabulary; static validators gate it; a validate→retry
  loop (G-29) feeds the exact error back once; a deterministic Layer-1 safety floor (G-30)
  refuses harmful framings before any cloud spend.
- 5 seed types, 8 seed skills (tasks, runs, moods, people-facts), multi-record queries
  (list-tasks, recall-facts), and a first 9-test `dart test` suite locking the spine in.

It is a demo in the honest sense — sequential ids, single-turn undo, a corpus of a few dozen
templates — but nothing in it is faked. Every bet the specs made is exercised in running code.

## The journey: how we got here

v0 was not the beginning of the work; it was the *verdict* on a month of research and a week
of unusually disciplined validation. The repo starts with a placeholder readme (2026-06-07)
and then, on 2026-07-05, lands the whole intellectual foundation at once: the locked research
doc (v0.10 — vision, the twenty marquee tasks, the "capabilities grow as data" thesis) and
Specs 01–05a (`c25e5e1`) — meta-schema, Skill DSL, NLU/intent, architecture, functional flows,
and the 60-example validation corpus.

**Trace-before-build.** The first substantive act (`ed207b4`) was to refuse to write app code.
Spec 05a Phase 3 traced all 60 functional examples end to end — utterance → NLU → routing →
DSL → interaction → response, in both authored-on-the-fly and predefined variants — grounded
in real model measurements on a local rig (`05a-rig`). The traces ran "define-as-we-trace":
where a spec was silent the trace defined the artifact and filed a gap, producing the
05b gap register (G-01..G-33). Three measured outcomes bent the design permanently:

1. **The authoring bet holds** — a closed-vocabulary DSL is authored reliably for simple
   skills; complex ones need structured output + validate-retry + a pinned model (G-29).
2. **The local generative router is dead.** No small on-device model cleared 49% routing
   accuracy (G-20). The originally-planned llama.cpp 1B–3B router was cut from the trusted
   path — replaced by the deterministic cascade (corpus + retrieval-margin + typed slot
   extractors, Haiku residual, clarify offline) that v0 then implemented verbatim.
3. **Safety is model-version-dependent on borderline cases** → the 3-layer defense-in-depth
   design (G-30), of which v0 ships the deterministic Layer 1.

**The independent review, and a second measurement that hurt.** Claude Fable 5 was run as a
fresh reviewer over the full corpus (05c, 11 ranked findings; `902fb86`). Its biggest catch
was epistemic: the G-20 eval had pre-supplied correct candidate sets, flattering the router.
Re-measured honestly, retrieval is a candidate *generator*, not a router — top-1 40–47%,
recall@5 76–80%, no viable margin operating point. Cold-start routing is clarify-heavy, and
the corpus-learning *rate* became the declared make-or-break UX metric (G-38, Spec 03 §7.3.4).
Fable then designed a clean-slate slate of routing candidates (05d), which was evaluated
independently (`02a384e`, E1–E5, held-out utterances from a different model to avoid style
leakage): **adopt** multi-vector retrieval + synthetic anchors (80% top-1 / 96% recall@5) and
Haiku full-inventory for online cold-start (94%); **reject** the deterministic act-type gate
as overfit (−15 pts held-out); the E5 learning-curve simulation showed friction falling
20%→3% as habitual phrasings are learned — conditional on real per-user reuse, testable only
by dogfooding. This adopt/reject discipline — design by one model, evaluate by another,
measure on held-out data — is the reason v0's router shape never had to change afterward.

**Two decisions with long shadows.** First, privacy vs durability (`db85d59`): the journal
and sensitive content had been spec'd device-local; Luis ruled that trading a privacy leak
for *data loss on device loss* was the worse failure. Journal and sensitive records sync like
any record; provider-unreadable encryption (Spec 01 §8.7 CryptoBox) is deferred and stated
honestly (G-37). Second, storage (`1ad5ce8`, storage-sync-assessment.md): a per-device
event-log proposal was assessed by Fable and rejected in favor of the middle path — per-record
current-state JSON files in the user's own cloud folder (no backend, no subscription), made
mergeable with a **state-based CRDT**: per-field HLC+deviceId stamps, field-by-field merge,
losers surfaced in `_meta.conflicts`, never silent.

**Phase-0 spikes: prove it throwaway-cheap.** Spike #1 (`87e96b3`) hand-encoded three diverse
tasks as JSON and ran them through a throwaway Python interpreter — GREEN, 4/4, with one design
refinement that mattered: the G-17 entityRef check *must* be a static dataflow check, because a
resolved id and a raw name are indistinguishable strings at runtime. Spike #2 (`c7fb12b`)
property-tested the CRDT merge 200/200 (idempotent/commutative/associative — replicas converge
under unordered, at-least-once file delivery) and surfaced two findings: precise conflict
*surfacing* needs per-field version vectors (convergence is the CRDT; the conflict list is
best-effort), and full-scan startup is slow even on a desktop SSD, so a bootstrap cache is
required on every platform — which also shrank the deferred, hardware-gated iOS risk. The iOS
file-sync spike remains the one Phase-0 question a Windows box cannot answer.

**Then, build.** The decision recorded in `697dcad` was explicitly *build now, don't finish
specs 6–11 first* — the remaining risks were empirical, and the spikes had shown that
unvalidated specs bake in wrong assumptions. The Dart SDK went into a gitignored `.tools/`,
and over one long day the skeleton grew in disciplined increments, each commit a working
program: interpreter port → real corpus router + date resolver (`b0418cb`) → undo (`430f0dd`)
→ retrieval fallback, which honestly reproduced the measured weakness live (`6daf21b`) →
capability growth as pure data (`60d4968`) → REPL (`976b03c`) → Haiku residual (`6ff8f1b`) →
the learning ratchet, demonstrated live: "jot down that I need to buy milk" costs one cloud
call, then "jot down that I need to call mom" fast-paths free (`f54b3e5`) → authoring
end-to-end (`1b82fa8`) → correction (`3ea77fb`) → the safety floor (`e7d7bf3`) → validate-retry
(`69bc13e`) → tests (`e89a940`) → multi-record queries (`17af4c1`). The very first run
surfaced and fixed a real skill bug (create-task assumed a due date), which was taken as the
skeleton earning its keep.

Notable dead-ends and redirects of the era: the local-model router (measured dead, cut); the
act-type routing gate (rejected as overfit); device-local journal (reversed for durability);
per-device event logs (rejected for the CRDT middle path). Each is written down where the
next person will trip over it — that habit starts here.

## What shipped

- Specs 01–05 + 05a/05a-traces/05b/05c/05d + storage-sync-assessment; research doc locked.
- The 05a measurement rig and `research/spec-05a-phase3/` findings (§10–13).
- Phase-0 spikes: `spikes/dsl-meta-schema/`, `spikes/storage-crdt/`, PHASE-0-STATUS.
- The v0 Dart engine: interpreter + validators, corpus router + resolvers + learning,
  retrieval client, ClaudeClient (residual routing + authoring), CRDT-format store, undo/
  correction, safety floor, console REPL, 5 types / 8 skills as data, 9 tests.
- CLAUDE.md working-mode rule ("never ask permission to proceed") — the process decision
  that shaped every later session.

## Known gaps at release

No GUI, no voice, no iOS (toolchain/hardware-gated, recorded in 05b). Sequential record ids;
single-turn in-memory undo; no reminders, people-interaction loop, or generative features;
authoring hardening (structured output, pinned model) deferred to the paid tier; safety
Layers 2/3 deferred; retrieval requires an optional local embed server; the CRDT merge
*engine* deferred to P2 (format is merge-ready). The corpus is small and the clarify rate
correspondingly high — by design, this is what the learning loop exists to fix.

## Toolchain / runnable note

Console-only. Runs with a local Dart SDK (`.tools/dart-sdk`); `dart run bin/plenara.dart`
from `v0/`. No Windows .exe exists at this point — a GitHub Release for v0 would be a source
archive or a `dart compile exe` artifact, not a GUI binary.
