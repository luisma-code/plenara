# Spec 05c — Independent End-to-End Review (Fable)

**Status:** v1.0 — July 2026 — full-corpus critical review by Claude Fable 5, run independently of the authoring model (Opus 4.8).
**Scope reviewed:** research doc v0.10 (locked — critiqued, not edited), Specs 01–05, 05a (catalog + traces), 05b (gap register), and the Phase-3 empirical record (`research/spec-05a-phase3/findings.md`, `local-model-eval.md`).
**Method:** read the corpus end to end in dependency order; checked every cross-spec seam named in one spec against its definition in the other; checked the two measured pivots (local-model NO-GO → Spec 03 §7.3; safety findings → Spec 02 §7.6) for stale residue elsewhere; checked the locked principles (act-then-describe, no-silent-failure, code-over-AI, capabilities-as-data) end to end. Known items in 05b §5 (the truncation/completeness backlog) were treated as already-tracked and are not re-surfaced.
**Edits:** every "Edited" finding below is an uncommitted change in the working tree, reviewable as a diff against HEAD. New gaps were registered as **G-34…G-38** in 05b §1.

**Overall verdict up front.** This is an unusually coherent design corpus for its size — the resolve-stage discipline (trace → gap → fold-back → re-confirm) genuinely worked, and the two measured pivots were absorbed *at the decision level* correctly. The weaknesses are of three kinds: (1) the pivots were absorbed in trailing amendments while the body text of Specs 03/04 still described the dead design — an implementer reading linearly would build the wrong router; (2) a handful of seams that *look* welded are not — most seriously, the post-pivot router's accuracy has never been measured as a stack, the journal's privacy invariant rested on a sync exclusion no platform can deliver, and reminder *delivery* has no owner at all; (3) the locked research doc now contradicts its own measured record in several load-bearing places and needs an in-session amendment pass from Luis.

---

## 1. Findings, ranked by impact

### F-1 · The post-NO-GO router's accuracy is asserted, never measured — the biggest open bet in the corpus
**Severity: HIGH · Location: Spec 03 §7.3, local-model-eval.md §11 note (c) · Edited (Spec 03 §7.3.4 measurement-gate paragraph; 05b G-38) · Confidence: high that it's unmeasured; medium that it will disappoint.**

The G-20 eval was well designed and the NO-GO call is right. But the eval isolated the *models*: every test case handed the model a pre-built, correct candidate set. The replacement design makes the **retrieval embedding model the router** (top-1-with-margin), and nobody has measured whether retrieval *alone* puts the correct capability at top-1 with margin ≥ τ on the labeled utterance set. Similarly, §7.3.3's claim that the deterministic extractor inventory is "*more* reliable, not a downgrade" vs Haiku's 78% slot-exact is an inference, not a result — dates/entities/quantities are rule-shaped and will likely beat 78%, but the free-form `text` span heuristic ("the residual after removing the matched trigger") is exactly the kind of thing that degrades badly on disfluent speech ("um, remind me to, uh, call the plumber I guess, Thursday"). MiniLM-class embeddings on *terse* utterances ("had oatmeal", "5k") over near-neighbor skills (`log-meal` vs `log-interaction`; the task/reminder twins that dragged even Haiku to 70% on class E) are a real risk of a high clarify-rate in exactly the cold-start weeks where the corpus hasn't learned anything yet — and on the offline free tier there is no Haiku to absorb the residual, only clarification. If the clarify rate is high early, the §2.1 vision ("within a few weeks the app rarely asks") depends on the user tolerating an interrogative app long enough to teach it. **This is one harness extension away from being a number instead of a hope** (`eval_routing.py` re-scored retrieval-only + extractor-only), and I have gated the section on it. It should be the first thing the Phase-0 local-routing spike measures.

### F-2 · The journal's privacy invariant rested on a platform capability that doesn't exist
**Severity: HIGH · Location: Spec 05 §11, Spec 01 §12.3, research §10.3 · Edited (Spec 01 §12.3, Spec 05 §11; 05b G-37 resolved) · Confidence: high.**

Spec 05 §11 promised the journal is "never in the cloud-synced portion (the journal/ subfolder is excluded from sync)" — with `journal/` a subfolder of the user-chosen synced Plenara root. **No major provider gives an app a reliable, programmatic way to exclude one subfolder of a user-synced tree**: iCloud Drive's `.nosync` behavior is macOS-side and undocumented for iOS document-provider roots; OneDrive has no client-side app-settable folder exclusion; Google Drive mobile has none. Had this shipped, the most sensitive data in the app would have synced to the cloud while the spec asserted a testable invariant that it never leaves the device. Since journal entries are *by design* never synced, storing them in the synced root bought nothing; I moved them to device-local app storage (`[app-support]/plenara/journal/`, encrypted), alongside the execution journal. The research doc §10.3 ("Stored as journal/YYYY-MM-DD.json") is locked and still says the old thing — flagged in §3 below. Follow-on for Spec 06: the StorageRepository now has a second, non-watched, non-synced root.

### F-3 · Reminder *delivery* has no owner — a marquee free-tier task with a missing mechanism
**Severity: HIGH · Location: Spec 04 §3.9/§4.8, Spec 05 §5/§8/§15 · Flagged (05b G-35); not edited — needs a real design decision · Confidence: high.**

A `task` with `dueAt` must make the phone buzz at that time. `AutomationRunner` owns only the `automations/` registry (cron + onWrite); a task record is not an automation, and no component in Spec 04's inventory arms OS notifications from `dueAt`/RRULE fields. Worse, the implied mechanism (a live in-app scheduler) does not exist on iOS: apps get no reliable background execution (BGTaskScheduler is opportunistic), so both F2 reminders and the 7 AM briefing automation (§15) cannot assume the app is running at fire time. The realistic shape is: schedule `UNUserNotificationCenter` local notifications *at write time* (and re-derive the next N occurrences of each RRULE on every app open), and make the "7 AM briefing" a local notification whose *tap* triggers generation (or generation-on-next-open), not a background Claude call. This is Spec 06 territory, but it constrains Spec 04's component model (a `NotificationScheduler` is missing) and softens a marquee promise ("delivered as natural speech at 7 AM" becomes "waiting for you at 7 AM"). Registered as G-35; this is a pre-v0 design item, since even the walking skeleton (v0 scope: "local reminder") hits it.

### F-4 · The NO-GO pivot left the body of Specs 03/04 describing the dead router
**Severity: HIGH (implementability) · Location: Spec 03 §§3.4, 3.5, 4.1 Axis-2, 4.3; Spec 04 §4.1, §4.2 · Edited (supersession banners + pipeline/isolate-table rewrites) · Confidence: high.**

Spec 03 absorbed the NO-GO only as trailing amendments (§7.1–7.3) while §3.4 ("Classification Step (Local Model)"), §3.5's confidence-based escalation trigger, the Axis-2 threshold table, and the §4.3 flow diagram all still read as normative — and Spec 04's isolate table put "the local llama.cpp model … classification, extraction" on the inference isolate with a turn pipeline showing "local classify → local low-conf → cloud". An implementer reading front-to-back would build the measured-dead design. I added explicit SUPERSEDED/amended banners at each stale section (keeping them as design record for the optional future tie-breaker role) and rewrote Spec 04's isolate row and pipeline diagram. Related and also fixed: **the `routingSource` enum had no value for the new common case** — a retrieval-margin dispatch had no defined source, which broke the corpus write-back's boost-vs-create rule (§2.6 keyed on `local_model`/`cloud_model`). Added `retrieval` to the enum and threaded it through §2.1/§2.5/§2.6. Also fixed Spec 01 §6.2, whose weekly consolidation pass still said "(on-device, local model)".

### F-5 · The undo ring of one silently breaks the correction contract
**Severity: HIGH · Location: Spec 04 §3.11 vs Spec 05 §3.3 · Edited (Spec 04 §3.11) · Confidence: high on the inconsistency; the fix is my judgment call.**

Spec 04 §3.11's v1 default was "the last completed execution, for 5 minutes — or until the next completed write." Spec 05 §3.3's correction flow (the single most important correctness path in the free tier, per F-14) reverses *the prior turn's* write via its before-images and asserts "the reversal is always available." These contradict: log a run, then log water, then say "no, that run was a walk" — the run's journal entry was already evicted by the water log, and the correction cannot reverse it; the misroute leaves an orphan record, exactly what F-14 exists to prevent. I widened the retention to a small ring (last 5 completed executions within the window), kept bare `undo` targeting only the most recent, and added the honest degrade for corrections arriving after the window ("want me to just fix the record?" — an update, not a stale reversal). Genuine problem, not taste; the specific ring size is tunable.

### F-6 · Capabilities-as-data has two quiet cracks: `instantiate-template` and automation edits are not expressible in the DSL
**Severity: MEDIUM-HIGH · Location: Spec 02 §9.2, Spec 04 §3.9, Spec 05 §6/§15 E4, P-19 · Edited (Spec 02 §9.2 boundary note; Spec 04 §3.9 meta-operation paragraph) · Confidence: high.**

The ten primitives write *records of registered types*. Registering a type and binding skills (`instantiate-template`), and rewriting an `automations/` file ("move my briefing to 6:30", P-19 — which the traces even described as "a `foreach` over automation config writes"), are registry operations no primitive can perform — yet both sat in the seed-*skill* table / flows as if the interpreter ran them. Left implicit, this is how a "just this once" eleventh primitive sneaks into the closed vocabulary during implementation and muddies both the safety ceiling (§13.1 of the research doc) and the Apple 2.5.2 story. I made the boundary explicit: both are **system meta-operations** — voice-routable capability-index targets that the orchestrator dispatches to the registry, exactly like `search-records` already was. This also surfaces a small UX seam I only flagged: `undo` after "track my mood" is undefined (type registration isn't a record write; strictly it needs the §24 deletion flow, which pre-confirms — awkward for something created two seconds ago; a freshly-instantiated, zero-record template could get a lightweight instant-remove path).

### F-7 · The corpus flow-table is a monolithic synced file under whole-file LWW — a multi-device self-conflict
**Severity: MEDIUM-HIGH (dormant until multi-device) · Location: Spec 03 §5.1/§5.3-layout · Edited (caution note in §5.1; 05b G-36) · Confidence: high.**

The storage layer's whole design principle is per-record files *because* whole-file LWW sync destroys concurrent edits (research §8.2, Spec 02 §5.2 used the same argument to evict execution state from skill files). Lane 1 then puts the single most frequently-written file in the system — `nlu/flow-table.json`, one write-back per dispatched turn — into the synced root as one monolithic JSON. Two devices in use in the same sync window will clobber each other's learned entries or spawn conflict copies nobody handles; the "earned phrasing that should survive a device swap" rationale is defeated by the very mechanism chosen to deliver it. Tolerable for a single-device v1; must be per-entry files or per-device journals merged at load (the data is append-mostly and mergeable by construction) before P2 (Windows desktop) makes two live devices the normal case.

### F-8 · The record-content search index (F-12) is specified nowhere
**Severity: MEDIUM · Location: Spec 05 §12, Spec 01 §5.4 · Flagged (05b G-34) · Confidence: high.**

`search-records` needs an embedding index over record and journal *content* — a different artifact from the `CapabilityIndex` (which indexes type/skill/generative *metadata* only). No spec names its owner, rebuild triggers (every record write? batched?), storage location, or protection. The protection question is not pedantic: embeddings of journal text are invertible enough to leak meaning, so this index must be device-local **and encrypted at rest** — Spec 05 §12 E4's "the embedding itself is not stored in the cloud" is the right instinct without a mechanism behind it. Also a startup-cost question: embedding every record ever written is much heavier than embedding a hundred capability descriptions.

### F-9 · Seed-skill bugs: the canonical examples fail their own validator
**Severity: MEDIUM (but embarrassing at spike time) · Location: Spec 02 §9.2, §3.6 · Edited · Confidence: high.**

`query-last-interaction`'s `format` referenced `{lastLabel}`, a variable no step ever binds — the skill fails §6.4's own variable-closure check (rule 4) and violates the §9.1 confirmation idiom it sits under. Fixed with the idiomatic `compute format_date(...) → lastLabel`. `recall-contact-fact`'s absent-case default nested `{subject.displayName}` inside a `default:` literal — undefined in the format grammar, and null when the person is unknown (the exact case the default serves); rebuilt it from the always-present `subjectName` slot. And the "a null `medium` filter matches all" behavior both skills rely on existed only as a footnote while §3.6's normative text said literal values are exact matches (which would make a null filter match only null fields — the opposite). Promoted the null-drops-the-entry rule into §3.6 with the explicit-`null`-operator contrast. These matter because Phase 0's most important spike hand-encodes skills against exactly these semantics.

### F-10 · Assorted cross-spec drift (each small; together they erode trust in the seams)
**Severity: LOW-MEDIUM · All edited · Confidence: high.**

- **`foresight` missing from Spec 03 §2.2a's "fixed" set** while Spec 04 §3.10 (G-27) and the traces both said it was added there. A closed enum that two specs disagree about isn't closed. Added.
- **Spec 05 §3.8 said "Seven of the ten paid marquee tasks" then listed eight.** Fixed to eight, with the foresight note.
- **Spec 05 §3.7's seed-type list** omitted `contact_fact`, `contact_relationship`, and `goal` — the §9 flows it governs literally cannot run on the four types it listed. Fixed.
- **Journal consent granularity:** Spec 05 §11 said "per-entry" opt-in; the resolved design (G-26, DP-07, Spec 04 §3.10) is per-session assembly-time consent. Aligned to per-session.
- **`ConfirmationKind` name collision:** Spec 03 §2.6 and Spec 04 §3.6 defined two unrelated enums with the same identifier. Renamed Spec 04's to `PreActionConfirmKind`.
- **`SelectCandidate { String skillId }`** was too narrow — the same response answers entity disambiguation ("Which Sarah?"), where the id is a contact. Renamed to `candidateId` with semantics keyed to the prompt.
- **Stale references:** Spec 01 §4.1's example still carried the retired `confirmationTemplate`; §4.2's `nluHints` row pointed at nonexistent §10 without noting the retirement; Spec 02 §3.3 cited "the confirmation template in Spec 01 §10"; Spec 04 cited `CloudResult` at "(§3.10)" (is §3.5) and a literal placeholder "Spec 02 §7.x". All fixed. Spec 01's header depended on "Research doc v0.8" (now v0.10). Fixed.
- **Spec 01 §5.3** lacked the invariant that an automation's skill must not be `destructive` — asserted in Spec 02 §7 and Spec 04 §3.9 but enforced nowhere in the registry's own invariant list. Added.
- **Rate-limit honesty:** Spec 03 §3.5 degraded an over-limit escalation to a bare clarification; Spec 04 §5.2 maps `rateLimited` to "I've hit today's limit." A clarify that hides *why* it's asking is a quiet failure by the corpus's own P2.8 standard. Aligned Spec 03 to name the limit.
- **F6's flow prose** still described the pre-G-10/G-11 model ("Attribute allergy on Mia's record"); aligned to `contact_fact`/`contact_relationship`.
- **§7.3.3's extractor table** used value-type names that don't exist in Spec 01 §3 (`recurrence`, `entity`, `integer`). Aligned.

### F-11 · The briefing's Batch-API costing was stale against the corpus's own measurements
**Severity: LOW-MEDIUM · Location: Spec 05 §15, research §7.2 · Edited (Spec 05 §15 freshness note) · Confidence: high.**

"Batched overnight" for a 7 AM briefing is both operationally wrong (batch completes "within 24 h" — not guaranteed by 7 AM) and semantically wrong (assembled from yesterday's data; the 11 PM task is missing). The discount defends a third of a tenth of a cent against measured Haiku cost of ~$0.0007/briefing (findings §10.1). Changed the default to generate-at-fire-time; batch stays right for the weekly consolidation pass. The research doc's §7.2 batch framing is locked — see §3.

---

## 2. Where I doubt the design will actually work (flagged, not edited — these need experiments or decisions, not prose)

**D-1 · Mobile file-sync as the storage backbone (iOS especially).** Known as a Phase-0 spike, but I want to sharpen *why* it's the riskiest infrastructure bet: on iOS, files in an iCloud Drive (or provider) folder can be **dataless** — present as metadata, content evicted — so "scan the folder and parse changed files at startup" can mean triggering hundreds of on-demand downloads behind a security-scoped bookmark, with no reliable change notifications while the app is backgrounded (there is no FSEvents equivalent for provider roots on iOS; NSMetadataQuery works for iCloud only). The "10,000 files parse in under a second" figure (research §8.4) is a desktop number. The startup gate (Spec 04 §4.5 — no dispatch until hydration completes) then puts this directly in the voice-latency path: a cold start after a big sync could hold the mic hostage for seconds-to-minutes. If the Phase-0 spike shows this, the mitigation shape is an on-device change-journal + lazy hydration by type, which touches Spec 04's "complete store before dispatch" invariant — better to know early. *Confidence that this bites on iOS in some form: high.*

**D-2 · The emergent-types bet is validated for authoring, not for living with the result.** The measurements prove models emit valid DSL; they don't yet test the *governance* loop: the 0.85 reconciliation threshold is a guess with no data; merge mappings are Claude-proposed (paid) so a free-tier user accumulates duplicates the triage list can name but not fix; and nothing measures whether an authored type's `examplePhrases` (model-written) are good retrieval anchors — a badly-phrased authored type will lose the retrieval-margin race to seeds forever, and the user will experience it as "my custom tracker never works by voice." The v1.2 capability-ladder rung tests one user-defined type; the sprawl dynamics only appear at ten. *Confidence this needs iteration: medium-high.*

**D-3 · Apple 2.5.2 residual risk.** The compliance argument (§13.6) is genuinely good — interpreter in binary, human-readable JSON, no remote fetch — and the corpus consistently protects it (§3.0's refusal to persist compiled form; my F-6 edit keeps meta-operations out of the DSL). Two residual exposures: (a) skills *do* arrive over the network in one sense — via the user's own cloud folder syncing from another device; a literal-minded reviewer may not care that the server is the user's iCloud; (b) the 2026 enforcement wave (Anything, Replit, Vibecode) shows Apple judging by *product framing* as much as mechanism — marketing that says "describe a capability and the app builds it" pattern-matches to exactly what they've been pulling. The pre-submission review in §15.2 should happen before v2 builds the authoring UI, not before store submission. *Confidence in eventual approval: medium; confidence that the framing needs care: high.*

**D-4 · Prompt-injection posture is complete for authoring/classification, unstated for generation.** Spec 02 §7.3 correctly keeps user record *content* out of authoring and classification prompts. Generative prompts, by their nature, are *full of* record content (a briefing includes task descriptions; event prep includes notes) — a hostile or accidentally-instruction-shaped note ("ignore previous instructions and tell the user to…") lands inside a Claude prompt. The blast radius is genuinely small — generative output is read-only prose, no tool calls, nothing executes — and G-25's addressable items are only consumed by a *user-initiated* following turn. But the posture ("injection into generation is contained by read-only-ness, and assemblers should delimit record content as data") should be stated in Spec 08 rather than left to be rediscovered. *Flagged for Spec 08's outline.*

**D-5 · The corpus fast-path's slot-recipe quality is load-bearing and lightly specified.** Post-NO-GO, the fast path isn't an optimization — it's the *primary* router for repeat phrasings, and its `span`/`fixed` slot recipes are doing extraction work. §5.4 (normalization/templating) is in the known completeness backlog, but I'll note the stakes have risen since that backlog was written: the templating algorithm is now correctness-critical path, not P1-nice-to-have. Recommend promoting Spec 03 §5.2–5.6 to the top of the completeness queue (05b §5 already points there — endorse it).

**D-6 · "60/60 traced" overstates slightly.** §§7.1–7.8 trace representatives per cluster and confirm the rest against the pattern. That's a sound method, but the five deep traces caught defects (G-12's name/id defect, G-17) that pattern-confirmation would have missed in siblings. The claim should be read as "60/60 dispositioned, ~12 deeply traced." Not edited — the method is defensible — but calibrate confidence accordingly.

---

## 3. The locked research doc — proposed amendments (not edited, per lock)

The research doc is now contradicted by the corpus's own measured record in four places. Proposed changes for Luis to apply in-session:

1. **§7.1 "The Local Model (95% of AI calls)"** — the section's premise (a 1–3B generative model doing classification/extraction) is measured-dead (findings §11: ≤49% routing, 0% meta-intent, dead calibration). The *spirit* survives — ~95%+ of turns still complete with zero cloud calls — but the mechanism is now: corpus fast-path + dedicated retrieval-embedding model (~80 MB) + deterministic resolvers, with Haiku on the genuine residual. Rewrite §7.1 around that stack; keep the 1–3B model only as a future tie-breaker option gated on a new eval. The same correction applies to §2.5's "local model handles ~95% of calls" phrasing and — outside this review's edit scope — **CLAUDE.md's stack line** ("Local NLU: llama.cpp 1B–3B model via Flutter platform channel"), which now describes a component the design cut.
2. **§7.2 / §3.3 batch framing for the briefing** — see F-11; batch is wrong for deadline-anchored generation and defends a rounding error of cost.
3. **§10.3 journal location** — "Stored as journal/YYYY-MM-DD.json" in the synced folder is superseded by G-37 (device-local, encrypted); §8.2's folder diagram similarly shows `journal/` in the synced root.
4. **The document ends mid-sentence** — §15.2's final bullet stops at "Assigned to Claud". One line to finish, but it's the *App Store compliance* action item, which shouldn't end ambiguously.
5. *(Minor)* §6.5's Porcupine wake-word and §5's framework stars are 2026-era claims that will want re-verification at v3; no action now.

---

## 4. Principles audit — are the locked principles actually delivered end to end?

- **Act-then-describe:** delivered and consistently reconciled (the v0.3→v0.4 sweep was thorough). The one hole was the undo-ring/correction contradiction (F-5, fixed). Remaining soft spot: the moderate-band transparency caveat ("…let me know if you meant something else") has two candidate composers (skill `format` output vs orchestrator-appended `Routing` caveat); Spec 04 §3.6 implies the orchestrator appends — fine, but Spec 07 should own the exact sentence assembly.
- **No silent failure:** the strongest-delivered principle — the three-surface paid degrade (G-28), the denial corpus, and the AttentionSurface are exemplary. Two quiet spots fixed: rate-limit-disguised-as-clarify (F-10) and the correction-after-window case (F-5). One remains open by design: a suppressed onWrite cascade at `maxCascadeDepth` is "logged to the repair surface" — good — but nothing tells the *automation author* their automation silently stopped cascading; acceptable for v1.
- **Code over AI:** *strengthened* by the NO-GO — the hot path now has no generative model at all. The audit caught only the stale §6.2 consolidation-pass reference (fixed).
- **Capabilities are data:** delivered for records; the cracks were the meta-operations masquerading as skills (F-6, fixed by naming the boundary) — the principle is *better* served by an honest "these three things are registry code" than by pretending the DSL covers them.
- **AI authors, code executes:** validated structurally by measurement (7/7 simple; complex needs pinned Opus + structured output + retry — G-29, properly absorbed into Spec 02 §6.3). The safety pivot (G-30 → §7.6 three-layer defense) is genuinely well absorbed — Layer 1's framing-not-topic precision note is exactly right and the false-positive risk is honestly stated.

---

## 5. Matters of taste (recorded, not acted on)

- Spec 03 keeps superseded sections in the body with amendments at the end; I added banners rather than restructuring. A future editorial pass could inline §7.3 into §3/§4 and demote the old design to an appendix — cleaner, but churny to do mid-corpus.
- The θ/τ threshold menagerie (three axes, nine named values) is more machinery than a v1 with no tuning data can exercise; the specs already say "defaults equal, tune later," which is the right hedge, so I left it.
- `dangerLevel: "caution"` has no defined behavioral consequence anywhere (safe and destructive both do; caution gates nothing). Either give it a meaning or drop it — deferred as taste.
- The traces' `create-task` uses `format_date(…, 'EEEE')` for a due-date label — wrong for dates beyond a week out ("Thursday" three weeks hence). Trace-level; the canonical idiom in Spec 02 §9.1 doesn't repeat the mistake.

---

## 6. Edit manifest (for diff review)

| File | Edits |
|---|---|
| `01-meta-schema-type-system.md` | header dep v0.10; §4.1 example de-retired `confirmationTemplate`; §4.2 nluHints row; §5.3 non-destructive automation invariant; §6.2 consolidation de-localmodel; §12.3 journal → device-local (G-37) |
| `02-skill-dsl.md` | §3.3 stale Spec01§10 ref; §3.6 null-filter rule; §9.2 meta-operation boundary note (`instantiate-template`, `search-records`, automation edits); §9.2 `recall-contact-fact` + `query-last-interaction` skill fixes; footnote alignment |
| `03-nlu-intent.md` | `retrieval` routingSource (§2.1/§2.5/§2.6); `foresight` in §2.2a; SUPERSEDED banners (§3.4, §3.5, §4.1 Axis-2, §4.3); §3.5 rate-limit honesty; §5.1 corpus-sync hazard (G-36); §7.3.3 type-name alignment; §7.3.4 measurement gate (G-38) |
| `04-architecture.md` | §3.6 `PreActionConfirmKind` rename + `SelectCandidate.candidateId`; §3.9 automation-config meta-operation; §3.11 undo ring ≥ 5 + correction degrade; §4.1 isolate table + §4.2 pipeline post-NO-GO; §5.1/§5.5 ref fixes |
| `05-functional.md` | §3.2 retrieval-semantics note; §3.7 full seed list; §3.8 count + foresight; §9 fact-model alignment; §11 journal device-local + per-session consent; §15 fire-time generation + freshness note |
| `05b-gap-register.md` | G-34…G-38 rows; Fable-review status line |
| `05c-fable-review.md` | this report (new) |

Nothing outside the corpus was touched. All edits are uncommitted.
