# Spec 15 — The Living Presence

**Status:** Draft v0.1 — July 2026 (Fable 5). First full draft of the voice-first visual experience: the presence as the app's primary surface — the substrate, the presence state machine, the signal→visual expressive mapping, the disembodied personality rules, text materialization and yielding choreography, muted-mode visuals, the presence motion tokens, render tiers and perf budgets, and the accessibility constraints a permanently-moving surface must satisfy.
**A note on numbering:** this document is intimately a companion to Spec 07 — it deepens §2.1's Stage and §8.4's orb from "chrome" into the primary interface — and a lettered `07a` was considered. Rejected: in this suite, lettered companions (05a–05f) are *working artifacts* — trace rigs, gap registers, review logs — not chartered normative specs, and a normative spec takes a top-level number even when it exists to complete another (precedent: Spec 12's chartering note, which took slot 12 rather than `06a`). Slots 13 and 14 are occupied; this is **Spec 15**. Everything it extends or supersedes in Spec 07 is recorded explicitly as suite-sync items in §11, the way Spec 12 records its retargets — this spec edits no other file.
**Depends on:** Research doc (§2.1–2.3, §6.2, §11.3–11.5, §15.1); Spec 04 — Architecture (§2.2 layer rules, §3.6 `TurnEvent` stream + `DispatchOrchestrator`, §3.12 `AttentionSurface`, §4.3 barge-in, §4.7 detached ops, §5.2 error surfaces); Spec 05 — Functional (§3 act-then-describe, §13 offline/subtitle/quiet-overlay behavior); Spec 07 — UI & Design-Language (§2.1 the Stage, §6 turn cards, §7 quiet overlay & subtitles, §8 motion tokens & the orb, §9 typography/shape/color, §10 staging); Spec 08 — AI Cost & Privacy (§3.1 cloud latency, §5.2 residual routing — the "difficulty" signals of §4.2); Spec 12 — Voice (§2.1 `micLevel` + `SpeakEvent`, §4 transcript semantics, §6.3 muted `SpeakEvent`s, §7.2 latency budgets, §9 voice errors)
**Blocks:** Spec 09 — Test (the `PresenceDirector` property tests and golden-frame tier of §9.2 here); the v3 organic rung (Spec 07 §10 step 4 — this spec is that rung's normative content for the Stage); Spec 07's Q3 (wake-word "armed" reading — co-owned here as Q4)

---

## 0. Purpose & Scope

Spec 07 built the design language for Plenara's *views* — archetypes, turn cards, typography — and gave the voice loop a single piece of persistent chrome: the listening orb (§8.4), "an organic, softly irregular form" with four states. That was the seed. This spec grows the seed into the product owner's actual vision: **the interface is not an app that contains an assistant indicator — it is an entity you are talking with.** The screen at rest *is* the presence: an ethereal, quietly alive field that fluctuates with its speech, shifts hue with effort, and has a disembodied visual personality. Text is not the medium; text *materializes* when needed — read-back, lists, narration aids, captions — and dissolves back into the field. When muted, the presence keeps speaking visually while captions carry the words.

This document specifies:

1. **The substrate** — the one normative visual medium the presence is made of, its named alternates and their tradeoffs, and the Flutter rendering strategy with a frame budget (§2)
2. **The presence state machine** — the base states (aligned exactly to Spec 12's vocabulary), the modifiers layered over them, and what the substrate *does* in each (§3)
3. **The expressive mapping** — the concrete table from system signals (TurnEvents, mic level, SpeakEvents, tier/latency class, attention state) to the presence's parameter vector (§4)
4. **The disembodied personality** — the rules that make the presence read as alive-but-calm without a face, and the ban on anthropomorphic kitsch (§5)
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

**P4 — Expressive, never anthropomorphic.** The presence has no face, eyes, mouth, limbs, silhouette, or avatar form — ever, at any render tier, in any state. Its emotional vocabulary is entirely abstract: energy, coherence, tempo, hue, luminance, grain. This is a hard rule, not taste: a face invites social-presence expectations the system cannot honor (gaze, emotion reading, embarrassment), turns latency into "it's ignoring me," and ages into kitsch. The presence is weather, not a creature.

**P5 — Quiet by default (Spec 07 P8, applied to a living thing).** Alive-but-calm means the idle amplitude budget is tiny and fiercely defended: at rest the field moves at breath scale (§3.1) and nothing more. The presence never performs, never fidgets, never reacts to pointer movement or scrolling, and spends its expressive range only when meaning changes. A presence that is always interesting is an app that is always tiring.

**P6 — Text materializes; it never intrudes.** Text appears only when it carries something voice alone cannot (read-back, lists, disambiguation candidates, captions, errors) — Spec 07's surfaces decide *when*; this spec makes their arrival feel like condensation, not like a dialog landing on top of a screensaver. And per Spec 07 §8.2 rule 4, materialized text never moves positionally: it condenses and dissolves *in place* (§6.1).

**P7 — No state is carried by hue alone.** Every presence state and every difficulty grade is legible with color vision deficiency, on a grayscale screen, and in the reduced-motion variant: hue is always paired with at least one of tempo, coherence, luminance, or grain (§4.3, §10.2). This is the accessibility corollary of the product vision's "hue changes with difficulty" — hue is the *poetry*, never the sole *information*.

**P8 — Beauty degrades gracefully.** The presence has three render tiers (§9.1) and an automatic demotion ladder driven by measured frame time and platform power state. Tier demotion changes *fidelity*, never *meaning*: the same `PresenceFrame` drives every tier, so a low-power static presence still shows the same states, the same difficulty encoding, the same captions. GPU trouble is never allowed to become UX trouble (Spec 04 P2.8, visually).

---

## 2. The Substrate

### 2.1 The decision: a volumetric smoke field — "the veil"

**The presence's normative substrate is a continuous volumetric smoke/nebula field** — soft, self-luminous vapor with visible internal flow, no hard boundary, rendered as a GPU fragment shader. Working name: **the veil**. In its resting form it occupies a soft-edged region roughly the upper two-fifths of the Stage (one-handed reach keeps interaction in the bottom third, Spec 07 §9.4), densest at a drifting core and feathering to nothing — the screen never shows a "shape with an edge," it shows *where the substance happens to be*.

Why smoke over the alternatives, on both axes the choice must satisfy:

- **Feel.** A continuous field reads as *one* substance breathing — coherence is its native state, which suits an entity whose default demeanor is calm (P5). Its expressive range maps naturally onto the signals we have: flow speed is tempo, density is presence, internal turbulence is effort, luminance swell is speech. Smoke also fails gracefully: an under-animated particle swarm looks broken; an under-animated smoke field just looks *still*, which is exactly what reduced-motion and low-power tiers need (§8.3, §9.1).
- **Flutter feasibility.** A fragment shader (Flutter `FragmentProgram`, `.frag` compiled through impellerc — supported on Impeller across our targets, including the Windows dogfood platform) renders the whole field in **one draw call over one bounded quad**: 3–4 octaves of curl-advected simplex noise, domain-warped, tone-mapped, driven entirely by ~16 float uniforms. Cost is resolution-bound and constant — no per-element CPU work, no allocation, no jank cliff as expressiveness rises. A CustomPainter fallback (§9.1 T1) can approximate it with layered soft-blurred blobs when shaders are unavailable. Shader-compilation jank is mitigated by precompilation at first launch (Impeller's ahead-of-time pipeline state) — the presence must never stutter into existence.

**The accent layer — motes (optional, bounded).** The veil may carry at most **240 motes**: tiny luminous particles that condense out of the field for punctuation — the Done bloom (§4.2), the undo afterglow (§4.4), the gather toward a clarification (§3.2). Motes are an accent, never the body: they are drawn in the same pass or a single `drawVertices` call, capped, and entirely absent at tiers T0–T1. If the v3 design pass finds they read as glitter, they are cut without structural loss (Q5).

### 2.2 Named alternates and their tradeoffs

- **A coherent particle swarm** (2,000–6,000 particles, GPU-instanced or `drawVertices`). Stronger at *gesture* — gather, scatter, lean read vividly when thousands of individuals move as one — and inherently "digital," which some will prefer to vapor. Rejected as primary: coherence must be continuously *earned* (flocking simulation on the CPU or a compute-style shader trick), idle looks either frozen or restless with little in between, and the per-particle budget varies with count and platform where the shader field's cost is flat. Kept as the named alternate if the veil disappoints in the v3 design pass — the `PresenceFrame` vector (§2.4) was designed to drive either.
- **Aurora / ribbon field** (a few luminous flowing bands rather than a volume). Cheapest of all and elegant, but its expressive range is narrow — bands can flow and glow but cannot convincingly *gather*, *part*, or *grain up* under effort — and it tends to read as decoration rather than entity. Rejected; noted because tier T1 (§9.1) borrows its cheapness.

### 2.3 What the veil is not

Not a wallpaper (it responds within 90 ms to state changes, §3.3), not a music visualizer (it never free-runs on audio energy; every motion is a state or signal, P5), not full-screen fog (materialized text and views sit on calm ground, §6; the field guarantees them contrast, §10.1), and not a brand mascot (P4).

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

Rates of change are governed by the motion grammar (§8.1) — the director interpolates; renderers never animate on their own. The vector is deliberately renderer-agnostic and small: it is the whole contract between "what the presence feels" and "how the presence looks," which is what makes tiers, golden tests, and a future substrate swap all cheap.

---

## 3. The Presence State Machine

### 3.1 Base states — Spec 12's vocabulary, exactly

The base states are **idle / listening / thinking / speaking** — the same four Spec 07 §8.4 gave the orb and Spec 12's pipeline events imply. This spec adds no fifth base state: transitional and degraded conditions are *modifiers* (§3.2), so the base machine stays in lockstep with the turn lifecycle and Spec 12's semantics are never forked. What the veil does in each:

| State | Entered on | The veil |
|---|---|---|
| **idle** | app at rest; empty final; turn terminal events settled | **Breathing.** `energy ≈ 0.08`, `tempo 1.0`, high coherence, resting hue, slow toroidal drift of the core on a ~4 s sine (`m-breathe`). Nothing else. At a glance across a room it should be *just barely* discernibly alive. |
| **listening** | capture session live (mic open ⇔ listening, Spec 12 §3.5 — the veil must never claim listening when the mic is closed, and vice versa) | **Gathering, attentive.** Coherence rises toward 0.9 (`m-instant` snap into the state, per Spec 07 §8.4 — responsiveness beats smoothness here); `energy` rides the smoothed `micLevel` stream so the user *sees being heard* — the field's surface shivers with their own voice. Slight `lean` toward the subtitle region, where their words are condensing (§6.2). |
| **thinking** | final transcript dispatched; `TurnStarted` → pre-`Done` | **Turning inward.** Coherence high, `tempo` drops to ~0.7, luminance dips a shade, internal flow becomes visibly *convective* — the substance folds into itself. This state replaces every spinner in the app (Spec 07 §2.1). Its expression deepens along the difficulty ladder (§4.2) the longer it holds. |
| **speaking** | `SpeakEvent.started` → `finished`/`stopped` (Spec 12 §2.1) | **Fluctuating in unison with speech.** `energy` and `luminance` follow the speech envelope (§4.1) — swells at phrase scale, shimmer at cadence scale; coherence moderate; a gentle `lean` toward the listener (screen-center-down). Muted changes nothing here (§7): `SpeakEvent`s still fire (Spec 12 §6.3). |

### 3.2 Modifiers — layered, not forked

Modifiers adjust the active base state's frame; several can hold at once. Each has exactly one source of truth upstream:

- **clarifying** (`ClarificationRequested` outstanding): the veil gathers tighter and leans toward the question's chips — a listener waiting on an answer, not an alarm. Holds until `respond()` resolves the prompt.
- **effortful** (difficulty grade D1–D3, §4.2): hue cools along the vital ramp, turbulence rises. The visible truth of "this one is costing something."
- **attending** (`AttentionSurface` non-empty): one mote orbits slowly at the field's periphery — the veil's echo of the Stage chip (Spec 07 §6.7), same information, zero urgency, no red (P8 of 07).
- **afterglow** (undo window live, Spec 04 §3.11): a soft warmth at the field's lower edge, nearest the lingering `Done` line, fading exactly when the undo chip fades — the visual statement that the last act is still soft-set (Spec 07 P6).
- **muted** (TTS muted, Spec 07 §7.1): a thin, still desaturation at the field's rim — visibly muted, calmly so (extends Spec 07 §8.4's "a muted orb renders visibly muted"). Speech states still animate fully (§7).
- **degraded** (any `VoiceError` state — mic denied, STT unavailable; Spec 12 §9.2): the veil slows to ~0.8 tempo and desaturates slightly; the honest words live in the caption/attention surfaces where Spec 12 put them. The presence *never* pantomimes an error; it just visibly has less voice.
- **error beat** (`TurnError`): one slow exhale — a single coherence drop-and-recover over ~900 ms — then back to idle. The card carries the content (Spec 07 §6.6); the veil only acknowledges. No flare, no shudder, no red.

### 3.3 Transition rules

1. **Into listening: snap.** ≤ 90 ms (`m-instant`) from press to visible gathering — the one transition where quickness beats smoothness (Spec 07 §8.4), and it must not lead the mic (Spec 12 §3.5's invariant binds the visual too).
2. **Everything else: settle.** Base-state morphs interpolate over 300–450 ms with `m-settle` character; modifiers fade in/out at `m-quick`. The veil never cuts.
3. **Barge-in** (Spec 04 §4.3, Spec 07 §7.4): speaking halts as a soft fade *within* Spec 12's ≤ 150 ms stop budget — the envelope collapses, not the field — and the gather-to-listening rides the same beat. One motion, two meanings.
4. **No state theater.** A sub-perceptual turn (corpus hit inside Spec 12 §7.2's 1.0 s end-to-end budget) may pass through thinking so briefly it never visibly expresses; the director must not stretch states to "show work" that didn't happen. Honesty over drama.

---

## 4. The Expressive Mapping

The crux: every aesthetic behavior lands as a signal→parameter rule. The director implements this table and nothing not in this table (P5: no free expression).

### 4.1 Speech → fluctuation

The vision asks for the field to "fluctuate beautifully in unison with its speaking." The obstacle is honest: **platform TTS engines do not expose a realtime output-amplitude stream** (Spec 12 §6.1's matrix — none of the three publishes synthesis PCM to the app by default). The design therefore runs on a **cadence-envelope proxy**, upgraded when real timing data exists:

- **v1 proxy — the synthesized envelope.** When `speak(text)` is issued, the director derives a deterministic envelope from the *text itself*: syllable count estimation (vowel-group heuristic — cheap, locale-tolerant) sets a pulse train at spoken-syllable rate scaled to the configured TTS rate; punctuation and clause boundaries insert phrase-scale swells and dips; expected duration is estimated from character count × rate and **re-anchored against reality** at `SpeakEvent.started` and truncated at `finished`/`stopped`. The envelope drives `energy` (primary) and `luminance` (phrase-scale swells only — see the photosensitivity clamp, §10.3). Result: the veil breathes *with the shape of the sentence* — provably in sync at start/stop, plausibly in sync within — which observation of ambient-companion products suggests is fully sufficient at conversational glance distance. It will drift on long utterances; long utterances are already capped by the subtitle length discipline (Spec 07 §7.3).
- **Upgrade path — word boundaries.** If/when TTS word-boundary callbacks prove reliable cross-platform, Spec 12 carries them as `SpeakEvent` extensions (its Q6) and the director snaps the envelope to real word onsets. This spec is the *customer* of that question (suite-sync X6); the proxy is designed so the upgrade changes fidelity, not architecture.
- **Never raw audio taps.** The director does not capture system audio output to measure amplitude — a loopback tap would be platform-fragile and sits badly against Spec 12 §8's "audio never exists" posture even though output ≠ capture. The envelope is computed from text the app already holds.

### 4.2 Difficulty → hue, luminance, turbulence

"Difficulty" is defined operationally as a **ladder of effort grades**, each detected from signals that already exist — nothing new is instrumented:

| Grade | Operational trigger | Veil expression |
|---|---|---|
| **D0 — effortless** | corpus-hit local turn resolving inside the p50 budget (Spec 12 §7.2) | None. The high-confidence band shows nothing extra (Spec 07 §6.3's quiet), and neither does the veil. Most turns are D0 and *look* like it — that restraint is what makes D2 legible. |
| **D1 — working** | thinking state persists > 400 ms (local compute, long queries) | `tempo` −20%, `luminance` −1 step, convection deepens. No hue shift yet. |
| **D2 — reaching** | a cloud round-trip is in flight: residual routing or a generative/authoring detached op attributable to the live turn (Spec 04 §3.6/§4.7; Spec 08 §3.1's ~0.8–1.2 s) | hue cools to the ramp's far third (§4.3), fine-grain `turbulence` rises to ~0.5 — visible concentration. The user learns, wordlessly, what "thinking hard" (and, on the paid tier, "spending") looks like. |
| **D3 — struggling** | `ClarificationRequested`; a below-ASR-floor re-ask (Spec 12 §4.6); a `Correct` reversal in flight (Spec 05 §3.3) | D2's expression **plus** the clarifying gather (§3.2) and a half-step luminance *rise* — leaning in, asking. Never agitation: struggle reads as increased attention, not distress. |
| **D4 — can't** | `TurnError`; degraded voice states (Spec 12 §9.2) | The error beat / degraded modifier (§3.2): slower, stiller, slightly desaturated. Difficulty at its ceiling is *quieter*, not louder — the inversion that keeps failure calm (Spec 04 P2.8's surfaces carry the content). |

Every grade changes **at least two non-hue channels** (P7). Grades are monotonic within a turn (a turn may climb the ladder, never oscillate on it) and clear with the turn's terminal event.

### 4.3 The vital ramp — the presence's color system

Spec 07 §9.3 permits exactly two semantic colors beyond neutrals and reserves the 12-hue accent ramp for *type identity*. The presence needs a hue dimension and must not raid either. The resolution (suite-sync X3): the presence gets its own **vital ramp** — one continuous, narrow band of desaturated hues, exclusive to the veil, never used by any card, chip, glyph, or text:

- **Resting third** (`hueShift ≈ 0`): a warm near-neutral glow, barely distinguishable from the base surface's warmth — the presence at rest is *almost* the color of the room.
- **Effort third** (`hueShift → −1`, grades D2–D3): a cool drift — think pre-dawn blue-violet — always paired with turbulence/tempo changes (P7).
- **Assent accent** (`hueShift → +1`, momentary): the `Done` beat borrows Spec 07 §9.3's single confirmation-positive tint for a one-breath bloom coinciding with the `Done` line and glyph — the same semantic color, so the vocabulary stays at two.
- The **attention hue** appears in the veil only as the attending mote's tint (§3.2) — again the existing semantic color, not a new one.

Saturation across the entire ramp stays low (the veil is vapor, not neon), the exact anchor values are produced by the same visual-design pass as Spec 07 Q2's accent ramp (they must sit correctly against both themes), and the ramp ships as tokens, not literals.

### 4.4 Turn-contract cues, harmonized with Spec 07 §6

| System moment | Spec 07's surface (unchanged) | The veil's cue (this spec) |
|---|---|---|
| `Done` (act-then-describe) | `Done` line + undo chip (§6.2) | One-breath assent bloom (§4.3), then the **afterglow** modifier for exactly the undo window |
| Moderate-band routing (`Routing` advisory) | routing chip (§6.3) | A single soft shimmer across the field at the chip's arrival — a raised eyebrow, sub-500 ms, once |
| Clarification | question line + choice chips (§6.4) | clarifying gather + lean toward the chips; holds until resolved |
| Non-undoable deletion confirm | the one modal (§6.5) | The veil **stills almost completely** behind the sheet — held breath. The app's sole heavy surface gets the presence's sole full stop. |
| Residual offer / `Detached` | offer line / working entry (§6.6) | Nothing / a barely-visible peripheral circulation while the op runs (the Operation Center's shimmer, echoed at whisper level) |
| Attention item arises | Stage chip (§6.7) | attending mote (§3.2) |

The rule of the table: **the cards carry information; the veil carries demeanor.** No cue in the right column is ever the only signal of anything (P7 and Spec 07 P1 both demand it).

---

## 5. The Disembodied Personality

Personality with no body is *timing, restraint, and idiosyncrasy* — nothing else is available, which is a discipline, not a poverty.

### 5.1 Breath

The idle loop is a compound rhythm, not a sine: a ~4 s primary swell (`m-breathe`) carrying a slower ~26 s drift of the core's position, with per-install phase offsets from the seed (§5.4). Amplitude is clamped so that a screenshot of idle and a 2-second glance at idle are *both* unmistakably calm — the motion is discovered, not announced. After 90 s without interaction the swell shallows a further 40 % (resting deeper); any signal restores it instantly. The veil holds the screen's **one** `m-breathe` allowance (Spec 07 §8.2 rule 1) — the breath-budget consequences are §8.2.

### 5.2 Gesture vocabulary — five, total

All presence gestures are motions *of the field*, drawn from a closed set: **gather** (coherence up — attention), **lean** (core drift toward a screen region — orientation toward the subtitle, a chip set, a materializing card), **bloom** (the one-breath assent swell), **part** (the field thinning to make room, §6.3), **exhale** (the error beat's drop-and-recover). No new gesture ships without a rule in §4's tables. Five is the budget because a creature with fifty gestures is a performer, and a performer is exhausting to live with (P5).

### 5.3 Reaction timing is the personality's spine

- **Acknowledgment is instant:** any user-initiated signal (press, speech onset, typed submit) is reflected in the field within 90 ms (`m-instant`) — the presence *never* leaves the user unwitnessed.
- **Expression is unhurried:** everything that is not acknowledgment moves at `m-settle` pace or slower. Quick to notice, slow to emote — that asymmetry *is* the character: attentive, unflappable.
- **Silence is honored:** no speech, no turn → no motion beyond breath. The presence never fills a pause, never solicits, never demonstrates aliveness it isn't using (the wake-word-era "armed" reading is Q4).

### 5.4 The seed — consistent idiosyncrasy

A 32-bit **personality seed** is minted at install and persisted (extending Spec 07 §9.2's "unique per render seed" from per-render to per-*being* — suite-sync X1): it fixes the noise-field basis, breath phase offsets, core drift path bias, and mote condensation pattern. Two installs are visibly siblings, not twins; one install is *the same entity* every single day. The seed is the personality-consistency knob: v1 exposes no user tuning (curated, Spec 07 P8), and the seed's place in device migration/sync is Q6. Everything else about the personality — timing constants, gesture budget, amplitude clamps — is fixed in tokens, identical for everyone: Plenara has *a* character, not a character editor.

### 5.5 The kitsch fence (P4, enforced)

Never: eyes, face, mouth, blinking, emoji-affect, head-nod/shake motions, heartbeat pulses, "sleeping z" idles, seasonal costumes, or reactive cursor-following. Never sadness-theater on errors or celebration-theater on streaks (the streak lens carries its own quiet reward, Spec 05 §8 — the veil does not throw confetti). The test for any proposed behavior: *would weather do it?* Weather gathers, stills, glows, and parts; it does not wink.

---

## 6. Text Materialization & Yielding

### 6.1 The choreography: condensation and release

All presence-adjacent text obeys one arrival/departure grammar, layered on Spec 07's typography (§9.1) without violating §8.2 rule 4 (*text does not move positionally*):

- **Condense (arrive):** the field locally brightens and calms beneath the text's final position over ~120 ms; the text then resolves *in place* — opacity 0→1 with a slight weight/tracking settle (a `m-quick` solidify, exactly the mechanic Spec 07 §7.3 already uses for the interim transcript). Letters never fly, slide, or assemble. The impression is fog condensing into legibility.
- **Release (depart):** opacity fades (`m-quick`), then the local calm band relaxes over ~400 ms (`m-drift`). Exits are always softer than entrances (Spec 07 §8.2 rule 3). Nothing is ever wiped, swiped, or collapsed.
- The **calm band** — the local region of clamped turbulence and luminance beneath any live text (normatively specified in §10.1) — is what lets text and field coexist: the field is alive around words, never *under* them.

### 6.2 The subtitle slots

Spec 07 §7.3's two-slot contract is adopted wholesale — user slot (interim, dimmed-provisional, solidifies on final), assistant slot (whole-line on speech start, 4 s linger), two-line discipline, always-on. This spec adds only: both slots render inside the veil's lower margin on a calm band; the interim slot's provisional dimness reads as *not yet condensed* (the metaphor and the mechanic finally coincide); and the assistant slot's release re-joins the field per §6.1. Slot ownership, content, and timing remain Spec 07's; Spec 12 §4.3's ownership line is untouched.

### 6.3 Yielding — the seam with Spec 07's views, drawn explicitly

The hard question: Plenara *has* real views — archetype homes, the Stream, the Operation Center (Spec 07 §2–§3) — and the vision says the app must never feel like "a normal app with flat lists." The seam is the **yield ladder**: three named degrees of `veilYield`, and every surface in Spec 07 §2 sits at exactly one of them.

- **Y0 — the field (yield 0).** The Stage. The veil is the ground; the ambient cards (at most three, Spec 07 §2.1) float *on* it in its lower region, each on its own calm band; the lingering `Done` line sits at the threshold. The Stage's steady state is the entity, not a layout that includes an orb (supersedes Spec 07 §2.1's anatomy ordering — suite-sync X1).
- **Y1 — the parting (yield ≈ 0.5).** Turn-scoped content that arrives *in conversation*: result cards, generative cards, the authoring preview, clarification chip sets, search results (Spec 07 §6). The veil **parts** — thins and drifts toward the top and edges over `m-settle`, remaining fully visible as living margin — and the card materializes on the ground it exposed (condensation grammar for its text, doorway transition intact, Spec 07 §8.3). The presence is visibly *presenting* the card, the way a hand presents a page. When the card releases, the field refills (`m-drift`).
- **Y2 — the ember (yield 1).** Immersive surfaces: an archetype home opened full (Collections), deep Stream scrollback, the Operation Center, Settings. The veil recedes into a small, soft, softly-irregular form at the surface's edge — **the ember is the direct descendant of Spec 07 §8.4's orb, and supersedes it** (suite-sync X1): same four states, same `m-instant` snap, same push-to-talk gesture target, same muted rendering, now understood as the *contracted form of the one entity* rather than a separate chrome element. Speaking from Y2 still animates the ember and captions; a doorway back toward the Stage re-expands ember → field as one continuous morph (P3 — one entity, never a scene swap).

Rules across the ladder: yield transitions are single composed movements (one-mover, Spec 07 §8.2 rule 2 — the part and the card entrance are choreographed as one); views themselves remain 100 % Spec 07's (this spec never restyles an archetype); and *nothing except the user or the turn* changes yield — the veil never grabs the stage back on its own.

### 6.4 When text appears at all

Owned upstream, listed here for completeness: data read-back and anything list-shaped (Spec 05's flows — voice reads a summary, the card carries the detail), disambiguation candidates (Spec 07 §6.4), errors (Spec 07 §6.6 — errors are content, never toasts), captions always (Spec 07 §7.3), and narration aids at the generative cards' "more on screen" pattern (Spec 05 §16). The default for everything else is **no text** — a `Done` that needs no undo-window glance is a spoken sentence, a bloom, and a line that lingers only at the Stage threshold.

---

## 7. Muted Mode

Muting TTS (one of Spec 07 §7.1's two persisted booleans) changes the *audio*, never the entity:

- **The presence still speaks.** Muted `speak` calls still emit `SpeakEvent`s (Spec 12 §6.3 — guaranteed mechanically), so the speaking state, the cadence envelope, and the assistant caption run identically. The words the user would have heard are exactly the caption text (parity is Spec 07 §7.3's always-on rule; nothing new is needed here — that is the point of D8/07 and this spec inherits it whole). Watching a muted Plenara answer — the field swelling through the shape of a sentence it isn't voicing while the words print beneath — is the mode working as designed, not a degraded state.
- **The muted modifier** (§3.2) marks the state visibly and calmly at the field's rim, satisfying Spec 07 §8.4's visibly-muted rule in the veil idiom.
- **Text input:** when input modality is text (Spec 07 §7.1), the quiet overlay's docked field (§7.2) is the persistent affordance — on desktop it is the steady state, focus retained. **Nothing beneath it reflows** (Spec 07 P2, honored absolutely): the veil neither shrinks nor shifts for the field; the scrim exists only behind the field itself; the calm band beneath the docked field is simply always present while docked. A typed submission animates the same acknowledgment (§5.3) as a spoken one — the presence witnesses typing too.
- **Closed captions** are, precisely, the assistant subtitle slot — already always-on. Muted mode adds no second caption system; it removes the audio and leaves the contract standing (the cognitive-freeness argument of Spec 07 §7.3, restated as presence design: mode switches must cost the user nothing to re-learn).

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
| `p-snap` | ≤ 90 ms | listening acknowledgment; equals `m-instant` |

### 8.2 Rules — Spec 07 §8.2, amended for a living ground

1. **The presence holds the breath budget.** Spec 07 rule 1 allows one `m-breathe` surface per screen; the veil (or ember) *is* that surface, always. Other breathing surfaces — the locked-value shimmer, the working shimmer (Spec 07 §5.3, §2.4) — render **static-with-sheen at Y0/Y1** and may breathe only when the presence is at Y2 on their surface. (Suite-sync X2 — this is a real amendment to 07, recorded, not smuggled.)
2. **One mover still governs** (Spec 07 rule 2): `p-flow` is ground, not a mover; yield transitions compose with card movements as a single choreography; at most one `p-cue` plays at a time — cues queue at most one deep, then drop (a dropped cue lost nothing: P7 says no cue is ever sole carrier).
3. **Meaning gates motion** (Spec 07 rule 1): every departure from the idle frame traces to a row in §4's tables. There is no "ambient variety" system, no random flourishes. The seed varies *how*, never *whether*.
4. **Text rules unchanged:** condensation is opacity/weight in place (§6.1); Spec 07 rule 4 stands everywhere.

### 8.3 Reduced motion — the still presence (hard requirement)

When the OS reduced-motion flag is set (or the user chooses "still presence" in settings, which must exist independently of the OS flag):

- `p-flow` stops. The veil renders as a **static gradient form** — the same shape language, frozen mid-breath at its seed's characteristic pose.
- States and difficulty grades remain fully legible through **discrete cross-fades** (≤ 300 ms opacity-only) between per-state static forms: idle (soft, dim), listening (gathered, brighter — plus the caption's live interim, which is itself the strongest listening signal), thinking (dimmer, denser), speaking (brighter; the caption carries the words). Difficulty shows as the same hue/luminance steps, statically.
- All `p-cue` one-shots collapse to their end states; the bloom becomes the `Done` glyph's existing tint beat (Spec 07 §9.3); gestures are dropped entirely (they were never information — P7).
- This variant is not a penalty box: it is designed as *the presence, asleep-still but present*, and it must pass the same golden-state legibility tests as the animated tiers (Spec 09 hook, §9.2). It also doubles as render tier T0 (§9.1) — accessibility and performance land on one well-made variant.

### 8.4 Screen readers and the presence

With a screen reader active, app TTS already defers (Spec 12 §6.4). The veil additionally: exposes a single semantic node ("Plenara — idle / listening / thinking / speaking / muted / text mode", matching Spec 12 §9.5's labeled voice-state chrome), announces base-state changes only (never cues, never difficulty — grade changes are not events a listener needs narrated), and is marked decorative in every other respect so swipe-navigation never lands *inside* the field. Materialized text is ordinary accessible text from the instant it begins condensing (no waiting for the animation).

---

## 9. Render Tiers, Performance & Staging

### 9.1 Three tiers, one director

| Tier | Renderer | Where |
|---|---|---|
| **T2 — the veil** | fragment shader field + optional motes (§2.1) | v3 organic rung; capable GPUs; the design target |
| **T1 — the soft field** | CustomPainter: 5–9 large blurred radial forms, cheap advection, no motes | shader-unavailable platforms; sustained-thermal demotion; mid-tier mobile |
| **T0 — the still presence** | static per-state forms, cross-fade only (identical to §8.3) | reduced motion; power-saver; GPU-distressed; and the v1 ship vehicle |

All tiers consume the same `PresenceFrame` stream from the same `PresenceDirector` — tier selection is a composition-root decision plus a runtime demotion ladder, and **no behavioral logic lives in any renderer** (P2, P8). Demotion triggers: frame-time p90 > 12 ms sustained 3 s (T2→T1), > 12 ms again or OS low-power/thermal signal (T1→T0); promotion re-attempts only on app open (never oscillate mid-session). Backgrounded: the director suspends entirely — zero frames, zero uniforms, zero battery.

### 9.2 Budgets (normative, measured like Spec 12 §7.2's)

- T2 field: ≤ **2.0 ms GPU** per frame at device resolution on min-spec, one draw call (+1 for motes); T1: ≤ 2.5 ms raster; T0: zero steady-state cost.
- `PresenceDirector`: ≤ **0.3 ms CPU** per frame, allocation-free in steady state (the frame object is reused or pooled).
- 60 fps interaction target on all tiers; T2 idle may drop to 30 fps (breath at 4 s cannot tell the difference) for battery on mobile — desktop dogfood keeps 60.
- Startup: shader precompiled; the presence is breathing at first paint — it is never a late-arriving decoration.
- Test hooks (for Spec 09, recorded as suite-sync X7): the director is a pure function — property tests over signal sequences (every `TurnEvent` order the orchestrator can emit maps to a legal frame path; grades monotonic; acknowledgment ≤ 90 ms in frame terms), golden-image tests per (state × modifier × tier) on fixed seeds, and the frame-budget numbers CI-tracked from the v3 rung like Spec 12's latency table.

### 9.3 Staging — the same skeleton, honestly

Aligned to Spec 07 §10's rungs (structure lands final early; expression is staged):

1. **v1 / v1.2 (now, Windows dogfood):** ship **T0 on the Stage** — the still presence with cross-faded states — plus the calm-band caption region. This *already replaces* the busy indicator and delivers the state vocabulary; it is "functional and clean on the same skeleton." The `PresenceDirector` + `PresenceFrame` land here in final shape, driven by the real `TurnEvent`/`SpeakEvent` streams (and by Spec 14's shipped seam on the dogfood box).
2. **v1.5 (with the voice pipeline, Spec 07 §10 step 2):** `micLevel`-driven listening, the cadence envelope, yield levels Y0/Y2 (the ember subsumes the orb the moment the orb would have shipped — no throwaway orb is built; suite-sync X1 lands here at the latest).
3. **v2:** Y1 parting choreography arrives with the generative/authoring cards it presents.
4. **v3 (the organic rung):** T2 — the shader veil, motes, the vital ramp's designed anchors (with Spec 07 Q2's pass), gesture polish. A re-skin of the director's output, not a re-architecture — the invariant Spec 07 §10 already promises, kept here.

---

## 10. Accessibility (hard requirements, consolidated)

1. **Contrast — the calm band.** Any text over the field (captions, materialized text, card content at Y1) sits on a calm band: a region where the field's luminance is clamped to a band guaranteeing ≥ **4.5:1** contrast with the text color in both themes, and local turbulence/tempo are reduced ≥ 60 %. The band is computed by the renderer from text geometry supplied by layout — never hand-placed — and is the load-bearing answer to "living background, readable words." Verified per tier in the golden tests.
2. **Colorblind-safe difficulty.** P7 enforced: every state and grade differs from its neighbors in at least two of {tempo, coherence, luminance, grain} in animated tiers, and in luminance + form in T0. The vital ramp's hue axis is redundant by construction, and the golden tests include a grayscale-render assertion.
3. **Photosensitivity — no strobing, ever.** Full-field luminance modulation is rate-limited to **≤ 2 Hz** and amplitude-limited (well inside WCAG 2.3.1's three-flashes threshold with margin); the speech cadence pulse (§4.1, ~4–5 Hz syllabic) is therefore expressed through *motion amplitude and grain*, never through luminance flashing; motes never blink in unison; no cue inverts the field. These are director-level clamps, testable on the frame stream — not renderer courtesies.
4. **Vestibular safety.** No full-field zoom, rotation, or parallax sweeps; `lean` is capped at a small fraction of field size; yield transitions translate density, not the viewport.
5. **Reduced motion** (§8.3) and **screen-reader deference** (§8.4, Spec 12 §6.4/§9.5) as specified — both are release-gating, same class as Spec 07 §8.2 rule 5.
6. **No information is presence-only** (the mirror of "no information is audio-only," Spec 12 §9.5): every veil cue shadows a card, chip, caption, or attention item that carries the actual content. A user who never looks at the field loses mood, not meaning.

---

## 11. Suite-Sync Items (for the next reconciliation pass — this spec edits no other file)

- **X1 — Spec 07 §2.1 + §8.4: the orb is subsumed.** §2.1's Stage anatomy inverts (the field is the ground; "the presence — the listening orb" becomes a reference to this spec); §8.4 is superseded by §6.3's ember (same states, gestures, and muted rendering — re-specified as the Y2 form of the one entity) and should shrink to a pointer here; §9.2's "unique per render seed" is extended to the persisted personality seed (§5.4). Retarget Spec 12 §2.1's `micLevel` comment ("the orb's listening amplitude — Spec 07 §8.4") → this spec §3.1.
- **X2 — Spec 07 §8: breath budget + presence tokens.** Rule 1's "at most one `m-breathe` surface per screen" is amended: the presence permanently holds the allowance; locked/working shimmers demote to static-with-sheen when the presence is at Y0/Y1 (§8.2 r1). The `p-*` token register (§8.1) joins §8's table; `m-breathe`'s row notes its successor on the presence is `p-breath`.
- **X3 — Spec 07 §9.3: the vital ramp.** A third, presence-exclusive color family (§4.3) alongside the two semantic colors — with the explicit constraint that no card, chip, glyph, or text may ever use it, so the "two semantic colors beyond neutrals" rule survives for everything that isn't the veil. Anchor values produced together with Spec 07 Q2's design pass.
- **X4 — Spec 07 §7.3: condensation choreography.** The subtitle slots' visual arrival/release adopts §6.1's grammar (content, slots, discipline, and linger unchanged and still owned by 07); §7.2 gains the note that the docked overlay field sits on a persistent calm band.
- **X5 — Spec 07 §10 staging:** rungs 1–4 gain the presence deliverables of §9.3 here (T0 at v1, director at v1.2, ember-subsumes-orb at v1.5, T2 at v3); Spec 07's v3 "organic pass" line points to this spec as its Stage-side content.
- **X6 — Spec 12 Q6:** record this spec (§4.1) as the customer for TTS word-boundary `SpeakEvent` extensions; the cadence-envelope proxy is the standing v1 answer.
- **X7 — Spec 09:** add the presence test tier — `PresenceDirector` property tests, per-(state × modifier × tier) golden frames on fixed seeds, grayscale-legibility assertion, and the §9.2 frame budgets as CI-tracked numbers from the v3 rung.
- **X8 — Spec 14:** note that the dogfood presence rung (§9.3 step 1) binds to Spec 14's shipped `SpeechRecognizer` seam until Spec 12's `SpeechInput` lands; no contract change requested.

---

## 12. Decision Record

### Resolved

- **D1 — The presence is the primary surface.** The Stage's steady state is the entity; views are yields of it, not destinations that replace it; the presence never despawns (P1, P3, §6.3). *(§1, §6)*
- **D2 — Substrate: the shader-rendered smoke veil**, with a bounded mote accent layer; particle swarm and aurora ribbons recorded as alternates with tradeoffs. One draw call, ~16 uniforms, flat cost. *(§2)*
- **D3 — One pure director, one frame vector, three tiers.** `PresenceDirector` consumes only the sealed streams and projections (Spec 07 P5 tightened); `PresenceFrame` is the entire renderer contract; T2/T1/T0 differ in fidelity never meaning, with an automatic demotion ladder and T0 doubling as the reduced-motion variant. *(§2.4, §8.3, §9.1)*
- **D4 — Base states are Spec 12's four, unforked**; everything else is a modifier with a single upstream source of truth; into-listening snaps ≤ 90 ms and never leads the mic. *(§3)*
- **D5 — Speech sync runs on the cadence-envelope proxy** (text-derived, `SpeakEvent`-anchored), upgraded to word boundaries if Spec 12 Q6 resolves; no system-audio taps. *(§4.1)*
- **D6 — Difficulty is the five-grade operational ladder** (D0 effortless → D4 can't) built from existing signals; grades are monotonic per turn; the ceiling is *quieter*, not louder; every grade moves ≥ 2 non-hue channels. *(§4.2)*
- **D7 — The vital ramp** is a presence-exclusive third color family; the assent and attention moments reuse Spec 07's two existing semantic colors, so the app-wide vocabulary does not grow for anything that isn't vapor. *(§4.3)*
- **D8 — Personality = breath + five gestures + timing asymmetry + a persisted seed**; no user tuning in v1; the anthropomorphism fence is absolute ("would weather do it?"). *(§5)*
- **D9 — Text condenses in place** (opacity/weight, never position — Spec 07 §8.2 r4 preserved); the **yield ladder** (Y0 field / Y1 parting / Y2 ember) is the explicit seam with Spec 07's views, and the ember supersedes the orb as the one entity's contracted form. *(§6)*
- **D10 — Muted mode is inherited, not invented:** muted `SpeakEvent`s (Spec 12 §6.3) + always-on captions (Spec 07 §7.3) + the no-reflow overlay (Spec 07 P2) already compose the design; this spec adds only the muted rim treatment and the docked-field calm band. *(§7)*
- **D11 — Accessibility clamps live in the director**, not the renderers: calm-band contrast ≥ 4.5:1, ≤ 2 Hz full-field luminance modulation (cadence goes to motion, not light), no presence-only information, vestibular caps — all frame-stream-testable. *(§10)*
- **D12 — Chartered as Spec 15**, not 07a: lettered docs in this suite are working artifacts; normative specs take top-level numbers (Spec 12 precedent). All 07 touchpoints recorded as X1–X5 rather than edited in place. *(header, §11)*

### Open

- **Q1 — Shader viability on the dogfood box.** `FragmentProgram` + Impeller on Windows desktop needs a spike (compile pipeline, per-frame uniform cost, precompilation) before T2 is scheduled; T1 is the hedge and T0 ships regardless. Pairs with Spec 12 §10.1's Windows spike so one instrumentation pass measures both.
- **Q2 — Envelope fidelity.** Whether the syllable-heuristic cadence reads as "in unison" at conversational distance, and per-engine drift over long utterances — judged by eye in the v1.5 dogfood; escalates the priority of X6 (word boundaries) if it disappoints.
- **Q3 — Vital-ramp anchors and mote design** await the same visual-design pass as Spec 07 Q2 (real mockups, both themes, contrast-checked against the calm band); mechanisms here are decided regardless.
- **Q4 — The wake-word "armed" reading** (co-owned with Spec 07 Q3, gated with Spec 12 Q3): how idle-but-armed differs visibly from idle-and-off without reading as surveillance. Candidate direction — armed is *slightly more gathered*, never brighter — needs the ambient-rung design pass.
- **Q5 — Keep or cut motes.** If they read as glitter in T2 mockups, cut; the afterglow and attending cues fall back to field-local treatments already defined per-tier.
- **Q6 — Seed portability.** Whether the personality seed syncs across the user's devices (one being everywhere) or stays per-install (each device its own sibling) — a product-feel call with a trivial mechanism either way; decide with Spec 06's settings-sync posture.
- **Q7 — Difficulty-grade thresholds.** D1's 400 ms and the demotion ladder's numbers are launch guesses; calibrate against Spec 12 §7.2's measured budgets during the dogfood so "working" never fires on a healthy fast turn.

---

*End of Spec 15 — The Living Presence v0.1*
