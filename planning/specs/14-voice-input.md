# Spec 14 — Voice Input (STT)

Status: **seam shipped; concrete on-device engine specified, pending a dev-env upgrade + a model decision.**

Plenara's vision is voice-driven. This spec closes the gap between the shipped **text** pipeline
and spoken capture. The design keeps voice **purely additive**: the typed field is always the
fallback, and the app is fully usable with no speech engine at all.

## Decision

Luis's preference (2026-07-08): **use the system built-in speech API**; a one-time OS language
download is acceptable. So the primary path is the OS recognizer (the OS owns the model — we don't
bundle or manage one), with a fully-local engine as the privacy-max alternative behind the same
seam.

- **Primary — Windows system speech API** via `speech_to_text` (+ `speech_to_text_windows`). The
  OS handles the language model (one-time download); minimal app footprint; likely **no `record`
  dependency** (the plugin captures audio itself), which also sidesteps the CMake-3.23 blocker
  below.
  - **OPEN ITEM to verify before shipping:** the Windows implementation has historically routed
    audio through Microsoft's **online** speech *service* (audio leaves the device). Confirm
    whether it can be pinned to Windows 11's **on-device** recognition (installed speech language /
    voice-typing engine). If yes → private + system-managed, ideal. If it's cloud-only and that's
    not acceptable, fall to the local engine below. Per Luis's "OS download is fine," the online
    path is acceptable if on-device can't be pinned — but flag the privacy tradeoff in-app.
- **Privacy-max alternative — `sherpa_onnx` + `record`** (v1.13.4, Apache-2.0, ONNX Runtime, k2-fsa;
  first-class `sherpa_onnx_windows`, official Flutter examples, streaming ASR, **100% offline**).
  We'd manage a ~50–150 MB model (download-on-first-run). Use this if the system API can't be kept
  on-device.
- **Cloud fallback — Deepgram** (`deepgram_speech_to_text`), BYOK, if neither above fits.
- Rejected: `whisper4dart` (needs FFmpeg, less maintained than sherpa for Windows).

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

## Prerequisites

**Primary (system-API) path — per Luis's preference:**
1. **Verify on-device vs online** for `speech_to_text_windows` (the OPEN ITEM above). This decides
   privacy; either way the OS manages the language model (one-time OS download, which Luis has
   OK'd), so **we provision no model** and likely **need no `record` package** (so the CMake-3.23
   blocker below may not apply). Add `speech_to_text`, implement a `SystemSpeechRecognizer` behind
   the seam, `available` = plugin initialised + a recognizer present.

**Alternative (fully-offline sherpa) path — only if the system API can't be kept on-device:**
1. **Toolchain: CMake ≥ 3.23.** `record_windows` (and the sherpa native build) require it; this
   dev box has 3.20, so `flutter build windows` fails at CMake config with those packages added.
   Trivial to resolve — CMake 3.23+ ships with current VS 2022 / installable standalone.
2. **Model provisioning.** An English streaming model is ~50–150 MB: **download on first run**
   into `~/.plenara/models/` (recommended) or **bundle** in assets. `available` is false until the
   model is present, so the app degrades gracefully either way.

## Testing

- Seam: widget tests with a fake recognizer (shipped).
- Engine: an integration test behind an env flag once a model is provisioned (real mic isn't
  hermetic); keep the fake-recognizer widget tests as the always-run coverage.

## Summary

The voice **experience** (mic button, push-to-talk, review-then-send, graceful fallback) is built
and tested. Turning it on is a bounded task: bump CMake, add `sherpa_onnx` + `record`, drop in
`SherpaSpeechRecognizer`, and choose how the model is provisioned.
