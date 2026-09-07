# Spec 12 — Voice

> **⚠ AMENDED 2026-07-28 (`G-52`) — capture is USER-DELIMITED.** Automatic end-of-speech detection
> is REMOVED on every engine. Tap to start, tap again to stop-and-send; the ✕ (or mute) discards.
> This supersedes: §3.1's push-to-talk-as-primary (PTT is dropped for touch platforms — Luis
> approved amending the `plenara_research.md` §15.1 lock in-session), §3.2's silence endpointing and
> its user-adjustable `endpointSilence` (0.8–3.0s) setting, and §9.5/D12's "adjustable endpointing"
> accessibility requirement — which is now satisfied *by construction*, since nothing endpoints and
> a pause of any length can no longer truncate an utterance.
>
> What replaces it: the VAD/engine becomes a SEGMENTER (Whisper needs ~30s chunks) plus a watchdog —
> 15s with no speech cancels, 30s of trailing silence stops-and-SENDS, 120s is a hard cap (60s on
> Apple). Watchdogs key off **speech activity**, not off recognizer
> output, so thinking before you speak cannot be mistaken for silence. An auto-stop always sends and
> always says so — never a silent discard. On the OS-engine path (Windows/Apple) the engine's own
> finals are ACCUMULATED and never forwarded as independent turns; a deliberate stop trigger (tap
> or watchdog) or an unavoidable native session closure flushes the whole capture through one
> idempotent finalization door. Forwarding each engine final would have meant SAPI still endpointed
> and this change never reached that platform at all.

**Status:** Active v0.4 — audited against the wired implementation 2026-09-07. Tap-to-start/
tap-to-stop, native-final convergence, latest-partial recovery, on-device recognition, capture
watchdogs, transcript diagnostics by build channel, `SpeechRecognizer`, `SpeechOutput`, iOS voice
selection, and typed/voice convergence through `VoiceTurnController.send` are wired. Long-form
journal capture, wake word, downloadable local models, and output-only mute remain destinations.
**A note on numbering:** Specs 03, 04, and 08 cite a "Spec 06 — Voice" that was never written — the research doc's spec charter (§12) never listed a voice spec, and slot 6 was taken by Data & Sync. This document is that missing spec, chartered as **Spec 12**. It is the referent every "Spec 06 — Voice" citation intends; retargeting those citations (and Spec 10's mis-pointed ownership line) is a suite-sync pass item recorded in §10, not something this spec edits in place.
**Depends on:** Research doc (§2.1–2.3, §6.1–6.5, §9.1–9.2, §11.2–11.5, §15.1); Spec 03 — NLU / Intent (§1 P2.5, §2.6–2.7, §5.4 normalization, §10 MD10 — final-transcript-only); Spec 04 — Architecture (§2.1–2.3 layer model, §3.6 `DispatchOrchestrator`, §3.8 `SpeechEngine`, §4.2 turn pipeline, §4.3 barge-in policy, §5 error model); Spec 05 — Functional (§3.2 ASR floor, §11 voice journal F8, §13 offline/subtitle F10); Spec 07 — UI (§7 quiet overlay & subtitle contract, §8.4 the orb); Spec 08 — AI Cost & Privacy (§5.2 routing payload, §5.5 master table, §5.6 consent tiers)
**Blocks:** no shipped voice surface. This remains the normative source for Spec 08's STT/TTS
privacy row and for future long-form/wake-word/model work.

---

## 0. Purpose & Scope

Plenara is voice-first (P2.1): free-form speech is the primary input, and the whole downstream stack — NLU routing (Spec 03), the dispatch turn (Spec 04 §3.6), act-then-describe (Spec 05 §3) — is built to consume *a transcript*. This spec owns everything between the user's breath and that transcript, and everything between a `Done(confirmationText)` and the user's ear. It is deliberately a *thin* spec about a *thin* layer: the Voice layer is a leaf (Spec 04 §2.2) whose entire job is to turn audio into text and text into audio, honestly and fast, without ever touching storage, the model, or the network.

This document specifies:

1. **The Voice layer's formal contract** — the shipped `SpeechRecognizer` callback seam and
   `SpeechOutput`, plus the richer conceptual transcript contract retained for future evolution (§2)
2. **The capture model** — tap-to-start/tap-to-stop, watchdog/native-closure finalization, the journal's future continuous mode, the mic-lifecycle invariant, and the wake-word deferral (§3)
3. **Interim vs. final transcript semantics** — who consumes each, the exactly-one-final rule, finalization triggers, and the ASR floor (§4)
4. **STT engine selection** — the on-device mandate, the per-platform engine matrix (iOS/macOS, Windows, Android), and vocabulary biasing (§5)
5. **TTS** — engine selection, what gets spoken, screen-reader deference, and the shipped v0 talk-back (§6)
6. **Barge-in and latency targets** — the voice layer's obligations under Spec 04 §4.3's cancellation policy, with numeric budgets (§7)
7. **The voice-privacy statement** — exactly what audio and what transcript text exists where, what (if anything) leaves the device, and under which consent — the statement Spec 08 §5.5 presumes (§8)
8. **Error and degrade behavior** — mis-hear, no-speech, permission revoked, engine unavailable, TTS failure — every one landing on a surface, never a dead end (§9)
9. **Accessibility** (§9.5) and the current realization/future boundaries (§10)

It does **not** cover: what a transcript *means* (routing, slots, corrections — Spec 03); who drives the turn (the `DispatchOrchestrator`, Spec 04 §3.6); how the interim subtitle and the orb *look* (Spec 07 §7.3, §8.4 — this spec owns capture and transcript semantics, Spec 07 owns the visual surface, and the line between them is drawn precisely in §4.3); the consent mechanics for a final transcript reaching Claude during residual routing (Spec 08 §5.2/§5.6 — voice adds no new consent tier, §8.4); or notification sounds (Spec 04 §3.13).

---

## 1. Governing Principles

**P2.1 — Voice is uncompromising, so the pipeline must be unremarkable.** The user says what they naturally say; Plenara figures it out. The voice layer's contribution to that promise is *fidelity and speed*, nothing more: deliver what was said, as text, fast, and let the NLU layer (Spec 03) do the understanding. The voice layer never interprets, never filters, never "helps" — a transcript is delivered verbatim as the engine produced it, and normalization (lowercasing, disfluency stripping) is Spec 03 §5.4's job, downstream, where it is testable against recorded pairs.

**P2.2 — Text and speech converge on one turn pipeline.** The current controller receives either a
typed string or a final recognizer callback, then calls `VoiceTurnController.send`, which invokes
the same `Session.handle` route/execution path and conversation ledger. There is no concrete common
`TranscriptEvent` object today; parity is enforced at the shared controller method.

**P2.4 — Code over AI, applied to the one unavoidable model.** STT is the single place in the free
tier where a model's output enters the system uninspected. Treat that output as *untrusted text*,
never as ground truth. The current recognizer exposes no useful confidence and therefore has no
numeric ASR floor (§4.6); the act-then-describe, correction, and undo paths make a mis-hear visible
and recoverable downstream.

**P2.5 — Aggressive layering: Voice is a leaf.** Per Spec 04 §2.1–2.2, the Voice layer knows only
its controller-facing seam. Recognition arrives through callbacks and `speak(text)` calls flow
down; the layer never touches storage, the registry, NLU, the network, or a widget. Platform engines
are selected at the composition root (Spec 04 §2.3) behind the same interfaces on every platform.

**P2.8 — No silent failure.** A revoked mic permission, a missing language pack, a dead engine, an empty capture — every voice failure is a *named state with a surface* (§9), and the load-bearing one is automatic: when speech input cannot work, the app switches to text mode *and says so* (Spec 05 §13 E2). Voice being broken never means Plenara is broken, because text parity is total (P2.2).

**Audio is the most intimate data class in the app — the privacy bar is "it never exists."** Records sync as files; transcripts live in the Stream; but raw audio is never written to disk, never leaves the device, and ceases to exist the moment transcription completes (§8). This is stricter than any other data class's handling and it is deliberate: it converts "trust our audio handling" into "there is no audio to handle."

**Offline-first.** The entire voice pipeline — capture, STT, TTS — runs with the radio off, on every platform, in every mode (Spec 04 §6.1 lists STT/TTS in the offline contract). This is not an aspiration; it is enforced by the on-device mandate of §5.1, which forbids cloud STT outright rather than merely preferring its absence.

---

## 2. Position in the Architecture: Two Seams, One Layer

### 2.1 Shipped `SpeechRecognizer`/`SpeechOutput` and the destination contract

Input and output are separate leaf seams. The shipped input interface is `SpeechRecognizer`
(`init`, `available`, `levels`, callback-based `listen`, `stop`, synchronous `cancel`) and its
implementations are `SystemSpeechRecognizer`, optional local-model recognition, and
`NoopSpeechRecognizer`. The shipped output interface is `SpeechOutput`. The richer stream-based
`SpeechInput`/`TranscriptEvent` sketch below is retained as a destination contract, not a class map
of the current source:

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
  /// exactly one final TranscriptEvent (possibly empty, §4.2). The user's
  /// second tap and the journal's future stop both land here.
  Future<void> stopListening();

  /// Abort the session, discarding audio and emitting NO final transcript.
  /// Used when a capture is superseded (barge-in on a barge-in) or the
  /// user cancels mid-hold.
  Future<void> cancelListening();

  /// Smoothed input level while a session is live — the orb's listening
  /// amplitude (Spec 07 §8.4), surfaced to Plena through the controller
  /// view-model projection, never by the UI subscribing to this layer
  /// directly (P2.5).
  Stream<double> get micLevel;
}

enum CaptureMode { toggle, journal }   // §3; journal remains a target mode

/// The synthesis seam — SHIPPED (v0, `app/lib/speech_out.dart`); §6.5 owns
/// the utterance-lifecycle guarantees behind it.
abstract class SpeechOutput {
  /// One-time engine setup at the composition root; failure lands as
  /// `available: false`, never a throw the caller must handle.
  Future<void> init();

  bool get available;   // engine initialized + a usable voice
  bool get speaking;    // an utterance is in flight — the barge-in check (§7.1)

  /// Speak one utterance. Fire-and-forget: the caller never awaits audio
  /// duration. [onStart] fires at real audio onset; [onDone] fires exactly
  /// once when THIS utterance ends — natural finish OR stop() — unless a
  /// newer speak() superseded it first (the newer call then owns the
  /// callbacks; the stale one goes silent, §6.5). At most one utterance is
  /// active: a new speak() stops the current one — supersede, never queue.
  Future<void> speak(String text,
      {void Function()? onStart, void Function()? onDone});

  /// Halt playback now — the barge-in obligation, budget ≤ 150 ms (§7.1).
  /// Resolves the in-flight speak(): its onDone fires once.
  Future<void> stop();
}
```

Two deltas from draft v0.1's `SpeechOutput`, both deliberate. (a) The `Stream<SpeakEvent>` became **per-utterance callbacks**: a shared event stream is un-identified, which is exactly the cross-fire hazard §6.5's generation token exists to close — binding `onStart`/`onDone` at the call site gives each utterance its own timing signals with no correlation step, and the subtitle/caption lifecycle Spec 07 §7.3 consumes rides these callbacks instead. (b) `turnId` is gone — turn identity lives with the caller, which already holds the callbacks; and cross-turn queueing was dropped for supersede-always, since turns serialize upstream anyway. `NoopSpeechOutput` is the shipped silent implementation (tests, injected sessions, platforms without a voice): `available: false`, and each `speak` fires `onStart`/`onDone` immediately so lifecycle-dependent code runs identically.

### 2.2 Destination `TranscriptEvent`; current string boundary

The following remains the intended richer boundary object. It is **not implemented** in the current
app:

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

Today, `SpeechRecognizer.onResult(text, isFinal)` supplies strings. Only the accumulated final
string is sent. Typed text enters the same `VoiceTurnController.send(String)` method directly.

### 2.3 Who drives what

The Voice layer is driven, never driving (Spec 04 §2.2 — leaves are not intermediaries):

- The user's tap on an explicit voice target (or non-interactive Plena space) is a UI event;
  `VoiceTurnController` calls `SpeechRecognizer.listen`/`stop`. The recognizer has no gesture
  knowledge.
- A final transcript is handed to `VoiceTurnController.send`, which adapts the turn to
  `Session.handle`. The Voice layer never calls routing or execution directly.
- The orchestrator's `Done(confirmationText)`, clarification prompts, and error surfaces reach `SpeechOutput.speak` via the orchestrator (Spec 04 §3.6/§3.8). *What* is spoken — including the never-speak-sensitive-values-unprompted rule — is decided upstream (Spec 07 §5.4, Spec 05); `SpeechOutput` renders exactly the string it is given.
- Testing uses fake `SpeechRecognizer`/`SpeechOutput` implementations and `NoopSpeechRecognizer`/
  `NoopSpeechOutput`; platform shims receive simulator/host integration coverage.

---

## 3. The Capture Model

### 3.1 Tap-to-start / tap-to-stop is the only touch capture gesture

The first tap calls `startListening(toggle)`; the second calls `stopListening()` and sends. The
explicit × or mute action calls `cancelListening()` and discards. The listening form appears only
after capture has positively opened, so the visual state never lies about the microphone. No
interaction depends on press-and-hold, and a pause in speech is never interpreted as the user's
chosen end boundary.

### 3.2 Native segmentation and recovery stops

Platform recognizers may emit several native finals inside one user-delimited capture. Plenara
accumulates those segments and dispatches only once. A native session closure, error, watchdog, or
explicit stop converges on one idempotent finalization door. The current recognizer retains the
latest non-empty partial beside completed segments, so a native `done` callback that omits its final
payload still flushes the words the user saw on screen exactly once.

Watchdogs recover abandoned sessions rather than infer conversational intent: 15 seconds with no
speech cancels, 30 seconds of trailing silence stops and sends, and 120 seconds is the hard cap. An
automatic stop is visible. These are safety/resource bounds; the ordinary boundary remains the
second tap.

### 3.3 Journal continuous mode (destination; Spec 05 §11)

No separate long-form `journal` capture mode is implemented. Typed or ordinary voice commands can
write journal records through the normal turn pipeline. If a dedicated 60-second capture mode is
added, its destination semantics are:

- Continuous recognition up to a hard **60 s** window; long-form-capable engine required (§5.2–§5.4 name which per platform).
- The session ends on: the window closing; an explicit stop (tap/release — always available); or the **stop word** — a trailing, isolated "done" *followed by ≥ 1 s of silence*. The trailing-and-silent guard is what keeps "I'm done with the migraine phase, thankfully" mid-entry from truncating the entry; the stop word is stripped from the final text. When in doubt the engine keeps listening — an over-long entry is trimmable, a truncated one is lost.
- The final transcript is handed to the invoking journal skill as the entry body — it does **not** re-enter NLU routing (the skill was already dispatched; the body is content, not a command).
- The privacy invariants of Spec 05 §11 bind here mechanically: audio is processed in memory and discarded at finalization, never written to disk (§8.1); transcription is on-device only, which in journal mode is doubly enforced because §5.1's mandate leaves no cloud engine to reach anyway. E2/E3 (zero-speech abandon; transcription-failure re-offer) are Spec 05's surfaces; this layer's job is to emit the empty final or the typed `sttFailed` error that triggers them.

### 3.4 Wake word: deferred, and the seam is already shaped for it

"Hey Plenara" (Porcupine — on-device, low single-digit CPU, covers all four target platforms, research §6.5) is deferred to the ambient rung (research §11.5; "later polish," §15.1). Nothing in v1 blocks it: a wake-word detector is just another *initiator* of `startListening(toggle)` — the capture session, transcript semantics, and privacy statement are unchanged. What it *does* newly require, recorded now so it isn't forgotten: an always-on (on-device, buffer-discarding) detector loop, acoustic echo cancellation once speak/listen can overlap (§7.1 note), and a resolved answer to Spec 07 Q3 (how "idle but armed" reads without feeling surveilled). All three are Q3 of this spec's decision record.

### 3.5 The mic-lifecycle invariant

**The microphone is open if and only if a capture session is live**, and a live capture is reflected
by Plena's listening state. No pre-warming, trailing capture after finalization, or audio buffered
across sessions. Permission is requested on the first explicit capture action, never at app launch.
Fake-backed tests assert no `listen` without that action and no session outliving `stop`/`cancel`.

### 3.6 Speak and listen are mutually exclusive (v1)

At most one of `SpeechRecognizer` capture / `SpeechOutput` playback is active. Capture start while
speech is playing is a **barge-in**: `SpeechOutput.stop()` completes before the mic opens. This
ordering keeps the mic from hearing Plena's own voice; wake word would spend that simplification.

---

## 4. Transcript Semantics: Interim vs. Final

### 4.1 Two kinds of event, two consumers, no exceptions

- **Interim** transcripts (`isFinal: false`) are live, revisable hypotheses — words may be rewritten as the engine refines. Their only product consumer is the subtitle user-slot (Spec 07 §7.3), rendered dimmed-provisional. They are never dispatched (Spec 03 §10 MD10; Spec 04 §4.2: "only the final transcript enters the pipeline… so a turn starts exactly once per utterance"), never persisted as user records, and never fed to NLU. Internal diagnostic capture is the sole non-product observer and follows Spec 11's build-channel policy; external builds capture none.
- **Final** transcripts (`isFinal: true`) are emitted at most once per capture session through
  `RecognitionSession.finish` and are the sole voice-side input to
  `VoiceTurnController.send`/`Session.handle`. An empty final produces no turn. Repeated empty/no-
  match captures surface a microphone/text hint rather than routing garbage.

### 4.2 Finalization triggers, per mode

| Mode | Finalizes on |
|---|---|
| `toggle` | second tap / stop affordance; native closure or a visible recovery watchdog also converges on finalization (§3.2) |
| `journal` (destination) | a future long-form mode may use an explicit stop, bounded window, or guarded stop word (§3.3) |

One session, one `utteranceId`, one final. All completion signals — explicit stop, watchdog, native
`done`/error, and stop-call completion — converge on one idempotent finalization door. A native
engine `final` remains only a segment boundary. On Apple, a native session may instead end after
showing only an interim hypothesis; in that case the latest visible interim is promoted to the
session final rather than silently discarded. An explicit cancel is the only completion path that
discards recognized text. If the engine emits nothing on flush, the layer synthesizes the empty
final itself — the Business Logic layer must never be left waiting on a session that quietly died
(P2.8).

### 4.3 The ownership line with Spec 07 §7.3, drawn once

**This spec owns recognizer callback/finalization semantics; Spec 07 owns what the resulting text
looks like.** Current partial/final callbacks, exactly-once accumulated finalization, emptiness, and
the never-dispatched status of interims live here. No stream-based transcript contract or numeric
ASR floor is current. Spec 07 owns provisional/final caption rendering and assistant-reply linger.

### 4.4 Verbatim delivery; normalization is downstream

The Voice layer delivers the engine's text as produced — casing, punctuation, disfluencies and
all. Spec 03 §5.4 owns normalization because corpus matching needs one deterministic normalizer.
The future dedicated journal mode may strip its guarded stop word as a capture delimiter (§3.3);
the current ordinary capture path performs no such transform.

### 4.5 Vocabulary biasing (destination)

The shipped `speech_to_text` call passes no contact/capability bias list. If a future backend exposes
reliable local vocabulary hints, Business Logic may assemble contact aliases, capability names,
and learned literals; the list must remain on-device.

### 4.6 The ASR floor

The current `SpeechRecognizer` callback does not expose engine confidence, so no numeric ASR floor
is implemented. Engine errors/native closure converge through finalization; repeated captures with
no usable text surface a mic-permission/text-mode hint. A future confidence field may add an
advisory floor, but it must not become a routing score.

### 4.7 Mis-hearing is not this layer's problem to fix

A confidently wrong transcript ("log a tree-K run") is indistinguishable from a right one at this
layer, and no voice-side second-guessing is permitted (P2.1 — the layer never interprets). The
system's defenses live downstream: the description makes the mis-hear visible, `"correct"`
re-routes it (Spec 03 §2.7), undo reverses it (Spec 04 §3.11), and the corrections corpus absorbs
systematic phrasing variation. Vocabulary biasing is only a possible future mitigation (§4.5); the
current recognizer supplies no hint list.

---

## 5. STT Engine Selection & the On-Device Mandate

### 5.1 The mandate: Plenara never uses cloud STT — on any platform, in any mode

**Decision (D2, the load-bearing one).** Every STT path in Plenara is on-device. When an on-device engine is unavailable — permission revoked, language pack missing, hardware too old — the app degrades to **text mode** (§9.2), never to a platform cloud recognizer. Enforcement is by construction, not preference flags read hopefully: engines that *can* go to the network are configured with their on-device-only setting as a hard requirement (per-platform mechanics below), and an engine that cannot guarantee on-device operation is not an eligible backend at the composition root.

Why absolute rather than best-effort: (a) Spec 08 §5.5 already promises it — the master table's STT/TTS row reads **"Never"** with no consent tier, and this spec is that row's normative source; a "usually on-device" engine would make that row false. (b) Spec 05 §11's journal invariant ("no cloud STT; on-device transcription only") cannot hold for one mode if the same engine session type reaches the network in another. (c) The research doc's own platform survey flags the trap this mandate exists to avoid: Android's `SpeechRecognizer` "uses Google STT by default (requires network)" (research §6.3) — the *default* on one of our four platforms is a silent third-party disclosure of everything the user says. The mandate converts that from a per-platform footnote into a single testable invariant. (d) It makes the privacy statement (§8) one sentence instead of a matrix.

The cost is honest and accepted: on-device recognition trails the best cloud recognizers in accuracy, and older devices may lack it entirely. The min-OS decision already leans into this ("target the latest major OS versions to use state-of-the-art APIs (e.g. SpeechAnalyzer), accepting reduced reach" — research §15.1), and the correct-and-learn loop absorbs WER (§4.7).

### 5.2 iOS / macOS (P1 and P4)

- **Current:** `speech_to_text` wraps Apple's speech recognizer and the single options builder sets
  `onDevice: true` (mapped to `requiresOnDeviceRecognition`). Unsupported device/locale state
  degrades to text mode.
- **Destination:** SpeechAnalyzer may replace the bridge if measured platform coverage and quality
  justify it; it is not a current dependency.
- **Current Flutter bridge:** `speech_to_text`, configured through the single
  `plenaraSpeechOptions` builder with `onDevice: true`, behind `SpeechRecognizer`.
  SpeechAnalyzer and downloadable local-model alternatives remain implementation options, not
  current dependencies.

### 5.3 Windows (P2 — the current dogfood platform)

- **Current:** provisioned `sherpa_onnx` local Whisper is preferred for turn capture; the system
  recognizer is the zero-provisioning fallback. The model is manually provisioned today.
- **Destination:** first-run model download and a distinct long-form journal mode.

### 5.4 Android (P3)

- **Android `SpeechRecognizer` in on-device mode only** (supported Android 10+, research §6.3; the min-OS posture keeps us comfortably above that). The network-backed default path is **prohibited** (§5.1) — if on-device recognition is absent for the device/locale, the recognizer is unavailable, full stop.
- **Fallback: Whisper.cpp** via platform channel (research §6.3's "no Google dependency, works offline") — likely also the journal engine, mirroring the Windows split.
- **TTS-adjacent note:** the same on-device discipline applies to any Google-provided language packs — pack *download* is a one-time explicit act with the network, not per-utterance traffic, and is surfaced as such (§9.2's language-pack repair item).

### 5.5 What "engine selection" is not

There is no runtime engine picker, per-utterance racing, or cloud-STT quality tier. The
`SpeechRecognizer` seam lets the composition root change platform backends without changing the
controller.

---

## 6. Text-to-Speech

### 6.1 Engine matrix — platform-native, offline, one per platform

Per research §6.4, adopted without contest — every platform's native synthesizer is offline-capable and good-to-high quality:

| Platform | Engine | Notes |
|---|---|---|
| iOS / macOS | `AVSpeechSynthesizer` | High quality; enhanced/Siri-class voices via one-time on-device download |
| Android | Android `TextToSpeech` | Good (Google TTS engine, on-device voices) |
| Windows | WinRT `SpeechSynthesizer` | **Shipped** (v0, via `flutter_tts` → WinRT/SAPI — §6.5); the default local voice is honestly mediocre, and that is the accepted cost of the offline mandate |

One voice per install, consistent across utterance kinds. On iOS, Settings exposes installed
Enhanced/Premium English voices and persists the user's selection; without a valid explicit choice,
the engine selects the best installed local voice. Other platforms use their local default. The
current engine fixes rate at `0.5` and pitch at `1.0`; user-adjustable rate/pitch is not shipped.

### 6.2 What is spoken

`SpeechOutput.speak` is called by the orchestrator with, and only with: the `Done(confirmationText)` line (Spec 04 §3.6 — "the resolved artifact of the very plan the interpreter applied"), clarification and follow-up questions (Spec 03 §2.4/§6.3), residual offers, error surfaces (Spec 04 §5.2's spoken forms), nudge/briefing deliveries, and generative openers (first sentence spoken, rest on the card — Spec 07 §7.3's length discipline). Content policy is entirely upstream: the sensitive-values rule (never read a `sensitive` value aloud unprompted) is Spec 07 §5.4's and is applied before the string reaches this layer. Every spoken word is simultaneously on screen (subtitle assistant slot, Spec 07 §7.3, driven by this layer's `onStart`/`onDone` lifecycle, §2.1) — TTS is a channel, never the sole carrier.

### 6.3 Muting and quiet mode

The single persisted `voiceMuted` setting both selects the text-first posture and suppresses TTS.
A muted turn never reaches `speak`; captions and durable ledger output still carry the reply.
Muting mid-utterance stops playback immediately (§6.5). TTS engine failure is distinct from muting
and is §9.4. Independent output-only mute remains a destination (Spec 07 §7.1).

### 6.4 Screen-reader deference

The UI provides semantic labels and complete text/caption operation, but automatic screen-reader
detection and TTS muting are not implemented. That remains a release accessibility destination so
two synthesized voices do not compete.

### 6.5 Shipped: the v0 talk-back (two-way voice is live)

As of v0 (July 2026), the talk-back half of the loop is real: Plena speaks every reply aloud through the shipped `SpeechOutput` seam (`app/lib/speech_out.dart`), wired in `app/lib/main.dart` to her *speaking* presence (Spec 15 §3.1/§4.1). What shipped, and the guarantees an implementer or auditor should hold it to:

- **Engine — offline, on-device, per the §6.1 matrix.** `FlutterTtsSpeechOutput` wraps
  `flutter_tts` on every shipped platform, reaching the installed system voices (including Apple
  voices on iOS/macOS and WinRT/SAPI on Windows). The iOS composition configures its playback
  session and exposes a persisted installed-voice picker. Windows build note: the plugin restores
  its WinRT dependencies via NuGet, and `build.cmd` fetches `nuget.exe` once if absent.
- **Per-utterance generation token — the exactly-once guarantee.** `init()` sets `awaitSpeakCompletion(true)`, so the engine's speak future resolves *per utterance* — on natural end **or** on `stop()`. Each `speak()` takes an incrementing generation; completion state and `onDone` are driven from that future, gated on the generation still being current — never from the engine's shared, un-identified handlers. A stale event from a superseded utterance can therefore never cross-fire a newer utterance's callbacks, and `onDone` fires exactly once per non-superseded call.
- **Animation anchoring.** `onStart` — driven by the engine's start handler — anchors Plena's *speaking* state to real audio onset, not to the `speak()` call; `onDone` (natural end or barge-in stop) ends it, and the caption clears a beat (~1.6 s) later, so captions follow actual speech rather than a guessed duration.
- **Safety timer.** A cap scaled to response length (3 s + 75 ms/char, clamped 4–60 s) guarantees the speaking state and caption always clear even if the engine never reports completion. It is deliberately generous: it exists to catch a dead engine, never to cut speech off mid-sentence.
- **Barge-in and mute, wired (§7.1's obligations).** Starting to listen (tap/mic) stops in-flight speech *before* the mic opens (§3.6's ordering, exactly); muting stops it immediately (captions still carry, §6.3); and a new turn's send stops any still-playing prior reply.

---

## 7. Barge-In & Latency Targets

### 7.1 Barge-in, the voice layer's half

Spec 04 §4.3 owns the turn-level policy (pre-write-barrier: cancel the live turn; post-barrier: queue). Spec 07 §7.4 owns the visual (soft fade, orb snap, `TurnCancelled` in the Stream). This layer owns the audio mechanics, in order:

1. Capture tap arrives while `SpeechOutput` is playing → `stop()` — playback halts within **≤ 150 ms** (perceived-instant; the fade Spec 07 describes lives inside this budget).
2. Only after `stop()` completes does the mic open (§3.6 mutual exclusion — no self-hearing, no AEC needed in v1).
3. The Business Logic layer signals the orchestrator's `cancel(turnId)` per Spec 04 §4.3; the Voice layer neither knows nor cares whether the turn was cancelled or queued.

A barge-in during *capture* (press while already listening — possible in toggle mode) is `cancelListening()` + fresh `startListening`: new session, new `utteranceId`, no final from the abandoned one.

Steps 1–2 are shipped in v0 exactly as written: the listen handler awaits `SpeechOutput.stop()` before the mic opens, and mute and a new send take the same in-flight-speech kill path (§6.5).

### 7.2 Latency budgets (normative targets, measured at the seam)

Voice-first lives or dies on turn tempo — Spec 07 §8.2's beat rule ("a voice turn's `Done` line must be visible within the same beat as the spoken word 'Done'") needs numbers underneath it. Targets are p50 / p95 on the min-spec device per platform; the Spec 09 harness records them from day one (they are seam-level and fake-excludable, so CI tracks the real shims only in the platform smoke):

| Segment | p50 | p95 |
|---|---|---|
| Orb press → mic open + *listening* state shown | 100 ms | 150 ms |
| Speech onset → first interim in the subtitle | 350 ms | 700 ms |
| Interim update cadence while speaking | ≤ 300 ms between revisions | — |
| Stop tap → final transcript delivered | 300 ms | 700 ms |
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

Interims are never dispatched, stored as user records, added to the conversation ledger, synced, or
sent to a model. Internal/development builds deliberately retain recognizer hypotheses in local raw
diagnostics so capture failures can be reconstructed; external builds capture none. Spec 11 is the
sole authority for retention/export, and raw audio remains forbidden in every channel.

### 8.3 Final transcripts — the honest edges

A final transcript is *text*, and it flows where the user's words are supposed to flow. Stated plainly:

- **On-device:** it enters the durable conversation/action ledger (Spec 17), the device-local diagnostic log according to Spec 11's build channel (content-bearing and manually raw-exportable in internal dogfood; absent from external raw logs), and — via dispatch — whatever records the routed skill writes. The journal transcript is the record body and follows Spec 05 §11's stated sync posture.
- **Off-device, exactly one path:** on the paid tier, a *novel* phrasing's final transcript is sent **verbatim** to Anthropic as the residual-routing utterance, under the standing tier-(a) consent granted at key connection, with the free/offline tiers never sending it — exactly as specified in Spec 08 §5.2/§5.6. **Voice changes nothing here and adds no new consent**: the transcript's exposure is identical whether the words were spoken or typed (P2.2, one pipeline). The onboarding sentence Spec 08 §5.6 mandates ("it will send that sentence — and only it") is the disclosure; this spec's contribution is that *audio* is categorically not part of that sentence.
- **Future vocabulary hints (§4.5)** must remain on-device. The current recognizer assembles and
  sends no contact, capability, or corpus bias list.

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

### 9.1 Destination typed error set

The shipped seam reports availability, exceptions, `SpeechNotice`, and `onDone`; it does not define
these classes. The following remains the intended typed expansion if platform-specific recovery
needs outgrow the current controller state:

```dart
sealed class VoiceError { }
class MicPermissionDenied  extends VoiceError {}   // OS permission absent/revoked
class SttUnavailable       extends VoiceError { String reason; } // no engine / language pack / init failure
class SttFailed            extends VoiceError {}   // session died mid-capture (engine fault)
class TtsUnavailable       extends VoiceError {}   // no usable synthesis voice
```

(`noSpeech` and below-floor are deliberately *not* errors — they are normal outcomes with defined handling, §4.1/§4.6.) The set extends Spec 04 §5.1's layer table with a Voice row; the mapping below extends §5.2's surface map. Recorded as suite-sync item X6.

### 9.2 Failure-surface destination and current floor

Current behavior always clears capture state, preserves/finalizes heard text unless explicitly
cancelled, shows capture notices, and leaves the typed field available. The richer OS-settings deep
links, language-pack repair entries, confidence-floor surface, and sealed-error mapping in this
table are destinations unless independently implemented:

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

Voice diagnostics follow Spec 11, the sole collection/export authority. Internal dogfood traces may contain final transcripts and interim recognizer hypotheses so a failed native capture can be reconstructed; external raw capture/export is disabled. Raw audio and bias-list contents are never logged.

### 9.5 Accessibility (hard requirements)

- **Motor:** tap-to-toggle capture everywhere (§3.1); pauses do not endpoint ordinary speech, and no interaction anywhere requires press-and-hold.
- **Hearing / deaf users:** the app is fully usable with TTS off or absent — subtitles are always on (Spec 07 §7.3) and text mode is complete (P2.2). No information is audio-only, ever (this is why notification sounds are Spec 04 §3.13's problem *with* visible counterparts).
- **Speech and voice differences:** dysarthric, accented, or atypical speech will fare as the
  platform engine fares. The current recovery is visible notices plus a first-class text mode;
  vocabulary hints and confidence-based gating are future options, not current protections.
- **Screen readers:** current controls and text carry semantic labels. Automatic screen-reader
  detection/TTS deference remains the §6.4 destination.
- **TTS rate/pitch:** currently fixed at rate `0.5`, pitch `1.0`. User-adjustable persisted values
  remain an accessibility destination.
- Reduced-motion and visual accessibility are Spec 07 §8.2's and unchanged by this spec.

---

## 10. Current Realization & Suite-Sync Corrections

### 10.1 Current realization

The voice loop is shipped: callback-based recognition, accumulated native segments, user-delimited
stop-and-send, watchdog recovery, live mic levels/captions, on-device-only options, TTS lifecycle,
barge-in ordering, mute, and typed parity all converge through `VoiceTurnController`. Remaining
work is explicitly additive: long-form journal capture, optional downloadable local models,
wake-word prerequisites, and richer transcript metadata. None blocks the current voice workflow.

### 10.2 Corrections for the next reconciliation pass (this spec edits no other file)

> **✅ APPLIED — suite-sync pass, 2026-07-07.** Every X-item below has been propagated to its counterpart spec (X1/X3 → Specs 03/04; X2 → Spec 08 §5.5; X4 → Spec 10 §0; X5 → Spec 05 §3.2; X6 → Spec 04 §5.1/§5.2). Kept for the record.

- **X1 — Retarget "Spec 06 — Voice" citations → Spec 12:** Spec 03 §0 (scope exclusion), §1 P2.5 ("Spec 06 signals a final transcript"); Spec 04 §0 (scope), §3.8 ("Defined at research §9.2 and Spec 06"); Spec 08 §0 (scope) and §5.5 (STT/TTS row, twice). Spec 04 §4.2's subtitle sentence splits per §4.3's ownership line: rendering cite → Spec 07 §7.3 (already Spec 07 X4), dispatch-semantics cite → this spec §4.1.
- **X2 — Spec 08 §5.5 STT/TTS row** gains this spec as its normative source ("configured on-device per Spec 12 §5.1").
- **X3 — Voice seam naming:** current specs use shipped `SpeechRecognizer`/`SpeechOutput` names;
  `SpeechInput`/`TranscriptEvent` remains only the destination sketch in §2.
- **X4 — Spec 10 out-of-scope line** ("the voice pipeline's STT privacy characteristics… belong to Spec 08") → belong to Spec 12 §8; Spec 08 carries only the consent-tier framing.
- **X5 — Spec 05 §3.2 ASR-floor miscite** ("Spec 03 §3.5") → this spec §4.6.
- **X6 — Spec 04 §5.1/§5.2** gain the `VoiceError` row and surfaces of §9.1–§9.2.

---

## 11. Decision Record

### Resolved

- **D1 — Two seams, one layer.** The shipped pair is callback-based `SpeechRecognizer` plus
  `SpeechOutput`, strict leaves selected at composition. The richer `SpeechInput`/
  `TranscriptEvent` vocabulary is a destination. Current typed and spoken strings converge at
  `VoiceTurnController.send`, not through an identical transcript object. *(§2)*
- **D2 — No cloud STT, ever — the on-device mandate.** All speech recognition is on-device on every platform in every mode, enforced by construction (hard on-device engine flags; ineligible otherwise); unavailability degrades to text mode, never to a networked recognizer. The shipped `plenaraSpeechOptions` is the one option builder and sets `onDevice: true`; on Apple the plugin maps that to `requiresOnDeviceRecognition = true`, and a regression test rejects either platform option if the flag falls. This is the normative source for Spec 08 §5.5's "Never" row and the generalization of Spec 05 §11's journal invariant. Accepted costs: platform-trailing accuracy (absorbed by the correct-and-learn loop, research §6.3) and reduced reach on old devices (consistent with the min-OS decision, research §15.1). *(§5.1)*
- **D3 — Current engine matrix.** `speech_to_text` wraps the platform system recognizer and the
  shared options require on-device recognition. Optional local-model and SpeechAnalyzer paths are
  future alternatives. There is no cloud fallback or runtime engine picker. *(§5.2–§5.5)*
- **D4 — Capture model.** Tap starts a turn; the next tap stops and sends; the explicit × or mute discards. Engines may segment but never decide the user is finished. The 15 s no-speech, 30 s trailing-silence, and 120 s hard-cap watchdogs only recover forgotten sessions and visibly report any automatic stop. Wake word remains deferred. Mic-lifecycle invariant: mic open ⇔ session live ⇔ orb listening; permission is asked at first tap. *(§3; amended by G-52)*
- **D5 — Interim/final semantics.** Interims feed live caption state and internal diagnostics but are
  never dispatched or persisted as conversation turns. `RecognitionSession.finish` is the single
  idempotent finalization door and emits at most one non-empty final; empty is a quiet no-op.
- **D6 — Verbatim delivery.** The Voice layer performs no text normalization (Spec 03 §5.4 owns the single normalizer); the only transform is journal stop-word stripping, a capture-delimiter concern. *(§4.4)*
- **D7 — The voice-privacy statement.** Audio never exists at rest or leaves the device. Internal
  builds may retain transcript hypotheses under Spec 11; external builds do not. A final transcript
  can leave only through the same consented residual-routing path as typed text. No vocabulary bias
  list is currently assembled. *(§8)*
- **D8 — TTS is platform-native, offline, one consistent voice**; capture and playback are mutually
  exclusive and mute retains visual output. Automatic screen-reader deference remains a destination.
- **D9 — Latency budgets are targets, not current evidence** (§7.2 table), headlined by release →
  spoken-`Done` ≤ 1.0 s p50 on a corpus-hit turn and barge-in silence ≤ 150 ms. The current suite
  checks sequencing and lifecycle; it does not claim physical-device latency measurement or a
  CI-tracked distribution. *(§7)*
- **D10 — The failure design center is text mode.** Current failures and repeated empty captures
  resolve through recognizer availability/notices and controller state; there is no sealed
  `VoiceError` implementation or numeric ASR floor. *(§4.6–§4.7, §9)*
- **D11 — Vocabulary biasing is a destination.** The current recognizer receives no contact,
  capability, or corpus hint list. Any future list is on-device only. *(§4.5)*
- **D12 — Accessibility requirements are hard:** toggle capture, complete no-audio operation,
  subtitles/text parity, semantic voice state, system Reduce Motion, and Still Presence are shipped.
  Persisted adjustable TTS rate/pitch remains a destination. Plenara never requires voice. *(§9.5)*
- **D13 — Talk-back shipped, offline-first.** `FlutterTtsSpeechOutput` supplies per-utterance
  callbacks, generation guards, safety cleanup, barge-in/mute handling, iOS playback-session setup,
  automatic best-installed voice choice, and an iOS Settings picker for natural English voices.
  Rate/pitch remain fixed. *(§2.1, §6.1–§6.5)*
- **D14 — OS-dictation edge copy shipped (August 2026).** The public privacy policy now says that keyboard dictation initiated in text mode belongs to the OS provider, while Plenara's own microphone path remains on-device-only. Q7 is resolved. *(§8.5)*

### Open

- **Q1 — Windows local-model packaging.** Provisioned `sherpa_onnx` Whisper is already preferred
  and the OS recognizer is the fallback. The remaining question is whether and how the model pack
  becomes a supported first-run download rather than a manually provisioned capability (§5.3).
- **Q2 — Confidence only if a future engine earns it.** No numeric ASR floor exists today. If a
  future backend exposes reliable utterance confidence, calibrate it against recorded captures
  before adding any advisory floor; do not introduce a launch-guess threshold.
- **Q3 — Wake word prerequisites** (ambient rung): Porcupine integration, acoustic echo cancellation once speak/listen can overlap, the always-armed buffer-discard audit against §8.1's "audio never exists at rest," and Spec 07 Q3's "armed without surveillance" orb reading. All four before "Hey Plenara" ships.
- **Q4 — Whisper.cpp sizing.** Model choice/quantization per platform (binary budget vs. WER vs. the §7.2 journal-finalization budget), and whether one multilingual model or per-locale packs. Interacts with Q5.
- **Q5 — Locale & multilingual.** v1 is single-locale (device locale); SpeechAnalyzer's automatic language detection and mixed-language utterances are deferred — and must land together with Spec 03's multilingual-embedder swap note (§3.2) or routing quality silently diverges from transcription language.
- **Q6 — Word-timing events.** Karaoke subtitles (Spec 07 Q4) wait on TTS word-boundary callbacks being reliable cross-platform; this layer would carry them as additional per-utterance callbacks on the `speak` contract (§2.1) if/when Spec 07 wants them.

---

*End of Spec 12 — Voice v0.4*
