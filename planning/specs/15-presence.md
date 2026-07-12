# Spec 15 — The Living Presence

**Status:** Draft v0.3 — July 2026 (Fable 5). First full draft (v0.1, early July) of the voice-first visual experience: the presence as the app's primary surface — the substrate, the presence state machine, the signal→visual expressive mapping, the disembodied personality rules, text materialization and yielding choreography, muted-mode visuals, the presence motion tokens, render tiers and perf budgets, and the accessibility constraints a permanently-moving surface must satisfy.
**v0.2 (2026-07-11):** after the first live mockup pass, the substrate is re-pointed from the smoke veil to the **coherent particle swarm** — "the murmuration" (§2.1; D2 rewritten; the veil becomes the documented alternate, §2.2 — a renderer re-pointing, not a re-architecture: §2.4's vector drives both). New: **§5A — the symbolic glyph vocabulary**, the swarm's rare figurative register, with a fifty-glyph curated table (D13). Recorded as release-gating: the **additive-blending hue-legibility constraint** — the mockup's white-out failure must never recur (§4.3, §10 item 7, Q3 extended).
**v0.3 (2026-07-11):** trued against the **first shipped implementation** (`app/lib/plena.dart`, `app/lib/glyphs.dart`, `app/lib/main.dart` — the Windows dogfood build, which shipped the *animated* swarm directly rather than waiting for the v3 rung, §9.3). The entity is named — **Plena** (§0). Glyph formation is re-specified from in-place mote assignment to the **comet-trail** mechanic the build chose: Plena flies the figure's path herself, shedding a faint semi-transparent tail that holds the shape and then rejoins her (§5A.4; D13 amended). Occasion→glyph selection ships as code (§5A.1). The presence-primary home lands (§6.3–§6.4, §7): Plena plus a mute control and nothing else, tap-anywhere to speak, corner-hover for list content, the **ephemeral current exchange** (no scrollback — the v0 chat feed is deleted), and the muted input bar rising from below. Also recorded: the aura underlay is the *selected* §4.3 mechanism (the fireball core, now designed rather than accidental); true trail persistence via a capped ping-pong buffer (§2.1, §9.2); the dogfood tuning sheet (§5.4).
**A note on numbering:** this document is intimately a companion to Spec 07 — it deepens §2.1's Stage and §8.4's orb from "chrome" into the primary interface — and a lettered `07a` was considered. Rejected: in this suite, lettered companions (05a–05f) are *working artifacts* — trace rigs, gap registers, review logs — not chartered normative specs, and a normative spec takes a top-level number even when it exists to complete another (precedent: Spec 12's chartering note, which took slot 12 rather than `06a`). Slots 13 and 14 are occupied; this is **Spec 15**. Everything it extends or supersedes in Spec 07 is recorded explicitly as suite-sync items in §11, the way Spec 12 records its retargets — this spec edits no other file.
**Depends on:** Research doc (§2.1–2.3, §6.2, §11.3–11.5, §15.1); Spec 04 — Architecture (§2.2 layer rules, §3.6 `TurnEvent` stream + `DispatchOrchestrator`, §3.12 `AttentionSurface`, §4.3 barge-in, §4.7 detached ops, §5.2 error surfaces); Spec 05 — Functional (§3 act-then-describe, §13 offline/subtitle/quiet-overlay behavior); Spec 07 — UI & Design-Language (§2.1 the Stage, §6 turn cards, §7 quiet overlay & subtitles, §8 motion tokens & the orb, §9 typography/shape/color, §10 staging); Spec 08 — AI Cost & Privacy (§3.1 cloud latency, §5.2 residual routing — the "difficulty" signals of §4.2); Spec 12 — Voice (§2.1 `micLevel` + `SpeakEvent`, §4 transcript semantics, §6.3 muted `SpeakEvent`s, §7.2 latency budgets, §9 voice errors)
**Blocks:** Spec 09 — Test (the `PresenceDirector` property tests and golden-frame tier of §9.2 here); the v3 organic rung (Spec 07 §10 step 4 — this spec is that rung's normative content for the Stage); Spec 07's Q3 (wake-word "armed" reading — co-owned here as Q4)

---

## 0. Purpose & Scope

Spec 07 built the design language for Plenara's *views* — archetypes, turn cards, typography — and gave the voice loop a single piece of persistent chrome: the listening orb (§8.4), "an organic, softly irregular form" with four states. That was the seed. This spec grows the seed into the product owner's actual vision: **the interface is not an app that contains an assistant indicator — it is an entity you are talking with.** *(v0.3)* That entity has a name: **Plena** — she introduces herself by it, the code names her by it (`plena.dart`), and this spec now does too. The substrate keeps its working name, *the murmuration*; "the presence" remains the neutral term of art. The screen at rest *is* the presence: an ethereal, quietly alive field that fluctuates with its speech, shifts hue with effort, has a disembodied visual personality, and — rarely, at moments that earn it — traces a symbolic figure (§5A). Text is not the medium; text *materializes* when needed — read-back, lists, narration aids, captions — and dissolves back into the field. When muted, the presence keeps speaking visually while captions carry the words.

This document specifies:

1. **The substrate** — the one normative visual medium the presence is made of, its named alternates and their tradeoffs, and the Flutter rendering strategy with a frame budget (§2)
2. **The presence state machine** — the base states (aligned exactly to Spec 12's vocabulary), the modifiers layered over them, and what the substrate *does* in each (§3)
3. **The expressive mapping** — the concrete table from system signals (TurnEvents, mic level, SpeakEvents, tier/latency class, attention state) to the presence's parameter vector (§4)
4. **The disembodied personality** — the rules that make the presence read as alive-but-calm without a face, and the ban on anthropomorphic kitsch (§5) — and the **symbolic glyph vocabulary**, the presence's rare figurative register and its fifty curated figures (§5A)
5. **Text materialization and yielding** — how text condenses out of the field and releases back into it, and the three yield levels by which the presence makes room for Spec 07's views without ever despawning (§6)
6. **Muted mode** — the visual contract when TTS is off: captions carry words, the presence still speaks (§7)
7. **The presence motion grammar** — extensions to Spec 07 §8's tokens, the breath-budget reconciliation, reduced-motion and photosensitivity constraints (§8)
8. **Render tiers, performance budgets, and staging** — how v1 ships functional-and-clean on the same skeleton, with the full organic field as the v3 rung (§9)
9. **Accessibility** as hard requirements: contrast over a live field, colorblind-safe difficulty encoding, screen-reader deference, vestibular and photosensitive safety (§10)

It does **not** cover: the view-archetype library and type→archetype mapping (Spec 07 §3–§5 owns those unchanged — when the presence yields to a data view, *what that view is* remains entirely Spec 07's); capture and transcript semantics (Spec 12 — this spec renders the states Spec 12 defines and never redefines them); turn sequencing, barge-in policy, or the write barrier (Spec 04 §4.3); when the app asks vs. acts (Spec 05 §3); subtitle *content* rules — always-on parity, two-slot discipline, length limits (Spec 07 §7.3 owns those; this spec owns only the choreography by which those slots' text appears and releases, §6.2); and TTS/STT engine behavior (Spec 12 §5–§6). Where this spec extends or supersedes Spec 07 — the orb, the Stage's steady state, the breath budget, the color system — the changes are enumerated as suite-sync items in §11, and until that pass lands, Spec 07's text stands as written.

---

## 1. Governing Principles

**P1 — The presence is the app, not a widget in it.** The steady state of the screen is the entity, quietly alive; everything else — cards, captions, views — is something the entity *does* or *makes room for*. Consequences: the Stage's visual hierarchy inverts from Spec 07 §2.1 (the field is the ground, the ambient cards are guests on it — suite-sync X1); there is no frame, panel, or chrome that "contains" the presence; and the presence never unmounts — on every surface, at every scroll depth, some form of it is on screen (§6.3).

**P2 — Driven by streams, never by queries (Spec 07 P5, tightened).** The presence is rendered from a single small value — the `PresenceFrame` parameter vector (§2.4) — computed by one pure component, the `PresenceDirector`, whose only inputs are: the sealed `TurnEvent` stream (Spec 04 §3.6), the `micLevel` and `SpeakEvent` projections (Spec 12 §2.1, surfaced through Business Logic view models per Spec 12 P2.5), the `AttentionSurface` count projection (Spec 04 §3.12), and the voice-availability state (Spec 12 §9). The renderer consumes frames; it holds no other reference. No shader, painter, or particle ever knows what a record, a registry, or a model is. This makes the presence's entire behavior a pure function `(state, signals, time) → PresenceFrame` — deterministic, golden-testable (Spec 09), and skinnable across render tiers (§9.1) without behavioral drift.

**P3 — One entity, continuous.** There is exactly one presence per install. It never duplicates, never despawns, never "closes." Navigation is the presence yielding, receding, or gathering (§6.3) — never the presence being replaced by a screen. Its personality seed (§5.4) is stable for the life of the install. Two presences on screen, or a presence that pops in and out, would break the fiction this whole spec exists to build.

**P4 — Expressive, never anthropomorphic.** The presence has no face, eyes, mouth, limbs, silhouette, or avatar form — ever, at any render tier, in any state. Its emotional vocabulary is entirely abstract: energy, coherence, tempo, hue, luminance, grain. This is a hard rule, not taste: a face invites social-presence expectations the system cannot honor (gaze, emotion reading, embarrassment), turns latency into "it's ignoring me," and ages into kitsch. The presence is weather, not a creature. *One bounded amendment (v0.2):* the presence may briefly **trace** a symbolic line-figure — a glyph (§5A) — including figures that quote facial affect (a smile arc beneath two dots). The body still has no face: a glyph is a drawing the presence makes and releases, never anatomy it possesses — it does not blink, track gaze, lip-sync, or persist. §5A.7 fences the exception; outside it, this rule is as absolute as ever.

**P5 — Quiet by default (Spec 07 P8, applied to a living thing).** Alive-but-calm means the idle amplitude budget is tiny and fiercely defended: at rest the field moves at breath scale (§3.1) and nothing more. The presence never performs, never fidgets, never reacts to pointer movement or scrolling, and spends its expressive range only when meaning changes. A presence that is always interesting is an app that is always tiring.

**P6 — Text materializes; it never intrudes.** Text appears only when it carries something voice alone cannot (read-back, lists, disambiguation candidates, captions, errors) — Spec 07's surfaces decide *when*; this spec makes their arrival feel like condensation, not like a dialog landing on top of a screensaver. And per Spec 07 §8.2 rule 4, materialized text never moves positionally: it condenses and dissolves *in place* (§6.1).

**P7 — No state is carried by hue alone.** Every presence state and every difficulty grade is legible with color vision deficiency, on a grayscale screen, and in the reduced-motion variant: hue is always paired with at least one of tempo, coherence, luminance, or grain (§4.3, §10.2). This is the accessibility corollary of the product vision's "hue changes with difficulty" — hue is the *poetry*, never the sole *information*.

**P8 — Beauty degrades gracefully.** The presence has three render tiers (§9.1) and an automatic demotion ladder driven by measured frame time and platform power state. Tier demotion changes *fidelity*, never *meaning*: the same `PresenceFrame` drives every tier, so a low-power static presence still shows the same states, the same difficulty encoding, the same captions. GPU trouble is never allowed to become UX trouble (Spec 04 P2.8, visually).

---

## 2. The Substrate

### 2.1 The decision: a coherent particle swarm — "the murmuration"

**The presence's normative substrate is a coherent particle swarm** — 2,000–6,000 tiny luminous motes moving as one organism through a shared flow field, GPU-drawn in a single instanced/`drawVertices` pass. Working name: **the murmuration**. *(v0.2 — this section previously specified the smoke veil, now the documented alternate, §2.2. The change is a renderer re-pointing, not a re-architecture: the `PresenceFrame` vector, §2.4, was designed to drive either body and does.)* In its resting form it occupies a soft-edged congregation roughly the upper two-fifths of the Stage (one-handed reach keeps interaction in the bottom third, Spec 07 §9.4), densest around a drifting core and thinning to a few stray outriders — the screen never shows a "shape with an edge," it shows *where the motes happen to be*.

Why the swarm — and how the design answers the three tradeoffs v0.1 honestly recorded against it:

- **Feel.** Thousands of individuals moving as one is the most vivid *gesture* medium available: gather, scatter, lean, part (§5.2) are what a swarm natively does, and the live mockup confirmed it — coherence arriving out of dispersal reads as attention in a way vapor only suggests. And the swarm can do the one thing no continuous field can: **trace a figure** (§5A) — motes can take positions on a line, and a line can mean something. That capability is now load-bearing.
- **"Coherence must be earned"** (v0.1's first objection) is answered by the flow/cohesion model, not by simulation: every mote advects through **one shared curl-noise flow field** — coherence is free when everyone reads the same weather — plus a per-mote spring toward the drifting core whose stiffness *is* `coherence` (§2.4). No flocking, no neighbor queries: O(n), branch-free, SIMD-friendly.
- **"Idle looks frozen or restless"** is answered by the **resting micro-flow**: at idle the shared field runs at whisper amplitude while the core's cohesion radius breathes on `p-breath` — each mote individually near-still (sub-pixel per frame, seed-phased), the congregation collectively, unmistakably alive. The two failure modes bracket a designed middle.
- **"Per-particle cost varies with count and platform"** is answered by a **fixed mote budget** chosen per device class at startup (never changed mid-session — no popping) plus **density-based LOD**: fewer, slightly larger and brighter motes carry the same silhouette from the same `PresenceFrame`, so T1 (§9.1) is the same body at lower resolution, not a different creature.

**Flutter feasibility.** Positions and velocities live in pooled `Float32List` buffers (no per-mote objects, allocation-free in steady state); the flow field is sampled from a small precomputed curl-noise tile; the draw is **one atlas/instanced pass** with additive blending — *(v0.3)* shipped as a single `drawAtlas` call blitting a small radial-gradient sprite per mote (`drawVertices` remains the documented alternative) — plus one cheap **aura underlay** pass, a soft radial hue wash behind the motes, which is now the *selected* mechanism for the §4.3 additive-legibility constraint (shipped). Cost is linear in count, hence the fixed budget; and the body itself has no fragment-shader dependency (the aura is a trivial gradient), which *shrinks* the platform risk Q1 carried for the veil.

**Trail persistence (v0.3 — shipped).** Plena leaves a trail of herself: true frame persistence via a ping-pong `ui.Image` buffer (`toImageSync`) — each frame the previous buffer is redrawn, eroded by the Trail setting (a `dstOut` fade; §5.4's knob sets the rate), the motes drawn into it additively, and the result blitted up to the screen. The buffer is **capped at ~760 px on its longest side** and scaled on the blit, so the per-frame `toImageSync` stays cheap at any window size — an uncapped full-resolution buffer stalls the raster thread (§9.2). The static / reduced-motion path **bypasses the buffer entirely** and draws motes straight to the canvas: repeated repaints of a stationary body must not accumulate toward white or ghost prior states (§8.3). The trail is both an aesthetic (the body moves like slow fire) and the medium of the glyph tail (§5A.4).

**Punctuation is no longer a separate layer.** v0.1's bounded "mote accent" — the Done bloom (§4.2), the undo afterglow (§4.4), the attending orbit (§3.2) — is now simply the body's own motes doing those jobs. The accent layer merges into the substrate, and the old keep-or-cut-motes question is moot (Q5, repurposed).

### 2.2 Named alternates and their tradeoffs

- **The smoke veil** *(v0.1's primary; demoted v0.2)*: a continuous volumetric smoke/nebula field — soft self-luminous vapor rendered as one fragment shader over one bounded quad, ~16 uniforms, resolution-bound flat cost. Its virtues stand exactly as first recorded: coherence is its native state; it fails gracefully (an under-animated field just looks *still* — precisely what reduced motion wants); its cost never varies with expressiveness. Why it lost the mockup round: it is weaker at gesture — gather and part read as shifts of density, not acts — and it categorically cannot trace a line-figure, so the glyph register (§5A) is closed to it. It remains **the documented alternate**: the `PresenceFrame` vector (§2.4) drives it unchanged, and if the murmuration disappoints in the v3 design pass the swap back is a renderer change, not a spec change. (Its shader-pipeline spike folds into Q1 only if the alternate is ever activated.)
- **Aurora / ribbon field** (a few luminous flowing bands rather than a volume). Cheapest of all and elegant, but its expressive range is narrow — bands can flow and glow but cannot convincingly *gather*, *part*, or *grain up* under effort — and it tends to read as decoration rather than entity. Rejected; noted because tier T1 (§9.1) borrows its cheapness.

### 2.3 What the murmuration is not

Not a wallpaper (it responds within 90 ms to state changes, §3.3), not a music visualizer (it never free-runs on audio energy; every motion is a state or signal, P5), not a particle *system* in the fireworks sense (nothing is emitted, nothing dies — the same motes persist for the whole session, P3 in miniature), not full-screen static (materialized text and views sit on calm ground, §6; the swarm guarantees them contrast, §10.1), and not a brand mascot (P4).

### 2.4 `PresenceFrame` — the parameter vector

The entire substrate is driven by one immutable value, emitted by the `PresenceDirector` at display rate and consumed by whichever tier renderer is active:

```dart
class PresenceFrame {
  final double energy;      // 0..1  overall animation amplitude (breath → full speech)
  final double tempo;       // 0.2..2.0  internal flow rate multiplier (1.0 = resting)
  final double coherence;   // 0..1  1 = gathered, tight core; 0 = diffuse, spread
  final double turbulence;  // 0..1  fine-grain churn — the "effort" channel
  final double luminance;   // 0..1  core self-illumination (display-mapped per theme)
  final double hueShift;    // -1..1 position on the vital ramp (§4.3); 0 = resting hue
  final double spread;      // 0..1  spatial extent of the field within its region
  final Offset lean;        // unit-space drift of the core (gestures, §5.2); (0,0) at rest
  final double veilYield;   // 0..1  0 = full field (Y0), 1 = receded ember (Y2) — §6.3
  final int    seed;        // per-install personality seed (§5.4); constant
}
```

Rates of change are governed by the motion grammar (§8.1) — the director interpolates; renderers never animate on their own. The vector is deliberately renderer-agnostic and small: it is the whole contract between "what the presence feels" and "how the presence looks," which is what makes tiers, golden tests, and a substrate swap all cheap — a claim v0.2 has now cashed: the same vector that drove the veil drives the murmuration, with no field changed and none added.

---

## 3. The Presence State Machine

### 3.1 Base states — Spec 12's vocabulary, exactly

The base states are **idle / listening / thinking / speaking** — the same four Spec 07 §8.4 gave the orb and Spec 12's pipeline events imply. This spec adds no fifth base state: transitional and degraded conditions are *modifiers* (§3.2), so the base machine stays in lockstep with the turn lifecycle and Spec 12's semantics are never forked. What the swarm does in each:

| State | Entered on | The murmuration |
|---|---|---|
| **idle** | app at rest; empty final; turn terminal events settled | **Breathing.** `energy ≈ 0.08`, `tempo 1.0`, high coherence, resting hue, the resting micro-flow (§2.1): the core's cohesion radius swells on a ~4 s sine (`p-breath`) while each mote drifts sub-pixel along the shared field, slow toroidal drift of the core beneath. Nothing else. At a glance across a room it should be *just barely* discernibly alive. |
| **listening** | capture session live (mic open ⇔ listening, Spec 12 §3.5 — the swarm must never claim listening when the mic is closed, and vice versa) | **Gathering, attentive.** Coherence rises toward 0.9 — motes draw in from the margins toward a tighter core (`m-instant` snap into the state, per Spec 07 §8.4 — responsiveness beats smoothness here); `energy` rides the smoothed `micLevel` stream so the user *sees being heard* — the congregation's surface shivers with their own voice *(v0.3: the shipped recognizer seams surface no live mic level yet, so a gentle self-driven shimmer stands in until Spec 12's `micLevel` lands — the visible claim "she hears while the mic is open" is kept; the coupling to the actual voice is still owed)*. Slight `lean` toward the subtitle region, where their words are condensing (§6.2). |
| **thinking** | final transcript dispatched; `TurnStarted` → pre-`Done` | **Turning inward.** Coherence high, `tempo` drops to ~0.7, luminance dips a shade, circulation becomes visibly *convective* — motes cycle inward and fold under, the swarm working on itself. This state replaces every spinner in the app (Spec 07 §2.1). Its expression deepens along the difficulty ladder (§4.2) the longer it holds. |
| **speaking** | `SpeakEvent.started` → `finished`/`stopped` (Spec 12 §2.1) | **Fluctuating in unison with speech.** `energy` and `luminance` follow the speech envelope (§4.1) — swells at phrase scale, shimmer at cadence scale; coherence moderate; a gentle `lean` toward the listener (screen-center-down). Muted changes nothing here (§7): `SpeakEvent`s still fire (Spec 12 §6.3). |

### 3.2 Modifiers — layered, not forked

Modifiers adjust the active base state's frame; several can hold at once. Each has exactly one source of truth upstream:

- **clarifying** (`ClarificationRequested` outstanding): the swarm gathers tighter and leans toward the question's chips — a listener waiting on an answer, not an alarm. Holds until `respond()` resolves the prompt.
- **effortful** (difficulty grade D1–D3, §4.2): hue cools along the vital ramp, turbulence rises. The visible truth of "this one is costing something."
- **attending** (`AttentionSurface` non-empty): a single mote detaches and orbits slowly at the congregation's periphery — the presence's echo of the Stage chip (Spec 07 §6.7), same information, zero urgency, no red (P8 of 07).
- **afterglow** (undo window live, Spec 04 §3.11): a soft warmth at the swarm's lower edge, nearest the lingering `Done` line, fading exactly when the undo chip fades — the visual statement that the last act is still soft-set (Spec 07 P6).
- **muted** (TTS muted, Spec 07 §7.1): the outermost motes desaturate into a thin, still rim — visibly muted, calmly so (extends Spec 07 §8.4's "a muted orb renders visibly muted"). Speech states still animate fully (§7).
- **degraded** (any `VoiceError` state — mic denied, STT unavailable; Spec 12 §9.2): the swarm slows to ~0.8 tempo and desaturates slightly; the honest words live in the caption/attention surfaces where Spec 12 put them. The presence *never* pantomimes an error; it just visibly has less voice.
- **error beat** (`TurnError`): one slow exhale — a single coherence drop-and-recover over ~900 ms — then back to idle. The card carries the content (Spec 07 §6.6); the swarm only acknowledges. No flare, no shudder, no red.

### 3.3 Transition rules

1. **Into listening: snap.** ≤ 90 ms (`m-instant`) from press to visible gathering — the one transition where quickness beats smoothness (Spec 07 §8.4), and it must not lead the mic (Spec 12 §3.5's invariant binds the visual too).
2. **Everything else: settle.** Base-state morphs interpolate over 300–450 ms with `m-settle` character; modifiers fade in/out at `m-quick`. The swarm never cuts.
3. **Barge-in** (Spec 04 §4.3, Spec 07 §7.4): speaking halts as a soft fade *within* Spec 12's ≤ 150 ms stop budget — the envelope collapses, not the body — and the gather-to-listening rides the same beat. One motion, two meanings.
4. **No state theater.** A sub-perceptual turn (corpus hit inside Spec 12 §7.2's 1.0 s end-to-end budget) may pass through thinking so briefly it never visibly expresses; the director must not stretch states to "show work" that didn't happen. Honesty over drama.

---

## 4. The Expressive Mapping

The crux: every aesthetic behavior lands as a signal→parameter rule. The director implements this table and nothing not in this table (P5: no free expression).

### 4.1 Speech → fluctuation

The vision asks for the field to "fluctuate beautifully in unison with its speaking." The obstacle is honest: **platform TTS engines do not expose a realtime output-amplitude stream** (Spec 12 §6.1's matrix — none of the three publishes synthesis PCM to the app by default). The design therefore runs on a **cadence-envelope proxy**, upgraded when real timing data exists:

- **v1 proxy — the synthesized envelope.** When `speak(text)` is issued, the director derives a deterministic envelope from the *text itself*: syllable count estimation (vowel-group heuristic — cheap, locale-tolerant) sets a pulse train at spoken-syllable rate scaled to the configured TTS rate; punctuation and clause boundaries insert phrase-scale swells and dips; expected duration is estimated from character count × rate and **re-anchored against reality** at `SpeakEvent.started` and truncated at `finished`/`stopped`. The envelope drives `energy` (primary) and `luminance` (phrase-scale swells only — see the photosensitivity clamp, §10.3). Result: the swarm breathes *with the shape of the sentence* — provably in sync at start/stop, plausibly in sync within — which observation of ambient-companion products suggests is fully sufficient at conversational glance distance. It will drift on long utterances; long utterances are already capped by the subtitle length discipline (Spec 07 §7.3).
- **Upgrade path — word boundaries.** If/when TTS word-boundary callbacks prove reliable cross-platform, Spec 12 carries them as `SpeakEvent` extensions (its Q6) and the director snaps the envelope to real word onsets. This spec is the *customer* of that question (suite-sync X6); the proxy is designed so the upgrade changes fidelity, not architecture.
- **Never raw audio taps.** The director does not capture system audio output to measure amplitude — a loopback tap would be platform-fragile and sits badly against Spec 12 §8's "audio never exists" posture even though output ≠ capture. The envelope is computed from text the app already holds.
- *(v0.3 — shipped baseline.)* The dogfood build anchors the speaking state strictly to the real TTS callbacks: `speak()`'s start/done bracket the animation, with a generous length-scaled safety cap so a stalled engine can never freeze her mid-speech; when muted (or voiceless) a silent flourish timed to the reply's length stands in. The cadence envelope above is still to land on this anchor — the provably-in-sync endpoints already exist.

### 4.2 Difficulty → hue, luminance, turbulence

"Difficulty" is defined operationally as a **ladder of effort grades**, each detected from signals that already exist — nothing new is instrumented:

| Grade | Operational trigger | Swarm expression |
|---|---|---|
| **D0 — effortless** | corpus-hit local turn resolving inside the p50 budget (Spec 12 §7.2) | None. The high-confidence band shows nothing extra (Spec 07 §6.3's quiet), and neither does the swarm. Most turns are D0 and *look* like it — that restraint is what makes D2 legible. |
| **D1 — working** | thinking state persists > 400 ms (local compute, long queries) | `tempo` −20%, `luminance` −1 step, convection deepens. No hue shift yet. |
| **D2 — reaching** | a cloud round-trip is in flight: residual routing or a generative/authoring detached op attributable to the live turn (Spec 04 §3.6/§4.7; Spec 08 §3.1's ~0.8–1.2 s) | hue cools to the ramp's far third (§4.3), fine-grain `turbulence` rises to ~0.5 — visible concentration. The user learns, wordlessly, what "thinking hard" (and, on the paid tier, "spending") looks like. |
| **D3 — struggling** | `ClarificationRequested`; a below-ASR-floor re-ask (Spec 12 §4.6); a `Correct` reversal in flight (Spec 05 §3.3) | D2's expression **plus** the clarifying gather (§3.2) and a half-step luminance *rise* — leaning in, asking. Never agitation: struggle reads as increased attention, not distress. |
| **D4 — can't** | `TurnError`; degraded voice states (Spec 12 §9.2) | The error beat / degraded modifier (§3.2): slower, stiller, slightly desaturated. Difficulty at its ceiling is *quieter*, not louder — the inversion that keeps failure calm (Spec 04 P2.8's surfaces carry the content). |

Every grade changes **at least two non-hue channels** (P7). Grades are monotonic within a turn (a turn may climb the ladder, never oscillate on it) and clear with the turn's terminal event.

### 4.3 The vital ramp — the presence's color system

Spec 07 §9.3 permits exactly two semantic colors beyond neutrals and reserves the 12-hue accent ramp for *type identity*. The presence needs a hue dimension and must not raid either. The resolution (suite-sync X3): the presence gets its own **vital ramp** — one continuous, narrow band of desaturated hues, exclusive to the presence, never used by any card, chip, glyph, or text (icon glyphs in Spec 07 §9's sense — the presence's *traced* glyphs of §5A are made of the swarm's own motes and inherit its color):

- **Resting third** (`hueShift ≈ 0`): a warm near-neutral glow, barely distinguishable from the base surface's warmth — the presence at rest is *almost* the color of the room.
- **Effort third** (`hueShift → −1`, grades D2–D3): a cool drift — think pre-dawn blue-violet — always paired with turbulence/tempo changes (P7).
- **Assent accent** (`hueShift → +1`, momentary): the `Done` beat borrows Spec 07 §9.3's single confirmation-positive tint for a one-breath bloom coinciding with the `Done` line and glyph — the same semantic color, so the vocabulary stays at two.
- The **attention hue** appears in the presence only as the attending mote's tint (§3.2) — again the existing semantic color, not a new one.

Saturation across the entire ramp stays low (the swarm is embers, not neon) — subject to the saturation floors below: "low" means restrained, never so low that additive blending erases it. The exact anchor values are produced by the same visual-design pass as Spec 07 Q2's accent ramp (they must sit correctly against both themes), and the ramp ships as tokens, not literals.

**Legibility on an additive field (v0.2 — hard design-pass constraint).** The first live mockup failed exactly here: naive additive blending of thousands of luminous motes accumulated to a near-white core — a fireball — and the ramp's hue barely read. This is not a tuning note; it is a **release-gating constraint**, because §4.2's difficulty encoding leans on this ramp: hue is P7-redundant, but it is a *required* expressive channel, not an optional garnish. Normative requirement: **at every animated tier, in both themes, the ramp's resting, effort, and assent thirds must remain distinguishable on the live swarm at conversational glance distance, at full additive load.** Candidate mechanisms, to be *selected* (not debated away) in the Q3 design pass:

- **the aura underlay** (§2.1) — an ambient hue wash behind the mote layer that carries the ramp at low spatial frequency, immune to additive buildup;
- **constrained additive buildup** — a per-pixel accumulation cap and/or core density cap, so the center saturates *in the ramp's hue* rather than blowing out to white;
- **wider-separated ramp anchors with saturation floors** — anchors far enough apart, and floored saturated enough, that the residue surviving blending still reads.

*(v0.3 — selected.)* The shipped build answers with the first two together: the **aura underlay ships** (a radial ambient wash in the ramp hue behind the mote pass, `BlendMode.plus`), and **per-mote alpha is capped** (free motes ≤ 0.62, glyph deposits ≤ 0.28) so the additive core saturates in hue rather than blowing out. The result is deliberate: Plena reads as a **fireball-like core whose hue shifts with activity state** — bright center, colour carried by the aura and the body's fringes — the *designed* version of the accident the first mockup produced. Shipped ramp mechanics: the tuned warm resting hue cools continuously toward pre-dawn blue (≈ hue 214) as the difficulty grade climbs, with saturation dipping a step at the D4 ceiling. Q3 narrows to the golden-frame gate, the designed anchor values, and the light-theme variant.

The grayscale-legibility assertion (§10.2) gains a color sibling: a golden-frame assertion that the three thirds are distinguishable at full additive load (§10 item 7, X7). A forming glyph inherits the same demand from the other side — figure against ground, §5A.4.

### 4.4 Turn-contract cues, harmonized with Spec 07 §6

| System moment | Spec 07's surface (unchanged) | The swarm's cue (this spec) |
|---|---|---|
| `Done` (act-then-describe) | `Done` line + undo chip (§6.2) | One-breath assent bloom (§4.3), then the **afterglow** modifier for exactly the undo window |
| Moderate-band routing (`Routing` advisory) | routing chip (§6.3) | A single soft shimmer across the field at the chip's arrival — a raised eyebrow, sub-500 ms, once |
| Clarification | question line + choice chips (§6.4) | clarifying gather + lean toward the chips; holds until resolved |
| Non-undoable deletion confirm | the one modal (§6.5) | The swarm **stills almost completely** behind the sheet — held breath. The app's sole heavy surface gets the presence's sole full stop. |
| Residual offer / `Detached` | offer line / working entry (§6.6) | Nothing / a barely-visible peripheral circulation while the op runs (the Operation Center's shimmer, echoed at whisper level) |
| Attention item arises | Stage chip (§6.7) | attending mote (§3.2) |

The rule of the table: **the cards carry information; the swarm carries demeanor.** No cue in the right column is ever the only signal of anything (P7 and Spec 07 P1 both demand it). Presence glyphs (§5A) layer over this table at their own, rarer occasions and under their own cap — they refine a row's moment when apt; they never replace a row's cue.

---

## 5. The Disembodied Personality

Personality with no body is *timing, restraint, and idiosyncrasy* — nothing else is available, which is a discipline, not a poverty.

### 5.1 Breath

The idle loop is a compound rhythm, not a sine: a ~4 s primary swell (`m-breathe`) carrying a slower ~26 s drift of the core's position, with per-install phase offsets from the seed (§5.4). Amplitude is clamped so that a screenshot of idle and a 2-second glance at idle are *both* unmistakably calm — the motion is discovered, not announced. After 90 s without interaction the swell shallows a further 40 % (resting deeper); any signal restores it instantly. The swarm holds the screen's **one** `m-breathe` allowance (Spec 07 §8.2 rule 1) — the breath-budget consequences are §8.2.

### 5.2 Gesture vocabulary — five, total

All presence gestures are motions *of the whole body*, drawn from a closed set: **gather** (coherence up — attention), **lean** (core drift toward a screen region — orientation toward the subtitle, a chip set, a materializing card), **bloom** (the one-breath assent swell), **part** (the swarm thinning to make room, §6.3), **exhale** (the error beat's drop-and-recover). No new gesture ships without a rule in §4's tables. Five is the budget because a creature with fifty gestures is a performer, and a performer is exhausting to live with (P5).

**Glyphs are not gestures.** The traced figures of §5A are a separate, rarer, *figurative* register with its own budget and fences; they do not join this set, and this set does not grow to accommodate them. Gestures are how the swarm always moves; a glyph is something it occasionally *says*.

### 5.3 Reaction timing is the personality's spine

- **Acknowledgment is instant:** any user-initiated signal (press, speech onset, typed submit) is reflected in the field within 90 ms (`m-instant`) — the presence *never* leaves the user unwitnessed.
- **Expression is unhurried:** everything that is not acknowledgment moves at `m-settle` pace or slower. Quick to notice, slow to emote — that asymmetry *is* the character: attentive, unflappable.
- **Silence is honored:** no speech, no turn → no motion beyond breath. The presence never fills a pause, never solicits, never demonstrates aliveness it isn't using (the wake-word-era "armed" reading is Q4).

### 5.4 The seed — consistent idiosyncrasy

A 32-bit **personality seed** is minted at install and persisted (extending Spec 07 §9.2's "unique per render seed" from per-render to per-*being* — suite-sync X1): it fixes the noise-field basis, breath phase offsets, core drift path bias, mote condensation pattern, and the glyph dialect (§5A.6). Two installs are visibly siblings, not twins; one install is *the same entity* every single day. The seed is the personality-consistency knob: v1 exposes no user tuning (curated, Spec 07 P8), and the seed's place in device migration/sync is Q6. Everything else about the personality — timing constants, gesture budget, amplitude clamps — is fixed in tokens, identical for everyone: Plenara has *a* character, not a character editor.

*(v0.3 — two field notes.)* First: the shipped build runs on a **fixed constant seed** — the same Plena every run; per-install minting is still to come (Q6 unchanged). Second: the dogfood build carries a live **tuning sheet** — hue, vibrance, brightness, breadth, gravity, looseness, trail — the mockup's knobs brought in-app so the curated values are dialed by eye without a rebuild (changes apply live; Plena reads the tuning every frame). These are design instruments for *converging on* the shipped constants, not a shipped character editor: the curated-no-user-tuning posture stands for release. One tuning invariant worth recording: **compression is not shrinkage** — raising gravity gathers the congregation tighter without scaling down the luminous core; the knobs move spread, pull, and wander, never the core's size.

### 5.5 The kitsch fence (P4, enforced)

Never: eyes, face, mouth, blinking, emoji-affect, head-nod/shake motions, heartbeat pulses, "sleeping z" idles, seasonal costumes, or reactive cursor-following. Never sadness-theater on errors or celebration-theater on streaks (the streak lens carries its own quiet reward, Spec 05 §8 — the swarm does not throw confetti). The test for any proposed behavior: *would weather do it?* Weather gathers, stills, glows, and parts; it does not wink.

*(v0.2)* The one sanctioned figurative channel is the glyph register (§5A) — fenced separately and more strictly, not more loosely (§5A.7): a glyph *sketches* a symbol once and releases it; the body itself never acquires features. The confetti line above stands unamended — §5A.5 explains why a single traced figure is not confetti, and where the line is.

---

## 5A. The Symbolic Glyph Vocabulary (v0.2)

**A numbering note:** lettered §5A rather than renumbering — §6 through §12 are load-bearing cross-reference targets inside this file and across the suite (X1–X8 cite them; Spec 12 Q6 cites §4.1 here), and glyphs *are* personality, so the section belongs beside §5. The letter is a numbering convenience, not a demotion: §5A is fully normative.

### 5A.1 The governing rule: apt or absent

A glyph fires only when it is **semantically apt to what the app just did or is doing** — never as a free-floating emotional flourish. Add a todo and the heart has no business appearing; at most a quiet added-tick fires, and usually **nothing does**. The heart belongs to a genuinely affectionate moment — closeness logged with a loved one, a relationship note — and nowhere else. A bad-fit glyph is a **design error**, not a personality quirk: the mapping from occasion to glyph is tight, sensible, and closed (§5A.8's table *is* that mapping), and the seed's dialect (§5A.6) chooses among apt candidates only — it never overrides aptness.

**The default is no glyph.** The overwhelming majority of turns show none: the swarm's ordinary hue and motion are the whole response, and that scarcity is what makes a glyph worth looking at — exactly as D0's restraint makes D2 legible (§4.2), and for the same P5 reason: over-firing is the named failure mode, forbidden outright. The decision rule is **apt-or-absent**: if no glyph *clearly* fits the occasion, the answer is none — never the least-bad one.

**The appropriateness test** (applied to every row of §5A.8, and to any future candidate): *would this mark make sense if it appeared right after this exact action, with the sound off?* If a bystander watching the screen would wonder why the figure appeared, it does not fire.

*(v0.3)* The mapping ships as **code beside the data**: `glyphForTurn(skill, reply)` in `app/lib/glyphs.dart` resolves a completed turn — the dispatched skill id (matching inside a compound "a+b") plus the reply text — to an apt glyph or, on most branches, to null. Branch order encodes aptness: bad news is checked before celebration, so a **lapsed** streak resolves to the settle arc and never the star; an undo earns the undo-loop; a meaningful completion the check; a goal set the target; a journal save the quill; the heart fires only for closeness logged with a partner, while a plain interaction gets at most the quiet nod. The final branch — most turns — returns nothing. On-open greetings follow the same discipline in `main.dart`: a birthday nudge earns the candle, otherwise the smile.

### 5A.2 What a glyph is — and is not

A glyph is a brief, symbolic **line-figure** the swarm traces, holds for a beat, and releases: two dots land, an arc sweeps beneath them, the smile hangs for a breath, and the motes rejoin the flow. It is *expressive punctuation* — something the presence says once — never a persistent icon, badge, HUD element, or status indicator.

The distinction from §5.2's gesture vocabulary is sharp and load-bearing. **Gestures** (gather, lean, bloom, part, exhale) are how the body always moves — continuous, abstract, cheap, ambient demeanor. **Glyphs** are a rarer, higher-tier, *figurative* register — discrete, symbolic, expensive in attention, and strictly budgeted (§5A.5). Gestures are demeanor; glyphs are diction. A presence that gestured rarely would feel dead; a presence that glyphed often would be a performer, and a performer is exhausting to live with (P5, §5.5).

*(Terminology: Spec 07 §9.3's "glyph" means icon glyphs in type; this spec's traced figures are "presence glyphs" — "sigils" informally — and X3's exclusion list refers to the former.)*

### 5A.3 Glyphs are data, not code

Per the suite's standing rule that **AI authors, code executes** (the generative-card posture — Spec 05 §16: the model composes content, fixed code renders it), a glyph is a *definition*, not a renderer feature:

```dart
class GlyphDef {
  final String id;                  // stable token: "glyph.smile", "glyph.check", …
  final List<GlyphStroke> strokes;  // ordered polylines/arcs — draw order IS the choreography
  final List<GlyphDot> dots;        // point marks: eye-dots, ellipsis points, a clapper
  final double holdMs;              // how long the completed figure holds
  final String meaningKey;          // the spoken/caption equivalent (P7 — §5A.7 fence 1)
  final GlyphDegrade degrade;       // per-tier policy: full | simplify-to(id) | still | skip
}

class GlyphStroke {
  final List<Offset> path;   // normalized presence-space (0..1 within the swarm's region)
  final double delayMs;      // activation offset from glyph start — how "eyes land, then the smile sweeps"
  final double drawMs;       // duration of the ease-in draw along the path
}

class GlyphDot {
  final Offset at;           // normalized presence-space
  final double delayMs;
  final double dwellMs;      // optional extra dwell before the dot joins the release
}
```

*(v0.3 — shipped schema.)* The dogfood `GlyphDef` carries `id`, `occasion` (the trigger, as the definition's own text — §5A.1's rule made literal: the occasion field *is* the definition), a `core` flag, `strokes` (`pts`, `delayMs`, `drawMs`) and `dots` (`at`, `delayMs`); hold and release are currently director constants rather than per-glyph fields, and `meaningKey`/`degrade` are still owed as schema fields — fence 1 is honoured meanwhile because every shipped trigger fires alongside a spoken/captioned reply that carries the meaning.

The renderer's job is fixed and glyph-agnostic: it expands the definition into an ordered, timed target list and runs the comet-trail choreography of §5A.4 — fly, deposit, hold, release. **No glyph ever requires new render code.** Claude may *select* a glyph for an occasion, or — rarely — *compose* one within this schema for a bespoke moment, subject to every rule in §5A.1 and every fence in §5A.7; it cannot invent rendering, blending, or motion outside the schema. The shipped vocabulary (§5A.8) is curated data, versioned with the app.

### 5A.4 Formation, timing, release — the comet trail *(v0.3: re-specified to the shipped mechanic)*

v0.2 had motes take up positions on the figure while the body stayed put. The build found the stronger reading, and it is now normative: **Plena herself flies the glyph's path and ejects her tail** — the figure is the wispy, semi-transparent comet trail she leaves behind, which holds for a beat and then streams back into her. The entity writes; she doesn't delegate.

- **Expansion.** The director expands the `GlyphDef` into one ordered, timed target list: each dot scatters into a small cluster (~20 points around its mark, micro-staggered), each stroke resamples at roughly one target per 2–3 px of arc length; targets sort by fill-time and cap at **~600** (about a quarter of the current mote budget — the tail is sparse by design).
- **Flight.** Plena's core — her centre of mass — rides the target list on its fill-times, easing along the path. The majority of the body (~70 % of motes) becomes her **travellers**: they chase the flying core on a tightened radius with strengthened pull and damped flow, so the whole visible entity streams along the figure. What remains at home is the thin free residue plus the aura — the body *goes*. Draw order is still the choreography — the dots land, then the strokes sweep — because the core's own flight traces it.
- **Deposit — the tail.** As the core passes each target on time, one traveller is handed off and settles there, shimmering faintly in place. Deposits render **far more transparent than her bright core** — deposit alpha ≈ 0.19 × luminance (clamped ≤ 0.28), against the free body's ≤ 0.62 — and the trail-persistence buffer (§2.1) smokes them further: the figure is a comet trail forming the shape, never a solid stroke.
- **Flourish and hold.** At the path's end Plena flits briefly at the figure's terminus — a small pleased waggle (~0.6 s) while the last deposits land — then the completed figure holds ~0.5 s.
- **Release — the rejoin.** Deposits and travellers let go together and drift home at `m-drift` character, remnants rejoining the core mid-current over ~1.1 s. The figure doesn't vanish; it *pours back into her*. Release is still softer than the entrance (Spec 07 §8.2 r3).
- **Timing token.** The whole sequence is the `p-glyph` register (§8.1) — one-shot, never looping, one at a time; it occupies the `p-cue` exclusivity slot (§8.2 r2). A glyph requested while one is active is dropped, not queued — nothing is lost, because no glyph carries meaning alone (§5A.7 fence 1). Reduced motion **abandons** any in-flight figure rather than freezing it (§8.3): a static frame never shows a half-drawn glyph.
- **Figure against ground.** The figure/ground demand of §4.3 is met, as shipped, by the **alpha asymmetry itself** — a bright flying core writing a faint tail on the dark void reads as line against ground without dimming the field. v0.2's calmed-and-dimmed backing remains the fallback mechanism if a busier ground (Y1 content, the light theme) proves it insufficient; the golden-frame gate (§5A.7 fence 6) judges.

### 5A.5 Occasions, the cap, and the confetti reconciliation

- **Occasion-gated, signal-traced.** Every glyph fires from a real signal already in the streams — a `Done`, a logged interaction, a surfaced date, a streak counter, a `SpeakEvent` — mapped by §5A.8's trigger column under §5A.1's apt-or-absent rule. Never on a timer, never as ambient variety (§8.2 r3: meaning gates motion).
- **Frequency cap (normative):** at most **one glyph per turn**; **≥ 90 s** between glyphs; a soft daily budget of **~8**, with occasion-priority when the budget contends (occasions of the heart — birthdays, closeness, remembrance — outrank affirmations; affirmations outrank ornaments, which don't exist anyway). *(v0.3: the dogfood build runs a short 8 s debounce in place of the 90 s spacing while the vocabulary is exercised by eye; forced fires — the on-open greeting, the dev preview — bypass it. The production cap stands as written.)*
- **The confetti reconciliation.** §5.5 stands: the swarm does not throw confetti, and the streak lens keeps its own quiet reward (Spec 05 §8). A glyph is admissible where confetti is not because it is the *opposite structure*: confetti is many things, scattered, looping, unearned by content; a glyph is **one figure, once, drawn and released, tied to a named signal**. Even the celebration register obeys this — the "confetti" glyph (#40) is a single dotted arc: celebration *quoted* in one gesture, not performed. The moment a figure repeats, loops, multiplies, or fires without a signal, it has become confetti and is out of spec.

### 5A.6 Dialect — the seed's share

The personality seed (§5.4) biases the register into a per-install **dialect**: among glyphs apt for the *same* occasion (star vs. confetti-arc at a streak milestone; ellipsis vs. spiral for thinking-hard), the seed weights a stable preference; it also fixes micro-idiosyncrasy — the smile's exact curvature within tolerance, a few percent of stroke-speed bias, a characteristic corner of the region where figures tend to form. Same system, same vocabulary, personal handwriting: one Plenara habitually reaches for the nod-arc, another for the small check. The dialect never *adds* aptness (§5A.1 always wins) and never excludes a glyph from its occasion — it shades frequency and rendering, nothing else.

### 5A.7 Hard fences

1. **Never the sole carrier (P7, §10 item 6).** Every glyph has a `meaningKey` naming its spoken/caption equivalent, and the occasion that fires a glyph always also produces its ordinary surface — the `Done` line, the caption sentence, the birthday attention item. A user who never sees a glyph loses charm, not meaning. A definition without a meaning equivalent is invalid data.
2. **Reduced motion (§8.3):** no drawing. The glyph's end-state figure may appear as a brief still (≤ 300 ms cross-fade in, hold, fade) or the glyph is skipped entirely; the still-presence setting chooses, defaulting to skip. Never a moving trace.
3. **Photosensitivity (§10.3):** the draw is *motion*, never light. Glyph formation must not modulate full-field luminance; assigned motes keep body-normal brightness; nothing about a glyph blinks, strobes, or inverts. Pulse-figures (#19) express as scale, once, inside the ≤ 2 Hz clamp.
4. **The kitsch fence, tightened (P4, §5.5).** A glyph is a *symbolic line-figure* — the kind of mark a thoughtful person might sketch in a margin. That is the line: **"would a considered hand sketch it in one or two strokes?"** Admissible: a smile arc beneath two dots; a heart; a check. Out, permanently: literal faces with pupils, irises, or lids; a winking eye drawn *as an eye* (the wink glyph, #17, is a dot, a dash, and an arc — punctuation, not physiognomy); anything animated as anatomy (a mouth that moves, eyes that track); shading, photorealism, or multi-figure scenes; emoji or brand reproduction. Abstraction and economy are the rule — a figure that needs detail to read is the wrong figure.
5. **Tier degradation.** T2 renders glyphs fully. T1 renders core glyphs at its reduced count; figures marked † in §5A.8 do not read below ~400 motes and follow their `degrade` policy — usually simplification to a plainer sibling (cake → candle) or a skip. T0 and reduced motion behave per fence 2. *(v0.3: the "glyphs wait for v3" corollary is overtaken in the good direction — the dogfood build shipped the animated swarm with the glyph engine directly, §9.3; the tier-degradation policies stand for the platforms that will need them.)*
6. **Legibility (§4.3).** A glyph must read as figure against ground at full additive load — the calmed, dimmed backing of §5A.4 is normative, and glyph golden-frames join the §9.2 test hooks (X7).

### 5A.8 The vocabulary — fifty glyphs

Fifteen **core** (ship with the v3 rung), thirty-five **extended** (post-v3 curation, Q5). † = hard to read at low mote counts (T1 policy per §5A.7 fence 5). The **occasion column is the definition**: each figure exists *because* its trigger exists — the set is the app's functional-and-emotional vocabulary, not clip-art — and every trigger passes §5A.1's sound-off test. Figures are terse build instructions against the §5A.3 schema: strokes in draw order, dots as marked.

| # | Name | Occasion / trigger | Traced figure (strokes in draw order) | Tier |
|---|---|---|---|---|
| 1 | Smile | greeting — first open of the day | two dots land (left, right), then one shallow upward arc sweeps L→R beneath them | Core |
| 2 | Check | meaningful `Done` — an overdue task cleared, the last task of the day, a streak-extending completion (a routine `Done` keeps §4.4's bloom and no glyph) | one two-segment stroke: short down-right, long up-right, slight overshoot settle | Core |
| 3 | Heart | closeness logged with a loved one — an interaction of real warmth (never any task event; §5A.1's own example) | two mirrored arcs drawn simultaneously from top-center, meeting at the lower point | Core |
| 4 | Wave | farewell — goodnight sign-off, end of an evening session | one horizontal S-curve swept once L→R, trailing off | Core |
| 5 | Spark | small delight — the assistant finds something genuinely good (a free evening both friends share, a match in the calendar) | four short strokes radiating from center, drawn outward in quick succession | Core |
| 6 | Question curl | clarification asked (D3, `ClarificationRequested`) — accompanies the chips, never replaces them | question-mark arc drawn top→hook, detached dot lands below after a beat | Core |
| 7 | Ellipsis | thinking-hard — D2 held beyond ~3 s (the long cloud round-trip) | three dots land L→R with even dwell between | Core |
| 8 | Sunrise | morning brief delivered — the day's first summary | horizon stroke L→R, then a half-disc arc rising above it, then three short rays | Core |
| 9 | Crescent | evening wind-down — rest nudge or quiet-hours entry | outer arc top→bottom, then inner arc closing the crescent | Core |
| 10 | Star | streak milestone reached (7 / 30 / 100 days) | five-point star in one continuous stroke, starting and ending at the top point | Core |
| 11 | Candle | a birthday surfaces today (attention item) | one vertical stroke bottom→top, then a small closed flame loop at the tip | Core |
| 12 | Nod arc | assent — a confirmation accepted, a "got it" moment in conversation | one shallow down-and-up arc, drawn once: the path of a nod, no head | Core |
| 13 | Ripple | "I heard you" — a long, weighty user utterance lands (a hard journal entry spoken aloud) | three concentric arcs drawn inner→outer, expanding | Core |
| 14 | Settle arc | softening bad news — a lapsed streak, a missed reminder, a conflict found | one inverted shallow arc, low in the region, drawn slowly; nothing above it | Core |
| 15 | Quill flick | journal entry saved — the day's writing is in | one diagonal flick stroke rising right, terminal dot landing just past the tip | Core |
| 16 | Warm smile | reunion — first open after ≥ 4 days away | deeper smile arc sweeps first, then the two dots land above — the reversed order reads as slower warmth | Extended |
| 17 | Wink | a light joke lands in the reply (the assistant's, not the user's) | one dot, one short horizontal dash beside it, then the smile arc; never a drawn eye (§5A.7 fence 4) | Extended |
| 18 | Double-check | list cleared — every task of the day done | small check, then a second larger check overlapping to its right | Extended |
| 19 | Pulse-heart | relationship anniversary; a long closeness streak with one person | heart (#3), hold, then a single concentric heart outline expands and fades — once, inside the ≤ 2 Hz clamp | Extended |
| 20 | Linked rings | two people connected — an introduction logged between contacts | left circle drawn full, then right circle drawn through it, overlapping | Extended |
| 21 | House | a family gathering logged; a "home" plan made | one continuous pentagon: base L→R, wall up, roof peak, wall down, close | Extended |
| 22 | Gift † | gift idea captured for someone (degrade → #2 small form) | square base, lid stroke across, then two small bow loops at top center | Extended |
| 23 | Clasp | comfort — the assistant responds to a hard journal entry or a grief note | two hook-arcs drawn toward each other, interlocking at center: held hands, abstracted | Extended |
| 24 | Clock † | a far-ahead promise made — reminder confirmed for a date weeks out ("I'll hold this for March") | circle drawn full, then two hand strokes from center: short, then long | Extended |
| 25 | Hourglass | a gentle deadline approaches — surfaced with the reminder, never as pressure theater | upper triangle apex-down, then lower triangle apex-up, meeting at the waist | Extended |
| 26 | Up-arrow | weekly review shows an improving trend | vertical stroke bottom→top, then two short chevron strokes meeting at the tip | Extended |
| 27 | Flag | a goal completed — a finish line, not a streak tick | vertical pole bottom→top, then triangular pennant: out, back, close | Extended |
| 28 | Laurel † | a major milestone — 100-day streak, a year of journaling (degrade → #10) | two mirrored arcs rising toward center, each carrying three short leaf ticks base→tip | Extended |
| 29 | Rising bars | week review delivered with a positive trend across habits | three vertical strokes L→R, each taller than the last | Extended |
| 30 | Spiral | thinking-hard — dialect alternative to #7 (§5A.6) | one spiral, 1.5 turns, drawn center→out, slow | Extended |
| 31 | Orbit | a long detached op begins — generative or authoring work moves to the background | center dot lands, then two dots sweep one shared elliptical revolution and settle | Extended |
| 32 | Small check | a capture worth marking — first todo of a new project, an item the user flagged as important (a routine add shows **nothing**, §5A.1) | half-size check (#2) at the region's periphery, faster draw | Extended |
| 33 | Open book | journal session begins — the user opens the day's page by voice | center spine stroke top→bottom, then two mirrored page arcs opening outward | Extended |
| 34 | Up-tick | encouragement — the user reports progress on something they'd named as hard (the thumbs-up, abstracted past anatomy) | one rising stroke ending in a small upward flick | Extended |
| 35 | Leaf | a rest day honored — the user takes the break the app suggested | midrib stroke base→tip, then two mirrored margin arcs base→tip | Extended |
| 36 | Teacup † | a break suggested — "you've been at this a while" (degrade → #35) | bowl arc L→R, small handle loop at right, then one slow rising wisp stroke above | Extended |
| 37 | Bell | a reminder the user asked to be *sure* about fires (routine reminders fire silently — §5A.1) | bell dome arc L→R, base stroke, then clapper dot below | Extended |
| 38 | Balloon | celebration for a loved one's news, logged (an engagement, a new baby) | circle drawn full, small knot tick, then one wavering tail curve falling away | Extended |
| 39 | Cake † | a close person's birthday — the fuller form (degrade → #11) | two stacked tier strokes L→R, then one candle tick with flame loop atop | Extended |
| 40 | Confetti-arc | streak milestone — dialect alternative to #10; the register's entire concession to celebration (§5A.5) | six dots land in ballistic-arc order, rising L then falling R — one quoted arc, never a scatter | Extended |
| 41 | Infinity | a multi-year bond's anniversary — the oldest relationships in the circle | one continuous figure-eight, crossing at center, ending where it began | Extended |
| 42 | Seedling | a new habit created — day zero | vertical stem stroke bottom→top, then two small mirrored cotyledon arcs at the tip | Extended |
| 43 | Bridge | reconnection — a reach-out nudge accepted after a long gap with someone | two dots land far apart, then one low arc drawn between them | Extended |
| 44 | Meeting line | a new person added to the circle | two dots land apart, then a straight line drawn from one to the other | Extended |
| 45 | Ensō | day closed — the evening review completes | one circle drawn in a single unhurried stroke, deliberately not quite closed | Extended |
| 46 | Breath tilde | a breathing or unwind prompt accepted | one long horizontal sine stroke, drawn at half tempo, fading at both ends | Extended |
| 47 | Snooze arc | reminder snoozed — "set aside, not lost" | one arc sweeping right and down, terminal dot landing where it comes to rest | Extended |
| 48 | Undo loop | undo taken — the last act unwound cleanly (pairs with the afterglow's end, §3.2) | counter-clockwise three-quarter circle, short arrowhead tick at the open end | Extended |
| 49 | Target | a goal set — the moment of commitment, not completion | outer circle, inner circle, then center dot lands last | Extended |
| 50 | Still flame | remembrance — a memorial date surfaces | one slow vertical stroke, then a single dot above it that simply arrives and holds; dimmest figure, longest hold, softest release in the set | Extended |

Every row's `meaningKey` exists before the row ships (fence 1). Additions go through the same review as these fifty — occasion first, figure second, §5A.1's test always (Q5).

*(v0.3 — shipped coverage.)* Forty-nine of the fifty ship as data in `app/lib/glyphs.dart` — all fifteen core plus the extended set, including the †-marked figures authored as spare emblems (only the confetti-arc, #40, is still unwritten). The forms are a first pass, refined by eye through the **dev preview**: long-pressing Plena cycles the vocabulary — a development affordance outside the §5A.5 cap, not shipped behavior. `meaningKey` as a schema field is still owed (§5A.3); the reply text carries the meaning meanwhile.

---

## 6. Text Materialization & Yielding

### 6.1 The choreography: condensation and release

All presence-adjacent text obeys one arrival/departure grammar, layered on Spec 07's typography (§9.1) without violating §8.2 rule 4 (*text does not move positionally*):

- **Condense (arrive):** the swarm locally calms and clears beneath the text's final position over ~120 ms — motes thin, slow, and settle toward the contrast band; the text then resolves *in place* — opacity 0→1 with a slight weight/tracking settle (a `m-quick` solidify, exactly the mechanic Spec 07 §7.3 already uses for the interim transcript). Letters never fly, slide, or assemble. The impression is fog condensing into legibility.
- **Release (depart):** opacity fades (`m-quick`), then the local calm band relaxes over ~400 ms (`m-drift`). Exits are always softer than entrances (Spec 07 §8.2 rule 3). Nothing is ever wiped, swiped, or collapsed.
- The **calm band** — the local region of clamped density, turbulence, and luminance beneath any live text (normatively specified in §10.1) — is what lets text and swarm coexist: the body is alive around words, never *under* them.

### 6.2 The subtitle slots

Spec 07 §7.3's two-slot contract is adopted wholesale — user slot (interim, dimmed-provisional, solidifies on final), assistant slot (whole-line on speech start, 4 s linger), two-line discipline, always-on. This spec adds only: both slots render inside the swarm's lower margin on a calm band; the interim slot's provisional dimness reads as *not yet condensed* (the metaphor and the mechanic finally coincide); and the assistant slot's release re-joins the field per §6.1. Slot ownership, content, and timing remain Spec 07's; Spec 12 §4.3's ownership line is untouched. *(v0.3: shipped captions render as a width-constrained centered column low over the void — the measure, not the window, bounds the line, so a full-screen desktop window never stretches a caption across it; list content gets its own reading column, §6.3.)*

### 6.3 Yielding — the seam with Spec 07's views, drawn explicitly

The hard question: Plenara *has* real views — archetype homes, the Stream, the Operation Center (Spec 07 §2–§3) — and the vision says the app must never feel like "a normal app with flat lists." The seam is the **yield ladder**: three named degrees of `veilYield` (the field keeps its v0.1 name — the vector is frozen, §2.4), and every surface in Spec 07 §2 sits at exactly one of them.

- **Y0 — the field (yield 0).** The Stage. The murmuration is the ground; the ambient cards (at most three, Spec 07 §2.1) float *on* it in its lower region, each on its own calm band; the lingering `Done` line sits at the threshold. The Stage's steady state is the entity, not a layout that includes an orb (supersedes Spec 07 §2.1's anatomy ordering — suite-sync X1).
- **Y1 — the parting (yield ≈ 0.5).** Turn-scoped content that arrives *in conversation*: result cards, generative cards, the authoring preview, clarification chip sets, search results (Spec 07 §6). The swarm **parts** — motes thin away toward the top and edges over `m-settle`, remaining fully visible as a living margin — and the card materializes on the ground they exposed (condensation grammar for its text, doorway transition intact, Spec 07 §8.3). The presence is visibly *presenting* the card, the way a hand presents a page. When the card releases, the swarm refills (`m-drift`).
- **Y2 — the ember (yield 1).** Immersive surfaces: an archetype home opened full (Collections), deep Stream scrollback, the Operation Center, Settings. The swarm **contracts into the ember — a small, dense knot of motes**, softly irregular at its rim, at the surface's edge. **The ember is the direct descendant of Spec 07 §8.4's orb, and supersedes it** (suite-sync X1): same four states, same `m-instant` snap, same push-to-talk gesture target, same muted rendering, now understood as the *contracted swarm* — the one entity gathered small — rather than a separate chrome element. *(v0.2: previously a receded wisp of the veil; the knot of motes is stronger — a contracted swarm is visibly the same substance as the field it came from.)* Speaking from Y2 still animates the ember and captions; a doorway back toward the Stage re-expands ember → field as one continuous morph — the knot loosens and the motes stream back out (P3 — one entity, never a scene swap).

Rules across the ladder: yield transitions are single composed movements (one-mover, Spec 07 §8.2 rule 2 — the part and the card entrance are choreographed as one); views themselves remain 100 % Spec 07's (this spec never restyles an archetype); and *nothing except the user or the turn* changes yield — the swarm never grabs the stage back on its own.

**The shipped home (v0.3).** `main.dart`'s presence-primary screen is the first real cut of the ladder, and it confirms the shape while simplifying the dogfood middle:

- **Y0 as shipped:** Plena full-screen over the warm near-black void; the only chrome is a small **mute control at bottom-left** and a quiet overflow menu. **Tap (or click) anywhere is the speak gesture** — the whole screen is the mic target (one utterance per tap, auto-sent on the final transcript; a second tap aborts; tapping while she speaks barges in). No orb widget, no input chrome in voice mode.
- **Y1 as shipped — the corner-hover:** when a reply is list-shaped, Plena **eases to a corner** (~600 ms settle, remaining fully alive at small size) and the text hovers elegantly over the void beside her in a constrained reading column — the parting realized, for the dogfood, as making-room-by-withdrawing rather than parting-in-place. She returns full-screen when the exchange clears. The full Y1 parting choreography stands as the target for card-bearing surfaces.
- **Y2 as shipped — a recorded debt:** the data and settings pages are still plain pushed routes with no ember; P3's never-despawns is honoured on the home surface only. The ember remains owed (§9.3).

### 6.4 When text appears at all

Owned upstream, listed here for completeness: data read-back and anything list-shaped (Spec 05's flows — voice reads a summary, the card carries the detail), disambiguation candidates (Spec 07 §6.4), errors (Spec 07 §6.6 — errors are content, never toasts), captions always (Spec 07 §7.3), and narration aids at the generative cards' "more on screen" pattern (Spec 05 §16). The default for everything else is **no text** — a `Done` that needs no undo-window glance is a spoken sentence, a bloom, and a line that lingers only at the Stage threshold.

*(v0.3 — the ephemeral exchange.)* The shipped home carries this to its conclusion: **only the current exchange is ever on screen**. The reply materializes over the void as Plena speaks and releases a beat (~1.6 s) after she finishes; there is no scrollback — the v0 chat feed was removed as tech debt rather than restyled. History is not something the home shows; it re-enters only as/when Spec 07 §2.2's Conversation Stream is rebuilt from the turn log as a *visited* surface (a Y2 yield), never as a log the presence sits on top of.

---

## 7. Muted Mode

Muting TTS (one of Spec 07 §7.1's two persisted booleans) changes the *audio*, never the entity:

- **The presence still speaks.** Muted `speak` calls still emit `SpeakEvent`s (Spec 12 §6.3 — guaranteed mechanically), so the speaking state, the cadence envelope, and the assistant caption run identically. The words the user would have heard are exactly the caption text (parity is Spec 07 §7.3's always-on rule; nothing new is needed here — that is the point of D8/07 and this spec inherits it whole). Watching a muted Plenara answer — the swarm swelling through the shape of a sentence it isn't voicing while the words print beneath — is the mode working as designed, not a degraded state.
- **The muted modifier** (§3.2) marks the state visibly and calmly at the swarm's rim, satisfying Spec 07 §8.4's visibly-muted rule in the swarm idiom.
- **Text input:** when input modality is text (Spec 07 §7.1), the quiet overlay's docked field (§7.2) is the persistent affordance — on desktop it is the steady state, focus retained. **Nothing beneath it reflows** (Spec 07 P2, honored absolutely): the swarm neither shrinks nor shifts for the field; the scrim exists only behind the field itself; the calm band beneath the docked field is simply always present while docked. A typed submission animates the same acknowledgment (§5.3) as a spoken one — the presence witnesses typing too.
- **Closed captions** are, precisely, the assistant subtitle slot — already always-on. Muted mode adds no second caption system; it removes the audio and leaves the contract standing (the cognitive-freeness argument of Spec 07 §7.3, restated as presence design: mode switches must cost the user nothing to re-learn).
- *(v0.3 — as shipped.)* Mute is the bottom-left control, and in the dogfood **muting is switching to text mode**: it stops any in-flight speech, drops a hot mic (never leave one live with no way to stop it), and raises the **two-line input bar from off-screen bottom** (~350 ms ease; it also rises when no recognizer exists at all). One control drives both of Spec 07 §7.1's booleans for now; the independent-booleans model remains the target. Captions are unaffected — the exchange still materializes over the void, and muted speech still animates as a silent flourish (§4.1).

---

## 8. The Presence Motion Grammar

### 8.1 Tokens

The five tokens of Spec 07 §8.1 remain the app's motion vocabulary; the presence adds a field-rate register beneath them (suite-sync X2 records these into Spec 07 §8's table at reconciliation):

| Token | Value / character | Governs |
|---|---|---|
| `p-breath` | ~4 s primary / ~26 s drift, sine, seed-phased | idle rhythm (§5.1) — the successor of `m-breathe` on the presence |
| `p-state` | 300–450 ms, emphasized decelerate | base-state morphs, yield-ladder moves (composed with `m-settle` cards) |
| `p-flow` | continuous; `tempo` 0.2–2.0 × resting | internal advection rate — the only unbounded-duration motion in the app |
| `p-cue` | ≤ 500 ms, one-shot, non-repeating | shimmer, bloom, exhale — every §4.4 cue |
| `p-glyph` | draw per-definition, stroke-staggered (core figures 600–900 ms) · flourish ~0.6 s · hold ~0.5 s · rejoin ~1.1 s at `m-drift` character *(v0.3, §5A.4)* | glyph formation (§5A.4) — one-shot, never looping, occupies the `p-cue` slot |
| `p-snap` | ≤ 90 ms | listening acknowledgment; equals `m-instant` |

### 8.2 Rules — Spec 07 §8.2, amended for a living ground

1. **The presence holds the breath budget.** Spec 07 rule 1 allows one `m-breathe` surface per screen; the swarm (or ember) *is* that surface, always. Other breathing surfaces — the locked-value shimmer, the working shimmer (Spec 07 §5.3, §2.4) — render **static-with-sheen at Y0/Y1** and may breathe only when the presence is at Y2 on their surface. (Suite-sync X2 — this is a real amendment to 07, recorded, not smuggled.)
2. **One mover still governs** (Spec 07 rule 2): `p-flow` is ground, not a mover; yield transitions compose with card movements as a single choreography; at most one `p-cue` plays at a time — cues queue at most one deep, then drop (a dropped cue lost nothing: P7 says no cue is ever sole carrier); a glyph (`p-glyph`, §5A.4) occupies the same slot for its whole draw–hold–release life, and glyphs themselves never queue.
3. **Meaning gates motion** (Spec 07 rule 1): every departure from the idle frame traces to a row in §4's tables. There is no "ambient variety" system, no random flourishes. The seed varies *how*, never *whether*.
4. **Text rules unchanged:** condensation is opacity/weight in place (§6.1); Spec 07 rule 4 stands everywhere.

### 8.3 Reduced motion — the still presence (hard requirement)

When the OS reduced-motion flag is set (or the user chooses "still presence" in settings, which must exist independently of the OS flag):

- `p-flow` stops. The swarm renders as a **static per-state figure** — its motes a fixed constellation, frozen mid-breath at its seed's characteristic pose.
- States and difficulty grades remain fully legible through **discrete cross-fades** (≤ 300 ms opacity-only) between per-state static forms: idle (soft, dim), listening (gathered, brighter — plus the caption's live interim, which is itself the strongest listening signal), thinking (dimmer, denser), speaking (brighter; the caption carries the words). Difficulty shows as the same hue/luminance steps, statically.
- All `p-cue` one-shots collapse to their end states; the bloom becomes the `Done` glyph's existing tint beat (Spec 07 §9.3); gestures are dropped entirely (they were never information — P7).
- Presence glyphs do not draw (§5A.7 fence 2): the end-state figure appears as a brief still or the glyph is skipped — default skip; meaning is never lost either way.
- This variant is not a penalty box: it is designed as *the presence, asleep-still but present*, and it must pass the same golden-state legibility tests as the animated tiers (Spec 09 hook, §9.2). It also doubles as render tier T0 (§9.1) — accessibility and performance land on one well-made variant.

### 8.4 Screen readers and the presence

With a screen reader active, app TTS already defers (Spec 12 §6.4). The swarm additionally: exposes a single semantic node ("Plenara — idle / listening / thinking / speaking / muted / text mode", matching Spec 12 §9.5's labeled voice-state chrome), announces base-state changes only (never cues, never difficulty — grade changes are not events a listener needs narrated), and is marked decorative in every other respect so swipe-navigation never lands *inside* the field. Materialized text is ordinary accessible text from the instant it begins condensing (no waiting for the animation).

---

## 9. Render Tiers, Performance & Staging

### 9.1 Three tiers, one director

| Tier | Renderer | Where |
|---|---|---|
| **T2 — the murmuration** | the full GPU swarm: 2,000–6,000 motes, one atlas/instanced pass (`drawAtlas` as shipped), flow-field advection in pooled buffers, the aura underlay, the trail-persistence buffer, glyphs (§2.1, §5A) | **shipped on the Windows dogfood at 2,200 motes (v0.3)**; capable GPUs; the design target |
| **T1 — the reduced swarm** | 300–800 motes, cheaper draw (`drawPoints`/atlas blits), coarser flow sampling, no aura underlay, core glyphs only (§5A.7 fence 5) | instancing-poor platforms; sustained-thermal demotion; mid-tier mobile |
| **T0 — the still presence** | static per-state figures — a fixed constellation per state, cross-fade only (identical to §8.3); no glyphs; no trail buffer | reduced motion; power-saver; GPU-distressed *(v0.3: no longer the ship vehicle — it survives as the reduced-motion/test variant inside the shipped renderer, which snaps a static per-state frame and runs no ticker)* |

All tiers consume the same `PresenceFrame` stream from the same `PresenceDirector` — tier selection is a composition-root decision plus a runtime demotion ladder, and **no behavioral logic lives in any renderer** (P2, P8). The mote budget is fixed per tier at startup (§2.1); demotion switches tiers, never bleeds count mid-tier — density-based LOD keeps the silhouette continuous across the switch. Demotion triggers: frame-time p90 > 12 ms sustained 3 s (T2→T1), > 12 ms again or OS low-power/thermal signal (T1→T0); promotion re-attempts only on app open (never oscillate mid-session). Backgrounded: the director suspends entirely — zero frames, zero uniforms, zero battery.

### 9.2 Budgets (normative, measured like Spec 12 §7.2's)

- T2 swarm: ≤ **2.0 ms GPU** per frame at the full 6k budget on min-spec, **one draw call** (+1 for the aura underlay), plus ≤ **0.8 ms CPU** advection (pooled `Float32List`, allocation-free, SIMD-friendly); T1: ≤ 2.5 ms raster at ≤ 800 motes; T0: zero steady-state cost.
- `PresenceDirector`: ≤ **0.3 ms CPU** per frame, allocation-free in steady state (the frame object is reused or pooled; the glyph annotation is an id + scalar, nothing heap-borne).
- 60 fps interaction target on all tiers; T2 idle may drop to 30 fps (breath at 4 s cannot tell the difference) for battery on mobile — desktop dogfood keeps 60.
- Startup: mote buffers pre-allocated and the flow tile precomputed; the presence is breathing at first paint — it is never a late-arriving decoration.
- *(v0.3 — shipped raster-health rules, normative.)* The trail-persistence buffer is **capped at ~760 px on its longest side** and scaled up on the blit — an uncapped full-resolution per-frame `toImageSync` stalls the raster thread at full-screen. The sim runs **fixed 60 Hz substeps** (capped at 4 per frame, with no time-debt banking past the cap) and repaints **only when a substep actually ran**, so high-refresh displays neither double-deposit nor double-erode the trail; the static path draws direct and never touches the buffer.
- Test hooks (for Spec 09, recorded as suite-sync X7): the director is a pure function — property tests over signal sequences (every `TurnEvent` order the orchestrator can emit maps to a legal frame path; grades monotonic; acknowledgment ≤ 90 ms in frame terms), golden-image tests per (state × modifier × tier) on fixed seeds, glyph-formation goldens (draw-midpoint and held-figure frames for the core set), the full-load ramp-distinguishability assertion (§4.3, §10 item 7), and the frame-budget numbers CI-tracked from the v3 rung like Spec 12's latency table.

### 9.3 Staging — the same skeleton, honestly

Aligned to Spec 07 §10's rungs (structure lands final early; expression is staged):

1. **v1 / v1.2 (now, Windows dogfood):** ship **T0 on the Stage** — the still presence with cross-faded states — plus the calm-band caption region. This *already replaces* the busy indicator and delivers the state vocabulary; it is "functional and clean on the same skeleton." The `PresenceDirector` + `PresenceFrame` land here in final shape, driven by the real `TurnEvent`/`SpeakEvent` streams (and by Spec 14's shipped seam on the dogfood box).
2. **v1.5 (with the voice pipeline, Spec 07 §10 step 2):** `micLevel`-driven listening, the cadence envelope, yield levels Y0/Y2 (the ember subsumes the orb the moment the orb would have shipped — no throwaway orb is built; suite-sync X1 lands here at the latest).
3. **v2:** Y1 parting choreography arrives with the generative/authoring cards it presents.
4. **v3 (the organic rung):** T2 — the full murmuration, the aura underlay, the vital ramp's designed anchors *passing the §4.3 additive-legibility gate* (with Spec 07 Q2's pass), gesture polish, and the **core glyph set** (§5A.8). A re-skin of the director's output, not a re-architecture — the invariant Spec 07 §10 already promises, kept here. The extended glyph set follows post-v3 curation (Q5).

*(v0.3 — how it actually landed.)* The dogfood jumped the ladder: the **animated Plena shipped first** — the `drawAtlas` swarm at 2,200 motes with the aura, the trail buffer, the tuning sheet, and the glyph engine with 49 figures — with T0 surviving as the reduced-motion/test path inside the same renderer rather than as the ship vehicle. The director/renderer split held its shape (per-state parameter targets smoothed by the director half; the painter only reads), though the formal `PresenceDirector`/`PresenceFrame` components are still to be factored out as spec'd, driven by the sealed streams rather than the screen's booleans. Still owed from the rungs: `micLevel` listening (§3.1), the cadence envelope (§4.1), Y1's parting-in-place and Y2's ember (§6.3), the per-install seed (§5.4), and the designed vital-ramp anchors behind the tuning sheet's dialed values.

---

## 10. Accessibility (hard requirements, consolidated)

1. **Contrast — the calm band.** Any text over the field (captions, materialized text, card content at Y1) sits on a calm band: a region where the swarm's local density and luminance are clamped to a band guaranteeing ≥ **4.5:1** contrast with the text color in both themes, and local turbulence/tempo are reduced ≥ 60 %. The band is computed by the renderer from text geometry supplied by layout — never hand-placed — and is the load-bearing answer to "living background, readable words." Verified per tier in the golden tests.
2. **Colorblind-safe difficulty.** P7 enforced: every state and grade differs from its neighbors in at least two of {tempo, coherence, luminance, grain} in animated tiers, and in luminance + form in T0. The vital ramp's hue axis is redundant by construction, and the golden tests include a grayscale-render assertion.
3. **Photosensitivity — no strobing, ever.** Full-field luminance modulation is rate-limited to **≤ 2 Hz** and amplitude-limited (well inside WCAG 2.3.1's three-flashes threshold with margin); the speech cadence pulse (§4.1, ~4–5 Hz syllabic) is therefore expressed through *motion amplitude and grain*, never through luminance flashing; motes never blink in unison; no cue inverts the field; glyph formation is motion, never light (§5A.7 fence 3). These are director-level clamps, testable on the frame stream — not renderer courtesies.
4. **Vestibular safety.** No full-field zoom, rotation, or parallax sweeps; `lean` is capped at a small fraction of field size; yield transitions translate density, not the viewport.
5. **Reduced motion** (§8.3) and **screen-reader deference** (§8.4, Spec 12 §6.4/§9.5) as specified — both are release-gating, same class as Spec 07 §8.2 rule 5.
6. **No information is presence-only** (the mirror of "no information is audio-only," Spec 12 §9.5): every swarm cue — and every glyph, via its `meaningKey` (§5A.7 fence 1) — shadows a card, chip, caption, or attention item that carries the actual content. A user who never looks at the field loses mood, not meaning.
7. **Hue legibility on the additive field (v0.2).** The vital ramp must not white out under additive mote blending: §4.3's constraint is **release-gating** for T2/T1, verified by the full-load ramp-distinguishability golden frames (§9.2). A presence whose effort hue cannot be seen has silently dropped a required expressive channel — §4.2 depends on it.

---

## 11. Suite-Sync Items (for the next reconciliation pass — this spec edits no other file)

- **X1 — Spec 07 §2.1 + §8.4: the orb is subsumed.** §2.1's Stage anatomy inverts (the field is the ground; "the presence — the listening orb" becomes a reference to this spec); §8.4 is superseded by §6.3's ember (same states, gestures, and muted rendering — re-specified as the Y2 form of the one entity) and should shrink to a pointer here; §9.2's "unique per render seed" is extended to the persisted personality seed (§5.4). Retarget Spec 12 §2.1's `micLevel` comment ("the orb's listening amplitude — Spec 07 §8.4") → this spec §3.1. *(Partially landed 2026-07-11: Spec 07 §2.1 now carries the inversion note, §8.4 the supersession pointer, and §2.2/§10/D11 the retirement of the v0 chat seed; Spec 12's retarget and §9.2's seed extension still pending.)*
- **X2 — Spec 07 §8: breath budget + presence tokens.** Rule 1's "at most one `m-breathe` surface per screen" is amended: the presence permanently holds the allowance; locked/working shimmers demote to static-with-sheen when the presence is at Y0/Y1 (§8.2 r1). The `p-*` token register (§8.1) joins §8's table; `m-breathe`'s row notes its successor on the presence is `p-breath`.
- **X3 — Spec 07 §9.3: the vital ramp.** A third, presence-exclusive color family (§4.3) alongside the two semantic colors — with the explicit constraint that no card, chip, glyph (icon glyphs in 07's sense — §5A.2's terminology note), or text may ever use it, so the "two semantic colors beyond neutrals" rule survives for everything that isn't the presence. Anchor values produced together with Spec 07 Q2's design pass, which now also selects the §4.3 additive-legibility mechanism.
- **X4 — Spec 07 §7.3: condensation choreography.** The subtitle slots' visual arrival/release adopts §6.1's grammar (content, slots, discipline, and linger unchanged and still owned by 07); §7.2 gains the note that the docked overlay field sits on a persistent calm band.
- **X5 — Spec 07 §10 staging:** rungs 1–4 gain the presence deliverables of §9.3 here (T0 at v1, director at v1.2, ember-subsumes-orb at v1.5, T2 at v3); Spec 07's v3 "organic pass" line points to this spec as its Stage-side content.
- **X6 — Spec 12 Q6:** record this spec (§4.1) as the customer for TTS word-boundary `SpeakEvent` extensions; the cadence-envelope proxy is the standing v1 answer.
- **X7 — Spec 09:** add the presence test tier — `PresenceDirector` property tests, per-(state × modifier × tier) golden frames on fixed seeds, grayscale-legibility assertion, glyph-formation goldens for the core set, the full-load ramp-distinguishability assertion (§4.3, §10 item 7), and the §9.2 frame budgets as CI-tracked numbers from the v3 rung.
- **X8 — Spec 14:** note that the dogfood presence rung (§9.3 step 1) binds to Spec 14's shipped `SpeechRecognizer` seam until Spec 12's `SpeechInput` lands; no contract change requested.

---

## 12. Decision Record

### Resolved

- **D1 — The presence is the primary surface.** The Stage's steady state is the entity; views are yields of it, not destinations that replace it; the presence never despawns (P1, P3, §6.3). *(§1, §6)*
- **D2 — Substrate: the coherent particle swarm — "the murmuration"** *(v0.2, 2026-07-11; supersedes v0.1's smoke veil after the first live mockup)*: 2,000–6,000 motes, one `drawVertices`/instanced pass, the shared-flow-field + core-cohesion model (coherence is a parameter, not an achievement), fixed per-device mote budget with density-based LOD, resting micro-flow for idle. Decisive: the swarm's native gesture vividness, and the glyph register (§5A) — a capability categorically closed to a continuous field. The veil is retained as the documented alternate, driven unchanged by the same `PresenceFrame`; aurora ribbons stay rejected. *(§2)*
- **D3 — One pure director, one frame vector, three tiers.** `PresenceDirector` consumes only the sealed streams and projections (Spec 07 P5 tightened); `PresenceFrame` is the entire renderer contract; T2/T1/T0 differ in fidelity never meaning, with an automatic demotion ladder and T0 doubling as the reduced-motion variant. *(§2.4, §8.3, §9.1)*
- **D4 — Base states are Spec 12's four, unforked**; everything else is a modifier with a single upstream source of truth; into-listening snaps ≤ 90 ms and never leads the mic. *(§3)*
- **D5 — Speech sync runs on the cadence-envelope proxy** (text-derived, `SpeakEvent`-anchored), upgraded to word boundaries if Spec 12 Q6 resolves; no system-audio taps. *(§4.1)*
- **D6 — Difficulty is the five-grade operational ladder** (D0 effortless → D4 can't) built from existing signals; grades are monotonic per turn; the ceiling is *quieter*, not louder; every grade moves ≥ 2 non-hue channels. *(§4.2)*
- **D7 — The vital ramp** is a presence-exclusive third color family; the assent and attention moments reuse Spec 07's two existing semantic colors, so the app-wide vocabulary does not grow for anything that isn't the presence. *(v0.2 addendum:)* the ramp's legibility on the additive mote field is a release-gating design-pass constraint — aura underlay, constrained buildup, or separated/floored anchors, selected in Q3's pass, verified by golden frame. *(§4.3, §10 item 7)*
- **D8 — Personality = breath + five gestures + timing asymmetry + a persisted seed**; no user tuning in v1; the anthropomorphism fence is absolute ("would weather do it?"). *(v0.2: amended by D13 — the glyph register is the one fenced figurative exception, tightened rather than loosened; the gesture budget of five and the body-fence stand unchanged.)* *(§5)*
- **D9 — Text condenses in place** (opacity/weight, never position — Spec 07 §8.2 r4 preserved); the **yield ladder** (Y0 field / Y1 parting / Y2 ember) is the explicit seam with Spec 07's views, and the ember supersedes the orb as the one entity's contracted form. *(§6)*
- **D10 — Muted mode is inherited, not invented:** muted `SpeakEvent`s (Spec 12 §6.3) + always-on captions (Spec 07 §7.3) + the no-reflow overlay (Spec 07 P2) already compose the design; this spec adds only the muted rim treatment and the docked-field calm band. *(§7)*
- **D11 — Accessibility clamps live in the director**, not the renderers: calm-band contrast ≥ 4.5:1, ≤ 2 Hz full-field luminance modulation (cadence goes to motion, not light), no presence-only information, vestibular caps — all frame-stream-testable. *(§10)*
- **D12 — Chartered as Spec 15**, not 07a: lettered docs in this suite are working artifacts; normative specs take top-level numbers (Spec 12 precedent). All 07 touchpoints recorded as X1–X5 rather than edited in place. *(header, §11)*
- **D13 — The symbolic glyph vocabulary (v0.2).** Glyphs are a figurative register distinct from the five gestures, governed by **apt-or-absent**: a glyph fires only when semantically apt to the app's actual action (a heart for closeness logged, never for a todo added), and most turns fire none. Data-defined line-figures (ordered strokes + dots in normalized presence-space) traced by ≤ 15 % of the swarm's motes on `p-glyph`, one per turn, ≥ 90 s apart, ~8/day soft cap, signal-traced always. Fifty curated: fifteen core with the v3 rung, thirty-five extended behind Q5. AI selects or composes within the schema; code executes; never the sole carrier of meaning; stills-or-skips under reduced motion; the kitsch fence is tightened, not loosened ("would a considered hand sketch it in one or two strokes?"). *(§5A)* *(v0.3: formation re-specified to the comet-trail mechanic — Plena flies the path and sheds her tail, §5A.4; the ≤ 15 % in-place assignment cap is superseded by ~600 sparse faint deposits with most of the body in flight; selection ships as `glyphForTurn` in `glyphs.dart`.)*
- **D14 — Plena, shipped (v0.3, 2026-07-11).** The entity is named **Plena**. The first implementation ships the animated swarm ahead of the ladder (`drawAtlas` at 2,200 motes, aura underlay, capped trail-persistence buffer) and the **presence-primary home**: Plena and a bottom-left mute control are the whole steady-state UI; tap-anywhere is the speak gesture; list-shaped content earns the corner-hover while the text hovers over the void; the exchange is **ephemeral** (no scrollback — the v0 chat feed is deleted); muting switches to text mode and raises the two-line input bar from below. Glyphs form as comet trails — she flies the figure's path, sheds a ~0.19-alpha tail that holds the shape, and it rejoins her — and the occasion mapping is code. The tuning sheet (hue / vibrance / brightness / breadth / gravity / looseness / trail) is a dogfood instrument for converging on curated constants, not a shipped preference. *(§0, §2.1, §5A.1, §5A.4, §6.3–§6.4, §7, §9.3)*

### Open

- **Q1 — Swarm viability on the dogfood box.** `drawVertices`/instanced throughput at 2–6k motes, the CPU advection budget (§9.2), and the aura underlay's cost need a spike on Windows desktop before T2 is scheduled; T1 is the hedge and T0 ships regardless. Pairs with Spec 12 §10.1's Windows spike so one instrumentation pass measures both. (The veil's `FragmentProgram` pipeline spike folds in here only if the alternate is ever activated, §2.2.) *(v0.3: substantially answered — `drawAtlas` at 2,200 motes plus the capped trail buffer holds up full-screen on the dogfood box; what remains is measured headroom toward 6k, and mobile.)*
- **Q2 — Envelope fidelity.** Whether the syllable-heuristic cadence reads as "in unison" at conversational distance, and per-engine drift over long utterances — judged by eye in the v1.5 dogfood; escalates the priority of X6 (word boundaries) if it disappoints.
- **Q3 — Vital-ramp anchors, aura design, and additive legibility** await the same visual-design pass as Spec 07 Q2 (real mockups, both themes, contrast-checked against the calm band); mechanisms here are decided regardless. *(Extended v0.2:)* the pass must **select the mechanism(s)** by which the ramp survives additive blending — aura underlay, constrained buildup / density cap, separated anchors with saturation floors (§4.3) — and the full-load ramp-distinguishability golden frame gates the v3 rung (§10 item 7). The mockup's white-out fireball is the failure this Q exists to keep from recurring. *(v0.3: mechanism selected and shipped — the aura underlay plus alpha caps, §4.3; the hue-shifting fireball core is now the designed look. What remains: the golden-frame gate, the designed anchor values behind the tuning sheet's dialed defaults, and the light theme.)*
- **Q4 — The wake-word "armed" reading** (co-owned with Spec 07 Q3, gated with Spec 12 Q3): how idle-but-armed differs visibly from idle-and-off without reading as surveillance. Candidate direction — armed is *slightly more gathered*, never brighter — needs the ambient-rung design pass.
- **Q5 — Glyph repertoire calibration** *(repurposed v0.2 — the original keep-or-cut-motes question is moot: the body is motes)*: whether §5A.5's caps feel right in the dogfood (too chatty vs. never seen), whether apt-or-absent is holding in practice (no glyph should ever draw a "why did that appear?" — §5A.1's test, checked against real transcripts), which †-marked figures actually read at T1 counts, and which extended glyphs earn promotion to core — or removal — after the v3 pass. *(v0.3: the calibration instruments exist — 49/50 figures authored as data, the long-press dev preview cycling the vocabulary, and the live occasion mapping in `glyphForTurn` — so this Q is now answerable from real dogfood use.)*
- **Q6 — Seed portability.** Whether the personality seed syncs across the user's devices (one being everywhere) or stays per-install (each device its own sibling) — a product-feel call with a trivial mechanism either way; decide with Spec 06's settings-sync posture.
- **Q7 — Difficulty-grade thresholds.** D1's 400 ms and the demotion ladder's numbers are launch guesses; calibrate against Spec 12 §7.2's measured budgets during the dogfood so "working" never fires on a healthy fast turn.

---

*End of Spec 15 — The Living Presence v0.3*
