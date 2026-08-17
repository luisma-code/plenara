import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'speech.dart';

/// On-device speech recognition via sherpa_onnx (ONNX Runtime): a Whisper offline model for
/// modern, accurate, naturally-cased transcription. Fully offline and private. Audio is captured
/// with `record` at 16 kHz PCM16 and fed to a Silero VAD.
///
/// **The VAD no longer decides when you are finished** (Spec 12 §3.1, amended). It used to emit the
/// first completed segment as the final result, so a thinking pause mid-command truncated the
/// utterance and auto-sent half of it. Its three remaining jobs:
///  1. **Segmenter** — Whisper transcribes ~30s windows, so a long utterance MUST be chunked;
///     completed VAD segments are exactly the right boundaries. Each is transcribed as it closes
///     and its text is ACCUMULATED (bounded memory: text, not PCM) rather than emitted, so stop
///     latency is one trailing segment and the 30s VAD buffer can never overflow.
///  2. **Hint trigger** — a long pause while recording re-shows "tap when you're done".
///  3. **Watchdog** — bounds a forgotten-open mic (see [CaptureLimits]).
///
/// [stop] joins the accumulated text with the flushed trailing segment and emits ONE final.
/// If the model files are absent or init fails, [available] is false and the app falls back
/// (SAPI, then typing).
class SherpaSpeechRecognizer implements SpeechRecognizer {
  @override
  Stream<double> get levels => const Stream<double>.empty();

  final String modelDir;
  final void Function(String msg)? onLog;
  SherpaSpeechRecognizer(this.modelDir, {this.onLog});
  void _log(String m) => onLog?.call(m);

  static bool _bindingsInited = false;

  sherpa.OfflineRecognizer? _recognizer;
  sherpa.VoiceActivityDetector? _vad;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSub;
  void Function(String, bool)? _onResult;
  void Function()? _onDone;
  void Function(SpeechNotice)? _onNotice;
  bool _listening = false;
  bool _emitted = false;

  /// Transcribed text of every VAD segment closed so far this session, in order.
  final List<String> _segments = [];
  Timer? _noSpeechTimer, _silenceTimer, _hintTimer, _capTimer;
  bool _sawSpeech = false;

  /// When the currently-open speech segment began — used to force a flush before the VAD's 30s
  /// buffer overflows on one unbroken utterance.
  DateTime? _segmentOpenedAt;

  @override
  Future<void> init() async {
    try {
      final dir = Directory(modelDir);
      if (!dir.existsSync()) {
        _log('model dir missing: $modelDir');
        return;
      }
      final files = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .toList();
      String? pick(String kind) {
        final m = files
            .where(
              (p) =>
                  p.toLowerCase().endsWith('.onnx') &&
                  p.toLowerCase().contains(kind),
            )
            .toList();
        if (m.isEmpty) return null;
        final i8 = m.where(
          (p) => p.contains('int8'),
        ); // prefer int8 (smaller, ~same accuracy)
        return i8.isNotEmpty ? i8.first : m.first;
      }

      final encoder = pick('encoder');
      final decoder = pick('decoder');
      final tokens = files.firstWhere(
        (p) => p.toLowerCase().endsWith('tokens.txt'),
        orElse: () => '',
      );
      final vadModel = files.firstWhere(
        (p) =>
            p.toLowerCase().contains('silero') &&
            p.toLowerCase().endsWith('.onnx'),
        orElse: () => '',
      );
      if (encoder == null ||
          decoder == null ||
          tokens.isEmpty ||
          vadModel.isEmpty) {
        _log(
          'model incomplete (enc=$encoder dec=$decoder tok=$tokens vad=$vadModel)',
        );
        return;
      }

      if (!_bindingsInited) {
        sherpa.initBindings();
        _bindingsInited = true;
      }
      _recognizer = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            whisper: sherpa.OfflineWhisperModelConfig(
              encoder: encoder,
              decoder: decoder,
            ),
            tokens: tokens,
            modelType: 'whisper',
            numThreads: 2,
            debug: false,
          ),
        ),
      );
      _vad = sherpa.VoiceActivityDetector(
        config: sherpa.VadModelConfig(
          sileroVad: sherpa.SileroVadModelConfig(
            model: vadModel,
            minSilenceDuration: 0.4,
            minSpeechDuration: 0.2,
          ),
          numThreads: 1,
          debug: false,
        ),
        bufferSizeInSeconds: 30,
      );
      _log('whisper + vad ready');
    } catch (e) {
      _log('init failed: $e');
      _recognizer = null;
    }
  }

  @override
  bool get available => _recognizer != null && _vad != null;

  @override
  Future<void> listen({
    required void Function(String, bool) onResult,
    required void Function() onDone,
    void Function(SpeechNotice)? onNotice,
  }) async {
    final vad = _vad;
    if (_recognizer == null || vad == null) {
      onDone();
      return;
    }
    if (!await _recorder.hasPermission()) {
      _log('no mic permission');
      onDone();
      return;
    }
    _onResult = onResult;
    _onDone = onDone;
    _onNotice = onNotice;
    _emitted = false;
    _sawSpeech = false;
    _segmentOpenedAt = null;
    _segments.clear();
    vad.clear(); // drop any state from a prior session
    _listening = true;
    _armWatchdogs();
    _log('listen: start');
    try {
      final audio = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _audioSub = audio.listen(
        _onAudio,
        onError: (e) {
          _log('audio error: $e');
          _finalize();
        },
      );
    } catch (e) {
      _log('startStream failed: $e');
      _finalize();
    }
  }

  void _armWatchdogs() {
    _clearTimers();
    _noSpeechTimer = Timer(CaptureLimits.noSpeech, () {
      if (_sawSpeech || !_listening) return;
      _onNotice?.call(SpeechNotice.autoCancelledNoSpeech);
      // Grab onDone BEFORE cancel(), which nulls it — otherwise this watchdog silently ends the
      // session without ever telling the caller, and the seam's "onDone fires when listening ends
      // for any reason" contract is broken.
      final done = _onDone;
      cancel(); // nothing said — nothing to send
      done?.call();
    });
    _capTimer = Timer(CaptureLimits.session, () {
      if (!_listening) return;
      _onNotice?.call(SpeechNotice.autoStopped);
      _finalize(flush: true); // stop AND SEND at the hard cap
    });
  }

  /// Speech is happening: push the trailing-silence watchdog and the re-hint out.
  void _bumpActivity() {
    _sawSpeech = true;
    _segmentOpenedAt ??= DateTime.now();
    _noSpeechTimer?.cancel();
    _silenceTimer?.cancel();
    _hintTimer?.cancel();
    _hintTimer = Timer(CaptureLimits.longPauseHint, () {
      if (_listening) _onNotice?.call(SpeechNotice.longPause);
    });
    _silenceTimer = Timer(CaptureLimits.trailingSilence, () {
      if (!_listening) return;
      _onNotice?.call(SpeechNotice.autoStopped);
      _finalize(flush: true); // stop AND SEND — never discard real speech
    });
  }

  void _clearTimers() {
    _noSpeechTimer?.cancel();
    _silenceTimer?.cancel();
    _hintTimer?.cancel();
    _capTimer?.cancel();
    _noSpeechTimer = _silenceTimer = _hintTimer = _capTimer = null;
  }

  void _onAudio(Uint8List bytes) {
    final vad = _vad;
    if (!_listening || vad == null) return;
    vad.acceptWaveform(_toFloat32(bytes));
    // Watch SPEECH ACTIVITY, not just closed segments. A segment only closes after a 0.4s pause,
    // so keying the watchdogs off segment closure meant: (a) someone who thinks for 14s and then
    // starts talking got cancelled mid-sentence with "I didn't hear anything", and (b) 30s of
    // unbroken speech looked identical to 30s of silence and was auto-sent mid-word.
    if (vad.isDetected()) _bumpActivity();
    // A single unbroken utterance longer than the VAD's 30s buffer can never close on its own and
    // would silently drop audio. Force a flush a little before the buffer limit so long speech is
    // chunked rather than lost.
    if (_sawSpeech &&
        _segmentOpenedAt != null &&
        DateTime.now().difference(_segmentOpenedAt!) >
            const Duration(seconds: 25)) {
      vad.flush();
      _segmentOpenedAt = DateTime.now();
    }
    // A completed segment is a CHUNK BOUNDARY, not the end of the utterance: transcribe it now
    // (bounded memory, and stop latency stays at one trailing segment) and keep listening until
    // the user taps stop.
    while (!vad.isEmpty()) {
      final seg = vad.front();
      vad.pop();
      final text = _transcribe(seg.samples).trim();
      _segmentOpenedAt = null; // this segment closed; the next one starts fresh
      if (text.isNotEmpty) {
        _segments.add(text);
        _bumpActivity();
      }
    }
  }

  String _transcribe(Float32List samples) {
    final rec = _recognizer!;
    final stream = rec.createStream();
    stream.acceptWaveform(samples: samples, sampleRate: 16000);
    rec.decode(stream);
    final text = rec.getResult(stream).text;
    stream.free();
    return text;
  }

  /// Stop capture, clean up, fire onDone. Idempotent. When [flush] (the user's stop tap, or a
  /// watchdog), push the trailing buffered speech through the VAD, transcribe it, and emit the
  /// WHOLE session — every accumulated segment joined with that tail — as one final result.
  void _finalize({bool flush = false}) {
    if (!_listening) return;
    _listening = false;
    _clearTimers();
    _audioSub?.cancel();
    _audioSub = null;
    // ignore: discarded_futures
    _recorder.stop();
    if (flush && !_emitted) {
      if (_vad != null) {
        _vad!
            .flush(); // whatever is mid-segment when the user taps stop is still real speech
        while (!_vad!.isEmpty()) {
          final seg = _vad!.front();
          _vad!.pop();
          final text = _transcribe(seg.samples).trim();
          if (text.isNotEmpty) _segments.add(text);
        }
      }
      final full = _segments.join(' ').trim();
      if (full.isNotEmpty) {
        _emitted = true;
        _onResult?.call(full, true); // ONE final for the session
      }
    }
    final done = _onDone;
    _onDone = null;
    done?.call();
  }

  /// The user's stop tap: finalize and deliver everything said this session.
  @override
  Future<void> stop() async => _finalize(flush: true);

  @override
  void cancel() {
    _listening = false;
    _clearTimers();
    _audioSub?.cancel();
    _audioSub = null;
    // ignore: discarded_futures
    _recorder.stop();
    _vad?.clear();
    _segments
        .clear(); // discard — a cancel must never leak into the next session's transcript
    _onDone = null;
  }

  static Float32List _toFloat32(Uint8List bytes) {
    final n = bytes.length ~/ 2;
    final out = Float32List(n);
    final bd = ByteData.sublistView(bytes);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }
}
