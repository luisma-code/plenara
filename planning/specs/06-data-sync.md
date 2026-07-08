# Spec 06 — Data & Sync

**Status:** Draft v0.1 — July 2026 (Claude Fable 5 first draft. Formalizes and **supersedes** the preliminary [storage-sync assessment](storage-sync-assessment.md): its Option-C verdict is adopted here as normative design, its recommendations amended where later calls overrode them — see D2, D15. Documents the storage decisions **actually implemented** in `v0/lib/store.dart` / `v0/lib/storage_repository.dart` as the format baseline, and lists where v0 must still be brought into conformance — §11.)
**Depends on:** Research doc v0.10 (§4.9, §8, §10.3, §11.1); Spec 01 §§4.5, 5, 7, 8, 12; Spec 02 §5; Spec 03 §5; Spec 04 §§3.1, 3.11, 3.12, 4.5, 5, 7; storage-sync-assessment.md; the v0 implementation.
**Blocks:** Spec 09 — Test (merge property tests, §6.1); the iOS file-sync spike (05c D-1) charter (§9.5); the P2 (second-device) milestone (§6.1, §10.1).

---

## 0. Purpose & Scope

This spec is research §12 item 6: it extends the storage foundation of research §8 to the world the emergent type system creates — user-defined types persisting over a user-owned, cloud-synced folder with **no backend and no sync protocol of Plenara's own**. It defines:

1. The **file layout** of the synced folder and the device-local store, as actually shipped in v0 (§3)
2. The **record envelope and clock model** — per-record JSON with per-field hybrid-logical-clock (HLC) stamps and a per-install `deviceId` (§4)
3. The **atomic-write guarantees** every persist path must honor (§5)
4. **Conflict handling** — the state-CRDT per-record merge for instance records, and the escalate-on-ambiguity rule for type/skill files (Spec 01 §7.5) with the detection mechanics that make it implementable (§6)
5. **Tombstones and garbage collection** (§7)
6. The **migration runner over a synced folder** — per-record `schemaVersion`, the migrate-on-read guard, version skew between devices, and failed-migration repair (§8)
7. The **startup-scan performance budget** and the bootstrap cache that keeps hydration off the voice-latency path (§9)
8. The **machine-owned hot files** — corpus, settings, turn log — which follow different rules than records (§10)

It does **not** cover: the `StorageRepository` interface semantics (Spec 04 §3.1 owns the seam; this spec owns what is behind it), at-rest encryption (Spec 01 §8.7 — **deferred**; this spec stores plaintext and reserves the envelope slot, D16), the corpus's *content* and learning semantics (Spec 03 §5), or provider path acquisition per platform (research §8.5). Where this spec and the research doc's §8 sketch disagree, this spec is authoritative and the divergence is recorded (D3, D4, D13).

**A scoping fact that shapes everything here** (assessment §1.1): the write surface is mostly append-only by construction — new records are new UUID-named files that can never collide across devices. The machinery below is deliberately sized to the *actual* conflict profile of a solo user with 2–4 devices: rare offline divergence on a small mutable surface (`task.completed`, `contact` fields), not high-contention multi-writer sync.

---

## 1. Governing Principles

**P1 — The folder is the spine; there is no backend** (research §8.1). Plenara's only transport is the user's own cloud-sync client moving whole files. Every design below must be correct over that transport as it actually behaves (§2), not as a database would behave.

**P2 — Human-readable current state is load-bearing** (assessment §3.4). A record file, opened in any text editor, is a plain statement of that record's current state. This is what makes "your data outlives the app" true, and it is part of the App Store 2.5.2 auditability story (research §13.6). Merge metadata rides along as an ignorable `_meta` trailer; the truth of a record is never a computation over event streams. This principle is why per-device event logs were **rejected** as the record format (assessment §3, D1).

**P3 — Single-writer or mergeable.** Every synced file is in exactly one of two classes: written by a single device (per-device corpus files at P2, §10.1) or carrying enough metadata to merge deterministically when two versions meet (records, §4; and the special-cased definition files, §6.3). A shared-mutable synced file with neither property is a design defect (`G-36` is the register entry for the one v1 carries knowingly — §10.1).

**P4 — Format before engine** (assessment §6.3). The on-disk format pays its full multi-device cost from the **first record ever written** — per-field stamps, tombstones, stable deviceId — even though the merge *engine* ships only at P2. Format is the part that cannot be retrofitted without a migration; the engine is a pure function added later. v0 implements the format (§4); the engine is specified here (§6.1) and built after the iOS spike, before P2.

**P5 — No silent failure** (P2.8). A sync conflict, a corrupt file, a failed migration, a record the schema cannot read — each lands on the `AttentionSurface` (Spec 04 §3.12) with an action, never in a log nobody reads and never in silent data loss. The one *bounded, named* exception is the dead-device window (§6.1), accepted explicitly as the price of no-backend.

**P6 — Aggressive layering** (P2.5). Everything in this spec lives behind `StorageRepository` (Spec 04 §3.1). Business logic never touches a path, a stamp, or a merge; if folder-JSON sync ever proves unworkable, this entire spec is replaced behind that seam (research §2.5).

**P7 — Storage is type-agnostic** (Spec 01 §5, Spec 04 §2.2). The storage layer knows the kernel envelope (§4.1) and nothing else. A `meal` record and a `task` record are stored, stamped, merged, and migrated by identical code paths — this is what lets user-defined types get sync and conflict handling "for free" (research §4.2).

---

## 2. The Transport Model — What the Folder Actually Guarantees

Everything below must survive these transport facts (assessment §1.3, research §8.5). They are assumptions in the formal sense: a design that needs more than this is wrong.

| # | Fact | Consequence |
|---|---|---|
| T1 | Unit of sync is **whole-file replacement** | No partial/ranged transfer; append-heavy files re-upload entirely (why records stay small, §3.1) |
| T2 | **No cross-file ordering** | File B's update can arrive before file A's even if written after; readers must tolerate any interleaving (§6.2, §8.3) |
| T3 | **Arbitrary delay** — minutes to hours, especially iOS background sync | Merge must be time-independent; no protocol step may wait on "the other device" |
| T4 | **At-least-once, duplicated delivery** — the same content may be re-observed | Every reconcile action must be idempotent (§6.2) |
| T5 | **Provider-specific conflict behavior** — iCloud keeps `NSFileVersion` versions (effectively silent LWW unless asked); OneDrive sometimes mints "conflicted copy" siblings; Drive keeps versions | The merge cannot rely on the provider surfacing conflicts; the conflict-copy sweep (§6.5) is best-effort recovery, not the mechanism |
| T6 | **iOS dataless files** — evicted content costs a full download to read | Startup must not require reading every file (§9.2); measured by the D-1 spike (§9.5) |
| T7 | **File timestamps are advisory** — sync clients set mtimes from source metadata across skewed clocks | mtime/size fingerprints drive the *scan* (§9.2) but are never merge authority; only HLC stamps decide a merge (§4.2) |

The formal fit (assessment §4): over an unordered, at-least-once, whole-file transport, a **state-based CRDT** — exchange full states, merge commutatively/associatively/idempotently — is the natural design, because the provider's file sync *is* the anti-entropy channel and no watermark/segment/compaction machinery is needed. That is what §4 + §6.1 implement.

---

## 3. File Layout

### 3.1 The synced root

The user-chosen folder (`dataDir`; pointed at an iCloud/OneDrive/Drive/Dropbox location — research §8.1, `v0/lib/config.dart`):

```
Plenara/                              ← the synced root; everything here syncs
  types/{typeId}.json                 ← one file per type definition, seeds included (Spec 01 §4)
  skills/{skillId}.json               ← one file per skill (Spec 02)
  automations/{automationId}.json     ← the trigger registry (Spec 01 §4.4)
  templates/{templateId}.json         ← built-in tracker templates, seeded at first run (§3.4)
  records/{recordId}.json             ← ONE FLAT FOLDER, all instance records of all types (D3)
  corpus.json                         ← the shipped seed corpus (read-only after seeding, §3.4)
  corpus-learned.json                 ← the learned corpus, Lane 1 (single file in v1 — §10.1)
  settings.json                       ← user preferences (whole-file LWW in v1, §10.2)
  audit/{assessmentId}.json           ← stored safety assessments (research §13.2; written by AuthoringService)
```

**Records live in one flat `records/` folder, keyed by record id, with `typeId` inside the envelope** — the decision v0 actually made (`store.dart loadRecords`, `FileStorageRepository`), **superseding** research §8.2's per-type-folder sketch (`tasks/`, `meals/`, …). Rationale (D3): the storage layer is type-agnostic (P7) and should not encode schema into the directory tree; a type merge (Spec 01 §6.2) or rename would otherwise relocate thousands of files (churning sync, T1); and a single folder is one directory listing at scan time (§9.2). The per-type view research §8.2 wanted is an in-memory index over `typeId`, not a filesystem shape. What research §8.2 got right is kept: aggressive per-record granularity, `schemaVersion` on every file, and conflict isolation to one small file per record.

**Journal entries are ordinary records** in `records/`, per the assessment (§6.3 item 3) — **not** the date-keyed `journal/YYYY-MM-DD.json` files of the original research §10.3, which mint a guaranteed create/create collision when two devices journal the same day. The navigability that research §10.3's amended naming (`YYYY-MM-DD-<id>.json`) wanted is preserved by convention, not by location: a `journal_entry` record's *id* is minted date-prefixed (`2026-07-07-a1b2c3…`), so the filename sorts chronologically while remaining globally unique (D4). Journal entries sync like every record (`G-37`, Spec 01 §12.3 — device-loss durability beats provider-privacy until §8.7 encryption ships).

**Size discipline (T1):** a record file is ~0.5–2 KB; nothing in the synced root is append-per-turn except `corpus-learned.json` (the known, register-tracked exception — §10.1). The high-frequency machine files live device-local (§3.2).

### 3.2 The device-local store (`[app-support]/plenara/`)

Never synced; everything here is rebuildable from the synced root or is volatile per-device state:

```
[app-support]/plenara/
  device-id                           ← the per-install HLC deviceId (§4.3 — D6; landed, §11 V1)
  executions/{executionId}.json       ← the execution journal (Spec 02 §5.2, Spec 04 §3.3)
  index/                              ← CapabilityIndex binaries (Spec 01 §5.4, Spec 03 §10 MD9)
  search-index/                       ← ContentSearchIndex (Spec 04 §3.14)
  bootstrap/                          ← the hydration snapshot + fingerprint map (§9.2 — D13)
  turnlog.jsonl                       ← per-turn diagnostics (research §14.2; landed, §11 V6)
  nlu/plan-cache                      ← Lane 2, deferred (Spec 03 §5.1)
```

*(v0 packaging note: v0's concrete device-local home is the app-**injected** `deviceDir` — `~/.plenara`, `config.defaultDeviceDir`, the same non-synced home as the config/key, threaded `Session → FileStorageRepository` and defaulting to `dataDir` for CLI/tests (commit `d956390`). The `[app-support]/plenara/` path above is the v1 packaging of the same role.)*

The dividing rule, restated from Spec 02 §5.2 / Spec 03 §5.1: **earned user data syncs; volatile execution state and rebuildable artifacts do not.** A binary index inside the synced root would force every sync engine to special-case an exclusion no provider reliably offers (`G-37`) — so nothing device-local ever sits under the synced root.

### 3.3 What ships in the binary vs. what is seeded into the folder

v0's `ensureSeeded` (`config.dart`) records the decision: on first run against an empty folder, the shipped seed **types, skills, templates, and seed corpus are copied into the synced folder**, and everything accretes there thereafter — "the whole 'capabilities are data' surface lives in the user's own synced folder." This is the concrete form of Spec 01's "no privileged class of built-in type — only seed types loaded at first launch" (P2.6): after first run, the app treats a seed type identically to an authored one, reading it from `types/` like any other.

Two consequences this spec makes explicit:

- **Seeding is idempotent and non-clobbering.** `ensureSeeded` runs only when `types/` is empty. On a *second* device pointing at an already-populated folder, seeding is a no-op — the synced definitions are the truth, including any user edits to them. App updates that revise a seed type do so through the normal migration path (Spec 01 §5.2 step 3 — mismatched seed `schemaVersion` triggers in-app migration), never by re-copying over the folder.
- **Templates are shipped content that becomes folder content.** Spec 01 §12.4 (`G-22`) calls templates "binary-shipped `(type + bundled skills)` pairs"; v0 materializes them into `templates/` at seeding so `instantiate-template` (Spec 02 §9) reads them uniformly through `loadDefs`. Reconciliation: the *authoritative source* of a template remains the app binary (a new install always has the current set); the folder copy is a materialization that may lag after an app update, and template instantiation reads the binary's version when the two differ. Template files are never user-edited; a template conflict is resolved by re-materializing from the binary (no §6.3 escalation needed).

---

## 4. The Record Envelope & the Clock Model

### 4.1 The on-disk envelope

Normative form (implemented in `store.dart persist`, extended per D5/D8; a full example after merge activity):

```json
{
  "id": "d4e5f6-…",
  "typeId": "contact",
  "schemaVersion": 1,
  "createdAt": "2026-07-03T08:00:00Z",
  "parentId": "…",
  "fields": {
    "displayName": "Sarah Mitchell",
    "birthday": "1990-11-14",
    "notes": "…"
  },
  "_meta": {
    "vv": { "dev-a1b2c3d4e5f6": 12, "dev-0f9e8d7c6b5a": 3 },
    "stamps": {
      "displayName": { "ms": 1751529600000, "counter": 0, "deviceId": "dev-a1b2c3d4e5f6" },
      "birthday":    { "ms": 1751745243412, "counter": 0, "deviceId": "dev-0f9e8d7c6b5a" },
      "notes":       { "ms": 1751655731007, "counter": 2, "deviceId": "dev-a1b2c3d4e5f6" }
    },
    "conflicts": []
  }
}
```

| Field | Rule |
|---|---|
| `id` | The record's UUID; equals the filename stem. Immutable. Journal-entry ids are date-prefixed (§3.1). |
| `typeId` | The owning type (Spec 01 §4.2). Immutable. |
| `schemaVersion` | The type's `schemaVersion` in effect when the record was last written/migrated (Spec 01 §7). **Absent ⇒ reads as 1** (D5) — this is the defined semantics for every record v0 wrote before the field landed (§11), and it is safe because all v0-era types are at version 1. |
| `createdAt` | Write-once, set at mint. Plaintext metadata per Spec 01 §8.2. |
| `parentId` | Present iff the type is owned (Spec 01 §4.5); plaintext so children index without decryption. |
| `fields` | Every attribute value, current state, human-readable (P2). In the deferred-encryption v1 posture this includes `sensitive` values as plaintext (Spec 01 §8.7 deferral, Spec 04 §3.1 v1 posture note). The envelope **reserves** a sibling `encryptedPayload` slot for when §8.7 ships; nothing here changes then except which values sit where. |
| `_meta.vv` | Per-record version vector: `deviceId → write count` (D8; assessment §4.1). Detects concurrent-vs-ordered versions at merge. **Required from the next format revision; absent in v0-written records** — see the legacy rule in §6.1. |
| `_meta.stamps` | Per-field HLC tag of the last write to that field (§4.2). The merge authority. |
| `_meta.conflicts` | Losing values stashed by a concurrent same-field merge (§6.1), carried until the user resolves or GC (§7). |
| `_meta.deleted` / `deletedStamp` | Tombstone marker (§7). |

**`lastModified` is derived, not stored, and is never merge authority** (D5 — a deliberate reconciliation). Spec 01 §8.2 lists a stored `lastModified`; research §8.2 leans on it for the startup scan; Spec 04 §3.11 uses "fresh `lastModified`" as the tombstone-revival tiebreaker. All three roles are reassigned: merge authority is HLC stamps only (§4.2), the startup scan uses filesystem fingerprints (§9.2, per T7), and tombstone revival is decided by stamp comparison (§6.6). A stored whole-record `lastModified` would be a second clock that can disagree with the stamps — it is dropped from the envelope rather than maintained as a lie. Where other specs display "last modified," it is `max(stamps).ms` computed at read.

### 4.2 The hybrid logical clock

Each device maintains one HLC (`store.dart HlcDevice`): a wall-clock millisecond value plus a logical counter, Kulkarni-style, so clock skew cannot reorder causally related writes (assessment §4.1).

- **Stamp shape:** the structured map `{ms, counter, deviceId}` — the form v0 actually writes, adopted over the assessment §4.1 string-tag sketch (D7: same information; structured beats re-parsing).
- **Send rule** (implemented): stamping advances `ms` to `now` if the wall clock moved forward, else increments `counter`. Monotonic per device by construction.
- **Receive rule** (specified here; not yet in v0, which never observes remote stamps — §11): whenever hydration or a merge observes a stamp with `ms` greater than the local HLC's `ms`, the local HLC advances to it (counter resets past the observed counter). This preserves causality across devices: a write made *after seeing* a remote value always out-stamps it, even under backward wall-clock skew. A remote `ms` implausibly far ahead of local wall time (> `maxClockDriftMs`, default 1 hour) is still adopted — convergence beats suspicion — but logged to diagnostics (Q7 owns tightening this).
- **Total order:** stamps compare by `(ms, counter, deviceId)` — deviceId lexicographic as the final tiebreaker, which is the entire reason deviceId is in the stamp (§4.3).

### 4.3 The per-install `deviceId`

A stable, random, per-install identifier (`dev-` + 12 hex; `storage_repository.dart _deviceId`), minted on first run and persisted. Its sole job is the HLC tiebreak: two installs sharing an id would produce indistinguishable stamps and silently corrupt the CRDT tie-break — which is why v0 replaced the earlier constant `'this-device'` before any real data was written (the code comment records this as a deliberate format decision).

**Location (D6): device-local, never in the synced folder — ✅ LANDED (commit `d956390`).** v0 formerly persisted it at `{dataDir}/.device-id`, i.e. *inside the synced root* — which would sync to the next device, which would then adopt the *same* id, defeating the field's entire purpose the moment a second install exists. The fix: the deviceId now lives in a device-local `deviceDir` **injected by the app** (`~/.plenara`, `config.defaultDeviceDir`; defaults to `dataDir` only for CLI/tests), off the synced folder — V1 in §11 is closed, before any second install existed. The v1 packaging target remains `[app-support]/plenara/device-id`. Per-install also means: a restore-from-backup or reinstall mints a *new* id (the old one simply stops appearing in fresh stamps; no retirement protocol is needed under state-based merge — the id lingering in old stamps and `vv` entries is inert history, one of the concrete wins over event logs, assessment §3.1).

### 4.4 Stamp-on-change

Implemented in `store.dart persist` and normative: on every write, a field receives a fresh stamp **only if its value actually changed**; unchanged fields carry their prior stamp (and prior `conflicts`) forward. Without this, every whole-record save would re-stamp every field and the per-field metadata would collapse into whole-record LWW — the exact failure the format exists to prevent. Corollary (implemented): if the prior file is unreadable, all fields are treated as changed (fresh stamps) — conservative and convergent.

A field *removed* by a write (present in prior `fields`, absent in the new flat record) is not currently representable distinctly in v0 (the field and its stamp simply vanish). Specified here: field removal writes a stamp with a reserved `"__absent__"` value marker in `fields`, so a removal can win or lose a merge like any other write. Rare in practice (attribute removal is a migration operation, Spec 01 §7.2, not a runtime write); required for merge correctness; a v0 delta (§11).

---

## 5. Atomic Writes & Durability

Every persist path — records, tombstones, and definition files alike — goes through one atomic-write primitive (`store.dart _atomicWrite`):

1. Serialize to `{file}.tmp` in the same directory.
2. Rename over the destination. POSIX rename replaces atomically in one step.
3. **Windows fallback** (rename-over-existing fails): move the current file *aside* to `{file}.bak`, rename `.tmp` into place, delete `.bak`. Deliberately move-aside, **not** delete-then-rename: at every instant of a crash mid-replace the data exists in `.json`, `.bak`, or `.tmp` — there is no window where the record is simply gone.

Guarantees and their honest limits (D10):

- **Guaranteed:** no reader — including the cloud-sync client, the most important reader (T1 uploads whatever bytes are on disk) — ever observes a half-written file at the destination path. A crash mid-write orphans a `.tmp`/`.bak`, never corrupts a record.
- **Not guaranteed:** power-loss durability of the very last write (no fsync in the path). Accepted for a personal-notes workload: the loss bound is the final in-flight record, the in-memory store is rebuilt from disk at next launch (Spec 04 §4.5), and a mid-execute crash is recovered by the execution journal's before-images (Spec 04 §5.4), not by storage-layer durability.
- **Hygiene:** hydration ignores non-`.json` suffixes by construction (the loader's `endsWith('.json')` filter — `.tmp`/`.bak` never load); a startup GC pass deletes orphaned `.tmp`/`.bak` files older than 7 days (§7.3).

**Corrupt or half-synced files never brick startup** (`store.dart loadRecords`): a file that fails to parse is skipped and hydration continues — the folder is a sync target, so partially-transferred files are expected, not exotic. Conformance note (P5): v0 skips *silently*; v1 must route each skipped file into the `HydrationReport` → `AttentionSurface` (Spec 04 §3.1, §5.5, §7.1) so a corrupt record is a visible repair item, not a quiet disappearance (§11). A skipped file is left untouched on disk — the sync client may still be mid-transfer, and the file watcher (Spec 04 §4.5) re-reads it when it settles.

Definition files (`types/`, `skills/`, `automations/`) use the same primitive. v0's `writeDef` currently writes directly (`writeAsStringSync`, no temp/rename) — a v0 delta (§11): a crash mid-write of a *type* file is strictly worse than mid-write of one record (it degrades every instance of the type at next hydration, Spec 01 §5.2 step 5).

---

## 6. Conflict Handling & Merge

Four classes of synced file, four resolution disciplines — this table is the section in one view:

| File class | Discipline | Escalation |
|---|---|---|
| Instance records (`records/`) | Deterministic per-field state-CRDT merge (§6.1) | Concurrent same-field edit → loser stashed in `_meta.conflicts`, surfaced; never silent |
| Type & skill definitions | Version-directed adopt; **never auto-merge an ambiguous case** (Spec 01 §7.5; §6.3) | Same-version content divergence → user reviews a diff |
| Automations, templates | Whole-file; automations LWW-with-surface (§6.4); templates re-materialize (§3.3) | Automation divergence surfaced in the automation UI |
| Machine-owned hot files (corpus, settings) | §10 — single-file LWW in v1 by explicit call; per-device single-writer at P2 | `G-36` tracks the v1 residue |

### 6.1 Instance records — the per-field state-CRDT merge

Formally (assessment §4): each record is a per-field LWW-register map with a version vector; merge is commutative, associative, and idempotent, so it converges under any delivery order, duplication, or delay (T2–T4). **The format ships in v0/v1 (it already has, §4); the merge engine is a P2 deliverable** — v1 is single-device, so no merge ever runs, but every record v1 writes is mergeable the day a second device appears (P4, D2).

`merge(local, remote) → merged`, a pure function:

1. **Tombstone cases** — see §6.6.
2. **Dominance fast path:** if one side's `vv` dominates (≥ on every device counter), that side is simply *newer* — take it whole. The overwhelmingly common case (a record edited on one device at a time).
3. **Concurrent versions** (neither `vv` dominates), per field:
   - Present on one side only → keep it (with its stamp).
   - Present on both, equal values → keep either; keep the higher stamp.
   - Present on both, different values → **higher HLC stamp wins** (§4.2 total order); the losing `(value, stamp)` is appended to `_meta.conflicts`, and the record is flagged to the `AttentionSurface` — the *record-conflict* analogue of Spec 01 §7.5's type escalation, except records auto-resolve (capture must not block on modals) and the surface is for review/recovery, not a gate. This extends Spec 04 §3.12's bucket list with a `recordConflicts` bucket (noted for the next Spec 04 pass).
   - Resulting `vv` = element-wise max; `conflicts` = union, deduped by `(field, stamp)`.
4. **Legacy rule (records without `vv`** — everything v0 wrote before D8 lands, §11): dominance cannot be computed, so step 2 is skipped and every cross-device same-field divergence goes through step 3's stash path. Convergent and lossless, but it may stash "conflicts" that were actually ordered overwrites (a remote deliberate overwrite is indistinguishable from a concurrent edit without `vv`). Accepted for the small v0-era corpus; it is exactly the noise `vv` exists to remove, which is why `vv` is **required before the merge engine ships** (D8).

**The named residue — the dead-device window** (assessment §4.3, accepted as D1's price): device A writes field *f* and syncs; B, unaware, later uploads its older version; the provider silently LWWs → *f* is absent from the cloud until A next reconciles and re-merges from its own state. If A is destroyed first, *f* is lost. Requires divergent same-record edits AND silent-LWW provider behavior AND permanent origin-device death before one reconcile; bounded to one record's fields; provider version history (~30 days on all major providers) is the manual backstop. This is the honest cost of having no backend, and it is *named* here rather than hidden (P5). The **local shadow** that closes the recoverable half of this window — a small device-local dirty-set of records this device wrote whose `vv` contribution has not yet been observed back from the synced file — ships with the merge engine at P2 (assessment §4.1 call site 2).

**Where merges run** (P2; one pure function, three call sites — assessment §4.1):
1. **Watcher reconcile** (Spec 04 §4.5): a synced-in record vs. the in-store version → merge; if result ≠ disk, write back (idempotent; converges across devices doing the same).
2. **Hydration scan** (§9.1): a changed file vs. the bootstrap snapshot / local shadow.
3. **Conflict-copy sweep** (§6.5): a provider-minted sibling vs. its base.

**Testing** (blocks Spec 09): the merge is a pure function over value objects — property-test commutativity, associativity, idempotence, and convergence under random delivery schedules, entirely in memory; integration-test the sweep against real conflict artifacts on desktop OneDrive/Drive (assessment §6.3 item 6).

### 6.2 Reconcile semantics — idempotent, unordered, mid-turn-safe

Restating the Spec 04 §4.5 contract from the storage side, since T2–T4 make it load-bearing: watcher events arrive debounced and batched; each batch is reconciled by re-reading only the changed files; every reconcile action (merge + conditional write-back, re-register, re-index) is idempotent, so duplicate or reordered observation of the same state is harmless. A change arriving mid-turn never mutates the turn's frozen inputs — it lands in the store and is caught by the execute-phase re-verify (Spec 02 §4.2). Cross-file ordering is never assumed: a record referencing a type whose file has not yet arrived is the *same* state as a dangling reference (Spec 01 §4.5, §5.3) — tolerated, surfaced if it persists, self-healing when the file lands (§8.3 is the schemaVersion instance of this).

### 6.3 Type & skill definition files — escalate on ambiguity, and how a conflict is actually detected

The resolution rule is Spec 01 §7.5, normative and restated: (1) one side has a higher `schemaVersion` → take it, no questions; (2) same `schemaVersion`, different content → **never auto-merge**; surface a diff-style review ("Two versions of your Meal type were changed on different devices"); (3) identical content → take either. Type-file conflicts are high-stakes — they govern every instance record — and skills follow the identical rule (a skill's step list is as load-bearing as a type's attributes; Spec 02's `skillSchemaVersion` is the version field). Definition files carry **no** per-field `_meta`: they are authored as wholes (by Claude or the developer, Spec 01 §4), reviewed as wholes, and merged never.

What Spec 01 §7.5 left open is *detection* — the transport does not announce conflicts (T5). Mechanics (D11):

- **The definition shadow.** The registry keeps a device-local map `{defId → contentHash}` of each definition as last registered/adopted on this device, plus a **dirty flag** set when *this device* writes a definition (authoring, type edit) and cleared when the write is observed back as the synced state.
- **Watcher delivers a changed definition file:**
  - hash == shadow → echo of our own write or a duplicate delivery; no-op (T4).
  - incoming `schemaVersion` > registered → adopt, re-register, run migration (§8.1), re-index (Spec 04 §4.5).
  - same `schemaVersion`, different content, **dirty flag clear** → a remote edit with no local divergence; adopt and re-register (this is not a conflict, just a change we didn't make).
  - same `schemaVersion`, different content, **dirty flag set** → both sides changed independently → **escalate**: `AttentionSurface.typeConflicts`, diff view, user picks or asks Claude to reconcile (which is an authoring flow, producing a version bump).
  - incoming `schemaVersion` *lower* than registered → stale delivery (T2/T4); ignore.
- **Conflict-copy siblings** of a definition file (§6.5) at the same `schemaVersion` always escalate — a provider-minted pair *is* the two-sided divergence, regardless of dirty flags.
- **While a conflict is pending:** the currently-registered version stays active (deterministic behavior beats a frozen app); instance writes continue validating against it; authoring edits to *that* definition are blocked until resolved; the pending item follows the user like any attention item (P5). Corpus entries targeting the type are untouched until resolution (an edit that then changes slot shape triggers the normal Spec 03 §5.5 invalidation).

### 6.4 Automations and settings

`automations/` files are small, single-concern, and edited rarely (a schedule change is a registry meta-operation, Spec 04 §3.9). v1: whole-file adopt-newest with the definition-shadow echo check; a same-file divergence is surfaced in the automation-management UI rather than a diff modal (the record is four fields; "keep which schedule?" is a picker, not a merge). They carry no `schemaVersion` today, so rule (1) of §6.3 does not apply — divergence goes straight to the picker. `settings.json` is §10.2. Templates never conflict (§3.3).

### 6.5 The conflict-copy sweep

At hydration and on watcher settle, any sibling matching provider conflict-copy patterns — `* (conflicted copy)*` / `*conflicted copy*` (Dropbox/OneDrive families), `{name} 2.json` (iCloud's pattern), and per-provider variants (Q3 tracks verifying the current-generation patterns empirically) — is resolved: parse the sibling; **records** → merge into the base (§6.1) and delete the sibling; **definitions** → escalate per §6.3; unparseable sibling → repair surface. The sweep is recovery for providers that mint copies instead of silently LWW-ing (T5); the merge discipline never *depends* on it.

### 6.6 Delete vs. edit, and the undo-revival race

Tombstone interaction rules (completing §6.1 step 1):

- Both tombstoned → keep the higher `deletedStamp`; union `conflicts`.
- One tombstoned, one live → compare `deletedStamp` against the live side's **highest field stamp**: if the delete is later, the delete wins (tombstone, with the live side's fields retained under `_meta` until GC for recoverability); if any field write is later than the delete, **the record revives** with the surviving fields. Edit-after-delete revives; delete-after-edit deletes. Deterministic on every device.
- **This closes the cross-device undo-revival race Spec 04 §3.11 carried to this spec.** An undo of a deletion re-creates the record from its before-image with *fresh HLC stamps on every field* (the acting device's HLC is necessarily past its own `deletedStamp` — send-rule monotonicity, §4.2). When the revival and the earlier tombstone meet on any other device, in either arrival order (T2), the revival's stamps post-date the `deletedStamp` and the record revives everywhere. Spec 04 §3.11's phrasing ("fresh `lastModified` … intended tiebreaker") is hereby made concrete as stamp comparison — `lastModified` is not stored and is never authority (§4.1, D5). Confirming the behavior over real provider sync is a P2 integration test (with the merge engine), not a v1 blocker — same-device undo within the window is the v1 case and needs no merge at all.

---

## 7. Tombstones & Garbage Collection

### 7.1 Tombstones

A delete never removes the file — a hard delete resurrects on the next sync restore, because the transport cannot distinguish "deleted here" from "not yet arrived there" (`store.dart tombstone`, assessment §4.1). Deletion marks the envelope: `_meta.deleted: true` plus a `deletedStamp` (HLC). Tombstoned records are excluded from hydration into the live store (`loadRecords` skips them) and from all reads; they exist purely for convergence.

Two implemented subtleties, kept normative:

- **Tombstones are written unconditionally** — even when the record's file is absent locally. A delete arriving for a record that synced in but was never persisted locally must still leave a tombstone, or the record resurrects on the next sync (the `store.dart` comment records exactly this reasoning).
- **`StorageRepository.delete` is idempotent** (Spec 04 §3.1): tombstoning an absent id mints a bare tombstone (`{id, _meta:{deleted, deletedStamp}}`).

### 7.2 Tombstone GC

Tombstone files are tiny but accumulate. GC (D9): a tombstone whose `deletedStamp.ms` is older than **`tombstoneRetentionDays` = 90** may be hard-deleted by any device, during the weekly idle consolidation pass (piggybacking Spec 01 §6.2's schedule). The named residue: a device offline longer than the horizon can re-upload a record whose tombstone was GC'd, resurrecting it. Accepted because (a) a 90-day-offline device in a 2–4 device personal fleet is nearly always a retired device, (b) the failure is a *visible reappearance* the user can re-delete, never silent loss (P5), and (c) closing it requires exactly the membership/liveness protocol the assessment rejected event logs over (§3.1). `_meta.conflicts` entries age out on the same 90-day horizon after surfacing.

### 7.3 Other GC

Startup, off the critical path: orphaned `.tmp`/`.bak` older than 7 days (§5); resolved conflict-copy siblings (deleted at sweep time, §6.5); expired execution-journal entries (owned by Spec 04 §3.3, listed here only because it is the same idle pass). Deprecated *types* are explicitly **not** GC'd by storage — Spec 01 §6.2 owns that lifecycle (files persist until migration is verified).

---

## 8. The Migration Runner over a Synced Folder

Spec 01 §7 defines the runner — declarative descriptors, safe coercions, atomic per record, developer-registered steps for built-ins and Claude-authored `migrations` blocks for user types. This section specifies its interaction with per-record storage and sync, which Spec 01 deferred here.

### 8.1 Trigger points, restated against this storage model

Per Spec 01 §7.4, with the storage-side mechanics filled in:

- **Startup:** hydration (§9.1) compares each record's envelope `schemaVersion` (§4.1; absent ⇒ 1) against its type's current version. Any record below current queues a migration run **before the dispatch gate opens** (Spec 04 §4.5/§7.1 — the interpreter must never resolve against un-migrated records; see §8.2 for the read-side guard that makes the gate cheap).
- **After sync:** the watcher reconcile (§6.2) re-runs the same per-record check for (a) a type file arriving at a higher `schemaVersion` — migrate all local instances; (b) *record* files arriving below the local type's version (written by a device whose type file lags) — migrate those records.
- **After type edit:** type file first, then the record run — the write order Spec 01 §7.4 fixes, and the reason it matters *doubles* under sync: because each record carries its own `schemaVersion`, a crash mid-run — or a sync snapshot taken mid-run (T2: other devices can observe the folder half-migrated) — is simply "type at vN, some records at vN−1," the exact state every device's startup/after-sync check detects and finishes idempotently. Migration needs no cross-device coordination: any device that sees the vN type file and a vN−1 record applies the same deterministic descriptor and converges (re-application is prevented per record by its version field, and double-application cannot happen — a record at vN matches no vN−1→vN step).

### 8.2 Migrate-on-read — the guard between the triggers

Between batch runs, individual stale records can surface (a file synced in seconds ago; a record the batch left mid-queue). The read path carries a guard: `StorageRepository` reads that encounter a record whose `schemaVersion` < the type's current version **apply the descriptor chain in memory** and serve the migrated form, queueing the persistent rewrite onto the serial-execute queue (Spec 04 §4.4) rather than writing inline — reads stay synchronous (Spec 04 §3.1) and a sync-storm of stale records does not amplify into a write storm. An in-memory migration failure is handled exactly as a batch failure (§8.4). The batch triggers of §8.1 remain primary (they bound how long the guard runs); the guard is what makes the startup gate cheap — hydration need not *complete* every rewrite before dispatch opens, it need only know every read will be served at the current version.

### 8.3 Version skew — a record from the future

The inverse arrival (T2): a record lands with `schemaVersion` *greater* than the local type file's version — another device migrated before its type file synced here, or wrote under a newer type. The record is **parked**: held out of the dispatch-visible store, surfaced as `SchemaError.versionTooNew` on direct access (Spec 04 §5.1/§5.2 — "this needs a newer definition," and if the type file never comes, "a newer Plenara"), listed on the `AttentionSurface`, and **auto-cleared** the moment the watcher delivers the newer type file (at which point it is simply a current-version record). Parking is the record-level twin of Spec 01 §5.3's degraded-reference tolerance: unordered arrival is a normal state, never an error dialog, and it self-heals (§6.2).

### 8.4 Failed migration — surface for repair

Per Spec 01 §7.4: atomic per record; a failing record is left at its old version on disk, logged, and the run continues. This spec adds the serving rule (extending Spec 01 §7.4, in the spirit of Spec 04 §4.5's half-loaded-store argument): a failed-migration record is **excluded from typed reads** (`readMany` etc.) — the interpreter validated its plan against the *current* schema, and serving a record the migration could not bring to that schema invites a wrong plan — and appears in `AttentionSurface.failedMigrations` (Spec 04 §3.12) with the record's raw content, the failing step, and the repair actions: retry after fixing the value, edit the record, or delete it. Never silently dropped, never silently served malformed (P5).

### 8.5 Downstream invalidation

A completed migration that changed slot shapes emits the registry invalidation of Spec 03 §5.5 (corpus entries whose `slotRecipes` no longer apply go `active: false`; any Lane-2 plan keyed on the old signature drops). The bootstrap snapshot (§9.2) is refreshed after a batch run so the next launch does not re-derive the migration.

---

## 9. Startup Scan & the Performance Budget

### 9.1 The hydration sequence

Owned by Spec 04 §7.1 (the fixed, fully-offline cold-start sequence and the no-dispatch-until-hydrated gate, Spec 04 §4.5); this section specifies the storage steps inside it and their budget. Storage-side order: load bootstrap snapshot (§9.2) → fingerprint-diff the folder → parse changed/new files (records via `loadRecords` semantics: tombstones excluded, corrupt files reported-and-skipped, §5) → registry hydration + cross-reference (Spec 01 §5.2) → per-record version check (§8.1) → gate opens; conflict-copy sweep (§6.5) and GC (§7) run after the gate, off the critical path.

### 9.2 The bootstrap cache

Research §8.4's amendment is binding: full-scan-every-launch does not scale — the storage-crdt spike measured ~230 files/s scan+parse (~22 s for 5,000 files) on a desktop SSD in Python, orders slower than the original estimate, before iOS dataless files make it worse (T6). A compiled-Dart implementation will beat that constant, but not the shape; the design must not re-read the world per launch.

The bootstrap cache (D13), at `[app-support]/plenara/bootstrap/`:

- **A materialized snapshot** of the hydrated store (records + parsed definitions), written after hydration settles, refreshed on graceful shutdown / periodically (debounced) / after a migration batch (§8.5).
- **A fingerprint map** `{relativePath → (mtimeMs, size)}` captured with it — a *per-file* map, deliberately not a single `lastStartupScan` watermark, because sync clients set mtimes from source metadata across skewed device clocks (T7): a synced-in file can carry an mtime *older* than any watermark, which a watermark scan silently misses and a fingerprint diff still catches (the entry changed). **This amends Spec 01 §5.2 step 1 and research §8.2's scan sketch:** the scan state lives in the device-local bootstrap cache, **not** in `settings.json` — a per-device cursor in a synced file is wrong twice (it self-conflicts across devices under LWW, §10.2, and it lies under T7).
- **Startup diff:** one directory listing (metadata-only — no content reads, which on iOS means no dataless-file materialization for unchanged files, T6) → compare against the map → re-parse only changed/new entries; entries missing from disk are dropped from the store (their tombstones, if any, arrived as changed files).
- **The cache is a cache** (assessment §6.3): device-local, versioned by envelope-format revision, discarded wholesale on version mismatch, folder-path change, or corruption — the folder is always sufficient to rebuild, and deleting the cache is always safe.
- **Named residue:** a content change with identical `(mtime, size)` is invisible to the diff. Live changes are covered by the watcher regardless (Spec 04 §4.5); the between-runs case is bounded by same-size rewrites with preserved mtimes — pathological for JSON records whose serialized size tracks content. Accepted; Q2 tracks whether a periodic full-hash validation pass is worth its cost.

### 9.3 The budget

Design ceiling: **10,000 records, 500 types, 200 skills** — a decade of heavy personal use (research §8.2's granularity math). Budgets are gates for Spec 09 perf tests; desktop numbers are commitments, iOS numbers are spike-owned (§9.5):

| # | Path | Budget (desktop, 5k records) | Notes |
|---|---|---|---|
| B1 | Warm start → dispatch gate open (snapshot + diff, <1% changed) | ≤ 1.0 s p50 / 2.5 s p95 | The normal launch; sits directly in the voice-latency path |
| B2 | Cold start, no snapshot (first run on a device / cache discarded) | ≤ 6 s, **with a visible progress surface** | Never silent (P5): "Reading your Plenara folder…" with a count, not a frozen mic |
| B3 | Registry hydration + cross-reference | ≤ 50 ms per 100 types | Spec 01 §5.2's figure, adopted |
| B4 | Directory fingerprint listing, 10k entries | ≤ 300 ms | Metadata-only listing (§9.2) |
| B5 | Single record persist (stamp + atomic write) | ≤ 10 ms typical | On the IO worker isolate (Spec 04 §4.1); never blocks a frame |
| B6 | Watcher reconcile of a settled 100-file sync batch | ≤ 500 ms, off the UI isolate | Debounced (Spec 04 §4.5) |

Hydration parses run on the IO/crypto worker isolates (Spec 04 §4.1); the UI is interactive for browsing while the store fills, with only the dispatch pipeline gated (Spec 04 §4.5's two-audience rule).

### 9.4 If the budget blows

The escalation ladder, in order, without reopening the format decision (assessment §6.3 item 7): (1) parallelize parse across workers; (2) move the snapshot to a binary/SQLite materialization — the "local materialized cache" question, Q4, decided on spike numbers, orthogonal to the source-of-truth format; (3) the **bootstrap bundle** — a periodically exported single-archive snapshot *in the synced folder* used only for first hydration on a new device (a cache with a synced home, not a source of truth), targeting the one real per-record weakness: new-device bootstrap of thousands of small files through a per-file-round-trip file provider.

### 9.5 What the iOS spike (05c D-1) must measure for this spec

The spike happens regardless (assessment constraints); these are its Spec-06 exit questions: (a) cold-bootstrap wall time for ~5k per-record files through the iOS file provider (dataless materialization + per-file overhead) — decides whether §9.4's bundle ships for P1; (b) watcher/metadata-query latency and reliability for detecting a changed subset (research §8.5's "fragile part"); (c) whether directory listing alone avoids materializing dataless files (T6, the premise of §9.2's diff); (d) conflict-artifact behavior of iCloud under concurrent edit (feeds §6.5's pattern table, Q3). Go/no-go: B1's warm-start budget within 2× on a mid-range iPhone; miss → the bundle plus, in the limit, the `StorageRepository` swap-out clause (P6).

---

## 10. Machine-Owned Hot Files

The assessment's sharpest finding (§1.2): the real conflict pain comes from the few monolithic, high-frequency files that violate the per-record principle — not from per-record files failing. Each gets an explicit disposition:

### 10.1 The learned corpus (Lane 1) — `G-36`

The one append-per-turn synced write in the system. v0/v1 ships **a single `corpus-learned.json`** (plus the read-only seeded `corpus.json`, §3.3) — **by Luis's explicit call (2026-07, recorded in Spec 03 §5.1)**, which overrode the assessment's "split now" recommendation (§6.3 item 4) on timing: v1 is single-device, so the single file is safe, and the split lands **together with the merge engine at P2** (the corpus has the same convergence needs as records and converts in the same milestone). This spec formalizes the P2 target so the v1 format cannot paint over it (`G-36`'s closing warning):

- **P2 shape:** `corpus-learned-{deviceId}.json` — per-device, single-writer (P3), merged at load. Single-writer files cannot same-file conflict; this is the event-log insight applied exactly where it fits (assessment §3.6): machine-owned, keyed, commutative, nobody reads it by hand.
- **Merge at load:** entries keyed by `(skillId, templateSig)` (Spec 03 §5.3); latest-stamp-wins per key; boosts/decay recompute from the winning entry (Spec 03 §4.2).
- **Cross-device forget:** a device cannot edit another device's file, so `removeCorpusLearned` (the Spec 03 §5.2 negative path) becomes, at P2, an appended **retraction entry** (`active: false` + stamp) in the forgetting device's own file, honored at merge by the latest-stamp rule. v0's in-place list rewrite remains correct for the single-file era.
- **v1 conformance:** v0's `corpus.json` + `corpus-learned.json` at the folder root are consistent with Spec 03 §5.1's note; the path drift versus Spec 03's `nlu/flow-table.json` naming is cosmetic and resolved in favor of the shipped names (assessment §7 flagged the drift; the file gets renamed at most once, at the P2 split).

### 10.2 `settings.json`

Low-frequency, whole-file LWW in v1 — accepted (assessment §6.3 item 5). Two rules to keep it acceptable: **nothing per-device or high-frequency may live in it** — the `lastStartupScan` cursor Spec 01 §5.2 placed there is relocated to the bootstrap cache (§9.2, D13), and any future per-device value goes to `[app-support]` — and if divergence is ever observed in practice, the record `_meta` treatment (per-key stamps) retrofits onto it without a format break (it is just a record with a well-known id). Candidate, not commitment (Q5).

### 10.3 The turn log

Diagnostics (research §14.2), one JSONL line per turn — device-specific by nature and append-per-turn, so it must be **device-local**: `[app-support]/plenara/turnlog.jsonl`. v0 formerly wrote it into the synced `dataDir` (`storage_repository.dart logTurn`) — expedient for single-device dogfooding, but a per-turn synced write (T1 re-uploads the whole growing file every turn) and a guaranteed two-device append conflict. **✅ Relocated (commit `d956390`):** the turnlog now lives in the app-injected device-local `deviceDir` (`~/.plenara`, same mechanism as the deviceId — §4.3), off the synced folder; V6 in §11 is closed. Never merged, never synced; rotation remains to do locally.

### 10.4 Already correctly placed

The execution journal (Spec 02 §5.2), plan cache (deferred, Spec 03 §5.1), embedding indexes (Spec 01 §5.4 / Spec 03 §10 MD9), and content-search index (Spec 04 §3.14) are all device-local by their owning specs' decisions — listed here only to affirm this spec adds no synced home for any of them.

---

## 11. v0 Conformance Deltas

What the v0 implementation already got right, and the ordered list of deltas between v0 and this spec. v0 is the format baseline (its per-record files, stamps, tombstones, and atomic writes are the decisions this spec documents); the deltas are the parts of the format that must land **before the data being written today becomes multi-device data** — each is small, and none invalidates a byte v0 has written (the legacy rules in §4.1/§6.1 define how pre-delta records read).

**Already conformant (no action):** per-record files with `{id, typeId, fields, _meta}`; per-field HLC stamps with stamp-on-change (§4.4); structured stamp shape (§4.2); tombstones written unconditionally, skipped at hydration (§7.1); atomic record writes with the Windows move-aside fallback (§5); corrupt-file skip-don't-brick (§5); per-install random deviceId replacing the `'this-device'` constant (§4.3); first-run seeding into the folder (§3.3); flat `records/` (§3.1); single-file corpus per Spec 03 §5.1's call (§10.1).

| # | Delta | Spec § | Urgency |
|---|---|---|---|
| V1 | ~~Move `deviceId` from `{dataDir}/.device-id` (synced!) off the synced root~~ **✅ DONE (commit `d956390`)** — deviceId now lives in the app-injected device-local `deviceDir` (`~/.plenara`); a synced id would be adopted by the next install, silently breaking the HLC tiebreak | §4.3, D6 | Landed before any second install existed |
| V2 | Write `schemaVersion` (and `createdAt`) into the record envelope; absent reads as 1 | §4.1, D5 | Before any type reaches schemaVersion 2 (the migration runner needs it) |
| V3 | Add `_meta.vv`, incremented per persist | §4.1, D8 | Before the P2 merge engine; earlier is cheaper (less legacy-rule noise) |
| V4 | Route `writeDef` through the atomic-write primitive | §5, D10 | Next v0 touch — a torn type file degrades every instance |
| V5 | Surface skipped corrupt files into `HydrationReport`/`AttentionSurface` instead of silent `continue` | §5, P5 | With the v1 attention-surface work |
| V6 | ~~Relocate `turnlog.jsonl` off the synced root~~ **✅ DONE (commit `d956390`)** — turnlog now lives in the app-injected device-local `deviceDir` (`~/.plenara`); rotation still pending (§10.3) | §10.3 | Landed; rotation with the v1 diagnostics work |
| V7 | HLC receive rule — advance the local clock on observing remote stamps at hydration/merge | §4.2 | With the merge engine (no remote stamps are observed before it) |
| V8 | Field-removal marker (`"__absent__"`) | §4.4 | With the merge engine |
| V9 | Migrate-on-read guard + version parking in the repository read path | §8.2, §8.3 | With the first real schemaVersion bump |

---

## 12. Decision Record

### Resolved

- **D1 — Record format: per-record current-state files + per-field HLC metadata (the assessment's Option C), adopted.** Per-device event logs are **rejected** as the record source of truth (relocate conflicts to compaction/GC, worsen iOS and sync traffic, break human readability — assessment §3); their single-writer insight is adopted narrowly for the corpus at P2 (§10.1). This formalizes the assessment's verdict; that document is superseded.
- **D2 — Format now, engine at P2.** The mergeable format ships from the first record (it has — v0); the merge engine, local shadow, and per-device corpus split land together at P2, after the iOS spike (§6.1, assessment §6.3). v1 single-device behavior is the format without the engine.
- **D3 — One flat `records/` folder,** `typeId` in the envelope; supersedes research §8.2's per-type folders (§3.1). Type-agnostic storage, no file moves on type merge, one listing at scan time.
- **D4 — Journal entries are ordinary UUID records; the date lives in the record id** (`YYYY-MM-DD-<uuid>`), reconciling research §10.3's amended naming with the assessment's collision fix (§3.1).
- **D5 — The envelope is `{id, typeId, schemaVersion, createdAt, parentId?, fields, _meta}`; absent `schemaVersion` reads as 1; `lastModified` is derived from stamps, never stored, never merge authority** (§4.1 — reconciles Spec 01 §8.2 and re-grounds Spec 04 §3.11's revival tiebreak in stamps, §6.6).
- **D6 — `deviceId` is per-install, random, and device-local** (`[app-support]`, never the synced folder) (§4.3; v0 delta V1).
- **D7 — HLC stamp is the structured `{ms, counter, deviceId}` map** (v0's shape), compared `(ms, counter, deviceId)`; send rule as implemented, receive rule specified for the merge era (§4.2).
- **D8 — `_meta.vv` (per-record version vector) is part of the format,** required before the merge engine; stamps-only legacy records merge under the conservative rule (§6.1 step 4).
- **D9 — Deletes are tombstones with `deletedStamp`; edit-after-delete revives, delete-after-edit deletes, by stamp comparison; tombstone GC at 90 days** with the named offline-device resurrection residue (§6.6, §7).
- **D10 — One atomic-write primitive (temp + rename, Windows move-aside) for records, tombstones, and definitions;** rename-atomicity guaranteed, last-write power-loss durability explicitly not (§5).
- **D11 — Definition conflicts: Spec 01 §7.5's rule, detected via the device-local definition shadow + dirty flag and the conflict-copy sweep; registered version stays active while a conflict is pending; same-version divergence never auto-merges** (§6.3). Record-level concurrent-field conflicts, by contrast, auto-resolve by stamp and stash the loser visibly (§6.1) — capture never blocks on a modal.
- **D12 — Migration over sync: batch at Spec 01 §7.4's triggers + a migrate-on-read guard; type-file-first ordering makes half-migrated folders (crash or mid-sync snapshot) a normal, self-healing state; future-versioned records park and auto-clear; failed records are excluded from typed reads and surfaced for repair** (§8; the exclusion extends Spec 01 §7.4).
- **D13 — Hydration is snapshot + per-file fingerprint diff from a device-local bootstrap cache;** the scan cursor moves out of `settings.json` (amending Spec 01 §5.2 step 1); full-scan-per-launch is rejected on the spike's measurement (§9.2, research §8.4).
- **D14 — The performance budget table (§9.3) gates Spec 09 perf tests;** iOS numbers are owned by the D-1 spike with a defined escalation ladder ending in the bootstrap bundle, never in reopening the format (§9.4–9.5).
- **D15 — Corpus: single synced file in v1 (Luis's call, Spec 03 §5.1), per-device single-writer files with retraction entries at P2** (§10.1); the assessment's "split now" is overridden on timing, not on shape. Turn log and all indexes/journals stay device-local (§10.3–10.4).
- **D16 — No encryption in this spec's v1 scope** (Spec 01 §8.7 deferral, Spec 04 §3.1 posture note): all synced content including `sensitive` values is plaintext in the user's own folder; the envelope reserves `encryptedPayload` so §8.7 activates without a format break (§4.1).

### Open questions

- **Q1 — iOS numbers (D-1 spike).** Cold bootstrap, watcher reliability, dataless-listing behavior, iCloud conflict artifacts (§9.5). Gates the bundle decision and, in the limit, P1's storage posture.
- **Q2 — The fingerprint residue.** Is a same-`(mtime, size)` content change observable from real providers often enough to justify a periodic full-hash validation pass (§9.2)?
- **Q3 — Conflict-copy patterns.** Empirically verify current-generation sibling naming per provider (iCloud/OneDrive/Drive/Dropbox) for the sweep's matcher (§6.5).
- **Q4 — The bootstrap cache's physical form.** Plain JSON snapshot vs. SQLite/Isar materialization — decide on spike startup numbers (assessment §6.3 item 8); invisible behind `StorageRepository` either way.
- **Q5 — `settings.json` per-key merge.** Retrofit the `_meta` treatment if real divergence is observed, or leave LWW forever (§10.2)?
- **Q6 — Device retirement at P2.** Stale per-device corpus files from retired installs are inert but immortal (§10.1, §4.3); is a fold-in (merge into the live device's file + delete) worth its small race, or is "small files linger" fine for a 2–4 device fleet?
- **Q7 — Clock-drift policy.** The receive rule adopts arbitrarily future stamps (capped-log at 1 h drift, §4.2); should a pathological clock (a device years in the future poisoning tiebreaks) get active correction or user surfacing?
- **Q8 — Numbering drift (editorial) — ✅ RESOLVED (suite-sync CS-03).** Spec 04 §0 formerly referred to both "Spec 06 — Voice" and "Spec 06 — Data & Sync"; research §12 assigns 6 to Data & Sync (this document). The voice/STT/TTS material now has its home: **Spec 12 — Voice**, and every "Spec 06 — Voice" citation in Specs 03/04/08 has been retargeted to Spec 12.
