# Plenara — Version Manifest

Version milestones reconstructed from the full 292-commit history (2026-06-07 → 2026-07-11).
Each row's commit is the **release point** — the last commit of that phase — intended to
become the git tag. Retrospectives live in `releases/vX/RETROSPECTIVE.md`. Newest last.

| version | name | date | commit | GUI? | one-line summary |
|---------|------|------|--------|------|------------------|
| v0 | The Box Demo | 2026-07-06 | `920a836` | no (console) | Research + specs 01–05, measured routing pivots, Phase-0 spikes, and the Dart walking skeleton: the whole design (route→resolve→execute→persist→describe, learning, authoring, undo, safety) running end to end in a console. |
| v1 | A Window on the Engine | 2026-07-06 | `717c5ca` | yes | First Flutter Windows .exe over a shared Session engine; record/replay cloud cassette; 1,004 hermetic tests; six-wave Fable review hardening (UUID ids, CRDT fidelity, never-throw cloud, update/delete ops). |
| v2 | The Daily Companion | 2026-07-07 | `8cfce8a` | yes | Dogfood-ready assistant: config + turnlog, reminders firing as real Windows toasts, the complete people loop + birthday nudges, ProvideSlot/disambiguation/aliases, typed CloudResult, first generative kinds, review-#2 P0/CRDT fixes. |
| v3 | Spec-Complete | 2026-07-08 | `3828ecb` | yes | Every Spec 04 component exists (AutomationRunner+cron, MigrationRunner, authoring offer→preview→activate, template library, denial floors); specs 06–13 written + reconciled; measured 22/60 conformance with ratchet; coverage/import-lint/precheck gate; data view + Settings. |
| v4 | First Contact | 2026-07-09 | `68a7c24` | yes | The play test: live BYOK cloud validation (+4 fake-hidden bugs fixed), guided onboarding, on-device voice (SAPI root-caused → sherpa → Whisper+VAD), content search + nutrition KB, corpus 190→640 templates, ~28 phrasing-gap batches, cost telemetry, Free/Paid toggle. |
| v5 | The Router Grows Up | 2026-07-10 | `1c06393` | yes | Cloud-router upgrade from real dogfooding: entity resolution (no duplicate contacts), multi-action routing, plans-vs-past, general dedup, full 33-finding Fable review fixed, and the self-improving corpus (cloud-suggested, round-trip-validated templates). |
| v6 | The Living Presence | 2026-07-11 | `467e35f` | yes | Spec 15 v0.1→v0.2: the voice-first presence (PresenceDirector/PresenceFrame, particle-swarm substrate, glyph vocabulary) chartered as the future primary interface, plus root run/build/dogfood/machine-prep scripts; engine unchanged from v5. |
| v7 | Off the Desktop | 2026-07-14 | `e2432a4` | yes | Platform move Windows→macOS with iPhone rechartered as the P1 target: Apple-Speech voice + live transcript, a P0/P1 render test-net (headless Picture/Image leak audit, static-shader lint, suspend-when-hidden, numeric render-and-measure invariants) that root-caused a per-frame `ui.Gradient` GPU leak and an idle-suspension RAM balloon, the guided "what can you do?" Tour v1, and the list-reply presence redesign. Engine unchanged from v6. |
| v8 | On the Phone, In Her Voice | 2026-07-14 | `(this commit)` | yes | First running on iPhone: on-device deploy (work-MDM cert-block diagnosed via pulled device logs and cleared; release-mode standalone sidesteps the debug-attach/Impeller pitfalls) and iOS path fixes (app-injected home dir, live-derived dataDir, Files-app-visible logs + a Share-diagnostics button). The voice-first experience made real: an iOS `.playback` audio session so Plena speaks in silent mode (like Siri), an in-app natural-voice picker (Enhanced/Premium), two-track `speakify` + voice-first captions (text only when muted), and topic-paced speech. The Tour became a *show* — a privacy opener, per-chapter glyphs, and a live colour-demo capstone (warm→cool AI shade, cost minimised + tracked in Settings). Glyph vocabulary expanded across everyday actions and redesigned via a render-and-review loop (Fable's bell fix; one-line flower + sun from Luis's references). |

## How the boundaries were chosen

Boundaries follow the product's real inflection points rather than calendar or commit volume:
each version ends where a distinct *kind* of product exists that did not before — the proven
console skeleton (v0), the first windowed+hardened build (v1), the first build fit to run on
real personal data with OS notifications (v2), the completion of the specified architecture
before dogfooding per Luis's build-to-spec-first directive (v3), the first live-cloud,
voice-driven, phrasing-hardened daily driver (v4), the conversationally competent cloud tier
with a closed learning loop (v5), and the designed pivot from chat window to presence at
HEAD (v6). Release points are the last commit of each phase — usually the handoff/docs commit
that closes its arc — so tags land on states the history itself declared stable (tests green,
state recorded).

Notes for tagging: v0/v1 share a date (2026-07-06) — the day spanned both milestones. v6's
release point is HEAD (`467e35f`, a scripts chore); the substantive tip of its arc is
`99047e2` (Spec 15 v0.2) if a content commit is preferred for the tag. v3's cut at `3828ecb`
places the first *live* cloud runs (`5d1c641` onward, same day) in v4, since going live is
that version's story; v2's cut at `8cfce8a` includes the first six spec-conformance items,
whose completion is narrated in v3.
