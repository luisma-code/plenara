# Storage & Sync Assessment — Per-Device Event Logs vs. Per-Record Files

**Status:** v1.0 — July 2026 — independent assessment by Claude Fable 5, requested by Luis as a decision input for the storage/sync format. **Not a spec.** Nothing here is folded into Specs 01–06; adopt, amend, or discard in-session.
**Question assessed:** should Plenara replace mutable per-record JSON files with per-device append-only event logs (`log-{deviceId}.jsonl` + snapshot + watermarks + version-vectors + compaction), keep the status quo, or take a middle path (per-record current-state files with embedded per-field version metadata)?
**Constraints taken as fixed:** no backend, no subscription (maybe v2); user-owned cloud folder is the only transport; iOS P1 / Windows P2; offline-first; solo user with 2–4 devices; the iOS file-sync spike (05c D-1) happens regardless.

---

## 0. Verdict up front

**Do not adopt the event log for records. Adopt the middle path — per-record current-state files with per-field logical timestamps and a deterministic field-level merge — and adopt its *on-disk format* now, even though the merge *engine* can wait until the second device (P2).** Use the event-log idea only where it is actually right: the machine-owned hot files (the corpus flow-table, `G-36`), which should become per-device files merged at load, exactly as the gap register already proposed.

The one-sentence reasoning: **cloud file-sync is an unreliable, unordered, at-least-once transport, and over such a transport a state-based CRDT (merge full states, idempotently) is the natural fit, while an op-based CRDT (ship and replay event streams) forces you to build the delivery guarantees the transport doesn't give you — watermarks, segment sealing, compaction coordination, device retirement — which is a backend's job, and you have no backend to run it.** The event-log proposal is a distributed-systems answer scaled for a problem Plenara does not have (many writers, high contention, audit requirements) at the cost of the two things Plenara actually promised (human-readable current-state files; cheap boring startup) — and it does not even eliminate the conflict class, it relocates it to the compaction/metadata plane.

The middle path gets ~90% of the event log's correctness benefit (deterministic field-level merge, no lost same-record edits, no reliance on provider conflict heuristics) for ~15% of its complexity, keeps every file a human-readable statement of current state, changes nothing about startup or the iOS risk profile, and is retrofittable: the format ships in v0 as an inert `_meta` block, the merge engine ships when a second device exists.

---

## 1. Size the actual problem before choosing machinery

The proposal treats "same-record conflict" as the design driver. Before accepting that, it is worth being honest about how big the driver is for *this* app.

### 1.1 The write surface is mostly append-only already

Look at the seed types (Spec 01 §12.3): `contact_interaction` is `append: true`; `contact_fact` is create-mostly; journal entries are created and rarely edited; tracker logs (meals, runs, moods) are append-by-construction. **A new record is a new UUID-named file — two devices creating records concurrently can never collide at the file level.** The genuinely *mutable* record surface is small: `task` (the `completed` flag, occasionally `dueAt`), `contact` (notes, birthday), and the odd correction-driven update. And the most common concurrent same-record write imaginable — marking the same task done on two devices — converges under naive LWW anyway, because both sides wrote the same value.

The realistic same-record conflict is not a race within a sync window; it is **offline divergence**: edit a contact's notes on the phone during a flight, edit the same contact's birthday at the desktop, phone reconnects. That happens, and the status quo genuinely handles it badly (§2 below). But it is a low-frequency event measured in occurrences per month, not per hour. Machinery should be sized accordingly.

### 1.2 The actual hot files are not records

The system's genuinely high-frequency writes are:

| File | Write rate | Shape |
|---|---|---|
| `nlu/flow-table.json` (Lane-1 corpus) | **once per dispatched turn** | monolithic synced JSON — `G-36` |
| `settings.json` | occasional | monolithic synced JSON |
| journal day-file (`journal/YYYY-MM-DD.json` per research §10.3) | per journaling session | **date-keyed filename** — two devices creating the same day's entry mint the *same new file*, a guaranteed create/create collision the UUID principle was supposed to prevent |
| execution journal, plan cache, content index | per turn | already device-local, correctly out of scope |

**This is the tell: the conflict pain that motivated the event-log proposal comes overwhelmingly from the two or three monolithic/keyed files that violate the per-record principle — not from per-record files failing.** Fixing those three (per-device corpus files; per-key or vv-merged settings; UUID-named journal entries with `entryDate` as an attribute, which Spec 01 §12.3's `journal_entry` type already implies) removes most of the observed hazard without touching the record format at all.

### 1.3 What the transport actually guarantees (nothing)

Any design must survive what iCloud/OneDrive/Drive actually provide: whole-file replacement as the unit of sync; **no cross-file ordering** (file B's update can arrive before file A's even if written after); arbitrary delay (minutes to hours on iOS background sync); provider-specific conflict behavior (iCloud keeps `NSFileVersion` conflict versions invisible to naive apps — effectively LWW unless you ask; OneDrive sometimes mints "conflicted copy" files; Drive keeps versions); and on iOS, **dataless files** whose content costs a full download to read. No format choice changes any of this; the choice is only about which failure modes the format converts into merges versus losses.

---

## 2. Option A — status quo: mutable per-record files

**What it is.** One JSON file per record; provider resolves same-file concurrency by LWW or conflict copy; research §8.6 sketches per-type resolution ("for contacts: non-conflicting fields are merged").

**The unfixable defect as specified: §8.6's contact merge is not implementable.** "Merge non-conflicting fields" requires knowing *which fields each side changed*, which requires either a common ancestor (not available — providers don't hand you one reliably) or per-field metadata (not in the format). With only whole-record `lastModified`, you cannot distinguish "B changed birthday, A changed notes → merge both" from "both changed notes → conflict." So the status quo's conflict story is really: same-record divergence silently loses one side (provider LWW), or surfaces a whole-record picker forcing the user to sacrifice one side's fields even when the edits don't overlap. Both violate P2.8's spirit — the loss is silent or the surface is lossy.

**Everything else about A is fine.** Startup, iOS behavior, readability, sync traffic, complexity — all as good as this architecture gets. A is fully acceptable for single-device v1. Its only sin is that its on-disk format carries no information a future merge can use — exactly the trap `G-36`'s closing line warned about ("the format must not be one a merge cannot be retrofitted onto"). That sin is cheap to fix (Option C) without changing anything else.

---

## 3. Option B — per-device append-only event logs (the proposal)

**What it is.** Each device writes only `log-{deviceId}.jsonl` (field-level change events with version vectors); load = snapshot + replay tails past per-device watermarks; periodic compaction bounds growth; materialized into the local store.

The core insight is correct: **a file written by exactly one device can never suffer a same-file sync conflict.** Per-device single-writer files are the right primitive for cloud-folder sync. The question is whether making them the *record source of truth* is worth what it costs. My judgment: no, for six reasons — several of which are not incidental but structural.

### 3.1 It doesn't eliminate the conflict problem; it relocates it to compaction and GC

- **The snapshot is a shared mutable file.** If there is one `snapshot.json`, two devices compacting produce exactly the whole-file LWW conflict the design exists to kill — on the *most load-bearing file in the system*. So snapshots must be per-device too (`snapshot-{deviceId}`), which works but means a reader merges N snapshots + N tails, and "which snapshot covers which log prefix" needs explicit watermark metadata that itself must never be shared-mutable.
- **Truncating your own log races the sync client.** Device A compacts and truncates `log-A`; device B can receive the shortened `log-A` *before* the new `snapshot-A` (no cross-file ordering, §1.3) and watch events vanish. The standard fix is sealed segments (`log-A.0007.jsonl`, never rewritten, compact only sealed segments, delete segments only after provable coverage) — i.e., you are now building a miniature Kafka with segment lifecycle management on top of iCloud.
- **Device retirement is a coordination problem with no coordinator.** A wiped/reinstalled phone gets a new deviceId; its old log and snapshot linger forever, because the single-writer invariant says nobody else may touch them. Deleting them safely requires knowing every live device has absorbed them — a liveness/membership question that needs a device registry, which is itself shared mutable state. For a solo user this decays into "a stale log from a phone Luis traded in two years ago sits in the folder forever and every new device downloads and replays it," or into heuristic GC ("untouched for 90 days → fold in") with a real, if small, correctness hole.

None of these is unsolvable. Every one of them is a distributed-protocol design with edge cases that a solo developer will hit *rarely, months apart, on real data* — the worst debugging profile there is.

### 3.2 On iOS it is *worse* than per-record files, not better

The proposal must be judged on P1, and D-1's dataless-file reality cuts against logs specifically:

- **You cannot read "the tail" of a dataless file.** Reading any byte range of an evicted iCloud file materializes the whole file (ranged/partial materialization exists in newer File Provider APIs but is provider-implemented and cannot be relied on for iCloud). So "read N log tails past watermarks" becomes "download N entire logs" whenever the OS has evicted them — and hot, frequently-rewritten files that are also periodically compacted (changing their identity) are prime eviction/redownload candidates.
- **Append amplifies sync traffic.** Providers upload whole files. A per-record write under A/C uploads ~1 KB. An append to a 5 MB log uploads ~5 MB (Dropbox's block-level delta being the exception nobody's P1 uses). Between compactions, every dispatched turn re-uploads the device's entire accumulated log. Daily/size-capped segments bound this — more machinery again.
- **The one genuine iOS win B has** is new-device bootstrap: pulling one snapshot + a few logs beats pulling 10,000 tiny files through a file-provider that round-trips metadata per file (a real per-record weakness — §6.3 flags it for the spike). That win is real but purchasable much more cheaply: a periodically-exported bootstrap bundle alongside per-record files, *if the spike proves the pain is real*, without changing the source of truth.

### 3.3 Startup cost: the happy path is fine; the failure modes are exactly the ones asked about

Snapshot + watermark + tail replay is cheap **when compaction is current and files are materialized**. The asked-about cases are the ones that bite: a device offline for three weeks returns to N grown tails (all evicted → N full downloads before hydration completes, sitting directly in the §4.5 no-dispatch-until-hydrated voice-latency gate); a compaction race (§3.1) mid-recovery; a new device replaying a year of events from a retired device's un-GC'd log. The status quo/middle path's equivalent worst case — re-parse the records whose `lastModified` changed — is strictly simpler and has no replay-correctness dimension: state files are idempotent to re-read, logs are only idempotent if the watermark bookkeeping is right.

### 3.4 It breaks the human-readable-data principle, and that principle is load-bearing

`tasks/call-the-plumber.json` openable in any text editor **is the no-backend architecture's justifying virtue** — it is what makes "your data outlives the app, no lock-in, auditable" true (research §8.1, and the same auditability argument underpins the App Store 2.5.2 story for skills). Under B, the folder's truth becomes N interleaved event streams; the current state of one task is a *computation* over them. `.jsonl` is technically text, but "readable" in the sense the principle means — a human finds and reads their data without the app — is gone. The materialized cache doesn't rescue this: it's device-local, rebuildable, explicitly *not* the durable artifact. If Plenara dies, a B-format folder needs a bespoke script to exhume; an A/C-format folder needs `cat`. For a personal-memory app whose pitch includes data longevity, I weight this heavily, not sentimentally.

### 3.5 What B genuinely buys, stated fairly

Honesty requires listing what the middle path does *not* match: (a) **full history/audit** for free — every edit ever, replayable (though the execution journal already covers the undo window, which is the only history the product uses); (b) **cross-record atomic change-sets** — a multi-write skill's three records land as one log entry (though sync still delivers other devices' files non-atomically, so readers must tolerate partial states under every option); (c) **no reliance on the origin device for clobber recovery** — once an event is in your log, no other device's upload can destroy it (the middle path's one real gap, quantified in §4.3). None of these three is worth the §3.1–§3.4 bill for a 2–4 device solo deployment.

### 3.6 B verdict

**Reject as the record format.** Adopt its core insight — per-device single-writer files — narrowly, for the data that is actually shaped like a log and owned by the machine: the Lane-1 corpus (`G-36`), where entries are keyed, boosts are commutative, merge-at-load is trivial, nobody browses the file, and compaction is optional (the corpus is small and self-pruning via decay/invalidation). That was the gap register's own instinct; it was right, and the error in the current proposal is generalizing it from the corpus to the world.

---

## 4. Option C — the middle path: per-record state files + per-field logical timestamps

**What it is.** Records stay one-file-per-record, current-state, human-readable. Each record carries a small `_meta` block: a per-record version vector (writes-per-device) and a per-field last-write tag (hybrid logical clock + deviceId). Merge is deterministic, field-level, and runs wherever two versions of a record meet: a provider conflict-copy pair, a synced-in file vs. the local store, or a hydration-time scan.

Formally this is a **state-based CRDT** — a per-field LWW-register map with a version vector for concurrency detection. Merge is commutative, associative, idempotent, so it converges regardless of delivery order, duplication, or delay — which is precisely the guarantee profile matching what the transport gives you (§1.3). Same theory as B's version-vectors, applied to states instead of ops: **the provider's file sync becomes the anti-entropy channel, and no watermark, segment, or compaction machinery is needed because full states, not deltas, are exchanged.**

### 4.1 Concrete format sketch

```json
{
  "id": "d4e5f6...",
  "typeId": "contact",
  "schemaVersion": 1,
  "createdAt": "2026-07-03T08:00:00Z",
  "lastModified": "2026-07-05T21:14:03Z",
  "fields": { "displayName": "Sarah Mitchell", "birthday": "1990-11-14", "notes": "..." },
  "_meta": {
    "vv": { "iph-a1b2": 12, "win-c3d4": 3 },
    "f": {
      "displayName": "2026-07-03T08:00:00.000Z-0001-iph-a1b2",
      "birthday":    "2026-07-05T21:14:03.412Z-0000-win-c3d4",
      "notes":       "2026-07-04T19:02:11.007Z-0002-iph-a1b2"
    }
  }
}
```

- **Per-field tag** = HLC (wall-clock millis + logical counter, Kulkarni-style, so clock skew can't reorder causally-related writes) + deviceId as total-order tiebreaker. ~60 bytes/field.
- **`vv`** = writes-per-device counter for the record; lets the merger detect *concurrent* (neither dominates) vs. *ordered* versions. 2–4 entries for this user.
- **Overhead:** ~100–250 bytes per record — noise. Readability: the record remains a plain statement of current state; `_meta` is an ignorable trailer, and the principle survives intact.

**Merge(recordX, recordY):** if one `vv` dominates, take that version whole (fast path — the overwhelmingly common case). Otherwise, per field: higher HLC tag wins; when both sides changed the *same text field* concurrently (detected via vv-concurrency + differing tags from different devices), keep the winner **and stash the loser in `_meta.conflicts` → surfaced in the `AttentionSurface` repair view** — so even the worst case is never *silent* loss, which is better than P2.8 currently gets from §8.6. Deletion = tombstone file (`"_deleted": true` + tag), GC'd after ~90 days; needed under every option, since naive file deletion resurrects via sync.

**Where merges run:** (1) file-watcher reconcile (§4.5 of Spec 04): synced-in version vs. in-store version → merge; if result ≠ disk, write back (idempotent; converges); (2) hydration scan: same, against a **device-local shadow** of the device's own last-written state (a tiny local dirty-set/outbox, pruned once the synced file's `vv` contains your counter — this is what recovers a provider LWW clobber of your write while you were offline); (3) conflict-copy sweep: any `* (conflicted copy)*` sibling → merge into base, delete sibling. One merge function, three call sites.

### 4.2 How it scores

- **Conflict handling:** deterministic field-level merge for the offline-divergence case (§1.1's realistic scenario); create/create impossible by UUID; delete/edit resolved by tombstone tags; concurrent same-field never silent. This is the *actual requirement*, met.
- **Startup:** identical to status quo. No replay, no watermarks, nothing new in the voice-latency path. The D-1 iOS risk is unchanged — neither helped nor worsened.
- **iOS:** identical file profile to A. Dataless behavior, file-count bootstrap cost, watcher unreliability — all the same, all owned by the D-1 spike either way.
- **Human readability:** preserved. A record file remains the record.
- **Complexity:** one merge function (~200 lines with tests), HLC generation, tombstones, the local shadow. No protocol, no GC coordination, no membership. Testable exhaustively in-memory (merge is a pure function — property-test commutativity/idempotence).
- **Sync traffic:** identical to A (small whole-file uploads per write).

### 4.3 C's honest weaknesses

- **The dead-device window.** A writes field f, syncs; B (offline earlier, unaware of f) later uploads its version; provider LWW's silently → f is gone from the cloud until A next reconciles and re-merges from its shadow. If A is *destroyed* before that, f is lost. Required coincidence: divergent same-record edits AND silent-LWW (not conflict-copy) behavior AND permanent origin-device death before one reconcile. Bounded to the fields of one record; provider version history (30 days on all three) is the manual backstop. For 2–4 personal devices I judge this acceptable and — importantly — *nameable*: it is the residue you accept for not running a backend. B closes it; nothing else about B justifies its price.
- **No history.** Only current state + the undo-window journal. If Luis someday wants "what did this contact's notes say in March," C doesn't have it. The product as specced never asks that question.
- **Text-field merges are whole-field.** No intra-string merge (that's Automerge territory, §5). Concurrent prose edits to the *same* note pick a winner and stash the loser. Rare, visible, acceptable.
- **File count remains.** C does nothing about the 10k-small-files bootstrap concern on iCloud. That is a real, shared A/C weakness the spike must measure (§6.3), with a cheap mitigation available later (bootstrap bundle) that doesn't change the source of truth.

---

## 5. Option D — other backend-free shapes considered and rejected

- **CloudKit private database.** Genuinely serverless-for-you, free at this scale, record-level sync with change tokens, solves everything on Apple platforms. Rejected: no Windows (P2), total Apple lock-in, and data stops being user-visible files — kills portability and the provider-choice principle. Worth naming because it is the one "no backend you operate" option that fully solves sync; it fails on values, not mechanics.
- **Automerge/Yjs-style CRDT documents per record.** Real libraries, proven merges, intra-text merging. Rejected: binary/opaque on disk (readability gone), a heavy dependency for records that are flat attribute maps, and the merge power (collaborative text) solves a problem a single human doesn't have. C is the ~50-line subset of this that Plenara needs.
- **cr-sqlite / SQLite-with-CRDT-extensions.** Violates the no-SQL-on-disk decision (research §8.3) and syncs a binary blob — the exact original sin.
- **Provider version-history as merge ancestor** (three-way merge using the provider's kept versions). Rejected: API access to versions is provider-specific, absent on some, and unavailable through the iOS file-provider abstraction — a merge that only works on some providers is not a merge discipline.
- **Per-record per-device state files** (`tasks/{id}/{device}.json`, merge at read). Single-writer purity with state-based merging — theoretically clean, but multiplies file count by device count and makes "the record" a directory computation; C achieves the same convergence with one file by accepting the §4.3 window. Not worth it.

---

## 6. Ranked comparison and recommendation

### 6.1 The table

| | **A — status quo** (mutable per-record) | **B — per-device event logs** | **C — per-record + per-field vv/HLC** |
|---|---|---|---|
| Same-record conflict | silent LWW loss or lossy whole-record picker; §8.6 merge **unimplementable as specced** | solved (single-writer files) — but conflict class **relocated** to snapshot/compaction/GC plane | solved: deterministic field-level merge; concurrent-same-field → visible repair item, never silent |
| Monolithic hot files (`G-36`) | unsolved | solved as a side effect | unsolved by the record format — **fix separately with per-device corpus files** (B's idea, right-sized) |
| Startup cost | scan changed files; D-1 applies | snapshot+tails happy path OK; offline-weeks / evicted logs / compaction races land in voice-latency path | **identical to A**; nothing new in the path |
| iOS behavior | D-1 risk; many-small-files bootstrap | dataless **whole-log** downloads; whole-file re-upload per append; wins only on bootstrap file-count | identical to A |
| Human readability | full | **broken** — truth becomes interleaved event streams | full (ignorable `_meta` trailer) |
| Complexity | none new (but promised merge is vapor) | protocol-grade: segments, watermarks, compaction, device retirement/GC, membership | one pure merge fn + HLC + tombstones + local shadow |
| Data-loss residue | any divergent same-record edit loses a side | ~none once events sync | dead-device window (§4.3): rare, bounded, nameable |
| Fit to principles | violates P2.8 in the merge gap | violates "user owns readable data"; strains minimalism-of-mechanism | consistent with all locked principles |

### 6.2 Ranking

1. **C — per-record files + per-field version metadata.** The winner. Meets the actual (small) conflict requirement, costs almost nothing where Plenara is weakest (iOS, startup), preserves the principle that justifies no-backend, and is retrofittable in two stages.
2. **A — status quo**, acceptable strictly as "C's format without C's engine yet" for single-device v1. As an *end state* it is dominated: it carries a specced-but-unimplementable merge promise and a format that discards the information a future merge needs.
3. **B — event logs.** Rejected for records. Its correct kernel — per-device single-writer files — is adopted for the corpus (and any future machine-owned hot file). As a record format it is the most complex option, the worst on iOS specifics, the only one that breaks a core principle, and it still needs its own conflict-avoidance protocol for snapshots/compaction. It is the right design for a different app (multi-user, contended, audited) or for a future Plenara *with* a backend to referee GC.

### 6.3 What to do NOW vs. after the iOS spike

**Now (v0, single device — cheap, format-only, no behavior change):**
1. **Write the `_meta` block from the first record ever persisted** (vv + per-field HLC tags on write; readers ignore it). This is the whole "avoid a later migration" insurance — ~a day of work, and it discharges `G-36`'s format warning for records.
2. **Adopt the tombstone convention** for deletes from day one (deletion behavior is otherwise a latent resurrection bug even single-device, via sync restore).
3. **Kill the date-keyed journal filename** (§1.2): journal entries are UUID-named records with `entryDate` as an attribute, like everything else. One line in Spec 06 now vs. a create/create collision class later.
4. **Split the corpus per device** (`nlu/corpus-{deviceId}.json`, merged at load — entries keyed by `templateSig`, boosts max/sum-commutative, invalidations by tag). Do it now rather than pre-P2: it is small, it closes `G-36`, and it removes the *only* high-frequency synced-write in the system. Note in passing: Spec 04 §7.1's text currently says the corpus is "device-local/encrypted (never synced)," which contradicts Spec 03 §5.1's synced Lane-1 — that drift needs reconciling whichever way this lands.
5. Leave `settings.json` as-is (low frequency), noted as a candidate for the same per-field treatment later.

**After the iOS spike (and before P2 makes two devices real):**
6. **Build the merge engine** (the pure function + three call sites of §4.1) — with property tests for commutativity/idempotence, and integration tests against real provider conflict artifacts (a simulated "(conflicted copy)" sweep is testable on desktop OneDrive/Drive today).
7. **Have the spike measure the shared A/C weak spot, not just D-1's list:** cold-bootstrap wall-time for ~5k per-record files through the iOS file provider (dataless materialization, per-file overhead), and watcher/metadata-query latency for detecting a changed subset. If bootstrap is intolerable, add the **bootstrap bundle** (a periodically exported single-archive snapshot used only for first hydration on a new device — a cache, not a source of truth) rather than reopening the format decision.
8. **Decide the local materialized cache** (SQLite/Isar) on the spike's startup numbers — orthogonal to this decision under C, exactly as it is under B.

### 6.4 Answers to the six questions, compressed

1. **Is the event log better for this context?** No. Its single-writer insight is right; as a record format it relocates conflicts to compaction/GC, worsens iOS and sync-traffic behavior, and solves a contention level this app doesn't have. It *does* fix the monolithic-hot-file problem — but so does just splitting those two files, without collateral damage.
2. **Does snapshot+tail keep startup cheap?** Happy path yes; the named failure modes (weeks-offline tails, dataless whole-log materialization, compaction/truncation racing unordered sync) are all real, all land in the no-dispatch-until-hydrated voice gate, and all require protocol machinery (segments, per-device snapshots, coverage proofs) to close. C sidesteps the entire category.
3. **Does the event log break the readability principle?** Yes, meaningfully — current state becomes a computation over interleaved streams, and the readable artifact left (the local cache) is explicitly non-durable. The principle is the no-backend architecture's justifying virtue and part of the compliance/auditability story; I weight the break as disqualifying on its own, independent of §3.1–3.3.
4. **The middle path?** Adopt it. It is a state-based CRDT whose anti-entropy channel is the file sync you already have — the formally correct fit for an unordered at-least-once transport — at roughly the complexity of one pure function. Its one real gap vs. the log (the dead-device clobber window, §4.3) is rare, bounded, backstopped by provider version history, and an honest price for no-backend.
5. **Better backend-free options?** None found that survive the constraints. CloudKit solves sync but fails Windows and portability; Automerge-class CRDTs solve text-merging nobody needs at the price of opacity; provider version-history merging isn't portable across providers. The corpus-as-per-device-files piece is the one borrowed improvement worth taking.
6. **Timing?** Split the decision: adopt the *format* now (steps 1–4 — cheap, inert, migration-proof), build the *engine* after the spike and before P2. Do not build compaction infrastructure at any point unless a future measured problem demands it — which, with no event log, none will.

---

## 7. Side findings surfaced while assessing (not acted on)

- **Spec 04 §7.1 vs Spec 03 §5.1 corpus-location contradiction** (§6.3 item 4 above) — one of them is stale; reconcile when `G-36` is resolved.
- **Research §8.6's per-field contact merge is unimplementable in the current format** (no ancestor, no per-field metadata) — adopting C makes it true; keeping A means rewording it honestly to whole-record resolution.
- **Journal day-file naming** (research §10.3 "one file per day") contradicts the UUID-per-record principle and the `journal_entry` seed type's shape; a same-day two-device journaling session is a create/create collision as currently written.
- **Naming drift:** research §8.2 calls the corpus `nlu/corrections.json`; Spec 03 §5.1 calls it `nlu/flow-table.json`. Cosmetic, but the file is about to be redesigned anyway.
