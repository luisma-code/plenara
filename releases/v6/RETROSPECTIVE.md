# v6 — The Living Presence

**Release point:** `467e35f` — 2026-07-11 (HEAD; "chore(scripts): root-level launch/build/dogfood + machine-prep scripts")
**Runnable:** Windows GUI (.exe) with voice — engine unchanged from v5; this version's substance is design + packaging.
**Span:** `7f6a6c2` → `467e35f` (2026-07-11), 3 commits.

## What this version is

v6 is a design release: the moment Plenara decided what it wants to *look like*. The engine
and app binary are v5's (1,643 + 38 tests, unchanged); what's new is **Spec 15 — The Living
Presence**, the charter for the voice-first visual experience that will replace the chat
window as the primary interface, taken through two drafts and a live mockup in one day. It
ships with root-level operational scripts (`run.cmd`, `build.cmd`, `dogfood.cmd`,
`prep-machine.ps1`) that make the app launchable and installable on a fresh Windows box —
the first packaging gesture toward running Plenara somewhere other than the dev machine.

## The journey from v5

**The problem Spec 15 answers.** Every version since v1 has worn the same face: a Material
chat column. That was always scaffolding. The research doc's north star is a voice-first,
"sci-fi level helpful" companion, and Spec 07 had gestured at it — a Stage, a "listening orb"
— but as *chrome* around a text transcript. With the engine spec-complete (v3), dogfooded
(v4), and conversationally competent (v5), the presence became the highest-value unbuilt
thing. Spec 15 (Fable-authored, `7f6a6c2`) promotes the orb from chrome to **the primary
interface**: an ethereal entity whose motion, hue, and luminance express system state —
listening, thinking, difficulty, failure — with text materializing only when needed and full
caption parity when muted.

The architecture is disciplined where it would be easy to be hand-wavy: one pure
`PresenceDirector` emits a `PresenceFrame` vector; three render tiers consume it (T2 shader /
T1 painter / T0 still — T0 is the v1 ship target *and* the reduced-motion answer). Speech
sync is a cadence-envelope proxy anchored to Spec 12's SpeakEvents, because no realtime TTS
amplitude exists to key off. Difficulty is a five-grade operational ladder, always
dual-encoded; **failure gets quieter, not louder**. A yield ladder (field → parting → ember)
draws the seam with Spec 07's data views. Accessibility clamps — contrast calm-band, ≤2Hz
luminance, colorblind-safe, vestibular — live in the director, not the renderer, so no tier
can violate them. Like Spec 12 before it, it takes a top-level number rather than a lettered
companion slot, and reconciles with 07/12/04 through explicit suite-sync items instead of
editing other specs in place.

**The mockup redirect — v0.1 to v0.2 in a day.** A live mockup pass did what mockups are
for: it changed the design. The smoke-veil substrate lost to the **particle swarm** — "the
murmuration", 2–6k motes in one drawVertices pass with a shared flow field and core-cohesion
spring (`99047e2`). The veil is demoted to a documented alternate; because both substrates
consume the same PresenceFrame vector, the swap is a renderer re-pointing, not a
re-architecture — the abstraction earned its keep on day one. The mockup also failed
usefully: additive blending washed hues into an illegible white-out, and that failure is now
**release-gating** (aura underlay, density caps, floored ramp anchors — §4.3/§10/Q3).

v0.2's other addition is the spec's most charming and most fenced section: **§5A, the
symbolic glyph vocabulary**. The swarm may occasionally trace a line-figure — a check, a
smile, a heart — then release it. The governing rule is *apt-or-absent*: a todo never earns
a heart, the default is no glyph, and a sound-off appropriateness test gates every use.
Glyphs are data (a GlyphDef schema), frequency-capped (one per turn, ≥90s apart, ~8/day),
never the sole carrier of meaning, reduced-motion-safe, with a curated table of fifty
defined *by their Plenara occasion* rather than by shape. It reads as a spec written by
people who have seen delight curdle into kitsch and decided to legislate against it.

**And the ops scripts** (`467e35f`): launch/build/dogfood entry points at the repo root
instead of buried in the vendored toolchain, plus `prep-machine.ps1` — the Flutter Release
folder is self-contained, so preparing a novel Windows box reduces to ensuring the VC++ x64
runtime. Small, but it marks the transition from "runs on the dev box" toward "runs
anywhere", which is the same transition Spec 15 marks for the face of the app.

## What shipped

- Spec 15 v0.1: presence-as-primary-interface — PresenceDirector/PresenceFrame, three render
  tiers, state machine, difficulty ladder, yield ladder, muted-mode parity, accessibility
  clamps, suite-sync items X1–X8.
- Spec 15 v0.2: swarm substrate (veil demoted), §5A glyph vocabulary (50 glyphs,
  apt-or-absent, hard fences), hue-legibility made release-gating after the mockup white-out.
- Root scripts: run.cmd / build.cmd / dogfood.cmd / prep-machine.ps1.

## Known gaps at release

The presence is specified, not built — no PresenceDirector or swarm renderer exists in the
app yet; the chat window remains the shipped face. Spec 15's suite-sync items against 07/12/04
are recorded but not applied. All v5 engine gaps carry forward (model download-on-first-run,
asset bundling, MSIX, per-action batch slot-fill, at-rest encryption, CRDT merge engine, iOS).
Building T0/T1 of the presence is the obvious next arc.

## Toolchain / runnable note

Windows GUI (.exe) with voice, identical engine to v5; `run.cmd` builds and launches,
`prep-machine.ps1` readies a fresh box (VC++ runtime). Suitable for a GitHub Release binary —
functionally the same binary as v5, tagged here for the spec milestone and the packaging
scripts.
