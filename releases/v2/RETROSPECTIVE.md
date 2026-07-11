# v2 — The Daily Companion (dogfood-ready)

**Release point:** `8cfce8a` — 2026-07-07 ("docs(handoff): ATL/toast done; remaining Luis-gated item is credential rotation")
**Runnable:** Windows GUI (.exe) + console. Reminders fire as real OS toast notifications.
**Span:** `ea9fddd` → `8cfce8a` (2026-07-07, one immense day), ~100 commits.

## What this version is

v2 is the moment Plenara stops being an engine demo and becomes an assistant a person could
run on their own life. At the release point the app: points at a user-chosen synced folder
with a BYOK key (config + first-run seeding); measures itself (a per-turn telemetry log with
full debug traces); sets, lists, completes, cancels, and snoozes **reminders that fire as
native Windows toasts**; carries a complete **people loop** — facts, aliases-in-embryo,
relationships (both directions), interactions, "when did I last talk to X", birthdays, and
on-open birthday nudges; keeps a due-tasks agenda; recalls moods; holds a resumable
**slot-filling dialogue** (ProvideSlot) and a **disambiguation clarify** for partial names;
tells the truth about the cloud (typed `CloudResult` — offline vs bad-key vs rate-limited,
named to the user); answers "what can you do" from its real registry; and has begun the
generative tier (grounded gift ideas, daily briefing, reconnect coaching behind fakes).
1,284 Dart tests + 8 widget tests, 32 skills. HANDOFF.md exists from this version on — the
session-arc document that makes the work resumable across process relaunches.

## The journey from v1

**First, settle the language.** The day opened with two design calls from Luis, recorded as
decisions: converge the DSL dialect spec↔code — v0's structured `{fn,args}` form (the
JSON-schema-constrainable, authoring-reliable shape) with the spec's canonical names
(`entityRef`, `confirmationText`, `reads`/`writes` envelope) (`ea9fddd`..`a80f3c9`); and ship
a single corpus file in v1, per-device split deferred to P2. Then "Track A" paid down the
reviewers' structural debts: the execution-journal ring (multi-turn undo at last), the tenth
DSL op (`read_related`), the `StorageRepository` seam (Session lost every raw `File` call —
proven by running a full session on an in-memory repository), and the corpus-learning
**negative half** — a correction now *forgets* the learned template that misrouted it
(`6b9dd65`), closing the "one bad template misroutes forever" hole. A subtle sibling defect
fell immediately after: a correction following a *read-only* misroute reversed an unrelated
earlier write (`e09e9f0`) — the first of three rounds this class of bug would take to kill.

**Dogfood enablement was Fable's priority #1** and shipped early: runtime config
(env → `~/.plenara/config.json` → scaffolded default), first-run seeding into the user's
folder, and the turnlog — because the make-or-break metric (clarify rate) had only ever been
measured synthetically, and E5's learning-curve promise needed real turns to verify.

**Then the retention hook.** Reminders (F2) were built test-first behind a
`NotificationScheduler` seam per Luis's standing directive #1 — *every OS-facing capability
ships behind a thin adapter with a fake, so the logic is CI-tested and only the razor-thin OS
shim needs a human smoke*. The armed set is **derived** from the record store and reconciled
idempotently, so undo, delete, complete, and reschedule cancel toasts for free and re-open
never double-arms (`4d30b68`). Building snooze exposed a real reconcile bug — a time change
kept the old armed toast (`6a17c15`). The native half stayed blocked on an admin-only ATL
install for most of the day; when it landed, `WindowsToastScheduler` slotted behind the
already-tested seam, and along the way two app-quality problems were *measured, not guessed*:
a ~140s startup hang (the down embed server × 70 anchors — probe once, default retrieval
off; boot fell to 103ms) and the absence of any diagnostics — fixed with `AppLog`, a flushed
timestamped log whose path the app greets you with (`daaedfb`..`e2ba8d8`).

**The people loop** — the app's actual mission — went from thin to complete: interactions and
last-interaction, birthdays (new annual-date DSL fns, month-name dates), on-open nudges
derived from records with no new skill, list-interactions, relationship queries in both
directions, forget-fact (memories must be correctable), and remember-relationship — added
after an end-to-end console smoke revealed the flagship greeting example "remember that Mia
is Sarah's daughter" fell to the cloud and failed offline (`93ecb99`). Fable's Phase 1/2
polish followed: typed `CloudResult` so the cloud seam "stops lying and stops dropping"
(cloud date slots now normalize through the deterministic resolvers — no more midnight
reminders), discoverability, the turnlog report, and partial-name matching that made the
disambiguation dialogue *reachable* instead of decorative.

**The audit that changed the plan.** Mid-day, a five-fork spec-vs-code audit corrected a
comfortable illusion: the engine spine was done, but only ~1 of the 60 05a examples passed
cleanly — four whole architecture components and most conversational NLU seams were unbuilt.
"This is weeks of build, NOT 'mostly done'" went into the handoff verbatim (`f05a73e`), with
a ranked top-10. v2 contains the program's first six items: DSL query/compute fidelity
(read_many operators/ordering/limit, aggregation and date math — retiring the foreach-MAX
hack), ProvideSlot, aliases ("Mum" → contact, resolving everywhere through the one shared
read_one), correction-prefix broadening, the OOD boundary with its personal-cue *privacy*
guard (a records query is never handed outward), the record-integrity floor (refuse to
fabricate the past), and the first GenerativeService kinds. It also fixed two live defects
the audit found: a safety-floor bypass ("build me a…" missed the trigger regex) and a
`{var}` leak in format (`c29732c`).

**Fable review #2** (05e, three lenses) then audited the sprint itself and found the P0 of
the era: every early-return path (help, OOD, generative, refusal) left the "last turn wrote"
flag stale, so a correction two turns after a write reversed the wrong record — genuine data
loss, fixed by snapshotting turn outcomes at the top of the handler (`edc4091`). Three CRDT
format flaws were fixed *before dogfooding fossilizes them in synced data* (constant HLC
deviceId; tombstone no-op on ghost records; delete-then-rename atomicity). Learned templates
were demoted to a second routing pass so they can never shadow seed skills. The validator
gained var-closure. And the review institutionalized a rule that outlived it: code→spec drift
gets a gap-register entry (G-39..G-48) in the same commit that creates it (`6a7a346`).
Its strategy lens said the uncomfortable true thing: *zero real turns had run yet* — the
blocker was a 20-minute human window (credentials + ATL), not code.

## What shipped

- Config + seeding + DOGFOOD.md; turnlog with per-turn debug traces and report tooling.
- Reminders end-to-end incl. real Windows toasts; snooze/reschedule; lifecycle guards.
- The complete people loop + birthdays + nudges; due-tasks; recall-mood; journaling; streaks.
- ProvideSlot dialogue; partial-name disambiguation; aliases; OOD boundary; discoverability.
- Typed CloudResult; GenerativeService (gift ideas / briefing / reconnect) behind fakes.
- Track A: journal ring, read_related, StorageRepository, negative-half learning.
- Review #2 fixes (P0 correction data-loss, CRDT format, template shadowing, var-closure);
  G-39..48 ledger; AppLog diagnostics; startup fix. 1,284 + 8 tests, 32 skills.

## Known gaps at release

The heavy half of the top-10 remained: authoring preview→activate, recurrence, the template
library, F-14/F-15 corrections, and specs 06–11 were still unwritten. No real turns had been
run (credentials un-rotated). Undo journal still in-memory; no data-view UI; no voice; the
conformance number stood wherever the audit left it — unmeasured, which G-47 would soon fix.

## Toolchain / runnable note

Windows GUI (.exe) via `flutter build windows`; requires the ATL VS component to compile the
notification plugin. First version whose binary is genuinely usable day-to-day (config-driven
data folder, OS notifications). Suitable for a GitHub Release binary.
