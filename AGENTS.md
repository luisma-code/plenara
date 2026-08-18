# Plenara project instructions

This file is the canonical project-specific guide for coding agents. Cross-project working preferences belong in the user's global agent instructions; do not copy them here. `CLAUDE.md` is a compatibility pointer to this file, not a second authority.

## Product

Plenara is Luis's voice-first, AI-augmented personal planner and relationship assistant. Its purpose is to help him remember people and commitments, plan realistically, and follow through as a friend, husband, and parent. It is a personal product, not a commercial venture; optimize for an app he genuinely loves and relies on.

Nothing in the repository is intrinsically set in stone. Treat principles and specifications as current decisions with history, not constraints on Luis. If his request conflicts with a written rule, implement the request where safe, identify the displaced rule and its origin, and update every active restatement in the same change.

## Start every session with current truth

1. Read [`WORK-CAPSULE.md`](WORK-CAPSULE.md) for live state, commands, deployments, platform facts, and owner-only blockers.
2. Read the specifications that own the area before changing architecture, product behavior, storage, privacy, voice, or interfaces.
3. Treat [`reviews/`](reviews/) and archived handoffs as historical evidence. Do not silently rewrite old findings after a decision changes.
4. Keep `WORK-CAPSULE.md` current when non-obvious facts, decisions, deployments, blockers, or verification results change.

## Authority map

| Source | Authority |
|---|---|
| [`planning/specs/17-living-planner.md`](planning/specs/17-living-planner.md) | Today / Plan / Library / History product model and multimodal interaction |
| [`planning/specs/11-feedback-diagnostics.md`](planning/specs/11-feedback-diagnostics.md) | Diagnostic collection, content, export, and channel boundaries |
| [`planning/specs/01-meta-schema-type-system.md`](planning/specs/01-meta-schema-type-system.md) through [`planning/specs/06-data-sync.md`](planning/specs/06-data-sync.md) | Schema, capability DSL, routing, architecture, behavior, and storage/sync |
| [`planning/specs/07-ui-design-language.md`](planning/specs/07-ui-design-language.md) through [`planning/specs/16-routines.md`](planning/specs/16-routines.md) | Visual language, AI/privacy, testing, security, voice, reference data, presence, and routines |
| [`planning/implementation-plan-2026-08-17.md`](planning/implementation-plan-2026-08-17.md) | Implemented review-remediation program and its acceptance evidence |

The research document and worked examples preserve rationale and evaluation history. When they conflict with a later active specification or wired behavior, label the distinction rather than presenting both as current.

## Current product and implementation facts

- Flutter/Dart app; P1 iPhone, then Windows, Android, and macOS.
- Per-record JSON storage in a device-local or user-selected provider folder; no SQL on disk.
- User records, including journal and `sensitive` fields, currently sync as plaintext JSON. Execution/undo history, conversation history, operation state, and diagnostics are device-local and currently plaintext.
- Routing is corpus fast path -> deterministic in-process feature-hash retrieval -> cloud residual -> clarification. The old localhost and packaged generative-router plans are not current runtime dependencies.
- `Session` owns the current walking turn pipeline. Production mutations converge on `ExecutionCoordinator`, durable device-local `ExecutionJournal`, and `StorageRepository`.
- Internal/development builds intentionally retain content-bearing diagnostic exchanges and allow manual raw export because Luis is the sole beta tester. External builds capture none. Raw audio and secrets are forbidden in every channel. Do not "scrub" the approved internal logs by silently changing this boundary.

## Product defaults

- Voice is first-class and free-form, with outcome parity. Visible UI is equally responsible for persistent state, comparison, planning, and precise editing; it is not merely a subtitle overlay.
- Understood, undoable requests act first and then describe the result. Non-undoable type/skill deletion may confirm; unattended automation writes go to Review Feed.
- Prefer deterministic code for repeatable work. AI fills genuine gaps and may author human-readable declarative capabilities; shipped code remains the executor.
- Preserve UI -> business logic -> storage/intelligence/voice boundaries and the import-lint gate.
- No silent failure: clarify ambiguity, explain policy blocks, and make failures visible and actionable.
- Design priority is usability, then capability, performance, and minimalism.

## Non-negotiable operational boundaries

- The physical iPhone is deployment-only. Never run tests, probes, experimental builds, log collection, layout checks, or automated launches on it. Touch it only when Luis explicitly requests a usable deployment. All verification uses local simulators, widget/render surfaces, or macOS.
- A separate explicit request to read device logs authorizes only that read; it does not turn the phone into a test target.
- When launching an app locally, sample memory, kill a ballooning process immediately, terminate every instance started, and check for orphan processes. A short plateau is not a leak-free claim.
- Keep the Mac awake during an active long-running session with `caffeinate -dimsu`; do not leave app/test processes running afterward.
- Storage, migration, sync, and durability tests use real temporary files. Pure routing/business tests may use in-memory seams when persistence is not the subject.
- Never put execution state in the synced provider folder. Do not add pre-action confirmation to undoable actions. Do not cache user slot values in the routing corpus.

## Verification and maintenance

- Run `bash tool/precheck.sh` before reporting an implementation complete. Use focused checks while iterating, but the final claim is based on the full gate.
- A new or changed test/verifier must be calibrated: show it the real broken state, observe failure, restore the implementation, and observe success.
- Update code, owning specification, user-facing copy, tests, and operational docs together when a rule changes. `dart run tool/doc_consistency.dart` guards known drift but does not replace prose review.
- Use the repo skill `plenara-simulator-verification` for app launches, voice/UI integration, rendering, or motion checks; `plenara-doc-alignment` for rule/spec/document changes; and `plenara-phone-deploy` only after an explicit deployment request.

## Project agent definitions

Project-scoped agent roles live in [`.codex/agents/`](.codex/agents/). They are available for an explicitly requested parallel/delegated review or simulator-verification effort; their existence is not standing permission to spend tokens or perform external actions.
