# Phase-0 Spike: Storage CRDT (Windows)

**Throwaway** spike validating the storage/sync **decision** (`planning/specs/storage-sync-assessment.md`) on the Windows dev box — the feasible substitute for the (hardware-blocked) iOS spike on everything *except* iOS-specific dataless-file behavior.

`python test_crdt.py` → all pass.

## What it validates

The decision: keep **per-record current-state JSON files** in the user's cloud folder (no backend; the provider is the transport), made mergeable by a **state-based CRDT** — per-field Hybrid-Logical-Clock stamps `(ms, counter, deviceId)`, merged as a per-field last-write-wins register with tombstones for deletes.

- `merge.py` — the ~120-line pure merge.
- `test_crdt.py` — property tests + two-device scenarios + a startup-scale timing.

## Results

**1. ✅ The merge is a proper CRDT — it converges regardless of sync order.**
200/200 randomized seeds pass **idempotent**, **commutative**, and **associative**, which together mean *any* order or duplication of the provider's file deliveries folds to the same state. Concretely: different-field concurrent edits **both survive** (the win over whole-file LWW, which loses one); same-field concurrent edits pick a **deterministic, order-independent** winner (no divergence); delete-vs-edit resolves by clock. **The storage decision is sound** over an unordered, at-least-once, whole-file transport (iCloud/OneDrive/Drive) — which is exactly what those providers give.

**2. 🔑 Finding — precise conflict *surfacing* needs per-field version vectors, not just stamps.**
The spike caught a real bug in my first two attempts: per-field stamps **can't distinguish an unmodified-ancestor value from a concurrent edit**, so a naïve "record the loser" conflict list both over-triggers *and* is order-dependent. The resolution: the **convergent state (fields + stamps + tombstone) is the CRDT**; the conflict list is a **derived, best-effort** UI signal, explicitly *not* convergent state. Trustworthy "you also edited this elsewhere" detection for the AttentionSurface needs **per-field dotted version vectors** — a Spec 06 refinement. The *data* is always correct and convergent regardless; only the optional nudge needs the extra machinery (and the assessment's provider-30-day-history backstop covers the gap meanwhile).

**3. ⚠ Finding — startup full-scan is slow *even on a local desktop filesystem*, independent of iOS.**
Writing 5,000 per-record JSON files then enumerating+parsing+hydrating them took **~22 s in Python on Windows (~230 files/s)**. Even allowing a large factor for Python/Windows overhead, that does **not** support the research doc §8.4 claim of "10,000 files parse in under a second." The lesson is *not* iOS-specific: **"scan the whole folder and parse every file at startup" doesn't scale**, so the **bootstrap-bundle cache** the assessment named (keep a local materialized snapshot; on startup read only *changed* files, not the whole folder) is needed for **desktop too**, not just to dodge iOS dataless files. This also *reframes* the deferred iOS spike: the biggest cost (full cold-scan) is a **shared** weak point the cache mitigates on both platforms — so the iOS-specific residual risk is smaller than it looked.

## What this de-risks vs. the iOS spike

- **De-risked here:** the merge is correct (the core of the storage decision); the full-scan-startup cost is real and now has a required mitigation (bootstrap cache).
- **Still deferred (needs iOS hardware):** whether iCloud *dataless-file* eviction + no-change-notifications make even the *incremental* (changed-files-only) read viable on iOS. The bootstrap cache is designed to absorb a bad outcome; the residual is bounded.

## Verdict

Storage decision **validated on Windows.** Two refinements captured (version-vector conflict detection → Spec 06; bootstrap cache → required, and it de-risks iOS too). Research §8.4's startup budget is revised. Green to build the v0 walking skeleton on Windows.
