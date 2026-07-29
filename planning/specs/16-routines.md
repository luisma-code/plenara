# Spec 16 — Routines & Guided Movement

_Status: v0.1, implemented 2026-07-28. Designed with Fable; the figure decision is grounded in a
measured spike rather than taste (§2)._

## 0. What this is

"Create a stretch routine for my low back" → a durable, replayable routine. Later, "let's do low
back" walks you through it one movement at a time, out loud, hands-free.

Routine creation is a **third content category**, alongside capability authoring and generative
kinds — and it must be classified explicitly or someone will misapply Spec 08 D4's "never cache
generative effects" to it:

| | Capability authoring | **Routine authoring** | Generative kinds |
|---|---|---|---|
| Output | type/skill definitions | ordinary **records** | ephemeral text |
| Cached? | forever (it's data) | **forever (they're records)** | never |
| Gate | preview → "activate" | **act-then-describe + undo** | n/a |
| Replay | interpreter | shipped player + renderer | regenerated |

A routine's whole value is *stability* — the same seven movements every morning. It is not a
briefing.

## 1. Division of labour ("code over AI", principle 3)

    CODE   narrows 640 catalogue exercises to a scored, deterministic shortlist
    MODEL  sequences and labels a routine from that shortlist
    CODE   validates every field of what comes back

Consequences that are *enforced*, not hoped for:
- A model **cannot invent an exercise** — an `exerciseKey` outside the catalogue is rejected.
- A model **cannot reword a movement** — instructions are copied FROM the catalogue. It only
  supplies wording for a step with no catalogue exercise (a plain hold or breather).
- A model **cannot ship a step the app can't say** — an instruction under 15 characters is invalid.

One gated retry, fed the deterministic validation error. A second failure writes **nothing**: a
half-routine is worse than none.

## 2. Why a catalogue and not generated figures (the spike, 2026-07-28)

The original idea was model-drawn stick figures. It was spiked before building:

- **Safety subset: 19/19 clean.** A strict render-only SVG allowlist (no `script`, `style`, `href`,
  `use`, `image`, `animate`, no CSS, no `url()`) held under a parser + allowlist check.
- **Correspondence: 18/19.** Keyframe pairs shared element order and path command letters, so real
  tweening was possible — not just a crossfade.
- **But readability failed for a whole class.** Standing/seated/kneeling poses read well; poses
  lying on the back collapsed into overlapping lines (~10–11 of 15 usable).
- **Two levers did not fix it.** Explicit 3/4 projection *geometry* was followed (the adjective
  "3/4" alone was ignored) and still produced unrecognisable poses; a render-and-critique **vision
  loop made them worse** — the model simplified rather than repaired.

Root cause looks structural: recognising a reclining body depends on foreshortening and volume,
which single-stroke line art does not have. So the model stopped drawing and started **selecting**.

**Source:** wger.de, CC BY-SA 4.0, illustrations largely by Everkinetic, with per-record
`license_author` so attribution is mechanical. 640 exercises, 200 illustrated. Transparent-background
line art, so a render-time `invert()` puts light figures straight on the void.

**Coverage is partial by design (~1/3 illustrated).** A step whose exercise has no picture renders
text-only. That is a first-class path, not a degradation, because §5's ear-sufficiency rule means
the words already have to carry the movement.

**Licensing posture:** images ship **unmodified** and are recoloured at DISPLAY time. Share-alike
attaches to adaptations; displaying the work with a display transform is a cleaner position than
distributing a modified copy. An attributions surface is required.

## 3. Data model

Three seed types (`v0/data/types/`):

- `routine` — title, focusArea, kind (stretch|strength|mobility), intent (the user's own words),
  estMinutes, safetyNote, status, createdAt.
- `routine_step` — **owned** (`parentType: routine`), editable: order, name, instruction,
  exerciseKey, durationSeconds | reps, side.
- `routine_session` — **owned**, append-shaped: routine, routineTitle, **date**, completedAt,
  stepsCompleted, stepsTotal, feel.

Steps are **child records, not an embedded json array**, so "make step 3 longer" is an ordinary
journaled, undoable field-merge, and the player walks them with `read_related` + `orderBy`.
`routine_session.date` is a plain date so the existing `current_streak`/`longest_streak` compute
fns work with **no new vocabulary**.

**Where the emergent-types bet stops.** These are *seed* types, because the player is shipped
experience code and the renderer is binary code keyed to the schema. The bet holds for data shapes
and the capture/query grammar; it does not extend to stateful guided experiences. That is the same
boundary Spec 02 §9.2 already draws for `instantiate-template` — a mapped edge, not a defeat. What
stays emergent is the *content*: which routines exist and how they evolve.

## 4. The player is a MODE, not a skill

The closed DSL has no timer and no suspended interactive state — and Spec 02 §8.4 uses *"that would
require a timer"* as its canonical honest refusal. So the player is a Session conversational mode,
the direct sibling of the Tour, and **the interpreter's opcode set is untouched**.

- Control words are offline regexes: `next`/`done`, `skip`, `back`, `repeat`, `pause`/`go on`,
  `stop`. Free, instant, no round-trip while you're holding a stretch.
- `repeat` re-speaks the **stored** instruction — never a model call mid-run.
- **The run is STICKY.** Unlike the Tour (which dies when a turn dispatches out of domain), an
  unrelated command mid-run executes normally and the run survives. There is sunk physical effort
  here; dropping a workout because the user asked one side question is worse than any tidiness.
- Completion dispatches `log-routine-session` through ordinary skill dispatch, so it is journaled,
  undoable and visible to automations. A partway quit logs a **partial** session. An abandoned run
  logs **nothing** — a fabricated session would corrupt the record (DP-05).

**The one genuine architecture extension:** the auto-advancing cadence means the app speaks
**without a user turn**, which the one-active-turn pipeline does not model. It runs device-local and
deterministic, outside the pipeline, and pauses while a turn is in flight. Precedent exists (nudges,
notification delivery); this spec owns it explicitly rather than smuggling it in.

## 5. Voice-first, with the most visual feature in the app

The figure is a **Y1 guest surface**: Plena eases to her corner (the shipped list-reply mechanic)
and the step hovers in the space she vacates. The figure is **content, not a presence glyph** —
Plena's glyph system has hard rarity caps and an apt-or-absent rule, and a functional diagram every
45 seconds would shred them.

**Ear-sufficiency is a validator rule, not a prompt hope:** every step must stand alone for the ear,
and the figure is never the sole carrier of the movement.

**Honest limit — "screen off" is not yet true on iOS.** The cadence is a Dart timer in the widget
tree plus foreground TTS, and the app declares no `UIBackgroundModes`. Locking the phone suspends
it: the timer freezes and speech stops after the current utterance. Face-down-but-awake works;
locked does not. Making it true needs a background-audio session, which is not built. Until then the
claim is scoped to "you don't have to LOOK at it", not "it runs locked".

**Spoken ≠ printed.** Catalogue wording is written to be read ("Starting position: … Steps: …
Tips: To leave the pose, walk your arms back…"). Spoken in full that is a wall of text while you're
on the floor. `spokenInstruction()` drops the Tips tail and print-only labels and cuts at a
**sentence** boundary. The full text stays on the record — the card shows everything.

Timed steps auto-advance; **rep steps never do**, because only the user knows when the reps are
done.

## 6. Safety

Health-adjacent, so three independent layers:

0. **The app's existing refusal floors run FIRST** — fabrication, scope, harm, medical. A first
   implementation put routine handling *above* the harm and medical floors, so "a workout for my
   anorexia recovery" and "a workout to help with what's wrong with me" reached authoring
   completely ungated. Exercise-as-treatment for a disordered-eating or self-harm framing is the
   worst output this feature could produce; the harm floor now also names those framings
   explicitly, and `_createRoutine` re-checks it rather than trusting call order alone.
1. **Layer 1, before any spend.** Injury/medical *framing* ("herniated disc", "sciatica", "after my
   surgery", "a pulled hamstring", "my sore back") gets a redirect to a physio, not a treatment
   plan. Keyed on **framing, not topic**: "low back", "shoulders", "stability", and — importantly —
   "injury *prevention*" pass untouched.

   **This gate REFUSES; it does not sanitise.** An earlier draft of this spec claimed the condition
   was "stripped from the prompt so it never leaves the device". No such code ever existed, and the
   claim hid where the risk actually sits: when the gate fires, nothing is sent at all; when it
   *misses*, the utterance goes to the cloud verbatim and is stored as `intent`. The privacy
   property of this feature is therefore **the recall of that pattern**, which is why its lexicon is
   deliberately broad — a false positive costs one redirect the user can rephrase past, a false
   negative ships someone's medical detail to a third party.
2. **The standing disclaimer is OURS**, fixed in code. A test asserts a model cannot reword or drop
   it: a disclaimer the model can rewrite is not a disclaimer.
3. **Spoken once per routine, on first run.** Repeating it every run is itself a safety failure —
   warnings that always fire stop being heard. It stays visible on the card.

**Ordering is a safety property.** Routine handling runs *after* the fabrication / scope / harm
floors. A first implementation put it before them, and a greedy create-regex swallowed "create a
tracker to hide my eating" — routing it to routine authoring and skipping the floors entirely. Fixed
twice over (floors first, and the routine noun is required).

## 7. Cost

One call per routine, on an authoring-class model, then **free forever**. Roughly $0.05–0.10 per
routine; everything afterwards — listing, playing, logging, streaks — is offline and free, which is
the Spec 05 §3.7 free-tier invariant.

## 8. Not built (deliberately)

Refinement turns ("make it harder", "swap step 5"); gap-detection nudges; weekly-review grounding;
post-run "how did it feel"; camera/sensor form-checking (wrong product, privacy change); a curated
pose library (only if catalogue coverage proves too thin in dogfood); multi-week periodised
programmes (coaching-app territory — a routine is a unit, not a program).
