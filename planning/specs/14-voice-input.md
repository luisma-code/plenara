# Spec 14 — Voice Input (STT)

> **⚠ AMENDED 2026-07-28 (`G-52`).** "The ENGINE finalizes the utterance" is no longer true: the
> USER finalizes, the engine only segments. `stop()` is now THE finalization path (it flushes,
> joins every accumulated segment, and emits exactly one final); `cancel()` discards. The VAD's
> `minSilenceDuration` is an internal chunking parameter with no user-visible behaviour. See
> Spec 12's amendment note for the watchdog constants.

Status: **SHIPPED (v0) — two on-device engines live behind the seam; sherpa_onnx (Whisper) is
primary when its model is present, the OS engine is the fallback, typing is always the floor.**

**Change note (2026-07-11, Fable 5):** synced to the shipped implementation (`app/lib/speech.dart`,
`app/lib/sherpa_speech.dart`, `app/lib/main.dart`, wired per Spec 15's presence-primary home).
Three things moved since the draft: the seam grew from a one-shot `transcribe()` into a streaming
`listen()` contract; the engine priority **inverted** (the fully-local sherpa path, the draft's
"privacy-max alternative," is now the primary — matching the offline-first posture — with the
system API as the built-in fallback); and the interaction changed from a mic button +
review-then-send to **tap-anywhere + auto-send** (Spec 15 §6.3–§6.4). Still-unshipped items are
labeled **still planned** below.

Plenara's vision is voice-driven. This spec covers spoken **capture** (the input side; talk-back is
Spec 12). The design keeps voice **purely additive**: the typed field is always the fallback, and
the app is fully usable with no speech engine at all.

## Decision

Luis's original preference (2026-07-08) was the system built-in speech API first, fully-local as
the alternative. **How it landed:** both engines shipped behind the same seam, but the priority
inverted — on-device sherpa_onnx is primary because offline-first is the posture and its Whisper
transcription is markedly better than SAPI dictation. Selection is automatic at startup
(`_pickSpeech()` in `main.dart`); no user-facing engine setting.

- **Primary (SHIPPED) — `sherpa_onnx` + `record`** (`sherpa_onnx: ^1.13.4`, `record: ^7.1.1`):
  an **offline Whisper** model (not the draft's streaming transducer) gated by a **Silero VAD**
  for hands-free endpointing. 100% offline and private; we manage the model files (see
  Prerequisites). Used whenever the model is present and initializes.
- **Fallback (SHIPPED) — Windows system speech** via `speech_to_text: ^7.4.0`. The OS owns the
  language model; zero provisioning. The draft's OPEN ITEM (online service vs on-device) resolved
  benignly: the shipped backend is the in-proc SAPI recognition path — local, not the online
  service. The tradeoff that *did* materialize is quality: SAPI dictation is rough, delivers
  **finals only** (its backend never registers hypothesis events, so no partials), and leaks stale
  results across sessions (guarded in code — see below). Fine as a no-setup fallback; not the
  primary.
- **Cloud fallback — Deepgram** (`deepgram_speech_to_text`), BYOK: **still planned**, unshipped.
  Neither shipped engine needed it for the Windows dogfood.
- Rejected: `whisper4dart` (needs FFmpeg, less maintained than sherpa for Windows). Note the irony:
  we run Whisper anyway, via sherpa's ONNX runtime.

## Architecture

**Seam (SHIPPED, `app/lib/speech.dart`):** the draft's one-shot `transcribe()` became a streaming
contract — tap to START, the **engine** finalizes the utterance via its own end-of-utterance
detection, tap again to ABORT:

```dart
abstract class SpeechRecognizer {
  Future<void> init();
  bool get available;
  /// onResult streams the transcript; isFinal marks the engine's final result for an utterance.
  Future<void> listen({required void Function(String text, bool isFinal) onResult,
                       required void Function() onDone});
  Future<void> stop();   // manual finish — may flush + finalize buffered speech
  void cancel();         // abort — discard, never finalize
}
```

- `NoopSpeechRecognizer` (default under injected/test sessions) → `available == false` → text
  mode, typing works. The `stop()`/`cancel()` distinction is load-bearing: `stop()` on the sherpa
  engine flushes the VAD and transcribes buffered speech; `cancel()` throws it away (used for
  abort, mute, and teardown — never auto-send a half-spoken command).
- Partial transcripts: the contract carries `(text, isFinal)`, but v0 **consumes finals only** —
  SAPI never produces partials, and the sherpa path is final-only by design (offline Whisper
  transcribes a completed VAD segment). Live partial captioning while the user speaks: **still
  planned** (would need sherpa's streaming/online models; Spec 12 §4 owns the transcript-display
  contract).

**Engines (SHIPPED):**

- `SherpaSpeechRecognizer` (`app/lib/sherpa_speech.dart`): `record` captures 16 kHz PCM16 mono; a
  **Silero VAD** (min silence 0.4 s, min speech 0.2 s) does the endpointing; a completed segment
  (speech + short pause) is transcribed by the offline **Whisper** model and delivered as one
  final result — **one utterance per tap**. Model discovery is by filename inside the model dir
  (encoder/decoder `.onnx` — int8 variants preferred — plus `tokens.txt` and a `silero*.onnx`);
  missing/incomplete files or a failed native init ⇒ `available == false`, exactly like Noop —
  never a broken mic.
- `SystemSpeechRecognizer` (`app/lib/speech.dart`): `speech_to_text` → Windows built-in
  recognition. Battle scars are documented in code and worth knowing when auditing: a
  **stale-result guard** drops any result arriving <500 ms after `listen()` starts (SAPI strands
  an undelivered final in the recognition context when stopped early, then delivers it at the
  start of the *next* session); `listenFor` caps a session at 45 s; **no `pauseFor`** (it's a
  Dart-side timer reset by results — with no partials on Windows it would fire mid-sentence).

**Shipped v0 capture path (`main.dart`):**

1. **Engine pick at startup:** injected test recognizer wins; injected session ⇒ Noop; else
   sherpa if `~/.plenara/models/en-whisper` yields a working init; else the OS engine (whose own
   init failure ⇒ unavailable ⇒ text mode).
2. **Tap anywhere to talk** (Spec 15 §6.3): a full-screen tap target, active only when a
   recognizer is available, not muted, and no turn is in flight.
3. **Re-entry guard:** `_listening` is set *before* the barge-in await, so a second tap during it
   hits the abort branch instead of starting a second recognizer session. Tapping while listening
   **aborts** via `cancel()` (deliberately not `stop()` — see above).
4. **Barge-in:** starting to listen stops any in-flight TTS first (Spec 12 §7) — you can always
   cut Plena off by starting to speak.
5. **Final ⇒ turn:** on the engine's final result, listening clears, the recognizer is cancelled
   (one utterance per tap), the transcript becomes the input text and is **auto-sent** — a
   complete hands-free action, ~1 s after the speaker pauses. No review-then-send step; abort is
   the safety valve. Empty transcripts send nothing.
6. **Degrade & hygiene:** `onDone`/catch always clear the listening state (can't get stuck);
   no recognizer ⇒ the typed input bar rises from the bottom; **muting cancels a hot mic** and
   switches to text mode (Spec 15 §7); widget teardown cancels the recognizer — never leave it
   recording (privacy).

## Prerequisites

- ~~**Toolchain: CMake ≥ 3.23**~~ — **RESOLVED.** `record` and `sherpa_onnx` are in `pubspec.yaml`
  and the Windows build ships with both.
- **Model provisioning — shipped as manual, downloader still planned.** The sherpa engine looks in
  `~/.plenara/models/en-whisper` for the Whisper encoder/decoder/tokens + Silero VAD files
  (~50–150 MB, placed by hand today). Absent ⇒ graceful fall-through to the OS engine, then
  typing. A download-on-first-run flow (with progress over the void) is the intended v1 polish.

## Testing

- Seam (SHIPPED): hermetic widget tests with fake recognizers — tap-to-talk transcribes and
  auto-sends; a null transcript sends nothing; a throwing engine is caught and listening clears;
  Noop ⇒ text mode.
- Engines (**still planned**): an integration test behind an env flag once model provisioning is
  automated (a real mic isn't hermetic); the fake-recognizer widget tests stay the always-run
  coverage.

## Summary

Spoken capture is **live**: tap the void, talk, pause — the on-device Whisper (or, without its
model, the OS engine) finalizes the utterance and the turn auto-sends, with barge-in over TTS, an
abort tap, and mute/typing as the always-present floor. Remaining, all additive: the first-run
model downloader, live partial captions (streaming model), and the BYOK cloud fallback.
