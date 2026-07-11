# Plenara — Session Handoff (pick up here)

_Last updated: 2026-07-11. Written to survive a Claude process relaunch._

## LATEST SESSION (2026-07-11) — Spec 15 "Plena" presence + versioning/releases + app integration. HEAD = `08f5313`, 1643 Dart + 38 app tests green.

Dogfood-driven engine polish, then a pivot into the UI:
- **Engine (early in session):** compound utterances (two sentences) fall through to the cloud multi-action
  path (fixed "I had dinner with X. I learned Y" logging the whole blob as a meal); interaction `kind`+`note`
  capture (dinner/place/remarks preserved); weekday abbreviations ("Sat") + "add a todo …" offline templates;
  **self-improving corpus** — the cloud now returns a surface-abstracted `template` in the same routing call,
  the router validates it by round-trip and adopts it, so date/time phrasings learn too (`learnSuggested`).
  New `v0/bin/dogfood.dart` CLI (drives the real engine; reports offline vs cloud per turn).
- **Spec 15 — The Living Presence** (Fable-authored, `planning/specs/15-presence.md`): the voice-first visual
  identity. Substrate decided by live mockup → the **particle swarm ("the murmuration")**, veil demoted to
  alternate. The being is named **Plena**. §5A symbolic **glyph vocabulary** (50 glyphs) — occasion-appropriate
  (apt-or-absent; a todo never earns a heart), glyphs-as-data, traced by the swarm then released. Interactive
  mockups were iterated as an Artifact (swarm + hue/gravity/breadth tuning + comet-trail + fly-out-and-rejoin).
- **Versioning + releases:** `releases/vX/RETROSPECTIVE.md` (v0–v6, Fable-reconstructed multi-page capsules)
  + `releases/VERSIONS.md` manifest. **Git tags `v0`–`v6` created LOCALLY.** Root scripts: `run.cmd`,
  `build.cmd`, `dogfood.cmd`, `prep-machine.ps1`. v6 package built to `app/build/plena-v6-win-x64.zip` (20.5 MB).
  **⚠ PENDING (blocked on GitHub auth — the USER must run):** `git push origin main --follow-tags`, then
  `gh release create v6 <zip> -t "v6 — The Living Presence" -F releases/v6/RETROSPECTIVE.md`. The remote is
  MANY commits behind — the push publishes the whole v4→v6 arc. Binaries stay OUT of git (GitHub Releases only).
- **Plena integrated into the app** (`app/lib/plena.dart`, `glyphs.dart`, `main.dart`): a `drawAtlas`
  particle-swarm `PresenceView` driven by real turn state (idle/listening/thinking/speaking; a "speaking"
  flourish on a reply since there's no TTS yet; D1 in-flight → D2 once a turn is clearly working → cooler,
  churning). Replaces the busy spinner. `animate:false` under an injected test session so `pumpAndSettle`
  terminates; reduced-motion honoured; a Semantics label announces her state.
- **Plena's glyph vocabulary** (`glyphs.dart`, 49 glyphs): the fly-out-and-rejoin engine (travellers fly the
  path, deposit a faint tail to hold the figure, flitter, rejoin), fired **apt-or-absent** on real occasions
  (`glyphForTurn`: completion→check, closeness-with-partner→heart, interaction→nod, streak→star, goal→target,
  journal→quill, undo→undo-loop; greeting on open→smile/candle). Long-press Plena = browse the vocabulary.
- **In-app tuning** (the Tune sheet: hue/vibrance/brightness/breadth/gravity/looseness/trail), **motion
  trails** (velocity echoes), and a **caption** that materialises the reply over Plena. Tap Plena to talk.
- **What's genuinely left for the presence:** TTS voice output (Spec 12, a separate feature), true
  comet-trail *persistence* (a ui.Image ping-pong vs the current velocity echoes), listening→mic-level
  energy, and the fuller presence-primary layout — plus aesthetic tuning, now in the owner's hands via the
  Tune sheet. App tests **48**, v0 **1643**, analyze clean.

## LATEST SESSION (2026-07-08/10) — gap-fill + cloud-router upgrade + FULL FABLE REVIEW. HEAD = `d70b96d`, 1620 Dart + 38 app tests green.

Continued well past the phrasing gaps into a live-dogfood-driven arc:
- **Cloud router upgraded** (3 phases, validated live): entity resolution (router gets the user's known
  contacts, reuses "Katherine"→"Katherine Zinger", no dup); **multi-action** ({"actions":[...]} — "dinner
  with X and Y" logs one record PER PERSON, reliable 6/6 after prompt tuning + a 200→700 token-cap fix);
  **future plans vs past** (log-plan + planned flag + upcoming-interaction; "seeing X tonight" is a plan,
  excluded from "last talked"). Relative dates now resolve against the REAL clock (model was using its stale
  training date).
- **General de-duplication** (user-reported): read_one `resolve` mode reuses an existing contact on a UNIQUE
  whole-word token match, else clarifies (>1) or creates (0); applied to every contact find-or-create.
  create-task dedups tasks (ieq + dedup_list). Merged the user's one leftover dup by hand.
- **Observability**: turnlog now traces WHICH record each read resolved to (diagnose wrong-match from the log);
  Settings "Cloud usage" panel (turns, offline/cloud split, spend/day/month, tokens, where-used, recent days);
  per-reply green dot when the cloud was used (keyed on real token spend). Free/paid mode toggle.
- **FULL FABLE REVIEW** (44 agents, 33 confirmed findings, adversarial-verified): fixed ALL 8 HIGH (resolve
  self-relationship + ambiguity-clarify, due-by null tasks, recurring reminders in date-windowed lists,
  multi-action undo-whole-turn, pastday bare-weekday backwards, _wordTime over-match, free-mode env-key leak,
  non-Map slots) + key MEDIUM (goal-dup brick→first:true, filter-validation crash, multi-action skip/exception,
  DST weekday step, cloud-dot accuracy) + LOW (thousands-comma split, reads-trace-on-throw, prompt-contact cap).
  Findings deliberately left: same-person shorter-name reuse (prevents dup), correction-after-multi edge,
  a few cosmetics. Review workflow: `.../workflows/scripts/fable-review-session-*.js`; live use-case harness:
  `v0/bin/usecase_harness.dart`.

### (earlier in the same session) phrasing-gap fill, ~28 batches. HEAD was `3e9840c`, 1599 Dart tests green.

Worked through the catalogued phrasing gaps (`planning/phrasing/*.json`), autonomous "do them all" mode.
Committed **~28 batches (~34 gaps)**, each: skill/router/interpreter change + corpus + tests + full suite green.
Essentially every free-tier gap is now closed (reminders, tasks, journal, people, logging, queries clusters).

**Shipped this session:**
- **Reminders (cluster complete):** relative-time (#43, prior), word-times "at five / half past six / quarter to seven"
  (#44), date-only → dated **task** (#45, spec-correct: a date with no clock time is a task not a 9am reminder),
  weekday-set "every weekday/weekend" (#46), multi-day "every monday and thursday" (#47), monthly-date "the 15th of
  every month" (#48), yearly "every year on march 3" (#49), date-filtered listing "what reminders tomorrow/this week"
  (#50), plural-weekday tolerance (#53), postfix "call mom tomorrow at 5pm" keeps the day (#54).
- **Tasks:** positional delete "delete the first task / task 3 / the last one" (#55), due-date filters "what's due
  tomorrow/this week/by friday" (#57), multi-task add "add milk, eggs, and bread" (#58).
- **Journal:** recall-by-date "what did I write yesterday" (#4), delete-latest-entry (#6).
- **People:** age "how old is Sarah" (years_since), dated interaction "talked to Sam yesterday / on last friday".
- **Logging:** bare mood "i'm exhausted / kind of down" (#6), meal type "eggs for breakfast" (#7), run route "ran the river loop" (#10).
- **Queries:** domain-scoped help "what can you do with reminders / how do I track water" (#10).

**New DSL / router machinery added (reusable):** compute fns `ordinal_suffix`, `weekday_nums`, `date_part`,
`time_part`, `split_list`, `position_index`, `nth`, `years_since`; `format_date` "MMMM d" + crash-safe; `read_many`
**compound (AND-list) filters** for date ranges; recurrence forms `days:<n,..>` / `monthlyday:<N>` / `yearly`;
constrained slot types **`dayword`** (forward), **`pastday`** (backward + "last <weekday>" in resolveDate),
**`posword`**, **`moodword`**, **`mealword`** — each a bounded regex so the router picks the right split without
backtracking (the #54/#11 limitation). New seed skills: set-{weekday,weekend,multiday,monthly-date,yearly}-reminder,
set-reminder-on-day, list-reminders-{on,week}, due-{on,week,by}, delete-task-at, recall-journal-on,
delete-journal-latest, contact-age.

### API-key outage (RESOLVED). Mid-session the BYOK key briefly went down (offline/malformed) — Luis rotated it and
it came back, so `bin/record_fixtures.dart` works again and new seed skills resumed. If it goes down again, only
existing-skill changes (no invSig change) can be committed until it returns.

### More shipped after the key returned (batches 16-28) — the session ran to ~28 gap batches total:
- **Reverse fact search** — "who do I know that likes hiking" (find-people-by-fact).
- **Goals** — update/clear + **set-goal upsert** (fixes the latent duplicate-goal bug): "change my goal to 60k", "delete my running goal".
- **People (cluster now COMPLETE):** neglected contacts ("who haven't I talked to in a while"), two-person relatedness
  ("how are Anna and Tom related"), **anchored predicates** ("Sarah is allergic to peanuts" — new `predword` slot,
  :contact-guarded so "France likes wine" is ignored), **self-relative** ("my sister Emma loves pottery"),
  **per-person dates/anniversaries** (new contact_date type + set/when skills).
- **Queries** — period-scoped run distance ("how far have I run this week/month" — was wrongly a COUNT), unqualified longest-streak.
- **Logging** — **runs in miles** ("ran 3 miles" → unit-aware mi→km on the SAME log-run skill via a distanceMiles input;
  cloud_test stays green — the earlier revert was a separate skill, this isn't).
- **Task de-duplication (user-reported):** create-task skips items already on the ACTIVE list (case-insensitive, new
  `ieq` filter op) and collapses repeats within a multi-add (`dedup_list`); completed tasks can be re-added.

### Remaining gaps (all lower-value / deferred)
- **Goals units/periods** (journal.json #0-2): non-running goals ("walk 10000 steps", "read 12 books", "save $500") +
  periods — deferred: setting a non-run goal is low-value with no matching data source to track progress against.
- **Paid-template internals:** weight-trend (logging #5), water-in-glasses/cumulative (#2/#3), steps/meds period aggregates
  (queries #0/#7) — inside the paid template bundles (`data/templates/*.json`), behind the paywall.
- **Agent-flagged NOT-safe / policy (skip):** "i did the laundry" (collides with activity logging), "today i {text}"
  (over-matches loggables), pushups/strength (authoring path), "scratch that, log a 5k" (no safe marker), "start a
  shopping list" (authoring path), event-relative "an hour before my meeting" (cloud path), "every second tuesday"
  biweekly ambiguity (product decision), generic slot corrections outside workouts (F-15 generalization, queries #8).

## TL;DR — where we are

The **v0 engine is complete and heavily tested**; the **Windows desktop app is
dogfood-ready** (runs on a user-chosen synced folder + BYOK key). Latest session
shipped **F2 reminders**, the **people loop** (Fable #3), **on-open nudges** (Fable
#4), and a **Fable strategic review → Phase 1 typed `CloudResult` refactor**. The
cloud seam now returns typed results (Ok/abstain vs named CloudError kinds); Session
surfaces honest failure reasons + logs cloud health per turn; cloud date/datetime
slots are normalized (no midnight/dropped reminders); the machine-specific `.env`
fallback is gone from the app path. **Fable Phase 2 is DONE too** — discoverability
("what can you do"), a turnlog report, and partial-name matching with a disambiguation
clarify ("Sam" → "Sam Rivera", or a "which one?" question). Then went DEEP on Phase-5
capability: relationship queries (both directions), forget-fact (+ a `contains` cond),
a due-tasks agenda, recall-mood, reschedule-reminder/task (snooze), and
remember-relationship (offline "X is Y's Z"). Fixed real bugs found along the way —
retrieval hermeticity, a **reconcile time-change bug** (a rescheduled reminder kept
its old toast), and the flagship "remember that Mia is Sarah's daughter" being
cloud-only. De-flaked the authoring fixtures (recorder + schema-drift test now drive
the real Session validate→retry loop), then started the spec-conformance program (below).
**HEAD = `d70b96d`** (see LATEST SESSION block above), working tree clean (ignore untracked
`.claude/settings.local.json`), **1620 Dart + 38 app tests + ~40 Flutter widget tests green** (coverage ~91%). The Windows app has been **dogfooded live** through many iterations;
it's running with on-device voice + the expanded corpus.

**VOICE (#18) — SHIPPED, on-device.** `speech_to_text`/SAPI was too inaccurate (Fable root-caused
its late-delivery bug in the C++), so switched to **sherpa_onnx Whisper base.en + Silero VAD**
(`app/lib/sherpa_speech.dart`): tap mic → speak → a ~1s pause finalizes → auto-sends; modern
accuracy, offline, private. Behind the same `SpeechRecognizer` seam (SAPI/Noop fallback). Toolchain:
**CMake 4.3.4** installed + the VS2019 cmake dir symlinked to it (record_windows needs ≥3.23); model
pre-provisioned at `~/.plenara/models/en-whisper` (TODO: download-on-first-run, ~/.plenara/models,
int8 ~150MB — recognizer no-ops to SAPI/typing if absent). A verbose `AppLog.debug` tier (on in
debug, off in retail) logs the full speech lifecycle.

**PHRASING-COVERAGE EXPANSION.** Six Fable agents brainstormed ~30 variants/capability; corpus grew
~190 → **640 templates** + 112 tracker phrasings across all hero scenarios (analyses + integrate.py
in `planning/phrasing/`). Over-match hardened: new router **`:entity` guard** (a name slot can't
start with an article/pronoun), 6 ambiguous templates dropped, 8 regex upgrades (search + meta). +13
regression guards. **NEW dogfood-driven skills:** `clear-tasks` ("delete all my todos", undo-safe),
`steps-today`. **~54 gaps catalogued** in `planning/phrasing/*.json` (unit conversion — note: a
separate log-run-miles skill confused the CLOUD router, so do unit-aware single skills instead;
weight queries, relative-time reminders, non-running goals, etc.).

Earlier PRE-DOGFOOD PUSH (all shipped): (#14) first-run onboarding WelcomeScreen; (#15) OFFLINE fact
recall via the `:contact` slot; (#16) content/semantic search; (#17) reference KB (403-food nutrition,
`read_reference` op). **PRE-DISTRIBUTION TODO:** the app seeds first-run data from the dev path
`sourceDataDir = Z:\code\plenara\v0\data`; `ensureSeeded` THROWS loudly if missing — bundle `v0/data/`
as Flutter assets before shipping elsewhere. **CLOUD TIER VALIDATED LIVE** (Luis's BYOK key, now set in `~/.plenara/config.json`): the
generative kinds produce excellent grounded output (gift ideas off a contact's real hobbies,
briefing, weekly review honest about light logging, pattern-insight degrading on thin data,
in-voice draft), authoring works end-to-end (DF-01 offer → yes → "Log Pushups"/"Log Water Intake"
→ activate → "Logged 5 glasses of water…"), residual routing places corpus-misses.
**FOUR real bugs the fakes hid, caught + fixed across three live passes:** (1) a stuck ProvideSlot
(a cloud reminder with no time swallowed every later turn); (2) an authored `{var:count}` format
template leaking (format now accepts `{name}` and `{var:name}`; authoring prompt clarified); (3)
"actually that was 6k" / "that was 30 min" corrections missing; (4) a unit/field customization
("track my water in glasses") pre-empted by the eager ml template — now routes to authoring so the
user gets the tracker they described. The app is fully dogfood-ready. (full `tool/precheck.sh` gate passes:
analyze, import-lint, coverage 91.5%, app build, secret scan, conformance ratchet). **Diagnostics
are dogfood-ready** — a bad turn's turnlog line carries the utterance, route, template, slots,
writes, response, timing, cloud health, error+stack, WHY a miss happened (`diag`), and unattended
`automations` activity. **Recent hero-scenario → DSL work:** F-03 ordinal recurrence (+`ordinal_num`
fn), F-16 medication adherence, `mul`/`div`/`round` DSL primitives, and P-18 goal-progress % (offline).
Spec 13 (reference knowledge bases — nutrition/calorie KB) written + greenlit, staged post-dogfood.
The app now has a **"Your data" view**
(archetype-rendered records, value-type-aware, tap-to-detail, automations card) and a
**Settings screen** (in-app BYOK key entry + data folder + diagnostics path) — the last
hand-edit-a-JSON step before dogfood is gone. **Every named Spec 04 business-logic
component now exists:** DispatchOrchestrator (`session`), SkillInterpreter, SchemaRegistry
(defs loading), **MigrationRunner** (`migration.dart` — migrate-on-read, just built),
AuthoringService (the authoring path), ExecutionJournal (`turnlog`), AutomationRunner,
GenerativeService, AttentionSurface (nudges + review feed). (35 seed skills + 5 templates that also ship
QUERY skills, 9 types; DSL has ordering/limit/filter-ops + aggregation/date-math; ProvideSlot
slot-filling; alias resolution; OOD boundary; record-integrity + scope + medical + impersonation
+ schema-edit denial floors; compound-utterance split; GenerativeService gift/briefing/reconnect
+ weekly_review/pattern_insight/draft_message — all 6 routed with kind-specific prompts), `dart
analyze` clean, **`flutter build windows --debug` succeeds**.

**NEW SUBSYSTEMS this session (all live + tested):** (1) **AutomationRunner** (`automations.dart`,
Spec 01 §4.4 / 04 §3.9) — onWrite conditions fire a skill through the interpreter, gated by the
Review Feed (read-only → deliver out-of-band; writes → HELD for "approve it"/"dismiss it" from
the chat; destructive refused); wired into `Session._dispatch` behind a containment guard;
schedule/cron is now armed too (`cron.dart` + `AutomationRunner.tick` on app open — a scheduled
fire lands the next open after its cron time; `lastFired` persisted device-local; a true
background timer is the only follow-up). The example
(`workout-encouragement`) seeds + fires + surfaces in the app. (2) **Full Spec 09 §8.4 quality gate as a local
script** (`tool/precheck.sh`, 8 steps, fails on any): v0 analyze → **import-lint** (`bin/
import_lint.dart` — dependency-rule layering, util<storage=intelligence<business-logic, unit-
tested) → v0 tests + **coverage gate** (`bin/coverage_check.dart`, measured **91.5%**, floor 80%)
→ app analyze/test → Windows build → `sk-ant-` secret scan → **conformance ratchet** (05a passing
count vs `conformance-baseline.txt`=21, no decrease). Only a hosted runner remains. (3) **Spec 07 UI slice** (`app/lib/data_view.dart`) — a read-only "Your
data" view rendering records by an archetype inferred from type STRUCTURE (checklist/personCard/
tracker/timeline/collection), reached from the chat app-bar.

**ALL 12 DEEP-DIVE SPECS NOW EXIST (research §12).** Specs 6–11 were written one-Fable-per-spec
in parallel, then Spec 12 — Voice was chartered (03/04/08 had cited a nonexistent "Spec 06 —
Voice"), then a cross-spec review (`05f`) + a suite-sync pass reconciled the contradictions
(voice citations → 12; CloudErrorKind unified to the shipped 7-member set owned by 04 §5.1;
generativeKind owned by 08 §3.3 incl. draft_message; lastModified dropped from the record
envelope per 06; authoring model-name lives only in 08; 02 §7.6 safety build-status banner).
`05f` carries a RESOLVED/PARTIAL/OPEN status column; CS-13..CS-26 remain OPEN (a second sync
pass). **Two code blockers the review found are FIXED (`d956390`):** the per-install `deviceId`
and the `turnlog` no longer live in the synced folder (device-local `~/.plenara` via an injected
`deviceDir`) — a synced deviceId had defeated the HLC tie-break. Also landed from the specs:
atomic `writeDef` + corrupt-file surfacing (P2.8, `1bcaf0a`), and the **DF-01 authoring offer
gate** (`e6229a8` — no paid cloud authoring call until the user says yes; Spec 08 consent).

**05a CONFORMANCE HARNESS (`v0/test/spec05a_test.dart`, G-47):** turns "complete per spec" into
a measured number — each of the 60 worked examples runs its exact utterance offline and asserts,
or `skip`s with a reason. **Now 24/60 offline (up from ~1/60 at the audit; ratchet baseline 24):** F-tier 14/20
(logging, people incl. nested-fact F-07, recurrence, tracker aggregate/streak queries), DP-tier
7/10 (all deterministic safety/scope/OOD/medical/impersonation floors), DF 3/10 (DF-01 offer,
DF-03, DF-10), P 0/20 (all BYOK-gated). The remaining skips are near the offline CEILING — they
genuinely need cloud (paid tier), voice/STT (F-11), embeddings (F-12 semantic search), or the
model-gated safety Layer-2/3 (G-30). A 3-agent Fable (Claude 5) round landed
generative kinds (P-10/11/20 — built + unit-tested, not yet routed from session.dart),
compound-utterance split (F-13 capability, `3cca666`), and nested people-fact (F-07, `8ebb59b`
generative / this commit F-07). Remaining biggest gaps: the paid tier is 100% BYOK-gated, and
free-tier F-08 (filtered fact query), F-11 (voice-journal start), F-12 (semantic search),
DF-01 (no-template offer surface), plus safety Layer-2 (G-30) still want building.

**Working-mode enforcement (new):** a user-level **Stop hook**
(`~/.claude/hooks/stop-guard.ps1` + `~/.claude/settings.json`) bounces any turn whose
final ~160 chars are a permission-seeking coda ("want me to…/should I…"), so work
continues while unblocked items remain. Fails open. If you (a future session) get a
"STOP BLOCKED (working-mode hook)" message, that's it — pick the next unblocked item and
do it, don't re-ask. The rule itself is in `CLAUDE.md` "Working mode" (rewritten `627d4cc`).

**The immediate next task: the SPEC-CONFORMANCE PROGRAM (the real remaining scope).**
A full spec-vs-code audit (5 forks, synthesized) found the engine *spine* is done but
the app satisfies only ~1 of the 60 05a examples cleanly, ~12 partially, ~47 fail —
four whole architecture components (Automation, Generative, SchemaRegistry/Migration,
ContentSearch) and the conversational NLU seams (slot-fill, alias, anaphora, OOD) are
unbuilt, and the DSL was thinner than the spec's own §9.2 seed skills. This is weeks of
build, NOT "mostly done." **Ranked top-10 (see "Spec-conformance program" section):**
1 DSL query+compute fidelity ✅ DONE (`8cc36ed`); 2 ProvideSlot slot-filling dialogue
✅ DONE (`619f07c`); 3 tracker templates + free instantiate (§12.4 G-22) — free→paid
misroute slice ✅ DONE (`f9e2695`, built-in recognizer); instantiating NEW built-in
types from a template library REMAINS; 4 alias/role/group person resolution ✅ DONE
(`f3a396f`); 5 correction robustness — natural-prefix triggers ✅ DONE (`60a0cc8`); the
HARD remainder (F-14 re-classify needs a walk capability, F-15 same-record slot update)
is still open; 6 GenerativeService + gift_ideas/briefing (§3.10) ✅ DONE (`aa793b4`, first
increment — grounded gift ideas + daily briefing behind a CloudClient.generate seam, fake-
cloud tested; more kinds — reconnect/weekly-review/draft-message — can follow); 7 authoring
preview→refine→activate +
reconcile + pin Opus + structured output (§6 G-18/29, L); 8 recurrence RRULE +
record-anchored dates (§6.2 G-14/15, M) — record-anchored ✅ DONE (`3b26cbc`,
task-before-birthday: next_annual−1day, fully DSL-expressible, no router change needed);
recurring RRULE reminders still open; 9 safety — record-integrity floor ✅ DONE (`cba5c50`, DP-05);
Layer-2/3 model gate still deferred (G-30); 10 records-vs-OOD boundary ✅ DONE (`925ceda`,
with the personal-cue privacy guard). Also-done this session: all 3 correctness defects
(`c29732c`, `f9e2695`), journaling/F-11, streaks/G-21, total-distance (aggregation demo).
**Net: ALL 10 top-10 items are now built, most fully:** 1 DSL, 2 ProvideSlot, 3 template
library (`04fafcb` — instantiate NEW types free + built-in recognizer), 4 aliases, 5
corrections (prefixes + F-14 re-classify `073eae9` + F-15 slot-update `7b96daa`), 6
GenerativeService (gift/briefing/reconnect), 7 authoring preview→activate (`605367c`), 8
record-anchored dates + daily/weekly recurring reminders (`296a56b`/`cfcbb51`), 9
record-integrity floor, 10 OOD boundary. **Remaining (smaller/specialized) to fully complete
per spec** (Luis: build to spec BEFORE dogfooding — see `spec-complete-before-dogfood`
memory): interval RRULE ("every second Tuesday"); authoring ≤5-turn refine + similarTo
reconcile + pinned-Opus/structured-output (G-29); safety Layer-2/3 model gate (G-30); the
value-type dialect align (G-40); remaining G-39..G-48 aligns; more templates
(reading/meds/steps — trivial data adds); and an 05a conformance harness (G-47).
(Blocked/deferred, do NOT pick: native toast/ATL, voice, CRDT merge engine, persisted
journal, presentation archetypes, at-rest encryption, per-device corpus.)

**ATL + native toast: DONE (`e2ba8d8`).** ATL installed, `WindowsToastScheduler` built +
wired + proven end-to-end (reminders fire as OS toasts; see the recent-arc entry). The
remaining **Luis-gated** item is credential rotation: the BYOK Anthropic key (in
`planning/specs/05a-rig/.env`) and the GitHub PAT are still exposed and unrotated — the one
real liability the Fable review flagged. Cloud features (gift ideas, briefing, cloud
routing) stay off until a fresh key is in the config; offline (tasks/people/journaling/
reminders) works now.

**Environment note (new machine/user `luism`):** re-established this session — git
`safe.directory` exceptions added, `luisma-code` PAT re-stored in GCM (headless
push verified), `dart pub get` re-run for both `v0/` and `app/`. Windows Dev Mode
is ON (registry-verified).

## Two standing directives from Luis (most important context)

1. **Automated tests must provide real product-level validation.** Anything whose
   only validation is manual dogfooding *will* regress. Every OS-facing capability
   ships **behind a thin adapter interface with a fake**, so the *logic* is
   CI-tested deterministically and only a razor-thin "call the real OS API" shim
   needs a one-time human smoke. (Same pattern as `StorageRepository` /
   `CloudClient`.) This is the governing principle for all new work.
2. **Work autonomously, never ask permission** (see `CLAUDE.md` working-mode). Decide,
   record rationale, commit, keep going. Review happens when the work is done.

## How to run / verify (toolchain is local, gitignored)

- Dart SDK: `Z:/code/plenara/.tools/dart-sdk/bin/dart.exe`
- Flutter: `Z:/code/plenara/.tools/flutter/bin/flutter.bat` (3.44.5, accepts VS Build Tools 2019)
- Tests: `cd v0 && Z:/code/plenara/.tools/dart-sdk/bin/dart.exe test` (1019, hermetic)
- Analyze: `<dart> analyze lib bin test` (from `v0/`)
- App: `cd app && <flutter> test` (widget) / `<flutter> build windows --debug` → `app/build/windows/x64/runner/Debug/plenara_app.exe`
- Cloud fixtures (only if `lib/fixture_inputs.dart` changes): `cd v0 && <dart> run bin/record_fixtures.dart` (one BYOK Haiku pass, commit the cassette)
- Optional embed server for retrieval: llama-server w/ bge-small on `:8091` (graceful if absent)

**Before every commit:** `git grep --cached -nE "sk-ant-[A-Za-z0-9]{20}"` must be 0.
Commit trailers required (Co-Authored-By: Claude Opus 4.8 (1M context) + Claude-Session)
— see `CLAUDE.md`. Line-ending (CRLF) warnings on commit are benign.

## Fresh machine / new user context — environment setup

The Claude auto-memory does NOT transfer across OS users/machines (it lives in
`C:\Users\<you>\.claude\…`). This doc + `CLAUDE.md` are in the repo and are all
you need. **First:** tell the new Claude *"read HANDOFF.md and CLAUDE.md, then
continue."* Then, if it's a fresh clone / different user, re-establish these
(all gitignored, so they don't come with the repo):

1. **Toolchain into `Z:\code\plenara\.tools\` (~2 GB, gitignored).**
   - **Flutter** (bundles the matching Dart): download `flutter_windows_<ver>-stable.zip`
     from flutter.dev's release archive (we used **3.44.5**; latest stable is fine),
     unzip to `.tools\flutter`. First `flutter\bin\flutter.bat --version` builds the tool.
   - **Dart SDK** used by the v0 commands is a standalone at `.tools\dart-sdk\`
     (**3.12.2**, from dart.dev's archive). Alternatively just use Flutter's bundled
     Dart at `.tools\flutter\bin\dart.bat` and adjust the commands.
2. **Windows build prereq:** Visual Studio **Build Tools 2019+ with "Desktop
   development with C++"** (2019 confirmed working; 2022 fine). `flutter doctor`
   verifies it. Native plugins (notifications, voice) also need **Windows Developer
   Mode ON** (Settings → For developers).
3. **API key.** The key pasted early on is **exposed — ROTATE it** at
   console.anthropic.com. Then provide the new one by ONE of: `ANTHROPIC_API_KEY`
   env var; `planning\specs\05a-rig\.env` as `ANTHROPIC_API_KEY=sk-ant-…` (gitignored,
   for tests/recorder); or `~/.plenara/config.json` `"apiKey"` (for the app).
4. **Permissions.** To match this session's autonomous flow, set the new user's
   `~/.claude/settings.json` `permissions.defaultMode` to `bypassPermissions` (or
   just approve interactively). This is a per-user setting, not in the repo.
5. **Optional:** the retrieval embed server (llama-server + bge-small on `:8091`)
   — everything degrades gracefully without it.

Same machine, different user? Simplest is to copy
`C:\Users\lmh10\.claude\projects\Z--code-plenara\` into the new user's
`.claude\projects\` — but it's optional; the in-repo docs cover everything.

## Transferring the repo + credentials to the new context

**Repo state: RESOLVED — origin is current.** `origin` =
`github.com/luisma-code/plenara.git` (public). All work is pushed;
`origin/main` == local `main`. Push auth was initially denied (this session
commits as GitHub user `cognivita-ai`, which lacks write access to
`luisma-code/plenara`); resolved by storing a **`luisma-code` PAT** in the OS
credential store (Git Credential Manager). Config set for headless push (global): `credential.credentialStore=dpapi` (a
Windows store GCM can persist to + read back without a GUI),
`credential.interactive=false`, `credential.guiPrompt=false`. Verified: `git
credential fill` returns the stored token non-interactively, so **plain `git push
origin main` works headlessly** — no token in any command needed anymore.

> **⚠ ROTATE the PAT.** The token was transmitted in chat → treat it as
> compromised. Generate a new fine-grained PAT (Contents: Read+Write on plenara)
> and re-store it: `printf 'protocol=https\nhost=github.com\nusername=luisma-code\npassword=<NEW>\n\n' | git credential approve`. The remote URL is token-free (verified); the token lives only in GCM, never in the repo/bundle.

- **Credential-free fallback bundle:** **`Z:\code\plenara.bundle`** has the full
  history (verified clonable, scanned clean) for moving to a machine without git
  creds — `git clone plenara.bundle plenara`. Regenerate: `git bundle create ../plenara.bundle --all`.

**Two different "Claude keys" — don't conflate:**
1. **Claude Code auth** (to RUN Claude as the new user): the new user signs in with
   their OWN Claude login / subscription (or configures their own Claude Code API key).
   Not transferable by tooling — it's per-user account auth.
2. **Anthropic BYOK key** (the app's own API calls — routing, authoring, the fixture
   recorder): rotate the exposed one, then supply via `ANTHROPIC_API_KEY` env /
   `planning\specs\05a-rig\.env` / `~/.plenara/config.json` (see setup above).

**Security:** move every credential (GitHub PAT, the BYOK key) **out-of-band** — a
password manager or a secure channel — **never in the repo, a commit, or the bundle.**
The bundle is intentionally secret-free; keep it that way.

## What's built (the code)

**`v0/lib/` — the engine (~pure Dart, ~1,600 lines):**
- `interpreter.dart` — Skill interpreter. Two-phase resolve→execute. **All 10 DSL
  ops** (read_one, read_many, read_related, write_record [create + update via
  `target`], delete_record [tombstone], compute, set, format, branch, foreach).
  UUID ids. `validateSkill` = hardened static gate (whitelisted ops/fns,
  branch-sound G-17 entityRef + refType, capability closure via `reads`/`writes`,
  requires `confirmationText`, total over arbitrary JSON). `validateType`.
- `router.dart` — corpus fast-path (template→regex→slots), date resolver,
  quantity/text/entity extraction, corpus-learning ratchet **both halves**
  (`learn` guarded; `isLearned`/`forget` = negative half), retrieval fallback.
- `session.dart` — the DispatchOrchestrator turn engine. `handle` catch-all
  boundary; undo→correction→authoring→route→execute→persist→learn. Per-turn clock.
  Execution-journal ring (multi-turn undo). Tracks previous turn (write OR read)
  so corrections target correctly. Emits the **turn log** telemetry.
- `storage_repository.dart` — `StorageRepository` interface + `FileStorageRepository`
  (per-record JSON, stamp-on-change, tombstones, atomic writes, corpus-learned,
  authored defs, turnlog). **Session holds the interface, never touches files.**
- `claude.dart` — `CloudClient` interface + `ClaudeClient` (Haiku residual routing
  + authoring). Never throws (offline/401/timeout/refusal→null). Injectable key+URL.
- `config.dart` — `loadConfig` (dataDir + apiKey from env > `~/.plenara/config.json`
  > scaffolded default) + `ensureSeeded` (copies built-in defs into the user folder).
- `store.dart` (HLC + file fns, wrapped by the repo), `embed.dart`,
  `replay_cloud.dart` (record/replay cassette), `fixture_inputs.dart`.
- `reminders.dart` — the `NotificationScheduler` OS seam + `FakeScheduler` + pure
  derive/reconcile (armed set DERIVED from the record store; idempotent). Session
  reconciles on init + every turn and exposes `pendingNudges()`.

**`v0/data/`** — 8 types, **26 skills**: tasks (create/list/complete/delete/due/**reschedule**),
running (log-run, count-runs-this-week), mood (log/recall), reminders (set/list/
complete/cancel/**reschedule**), people-facts (remember/recall/forget/**remember-relationship**),
interactions (log/last/list), list-relations, birthdays (set/when/upcoming). DSL compute fns: `format_time`,
`next_annual`, `days_until_annual`; conds incl. **`contains`**; the date resolver
handles month-name dates. Helper libs: `dates.dart` (annual math), `people.dart`
(birthday-nudge projection), `reminders.dart` (notification seam + reconcile),
`turnlog.dart` (dogfood metrics).
**`v0/bin/plenara.dart`** — console (REPL / `--demo` / one-shot) over the same Session.
**`app/`** — Flutter Windows chat UI; `buildSession()` from config; 2 widget tests.

**`v0/test/`** (1019): router (453), pipeline/fuzz (265), interpreter (~150),
cloud/cassette (~35), session (~35), robustness (33), store (~20), claude (14),
config (5), hardening (~20).

## Recent arc (what just happened, newest first)

- **Reminders FIRE — real Windows toast, proven end-to-end (`e2ba8d8` … `73b1959`):** ATL
  installed → the `flutter_local_notifications_windows` native code compiles →
  `WindowsToastScheduler` (real `NotificationScheduler` backend) wired into `buildSession()`.
  Fixed a **startup hang** (retrieval index hit the down embed server, ~2s × 70 anchors =
  140s → now 103ms: probe-once + app defaults `retrieval:false`). Added **diagnostics
  logging** the whole flow was missing: `AppLog` writes a timestamped, flushed log to
  `%TEMP%\plenara-logs\` (path shown in the app greeting; a GUI app can't print to the
  launching console) capturing boot, every init phase, every turn, scheduler init/ARM/fail,
  and uncaught/Flutter errors. **Verified the toast path fully automated** (no typing): seed
  a future reminder record → launch → log shows `plugin.initialize()->true` + `sched: ARMED
  … in 68s`; display proven by an immediate self-test `show()` (now gated behind
  `PLENARA_SELFTEST=1`). The app is genuinely dogfood-ready: starts in ~100ms, reminders
  fire as OS toasts, every turn + startup is diagnosable from the log. (Unpackaged limit:
  `cancel` is a no-op until MSIX packaging — toasts still fire.)
- **Fable review #2 (impl + spec) — done + acted on (`d0f9ab0` … `edc4091`):** a 3-lens Fable
  panel (architecture / spec-fidelity / strategy), synthesized in
  [`05e-fable-review.md`](planning/specs/05e-fable-review.md). Fixed every impl bug it found:
  a P0 correction data-loss (`edc4091`), OOD bouncing a known contact + list-tasks showing
  completed (`3ec834b`), three CRDT format flaws before sync fossilizes them (`63c5051`),
  ProvideSlot swallowing system commands (`3e508a3`), learned templates shadowing seeds
  (`245c2fe`), validator var-closure (`5a1bcf7`), avg([])→null (`d0f9ab0`). Added **rich
  per-turn debug tracing** for dogfood diagnosis (`d341308`, `72bf5b3` — turnlog now carries
  template/slots/writes/timing/response/error+stack; `turnlog_report --trace`/`--errors`).
  **Turned the gap register around** — filed G-39..G-48 for code→spec drift (`6a7a346`),
  adopted the rule "a code change contradicting a spec files a G-entry in the same commit."
  Strategy verdict (Luis-gated, unchanged): **zero real turns run yet** — the real blocker is
  the 20-min admin window (rotate the 2 exposed creds + ATL + write the config), then dogfood.
  **Per Luis: fix Fable issues (DONE) → push through the top-10 → then another review.**
- **Spec-conformance program STARTED (`46d15a5` … `e62bedf`):** ran a 5-fork spec-vs-code
  audit (the ranked top-10 is in the TL;DR + the gap register `05b-gap-register.md`);
  then shipped: journaling (`journal_entry` + log/recall, F-11/G-01), streaks
  (`current_streak`/`longest_streak` + run-streak, G-21), **2 real defects** (safety
  bypass: `_defRe` missed "build me a" so DP-01/DP-08 skipped the §7.6 floor; format
  leaked `{var}` on null — both fixed `c29732c`), and **DSL query+compute fidelity**
  (`8cc36ed`: read_many orderBy/limit + full filter ops; compute sum/avg/min/max/
  count_where/days_between/add_days/if) + total-distance demonstrating it; then item 2
  ProvideSlot (`619f07c`, resumable missing-slot dialogue), item 4 aliases (`f3a396f`,
  "Mum"/"the boss" → contact via a new alias tier in read_one), and the free→paid slice
  of item 3 (`f9e2695`), item 5 correction-prefix broadening (`60a0cc8`), item 10 OOD
  boundary + personal-cue privacy guard (`925ceda`), and item 9's record-integrity floor
  (`cba5c50`, refuse to fabricate the past), then item 6 GenerativeService (`aa793b4`,
  grounded gift ideas + daily briefing). **7 of the top-10 built; the heavy half is
  underway. Next: item 8 recurrence + record-anchored dates (deterministic, M), item 7
  authoring refine→activate loop (L), the full item-3 template library, and more generative
  kinds (reconnect coaching, weekly review, draft message).**
- **More depth + real bug fixes (done, `02f4388` … `6a17c15`):** reschedule-reminder
  (snooze) — which exposed and FIXED a `reconcileReminders` time-change bug (armed()
  now returns ref→time so a rescheduled reminder re-arms); reschedule-task;
  remember-relationship (closes the flagship "X is Y's Z" offline gap, found via an
  end-to-end console smoke); a "realistic day" cross-skill integration test; DOGFOOD.md
  refreshed for tonight (25+ skills to try, turnlog_report, ATL→toast→voice plan).
- **Working-mode fix (done, `627d4cc` + user-level hook):** rewrote the "keep going"
  rule to target turn-endings + added a Stop hook that enforces it. See TL;DR.
- **recall-mood + authoring de-flake (done, `c9fb48e`, `88c11c3`):** recall-mood
  ("how have I been feeling"); recorder + schema-drift test now drive the Session
  validate→retry authoring loop so re-records no longer flake on first-attempt
  out-of-vocab fns.
- **Capability depth (done, `b21ff4e` … `c36d00a`):** `due-tasks` ("what's due" /
  "anything overdue" — overdue + today, excluding future/done); `forget-fact`
  ("forget that Mia likes chess") + a new `contains` cond (case-insensitive substring
  in branches); `list-relations` querying the relationship graph BOTH directions
  ("Sarah's daughter: Mia" and "Mia: daughter of Sarah"). People loop is now full CRUD.
- **Phase 2 complete: partial name matching + disambiguation (done, `ec14145`):**
  `read_one` resolves exact-first then substring (opt-in `partial:true` on people READ
  skills); >1 match throws with candidate labels (`ResolveError.options`) which Session
  renders as a "which one?" clarify. Write/find-or-create stay exact (dedup preserved).
- **Phase 2a: discoverability + turnlog report (done, `949f501`):** "what can you do"
  is a Session special-case (no re-record) rendering a capability-grounded, per-skill-
  gated overview; `bin/turnlog_report.dart` + `lib/turnlog.dart` aggregate source
  distribution, cloud health, top skills, and the make-or-break clarify rate.
- **Phase 1: typed CloudResult (done, `072586e`):** `CloudResult` sealed type
  (`CloudOk`/`CloudError` + `CloudErrorKind`) replaces `Map?`/null at the cloud seam;
  `_message` maps every HTTP/parse outcome to a kind (never throws); Session names the
  cause on a cloud-caused miss + logs a `cloud` turnlog field; skill inputs can declare
  `"type": date|datetime` and Session normalizes cloud slots via resolveDate/DateTime;
  dropped the absolute `.env` fallback. Cassette UNCHANGED (recorded values wrap as Ok).
  `claude_test` now asserts a kind per failure; new `cloud_result_test` covers R1+R2.
- **Fable strategic review:** ranked next phases toward v1 — Phase 1 (cloud truth) now
  done; Phase 2 (conversation polish) next; persisted journal explicitly WAIT (Spec 04
  §3.11's undo window is 5 min, so post-restart undo is mostly moot until execution is
  async). Full review reasoning is in the session log.
- **list-interactions + app build verify (done, `e0268ca`, `6cce275`):**
  "what have I logged with X" (dated bullets + notes); grew app widget tests to 8
  (undo, multi-turn, list render, busy state); clarified count-runs-this-week's
  displayName so Haiku stops intermittently abstaining on "since Monday"; confirmed
  `flutter build windows` succeeds.
- **On-open birthday nudges (done, `74ee048`):** "🎂 X's birthday is in N days" on
  launch, derived from contacts (no new skill). Factored annual-date math into
  `lib/dates.dart` (shared by the interpreter + `lib/people.dart`). `pendingNudges()`
  now merges reminder (⏰) + birthday (🎂) nudges. Completes Fable #4.
- **Birthdays (done, `a31eefa`):** DSL `next_annual`/`days_until_annual` compute fns,
  month-name dates in the resolver ("March 3", "3rd of december"), + `set-birthday`
  / `when-birthday` / `upcoming-birthdays` (30-day window via reversed-gte). +6 tests.
  This completes Fable #3 (people loop).
- **People loop pt.1 (done, `bf6cdc4`):** `interaction` type (subject→contact,
  note, at) + `log-interaction` ("talked to/called/caught up with X [about Y]",
  finds-or-creates the contact) + `last-interaction` ("when did I last talk to X",
  MAX date via a foreach+gte/set reduction since the DSL has no sort). +6 tests.
- **Reminder management (done, `0fddb86`):** list / complete / cancel-reminder;
  complete sets `done:true` and cancel deletes → reconcile cancels the toast. +8 tests.
- **F2 reminders + notifications (done, `4d30b68`):** `NotificationScheduler`
  seam (`v0/lib/reminders.dart`) with a `FakeScheduler`; the armed set is DERIVED
  from the record store and reconciled idempotently (on init + every turn), so
  undo/delete/complete cancel toasts for free and re-open never double-arms.
  New `reminder` type + `set-reminder` skill (graceful missing-time clarify),
  corpus templates, `router.resolveDateTime` (a time-of-day is required = the
  task-vs-reminder discriminator), `interpreter.format_time`. App shows past-due
  reminders as on-open nudges. +30 v0 tests + 1 widget. Re-recorded the cloud
  cassette (adding a skill grows invSig). Native Windows toast deferred (ATL).
- **Hermeticity fix (`b6ca68c`):** the authoring path rebuilt the retrieval index
  unconditionally; now it honors `init(retrieval:)` like init does, so authoring
  is hermetic without the embed server (was a 30s timeout on a machine without it).
- **Dogfood enablement (Fable #1, done):** config + first-run seeding (real folder
  + BYOK key), the turn-log measurement instrument, fixed the correction/read-only
  defect Fable found, `DOGFOOD.md`.
- **Track A / foundation (done):** execution-journal ring (multi-turn undo),
  `read_related` (10/10 ops), `StorageRepository` seam, corpus-learning negative half.
- **Two design decisions (Luis's call):** DSL dialect **converge spec↔code** —
  structure from code (`{fn,args}` compute, inline then/else), names/envelope from
  spec (`entityRef`, `confirmationText`, `reads`/`writes`); corpus **single-file for
  v1** (per-device deferred to P2).
- **Fable code review fully implemented (6 waves):** UUID ids, hardened gate,
  never-throw client + timeout + unit tests, per-turn clock, app no-silent-failure,
  CRDT fidelity, framing-keyed safety floor, update/delete ops, encryption-posture
  spec fix, cost-cap flag.

## Next task (build this, test-first)

**Fable #1–#4 DONE; app widget tests grown (8).** Remaining options, roughly by
value/risk (none need Luis):
- **Depth in existing loops (re-record on each new skill):** `list-interactions`
  ("what have I logged with X" — read_related interactions, formatted); tracker
  templates; a "help / what can you do" surface.
- **Persisted undo journal** (Spec 04 §3.11) — undo is in-memory today (dies on
  restart). Contained to `Session` + a device-local journal file (NOT the synced
  records folder). Medium effort; marginal UX value (rare to undo post-restart).
- **Typed `CloudResult`** (offline vs bad-key vs rate-limited) — closes a
  spec-vs-code gap (CLAUDE.md architecture says the client returns typed results,
  not exceptions). HIGHER blast radius: changes the `CloudClient` interface, so it
  ripples through `ReplayCloud`/`RecordingCloud`, every test stub, and `session`.
  Best started fresh, not at the tail of a long session.
- Presentation archetypes stay DEFERRED (Spec 01 §9 unwritten; chat renders fine).

**When you DO add a skill later:** it grows the capability inventory → the cloud
cassette's `invSig` keys change → **re-record** `test/fixtures/cloud.json`
(`dart run bin/record_fixtures.dart`, needs the BYOK key in the rig `.env`).
Routing stayed stable across the re-records this session (one count-runs route
flapped once to abstain, correct on the next roll — Haiku sampling variance);
eyeball the printed routes each time.

**Reminder architecture already in place (reuse it):** `v0/lib/reminders.dart`
holds the `NotificationScheduler` seam + `FakeScheduler` + the pure derive/reconcile
(`desiredArmed`, `dueReminders`, `reconcileReminders`). Session takes an optional
`scheduler`, reconciles on init + every turn, and exposes `pendingNudges()`. The
armed set is derived from records, so any skill that writes/updates/deletes a
`reminder` (typeId `reminder`, `remindAt` datetime, `done` bool) participates for
free — no per-skill notification wiring.

## Fable's ranked next-phase priorities (strategic review)

1. Dogfood enablement — **DONE.**
2. **Reminders + notifications (F2)** — the retention hook (← next).
3. Deepen the people loop — log-interaction, "when did I last talk to X", birthdays.
4. Thin on-open nudge surface (not the full AutomationRunner yet).
5. Presentation archetypes — **defer** (Spec 01 §9 unwritten; chat renders fine; trap now).
6. Tracker templates — defer (spec-completion).
7. CRDT merge engine — **do not build** (hardware-gated, its own assessment defers it).
8. Safety Layers 2/3, spec completeness — archival for an audience of one.

## Deferred / open (don't lose these)

- **Native Windows toast for reminders — BLOCKED on ATL (needs admin).** The real
  `NotificationScheduler` impl (flutter_local_notifications, native C++/WinRT) needs
  the ATL VS component. Dev Mode is on and the plugin symlinks/compiles; it only
  fails on `fatal error C1083: 'atlbase.h'`. Install (ADMIN shell):
  `& 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe' modify --installPath 'C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools' --add Microsoft.VisualStudio.Component.VC.ATL --quiet --norestart`
  Then: re-add `flutter_local_notifications`, write the real impl behind the seam,
  inject it in `buildSession()`, `flutter build windows`, smoke a real toast. All
  logic is already tested against `FakeScheduler`; only the render is manual.
- **Cloud residual reminder times** — Haiku may route a reminder-ish utterance to
  set-reminder but its `when` slot isn't run through `resolveDateTime`, so a natural
  time ("tomorrow at 3pm") may not normalize. Corpus path is exact; cloud path for
  reminders is best-effort. Normalize cloud datetime slots in Session as a follow-up.
- **Voice** (STT/TTS) — behind `SpeechInput`/`SpeechOutput` seams; needs Dev Mode + audio hw.
- **iOS build** — Apple hardware.
- **Typed `CloudResult`** — distinguish offline / bad-key / rate-limited (minor UX; deferred).
- **Persisted execution journal** — undo is in-memory (dies on restart); Spec 04 wants persisted.
- **Per-device corpus files** — deferred to P2 (single-file for v1 per Luis).
- **CRDT merge engine** — format is merge-ready; the engine is P2 (needs 2 devices).
- **Cost-cap number** — Spec 03 §7.3 flagged "don't ship 20/hr unchanged"; needs beta data.
- **App widget tests** — thinnest-covered surface; grow these (per directive #1).
- **API key** — pasted in an early session, stored ONLY in gitignored
  `planning/specs/05a-rig/.env`; **MUST be rotated**; never print/commit it.

## Specs / docs map

`CLAUDE.md` (working mode + principles), `planning/plenara_research.md` (vision,
ch.12 roadmap), `planning/specs/01–05*` (01 meta-schema, 02 DSL [see the §3 dialect
convergence banner], 03 NLU, 04 architecture [§3.1 v1 encryption posture note], 05
functional + 05a examples + 05b gap-register + 05c/d/storage-assessment),
`v0/README.md` (real-vs-stub map + test suite), `DOGFOOD.md` (setup + turnlog).
