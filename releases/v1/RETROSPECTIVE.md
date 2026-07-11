# v1 — A Window on the Engine

**Release point:** `717c5ca` — 2026-07-06 ("docs(specs): reconcile the CRITICAL encryption contradiction")
**Runnable:** Windows GUI — `app/build/windows/x64/runner/Debug/plenara_app.exe` (Flutter desktop), plus the console.
**Span:** `8b65785` → `717c5ca` (2026-07-06, same day as v0), 17 commits.

## What this version is

v1 is the same engine as v0, now (a) behind a real windowed Flutter app, (b) provable —
1,004 hermetic Dart tests plus widget tests, with the cloud path replayed from a recorded
cassette — and (c) *hardened*, after a six-wave adversarial code review fixed every critical
defect the demo era had been living with. The product surface is a Material chat window over
a shared `Session` engine; the console drives the identical code. Functionally it is still
tasks / runs / moods / people-facts, now with complete-task and delete-task (the DSL gained
id-targeted update and delete ops), routed by the full cascade with learning.

## The journey from v0

**The UI was never actually blocked.** v0 had recorded UI as toolchain-gated on VS 2022; that
assumption was simply wrong — `flutter doctor` accepts VS Build Tools 2019 (`8b65785`). The
correction is characteristic of this project: the false blocker is named in the commit that
removes it. The turn loop was extracted from the console into `lib/session.dart` — a reusable
engine that *returns* its response text — so console, GUI, and test suite exercise one code
path. Flutter 3.44.5 went into `.tools/`; `flutter build windows` produced the first .exe.
An attempt at voice (flutter_tts) was reverted the same day — native plugins need Windows
Developer Mode — and recorded as the genuine gate rather than worked around (`d86a7a4`).

**The cassette: deterministic cloud tests with no network.** The cloud seam became an
interface (`CloudClient`), and `af21da5` added record/replay: `RecordingCloud` captures real
Haiku responses over a canonical input list once (BYOK), tests replay them offline, and an
unrecorded input throws loudly. The recorded reality was reassuring — Haiku routed all 18
in-domain novel phrasings correctly and abstained on all 3 out-of-domain probes. This one
mechanism is what allowed the test count to explode without ever touching the network, and
its `invSig` keying (inventory-sensitive) set up the "re-record on every new skill" cadence
that dominates later versions.

**The test avalanche.** In four commits the suite went 9 → 930: per-layer suites (453 router
cases across every date form and slot type; 111 interpreter; store CRDT round-trips; 25
offline end-to-end session stories) (`ef30c95`), a full-pipeline + seeded-fuzz suite
(`8dc8887`), an adversarial suite proving the format op is not a template-injection vector
(`29310cf`), and widget smoke tests after making `Session` injectable (`b25a130`). Hammering
found real bugs — `gte` compared numbers lexically ("10" >= "3" was false) — and the console
was rewired to the shared engine after it was caught running ~130 lines of untested duplicate
turn logic (`f841338`).

**The Fable review, six waves.** With the surface covered, an independent Fable review of the
implementation ran, and its findings were implemented wave by wave (`d08cbf9`..`69bb8bf`):

- *Wave 1 (critical):* sequential per-session record ids silently overwrote records on the
  second launch — replaced with UUID-v4. `validateSkill` rewritten into a genuinely closed
  gate (unknown ops/fns/types rejected, branch-sound, total over arbitrary JSON). The learn
  ratchet refused unsafe templates — a bare `{x:text}` template, inserted first and persisted,
  would have permanently hijacked all routing. Authoring hardened against path traversal and
  built-in clobbering; `ClaudeClient` made never-throw with a real timeout; `Session.handle`
  got its catch-all boundary (no exception reaches the UI).
- *Wave 2:* the hardcoded demo clock was removed from shipping entry points — a long-open app
  no longer freezes "today" at launch; the Flutter app can no longer brick on startup.
- *Wave 3:* CRDT fidelity — stamp-on-change (re-stamping every field had collapsed per-field
  LWW into whole-record LWW), tombstones instead of hard deletes (a hard delete resurrects on
  sync restore), corrupt-file skip, atomic writes.
- *Wave 4:* the safety floor re-keyed on harmful *framing*, not topic — "track my daughter's
  mood" (the flagship parenting marquee) is allowed; "secretly / without them knowing" blocks.
- *Wave 5:* the live client got 14 stub-server unit tests; undo became legible ("Undone —
  reversed: 'Added…'") because a safety net has to be readable to be trusted.
- *Wave 6:* `write_record target` (update) + `delete_record` — the second capability-ladder
  rung (flip task.completed) had been inexpressible — plus complete-task/delete-task as data.

The closing commit (`717c5ca`) reconciled the review's one CRITICAL *spec* finding: Spec 04
§3.1, read literally, would make every journal/sensitive write fail in v1 because CryptoBox
doesn't exist yet — a normative "v1 encryption posture" note now says plaintext-passthrough,
honestly. It also flagged the cost-cap: 20 Haiku calls/hour was sized for Haiku-as-tiebreak,
not Haiku-as-primary-cold-start-router — "do not ship the 20/hour default unchanged."

## What shipped

- Flutter Windows chat app over a shared `Session` engine; console rewired to it.
- CloudClient interface + record/replay cassette + fixture recorder.
- 1,004 Dart tests + 2 widget tests, hermetic; `dart analyze` clean.
- Six review waves: UUID ids, hardened validator, learn guard, never-throw client, per-turn
  clock, CRDT stamp-on-change/tombstones/atomic writes, framing-keyed safety, legible undo,
  update/delete ops, 9 skills.
- Spec reconciliation: v1 encryption posture, cost-cap flag.

## Known gaps at release

Undo is single-turn and in-memory; `Session` still touches the filesystem directly (no
StorageRepository seam); the DSL is 9/10 ops (`read_related` missing) and thinner than the
spec's own seed skills need; the corpus learning has no negative half (one bad learned
template misroutes forever); the app runs only against the hardcoded repo data path — no
config, no real user folder; no reminders, no people-interaction loop; voice and iOS still
gated. All of these are the explicit agenda of the next version.

## Toolchain / runnable note

First version with a Windows GUI. `flutter build windows` (VS Build Tools 2019+) produces
`plenara_app.exe`; a GitHub Release binary is feasible from this tag onward — with the caveat
that it reads its data from the in-repo path (config arrives in v2).
