# Spec 12 — Voice

**Status:** Draft v0.1 — July 2026 (Fable 5). First full draft of the voice pipeline: capture model, STT/TTS engine selection per platform, the interim/final transcript contract, barge-in and latency targets, the voice-privacy statement, and the error/degrade surfaces.
**A note on numbering:** Specs 03, 04, and 08 cite a "Spec 06 — Voice" that was never written — the research doc's spec charter (§12) never listed a voice spec, and slot 6 was taken by Data & Sync. This document is that missing spec, chartered as **Spec 12**. It is the referent every "Spec 06 — Voice" citation intends; retargeting those citations (and Spec 10's mis-pointed ownership line) is a suite-sync pass item recorded in §10, not something this spec edits in place.
**Depends on:** Research doc (§2.1–2.3, §6.1–6.5, §9.1–9.2, §11.2–11.5, §15.1); Spec 03 — NLU / Intent (§1 P2.5, §2.6–2.7, §5.4 normalization, §10 MD10 — final-transcript-only); Spec 04 — Architecture (§2.1–2.3 layer model, §3.6 `DispatchOrchestrator`, §3.8 `SpeechEngine`, §4.2 turn pipeline, §4.3 barge-in policy, §5 error model); Spec 05 — Functional (§3.2 ASR floor, §11 voice journal F8, §13 offline/subtitle F10); Spec 07 — UI (§7 quiet overlay & subtitle contract, §8.4 the orb); Spec 08 — AI Cost & Privacy (§5.2 routing payload, §5.5 master table, §5.6 consent tiers)
**Blocks:** Spec 09 — Test (the `SpeechInput`/`SpeechOutput` seams marked **[GAP]** in §3.1, and the voice E2E tier of §6.2 O3); the v1.5 voice rung (Spec 07 §10 step 2 — the Stage, orb, and subtitle region arrive with this pipeline); Spec 08 §5.5's STT/TTS row (this spec is its normative source)

---

## 0. Purpose & Scope

Plenara is voice-first (P2.1): free-form speech is the primary input, and the whole downstream stack — NLU routing (Spec 03), the dispatch turn (Spec 04 §3.6), act-then-describe (Spec 05 §3) — is built to consume *a transcript*. This spec owns everything between the user's breath and that transcript, and everything between a `Done(confirmationText)` and the user's ear. It is deliberately a *thin* spec about a *thin* layer: the Voice layer is a leaf (Spec 04 §2.2) whose entire job is to turn audio into text and text into audio, honestly and fast, without ever touching storage, the model, or the network.

This document specifies:

1. **The Voice layer's formal contract** — the `SpeechInput`/`SpeechOutput` seams behind Spec 04 §3.8's `SpeechEngine` summary, and the `Transcript` object that crosses the boundary (§2)
2. **The capture model** — push-to-talk, the tap-to-toggle variant, the journal's continuous mode, the mic-lifecycle invariant, and the wake-word deferral (§3)
3. **Interim vs. final transcript semantics** — who consumes each, the exactly-one-final rule, finalization triggers, and the ASR floor (§4)
4. **STT engine selection** — the on-device mandate, the per-platform engine matrix (iOS/macOS, Windows, Android), and vocabulary biasing (§5)
5. **TTS** — engine selection, what gets spoken, and screen-reader deference (§6)
6. **Barge-in and latency targets** — the voice layer's obligations under Spec 04 §4.3's cancellation policy, with numeric budgets (§7)
7. **The voice-privacy statement** — exactly what audio and what transcript text exists where, what (if anything) leaves the device, and under which consent — the statement Spec 08 §5.5 presumes (§8)
8. **Error and degrade behavior** — mis-hear, no-speech, permission revoked, engine unavailable, TTS failure — every one landing on a surface, never a dead end (§9)
9. **Accessibility** (§9.5) and **staging** against the current text-first v0 app (§10)

It does **not** cover: what a transcript *means* (routing, slots, corrections — Spec 03); who drives the turn (the `DispatchOrchestrator`, Spec 04 §3.6); how the interim subtitle and the orb *look* (Spec 07 §7.3, §8.4 — this spec owns capture and transcript semantics, Spec 07 owns the visual surface, and the line between them is drawn precisely in §4.3); the consent mechanics for a final transcript reaching Claude during residual routing (Spec 08 §5.2/§5.6 — voice adds no new consent tier, §8.4); or notification sounds (Spec 04 §3.13).

---

## 1. Governing Principles

**P2.1 — Voice is uncompromising, so the pipeline must be unremarkable.** The user says what they naturally say; Plenara figures it out. The voice layer's contribution to that promise is *fidelity and speed*, nothing more: deliver what was said, as text, fast, and let the NLU layer (Spec 03) do the understanding. The voice layer never interprets, never filters, never "helps" — a transcript is delivered verbatim as the engine produced it, and normalization (lowercasing, disfluency stripping) is Spec 03 §5.4's job, downstream, where it is testable against recorded pairs.

**P2.2 — Text is an overlay, one pipeline.** A typed submission from the quiet overlay (Spec 07 §7.2) enters `DispatchOrchestrator.dispatch` as a final `Transcript` with `source: typed` — the identical object, the identical pipeline (research §6.2). There is no separate text command path, and nothing downstream of the `Transcript` may branch on its source except diagnostics.

**P2.4 — Code over AI, applied to the one unavoidable model.** STT is the single place in the free tier where a model's output enters the system uninspected. The posture is the same as Spec 03's toward classifiers: treat the output as *untrusted text*, never as ground truth — the ASR floor gates obviously-failed recognition (§4.6), the correct-and-learn loop absorbs systematic mis-hearings (research §6.3's SpeechAnalyzer accuracy trade-off is *designed* to be absorbed this way), and no engine-reported confidence is ever load-bearing beyond the advisory floor (echoing Spec 03 §7.3.1's measured distrust of self-reported confidence).

**P2.5 — Aggressive layering: Voice is a leaf.** Per Spec 04 §2.1–2.2: the Voice layer knows only the Business Logic seam. Transcripts flow *up* on a stream; `speak(text)` calls flow *down*; the layer never touches storage, the registry, NLU, the network, or a widget. Platform engines are selected at the composition root (Spec 04 §2.3) behind the same interfaces on every platform.

**P2.8 — No silent failure.** A revoked mic permission, a missing language pack, a dead engine, an empty capture — every voice failure is a *named state with a surface* (§9), and the load-bearing one is automatic: when speech input cannot work, the app switches to text mode *and says so* (Spec 05 §13 E2). Voice being broken never means Plenara is broken, because text parity is total (P2.2).

**Audio is the most intimate data class in the app — the privacy bar is "it never exists."** Records sync as files; transcripts live in the Stream; but raw audio is never written to disk, never leaves the device, and ceases to exist the moment transcription completes (§8). This is stricter than any other data class's handling and it is deliberate: it converts "trust our audio handling" into "there is no audio to handle."

**Offline-first.** The entire voice pipeline — capture, STT, TTS — runs with the radio off, on every platform, in every mode (Spec 04 §6.1 lists STT/TTS in the offline contract). This is not an aspiration; it is enforced by the on-device mandate of §5.1, which forbids cloud STT outright rather than merely preferring its absence.

---

## 2. Position in the Architecture: Two Seams, One Layer

### 2.1 `SpeechInput` and `SpeechOutput`

Spec 04 §3.8 summarized one `SpeechEngine` (`startListening()`, `stopListening()`, `speak(text)`, `Stream<Transcript>`); Spec 09 §3.1 independently named two planned seams, `SpeechInput` and `SpeechOutput`, and marked them **[GAP]**. This spec resolves the naming in Spec 09's favor — input and output have different platform backends, different failure modes, different fakes, and no shared state, so one interface would be a false unit. **`SpeechEngine` survives as the collective name** for the pair (the composition-root registration and Spec 04's layer table need no restructuring — see §10 X3). The contracts:

```dart
/// The capture seam. Platform-backed (§5), selected at the composition root.
abstract class SpeechInput {
  /// True iff a usable engine, language model, and mic permission are all
  /// present. Callers check this before offering the voice affordance;
  /// false is a *state* (text mode engages, §9.2), never an exception.
  bool get available;

  /// Interim and final transcripts for the active capture session.
  /// Cold stream; never holds a caller reference (Spec 04 §2.2 up-flow rule).
  Stream<TranscriptEvent> get transcripts;

  /// Open the mic and begin recognition in the given mode (§3).
  /// Idempotent while a session is live. Throws typed VoiceError (§9.1)
  /// on permission/engine failure — before any audio is captured.
  Future<void> startListening(CaptureMode mode);

  /// End the session and force finalization: the engine flushes and emits
  /// exactly one final TranscriptEvent (possibly empty, §4.2). PTT release
  /// and the journal's stop both land here.
  Future<void> stopListening();

  /// Abort the session, discarding audio and emitting NO final transcript.
  /// Used when a capture is superseded (barge-in on a barge-in) or the
  /// user cancels mid-hold.
  Future<void> cancelListening();

  /// Smoothed input level while a session is live — the orb's listening
  /// amplitude (Spec 07 §8.4), surfaced to the UI through a Business Logic
  /// view-model projection, never by the UI subscribing to this layer
  /// directly (P2.5).
  Stream<double> get micLevel;
}

enum CaptureMode { pushToTalk, toggle, journal }   // §3

/// The synthesis seam.
abstract class SpeechOutput {
  bool get available;                               // engine + a usable voice

  /// Speak one utterance. Returns when playback STARTS (not ends) so the
  /// orchestrator is never blocked on audio duration. At most one speak
  /// is active; a new call queues behind the current one within a turn
  /// and supersedes it across turns.
  Future<void> speak(String text, {required String turnId});

  /// Halt playback now — the barge-in obligation, budget ≤ 150 ms (§7.1).
  Future<void> stop();

  /// started / finished / stopped(turnId) — the timing signals the subtitle
  /// assistant-slot lifecycle consumes (Spec 07 §7.3: appear on start,
  /// linger 4 s after finish).
  Stream<SpeakEvent> get events;
}
```

### 2.2 The `Transcript` object

The one shape that crosses the Voice → Business Logic boundary, and the shape `dispatch(Transcript)` (Spec 04 §3.6) already names:

```dart
class TranscriptEvent {
  final String utteranceId;      // one id per capture session; ties interims to their final
  final String text;             // verbatim engine output — normalization is NLU's (Spec 03 §5.4)
  final bool isFinal;            // §4: exactly one true per session
  final TranscriptSource source; // voice | typed
  final DateTime capturedAt;     // wall time at finalization; NluContext freezes its own clock (Spec 03 §2.6)
  final double? engineConfidence; // advisory only — consumed solely by the ASR floor (§4.6), never by routing
}
enum TranscriptSource { voice, typed }
```

A typed overlay submission is constructed by the Business Logic façade as a single `TranscriptEvent(isFinal: true, source: typed, engineConfidence: null)` with a fresh `utteranceId` — it never passes through `SpeechInput` at all, which is what keeps the Voice layer honest about owning *speech*, not *input*.

### 2.3 Who drives what

The Voice layer is driven, never driving (Spec 04 §2.2 — leaves are not intermediaries):

- The user's press/tap on the orb is a **UI event** → the Business Logic façade calls `SpeechInput.startListening` / `stopListening`. The Voice layer has no gesture knowledge.
- A **final** transcript is handed by the Business Logic layer to `DispatchOrchestrator.dispatch` (Spec 04 §4.2 stage 1). The Voice layer never calls the orchestrator.
- The orchestrator's `Done(confirmationText)`, clarification prompts, and error surfaces reach `SpeechOutput.speak` via the orchestrator (Spec 04 §3.6/§3.8). *What* is spoken — including the never-speak-sensitive-values-unprompted rule — is decided upstream (Spec 07 §5.4, Spec 05); `SpeechOutput` renders exactly the string it is given.
- Testing: both seams ship with fakes from day one (`FakeSpeechInput` emits scripted interim/final sequences; `FakeSpeechOutput` records speak calls), per Spec 09 D2 — only the razor-thin platform shims get the one-time human mic smoke.

---

## 3. The Capture Model

### 3.1 Push-to-talk is primary (v1, locked)

**Press-and-hold the orb; speak; release.** Locked at research §15.1 ("push-to-talk first; wake word is later polish") and assumed by Spec 04 §4.3 ("push-to-talk-first, single-user, voice-led") and Spec 07 §8.4. Semantics:

- Press → `startListening(pushToTalk)`; the orb snaps to *listening* (`m-instant`, Spec 07 §8.4) only after capture is actually open (§7.2 budget: ≤ 150 ms), so the visual state never lies about the mic.
- Release → `stopListening()` → the engine flushes → exactly one final transcript (§4.2).
- A press shorter than **250 ms with no speech detected** is treated as accidental: `cancelListening()`, no final, no surface. The first few such taps in PTT mode show a one-line "hold to talk" hint; after that, silence (quiet by default, Spec 07 P8).
- Push-to-talk costs nothing at idle — no open mic, no always-on audio, no battery draw (research §6.5). The mic-lifecycle invariant (§3.5) falls out for free.

### 3.2 Tap-to-toggle (setting; desktop default)

Press-and-hold is hostile to some motor abilities and awkward on a desktop with a mouse. **Tap-to-toggle** is the same session with different delimiters: tap → `startListening(toggle)`; the session ends on a second tap, on `stopListening` via the "cancel"/escape affordance, or on **silence endpointing** — a trailing silence of `endpointSilence` (default **1.2 s**, user-adjustable 0.8–3.0 s, §9.5) finalizes the utterance. It is a per-device setting; it is the **default on desktop** (the current dogfood platform — a held mouse button is nobody's preferred microphone) and an offered accessibility option everywhere. Keyboard parity on desktop: a hold-key binding behaves as §3.1, a tap of the same key as §3.2.

### 3.3 Journal continuous mode (Spec 05 §11)

The 60-second voice journal is the one long-form capture. `startListening(journal)` semantics, matching F8's flow exactly:

- Continuous recognition up to a hard **60 s** window; long-form-capable engine required (§5.2–§5.4 name which per platform).
- The session ends on: the window closing; an explicit stop (tap/release — always available); or the **stop word** — a trailing, isolated "done" *followed by ≥ 1 s of silence*. The trailing-and-silent guard is what keeps "I'm done with the migraine phase, thankfully" mid-entry from truncating the entry; the stop word is stripped from the final text. When in doubt the engine keeps listening — an over-long entry is trimmable, a truncated one is lost.
- The final transcript is handed to the invoking journal skill as the entry body — it does **not** re-enter NLU routing (the skill was already dispatched; the body is content, not a command).
- The privacy invariants of Spec 05 §11 bind here mechanically: audio is processed in memory and discarded at finalization, never written to disk (§8.1); transcription is on-device only, which in journal mode is doubly enforced because §5.1's mandate leaves no cloud engine to reach anyway. E2/E3 (zero-speech abandon; transcription-failure re-offer) are Spec 05's surfaces; this layer's job is to emit the empty final or the typed `sttFailed` error that triggers them.

### 3.4 Wake word: deferred, and the seam is already shaped for it

"Hey Plenara" (Porcupine — on-device, low single-digit CPU, covers all four target platforms, research §6.5) is deferred to the ambient rung (research §11.5; "later polish," §15.1). Nothing in v1 blocks it: a wake-word detector is just another *initiator* of `startListening(toggle)` — the capture session, transcript semantics, and privacy statement are unchanged. What it *does* newly require, recorded now so it isn't forgotten: an always-on (on-device, buffer-discarding) detector loop, acoustic echo cancellation once speak/listen can overlap (§7.1 note), and a resolved answer to Spec 07 Q3 (how "idle but armed" reads without feeling surveilled). All three are Q3 of this spec's decision record.

### 3.5 The mic-lifecycle invariant

**The microphone is open if and only if a capture session is live**, and a capture session is live if and only if the orb shows *listening*. No pre-warming with an open mic, no trailing capture after finalization, no audio buffered across sessions. Mic permission is requested on the **first press of the orb** — in context, when the user is expressing intent to speak — never at app launch. This invariant is the technical substrate of the privacy statement (§8.1) and is testable: the fake-backed harness asserts no `startListening` without a driving event and no session outliving its `stopListening`/`cancelListening`.

### 3.6 Speak and listen are mutually exclusive (v1)

At most one of `SpeechInput` capturing / `SpeechOutput` playing is active at any instant. A capture start while speech is playing is a **barge-in**: `SpeechOutput.stop()` completes (≤ 150 ms, §7.1) *before* the mic opens. This ordering means the mic never hears the app's own voice, which is why v1 needs no echo cancellation — a real simplification that push-to-talk buys and wake word will eventually spend (§3.4).

---

## 4. Transcript Semantics: Interim vs. Final

### 4.1 Two kinds of event, two consumers, no exceptions

- **Interim** transcripts (`isFinal: false`) are live, revisable hypotheses — words may be rewritten as the engine refines. They have **exactly one consumer**: the subtitle user-slot (Spec 07 §7.3), rendered dimmed-provisional. They are never dispatched (Spec 03 §10 MD10; Spec 04 §4.2: "only the final transcript enters the pipeline… so a turn starts exactly once per utterance"), never persisted, never written to the diagnostic log, never fed to NLU, and cease to exist when superseded (§8.2).
- **Final** transcripts (`isFinal: true`) are emitted **exactly once per capture session**, at finalization, and are the sole voice-side input to `DispatchOrchestrator.dispatch`. An **empty final** (silence, or nothing recognizable) produces **no turn**: the orb returns to idle, the subtitle slot clears, nothing is spoken and nothing enters the Stream — silence answered with silence (Spec 05 §11 E2 generalizes: an empty capture is abandoned quietly). The "didn't catch that" surface is reserved for the ASR floor (§4.6) — *speech happened but was unusable* — never for *no speech*.

### 4.2 Finalization triggers, per mode

| Mode | Finalizes on |
|---|---|
| `pushToTalk` | release (`stopListening`) → engine flush |
| `toggle` | second tap / stop affordance, **or** trailing silence ≥ `endpointSilence` (§3.2) |
| `journal` | 60 s window, explicit stop, or the guarded stop word (§3.3) |

One session, one `utteranceId`, one final. If the engine emits nothing on flush, the layer synthesizes the empty final itself — the Business Logic layer must never be left waiting on a session that quietly died (P2.8).

### 4.3 The ownership line with Spec 07 §7.3, drawn once

**This spec owns what a transcript *is*; Spec 07 owns what it *looks like*.** Concretely: this spec defines the event stream, revisability, the exactly-one-final rule, finalization triggers, emptiness, the ASR floor, and the never-dispatched/never-persisted status of interims. Spec 07 §7.3 defines the two-slot subtitle region, the dimmed-provisional style, the solidify-on-final weight change, the two-line discipline, and the assistant-slot linger. Spec 04 §4.2's live-subtitle sentence cites its rendering contract from Spec 07 §7.3 (per Spec 07 X4) and its dispatch contract from this section. Neither spec restates the other's half.

### 4.4 Verbatim delivery; normalization is downstream

The Voice layer delivers the engine's text as produced — casing, punctuation, disfluencies and all. Spec 03 §5.4 owns normalization (lowercase, strip disfluencies, canonicalize numbers/units) because the corpus template match depends on *its* normalization being the single, versioned, testable one. Two normalizers would mean corpus keys silently diverging from live traffic. The one transformation this layer performs is journal stop-word stripping (§3.3), which is a capture-delimiter concern, not text processing.

### 4.5 Vocabulary biasing (the hook into §5)

Where the platform engine supports recognition biasing (SFSpeechRecognizer `contextualStrings`, research §6.3; analogous hints elsewhere, §5), the Voice layer accepts a **bias list** assembled by the Business Logic layer: contact display names and aliases (the `entityNames` universe, Spec 03 §2.6), capability `displayName`s and template phrases, and high-frequency literal tokens from the user's learned corpus templates. This is the cheapest accuracy lever the pipeline has — "Mia," "reconnect," and the user's own tracker names are exactly what generic language models mis-hear, and exactly what routing most needs verbatim. The list is rebuilt on the same triggers as the `CapabilityIndex` (registry change, entity change — Spec 01 §5.4) and **never leaves the device**: it is only ever handed to an on-device engine (§5.1), so the fact that it contains every contact's name creates no disclosure (§8.3).

### 4.6 The ASR floor

When the engine reports utterance-level confidence and it falls below `θ_asr` (default **0.30**, configurable), or the engine signals recognition failure outright, the final transcript is delivered flagged below-floor and the orchestrator surfaces Spec 05 §3.2's line — "I didn't quite catch that. Could you say that again?" — instead of routing garbage. Rules: the floor is **advisory-confidence's only job** (P2.4 — engine confidence is never a routing input, mirroring Spec 03 §7.3.1's finding that self-reported confidence is uncalibrated everywhere it's been measured); a below-floor transcript is *shown* in the subtitle (the user should see what was heard — it's often informative) but not dispatched; two consecutive below-floor captures offer text mode ("Want to type it instead?") rather than looping. Calibrating `θ_asr` per engine is Q2. *(Housekeeping: Spec 05 §3.2 cites the ASR floor to "Spec 03 §3.5," which is the cloud-escalation section and has no such floor — the concept lives here; §10 X5.)*

### 4.7 Mis-hearing is not this layer's problem to fix

A *confident but wrong* transcript ("log a tree-K run") is indistinguishable from a right one at this layer, and no voice-side second-guessing is permitted (P2.1 — the layer never interprets). The system's real defenses live downstream and are already specified: the act-then-describe description makes the mis-hear visible in one line, `"correct"` re-routes it (Spec 03 §2.7), undo reverses it (Spec 04 §3.11), and the corrections corpus absorbs *systematic* mis-hearings the same way it absorbs phrasing variation — research §6.3 explicitly prices SpeechAnalyzer's higher word-error rate against this loop. The one voice-side contribution is biasing (§4.5), which prevents the most damaging class (proper nouns) at the source.

---

## 5. STT Engine Selection & the On-Device Mandate

### 5.1 The mandate: Plenara never uses cloud STT — on any platform, in any mode

**Decision (D2, the load-bearing one).** Every STT path in Plenara is on-device. When an on-device engine is unavailable — permission revoked, language pack missing, hardware too old — the app degrades to **text mode** (§9.2), never to a platform cloud recognizer. Enforcement is by construction, not preference flags read hopefully: engines that *can* go to the network are configured with their on-device-only setting as a hard requirement (per-platform mechanics below), and an engine that cannot guarantee on-device operation is not an eligible backend at the composition root.

Why absolute rather than best-effort: (a) Spec 08 §5.5 already promises it — the master table's STT/TTS row reads **"Never"** with no consent tier, and this spec is that row's normative source; a "usually on-device" engine would make that row false. (b) Spec 05 §11's journal invariant ("no cloud STT; on-device transcription only") cannot hold for one mode if the same engine session type reaches the network in another. (c) The research doc's own platform survey flags the trap this mandate exists to avoid: Android's `SpeechRecognizer` "uses Google STT by default (requires network)" (research §6.3) — the *default* on one of our four platforms is a silent third-party disclosure of everything the user says. The mandate converts that from a per-platform footnote into a single testable invariant. (d) It makes the privacy statement (§8) one sentence instead of a matrix.

The cost is honest and accepted: on-device recognition trails the best cloud recognizers in accuracy, and older devices may lack it entirely. The min-OS decision already leans into this ("target the latest major OS versions to use state-of-the-art APIs (e.g. SpeechAnalyzer), accepting reduced reach" — research §15.1), and the correct-and-learn loop absorbs WER (§4.7).

### 5.2 iOS / macOS (P1 and P4)

- **Primary: SpeechAnalyzer** (iOS 26 / macOS 26) — on-device, no network path at all, free, long-form-capable (covers journal mode), automatic language detection, ~2× faster than Whisper Large V3 Turbo on Apple Silicon at a modestly higher WER (research §6.3 — the accepted trade). The min-OS decision makes this the normal case, not the lucky one.
- **Fallback: SFSpeechRecognizer** (sub-26 devices) with **`requiresOnDeviceRecognition = true` as a hard requirement** — if on-device recognition is unsupported for the locale/device, the recognizer is treated as unavailable (→ text mode), never allowed to fall through to Apple's server path. `contextualStrings` carries the §4.5 bias list; SpeechAnalyzer's vocabulary-customization equivalent is used where exposed.
- **Flutter bridges:** `liquid_speech` (SpeechAnalyzer) and `speech_to_text` (SFSpeechRecognizer) per research §6.3, wrapped behind `SpeechInput` — bridge choice is a composition-root detail the layers above never see.

### 5.3 Windows (P2 — the current dogfood platform)

- **Turn capture (v1 working choice): WinRT `SpeechRecognizer`** — built-in, offline, well-suited to short command-length utterances (research §6.3). Zero added binary weight.
- **Journal / long-form: Whisper.cpp** with a small quantized model via a platform channel — WinRT is not built for 60 s of free dictation; Whisper.cpp is the research doc's named offline fallback for exactly this ("longer dictation or offline use"). Whisper's initial-prompt mechanism carries the §4.5 bias list.
- **Open (Q1):** whether Whisper.cpp should take *turn* capture too, giving Windows one engine and one quality bar at the price of model load latency and binary size. Decide from the dogfood spike's measured WER and time-to-first-interim on real hardware — this is the first platform where voice will actually be lived with, so the spike (§10.1) settles it with data, not taste.

### 5.4 Android (P3)

- **Android `SpeechRecognizer` in on-device mode only** (supported Android 10+, research §6.3; the min-OS posture keeps us comfortably above that). The network-backed default path is **prohibited** (§5.1) — if on-device recognition is absent for the device/locale, the recognizer is unavailable, full stop.
- **Fallback: Whisper.cpp** via platform channel (research §6.3's "no Google dependency, works offline") — likely also the journal engine, mirroring the Windows split.
- **TTS-adjacent note:** the same on-device discipline applies to any Google-provided language packs — pack *download* is a one-time explicit act with the network, not per-utterance traffic, and is surfaced as such (§9.2's language-pack repair item).

### 5.5 What "engine selection" is not

There is no runtime engine picker, no per-utterance engine racing, and no cloud-STT "quality boost" tier — one engine per (platform, mode) pair, chosen at the composition root, swappable only by build. The `SpeechInput` seam is precisely so this table can change per platform generation (SpeechAnalyzer arriving, Whisper models shrinking) with zero churn above the Voice layer (research §9.2's original intent for `SpeechEngine`).

---

## 6. Text-to-Speech

### 6.1 Engine matrix — platform-native, offline, one per platform

Per research §6.4, adopted without contest — every platform's native synthesizer is offline-capable and good-to-high quality:

| Platform | Engine | Notes |
|---|---|---|
| iOS / macOS | `AVSpeechSynthesizer` | High quality; enhanced/Siri-class voices via one-time on-device download |
| Android | Android `TextToSpeech` | Good (Google TTS engine, on-device voices) |
| Windows | WinRT `SpeechSynthesizer` | Good; neural voices on Win 11+ |

One voice per install, chosen from the platform's installed voices in Settings (default: the platform's best available local voice for the app locale); consistent across all utterance kinds — the assistant is one presence, not a cast. Speech rate is user-adjustable (§9.5) and the platform's default rate is the default.

### 6.2 What is spoken

`SpeechOutput.speak` is called by the orchestrator with, and only with: the `Done(confirmationText)` line (Spec 04 §3.6 — "the resolved artifact of the very plan the interpreter applied"), clarification and follow-up questions (Spec 03 §2.4/§6.3), residual offers, error surfaces (Spec 04 §5.2's spoken forms), nudge/briefing deliveries, and generative openers (first sentence spoken, rest on the card — Spec 07 §7.3's length discipline). Content policy is entirely upstream: the sensitive-values rule (never read a `sensitive` value aloud unprompted) is Spec 07 §5.4's and is applied before the string reaches this layer. Every spoken word is simultaneously on screen (subtitle assistant slot, Spec 07 §7.3, driven by this layer's `SpeakEvent`s) — TTS is a channel, never the sole carrier.

### 6.3 Muting and quiet mode

"Quiet mode" mutes TTS (one of Spec 07 §7.1's two persisted booleans). A muted `speak` still emits `SpeakEvent`s so the subtitle lifecycle is identical with audio off — Spec 07 §7.3's "no visual difference" rule falls out of this mechanically. TTS engine *failure* is distinct from muting and is §9.4.

### 6.4 Screen-reader deference

When a platform screen reader is active (VoiceOver / TalkBack / Windows Narrator), Plenara's own TTS **defaults to muted** and the app relies on properly-labeled semantics + the always-on subtitles, so two synthesized voices never fight over the same content. The user can re-enable app TTS explicitly (some users prefer the app's voice for content and the reader for chrome). This is a hard requirement, not polish — same class as Spec 07 §8.2's reduced-motion rule.

---

## 7. Barge-In & Latency Targets

### 7.1 Barge-in, the voice layer's half

Spec 04 §4.3 owns the turn-level policy (pre-write-barrier: cancel the live turn; post-barrier: queue). Spec 07 §7.4 owns the visual (soft fade, orb snap, `TurnCancelled` in the Stream). This layer owns the audio mechanics, in order:

1. PTT press (or toggle tap) arrives while `SpeechOutput` is playing → `stop()` — playback halts within **≤ 150 ms** (perceived-instant; the fade Spec 07 describes lives inside this budget).
2. Only after `stop()` completes does the mic open (§3.6 mutual exclusion — no self-hearing, no AEC needed in v1).
3. The Business Logic layer signals the orchestrator's `cancel(turnId)` per Spec 04 §4.3; the Voice layer neither knows nor cares whether the turn was cancelled or queued.

A barge-in during *capture* (press while already listening — possible in toggle mode) is `cancelListening()` + fresh `startListening`: new session, new `utteranceId`, no final from the abandoned one.

### 7.2 Latency budgets (normative targets, measured at the seam)

Voice-first lives or dies on turn tempo — Spec 07 §8.2's beat rule ("a voice turn's `Done` line must be visible within the same beat as the spoken word 'Done'") needs numbers underneath it. Targets are p50 / p95 on the min-spec device per platform; the Spec 09 harness records them from day one (they are seam-level and fake-excludable, so CI tracks the real shims only in the platform smoke):

| Segment | p50 | p95 |
|---|---|---|
| Orb press → mic open + *listening* state shown | 100 ms | 150 ms |
| Speech onset → first interim in the subtitle | 350 ms | 700 ms |
| Interim update cadence while speaking | ≤ 300 ms between revisions | — |
| PTT release → final transcript delivered | 300 ms | 700 ms |
| `speak()` call → audible speech onset | 250 ms | 500 ms |
| **End-to-end: release → spoken `Done` begins (corpus-hit turn)** | **1.0 s** | **2.0 s** |
| Barge-in: press → playback silent | 100 ms | 150 ms |
| Journal: stop → finalized 60 s transcript | 1.5 s | 3.0 s (SpeechAnalyzer-class engines are faster than real-time; Whisper.cpp sizing to meet this is part of Q4) |

The end-to-end row is the product number: a deterministic corpus-hit turn (Spec 03 §5 — the steady-state majority) has no inference in it, so voice I/O is the *whole* latency budget, and one spoken second is the difference between "assistant" and "voicemail." Residual (Haiku) turns add the measured ~0.8–1.2 s cloud latency (Spec 08 §3.1) on top and are exempt from the end-to-end row; detached operations never block voice at all (Spec 04 §4.7).

---

## 8. The Voice-Privacy Statement

This section is the statement Spec 08 §5.5 presumes (its STT/TTS row cites "Spec 06" today; §10 X2) and Spec 10 scopes out to it. It is written, like Spec 08 §5, to be checked against code.

### 8.1 Audio

**Raw audio never exists at rest and never leaves the device — no exceptions, no consent tier that could permit it.** Capture is processed in memory by an on-device engine (§5.1) and the buffers are discarded at finalization. Audio is never written to disk (Spec 05 §11's journal invariant, here generalized to *every* capture mode), never included in any record, log, diagnostic export, or sync payload, and never transmitted anywhere by Plenara. There is no audio-retention setting because there is no audio retention. The mic-lifecycle invariant (§3.5) bounds when audio can even transiently exist: only during a user-initiated, orb-visible capture session.

### 8.2 Interim transcripts

Ephemeral by contract (§4.1): rendered to the subtitle, superseded, gone. Never persisted, never logged (including the local diagnostic log — only the *final* transcript is a turn, and only turns are logged), never dispatched, never leave the device.

### 8.3 Final transcripts — the honest edges

A final transcript is *text*, and it flows where the user's words are supposed to flow. Stated plainly:

- **On-device:** it enters the Conversation Stream (visible history), the local diagnostic log (device-local, redacted-on-export per Spec 11), and — via dispatch — whatever records the routed skill writes (which then sync as records under Spec 06's rules, like any user data). The journal transcript is the record body and follows Spec 05 §11's stated posture (syncs to the user's own provider; provider-unreadability deferred with §8.7 encryption; onboarding says so).
- **Off-device, exactly one path:** on the paid tier, a *novel* phrasing's final transcript is sent **verbatim** to Anthropic as the residual-routing utterance, under the standing tier-(a) consent granted at key connection, with the free/offline tiers never sending it — exactly as specified in Spec 08 §5.2/§5.6. **Voice changes nothing here and adds no new consent**: the transcript's exposure is identical whether the words were spoken or typed (P2.2, one pipeline). The onboarding sentence Spec 08 §5.6 mandates ("it will send that sentence — and only it") is the disclosure; this spec's contribution is that *audio* is categorically not part of that sentence.
- **The bias list (§4.5)** — contact names, capability names, corpus literals — is handed only to on-device engines and never serialized anywhere off-device.

### 8.4 The consent chain, complete

1. **OS microphone permission** — requested in context at first orb press (§3.5); revocable at the OS at any time, and revocation lands on the named text-mode degrade (§9.2), never a silent breakage.
2. **Tier-(a) BYOK consent** (Spec 08 §5.6) — covers the final-transcript-to-Haiku residual path. Not a voice consent; it exists identically for typed input.
3. **There is no third item.** No audio consent exists because no audio use exists (§8.1). STT and TTS appear in Spec 08 §5.5 as a "Never / –" row, and this spec is what makes that row true by construction.

### 8.5 Platform honesty notes (for onboarding/privacy copy)

- On-device engines are the *platform's* models; their language packs may be downloaded from the platform vendor (a one-time, user-visible act, §5.4) — recognition traffic itself never leaves.
- In **text mode**, the user may invoke their OS keyboard's own dictation feature; that audio path belongs to the OS vendor's privacy policy, not Plenara's envelope. The privacy copy should say so in one sentence rather than let Plenara's "audio never leaves" claim be misread as covering the OS keyboard (Q7 owns the wording).
- Deeper adversarial analysis (malware with mic access, platform-vendor trust) is Spec 10's domain; Spec 10 currently points STT terms at Spec 08 — retarget to this section (§10 X4).

---

## 9. Errors & Degradation

### 9.1 The sealed error set (cross-spec addition to Spec 04 §5.1)

```dart
sealed class VoiceError { }
class MicPermissionDenied  extends VoiceError {}   // OS permission absent/revoked
class SttUnavailable       extends VoiceError { String reason; } // no engine / language pack / init failure
class SttFailed            extends VoiceError {}   // session died mid-capture (engine fault)
class TtsUnavailable       extends VoiceError {}   // no usable synthesis voice
```

(`noSpeech` and below-floor are deliberately *not* errors — they are normal outcomes with defined handling, §4.1/§4.6.) The set extends Spec 04 §5.1's layer table with a Voice row; the mapping below extends §5.2's surface map. Recorded as suite-sync item X6.

### 9.2 The surface map — every failure lands somewhere actionable

| Failure | Behavior + surface |
|---|---|
| `MicPermissionDenied` | **Auto-engage text mode** with the honest line — "Microphone access isn't available — switching to text mode." (Spec 05 §13 E2, verbatim). Orb renders visibly muted (Spec 07 §8.4). Action: OS-settings deep link. Re-grant is detected on next foreground; voice re-offers itself quietly, never with fanfare. |
| `SttUnavailable` | Auto-engage text mode with the reason named ("Speech recognition isn't available on this device — [language pack missing / not supported]"), plus an **AttentionSurface** entry (Spec 04 §3.12) carrying the fix where one exists (download the pack). Persistent state, so a persistent surface — not a per-launch toast. |
| `SttFailed` (mid-capture) | The session emits no final; the app says "Something went wrong with the microphone — try again?" once. Two consecutive failures → treat as `SttUnavailable` for the session (text mode + attention item) rather than looping the user through retries. |
| Below the ASR floor | "I didn't quite catch that. Could you say that again?" (Spec 05 §3.2); transcript shown-not-dispatched; two consecutive → offer text mode (§4.6). |
| No speech (empty final) | No turn, no surface — quiet no-op (§4.1). |
| `TtsUnavailable` | **Subtitles already carry full output parity** (Spec 07 §7.3 — always on), so nothing is lost; but per P2.8 it is *named once* per install-state change ("I can't speak aloud on this device right now — you'll see everything as text") and noted in Settings. Never a repeating nag. |
| Engine hang (no final within timeout) | Watchdog: a session with no event for 10 s after `stopListening` is force-cancelled → `SttFailed` path. The orchestrator is never left awaiting a transcript that will not come. |

The design center: **text mode is the universal safe state**, reachable automatically from every voice failure, with full functional parity (Spec 05 §13). Voice failures are inconveniences, never outages.

### 9.3 What is *not* degraded

Free-tier capability, offline operation, and subtitle behavior are untouched by any voice failure — they never depended on voice working. Conversely, no voice failure is ever "repaired" by reaching for a cloud engine (§5.1); availability is not a reason to break the privacy statement.

### 9.4 Diagnostics

Voice events in the local diagnostic log record *shapes, not content* beyond the turn transcript already logged by the turn machinery: session mode, durations, finalization trigger, error kinds, latency measurements (§7.2). No interim text, no audio, no bias-list contents. Export redaction is Spec 11's, unchanged.

### 9.5 Accessibility (hard requirements)

- **Motor:** tap-to-toggle capture everywhere (§3.2); `endpointSilence` adjustable 0.8–3.0 s for slow or pause-heavy speech; no interaction anywhere requires press-and-hold (P1 of Spec 07 — and the orb's hold gesture always has the toggle alternative).
- **Hearing / deaf users:** the app is fully usable with TTS off or absent — subtitles are always on (Spec 07 §7.3) and text mode is complete (P2.2). No information is audio-only, ever (this is why notification sounds are Spec 04 §3.13's problem *with* visible counterparts).
- **Speech and voice differences:** dysarthric, accented, or atypical speech will fare as the platform engine fares — the honest posture is: biasing (§4.5) helps proper nouns; the ASR-floor path offers text quickly rather than making the user fail repeatedly (§4.6's two-strike rule); and text mode is a first-class permanent choice, not a punishment. Plenara never requires voice.
- **Screen readers:** §6.4's deference rule; all voice-state chrome (orb states, muted state, text-mode state) carries semantic labels.
- **TTS rate/pitch:** user-adjustable within the platform voice's supported range; persisted.
- Reduced-motion and visual accessibility are Spec 07 §8.2's and unchanged by this spec.

---

## 10. Staging & Suite-Sync Corrections

### 10.1 Staging against the v0 app

The current `app/lib/main.dart` is text-first by design ("Text-first for now; voice later") — the typed path through `Session.handle` is exactly the P2.2 pipeline this spec keeps, so nothing is thrown away. The rungs:

1. **Seams first (any time, cheap):** land `SpeechInput`/`SpeechOutput` + `TranscriptEvent` with fakes and the `FakeSpeechInput`-driven E2E tier — this closes Spec 09 §3.1's **[GAP]** and §6.2 O3's blocked path *before* any platform shim exists, and refactors the ChatScreen send path to construct a typed `TranscriptEvent` (behavior-neutral).
2. **Windows spike (dogfood):** WinRT turn capture + Whisper.cpp journal capture behind the seams; measure WER, time-to-first-interim, and the §7.2 budgets on real hardware; settle Q1. This is the "voice spike" Spec 09 O3 waits on. *(Honesty note: research §11.2's walking skeleton lists "spoken confirmation" in v0; the actual v0 shipped text-first. The skeleton's voice leg lands here, with the spike — recorded, not hidden.)*
3. **v1.5 rung (Spec 07 §10 step 2):** the Stage, orb, subtitle region, and quiet overlay arrive together with this pipeline on the P1 platform (SpeechAnalyzer); latency budgets become CI-tracked numbers.
4. **Ambient rung (v3):** wake word per §3.4, gated on Q3.

### 10.2 Corrections for the next reconciliation pass (this spec edits no other file)

- **X1 — Retarget "Spec 06 — Voice" citations → Spec 12:** Spec 03 §0 (scope exclusion), §1 P2.5 ("Spec 06 signals a final transcript"); Spec 04 §0 (scope), §3.8 ("Defined at research §9.2 and Spec 06"); Spec 08 §0 (scope) and §5.5 (STT/TTS row, twice). Spec 04 §4.2's subtitle sentence splits per §4.3's ownership line: rendering cite → Spec 07 §7.3 (already Spec 07 X4), dispatch-semantics cite → this spec §4.1.
- **X2 — Spec 08 §5.5 STT/TTS row** gains this spec as its normative source ("configured on-device per Spec 12 §5.1").
- **X3 — `SpeechEngine` naming:** Spec 04 §2.3 (component inventory) and §3.8 note the split into `SpeechInput`/`SpeechOutput` (this spec §2.1), with `SpeechEngine` retained as the collective/layer name; Spec 09 §3.1's planned seam names are confirmed as-is.
- **X4 — Spec 10 out-of-scope line** ("the voice pipeline's STT privacy characteristics… belong to Spec 08") → belong to Spec 12 §8; Spec 08 carries only the consent-tier framing.
- **X5 — Spec 05 §3.2 ASR-floor miscite** ("Spec 03 §3.5") → this spec §4.6.
- **X6 — Spec 04 §5.1/§5.2** gain the `VoiceError` row and surfaces of §9.1–§9.2.

---

## 11. Decision Record

### Resolved

- **D1 — Two seams, one layer.** The Voice layer is `SpeechInput` + `SpeechOutput` (adopting Spec 09's names; `SpeechEngine` survives as the collective), a strict leaf per Spec 04 §2.2: transcripts up a stream, `speak` down a call, platform selection at the composition root, fakes from day one. The `TranscriptEvent` is the single boundary object; typed overlay input is the same object with `source: typed` — one pipeline (P2.2). *(§2)*
- **D2 — No cloud STT, ever — the on-device mandate.** All speech recognition is on-device on every platform in every mode, enforced by construction (hard on-device engine flags; ineligible otherwise); unavailability degrades to text mode, never to a networked recognizer. This is the normative source for Spec 08 §5.5's "Never" row and the generalization of Spec 05 §11's journal invariant. Accepted costs: platform-trailing accuracy (absorbed by the correct-and-learn loop, research §6.3) and reduced reach on old devices (consistent with the min-OS decision, research §15.1). *(§5.1)*
- **D3 — Engine matrix.** iOS/macOS: SpeechAnalyzer primary; SFSpeechRecognizer with `requiresOnDeviceRecognition = true` + `contextualStrings` as sub-26 fallback. Windows: WinRT for turn capture (pending Q1), Whisper.cpp for journal/long-form. Android: on-device `SpeechRecognizer` only (the network default is prohibited), Whisper.cpp fallback. One engine per (platform, mode); no runtime picker. *(§5.2–§5.5)*
- **D4 — Capture model.** Push-to-talk (press-and-hold the orb) is primary, per the locked research §15.1 decision; tap-to-toggle with silence endpointing (default 1.2 s, adjustable) is a setting and the desktop default; the journal's continuous 60 s mode uses the guarded trailing stop word; wake word is deferred to the ambient rung with the seam already shaped for it. Mic-lifecycle invariant: mic open ⇔ session live ⇔ orb listening; permission asked at first press. *(§3)*
- **D5 — Interim/final semantics.** Interims feed the subtitle user-slot only (Spec 07 §7.3) — never dispatched, persisted, or logged; exactly one final per session, the sole dispatch input (reaffirming Spec 03 MD10 / Spec 04 §4.2); an empty final is a quiet no-op, not an error. Ownership line with Spec 07 drawn at §4.3: this spec owns what a transcript is, Spec 07 owns how it renders. *(§4.1–§4.3)*
- **D6 — Verbatim delivery.** The Voice layer performs no text normalization (Spec 03 §5.4 owns the single normalizer); the only transform is journal stop-word stripping, a capture-delimiter concern. *(§4.4)*
- **D7 — The voice-privacy statement.** Audio never exists at rest and never leaves the device — no path, no consent tier, no retention setting; interims are ephemeral; a final transcript's only off-device path is the existing tier-(a) residual-routing consent (Spec 08 §5.2/§5.6), identical for spoken and typed input — **voice adds zero new disclosure and zero new consent**. The bias list (contact/capability names) is handed only to on-device engines. *(§8)*
- **D8 — TTS is platform-native, offline, one consistent voice**; speak and listen are mutually exclusive in v1 (no AEC needed); muted speech still emits `SpeakEvent`s so subtitles behave identically (Spec 07 D8); app TTS defers to an active screen reader by default. *(§6, §3.6)*
- **D9 — Latency budgets are normative** (§7.2 table), headlined by release → spoken-`Done` ≤ 1.0 s p50 on a corpus-hit turn and barge-in silence ≤ 150 ms; measured at the seams from the first spike, CI-tracked from the v1.5 rung. *(§7)*
- **D10 — The failure design center is text mode as the universal safe state.** Sealed `VoiceError` set; every failure auto-lands on text mode and/or an AttentionSurface item with the reason named (mic permission → Spec 05 §13 E2 verbatim; missing pack → repair item; TTS loss → named once, subtitles carry). No-speech is silent; the ASR floor (advisory confidence < 0.30, the *only* use of engine confidence — P2.4) re-asks once and offers text on the second strike; confident mis-hears belong to the downstream describe/correct/undo/corpus loop, never to voice-side second-guessing. *(§4.6–§4.7, §9)*
- **D11 — Vocabulary biasing** from contact names/aliases, capability display names + template phrases, and corpus literals; rebuilt on registry/entity change; on-device only. The cheapest proper-noun accuracy lever the pipeline has. *(§4.5)*
- **D12 — Accessibility requirements are hard:** toggle capture everywhere, adjustable endpointing, complete no-audio operation (subtitles + text mode), screen-reader deference, adjustable TTS rate. Plenara never *requires* voice. *(§9.5)*

### Open

- **Q1 — Windows turn-capture engine.** WinRT vs. Whisper.cpp-for-everything on the dogfood platform: decide from the spike's measured WER, time-to-first-interim, and model-load latency on min-spec hardware (§5.3). Whisper-for-all buys one quality bar; WinRT buys zero binary weight and instant start.
- **Q2 — ASR-floor calibration.** `θ_asr = 0.30` is a launch guess and engine confidence-reporting reliability varies (and may echo Spec 03's uncalibrated-confidence finding); calibrate per engine against recorded below-floor/above-floor captures during the spike, and confirm which engines report usable utterance confidence at all.
- **Q3 — Wake word prerequisites** (ambient rung): Porcupine integration, acoustic echo cancellation once speak/listen can overlap, the always-armed buffer-discard audit against §8.1's "audio never exists at rest," and Spec 07 Q3's "armed without surveillance" orb reading. All four before "Hey Plenara" ships.
- **Q4 — Whisper.cpp sizing.** Model choice/quantization per platform (binary budget vs. WER vs. the §7.2 journal-finalization budget), and whether one multilingual model or per-locale packs. Interacts with Q5.
- **Q5 — Locale & multilingual.** v1 is single-locale (device locale); SpeechAnalyzer's automatic language detection and mixed-language utterances are deferred — and must land together with Spec 03's multilingual-embedder swap note (§3.2) or routing quality silently diverges from transcription language.
- **Q6 — Word-timing events.** Karaoke subtitles (Spec 07 Q4) wait on TTS word-boundary callbacks being reliable cross-platform; this layer would carry them as `SpeakEvent` extensions if/when Spec 07 wants them.
- **Q7 — Privacy copy for the OS-dictation edge.** The one-sentence onboarding/privacy wording for §8.5's honest note that OS keyboard dictation in text mode is outside Plenara's audio envelope; owned with Spec 08 Q5's Anthropic-terms copy pass.

---

*End of Spec 12 — Voice v0.1*
