---
name: plenara-product-development
description: Orient Plenara changes to product behavior, architecture, schemas, storage/sync, routing, privacy, voice, or user interfaces. Use before designing or implementing those changes; do not invoke for documentation-only, verification-only, or deployment-only work.
---

# Develop Plenara from current truth

Load only the context needed for the requested area:

1. Use the authority map in [`AGENTS.md`](../../../AGENTS.md) to select the owning active specification. Do not read every specification.
2. Inspect the wired production entry point and its tests. Treat code as evidence of current behavior, not automatic authority for intended behavior.
3. List headings with `rg '^## ' WORK-CAPSULE.md`, then read only the current-state, platform, deployment, or verification sections that affect this task. Do not read the capsule end to end by default.
4. Distinguish implemented-and-wired behavior, declared-but-unwired code, destination design, and historical evidence. Dated reviews and archived handoffs are evidence, not current instructions.

Preserve the owning specification's product priorities and boundaries instead of copying them here. When behavior or a rule changes, use `plenara-doc-alignment` to update the owning spec, affected code, tests, copy, operational documentation, and stale restatements together.

Use real temporary files for storage, migration, sync, and durability work. Pure routing or business-logic tests may use in-memory seams when persistence is not the subject. Production mutations continue through the single durable execution path; execution state never belongs in the synced provider folder.
