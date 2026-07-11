# v3 — Spec-Complete

**Release point:** `3828ecb` — 2026-07-08 ("docs(handoff): diagnostics dogfood-ready; F-03/F-16/mul-div-round/P-18 + KB spec 13")
**Runnable:** Windows GUI (.exe) + console.
**Span:** `605367c` (2026-07-07) → `3828ecb` (2026-07-08), ~60 commits.

## What this version is

v3 is the version where the *architecture finishes itself*. Every named Spec 04 business-logic
component now exists in code — DispatchOrchestrator, SkillInterpreter, SchemaRegistry,
**MigrationRunner** (migrate-on-read schema evolution), AuthoringService with the full consent
loop, ExecutionJournal, **AutomationRunner** (onWrite triggers + cron schedules + the Review
Feed), GenerativeService (all six kinds routed), AttentionSurface. The spec suite itself is
complete: Specs 06–12 written, cross-reviewed, and reconciled twice. Conformance against the
60 worked examples is no longer a feeling but a **measured, ratcheted number** (22/60 offline,
up from ~1 at the audit). The app grew its first non-chat surfaces: a "Your data" view that
renders records by *structural archetype* (no per-type UI code), a tappable detail sheet, an
actionable checklist, an automations card, and an in-app Settings screen for the BYOK key —
the last hand-edit-a-JSON step gone. A local quality gate (`tool/precheck.sh`) enforces
analyze, import-lint layering, coverage (measured 91.4–91.5%, floor 80%), the app build, a
secret scan, and the conformance ratchet. 1,449 Dart + 25 widget tests, 36+ seed skills, 5
tracker templates.

## The journey from v2

**Luis's standing order shaped this whole version: build to spec *before* dogfooding.** The
temptation after v2 was to go live; the instruction (recorded in memory and handoff) was to
finish the remaining top-10 and the spec surface first, so that dogfooding would test a
complete design rather than an improvisation.

**The consent boundaries landed first.** Authoring gained the spec's load-bearing
design/commit boundary — nothing registers until the user says "activate" (`605367c`, G-18) —
and then the DF-01 *offer* gate in front of that: the paid authoring call itself is not spent
until the user says yes (`e6229a8`). Between them sits the free tier's whole shape: built-in
recognizer → template instantiation → only then a paid offer. The **template library**
(`04fafcb`) is the piece that made "start tracking my water intake" free — a shipped bundle of
types + skills + corpus that instantiates locally with no cloud call, immediately routable by
voice; reading, medication, steps, and weight followed as pure data, and templates learned to
ship *query* skills too ("how many steps this week", "did I take my meds today?").

**Corrections completed.** F-14 — called out in 05a as "the single most important correctness
example in the free set" — re-classifies a mistyped log ("no, that was a walk") by reversing
the before-image and re-dispatching with carried slots; F-15 updates the same record in place
("actually, 28 minutes") (`073eae9`, `7b96daa`). Recurrence grew stepwise — daily, weekly,
biweekly (phase-anchored so "every other Tuesday" never lands off-week), then ordinal-monthly
with a new `ordinal_num` fn — all at the projection layer (regenerate-on-open), so the
scheduler and reconcile logic never changed. Deterministic denial floors filled out the DP
tier: scope ("text Marco for me" → an honest "I'm not connected to messaging — I can set a
reminder"), medical, impersonation, schema-edit, each anchored against false positives.

**The measurement instrument for "done".** G-47 became the 05a conformance harness
(`cfc34bc`): each of the 60 examples runs its exact utterance offline and asserts, or skips
*with a reason* — turning "complete per spec" into 9/60, then a worklist, then 22/60 by the
release point, with a ratchet file so the number can never silently regress. The harness paid
for itself immediately: it found phrasing gaps where capability existed but wording didn't
route (F-05, F-10), refined F-13's skip into a documented product decision, and produced the
honest finding on F-08 that the blocker was flexible fact-query NLU, not the DSL (`9220ac0`)
— an investigation whose skill was deliberately backed out rather than shipped over-matched.

**The spec suite completed itself in parallel.** Six Fable agents wrote Specs 06–11
simultaneously, one per spec, each grounded in the running v0 code (`2085f7b`); the
cross-spec review (05f) then read all eleven together and found the characteristic defect of
parallel authorship — "reconciled-in-one-home" staleness — plus two genuine code blockers:
the per-install **deviceId and the turnlog lived inside the synced folder** (a synced deviceId
silently defeats the very HLC tie-break the sync design rests on; the turnlog was
content-bearing telemetry re-uploaded every turn). Both were fixed with a device-local
`deviceDir` (`d956390`). Spec 12 — Voice was chartered because three specs cited a "Spec 06 —
Voice" that had never existed. Two suite-sync passes (`5b2fc47`, `f13908d`) reconciled the
contradictions — enum ownership, the authoring model's single home, the safety build-status
banner — and 05f gained a RESOLVED/PARTIAL/OPEN status column. Spec 13 (reference knowledge
bases) was written as a design memo with a verdict: do it, as a general mechanism justified
on offline coverage and determinism, not the weak API-cost argument.

**Two whole subsystems were built by delegated Fable agents** and wired in at single seams:
the AutomationRunner (onWrite conditions fire skills through the interpreter, gated by plan
shape — read-only delivers out-of-band, writes are HELD for conversational approve/dismiss,
destructive refused; `daae0c5`, `00c4552`), completed by a minimal 5-field cron evaluator
with catch-up-on-open semantics (`576aa1c`, `99b9c98`); and migrate-on-read schema evolution,
dormant until any type bumps its version, then automatic (`6406c00`, `d92a102`).

**The gate closed the loop on trust.** Coverage was measured for the first time (91.4%);
import-lint made the CLAUDE.md layering promise mechanical; `precheck.sh` bundled all of it
into the solo pre-push path Spec 09 §8.4 describes. The version ends with diagnostics
declared dogfood-ready: a bad turn's log line now carries *why* a miss happened and what any
automation did unattended (`5f972c6`) — the precondition for the live era that starts in v4.

## What shipped

- Authoring preview→activate + DF-01 offer gate; template library (5 trackers + queries).
- F-14/F-15 corrections; daily/weekly/biweekly/ordinal-monthly recurrence; denial floors.
- Compound-utterance splitting (F-13); nested people-fact (F-07); value-type align (G-40).
- Specs 06–13 written; 05f cross-spec review + two suite-sync passes; deviceDir fix.
- AutomationRunner + cron + Review Feed; MigrationRunner; all Spec 04 BL components exist.
- "Your data" archetype view, detail sheet, actionable checklist, automations card, Settings.
- Conformance harness + ratchet (22/60); coverage gate 91.4%; import-lint; precheck.sh.
- mul/div/round DSL fns; goal type + goal-progress (P-18 offline); miss-diagnosis telemetry.

## Known gaps at release

The paid tier had still never run live (BYOK key not yet in config — that is v4's opening
act); voice unbuilt (seam only); the P-tier of the harness 0/20 pending cloud; interval RRULE
beyond ordinal-monthly, safety Layer-2/3 model gates, at-rest encryption, the CRDT merge
engine, and a hosted CI runner all deferred with reasons. First-run seeding still reads from
the dev path — bundling `v0/data` as Flutter assets is the noted pre-distribution task.

## Toolchain / runnable note

Windows GUI (.exe) + console. Builds via `flutter build windows`; precheck.sh is the quality
gate. Suitable for a GitHub Release binary (note the dev-path seeding caveat above).
