# Plenara full code review and remediation

**Date:** 2026-08-18
**Scope:** the whole production tree — `v0/lib` (engine) and `app/lib` (Flutter) — reviewed for
architecture, correctness, test quality, and diagnosability, then remediated in the same pass.
**Result:** 63 defects found, all confirmed ones fixed and covered by calibrated tests. The full
gate is green: 2,034 engine tests + 36 intentional skips, 175 Flutter tests + 4 channel skips,
95.7% deterministic-core / 90.0% product-logic / **83.8% transport** coverage, macOS build, seven
real-engine integration cases, external-channel, secret, and 24/60 conformance gates.

## How this review was run

Nine independent read-only reviewers covered disjoint slices of the tree (session/interpreter,
routing/cloud, storage/schema, execution/operations, planner/domain, app shell/UI, voice/platform,
diagnostics/logging, and the test suites themselves). Every reported defect was required to name a
concrete failure scenario and be verified against callers and covering tests before it was believed;
several were reproduced by executing the library against scratch data. Remediation then ran with
disjoint file ownership so parallel work could not collide.

**Every fix in this document was calibrated**: the test was shown failing against the broken
implementation and passing against the fix. Three tests written during remediation turned out *not*
to discriminate when calibrated, and were strengthened until they did — see "Tests that could not
fail" below.

## The five findings that mattered most

### 1. Every record update failed after a relaunch, for 13 of 17 shipped types

`store.loadRecords` injects the envelope's write-once `createdAt` as a top-level field of each flat
record. `interpreter`'s update path spreads the existing record into the write. `ValueCodec`'s
structural whitelist did not include `createdAt`, so validation rejected it as `unknown_field`.

The consequence in the running app: create a contact, relaunch, say *"Sarah's nickname is Mum"* —
**"I couldn't start that safely, so nothing changed."** The same for `set-birthday`, `set-alias`,
Library tap-to-edit, and "correct that" on any of contact, meal, mood, journal entry, project, area,
workout, interaction, routine step/session, and the contact sub-types. Undo of any pre-relaunch write
reported a false conflict for the same reason. A future version bump of any of those types would have
parked every record as `target_validation_failed`.

Every existing test missed it by creating and editing inside one session, where the injected field
never exists. Fixed by making `createdAt` structural in the validator (it is already routed back to
the envelope on write, so nothing is duplicated), plus a cross-restart round-trip suite covering
every shipped type.

### 2. Crash recovery replayed a stale write over a newer one; undo skipped its conflict check

A record left in `applying` (a write applied in memory whose persist failed) was replayed at next
launch with **no divergence check**. If a later turn had successfully edited the same record, recovery
silently overwrote it — the exact data loss the durable journal exists to prevent. Separately,
`_afterImagesStillMatch` ran only for `completed` records, so undoing an `applying` record skipped
conflict detection entirely and reverted whatever had been written since.

Both now compare current durable state against the recorded before/after images and escalate to a
new terminal `conflict` phase that is never replayed and never pruned. Replays are additionally
capped at three attempts, so a deterministically failing entry escalates instead of retrying forever.

### 3. The merge was not associative, so replicas could diverge permanently

When a delete met two concurrent live branches, the delete-vs-live decision was made by whole-record
last-write-wins *before* field merging: `merge(merge(D,L1),L2)` yielded `{y}` while
`merge(D,merge(L1,L2))` yielded `{x,y}`. Both outcomes are stable, so two devices folding the same
inputs in different orders never reconverge — and `reconcileRecords` folds in filesystem enumeration
order, which differs per device.

The merge is now a true join-semilattice: fields, stamps, and tombstones always merge, the deletion
stamp is carried as a maximum, and liveness is derived at the end from the merged document. The
randomized three-way property test — which previously generated only pairs of concurrent live
documents — now also generates deletes, tombstones, dominating version vectors, stamp ties, and
stamp-less legacy fields.

### 4. The turnlog ignored the build channel entirely

`v0` had no build-channel awareness of any kind. `Session.handle` appended the utterance, slot
values, response text, recognizer diagnostics, and exception messages to `turnlog.jsonl` in **every**
channel, including external — and the external startup purge deleted only `.log` files, so an
inherited turnlog survived a channel switch. Spec 11's external contract ("captures no raw content",
"changing channels cannot strand an old raw trace") was true of AppLog and false of the turnlog, and
no test covered it because the external canary battery never looked there.

The repository now takes an explicit `enableTurnlog`; external builds construct it `false`, so the
content-bearing record does not exist rather than merely being hidden from the UI. Inherited
turnlogs are purged on external startup. A Class S rejection boundary now runs before turnlog
serialization in *every* channel, so an exception message that interpolates a credential cannot
reach the file. Internal content-bearing diagnostics are unchanged and remain enabled exactly as
approved — this pass deliberately did not scrub them.

### 5. Recurrence was wrong across daylight-saving boundaries

Four of the five recurrence helpers stepped days by adding absolute `Duration`s to midnight-anchored
local times. In a US November, "the 2nd Sunday" landed on **Saturday**; in a European March, a
"last Sunday" rule skipped a week; a biweekly 9am reminder created in January fired at **10am for the
entire DST season**. The fifth helper did it correctly and its comment stated the rule the other four
violated. All four now use calendar-component arithmetic, verified by a sweep over every day of
2025–2027 × nine rule variants asserting exact wall-clock time and correct weekday/ordinal.

Feb-29 anniversaries also had three different behaviors in one product (Mar 1 from the birthday
nudge, Feb 28 from the yearly reminder, and never from the Plan agenda). One rule — clamp to Feb 28
in common years — now lives in `dates.dart` and all three call it.

## Everything else that was fixed

**Cloud and routing.** The Settings "Test connection" probe made real Anthropic calls outside the
persisted rate ledger (now shares it). Clock rollback erased admission history and the burst window
reset at local midnight, both fail-open (now: future-dated entries count and are never erased; the
burst window is purely rolling). Weekly review included **every task ever completed** — a review in
December listing March's work, and spending a cloud call on a week that was actually empty; its
covering test encoded the bug and was corrected. All three corpus-learning paths could persist a
private name verbatim into the synced corpus ("Ann" matching inside "anniversary", or a value
appearing twice); the token-boundary guard that existed in one path is now shared by all three.
TLS/HTTP failures reported "couldn't be parsed" instead of "offline". Truncated generations were
delivered as complete answers. The content-search index never re-embedded edited records.

**Execution and operations.** `operations.json` grew without bound and was fully rewritten on every
state change (now capped at 50 terminal records, never pruning undelivered results). A failed
persist during delivery lost the results in-session and threw into the UI. A cancelled queued
operation leaked its cancellation handle; a failed queued→running persist still ran the provider
call and then resurrected the failed record as succeeded.

**Planner.** The overload signal scanned past days, so one slipped day pinned it forever and rendered
"overdue has 540 minutes against 480 available". Sort comparators lacked a total order, so which
items survived the Next cap depended on filesystem enumeration order — the "deterministic projection"
was not deterministic. Cron accepted expressions it could not evaluate (`0 9 * * MON` registered
active and silently never fired) and scanned up to 527k minutes per app open for yearly rules.
Scheduled automations pending a skill never went live until a restart, contradicting their own
documented contract.

**Storage.** A single valid-JSON-but-wrong-shape record or type file crashed cold start on every
syncing device. Conflict-copy detection recognized Dropbox and iCloud but not OneDrive (the provider
the config scaffold names) or Syncthing, stranding remote edits indefinitely. Persisting over a
momentarily unreadable file reset the version vector, setting up silent loss of that edit. Atomic
writes did not flush before rename, so power loss could commit a rename over torn data.

**App and voice.** Backgrounding permanently killed the routine cadence — an incoming call mid-workout
stalled the run forever, since resume never re-armed. A timed step elapsing mid-utterance started a
turn that caused the user's arriving transcript to be **silently discarded**. Operation deliveries
landing mid-turn were overwritten by the turn's reply, or spoken over an open mic. Long list replies
were unscrollable (the scroll view sat inside an `IgnorePointer`). Data-view completion discarded the
engine's reply, so a clarification produced no feedback at all. The local-Whisper engine — the primary
Windows path, previously with **zero tests** — dropped every transcribed word when the audio stream
errored, and never reported the end of a session on its normal stop path. A late Apple result
re-armed watchdogs into a dead session. `initializeAppCredentials` could throw out of `main()` before
`runApp`, bricking boot with a blank screen on a locked keychain.

**Continuity.** `ContinuityColumn` never repositioned a surviving item, so a reschedule rendered in
stale order until the board unmounted — in the one widget whose entire purpose is that changes read
as changes to an existing thing.

## Diagnosability

The recent incidents (a data-folder read failure, a skill-validation abort, a speech finalization
bug) were all diagnosed from phone logs, and all three were harder than they needed to be. This pass
added, within Spec 11's channel boundaries: the iOS data-folder restore outcome and the chosen data
root at boot (previously stdout-only, invisible on a phone); boot sub-phase markers before
`Session.init`, so a hang shows its phase; `ExecutionResult.error` — carried faithfully by the
coordinator and read by **no call site anywhere** — now routed into the turn trace; `CloudError.detail`,
declared "for logs" and consumed nowhere, into the turn diagnostics; the cause of unreadable files
(previously discarded, so the startup warning named files but never why); a turn correlation id
linking AppLog lines to turnlog entries; storage-refresh counts and stacks; and data-root switch
logging. Mid-run refresh now parks failing records as visible repair items instead of silently
dropping them from the in-memory store, matching what cold start already did.

## Tests that could not fail

Three defects were in the *tests*, and are worth recording because they are the failure mode a green
suite hides:

- A `returnsNormally` matcher wrapped around an async closure asserted nothing (the future was
  discarded) and ran the turn twice, corrupting the assertion that followed it.
- The mid-capture defer test passed against the broken implementation, because the deferred turn
  completed before the transcript arrived. It now asserts the actual invariant — the run must not
  advance while the mic is open.
- The weekly-review test asserted the buggy behavior directly (a task with no completion date
  appearing in the prompt), so fixing the bug required fixing the test.

Transport coverage — the weakest tier at 68.1% — is now 83.8%, with the previously untested
`authorRoutine`, `authorFigures`, request-timeout, burst-limit, and Sonnet-pricing paths covered.

## Deliberately not changed

- **Internal content-bearing diagnostics**, including recognizer hypotheses. Approved policy for a
  single-user dogfood build; this pass did not narrow it.
- **Past-scheduled items appearing in Now.** Keeping slipped work visible is defensible product
  intent; the eviction-at-cap consequence (old leftovers can crowd today's items out of the
  three-item cap) is left for the owner to judge. The garbled "Scheduled Overdue" label was fixed.
- **`Session.handle` reentrancy.** UI mutations can still interleave with an in-flight voice turn.
  Serializing turns is an architecture change that deserves its own design pass rather than being
  slipped into a review remediation.
- **`session.dart` (5,039 lines) and `main.dart` (2,133 lines) remain undecomposed.** Both hide
  separable state machines — the voice/turn machine in particular is where three of the app bugs
  lived, precisely because its invariants are spread across ad-hoc booleans no unit test can hold.
  Recommended as the next structural piece of work; the fixes here are behavioral, not structural.
