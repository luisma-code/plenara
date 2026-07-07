# Plenara — Session Handoff (pick up here)

_Last updated: 2026-07-07. Written to survive a Claude process relaunch._

## TL;DR — where we are

The **v0 engine is complete and heavily tested**; the **Windows desktop app is
dogfood-ready** (runs on a user-chosen synced folder + BYOK key). We just finished
implementing a full Fable code review + a "Track A / foundation" phase + the
dogfood-enablement phase. **HEAD = `f8f7736`**, working tree clean, **1019 Dart
tests + 2 Flutter widget tests green**, `dart analyze` clean.

**The immediate next task:** build **reminders/notifications, test-first, behind a
`NotificationScheduler` adapter interface** — see "Next task" below. Luis is
enabling **Windows Developer Mode** (unblocks native Flutter plugins for
notifications + voice); verify that first.

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
credential store (Git Credential Manager). Config set for headless push:
`credential.interactive=false`, `credential.guiPrompt=false` (so GCM never blocks
on a GUI). Future `git push origin main` works non-interactively.

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

**`v0/data/`** — 6 types, **9 skills** (create/list/complete/delete-task, log-run,
log-mood, count-runs-this-week, remember-person-fact, recall-facts), corpus.json.
**`v0/bin/plenara.dart`** — console (REPL / `--demo` / one-shot) over the same Session.
**`app/`** — Flutter Windows chat UI; `buildSession()` from config; 2 widget tests.

**`v0/test/`** (1019): router (453), pipeline/fuzz (265), interpreter (~150),
cloud/cassette (~35), session (~35), robustness (33), store (~20), claude (14),
config (5), hardening (~20).

## Recent arc (what just happened, newest first)

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

**Reminders + on-open nudges, behind a `NotificationScheduler` adapter.**
- Interface `NotificationScheduler` { schedule(ref, when, body); cancel(ref); armed() }
  with a `FakeScheduler` (test) and a real Windows impl (native plugin — needs Dev Mode).
- Product-level tests (against the fake, in CI): "reminder for Thu 5pm arms exactly
  one notification"; "undo cancels it"; "re-open re-derives the armed set, no dupes";
  "past-due reminder → on-open nudge". Only "does Windows render the toast" is manual.
- Likely needs: a `reminder` concept (task `dueAt` + a time, or a reminder type),
  date-resolver extension (times of day), the on-open nudge surface in the Flutter UI
  (also widget-tested), wiring undo/delete → `cancel`.
- **First step when resuming:** confirm Dev Mode is on — `cd app && <flutter> pub add
  flutter_local_notifications` (or chosen plugin) + `<flutter> build windows`. If it
  builds, Dev Mode worked and native plugins (incl. voice later) are unblocked.

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
