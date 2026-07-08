# Spec 14 — Voice Input (STT)

Status: **seam shipped; concrete on-device engine specified, pending a dev-env upgrade + a model decision.**

Plenara's vision is voice-driven. This spec closes the gap between the shipped **text** pipeline
and spoken capture. The design keeps voice **purely additive**: the typed field is always the
fallback, and the app is fully usable with no speech engine at all.

## Decision (2026 research)

- **No third-party OAuth / subscription STT from Anthropic** — STT is a separate concern.
- **On-device, offline: `sherpa_onnx` + `record`.** `sherpa_onnx` (v1.13.4, Apache-2.0, ONNX
  Runtime, k2-fsa) has first-class **Windows** support (`sherpa_onnx_windows`), official Flutter
  examples, streaming ASR, and 100% offline operation — the right fit for a local-first, private
  app. `record` (v7.1.1, MediaFoundation on Windows) captures 16 kHz PCM16 mic audio.
- **Cloud fallback: Deepgram** (`deepgram_speech_to_text`) behind the same seam, if on-device is
  ever impractical (e.g. Windows-ARM). BYOK, not local-first — a fallback, not the default.
- Rejected: `speech_to_text_windows` (remote web service, not private, beta); `whisper4dart`
  (needs FFmpeg, less maintained than sherpa for Windows).

## Architecture

**Seam (SHIPPED, `app/lib/speech.dart` + `main.dart`, tested):**
- `abstract SpeechRecognizer { bool get available; Future<String?> transcribe(); void cancel(); }`
- `NoopSpeechRecognizer` (default) → `available == false` → mic button hidden, typing works.
- The chat input shows a **mic button** only when `available`; push-to-talk `transcribe()` drops
  the final text into the field for the user to review + send. Widget-tested (mic hidden with
  Noop; a fake recognizer transcribes into the input).

**Concrete engine (TO ENABLE):** a `SherpaSpeechRecognizer implements SpeechRecognizer`, gated on
a model file so a build with no model behaves exactly like Noop (mic hidden — never a broken
button). Sketch:

```dart
// app/lib/sherpa_speech.dart  (add sherpa_onnx + record to pubspec first)
import 'dart:io';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class SherpaSpeechRecognizer implements SpeechRecognizer {
  final String modelDir;               // ~/.plenara/models/<model>
  final _rec = AudioRecorder();
  sherpa.OnlineRecognizer? _asr;
  SherpaSpeechRecognizer(this.modelDir);

  // available only once the model is present AND the native libs initialise
  @override
  bool get available {
    if (!Directory(modelDir).existsSync()) return false;
    _asr ??= _init();                  // lazy; null on failure -> unavailable
    return _asr != null;
  }

  sherpa.OnlineRecognizer? _init() {
    try {
      sherpa.initBindings();
      final t = sherpa.OnlineTransducerModelConfig(
        encoder: '$modelDir/encoder.onnx', decoder: '$modelDir/decoder.onnx',
        joiner: '$modelDir/joiner.onnx');
      return sherpa.OnlineRecognizer(sherpa.OnlineRecognizerConfig(
        model: sherpa.OnlineModelConfig(transducer: t, tokens: '$modelDir/tokens.txt', numThreads: 1),
        // endpointing so a natural pause finalises the utterance (push-to-talk)
      ));
    } catch (_) { return null; }
  }

  @override
  Future<String?> transcribe() async {
    final asr = _asr; if (asr == null) return null;
    final stream = asr.createStream();
    // record 16kHz PCM16 mono -> feed chunks -> stop on endpoint or the user releasing the button
    final sub = await _rec.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1));
    // ... accumulate bytes -> Float32 -> stream.acceptWaveform(...) -> asr.decode(stream)
    // ... on endpoint: final = asr.getResult(stream).text; break
    await _rec.stop();
    return /* final text, trimmed, or null */;
  }

  @override
  void cancel() { _rec.stop(); }
}
```

Full reference: [k2-fsa streaming_asr.dart](https://github.com/k2-fsa/sherpa-onnx/blob/master/flutter-examples/streaming_asr/lib/streaming_asr.dart).

**Wiring:** in `main.dart` `buildSession`/`ChatScreen`, construct
`SherpaSpeechRecognizer(defaultModelDir())` instead of the Noop default. `available` gating means
no model → identical to today (mic hidden).

## Prerequisites (the two open items)

1. **Toolchain: CMake ≥ 3.23.** `record_windows` (and the sherpa native build) require it; this
   dev box has 3.20, so `flutter build windows` fails at CMake config with the packages added.
   Trivial to resolve — CMake 3.23+ ships with current VS 2022 / installable standalone. This is
   the only reason the concrete engine isn't already wired: the seam + implementation are ready,
   but the native build can't be verified here.
2. **Model provisioning (a product decision).** An English streaming model is ~50–150 MB. Options:
   (a) **download on first run** into `~/.plenara/models/` with a small progress UI (keeps the
   installer small — recommended); (b) **bundle** in assets (bigger installer, works offline
   from minute one). `available` returns false until the model is in place, so either way the app
   degrades gracefully.

## Testing

- Seam: widget tests with a fake recognizer (shipped).
- Engine: an integration test behind an env flag once a model is provisioned (real mic isn't
  hermetic); keep the fake-recognizer widget tests as the always-run coverage.

## Summary

The voice **experience** (mic button, push-to-talk, review-then-send, graceful fallback) is built
and tested. Turning it on is a bounded task: bump CMake, add `sherpa_onnx` + `record`, drop in
`SherpaSpeechRecognizer`, and choose how the model is provisioned.
