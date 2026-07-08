# Spec 11 — Feedback & Diagnostics

**Status:** v0.1 — July 2026 (first full draft. Unusually for this series, part of the machinery already exists in code — the per-turn **turnlog** (`v0/lib/session.dart`, `v0/lib/turnlog.dart`) and the timestamped **AppLog** (`app/lib/app_log.dart`, `app/lib/main.dart`) are live dogfood instruments. This spec formalizes what they collect, draws the redaction boundary between what stays local and what may ever be submitted, and designs the two outbound channels of research §14. Decisions recorded in §10.)
**Depends on:** research §12 item 11 + §14 (the mandate); Spec 03 — NLU/Intent (§2.5 `routingSource`, §2.6/§5 corrections corpus, §7.3 routing amendments); Spec 04 — Architecture (§3.5 `ClaudeClient`/`CloudError`, §3.12 `AttentionSurface`, §5 sealed error taxonomy, §7.1 device-local vs synced stores); Spec 02 — Skill DSL (§6 authoring seam, used by the area-label decision D6)
**Blocks:** release-candidate hardening (research §11.5 — "the diagnostics and feedback loop runs continuously from v1 and gates the first shared build"); informs the unwritten Spec 08 (AI Cost & Privacy) and Spec 10 (Security & Privacy threat model)

---

## 0. Purpose & Scope

Plenara must improve from real-world use without compromising the privacy that makes it trustworthy (research §14). This spec covers the whole diagnostic-and-feedback surface, in four parts:

1. **The local instruments** — the per-turn turnlog and the boot/turn AppLog that already exist in v0. These are rich, content-bearing, and never leave the device. They exist so a failed run is diagnosed *from the log*, not by lengthy retries — a hard project requirement (see §2.2).
2. **The data classification and redaction boundary** — the single rule set that decides what any *outbound* payload may contain (§3). This is the load-bearing section.
3. **The functional-gap report** (research §14.1) — when the app can't do something the user asked, it captures the *shape* of the failure (which layer fell short, and why) without the words the user said or the data involved, and lets the user submit it (§4).
4. **The diagnostic-log submission** (research §14.2) — a redacted, code-level trace a user can attach when reporting a serious failure (§5) — plus the guarantees testing (§6), retention (§7), the relationship to the corrections corpus (§8), and the UX surfaces (§9).

It does **not** cover: what leaves the device inside *model calls* (prompt payloads, BYOK consent — Spec 08's mandate; this spec owns only the feedback/diagnostic channels); usage analytics or A/B telemetry (**none exist and none are planned** — Plenara has no backend to receive them, research §15.1); or crash-reporting SaaS integration (declined for the same reason). There is deliberately no third category of "anonymous usage stats": the two channels here are the *only* outbound data paths outside the user's own model calls.

---

## 1. Governing Principles

**P11.1 — Everything is local by default; there is no telemetry endpoint.** The instruments write only to the user's own machine: the turnlog to the data folder (`StorageRepository.logTurn` → `<dataDir>/turnlog.jsonl`, `v0/lib/storage_repository.dart`), the AppLog to the OS temp folder (`%TEMP%/plenara-logs/`, `app/lib/app_log.dart`). No code path in the logging layer opens a socket. Submission, when the user chooses it, goes through the user's *own* mail client / OS share sheet (§4.3) — Plenara operates no server, consistent with the no-backend BYOK posture (research §15.1).

**P11.2 — Two zones, one boundary.** The **local zone** may hold user content, because real diagnosis needs it (you cannot debug a misroute without the utterance that misrouted). The **outbound zone** may hold *no PII and no user content, ever* (research §14.3). The boundary is enforced *structurally* — outbound payloads are built from typed structures whose fields can only hold enums, shipped-inventory ids, hashes, numbers, and shape descriptors — never by scrubbing free text after the fact (§3.3).

**P11.3 — Explicit, reviewable consent; the manifest is the payload.** Nothing is transmitted silently; both channels are off until the user chooses to send (research §14.3). Before anything is sent the user sees the *exact* payload rendered in plain English (§4.3, §5.2) — not a summary that could diverge from what ships. What you review is what is sent.

**P11.4 — Diagnose from the log, not by retrying.** A dogfood or beta failure must be attributable from the files on disk alone: the AppLog captures boot, every init phase, every turn, and every uncaught error, flushed line-by-line so even a hard hang leaves the last event on disk (`app/lib/app_log.dart`; `runZonedGuarded` + `FlutterError.onError` in `app/lib/main.dart`). The log path is printed to stdout at launch and shown in the app greeting so it is one file away. This was a hard requirement set by Luis during v0 bring-up and is now a spec-level invariant: **every layer transition, error, and turn outcome is reconstructable post-hoc.**

**P11.5 — The instruments never break the product (P2.8 applied to itself).** A logging failure is swallowed, never thrown into a turn (`AppLog.log` catches all IO errors; the turnlog append sits after the turn's catch-all in `Session.handle`). No silent failure means the *user's request* never fails silently — it does not mean the telemetry gets to take the turn down with it.

**P11.6 — Feedback measures the make-or-break metrics.** The instrument exists to answer the questions Spec 03 declared decisive: the clarify rate ("how often the app failed to act" — `v0/lib/turnlog.dart` names it the make-or-break metric), the correction rate, cloud health, and the corpus learning *curve* (Spec 03 §7.3.4: the ratchet's rate, not point accuracy, is what delivers the "rarely asks" promise). The functional-gap channel (§4) is the same measurement extended beyond one dogfooding device — the runtime sibling of the design-time gap register (`05b-gap-register.md`).

---

## 2. The Local Instruments (what exists today)

### 2.1 The turnlog — `<deviceDir>/turnlog.jsonl` (device-local; formerly `<dataDir>` — relocated, commit `d956390`)

One JSON line is appended per turn by `Session.handle` (`v0/lib/session.dart`), via `StorageRepository.logTurn`. The v0 field set, verbatim from code:

| field | type | presence | content class (§3) |
|---|---|---|---|
| `at` | ISO-8601 timestamp | always | F |
| `ms` | turn latency, int | always | F |
| `utterance` | the user's exact words | always | **C** |
| `source` | how the turn resolved: `corpus \| cloud \| correction \| undo \| help \| authored \| clarify \| out-of-domain \| error` | always | F |
| `skill` | dispatched skillId | when dispatched | F (built-in) / **Q** (authored) |
| `template` | the corpus template matched | corpus routes | **Q** (normalized, but derived from user phrasing) |
| `slots` | the slot values dispatched into the skill | when present | **C** |
| `cloud` | cloud health this turn: `ok` or a `CloudErrorKind` name (`noKey \| offline \| timeout \| badKey \| rateLimited \| serverError \| malformed` — the canonical sealed set, owned by Spec 04 §5.1; shipped in `v0/lib/claude.dart`) | cloud-consulting turns | F |
| `writes` | record ops this turn: `{op, id, typeId}` | writing turns | F (opaque ids) / **Q** (authored typeIds) |
| `response` | assistant reply, capped at 240 chars | always | **C** |
| `error` | exception type + message + stack, error path only — never shown to the user | error turns | **C** (messages/stacks can embed values) |

The reporting tool is `v0/bin/turnlog_report.dart`: a summary view (source mix, cloud health, top skills, and the clarify rate), `--errors` (full trace of every failed/clarify/OOD turn — the `isTroubleTurn` predicate in `v0/lib/turnlog.dart`), and `--trace N`. The summary aggregation (`summarizeTurns`/`formatSummary`) is the prototype of the submittable aggregate metrics in §8.

**Continuity with Spec 03.** `source` is the v0 rendering of Spec 03 §2.5's `routingSource`; when the v1 router lands, the turnlog records the full closed enum (`corpus_hit`, `retrieval`, `cloud_model`, `rule_match`, `anaphora`) plus the retrieval margin — all Class F, all gap-report-eligible.

### 2.2 The AppLog — `%TEMP%/plenara-logs/plenara-<timestamp>.log`

A timestamped plain-text diagnostic log opened at boot (`app/lib/app_log.dart`), one file per run (newest file = latest run), each line flushed immediately. It captures, per `app/lib/main.dart`:

- **Boot**: `boot: main() starting`, and the log path printed to stdout and repeated in the app greeting — so a failed manual test is one file away (P11.4).
- **Every `Session.init` phase** with elapsed ms (the `onPhase` callback, `v0/lib/session.dart §init`): defs loaded, skills validated, retrieval index built or skipped, reminders reconciled. A startup *hang* therefore shows the last phase that began (the design reason the retrieval-index phase logs *before* it starts — it can hang on a down embed server).
- **Every turn**: the utterance (`turn: "$t"`) and a 140-char response prefix — both Class C, local only.
- **Every uncaught error**: `FlutterError.onError` and the `runZonedGuarded` handler write the full exception + stack.

The AppLog is device-local by construction (OS temp folder, never the synced data folder) and is the *hang/crash* instrument, complementing the turnlog's *turn-outcome* instrument: the turnlog can only record a turn that completed its `handle` call; the AppLog catches the ones that never returned.

### 2.3 The delta between today's instruments and the outbound promise

Both instruments **do contain user content locally** — utterances, slot values, responses, raw exception text. That is deliberate and stays (D1): research §14.2's "engineered from the start to hold no PII" is hereby resolved to apply to the **submitted artifact**, not the local file — a content-free local log would defeat P11.4 (you cannot post-debug a misroute you cannot see). The consequence is absolute: **neither file is ever submitted as-is, and no submission path may read them as payload source** — outbound payloads are *derived* through the §3 boundary (gap records at capture time, §4.2; the diagnostic bundle at compose time, §5.1).

One placement correction (D9) — **✅ LANDED (commit `d956390`)**: the turnlog formerly lived in `<dataDir>` — the user's *synced* folder — which was fine for one dogfooding device but wrong at two (interleaved appends from two devices are a sync-conflict machine, and telemetry is per-device by nature). It now lives in the device-local `deviceDir` (`~/.plenara`), injected by the app and off the synced folder (same mechanism moved the HLC deviceId — Spec 06 §4.3; the v1 packaging target remains app-support, alongside the execution journal, Spec 04 §7.1; precedent `G-36`). Nothing about its content changed; rotation (D12) is still pending.

---

## 3. Data Classification & the Redaction Boundary

### 3.1 The four classes

Every value the system might log falls into exactly one class:

- **Class S — secrets.** The Anthropic API key and anything from `~/.plenara/config.json`. Never logged **anywhere**, local or outbound. A cloud auth failure logs `badKey` + HTTP status (`v0/lib/claude.dart` does exactly this), never the credential. Stricter than C: not even the local zone may hold it.
- **Class C — user content.** Utterance text, slot values, record field values, response text, journal/free-text of any kind, contact names, exception *messages* and any stack line that could interpolate a value, user-typed anything. Never leaves the device. Lives only in the local zone.
- **Class Q — user-shaped metadata.** Data that is structurally metadata but carries user-chosen vocabulary: authored typeIds/skillIds and their displayNames (`water_intake` tells you what the user tracks), corpus templates (normalized, but the fixed words are the user's phrasing — and Spec 03 §5.4's own rule is slot *shapes*, never slot values), `examplePhrases`, file paths containing the username. Outbound **only in generalized form**: an opaque hash plus a closed-vocabulary area label (§3.2).
- **Class F — functional facts.** The closed enums (`source`/`routingSource`, `CloudErrorKind`, the Spec 04 §5.1 sealed error *kinds*), **built-in** skill/type/template ids (they ship in the binary — they describe Plenara, not the user), timings, counts, confidence/margin numbers, op indices, schema/app versions, OS + platform, boolean flags, opaque record ids (random ids carry nothing), and **shape descriptors** of redacted values — `string[12]`, `number`, `date` (research §14.2). Freely includable outbound.

### 3.2 Generalizing Class Q: the hash + area label

Research §14.1's example payload reads "could not route a request in the **'nutrition' area**" — the *domain* is shareable; the user's own words for it are not. The mechanism (D6):

- An authored capability's outbound identity is `authored:<hash8>` — a stable 8-hex truncated hash of its id, salted per-install. Stable so repeated gap reports about the same capability correlate; salted so two users' `water_intake` trackers do not.
- At authoring time, the same Claude call that authors the type/skill (Spec 02 §6 — Claude is already in the loop and already sees the request, under the user's own key) also assigns one **area label from a closed, shipped vocabulary** of ~20 domains (`health`, `nutrition`, `fitness`, `relationships`, `finance`, `home`, `work`, `travel`, …, `other` — final list Q1). The label is stored in the definition file and is the only human-readable clue that ever leaves. A route-*miss* (nothing authored, nothing matched) has no label and reports `area: unknown` — plus the built-in candidates retrieval offered, which is often diagnosis enough.
- Corpus templates never leave in any form; only their count and hit-rates do (§8).

### 3.3 Structural enforcement, not scrubbing

The outbound boundary is a **typed payload builder**, not a filter. `GapRecord` and `DiagBundle` (§4.2, §5.1) are structs whose string-typed fields are constrained by construction: every string is (a) a member of a shipped closed enum, (b) a built-in inventory id — validated against the registry at build time, (c) an `authored:<hash8>` form, (d) a closed-vocabulary area label, or (e) a shape descriptor matching `^(string\[\d+\]|number|int|date|datetime|bool|list\[\d+\])$`. There is deliberately **no field that can hold an arbitrary string**, so there is nothing to scrub and no denylist to get wrong. A regex/denylist scrubber over free text is explicitly rejected (D3) — it fails open; the allowlist fails closed. No code path copies a turnlog or AppLog line into a payload (§2.3).

The one free-text exception: the user may *type* an optional "what were you trying to do" note into a gap report (§4.3). That is the user's own deliberate disclosure, composed by them in the email body — it is never auto-populated, and it lives outside the structured payload, visibly.

---

## 4. The Functional-Gap Report (research §14.1)

### 4.1 What counts as a gap

A gap is recorded when the app *fell short of acting on a request*, one record per triggering turn. The trigger set, mapped to existing signals (`isTroubleTurn`, `v0/lib/turnlog.dart`, extended):

| `kind` | trigger | today's signal |
|---|---|---|
| `route_miss` | no capability matched; the turn ended in clarification | `source: clarify` |
| `out_of_domain` | OOD detection fired (Spec 03 §7.2) | `source: out-of-domain` |
| `slot_dead_end` | the `ProvideSlot` loop (Spec 03 §6.3) was abandoned without dispatch | pending-fill dropped |
| `authoring_fail` | authoring validation failed or was declined (Spec 04 §3.7 `AuthoringError`) | authoring path |
| `dsl_gap` | authoring succeeded at understanding but the primitive vocabulary could not express the behavior (Spec 02) | authoring path |
| `runtime_error` | an exception escaped to the catch-all | `source: error` |
| `cloud_fail` | a cloud-dependent turn degraded (Spec 04 §6.2) | `cloud:` ≠ `ok` |

This is the **runtime gap register** — the production sibling of the design-time register in `05b-gap-register.md`, and it feeds the same decision: where to extend the primitive vocabulary, the templates, or the routing (research §14.1).

### 4.2 The gap record — redact-at-capture

Gap records are written to the device-local diagnostics store (a `gaps.jsonl` ring, cap 200 — §7) **already in outbound form**: the record *never* holds Class C content, even locally (D2). Submission is therefore a copy, not a transformation — there is no "redaction step" that could be skipped or buggy at send time. For *local* diagnosis, the record carries the turn timestamp, which joins it to the rich local turnlog on this device; off-device the pointer is meaningless.

```json
{
  "gapId": "g-01J9ZK…",
  "at": "2026-07-07",                       // coarsened to the day at capture
  "turnRef": "2026-07-07T09:14:22.184",     // local join key into turnlog; useless off-device
  "kind": "route_miss",
  "layer": "nlu",                            // nlu | interpreter | authoring | cloud | storage
  "source": "clarify",                       // the Spec 03 §2.5 routingSource / v0 source enum
  "area": "unknown",                         // closed vocab (§3.2) or "unknown"
  "candidates": [                            // what retrieval offered, with margins
    {"skillId": "create-task", "score": 0.41},
    {"skillId": "set-reminder", "score": 0.39},
    {"skillId": "authored:9f3a2c1e", "score": 0.22}
  ],
  "margin": 0.02,
  "utteranceShape": "string[38], 8 words",   // shape descriptor, never the words
  "cloud": "offline",                        // present iff the cloud was consulted / needed
  "errorKind": null,                         // sealed-error kind name on error paths
  "app": {"version": "1.0.3", "platform": "windows"},
  "inventory": {"types": 9, "skills": 25, "authored": 3, "corpusEntries": 412}
}
```

Every field passes the §3.3 builder; `utteranceShape` is the research §14.2 shape idiom applied to the one thing a route-miss most tempts you to log.

### 4.3 The submission flow

1. **Initiation is always the user's** — "report that" right after a failed turn (a system meta-intent, Spec 03 §2.3), or the settings surface, which shows the accumulated gap list ("14 gaps recorded"). Nothing auto-sends, nothing nags (D7): after a trouble turn the app may append, at most once per session, one calm line — "If this keeps happening, say 'report that' and I'll draft a privacy-safe report you can review."
2. **The app composes an email** (research §14.1: "an email (or equivalent) is composed and shown for review") via `mailto:`/OS share sheet — the user's own mail client, no Plenara endpoint (D5, P11.1). The body is the **manifest**: each gap rendered in one plain-English sentence, then the exact JSON below it, nothing hidden:

   > **What this contains:** which layers fell short and how confident the routing was — never your words or your data. Values appear only as types and sizes, like `string[38]`.
   >
   > • Jul 7 — I couldn't route a request (8 words) in an unknown area to any capability; best guesses were *create-task* (0.41) and *set-reminder* (0.39), margin 0.02, so I asked instead. I was offline.
   > • Jul 6 — a new capability in the *nutrition* area (`authored:9f3a2c1e`) failed validation twice before activating.
   >
   > *(full JSON payload follows, verbatim)*

3. **The user reviews, deletes any lines they like, optionally types context, and hits send in their own client.** The email draft is the consent surface; abandoning the draft sends nothing. Submitted gaps are marked sent locally so they are not re-offered.

The English rendering and the JSON are generated from the *same* `GapRecord` structs in the same pass — the manifest is the payload (P11.3, D4).

---

## 5. The Diagnostic-Log Submission (research §14.2)

### 5.1 The bundle is derived, never the raw file

For a serious failure ("it hung at startup", "it wrote the wrong record and undo failed"), gap records are too coarse — this channel ships a code-level trace: call path, layer transitions, init phases, interpreter step indices, error states, timings. The **diagnostic bundle** is composed *at submission time* from the local AppLog + turnlog (redact-at-compose, D2's counterpart), through the same §3.3 builder:

- **Kept verbatim (Class F):** init phase lines and their elapsed ms; turn skeletons (`at`, `ms`, `source`, built-in `skill`, `cloud`, op indices); `writes` with opaque record ids and built-in typeIds; sealed error *kinds*; `package:plenara` stack frames (code paths, not content — file:line only); app/OS versions.
- **Shape-redacted (Class C → descriptor):** `utterance` → `string[34], 7 words`; each slot → its name*-as-declared-in-the-shipped-skill* (or `slot[i]` for authored skills) + type descriptor (`distanceKm: number`, `note: string[52]`); `response` → `string[128]`.
- **Dropped:** exception *message* text (it can interpolate values — only the exception **type** and the sealed-error kind survive; Q2 tracks whitelisting known-constant messages), non-`plenara` stack frames beyond the top library frame, any path containing the home directory, corpus templates.
- **Generalized (Class Q):** authored ids → `authored:<hash8>` + area label (§3.2).

The v0 `formatTurnTrace` (`v0/lib/turnlog.dart`) is the *local* rendering of a turn — utterance and all; the bundle's turn rendering is the same skeleton with the Class C positions replaced by descriptors. A hang bundle is the AppLog's phase skeleton — which is already nearly pure Class F, by design (§2.2).

### 5.2 The manifest

Same contract as §4.3: the bundle is rendered readably, prefixed by a fixed plain-English statement of the redaction guarantees —

> **What this contains:** a technical trace of what Plenara's code did — which steps ran, how long they took, and what errors occurred. **What it cannot contain:** anything you said or stored. Your words and values appear only as types and sizes (`string[12]`, `date`); your own trackers appear only as anonymous codes (`authored:9f3a2c1e`) with a broad area label.

— shown scrollably before the user sends it from their own client. The rendered form *is* the payload (D4). A power-user "attach the raw log instead" option is **declined for v1** (D11): it re-opens the exact leak the channel is engineered to close, and a user who truly wants to hand over the raw file can find it — the path is printed at every launch.

---

## 6. Testing the Guarantee

Research §14.3 is explicit: no-PII/no-content "is a design constraint to be tested, not merely a promise." The test battery (lands in the Spec 09 CI suite):

1. **Canary end-to-end.** Synthetic sessions whose utterances, slot values, record values, contact names, config values, and exception messages all embed unique canary strings (`CANARY-a7f3-…`). Drive every gap `kind` and every bundle path; assert **zero canary bytes** in any `GapRecord`, any `DiagBundle`, and both rendered manifests. The API-key canary additionally asserts absence from the *local* logs (Class S).
2. **Closed-vocabulary assertion.** Every string in every outbound payload must parse as one of the §3.3 forms; every id must be ∈ the shipped inventory ∪ `authored:<hash8>`. Fails closed on any new field added without classification.
3. **Error-path fuzz.** Throw exceptions whose messages carry canaries from inside the interpreter, storage, and cloud layers; assert the bundle carries type + kind only.
4. **Manifest-equals-payload.** Render → parse-back → deep-equal against the struct, so the reviewed text can never diverge from the sent bytes.
5. **A manual red-team pass per release** — same spirit as the primitive-vocabulary red-team (research §13.1): task a model with extracting anything personal from a corpus of real (own-data) generated payloads.

---

## 7. Retention & Hygiene

All diagnostic state is plain files, plainly named, trivially deletable — the user's machine, the user's files.

- **AppLog:** one file per run in `%TEMP%/plenara-logs/` (v0 relies on OS temp cleanup); v1 prunes files older than 14 days at boot. Mobile targets need an app-support location + in-app viewer (Q3 — `%TEMP%`+stdout is desktop-shaped).
- **turnlog:** unbounded append today; already device-local (D9 landed, commit `d956390`); v1 rolls it into monthly segments with a total cap. It is the input to the make-or-break metrics (§8), so it is kept generously — but locally.
- **Gap register:** a 200-entry ring; entries clear on submit or explicit dismiss.
- **Uninstall/reset:** deleting the device-local folders (`~/.plenara` + app-support + temp logs) removes every instrument; nothing diagnostic hides in the synced data folder now that D9 has landed (commit `d956390`).

---

## 8. Relationship to the Corrections Corpus (Spec 03)

The corrections corpus is itself a feedback loop — but a **local, per-user** one: `recordCorrection`/`recordConfirmation` (Spec 03 §2.6, §5.2) teach *this* user's phrasings to *this* install, and the corpus never leaves the device in any channel (its templates are Class Q; its slot recipes are shapes by Spec 03 §5.4's own rule). What *may* travel, inside a gap report, are its **aggregate metrics** — pure Class F counts that contextualize a report exactly the way `formatSummary` (`v0/lib/turnlog.dart`) already renders them locally: total turns, clarify rate, correction rate, source mix, corpus size and hit rate, the learning-curve deltas Spec 03 §7.3.4 declared make-or-break. "Clarify rate 12% over 340 turns, down from 19% last month" is a functional fact about the *software*; per-template hit lists are the user's vocabulary and stay home. Top-skill breakdowns are included for built-in skills only; authored skills fold into `authored:*` totals.

This is the division of labor: the **corpus** makes one install better; the **gap channel** makes *Plenara* better. The first is automatic and private; the second is manual and consented.

---

## 9. Surfaces

- **"Report that"** — a system meta-intent (extends Spec 03 §2.3's closed rule-matched set), scoped to the most recent trouble turn; composes a single-gap report (§4.3).
- **Settings → Feedback & Diagnostics** — the gap list with per-item review/dismiss, "send gap report" (all unsent), and "send diagnostic trace" (§5); shows the local log locations and a one-tap "delete all diagnostics."
- **The post-failure line** — one calm, rate-limited sentence after a trouble turn (§4.3 step 1); never a modal, never repeated within a session (P2.3's calm posture; the `AttentionSurface` of Spec 04 §3.12 is *not* used for this — a gap is not an inconsistency needing repair).
- **The greeting/log-path line** — retained from v0 (`app/lib/main.dart`): the diagnostics-log path stays visible at startup and in init-failure messages. It has already paid for itself in dogfood.

---

## 10. Decision Record

### Resolved

- **D1 — Two-zone model.** Local logs stay rich and content-bearing (utterances, slots, stacks) because post-hoc diagnosability is a hard requirement (P11.4); outbound payloads are content-free **by construction**. This *resolves* research §14.2's "engineered from the start to hold no PII" as governing the **submitted artifact**, not the local file — the sentence was ambiguous; this is the reconciliation. Realized today: `session.dart` turnlog + `app_log.dart` both content-bearing, both local-only.
- **D2 — Redact-at-capture for gap records; redact-at-compose for diagnostic bundles.** Gap records hold zero content even at rest (submission = copy, no transform to get wrong), joined to the local turnlog by timestamp for on-device diagnosis. The bundle is derived from the local logs only at composition, through the same builder.
- **D3 — Structural allowlist, never scrubbing.** Outbound payloads are typed structs whose string fields admit only closed enums, shipped ids, `authored:<hash8>`, area labels, and shape descriptors. Regex/denylist redaction over free text is rejected — it fails open.
- **D4 — The manifest is the payload.** The plain-English rendering and the JSON are two views of one struct, generated in one pass and tested for round-trip equality (§6.4). No separate summary that could diverge.
- **D5 — Transport is the user's own mail client / share sheet.** No Plenara telemetry endpoint, consistent with no-backend BYOK (research §15.1). Abandoning the draft sends nothing.
- **D6 — Authored capabilities travel as `authored:<hash8>` + a closed-vocabulary area label** assigned by the authoring Claude call (Spec 02 §6) and stored in the def — realizing research §14.1's "'nutrition' area" example without shipping user vocabulary. Route-misses report `area: unknown` + built-in candidates.
- **D7 — Opt-in, user-initiated only.** No background transmission, no auto-prompts beyond one rate-limited post-failure line. Channels are off until used (research §14.3).
- **D8 — The v0 instruments are formalized as-is.** The turnlog field set (§2.1, from `Session.handle`) and the AppLog boot/phase/turn/error trace (§2.2) are the specified local instruments; "diagnose from the log, not by retrying" is promoted from a dogfood convention to invariant P11.4.
- **D9 — The turnlog is device-local — ✅ LANDED (commit `d956390`):** it now lives in the app-injected `deviceDir` (`~/.plenara`; v1 packaging target remains app-support, next to the execution journal — Spec 04 §7.1; precedent `G-36`). v0's original `<dataDir>/turnlog.jsonl` placement was single-device-acceptable; per-device telemetry in a synced folder is a conflict machine and a needless exposure of Class C to the sync provider beyond what `G-37` already accepts — which is why this landed ahead of any second device.
- **D10 — The API key is Class S: never in any log, local or outbound.** Auth failures log `badKey`/HTTP status only (already true in `v0/lib/claude.dart`); enforced by the §6.1 canary battery.
- **D11 — No raw-log attachment option in v1.** The redacted bundle is the only submittable trace; the raw files remain reachable by hand for a user who insists.
- **D12 — Retention:** AppLog 14-day boot-time sweep; turnlog monthly segments under a cap; gap ring of 200, cleared on submit/dismiss; everything user-deletable as plain files.

### Open

- **Q1 — The area-label taxonomy.** The ~20-label closed vocabulary needs drafting, a slot in the Spec 02 §6 authoring prompt, and a rule for re-labeling on capability edit. **Owner: this spec (Spec 11)** — suite-sync ownership call (05f §3 item 4): the taxonomy is drafted here as a follow-up; Spec 02 §6 (prompt slot) and Spec 01 §4 (the def field) then take it up by amendment.
- **Q2 — Whitelisting sealed-error message constants.** Spec 04 §5.1 kinds travel; message *text* is dropped even when it is a code constant, because interpolation risk is hard to prove per-site. Revisit with a lint that certifies constant-only messages.
- **Q3 — Mobile AppLog location & viewer.** `%TEMP%` + stdout path-printing is desktop-shaped; iOS/Android need an app-support directory and an in-app log view to preserve P11.4 without a console.
- **Q4 — Diagnostic value of hashed authored ids.** If real gap reports about authored capabilities prove undebuggable behind `authored:<hash8>` + area, consider an *explicit, per-report* user option to name the capability — a deliberate disclosure, clearly marked in the manifest. Decide after the first live reports.
- **Q5 — Transport limits.** `mailto:` body-size limits vs. share-sheet attachments per platform; a bundle may need to ship as an attached `.json` with the manifest in the body.
- **Q6 — Sync-provider exposure of local Class C stores.** Post-D9, remaining Class C in the synced folder (records, journal, learned corpus) is the already-accepted `G-37` plaintext posture — but the threat model (Spec 10, unwritten) should re-examine it together with §8.7 at-rest encryption; this spec's stores will be encrypted-at-rest whenever that lands, for free (device-local app-support is already the journal's encrypted home per Spec 04 §7.1).
