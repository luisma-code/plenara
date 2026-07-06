# Phase-0 De-Risking — Status & Wrap-Up

**Context:** Phase 0 (research §11.1) is throwaway spikes to prove the risky bets before the real codebase. The iOS file-sync spike can't run right now (no Apple hardware), so this records what a **Windows dev box has validated**, what's **deferred to iOS hardware** (and why we're not blocked on it), and the **recommended next step**.

## Status by bet

| Bet | Status | Evidence |
|---|---|---|
| **DSL / meta-schema viability** ("capabilities are data") | ✅ **Green** | `spikes/dsl-meta-schema/` — 3 diverse tasks hand-encoded as JSON, run through a two-phase interpreter (8/10 primitives, resolve/execute split holds). Finding folded back: `G-17` entityRef check must be *static* (Spec 02 §6.4). |
| **NLU / routing viability** | ✅ **Settled to the limit of what's testable without real usage** | findings §11–13: the local generative router is measured-dead and cut; the design is corpus fast-path + retrieval + Haiku residual + deterministic extractors (Spec 03 §7.3). Held-out eval confirms the redesign (80% top-1 / 96% recall@5); the act-type gate was rejected as overfit. **One residual unknown: real per-user phrasing-reuse — needs a beta.** |
| **Storage / sync viability** | ✅ **Green on Windows** (merge correct; scan-cost found) | `spikes/storage-crdt/` — the state-based CRDT merge is a proven CRDT (200/200 property tests → order-independent convergence). Two findings: conflict-*surfacing* needs version vectors (Spec 06 refinement); **full-scan startup is slow even on desktop → a bootstrap cache is required** (research §8.4 revised). |
| **Local-model trust** | ✅ **Done** (NO-GO) | findings §11 — the on-device generative model was evaluated and cut. |
| **iOS file-sync backbone** ("the dead-end we most want to find") | ⏸ **Deferred — needs Apple hardware** | Cannot be faked on Windows (iCloud dataless files, no provider change-notifications). Risk is **contained** — see below. |

## Why we're not blocked on the iOS spike

The Windows storage spike **reframed** the iOS risk. The biggest cost — a full cold-scan+parse of thousands of files at startup — turned out to be a problem **on the desktop too** (~22 s / 5,000 files in Python), not an iOS-only surprise. Its mitigation, the **bootstrap-bundle cache** (persist a local materialized snapshot; on launch read only *changed* files, never the whole folder), is therefore **required regardless of platform** — and it happens to absorb most of the iOS cold-start cost as well. So:

- The iOS-specific residual shrinks to: *does even the incremental (changed-files-only) read behave under iCloud dataless-file eviction?* — a **bounded** question.
- The storage layer is designed so a bad iOS answer is **contained** (the cache is a derived accelerator, not a source-of-truth change), so it can't force an architecture rewrite.
- It gets answered at the **first iOS build**, whenever hardware is available — not a blocker for progress now.

## Recommended next step

**Start the v0 walking skeleton on Windows.** CLAUDE.md explicitly sanctions this ("Phase 0 and v0 may use a desktop purely for iteration speed"). The design is now de-risked enough on paper + spikes that the highest-value work is building the thin end-to-end slice:

> type/skill JSON on disk → hydrate → route a typed utterance (corpus + retrieval) → resolve + execute a skill → describe it → persist via per-record files + the CRDT merge.

That exercises every layer boundary against real code, in the target language (Dart/Flutter on Windows), and it's where the next real learning is. The two open threads travel alongside it: the **beta** (to measure phrasing-reuse, the routing make-or-break) and the **iOS build** (to close the one deferred storage question), both when their prerequisites exist.

**Bottom line:** every Phase-0 bet that a Windows box can test is green; the one that needs Apple hardware is quarantined with a contained, already-required mitigation. This is a clean point to shift from design/spikes to building v0.
