import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'speech.dart';

/// On-device speech recognition via sherpa_onnx (ONNX Runtime): a Whisper offline model for
/// modern, accurate, naturally-cased transcription, gated by a Silero VAD for hands-free
/// endpointing. Fully offline and private. Audio is captured with `record` at 16 kHz PCM16 and
/// fed to the VAD; when it detects an utterance (speech followed by a short pause), that segment is
/// transcribed by Whisper and delivered as the final result -> auto-send. A manual stop flushes and
/// transcribes whatever was buffered. If the model files are absent or init fails, [available] is
/// false and the app falls back (SAPI, then typing).
class SherpaSpeechRecognizer implements SpeechRecognizer {
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
  bool _listening = false;
  bool _emitted = false;

  @override
  Future<void> init() async {
    try {
      final dir = Directory(modelDir);
      if (!dir.existsSync()) {
        _log('model dir missing: $modelDir');
        return;
      }
      final files = dir.listSync().whereType<File>().map((f) => f.path).toList();
      String? pick(String kind) {
        final m = files.where((p) => p.toLowerCase().endsWith('.onnx') && p.toLowerCase().contains(kind)).toList();
        if (m.isEmpty) return null;
        final i8 = m.where((p) => p.contains('int8')); // prefer int8 (smaller, ~same accuracy)
        return i8.isNotEmpty ? i8.first : m.first;
      }

      final encoder = pick('encoder');
      final decoder = pick('decoder');
      final tokens = files.firstWhere((p) => p.toLowerCase().endsWith('tokens.txt'), orElse: () => '');
      final vadModel = files.firstWhere(
          (p) => p.toLowerCase().contains('silero') && p.toLowerCase().endsWith('.onnx'),
          orElse: () => '');
      if (encoder == null || decoder == null || tokens.isEmpty || vadModel.isEmpty) {
        _log('model incomplete (enc=$encoder dec=$decoder tok=$tokens vad=$vadModel)');
        return;
      }

      if (!_bindingsInited) {
        sherpa.initBindings();
        _bindingsInited = true;
      }
      _recognizer = sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(encoder: encoder, decoder: decoder),
          tokens: tokens,
          modelType: 'whisper',
          numThreads: 2,
          debug: false,
        ),
      ));
      _vad = sherpa.VoiceActivityDetector(
        config: sherpa.VadModelConfig(
          sileroVad: sherpa.SileroVadModelConfig(model: vadModel, minSilenceDuration: 0.4, minSpeechDuration: 0.2),
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
  Future<void> listen({required void Function(String, bool) onResult, required void Function() onDone}) async {
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
    _emitted = false;
    vad.clear(); // drop any state from a prior session
    _listening = true;
    _log('listen: start');
    try {
      final audio = await _recorder.startStream(
          const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1));
      _audioSub = audio.listen(_onAudio, onError: (e) {
        _log('audio error: $e');
        _finalize();
      });
    } catch (e) {
      _log('startStream failed: $e');
      _finalize();
    }
  }

  void _onAudio(Uint8List bytes) {
    final vad = _vad;
    if (!_listening || vad == null) return;
    vad.acceptWaveform(_toFloat32(bytes));
    // A completed utterance (speech + a short pause) is queued as a segment -> transcribe it.
    while (!vad.isEmpty()) {
      final seg = vad.front();
      vad.pop();
      final text = _transcribe(seg.samples).trim();
      if (text.isNotEmpty && !_emitted) {
        _emitted = true;
        _onResult?.call(text, true); // one utterance per tap
        _finalize();
        return;
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

  /// Stop capture, clean up, fire onDone. Idempotent. When [flush] (a manual stop), force any
  /// buffered speech through the VAD and transcribe it so a cut-off utterance isn't lost.
  void _finalize({bool flush = false}) {
    if (!_listening) return;
    _listening = false;
    _audioSub?.cancel();
    _audioSub = null;
    // ignore: discarded_futures
    _recorder.stop();
    if (flush && !_emitted && _vad != null) {
      _vad!.flush();
      while (!_vad!.isEmpty()) {
        final seg = _vad!.front();
        _vad!.pop();
        final text = _transcribe(seg.samples).trim();
        if (text.isNotEmpty) {
          _emitted = true;
          _onResult?.call(text, true);
          break;
        }
      }
    }
    final done = _onDone;
    _onDone = null;
    done?.call();
  }

  @override
  Future<void> stop() async => _finalize(flush: true); // manual finish -> transcribe buffered speech

  @override
  void cancel() {
    _listening = false;
    _audioSub?.cancel();
    _audioSub = null;
    // ignore: discarded_futures
    _recorder.stop();
    _vad?.clear();
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
