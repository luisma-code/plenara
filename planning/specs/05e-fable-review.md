# Spec 05e — Fable Review #2 (impl + spec), 2026-07-07

A three-lens Fable (Claude 5) review requested after the spec-conformance program reached
8/10 of its ranked top-10. Three independent reviewers: **architecture/impl**,
**spec-fidelity**, **strategic direction**. This doc is the synthesis + the action ledger.
(Prior review: [`05c-fable-review.md`](05c-fable-review.md).)

---

## The one-line verdict (all three agree)

The engineering is genuinely strong — the two-phase interpreter + static gate, typed cloud
seam, derived-reminder reconciliation, and honest test discipline are better than most
funded teams manage. **But the project is optimizing a rubric (05a / the top-10) instead of
a life:** it has **never run a single real turn**, effort is flowing to Claude-buildable
breadth while the load-bearing basics (a reminder that actually fires, real usage, the core
loop's reliability) wait, and the code has quietly grown a **second dialect** that no spec
records. Fix the real bugs, turn the gap-register around to face the code, unblock the
20-minute human-gated window, and **dogfood** — or in a few weeks the specs become
archaeology and the app stays a beautifully-tested artifact no one uses.

---

## Lens 1 — Architecture / Implementation (the code has real bugs)

**Healthy core, but `session.dart` is the rot risk, not the interpreter.** The `resolve`→
`execute` + before-image design makes undo an engine property; the derived armed-set makes
reminder reconciliation fall out for free; `validateSkill` is the load-bearing gate. Real,
not aspirational. Tests mostly earn trust (drive the real turn engine, fakes only at true
seams) though "1270" is parametrization-inflated to ~350 real behavioral cases.

**Bugs found (ranked):**
1. **[P0 data-loss] Correction reverses an unrelated write after any non-routed turn.**
   `_lastTurnWrote`/`_lastTurnTemplate` are set only in `_dispatch` and reset only in
   undo/correction, so every early-return path (clarify miss, generative, authoring,
   builtin-tracker, OOD, help, fabrication) leaves them **stale**. "add buy milk" (writes) →
   "flurble" (miss) → "no, I meant to log a run" → the correction reverses the *milk task*.
   It's the sibling of the read-only-misroute defect already fixed — the fix didn't cover
   the guard paths. Fix: snapshot prev at the top of `_handle`, default this turn to
   "wrote nothing", let `_dispatch` upgrade.
2. **[P0-before-sync] Three CRDT on-disk format flaws** that sync will fossilize: constant
   `HlcDevice('this-device')` id (two devices → indistinguishable stamps); no tombstone
   when deleting a never-locally-persisted id (→ resurrection); delete-then-rename write is
   not atomic (crash-in-window loses the record). Format is forever — fix before dogfooding
   on a synced folder.
3. **[P1] ProvideSlot swallows help/corrections** as the slot answer (only cancel/undo
   escape the pending state).
4. **[P1] Validator var-closure gaps:** `listVars` dropped across branch merges; no
   format/compute placeholder-binding check (typo'd `{persoName}` validates, renders empty —
   silent failure at authoring time); no runtime entityRef existence check in `_resolveWrite`.
5. **[P1] The regex intent cascade is unowned architecture** — ~12 module-level regexes whose
   ordering in `_handle` is load-bearing and undocumented; wants to be a first-class ordered
   `IntentGuard` list.
6. **[P1] Learned templates can permanently shadow seed skills** (both insert at index 0);
   a learned `note {text}` outranks the seed `note that {person} {fact}` forever.
7. **[P2 — regression added THIS session] "who is Mia?" is bounced out-of-domain** — the OOD
   `who (is|was)` pattern with only a first-person cue guard violates the very
   records-privacy invariant it was built to protect. Check the store for a matching contact
   before declaring OOD.
8. **[P2] Product/ship items:** `list-tasks` shows completed tasks (no filter — inconsistent
   with due-tasks); contact-resolution logic duplicated (interpreter vs generative) and
   already diverging; **no real `NotificationScheduler` wired in `app/lib/main.dart`** (the
   flagship reminder feature produces no toast in the shipped app); hardcoded `Z:\code\…`
   seed path + model id are release blockers.

## Lens 2 — Spec fidelity (drift is now flowing the un-ledgered direction)

The gap-register lifecycle worked spec→code, but **"resolved" increasingly means "resolved
in prose, contradicted in code,"** and code→spec drift has no ledger. Concrete forks:
- **Authoring ships the measured-drift config (G-29 inverted):** `claude.dart` uses
  `claude-haiku-4-5` for `authorCapability` with regex JSON extraction — exactly the
  configuration the measurement said drifts; spec mandated pinned Opus + structured output.
  Safety Layers 2/3 absent, so Haiku is author *and* sole safety gate (the DP-08 shape).
- **The branch-condition grammar exists only in Dart** — `{isNull|notNull|gte|eq|contains}`
  appears in no spec; the "closed vocabulary" compliance story needs the spec to name it.
- **The `reminder` type forks the data model:** spec says a reminder *is* a `task` with a
  datetime `dueAt`; code ships a separate `reminder` type → "what's due" and "my reminders"
  are disjoint stores (generative.dart already has to query both). User-visible, unrecorded.
- **Value-type fork:** code has `integer`, rejects spec's `number/tag/duration/json/attachment`;
  the authoring prompt propagates the fork into every authored type. `avg([])→0` vs spec
  `null`; `decimal` not preserved (`sum` folds `double`).
- **G-14/15 reversed** (anchored date math in the DSL/skill vs the spec's resolver) and
  **G-18 skipped** (instant activation vs "nothing registered until 'activate'") — both with
  no spec update or gap entry.
- **Generative recognition is code, not data** (`_giftRe`/`_builtinTrackers` vs the spec's
  `kind: generative` CapabilityIndex) — the P2.6 crack: each new kind/template is a recompile.
- **Corpus trust ratchet is binary** (learn/forget) vs the spec's graded initConf/decay/
  requiresPreConfirm — and the §13 "learning-curve" make-or-break metric assumes the graded model.
- **No 05a conformance harness** — "47 fail → N fail" is a hand audit that will rot.
- **Doc contradictions:** journal has three simultaneous privacy postures across 05a/05c/01.

Fix: **turn the gap register around** — file G-39+ for each code→spec divergence in the same
spirit that made the spec phase work; refresh the stale Spec 02 §3 banner; stand up a
table-driven `test/spec05a/` conformance suite (doubles as the drift ledger).

## Lens 3 — Strategic (stop optimizing the rubric; go get real usage)

**Zero real turns have ever been run.** No `~/.plenara/config.json`, no synced folder, no
turnlog data. The instrument (turnlog + report) is built and excellent and has never
recorded a real turn. That fact dominates.
- **The top-10 program is mined past diminishing returns** — declare victory at 8/10. The
  remaining items (authoring loop, template library, RRULE, more generative kinds) are
  exactly what only real usage can prioritize.
- **The autonomy machinery (never-ask + Stop hook) structurally steers effort toward
  whatever Claude can build alone** — and everything gated on Luis (the firing toast, voice)
  is precisely the highest-value work. The last commit (a *third* generative kind) shipped
  while toast/voice sat blocked: the structural symptom, not a one-session lapse.
- **Voice is only *softly* gated** — Windows STT needs a mic + a human smoke, not admin; it's
  in the "tonight" bucket by association with ATL, not necessity. The seam pattern means
  Claude can build the `SpeechInput`/`SpeechOutput` logic now, tested against fakes.
- **The exposed BYOK key + GitHub PAT are still unrotated** after multiple sessions — a real
  liability sitting in a to-do list.
- **Honest caveat:** the moments Plenara serves happen mostly away from a desk; daily usage
  may be structurally capped until mobile. Mitigate by leaning into desk-shaped moments
  (morning briefing, evening journal, weekly review) + near-zero-friction capture (hotkey +
  voice). Don't read low usage as product failure before ruling out form-factor.

**Next 3 moves (strategic):** (1) the 20-minute admin window tonight — rotate both creds,
run the one-line ATL install, write the config pointing at a real synced folder; (2) the
voice spike immediately after (push-to-talk Windows STT behind the seam + a global hotkey);
(3) **freeze the backlog and dogfood for 7 days** — reminders + people notes through Plenara
only, run `turnlog_report` daily, and let the log — not 05a — write the next ranked list.

---

## Synthesized action ledger

**P0 — reliability before any more dogfooding (Claude, now):**
- [ ] Fix the turn-state data-loss bug (correction after a non-routed turn). — *impl #1*
- [ ] Fix the OOD "who is Mia" regression (store-check before declaring OOD). — *impl #7*
- [ ] `list-tasks` filter out completed tasks. — *impl #8*
- [ ] ProvideSlot: run system-command guards before consuming input as a slot. — *impl #3*

**P0-before-sync (Claude, before dogfooding on a synced folder):**
- [ ] Per-install random HLC device id; unconditional tombstones; real atomic replace. — *impl #2*

**P1 — turn the gap register around (Claude):**
- [ ] File G-39+ for each code→spec fork (reminder-type, value-types, cond grammar, G-14/15,
      G-18, generative-recognition, binary ratchet). Refresh the Spec 02 §3 banner.
- [ ] Decide the `reminder`-vs-`task` data-model question (merge to task+datetime, or write
      the two-type decision into Spec 01 §12 with rationale). — *spec #3*
- [ ] Stand up a `test/spec05a/` conformance harness (skip-with-G-ref for unbuilt). — *spec #9*
- [ ] Wire a real `NotificationScheduler` into `app/lib/main.dart` (currently none). — *impl #8*

**P1 — build the human-gated logic behind seams (Claude, so the smoke is thin):**
- [ ] `SpeechInput`/`SpeechOutput` seam + fakes; global-hotkey summon. — *strategic #2*
- [ ] Real Windows toast `NotificationScheduler` impl behind the seam (needs ATL to compile).

**Luis-gated — the 20-minute window (only Luis can):**
- [ ] Rotate the BYOK key + the GitHub PAT (still exposed).
- [ ] Install the ATL VS component (admin).
- [ ] Write `~/.plenara/config.json` → a real synced folder + key.
- [ ] **Then: commit to 7 days of dogfooding; freeze feature-breadth.**

**Deferred (unchanged):** CRDT merge engine, at-rest encryption, presentation archetypes,
the authoring refine loop, RRULE reminders, the full template library, more generative kinds
— all now explicitly *usage-gated*, not backlog-gated.
