# Plenara code/spec/document consistency review

**Date:** 2026-08-17  
**Scope:** production Dart/Flutter behavior, active Specs 01–17, research/product principles,
operator/release/privacy docs, historical handoffs, and the repository quality gate.  
**Result:** the tracked repository is internally consistent after the corrections in this pass. No
known current behavior is still presented as shipped when it is only a target. One untracked local
instruction file remains an owner decision, described at the end.

## Executive verdict

The implementation is materially ahead of several July specifications. The code is not generally
violating the product design; the dominant fault was that older destination architecture and
historical operating instructions were still written in present tense. That made five distinct
products appear to coexist:

1. an overlay-only voice orb with push-to-talk;
2. a Windows walking skeleton needing a localhost embedding server;
3. a future architecture with a merged capability index, numeric opcodes, worker isolates, and
   encrypted journals;
4. the actual living planner with tap-toggle voice, visible Today/Plan/Library/History, an
   in-process feature-hash router, durable plaintext device-local execution state, and six cloud
   synthesis kinds;
5. historical handoff/release instructions presented without an archive boundary.

The fourth is now consistently identified as current. The others are either explicitly labeled
historical or explicitly labeled target designs.

## Authority order used

For a claim about what a user can do today, I used this order:

1. wired production behavior and its passing tests;
2. [Spec 17](../planning/specs/17-living-planner.md) for the current product/surface model;
3. the owning subsystem spec for an invariant;
4. [CLAUDE.md](../CLAUDE.md), [DOGFOOD.md](../DOGFOOD.md), and
   [WORK-CAPSULE.md](../WORK-CAPSULE.md) for current operation;
5. research, gap reviews, handoffs, and retrospectives as design history.

This order is now written into the affected documents instead of being implicit.

## Misalignments corrected

### 1. Voice-first had become voice-only in older prose

**Before:** research and the project context said text was only an overlay and the primary canvas
must never change for visible UI. Voice and architecture specs also retained push-to-talk body text
after tap-toggle had shipped.

**Actual:** the product is a visible living planner. Voice remains global and free-form, while
Today, Plan, Library, History, detail editors, proposals, and repair views externalize persistent
state. Touch voice capture is tap once to start and once to stop.

**Correction:** [research §6.2/§6.5](../planning/plenara_research.md),
[Spec 04](../planning/specs/04-architecture.md), [Spec 07](../planning/specs/07-ui-design-language.md),
[Spec 12](../planning/specs/12-voice.md), [Spec 15](../planning/specs/15-presence.md), and
[CLAUDE.md](../CLAUDE.md) now say the same thing. Spec 17 is explicitly the surface authority.

### 2. Retrieval documentation described an unshipped model and owner

**Before:** multiple active docs said a packaged bge-small-class model and merged registry-owned
`CapabilityIndex` were shipped; the v0 README said production required a localhost embedding
server.

**Actual:** `Router` builds a skill-only, in-memory, deterministic 384-dimensional feature-hash
index. Only calibrated candidate-specific lanes can execute from retrieval. Rules, learned
templates, and the closed-set cloud residual handle generative/system recognition. No model file or
companion service is required.

**Correction:** [Specs 01](../planning/specs/01-meta-schema-type-system.md),
[03](../planning/specs/03-nlu-intent.md), [04](../planning/specs/04-architecture.md),
[13](../planning/specs/13-reference-knowledge-bases.md), research, and
[DOGFOOD.md](../DOGFOOD.md) now separate current feature hashing from a gated transformer/merged-index
target. [v0/README.md](../v0/README.md) is clearly marked as a historical walking-skeleton record.

### 3. Destination interfaces were being read as a class inventory

**Before:** the architecture claimed concrete standalone `DispatchOrchestrator`,
`AuthoringService`, `CapabilityIndex`, `CryptoBox`, inference isolate, and I/O workers.

**Actual:** `Session` currently owns dispatch and authoring coordination;
`ExecutionCoordinator` is the mutation/journal/undo door; `OperationCenter` serializes detached
work; `FileStorageRepository` owns files/reconciliation; Router owns current skill retrieval. File
and feature-hash work currently run on the main isolate. At-rest record/journal encryption is
deferred.

**Correction:** [Spec 04](../planning/specs/04-architecture.md) now begins with an implementation map
and labels its richer interfaces/topology as destination boundaries. The storage, threading,
startup, authoring, and cancellation sections no longer claim worker/isolate behavior that does not
exist.

### 4. The skill spec claimed numeric compilation and the wrong journal shape

**Before:** portions of Spec 02 said symbolic skills compiled to numeric opcodes and persisted a
`compiledFormVersion`/numeric action chain, despite another amendment calling compilation future
work.

**Actual:** validated structured JSON is interpreted directly through symbolic `op` dispatch.
`ExecutionCoordinator` persists concrete write/delete operations, exact before-images, phase, and
the next operation index in one bounded device-local ledger.

**Correction:** [Spec 02](../planning/specs/02-skill-dsl.md) now uses the actual journal envelope and
labels numeric opcodes as a performance target only. [Spec 04](../planning/specs/04-architecture.md)
uses the same current record shape.

### 5. Device-local did not mean encrypted

**Before:** several security/architecture statements called the execution journal and content index
encrypted at rest.

**Actual:** the journal is device-local but plaintext under OS data protection. Content search is an
in-memory feature-hash map and has no persisted file. Only the Anthropic credential is in platform
secure storage today.

**Correction:** [Specs 02](../planning/specs/02-skill-dsl.md),
[04](../planning/specs/04-architecture.md), [06](../planning/specs/06-data-sync.md), and
[10](../planning/specs/10-security-privacy-threat-model.md) now state that precisely. Future
`CryptoBox` protection remains an explicit hardening target rather than a false present-tense claim.

### 6. The cloud feature set drifted across four owners

**Before:** Specs 03–05 described eight to ten generative kinds, including event prep, meal
suggestion, monthly reflection, and foresight. The engine, egress declarations, and Settings expose
only six.

**Actual implemented set:** `briefing`, `draft_message`, `gift_ideas`, `pattern_insight`,
`reconnect`, and `weekly_review`.

**Correction:** [Spec 08 §3.3](../planning/specs/08-ai-cost-privacy.md) is the prose owner and now
contains a machine-readable implemented-kind marker. Candidate kinds remain labeled future. The
same spec no longer includes unimplemented monthly reflection in a current monthly-cost promise.
Specs 03–05 and 07 defer to this registry.

The new consistency gate compares four executable/documented copies on every precheck:

- `ClaudeClient`'s accepted residual kinds;
- `generativeDataClasses`, the deterministic egress registry;
- Settings' user-facing labels;
- Spec 08's implemented-kind marker.

### 7. Journal consent was described as active when exclusion is the active rule

**Before:** functional/architecture prose said pattern insight could ask to include journal text and
monthly reflection used a consent card.

**Actual:** every current assembler excludes journal records. There is no journal opt-in flow.

**Correction:** current docs state categorical exclusion. Per-session consent remains a required
design for a future journal-based feature, not a present surface.

### 8. Internal diagnostics policy had one public contradiction

**Before:** Spec 11 and the implementation plan correctly allowed content-bearing internal traces,
including recognizer hypotheses, but the public privacy policy said interim transcripts were
excluded from internal exports.

**Actual and approved policy:** development/internal traces may retain hypotheses needed to
reconstruct native capture finalization failures; external builds capture no raw content. Raw audio
and secrets are prohibited in every channel. Upload is never automatic.

**Correction:** [PRIVACY.md](../PRIVACY.md), [Spec 11](../planning/specs/11-feedback-diagnostics.md),
[Spec 12](../planning/specs/12-voice.md), [Spec 10](../planning/specs/10-security-privacy-threat-model.md),
the implementation plan, and WORK-CAPSULE now match.

### 9. Operator docs could send a developer down unsafe or dead paths

**Before:** DOGFOOD instructed plaintext-key config, a localhost server, volatile undo, and an old
chat surface. Old handoffs and release notes lacked a clear authority boundary.

**Correction:** [DOGFOOD.md](../DOGFOOD.md) is a current cross-platform operating guide. It points
to Settings/secure storage, in-process retrieval, current planner interactions, tap-toggle voice,
six cloud kinds, channel-specific diagnostics, and real iOS limitations. HANDOFF,
SESSION-HANDOFF, TRANSITION, RELEASING, and v0/README have archive banners and current-doc links.

### 10. A live error still directed users to plaintext config

`Session.cloudReason` told a missing/rejected-key user to edit `~/.plenara/config.json`, while the
app had already moved credentials to secure storage and Settings. The copy now points to Settings in
[session.dart](../v0/lib/session.dart), with regression assertions in
[cloud_result_test.dart](../v0/test/cloud_result_test.dart).

The test was calibrated: with the old copy restored, the two new assertions failed on the exact
`config.json` text; with the corrected copy, the focused suite and full suite passed.

## Durable consistency gate

[tool/doc_consistency.dart](../tool/doc_consistency.dart) now runs near the start of
[tool/precheck.sh](../tool/precheck.sh). It currently verifies:

- 28 active documents exist;
- 18 relative Markdown links resolve;
- 19 retired high-risk claims have not returned;
- the six cloud kinds match across runtime acceptance, deterministic egress, Settings, and Spec 08;
- historical handoffs retain archive banners and current-state pointers.

The instrument itself was calibrated. I deliberately changed Spec 12's current tap-toggle heading
back to “Push-to-talk is primary”; the gate failed on that exact claim. Restoring tap-toggle made it
green. This proves the added check can detect at least one real class of drift rather than merely
reporting success.

## Verification

The final tree passed the complete repository gate:

- documentation consistency: 28 docs, 18 relative links, 19 retired-claim guards, six cloud kinds;
- pure-Dart analysis and import layering: clean;
- engine: **1,922 passing tests + 36 intentional conformance skips**;
- coverage: **94.7% deterministic core / 90.5% product logic / 68.1% transport**;
- Flutter analysis: clean;
- visual verifier calibration tests: 2 passing;
- Flutter widget tests: **161 passing + 3 development-channel skips**;
- external-channel reachability: 3 passing;
- macOS debug build: successful;
- real-engine macOS integration: **7 passing**, including animated presence, planner surfaces,
  task-title/edit vs circle/complete, secure-store round trip, and startup reset;
- tracked secret scan: clean;
- conformance ratchet: **24/60**, unchanged and passing.

No simulator or physical phone was used for this documentation/code-copy pass. The host integration
runner terminated normally, and no Plenara, Runner, flutter_tester, or integration-test process was
left running.

## Explicit targets that are no longer confused with shipped behavior

These remain valid design options, but the docs now label them honestly:

- merged type/skill/generative `CapabilityIndex` and a packaged sentence transformer;
- numeric-opcode skill compilation;
- inference and bulk-I/O worker isolates;
- bootstrap snapshot/fingerprint cache;
- at-rest encryption for sensitive records and the execution journal;
- independent Layer-3 authoring safety review;
- sensitive-skill marker/exclusion;
- native iOS provider-event adapter for live reconciliation;
- event prep, meal suggestion, monthly reflection, and foresight cloud kinds.

## Owner decision: the one remaining local inconsistency

The repository root contains an **untracked, user-owned `AGENTS.md`**. It still says the local NLU
ships an ~80 MB retrieval model and that text is overlay-only, and it names the old concrete
architecture. Those statements conflict with the now-consistent tracked repo and with Spec 17.

I did not edit, stage, or commit that file because it is an untracked owner instruction file rather
than project source. My recommendation is to update its project-context section to match
`CLAUDE.md`/Spec 17 while preserving its working-process rules. The product choice is whether that
file should remain machine-local or become a tracked project instruction; either is coherent, but
leaving its current product claims unchanged is not.

The future target set above raises a second, lower-stakes cleanup decision: keep those ideas as
explicit roadmap contracts, or retire them from the active specs until evidence calls for them. I
recommend keeping only security obligations (encryption/review) as committed targets and treating
the packaged model, compiler, worker topology, bootstrap cache, and four candidate cloud kinds as
evidence-gated options—as the corrected specs now do.
