# Plenara art, visual engagement, and animation review

**Review date:** 2026-08-17  
**Scope:** shipped Flutter app, UI and presence specs, actual iPhone first-run render, Plena's real particle renderer, the full shipped presence-glyph vocabulary, routine illustrations, motion behavior, accessibility, and engagement direction.  
**Constraint:** review only. No production code or asset was changed.

## Verdict

Plena is the strongest piece of visual design in the project. The warm void, luminous swarm, restrained state changes, and idea that she writes a rare symbol out of her own body are distinctive enough to become a real identity. The app around her currently looks like a different product: the App Store icon is Flutter's stock logo; first run is a long, light, generic Material page; Settings and Data are teal Material routes; typography is the system default; and the planner state that would make the app useful is mostly absent from home.

The answer is **not more particles, more glyphs, or more animation**. Plena already has more expressive material than the rest of the product can support. Engagement should come from three things:

1. **Useful persistence:** the plan, the next commitment, and the latest action remain visible.
2. **Visible causality:** what the user says visibly becomes an object, moves when rescheduled, and closes when completed.
3. **Personal relevance:** Plena spends her rare expressive moments on people, promises, milestones, and care—not on every routine write.

The recommended product is an adaptive hybrid: full-screen Plena for rest and conversation; a compact, continuously present Plena beside a calm information canvas for planning; and a small ember at the edge of detail surfaces. This preserves the voice-first premise without making voice the only way to reconstruct state.

## What I inspected and how I verified it

### Rendered evidence

- Built and rendered the iOS app on an iPhone 17 simulator at 1206 × 2622. The captured first-run screen showed the real Material layout, typography, colors, viewport, and Dynamic Island interaction.
- Rendered all **52 live `GlyphDef` entries** through the real `PresenceView`, not redrawn vectors: **416 PNG frames**, eight evenly spaced samples per complete draw → flourish → hold → rejoin sequence.
- Rendered the four static presence states and ran the existing pixel measurements. Results:

| State | Mean luminance | Lit-pixel coverage |
|---|---:|---:|
| idle | 0.0785 | 0.3032 |
| listening | 0.1000 | 0.3295 |
| thinking | 0.0584 | 0.2031 |
| speaking | 0.1581 | 0.3613 |

The four states are materially different. Speaking is the brightest and broadest; thinking is markedly dimmer and tighter; listening is brighter and more coherent than idle. That part of the state vocabulary is real, not just declared.

- Inspected representative routine assets and inventoried all 200 shipped exercise images: **113 JPEG payloads, 84 PNG payloads, and 3 GIF payloads**, despite every filename ending in `.png`.
- Ran the real presence resource tests and render invariants; the targeted suite passed 17 tests. This supports bounded object lifecycle in the headless harness, state separability, background suspension, and idle suspension. It does not prove an hours-long leak is absent.

### Instrument calibration and limitations

The glyph-filmstrip harness was calibrated before I trusted it:

| Input | Exit | PNG output | Reading |
|---|---:|---:|---|
| known-missing glyph `__known_missing__` | failure | 0 | broken state detected |
| real `heart` glyph | pass | 8 | good state rendered across full range |

One verifier defect was found during the review. [`gesture_contact_sheet.py`](../app/tool/gesture_contact_sheet.py) converts RGBA frames directly to RGB, exposing arbitrary transparent-pixel RGB as an orange checkerboard instead of compositing the frames over the app's warm-black ground. I used the sheets for shape and sequence only, not for palette or contrast. The individual RGBA captures remain valid geometry evidence. The static render metric also isolates the painter without the real Scaffold background; its **relative state differences** are useful, but it should not be treated as an end-to-end color proof.

The macOS debug app rose from roughly 271 MB to 297 MB RSS over 19 seconds without a plateau, so I killed it under the project's RAM-safety rule. The iOS simulator process generally plateaued, with debug RSS fluctuating roughly 448–507 MB in short samples. Every app instance I launched was terminated, and I confirmed no Plenara, Runner, or `flutter run` process remained. These short samples are not leak certification.

## Priority findings

| Priority | Finding | Consequence |
|---|---|---|
| P0 | First run and app icon do not belong to Plena's visual world | The product loses its identity before the user meets its strongest design |
| P0 | Full-screen presence replaces rather than supports planning information | Beautiful home, weak planner; the user must interrogate memory instead of seeing state |
| P0 | Spoken replies intentionally suppress simultaneous captions | Voice output becomes ephemeral and violates the visual trust/recall model |
| P1 | The 52-glyph register is over-broad and routine actions trigger it frequently | Expressiveness turns into decorative latency and semantic ambiguity |
| P1 | Text arrival/departure motion is mostly not real | Important state appears and disappears without continuity |
| P1 | Reduced-motion support exists in the particle renderer but is incomplete product-wide | No independent still-presence setting; GIFs and route motion have no coherent policy |
| P1 | Routine illustration style is inconsistent, and authored A/B movement figures render only A | The visual flagship routine surface cannot teach motion consistently |
| P1 | Typography, palette, shape, iconography, and routes split into dark Plena vs. stock Material | The app reads as a prototype wrapped around one finished artwork |
| P2 | Several quiet labels fall below accessible contrast | Routine context and controls become unnecessarily hard to see |

## Art-direction review

### 1. Plena is a viable identity

The presence has a coherent visual thesis:

- Warm-black ground `#0A0908` and warm off-white ink `#EAE2D8` are quiet, intimate, and unlike generic productivity software ([`main.dart:988–998`](../app/lib/main.dart)).
- A fixed particle seed makes her form stable across runs; the warm hue cools with difficulty ([`plena.dart:27–43`](../app/lib/plena.dart), [`plena.dart:573–579`](../app/lib/plena.dart)).
- State targets are meaningfully differentiated ([`plena.dart:91–95`](../app/lib/plena.dart)); the render measurements confirmed those differences.
- The glyph mechanic has a memorable internal logic: Plena flies the line and sheds a wispy tail, then the figure pours back into her ([`plena.dart:457–511`](../app/lib/plena.dart)). It feels native to the entity rather than like an icon pasted above it.
- The best figures—heart, check, question, candle, gift, clock, target, hourglass, leaf, open book—are clear at the held frame and retain the hand-drawn marginalia quality required by Presence Spec §5A.

This is worth preserving. Replacing Plena with a conventional mascot, avatar, or dashboard ornament would throw away the project's most original design work.

### 2. The identity collapses outside the presence home

The actual iPhone first-run render is a long light page made from stock Material cards, default sans type, teal icons, and standard buttons. The app theme is literally `ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal)` ([`main.dart:113–121`](../app/lib/main.dart)); onboarding is built from `Icons.spa`, `Card`, `FilledButton`, and `TextButton` ([`onboarding_view.dart:33–100`](../app/lib/onboarding_view.dart)).

Concrete first-run defects:

- The `Icons.spa` brand mark is centered beneath the Dynamic Island, and the Island visibly hides its upper half. The screen's `ListView` uses a fixed 32-point padding but no `SafeArea` ([`onboarding_view.dart:37–45`](../app/lib/onboarding_view.dart)).
- The explanation stack is so tall that the primary choices begin below the initial viewport. The first impression is setup documentation, not meeting Plena.
- “Give Plena a natural voice” is a useful instruction, but it arrives as another gray card with a long numbered paragraph. Voice-first is introduced through reading-heavy setup.
- Home then jumps to a nearly black, luminous, characterful world. There is no transition or shared visual material between the two.
- Settings and Data return to light Material routes with `inversePrimary` app bars ([`settings_view.dart:306`](../app/lib/settings_view.dart), [`data_view.dart:130`](../app/lib/data_view.dart)). Plena does not remain as an ember or rail, despite Presence Spec §6.3's Y2 continuity.

The shipped 1024px iOS icon is still the stock Flutter mark: [`Icon-App-1024x1024@1x.png`](../app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png). That is the most externally visible art asset and currently communicates “Flutter build,” not Plena.

### 3. Recommended visual identity: “warm constellated memory”

Use one visual system across every surface:

- **Ground:** warm-black for home, charcoal/umber surfaces for information, and a warm paper-light variant only where long reading genuinely benefits. Do not use default Material teal as a parallel brand.
- **Presence color:** ember-gold at rest, cooling toward pre-dawn blue only for effort. Current `PresenceTuning.sat = .9` is visually closer to neon than Presence Spec §4.3's restrained/desaturated intent; tune saturation on the real dark composite and at phone viewing distance.
- **Ink:** warm off-white for primary text; muted mushroom/stone for supporting text; one attention hue and one positive hue, as already specified.
- **Typography:** ship the specified two-family hierarchy. A humanist sans should handle labels/data; a quiet serif should carry the user's own words, journal material, remembered details, and reflective summaries. There are currently no bundled fonts or custom `TextTheme`; the five-step scale in UI Spec §9.1 is not implemented.
- **Shape:** use the specified soft superellipse family and spacing instead of generic Material card geometry. Onboarding, Settings, Data, planning views, and routine controls should feel cut from the same material.
- **Iconography:** derive a small, optical-size-tested mark from Plena: a dense ember congregation with one off-center bright mote or short comet stroke. Avoid a literal face, a miniature complex swarm, or a generic sparkle. Test it at notification and Settings sizes, not only 1024px.

## Animation review

### 1. Presence state motion

What works:

- The particle director uses fixed 60 Hz substeps and caps recovery work, avoiding high-refresh double deposition and runaway catch-up ([`plena.dart:409–425`](../app/lib/plena.dart)).
- State parameters ease rather than jump, with faster listening response and slower other states ([`plena.dart:428–447`](../app/lib/plena.dart)).
- Background and three-minute user-idle suspension are implemented ([`plena.dart:176–215`](../app/lib/plena.dart)).
- iOS takes a straight-draw branch because the feedback buffer crashes Impeller; the limitation is explicit and Plena still animates ([`plena.dart:704–729`](../app/lib/plena.dart)).

What is still shallow:

- The app currently drives only difficulty 0, 1, and 2; D3 clarification and D4 failure expressions in Presence Spec §4.2 are not wired through `_difficulty` ([`main.dart:312–327`](../app/lib/main.dart)).
- Speaking is bracketed by TTS start/done, but there is no word/syllable cadence envelope yet. Plena changes into a generally active speaking state, not visibly “speaking this sentence.” Presence Spec §4.1 accurately admits this baseline.
- Listening shimmer is self-generated because mic level is unavailable ([`plena.dart:451–455`](../app/lib/plena.dart)). It signals “mic open,” but not “I am actually hearing your volume.”
- Thinking's measured coverage is only 0.2031 versus idle's 0.3032. The state is distinguishable, but on a dim phone or in peripheral vision it may read as disappearance. Test recognition on physical devices at normal brightness, not only pixel separation.

### 2. Glyph filmstrip findings

Every shipped glyph was inspected at eight evenly spaced points across its complete 2.60–3.58 second sequence.

Phase-by-phase:

| Frames | Observation |
|---|---|
| 1 | Plena departs; most figures are not yet recognizable. This is consistent across the vocabulary. |
| 2–3 | Geometry forms monotonically; no major discontinuities or malformed midpoint shapes appeared. |
| 4–5 | The figure is most legible. Clear marks read immediately; ambiguous marks remain ambiguous even fully formed. |
| 6 | The figure is already mostly released; semantic legibility falls sharply. |
| 7–8 | Every row returns to a similar hook/comet rejoin state. The convergence is smooth and correctly communicates return, but carries no remaining symbol meaning. |

The strong set: heart, check, star, candle, question, gift, clock, hourglass, target, bell, leaf, infinity, house, flower, sun, open book.

The ambiguous/redundant set:

- `smile`, `warm-smile`, `nod`, and `bridge` all resolve to related arcs and are hard to distinguish without occasion context.
- `crescent`, `orbit`, `enso`, `undo-loop`, and `snooze-arc` occupy a similar circular register.
- `wave` reads as a waveform, not necessarily farewell.
- `clasp` reads as two curls; comfort/held hands is not reliably recoverable sound-off.
- `still-flame` is intentionally minimal but reads more like a vertical mark than remembrance.
- `cake` and `teacup` need the bright travelling core to complete the figure; the faint deposited geometry alone is marginal.
- `reach` is a literal stick figure and feels closer to instructional illustration than the atmospheric marginalia register.

The vocabulary is also out of control administratively. Presence Spec §5A.8 defines fifty, says forty-nine ship, and omits confetti; the renderer contains 52 because `reach`, `flower`, and `sun` were added. More importantly, the frequency rule is not the production rule: the spec requires ≥90 seconds and about eight per day, while `_fireGlyph` uses an eight-second debounce and no daily budget ([`main.dart:254–264`](../app/lib/main.dart)). Routine creates/logs, task adds, reminders, person facts, moods, exercise logs, interactions, and gifts all have explicit mappings ([`glyphs.dart:708–762`](../app/lib/glyphs.dart)). Long-pressing the ordinary home cycles all glyphs in production ([`main.dart:1140–1148`](../app/lib/main.dart)), even though the spec describes that as a development preview.

**Recommendation:** keep the full corpus as a development sketchbook, but make the active product register much smaller.

- Everyday task/reminder/log writes: use a ≤300ms whole-body acknowledgment—gather, small assent bloom, or settle—with no traced symbol.
- Rare functional glyphs: question, undo-loop, target, final check, sunrise.
- Rare relational glyphs: heart, candle, gift, bridge, open book/quill.
- True milestones: star or laurel, never both in ordinary use.
- Remove or defer any symbol that cannot reach ≥80% sound-off recognition at its held frame.

This restores the central design truth: glyphs are punctuation, not the sentence.

### 3. Text and object motion

This is the weakest motion layer, and it matters more to planner engagement than another presence flourish.

- The current exchange is conditionally inserted inside an `AnimatedOpacity` whose opacity is always `1` ([`main.dart:1175–1189`](../app/lib/main.dart)). It cannot fade in from zero; when `hasContent` becomes false, the widget is removed immediately, so it cannot fade out. The specified condensation/release choreography is therefore not present.
- When TTS is available, the app deliberately sets the assistant display to `null` ([`main.dart:523–535`](../app/lib/main.dart)). This directly contradicts UI Spec §7.3's “every word TTS speaks is simultaneously on screen.” Spoken answers have no simultaneous visual anchor, and muted captions disappear only 1.6 seconds after the flourish ends ([`main.dart:546–555`](../app/lib/main.dart)), not the specified four-second linger plus persistent Stream.
- The input bar genuinely slides in with `AnimatedPositioned`, but uses an ad-hoc 350ms value ([`main.dart:1230–1237`](../app/lib/main.dart)). UI Spec §8.1 says every animation draws from named tokens and no widget defines ad-hoc durations; the current code has many raw timers and durations.
- The startup path still uses a generic `CircularProgressIndicator` ([`main.dart:988–997`](../app/lib/main.dart)), even though the Stage spec says thinking Plena replaces spinners.
- There is no shared-element doorway, no task moving between due groups, no completion closure, no visible undo reversal, and no persistent Done line. Those continuity transitions are precisely what would make spoken planning feel real.

The signature planner motion should be **object continuity**:

1. The transcript settles in place.
2. The resolved noun/commitment condenses into a small object.
3. That object travels once into its real Today/Next/Later location.
4. Plena gives a ≤300ms acknowledgment beside it.
5. The object remains visible; the user does not have to remember the animation.

Rescheduling should move the same object between horizons. Completion should softly close or fold the same object, leaving undo nearby. Undo should reverse that exact motion. This creates agency and confidence without adding gamification.

### 4. Reduced motion and accessibility

The particle renderer does honor `MediaQuery.disableAnimations`, stops the ticker, abandons half-drawn glyphs, and snaps to a static per-state form ([`plena.dart:243–295`](../app/lib/plena.dart)). That is a good foundation.

Product-level gaps remain:

- Presence Spec §8.3 requires a user-selectable “still presence” setting independent of the OS flag. No setting exists.
- The spec calls for ≤300ms opacity-only cross-fades between static state forms. The current static path snaps; there is no cross-fade between two static renders.
- The semantic node should include idle/listening/thinking/speaking plus muted/text mode. The current label exposes state and caption only ([`main.dart:1155–1162`](../app/lib/main.dart)).
- Three routine files are actual animated GIFs—`dumbbell-rear-delt-row.png`, `dumbbell-wide-bicep-curls.png`, and `smith-machine-split-squat.png`. `Image.asset` can loop them, but the routine view has no reduced-motion branch, timing token, or keyframe verification for those files.
- Routine context text at [`routine_view.dart:125–128`](../app/lib/routine_view.dart) composites to about **2.15:1** on the warm-black background at 11px. The Stop label at [`routine_view.dart:185–189`](../app/lib/routine_view.dart) is about **1.92:1**. Both are below accessible normal-text contrast. Main ink is 15.51:1; the issue is the overly faded quiet labels, not the dark theme itself.

## Routine and illustration review

The routine surface's structural composition is promising: a large illustration, quiet step context, strong movement name, instruction, progress, and voice-parallel controls on the same warm void ([`routine_view.dart:115–209`](../app/lib/routine_view.dart)). It is one of the few places where information already yields Plena rather than replacing her.

The art corpus is not one product yet:

- The 200 illustrations mix transparent anatomical line drawings, black-and-white bodybuilding drawings, colored clip art, red muscle highlights, different proportions, different crops, and three animated GIFs.
- The render-time invert filter makes dark lines light and white grounds dark ([`routine_view.dart:135–149`](../app/lib/routine_view.dart)), but tonal inversion does not unify anatomy, line weight, perspective, crop, or stylistic era. Colored art also changes to unrelated complement colors.
- JPEG compression on near-white backgrounds can become a dark halo/rectangle after inversion.
- The generated fallback is designed as an A/B SVG pair, and correspondence is validated, but the app passes only `figureA` ([`main.dart:1014–1032`](../app/lib/main.dart)); [`routines.dart:549–555`](../v0/lib/routines.dart) explicitly says interpolation and two-frame toggle are not built.

Recommendation:

1. Define one routine-figure grammar: consistent human proportions, two optical line weights, fixed crop box, no faces, limited equipment detail, and two canonical key poses.
2. Curate/replace the highest-use exercise images first instead of pretending inversion unifies all 200.
3. For movement teaching, show A and B as a two-panel still by default. On tap or at step start, play one slow A→B→A cycle, then stop. Never use a perpetual workout GIF as ambient decoration.
4. Under reduced motion, retain the two labeled stills. Nothing instructional is lost.
5. Any interpolated figure must get an 11-frame keyframe strip that checks limb correspondence, plausible pivots, monotonic movement, and no shape collapse. A/B validity is not enough to certify the middle.

## Engagement analysis: voice, presence, and visible information

The current design choice treated UI as a possible crutch. That was useful discipline—it forced the action path to work by voice—but the pendulum has moved too far. A planner is partly a conversation and partly an external memory. Voice is excellent for capture, adjustment, and asking; it is poor at persistent comparison, scanning, and prospective memory.

Three viable compositions exist:

| Direction | Character | Strength | Cost |
|---|---|---|---|
| **A. Voice sanctuary** | Current full-screen Plena, ephemeral exchange | Most distinctive and intimate; lowest chrome | Weak planner, low glanceability, hard to trust what persists |
| **B. Presence + living canvas** | Plena full-screen at rest/conversation, compact beside persistent planning objects | Preserves character while adding useful memory and visible causality | Requires the Y0/Y1/Y2 choreography to be designed and implemented well |
| **C. Visual planner with Plena rail** | Information-first home, Plena always small | Highest density and conventional planner utility | Risks making Plena decorative and the app generic |

**Choose B.** It matches the existing specs' yield ladder and makes voice and UI complementary:

- Voice is the fastest way to create and manipulate plans.
- The canvas proves what happened and keeps the future visible.
- Plena carries attention, confidence, difficulty, and relationship—not the data itself.

### Proposed surface behavior

**Rest / conversation (Y0):** Plena owns the screen. A greeting or reflective exchange can remain visually sparse. The most important current exchange is always captioned.

**Planning (Y1):** Plena eases into a compact edge/upper-corner congregation while a calm Today canvas arrives. Show only the information that supports the next decision:

- Now: the immediate commitment or active routine.
- Next: up to three due/meaningful objects.
- Later: one horizon summary (“4 this week”) rather than a wall of cards.
- One relationship-relevant nudge, when genuinely timely.
- Latest Done + Undo, until the undo window closes.

**Detail / browse (Y2):** Plena becomes a small ember/rail in the same location across Collections, Data, Settings, and person views. She remains present but stops competing with reading.

This is not a dashboard. It is a magazine-like canvas with a few carefully chosen facts and strong hierarchy. The “no UI as a crutch” test should become: **every action remains possible by voice; every consequential state remains inspectable without voice.**

### What makes this engaging without gamification

- **Recognition:** seeing “Call Mom · Friday” is more emotionally and cognitively engaging than asking the system what it remembers.
- **Completion:** the same object visibly closes when done; the user experiences agency.
- **Anticipation:** a due item gradually moves nearer in spatial hierarchy rather than merely triggering a notification.
- **Personal texture:** person threads, shared plans, remembered preferences, and past interactions create meaning; generic streak confetti does not.
- **Rarity:** Plena's largest gesture is saved for the moments the app exists to support—a birthday, reconnection, kept promise, or hard-earned milestone.
- **Continuity:** the object created by voice remains the object seen later. Trust is engagement.

## Recommended prototype sequence

### Prototype 0 — repair the visual instrument

- Composite glyph frames over the actual `#0A0908` ground before making color judgments.
- Add a screenshot matrix for: onboarding, idle, listening, thinking, speaking, short caption, long/list caption, muted input, Today canvas, routine, Data, Settings, reduced motion, and large text.
- Stamp every capture with build hash, platform, pixel size, text scale, brightness, reduce-motion state, and reached-state assertion.
- Keep the 8/11-frame glyph and motion strips as permanent review tools.

**Pass condition:** known-broken alpha/background, missing-glyph, collapsed-state, and missing-text variants all fail; known-good variants pass with different readings.

### Prototype 1 — one coherent first minute

- Replace the Flutter icon with a Plena-derived mark and test at small optical sizes.
- Put onboarding inside the warm constellated identity; honor safe areas.
- Reduce first run to one promise, one privacy statement, and two choices visible above the fold. Introduce voice setup after the user meets Plena, not before.
- Replace the startup spinner with a still/awakening Plena state.
- Keep captions present during TTS.

**Pass condition:** on the target iPhone, no art or control intersects the Dynamic Island/home indicator; both entry choices are visible without scrolling; a five-second first-impression test identifies “private assistant / people I care about,” not “setup page”; app icon is identifiable at Settings and notification sizes.

### Prototype 2 — presence + Today canvas

- Implement the existing Y0→Y1 yield: full Plena to compact collaborator.
- Add persistent Now/Next/Later objects, one relationship nudge, and latest Done/Undo.
- Use the same dark visual tokens and typography across the canvas.
- Keep tap-anywhere voice behavior where it does not collide with objects; give objects real semantics and touch targets.

**Pass condition:** after a five-second glance, Luis can correctly state the next commitment, what is due today, and whether the last action can be undone in 9/10 scripted states; every displayed object has a voice path; every voice write appears visibly within the same beat as its Done response.

### Prototype 3 — semantic continuity motion

- Build one end-to-end motion grammar for create, reschedule, complete, undo, and clarification.
- Animate real object identity, not substitute decoration.
- Make text condensation/release real and tokenized.
- Provide opacity-only reduced-motion equivalents.

**Pass condition:** sound-off recordings let a reviewer identify create/reschedule/complete/undo correctly in ≥90% of trials; no object teleports or disappears without a terminal state; all transitions render correctly at 11 frozen keyframes; only one mover-class transition occurs at a time.

### Prototype 4 — expressive curation and routines

- Reduce active presence glyphs to a small, rare register and implement the real 90-second/daily budget.
- Curate a coherent routine illustration subset and a verified A/B presentation.
- Add the independent still-presence setting; freeze or replace looping GIFs under reduced motion.

**Pass condition:** each active glyph reaches ≥80% sound-off recognition at the held frame; no everyday logging script exceeds the daily glyph budget; all routine figures retain instruction in reduced motion; no tween has a physically implausible intermediate frame.

## Release gates and success measures

| Area | Gate |
|---|---|
| First impression | Icon is non-placeholder; onboarding passes safe-area and first-viewport tests on every supported iPhone class |
| Presence semantics | Idle/listening/thinking/speaking recognized sound-off at normal phone distance; difficulty never relies on hue alone |
| Planner glanceability | Next action, today's load, and latest write/undo recoverable in five seconds without speaking |
| Motion meaning | Every non-ambient animation maps to one state change; no decorative loops beyond Plena's breath |
| Object continuity | Create/reschedule/complete/undo preserve object identity through the transition |
| Glyph restraint | ≥90 seconds between glyphs, daily budget enforced, active shapes pass sound-off recognition |
| Reduced motion | Independent still-presence option; no particle flow, glyph trace, routine GIF loop, positional text motion, or unverified tween |
| Typography and contrast | Normal text ≥4.5:1; large text and meaningful non-text marks ≥3:1; Dynamic Type does not clip or hide actions |
| Performance | Presence meets the existing frame budgets; long-run device soak is separate from short resource tests; no app process remains after test runs |
| Visual unity | Onboarding, home, Today, routine, Data, and Settings share the same palette, type scale, shape family, and Plena continuity |

## Final recommendation

Keep Plena. Stop asking her to be the entire interface.

Make her the living ground at rest, the collaborator at the edge of a plan, and the quiet ember beside detail. Put the plan itself on screen. Let spoken actions become persistent objects. Spend motion on showing what changed and expressive glyphs on the rare moments that matter. Then the voice-first choice stops fighting engagement: voice provides speed and intimacy; the visual canvas provides memory, trust, and anticipation.
