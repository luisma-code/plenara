# Plenara — Claude Code Context

## What this project is

Plenara is a voice-driven, AI-augmented personal assistant app. Solo project by Luis. Core purpose: help him be a better friend, husband, and parent — remembering things about people, surfacing nudges, and helping plan activities and gifts.

**Not a commercial venture.** No investors, no deadlines. The goal is an app Luis genuinely loves and relies on.

## Working mode (IMPORTANT — read first)

**This mode is GATED — it applies only when Luis explicitly requests it** (he'll say "working mode"
or "agentic mode"). That request signals **he is leaving the machine** and wants uninterrupted work.
**By default (he's at the keyboard), take SHORT turns** — one meaningful step, then hand back so he
can redirect without interrupting (see global `~/.claude/CLAUDE.md`). Everything below describes the
requested autonomous mode:

**Work autonomously and keep going. Never stop for input to proceed.** Top rule, most-repeated correction — honor it above default collaborative caution. Decide, act, commit, continue.

- **"Should I do the next step?" is ALWAYS yes** — never ask it. Finish an increment → commit → immediately start the next → repeat, indefinitely. Make design/tooling/sequencing calls yourself; record the rationale in the commit/handoff and move on. Review happens when the work is *done*.

- **Surfacing ≠ stopping. The sin is stopping while open work remains — not surfacing.** Reporting status, reasoning, and open ponderings is *welcome*, any time. But a status note is something you emit *while continuing*, never *instead of* it: while any unblocked work remains, keep doing it **in the same turn**. The failure is always the last message — handing a decision back, or asking permission, when you could have picked the next thing and done it. So don't end a turn on a solicitation ("want me to…", "should I…", "any preference…", "let me know…", "would you like…", "or should I just…") while work is still available — pick and do it, then report. A Stop hook bounces a turn that ends on such a coda with open work remaining.

- **Uncertainty is not a reason to stop.** Unsure whether more work is worth it, or which direction is best? Pick the highest-value option, state the assumption in ONE line ("Assuming X matters most — building it."), and keep going. Ponder out loud all you like — then act on the pondering rather than parking it for the user. Judgment calls become stated bets, not questions; the user redirects if a bet is wrong, which costs far less than stalling.

- **The ONLY sanctioned stop** is a genuine hard blocker — hardware/credentials/approval only Luis can supply, a real user/beta, or a truly irreversible high-stakes action — or nothing left to do. State the blocker declaratively ("Native toast needs the ATL install, which needs your admin — so I'm moving to the next unblocked item.") and keep working on everything still unblocked. A hard blocker on ONE thing is never an excuse to stop ALL work.

- **Exception — meta/process:** when Luis explicitly opens a decision about *how we work* (e.g. "should we rewrite this instruction?", "which approach do you prefer?"), engaging him IS correct — that's his call, not permission-seeking about the task. This exception does not extend to the work itself.

- Standing setup: broad allowlist + bypass mode remove per-action approvals.

- **Keep `WORK-CAPSULE.md` current as you work.** It's the living working-memory doc (live facts,
  deploy commands, hard-won gotchas, decisions + rationale, open threads). Update it **continuously** —
  whenever a non-obvious fact is discovered, a decision is made, state changes, or a thread opens/closes
  — not just at session end. Keep it skimmable and prune stale lines. It's the first thing a fresh
  session reads, so it must always reflect reality. (It supersedes the "current state" role of the
  older `SESSION-HANDOFF.md` / `HANDOFF.md`.)

- **Keep the Mac awake — every session, always (macOS).** At the **start of every session**, immediately
  run `caffeinate -dimsu` detached in the background (`pgrep -x caffeinate || nohup caffeinate -dimsu >/dev/null 2>&1 &`),
  and **keep it running for the ENTIRE session — do NOT kill it when a task completes.** An idle Mac
  drops into maintenance/idle sleep (even on AC), which suspends the Claude app process and drops the
  session mid-build (this bit us — repeated "lost connection"). Kill it **only** at true session end.
  (This overrides the general "kill background helpers when the task is done" rule — caffeinate is a
  session-long helper, not a per-task one. On Windows the equivalent was `scripts/keep-alive.ps1`.)

## Planning documents

All design specs live in [`planning/`](planning/). Read them before touching architecture or interfaces.

| File | Contents | Status |
|------|----------|--------|
| `planning/plenara_research.md` | Vision, principles, full tech baseline (v0.10) | Locked — do not edit unless Luis says so in-session |
| `planning/specs/01-06` | Schema, DSL, routing, architecture, functional behavior, storage/sync | Active subsystem authorities; each header states implementation status |
| `planning/specs/07-16` | Visual language, AI/privacy, tests, security, diagnostics, voice, references, presence, routines | Active domain authorities; target-only sections are labeled in place |
| `planning/specs/17-living-planner.md` | Today/Plan/Library/History product model and multimodal interaction | Current product authority; supersedes presence-only/overlay-only rules |
| `planning/implementation-plan-2026-08-17.md` | Review remediation program and acceptance evidence | Increments 0–8 implemented; remaining gates are ordinary-use measurements |
| `planning/specs/05a-*` | Worked examples, traces, gap register, and design reviews | Historical/evaluation evidence, not current-state handoff |

## Stack

- **Framework:** Flutter / Dart
- **Storage:** per-record JSON files in user-chosen folder (iCloud / OneDrive / Google Drive); no SQL on disk
- **In-memory cache:** Dart object store, hydrated from JSON at startup
- **Local NLU:** corpus fast-path + a deterministic in-process feature-hash retrieval index + deterministic date/entity/quantity resolvers; Haiku handles the genuine residual. The measured-failed 1–3B generative router is cut. A packaged sentence transformer remains a measured future upgrade, not a runtime dependency.
- **Storage caveat:** user records—including daily journal entries and fields marked `sensitive`—**sync** as plaintext JSON for durability until at-rest encryption ships (`G-37`). The execution/undo journal, conversation ledger, operations, and diagnostics are device-local and currently plaintext.
- **Cloud AI:** Claude Haiku 4.5 for routing/generation/capability authoring; Sonnet 4.5 for routine composition/figure calls; BYOK model
- **Platform targets:** P1 iPhone, P2 Windows desktop, P3 Android, P4 macOS

## Locked design principles

These are the current defaults, not constraints on Luis. Spec 17 owns the product-model amendments.

1. **Voice is first-class and uncompromising.** Free-form and adaptive, with outcome parity. Visible UI carries persistent state, comparison, planning, and precision editing; it is not restricted to overlays (Spec 17).
2. **Act-then-describe.** An understood request executes immediately; the app describes what it did in one past-tense sentence. No pre-action "are you sure?" — reliable undo is the safety net. The one exception: non-undoable type/skill deletion (app-initiated confirm). Automation writes (unattended) go to the Review Feed.
3. **Code over AI.** Deterministic code beats AI for repeatable tasks. AI fills gaps where code can't.
4. **Capabilities are data, not code.** Skills are a declarative DSL (closed primitive vocabulary), NOT generated code. Apple 2.5.2 compliance requires this — interpreter ships in binary, skills are recombined data.
5. **AI authors, code executes.** Claude authors a type/skill once (rare, paid). Deterministic Skill Interpreter runs it forever after.
6. **Aggressive layering.** UI → Business Logic → Storage → Intelligence, strictly separated behind interfaces. Dependency rule enforced by import-lint CI gate.
7. **No silent failure.** Fail to understand → clarify. Too complex → engage to break it down. Policy block → tell the user what and why. Every failure mode has a visible, actionable surface.

## Priority order for design calls

**Usability > Capability > Performance > Minimalism**

Take the option that gives the best experience and reliability, even at a small size or dependency cost. Don't reflexively pick the simplest option.

## Architecture in one paragraph

Five conceptual layers remain: UI, Business Logic, Storage, Intelligence, and Voice. The current walking implementation consolidates dispatch and orchestration in `Session`; all production mutations converge on `ExecutionCoordinator`, durable device-local `ExecutionJournal`, and `StorageRepository`. Routing is corpus → accepted deterministic retrieval → cloud residual → clarification. Cloud calls cross `ClaudeClient` and return typed `CloudResult` values; offline is a typed case. Spec 04 marks richer destination interfaces as targets rather than claiming their classes already exist.

## Things NOT to do

- Storage correctness, migration, sync, and durability tests use real temporary files. Pure routing/business tests may inject in-memory seams when persistence is not the subject.
- Don't add pre-action confirmation dialogs except for non-undoable deletions.
- Don't put execution state (journal) in the synced storage folder — it's device-local and encrypted.
- Don't fetch skills remotely or make the authored skill file non-human-readable (App Store compliance + auditability).
- Don't cache slot *values* in the NLU corpus — store slot *shapes* (typed placeholders + recovery recipes) only.
- Don't let automations lower a skill's undoability: automation-origin writes go to Review Feed, not act-then-describe.

## Bring-up order

Phase 0 → throwaway spikes (DSL/meta-schema viability first — hand-encode 3 diverse tasks).
v0 → walking skeleton (macOS).
v1.1–v1.5 → capability ladder; second rung = one user-defined type (validate the emergent-types bet early).
v2 → paid Claude layer.
v3 → ambient.

Experiment-and-reassess, don't march to a release.
