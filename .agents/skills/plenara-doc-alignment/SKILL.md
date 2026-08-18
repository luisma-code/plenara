---
name: plenara-doc-alignment
description: Keep Plenara code, active specs, tests, copy, and operational docs consistent when behavior, architecture, privacy, or product rules change. Do not rewrite historical review evidence as current truth.
---

# Align Plenara's current truth

Start from the wired behavior and the owning active specification identified in [`AGENTS.md`](../../../AGENTS.md). Distinguish four states explicitly: implemented and wired, declared but unwired, destination design, and historical evidence.

- Give each rule one authoritative home. Replace duplicate prose elsewhere with a short pointer or a deliberately scoped summary.
- Search the whole repository for every restatement of the changed rule, including tests, comments, scripts, UI copy, privacy/release material, and agent instructions. Fix stale active content in the same change.
- Preserve dated reviews and archived handoffs as evidence. Add or maintain their historical banner and current-state pointer instead of rewriting their original finding.
- Keep [`WORK-CAPSULE.md`](../../../WORK-CAPSULE.md) current and concise.
- Extend `tool/doc_consistency.dart` only for a concrete invariant that has drifted. Calibrate a new guard by reintroducing the actual retired claim, observing a named failure, restoring the correction, and observing green.
- Run `dart run tool/doc_consistency.dart`, then `bash tool/precheck.sh` before completion.
