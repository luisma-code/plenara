# Plenara — Claude Code Context

## What this project is

Plenara is a voice-driven, AI-augmented personal assistant app. Solo project by Luis. Core purpose: help him be a better friend, husband, and parent — remembering things about people, surfacing nudges, and helping plan activities and gifts.

**Not a commercial venture.** No investors, no deadlines. The goal is an app Luis genuinely loves and relies on.

## Planning documents

All design specs live in [`planning/`](planning/). Read them before touching architecture or interfaces.

| File | Contents | Status |
|------|----------|--------|
| `planning/plenara_research.md` | Vision, principles, full tech baseline (v0.10) | Locked — do not edit unless Luis says so in-session |
| `planning/specs/01-meta-schema-type-system.md` | Meta-schema kernel, type-def format, automations registry | v0.3 |
| `planning/specs/02-skill-dsl.md` | Skill DSL — primitive vocab, resolve/execute split, execution journal | v0.4 |
| `planning/specs/03-nlu-intent.md` | NLU/intent — routing, corpus, slot-template fast path | v0.5 |
| `planning/specs/04-architecture.md` | Layer contracts, threading, error handling, offline | v0.4 |
| `planning/specs/05-functional.md` | Marquee-task flows, interaction contract | v0.4 |
| `planning/specs/05a-functional-examples.md` | 60 worked examples corpus for NLU model testing | v0.1 |

## Stack

- **Framework:** Flutter / Dart
- **Storage:** per-record JSON files in user-chosen folder (iCloud / OneDrive / Google Drive); no SQL on disk
- **In-memory cache:** Dart object store, hydrated from JSON at startup
- **Local NLU:** corpus fast-path + retrieval-embedding model (~80MB, e.g. bge-small-en-v1.5) + deterministic date/entity resolvers; Haiku for the genuine residual. *(The originally-planned llama.cpp 1B–3B generative router was measured-dead and cut — Phase-3 findings §11–12, Spec 03 §7.3. A small generative model survives only as an optional future tie-breaker.)*
- **Storage caveat:** journal + `sensitive` content **sync** (durable across device loss). At-rest encryption / provider-privacy is **deferred to a later version** — early versions store content as plaintext JSON in the user's own synced folder (`G-37`).
- **Cloud AI:** Claude Haiku 4.5 (most calls) + Sonnet for reasoning; BYOK model
- **Platform targets:** P1 iPhone, P2 Windows desktop, P3 Android, P4 macOS

## Locked design principles

These are settled. Do not relitigate them.

1. **Voice is uncompromising.** Free-form, adaptive. Text/subtitles are overlays — UI is never compromised for keyboard/touch.
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

Five layers: UI → DispatchOrchestrator (BL) → SkillInterpreter + CapabilityIndex → StorageRepository + ExecutionJournal → ClaudeClient. The orchestrator is the only component that touches NLU output and drives the turn pipeline (route → resolve → execute → write-back). One active turn at a time; serial execute queue; inference and bulk-IO move off the UI isolate. Cloud calls are all-or-nothing through one ClaudeClient returning typed CloudResult values (never exceptions); offline is a type-forced case, not an afterthought.

## Things NOT to do

- Don't mock the database in tests — use real storage. The specs were written assuming integration-level correctness checks.
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
