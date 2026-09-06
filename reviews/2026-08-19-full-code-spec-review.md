# Full code/spec review — 2026-08-19

## Verdict

`main` was clean, fast-forward synced, and identical to `origin/main` at
`205a02e` (`Serialize turns, decompose main.dart, reserve Now capacity`). The complete repository
gate is green, but the code/spec review found **nine confirmed defects: five high, three medium, and
one low**. The highest-impact result is that the P1 iPhone target has no native notification backend,
so future reminders do not alert while Plenara is closed even though the active specifications say
they do.

This was a read-only review of product code and active specifications. No defect remediation is
included in this artifact.

## Scope and evidence

- Reviewed the active authority set (`planning/specs/01` through `17`), `WORK-CAPSULE.md`, and the
  current implementation across `v0/lib`, `app/lib`, iOS/macOS/Windows platform glue, tests, and
  verification tooling. Historical reviews were treated as evidence, not current truth.
- Traced the main user-data and control paths: bootstrap and folder authority, storage/reconcile,
  durable execution/undo, routing and content search, reminders, voice capture/output, planner and
  conversation history, privacy/build channels, and test/document gates.
- Ran `bash tool/precheck.sh` under `caffeinate -dimsu`. Analyze, import layering, engine and Flutter
  suites, coverage thresholds, macOS build, seven real-engine integration cases, external-channel
  isolation, secret scan, and the 24/60 conformance ratchet all passed. Current baseline: 2,042
  engine tests + 36 declared skips; 183 Flutter tests + 4 skips; 95.7% deterministic-core / 90.0%
  product-logic / 83.8% transport coverage.
- `dart run tool/doc_consistency.dart` passed: 32 active documents, 34 checked relative links, 27
  retired-claim guards, three project skills, three project agents, and six cloud kinds.
- No simulator or physical phone was used. No Plenara, Flutter test, precheck, or `caffeinate`
  process remained after the run.

## Findings

### H1 — iPhone reminders never reach the OS

**Impact:** A reminder created on the primary iPhone target is held only in an in-memory fake. It can
appear as an on-open nudge after becoming overdue, but it cannot alert the user at the requested time
while Plenara is closed or backgrounded.

**Evidence:** `platformScheduler()` selects a real backend only for Windows and macOS, then returns
`FakeScheduler` for every other platform (`app/lib/bootstrap.dart:33-47`). There is no iOS scheduler
implementation anywhere in `app/lib` or `app/ios`. This directly contradicts the active architecture,
which says a reminder arms `UNUserNotificationCenter` at write time because iOS cannot be relied on to
run the app in the background (`planning/specs/04-architecture.md:594-609`), and the canonical reminder
and briefing flows in Spec 05.

**Why the gate passed:** reminder tests use `FakeScheduler`; the macOS integration path exercises the
macOS adapter. No composition test asserts that the P1 iOS platform resolves to a native scheduler.

### H2 — native reminder reconciliation loses state across restart and recurring reminders arm only once

**Impact:** On macOS/Windows, a notification belonging to a record deleted while the app was closed can
still fire. A recurring reminder has only its next occurrence armed; unless Plenara is reopened after
that occurrence, later recurrences never fire. This is not the specified “next 16 occurrences” behavior.

**Evidence:** both native adapters keep their armed set only in a process-local map
(`app/lib/macos_scheduler.dart:23,102-125`; `app/lib/windows_scheduler.dart:26,90-114`). The scheduler
interface itself acknowledges that a cancel while closed can be missed because the map starts empty
(`v0/lib/reminders.dart:46-63`). Reconciliation can cancel only entries returned by that map
(`v0/lib/reminders.dart:313-329`). Recurrence projection produces one next `Reminder` per record and
keys the desired set by record id (`v0/lib/reminders.dart:112-304`); the native adapters likewise use
one notification id per record. Spec 04 requires materializing the next N occurrences, default 16
(`planning/specs/04-architecture.md:607-608`).

**Why the gate passed:** the restart test creates a fresh, empty fake and proves active records are
re-armed; it cannot represent an OS queue surviving the prior process (`v0/test/reminders_test.dart:151-166`).

### H3 — iOS folder selection commits its bookmark before validation and copying succeed

**Impact:** Selecting an incomplete/unrelated provider folder, hitting an out-of-space copy failure,
or failing the write probe leaves the old folder active in the current process but stores the rejected
new folder as the next launch's authority. On restart Plenara can therefore open the invalid/empty
destination instead of rolling back to the known-good root.

**Evidence:** the Swift picker immediately stops the old security-scoped access, creates and persists
the new bookmark, and returns the path (`app/ios/Runner/AppDelegate.swift:39-52`). Only afterward does
Dart validate the target, copy through staging, probe it, and save configuration
(`app/lib/settings_view.dart:238-269`; `app/lib/data_location.dart:118-196`). Bootstrap resolves the
native bookmark before configuration and unconditionally makes it `dataDirOverride`
(`app/lib/bootstrap.dart:124-147`). Spec 06 promises validation and copy first, configuration switch
only after success, with the old root retained for rollback (`planning/specs/06-data-sync.md:68-72`).

**Why the gate passed:** data-location tests call the Dart transaction directly and assert source-file
safety. They do not include the Swift bookmark as part of the transaction or relaunch after rejection
(`app/test/data_location_test.dart:66-88`).

### H4 — search speaks complete journal entries despite the explicit title/date-only rule

**Impact:** Asking Plenara to find a past note can cause a private journal entry's entire body to be
spoken aloud. The result also arrives as reply bullets rather than the specified ranked result card
and selection flow.

**Evidence:** journal search content is the full `entry` field (`v0/lib/content_search.dart:21-32`).
`Session._searchContent` converts each match to `• <full content>` and returns it as the assistant
reply (`v0/lib/session.dart:5130-5151`), which the voice controller speaks. Spec 05 requires a ranked
card and says the spoken response exposes only title/date, not full sensitive text
(`planning/specs/05-functional.md:506-532`).

**Why the gate passed:** content-search tests verify matching and ranking, but have no negative
assertion that journal body text is absent from the spoken reply and no result-card integration case.

### H5 — a third mic tap can start a new capture while the previous stop is still transcribing

**Impact:** A quick tap after “stop” can open a second recognizer before the first session finishes.
The old session's final callback then clears/cancels shared recognizer state and may auto-send the old
transcript while the new capture is active. The Sherpa backend compounds this by returning from
`stop()` before recorder/subscription shutdown has completed, creating audio-device contention.

**Evidence:** `toggleMic()` blocks only on recognizer availability and `_busy`; the stop branch clears
`_listening`, sets `_transcribing`, and awaits `speech.stop()` (`app/lib/voice_turn_controller.dart:431-452`).
The full-screen tap target remains enabled while transcribing (`app/lib/main.dart:838-844`). A third
tap therefore enters the fresh-listen branch and increments the shared epoch. Old final/onDone
callbacks do not capture or validate that epoch before changing state or sending
(`app/lib/voice_turn_controller.dart:522-575`). `SherpaSpeechRecognizer._teardownAudio` discards both
the subscription-cancel and recorder-stop futures, and its public `stop()` merely calls synchronous
finalization (`app/lib/sherpa_speech.dart:379-399`).

**Why the gate passed:** `_HoldingSpeech.stop()` emits its final synchronously, so the controller tests
cannot hold the transcribing window open; there is no third-tap-during-stop case
(`app/test/voice_turn_controller_test.dart:15-70,255-264`).

### M1 — content search retains deleted records and has unstable tie ordering

**Impact:** A provider-side deletion can remain in the in-memory semantic index. If stale ids consume
the semantic top-k, the user can get “nothing found” even though current records would match the
keyword fallback. Equal-scoring results can also change order with filesystem/map insertion order.

**Evidence:** `ContentSearchIndex.build` evicts absent ids only with `full: true`
(`v0/lib/content_search.dart:35-63`), but both production full-store calls omit that flag at startup
and after external reconciliation (`v0/lib/session.dart:1224-1229,1350-1354`). `full: true` appears
only in a component test. Semantic and keyword sorts compare only score, with no stable id tiebreaker
(`v0/lib/content_search.dart:84-89,131-140`). Spec 04 says the current in-memory index is rebuilt from
record content and updated after writes (`planning/specs/04-architecture.md:611-626`).

### M2 — active specifications contain mutually exclusive current claims, and the document gate misses them

**Impact:** An implementer cannot reliably determine current behavior from the active authority set;
the “all green” document check does not mean active prose matches wired behavior.

Confirmed examples:

- Spec 14's amendment says the user finalizes and stop flushes, but its architecture and shipped-path
  sections still say the engine finalizes, a second tap aborts, and partials are ignored
  (`planning/specs/14-voice-input.md:3-20,50-115`). Its status says Sherpa is primary, while Apple
  production explicitly skips Sherpa and uses the system recognizer (`app/lib/main.dart:410-439`).
- Spec 09 simultaneously labels coverage instrumentation shipped and its largest gap/open item
  (`planning/specs/09-test.md:194-204,280-285`), and still says voice, automations, durable restart
  undo, merge, and a widget tier larger than eight tests are unbuilt
  (`planning/specs/09-test.md:156-174`). Those are contradicted by the current implementation and
  183-test Flutter baseline.
- Spec 17 calls an older 1,922/161/94.7/90.5/68.1 gate the current aggregate
  (`planning/specs/17-living-planner.md:40-47`); current truth is
  2,042/183/95.7/90.0/83.8.
- Spec 05 says journal entries live under `journal/YYYY-MM-DD-<id>.json`
  (`planning/specs/05-functional.md:464-484`); Spec 06 and the implementation place them in flat
  `records/{recordId}.json` (`planning/specs/06-data-sync.md:74-89`).
- The threat model says the content index is “not yet built” and, later in the same document, says it
  is the current in-memory map (`planning/specs/10-security-privacy-threat-model.md:52-64,99-108`).

`tool/doc_consistency.dart` passed all 27 retired-claim guards, so these contradictions are outside
its current assertions.

### M3 — the conversation/action ledger is narrower than its active product contract

**Impact:** History cannot show which records a turn affected, proposal acceptance, or failure/recovery
state. After relaunch, a user sees text, route source, time, and sometimes an execution undo, but not
the richer causal history the active product spec claims is wired.

**Evidence:** Spec 17 requires affected-record links, durable execution, proposal/acceptance state,
failure/recovery state, and targeted actions (`planning/specs/17-living-planner.md:134-146`).
`ConversationEntry` stores only utterance, reply, source, timestamp, and optional execution id
(`v0/lib/conversation_ledger.dart:10-56`); the History card renders exactly those fields
(`app/lib/today_view.dart:654-730`). This is a declared destination presented inside an active,
fully-wired product authority, not current implementation.

### L1 — “Keep current” falsely claims the conflict resolution is undoable

**Impact:** The Attention surface tells the user an undo is available after “Keep current,” but that
path only clears conflict metadata and creates no durable execution.

**Evidence:** `resolveRecordSyncConflict(... restoreOther: false)` skips `_executeMutation` and only
clears the conflict (`v0/lib/session.dart:882-908`). The view uses the same success copy for both
choices: “The change is saved and undoable” (`app/lib/attention_view.dart:62-71`). The widget test
asserts that copy only for the restore path and never exercises Keep current
(`app/test/attention_view_test.dart:83`).

## Review conclusion

The repository is analytically clean and has unusually broad deterministic coverage, but the passing
gate overstates product readiness at four integration boundaries: platform composition, durable
native state across process death, asynchronous recognizer lifecycle, and executable spec alignment.
The five high findings are user-visible correctness/privacy failures, not architectural preferences.
The three medium findings explain why the suite and active docs did not expose them.

## Post-review remediation status — 2026-08-19

This section records the later remediation without rewriting the read-only findings or their original
evidence. All nine findings are resolved in the working tree:

- **H1/H2:** iOS now selects a native notification adapter. All native adapters persist versioned
  record/time payloads, reconstruct the OS queue after restart, cancel legacy/untraceable entries,
  materialize the next 16 recurring occurrences, and keep only the earliest 64 globally.
- **H3:** the iOS picker now grants a provisional folder. Validation, staged copy, and write probe
  precede an explicit native commit; finalize releases the prior scope and rollback restores both
  the prior bookmark and Dart configuration.
- **H4/M1:** content search performs a full live-store rebuild at startup, provider refresh, and the
  search door; deleted ids are evicted and score ties use record id. Speech exposes title/date only;
  full content is confined to ranked tappable result cards.
- **H5:** the transcribing state disables every voice target, callbacks are capture-epoch checked,
  and Sherpa stop awaits recorder and stream teardown through one idempotent finalization future.
- **M2:** Specs 04/05/06/09/10/14/17 now state the wired behavior. `doc_consistency.dart` has 36
  retired-claim guards and was proven red against a deliberately restored stale claim before green.
- **M3:** conversation entries persist derived outcome, affected record ids, proposal/acceptance
  state, and failure/recovery state. History renders the state and opens affected records directly.
- **L1:** restore-other retains truthful undoable copy; Keep current now says only that the current
  value was kept.

Each changed behavioral verifier was exercised against its corresponding broken state before the fix
was restored. Final `bash tool/precheck.sh` is green at 2,046 engine tests + 36 skips, 189 Flutter
tests + 4 skips, 95.7% / 89.9% / 83.8% coverage, macOS build, seven real-engine cases, external and
secret gates, and 24/60 conformance. The iOS simulator artifact builds. A production notification
run reached the iOS Allow sheet, but the host locked before Computer Use could click it; the final
OS-queue assertion therefore remains unclaimed, and no bypass exists in production or the test.
