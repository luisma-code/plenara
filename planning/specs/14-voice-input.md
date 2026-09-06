# Spec 14 — Voice Input (STT)

> **⚠ AMENDED 2026-07-28 (`G-52`).** "The ENGINE finalizes the utterance" is no longer true: the
> USER finalizes, the engine only segments. `stop()` is now THE finalization path (it flushes,
> joins every accumulated segment, and emits exactly one final); `cancel()` discards. The VAD's
> `minSilenceDuration` is an internal chunking parameter with no user-visible behaviour. See
> Spec 12's amendment note for the watchdog constants.

Status: **SHIPPED (v0) — Apple Speech is primary on iOS/macOS; Windows prefers local
sherpa_onnx Whisper when provisioned and otherwise uses its system recognizer; typing is always the
floor.**

**Change note (2026-07-11, Fable 5):** synced to the shipped implementation (`app/lib/speech.dart`,
`app/lib/sherpa_speech.dart`, `app/lib/voice_turn_controller.dart`, wired per Spec 15's
presence-primary home).
Three things moved since the draft: the seam grew from a one-shot `transcribe()` into a streaming
`listen()` contract; engine selection became platform-specific; and the interaction changed from a
mic button + review-then-send to **tap to start, tap again to stop-and-send**, with an explicit ✕ as
the discard door (Spec 15 §6.3–§6.4). Still-unshipped items are labeled **still planned** below.

Plenara's vision is voice-driven. This spec covers spoken **capture** (the input side; talk-back is
Spec 12). The design keeps voice **purely additive**: the typed field is always the fallback, and
the app is fully usable with no speech engine at all.

## Decision

Luis's original preference (2026-07-08) was the system built-in speech API first, fully-local as
the alternative. **How it landed:** selection is automatic in `_pickSpeech()` with no user-facing
engine setting. Apple platforms go directly to the on-device system recognizer; Windows prefers
sherpa because its Whisper transcription is markedly better than SAPI dictation.

- **Apple primary (SHIPPED) — system Speech** via `speech_to_text: ^7.4.0`: on-device system
  dictation on iOS/macOS, with no separate model download.
- **Windows primary when provisioned (SHIPPED) — `sherpa_onnx` + `record`**
  (`sherpa_onnx: ^1.13.4`, `record: ^7.1.1`): an offline Whisper model gated by Silero VAD for
  segmentation and capture health. The user, not VAD, ends the utterance.
- **Windows fallback (SHIPPED) — system speech** via `speech_to_text: ^7.4.0`. The OS owns the
  language model; zero provisioning. The draft's OPEN ITEM (online service vs on-device) resolved
  benignly: the shipped backend is the in-proc SAPI recognition path — local, not the online
  service. The tradeoff that *did* materialize is quality: SAPI dictation is rough and may deliver
  few useful partial hypotheses. It can leak stale results across sessions (guarded in code — see
  below). Fine as a no-setup fallback; not the preferred Windows engine.
- **Cloud fallback — Deepgram** (`deepgram_speech_to_text`), BYOK: **still planned**, unshipped.
  Neither shipped engine needed it for the Windows dogfood.
- Rejected: `whisper4dart` (needs FFmpeg, less maintained than sherpa for Windows). Note the irony:
  we run Whisper anyway, via sherpa's ONNX runtime.

## Architecture

**Seam (SHIPPED, `app/lib/speech.dart`):** the draft's one-shot `transcribe()` became a streaming
contract — tap to START, tap again to STOP and finalize, explicit ✕ to cancel and discard:

```dart
abstract class SpeechRecognizer {
  Future<void> init();
  bool get available;
  Stream<double> get levels; // normalized 0..1 when the platform exposes live level
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
- Partial transcripts: the contract carries `(text, isFinal)` and the controller consumes both.
  Partials update the visible “I heard” line and are retained by the session transcript reducer;
  they never dispatch a turn. Sherpa emits joined segment progress as partials and exactly one final
  from the shared stop/watchdog finalization door. SAPI availability of hypotheses remains
  platform-dependent.
- Listening level: the system recognizer maps its platform sound-level callback into a normalized
  broadcast `levels` stream for the presence. Sherpa currently exposes no equivalent platform
  signal and returns an empty stream; the presence uses its calm listening shimmer there. Level is
  ephemeral UI input only: never routed, persisted, or written to diagnostics.

**Engines (SHIPPED):**

- `SherpaSpeechRecognizer` (`app/lib/sherpa_speech.dart`): `record` captures 16 kHz PCM16 mono; a
  **Silero VAD** (min silence 0.4 s, min speech 0.2 s) segments the recording; a completed segment
  is transcribed by offline Whisper and contributes to the running partial. A stop tap flushes the
  trailing audio, waits for recorder/subscription teardown, joins all segments, and delivers one
  final result. Model discovery is by filename inside the model dir
  (encoder/decoder `.onnx` — int8 variants preferred — plus `tokens.txt` and a `silero*.onnx`);
  missing/incomplete files or a failed native init ⇒ `available == false`, exactly like Noop —
  never a broken mic.
- `SystemSpeechRecognizer` (`app/lib/speech.dart`): `speech_to_text` → Windows built-in
  recognition. Battle scars are documented in code and worth knowing when auditing: a
  **stale-result guard** drops any result arriving <500 ms after `listen()` starts (SAPI strands
  an undelivered final in the recognition context when stopped early, then delivers it at the
  start of the *next* session); `listenFor` caps a session at 45 s; **no `pauseFor`** (it's a
  Dart-side timer reset by results — with no partials on Windows it would fire mid-sentence).

**Shipped v0 capture path (`app/lib/voice_turn_controller.dart`, with the engine pick and the tap
target in `app/lib/main.dart`):**

1. **Engine pick at startup:** injected test recognizer wins; injected session ⇒ Noop. On Apple
   platforms the OS recognizer is selected directly. On Windows, sherpa wins when
   `~/.plenara/models/en-whisper` yields a working init and the OS recognizer is the fallback. Any
   selected engine's init failure ⇒ unavailable ⇒ text mode.
2. **Tap anywhere to talk** (Spec 15 §6.3): a full-screen tap target, active only when a
   recognizer is available, not muted, and no turn is in flight.
3. **Re-entry guard:** `_listening` is set before the barge-in await. The stop tap clears listening
   and raises `transcribing` until the recognizer's asynchronous flush/teardown completes; all voice
   targets are disabled during that state, so a third tap cannot start a second native session.
4. **Barge-in:** starting to listen stops any in-flight TTS first (Spec 12 §7) — you can always
   cut Plena off by starting to speak.
5. **Final ⇒ turn:** `stop()`/watchdog finalization emits exactly one joined transcript, which is
   auto-sent. `cancel()` is reserved for ✕, mute, backgrounding, and teardown. Empty transcripts
   send nothing. Engine callbacks are capture-epoch checked so stale completion cannot mutate a
   newer session.
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

- Seam (SHIPPED): hermetic controller/widget tests cover stop-and-send, cancel-only discard,
  partial/final reduction, watchdog surfaces, delayed native stop, stale-callback exclusion,
  barge-in, null transcript, throwing engines, and Noop text mode. The delayed-stop verifier is
  calibrated against the former re-entry defect.
- Engines (**still planned**): an integration test behind an env flag once model provisioning is
  automated (a real mic isn't hermetic); the fake-recognizer widget tests stay the always-run
  coverage.

## Summary

Spoken capture is **live**: tap, talk, tap to finish. Apple Speech handles iOS/macOS; Windows uses
local Whisper when provisioned and otherwise its OS recognizer. Stop waits for audio teardown and
auto-sends one transcript; ✕ discards; barge-in, watchdog visibility, mute, and typing remain the
safety floor. Remaining additions are the first-run Windows model downloader and BYOK cloud
fallback.
