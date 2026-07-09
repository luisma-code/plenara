import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'speech.dart';

/// On-device streaming ASR via sherpa_onnx (Next-gen Kaldi / ONNX Runtime) — modern neural
/// recognition, fully offline and private. Loads a streaming-zipformer transducer model from
/// [modelDir] (int8 variants preferred to keep it light). If the model is absent or init fails,
/// [available] is false and the app falls back (SAPI, then typing). Audio is captured with
/// `record` at 16 kHz PCM16 and fed to the recognizer; the engine's own endpoint detection
/// finalizes an utterance after a ~1.2 s pause (and a manual stop finalizes whatever is decoded).
class SherpaSpeechRecognizer implements SpeechRecognizer {
  final String modelDir;
  final void Function(String msg)? onLog;
  SherpaSpeechRecognizer(this.modelDir, {this.onLog});
  void _log(String m) => onLog?.call(m);

  static bool _bindingsInited = false;

  sherpa.OnlineRecognizer? _recognizer;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSub;
  sherpa.OnlineStream? _stream;
  void Function(String, bool)? _onResult;
  void Function()? _onDone;
  bool _listening = false;
  String _lastPartial = '';

  @override
  Future<void> init() async {
    try {
      final dir = Directory(modelDir);
      if (!dir.existsSync()) {
        _log('model dir missing: $modelDir');
        return;
      }
      final files = dir.listSync().whereType<File>().map((f) => f.path).toList();
      String? pick(String kind, {bool preferInt8 = false}) {
        final m = files.where((p) => p.toLowerCase().endsWith('.onnx') && p.toLowerCase().contains(kind)).toList();
        if (m.isEmpty) return null;
        if (preferInt8) {
          final i = m.where((p) => p.contains('int8'));
          if (i.isNotEmpty) return i.first;
        }
        final plain = m.where((p) => !p.contains('int8'));
        return plain.isNotEmpty ? plain.first : m.first;
      }

      final encoder = pick('encoder', preferInt8: true);
      final decoder = pick('decoder'); // tiny; fp32 is fine
      final joiner = pick('joiner', preferInt8: true);
      final tokens = files.firstWhere((p) => p.toLowerCase().endsWith('tokens.txt'), orElse: () => '');
      if (encoder == null || decoder == null || joiner == null || tokens.isEmpty) {
        _log('model incomplete (enc=$encoder dec=$decoder join=$joiner tok=$tokens)');
        return;
      }

      if (!_bindingsInited) {
        sherpa.initBindings();
        _bindingsInited = true;
      }
      _recognizer = sherpa.OnlineRecognizer(sherpa.OnlineRecognizerConfig(
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(encoder: encoder, decoder: decoder, joiner: joiner),
          tokens: tokens,
          numThreads: 2,
          debug: false,
        ),
        enableEndpoint: true,
        rule2MinTrailingSilence: 1.2, // ~1.2s pause ends the utterance
      ));
      _log('ready (int8 encoder)');
    } catch (e) {
      _log('init failed: $e');
      _recognizer = null;
    }
  }

  @override
  bool get available => _recognizer != null;

  @override
  Future<void> listen({required void Function(String, bool) onResult, required void Function() onDone}) async {
    final rec = _recognizer;
    if (rec == null) {
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
    _lastPartial = '';
    _stream = rec.createStream();
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
    final rec = _recognizer, s = _stream;
    if (!_listening || rec == null || s == null) return;
    s.acceptWaveform(samples: _toFloat32(bytes), sampleRate: 16000);
    while (rec.isReady(s)) {
      rec.decode(s);
    }
    final text = rec.getResult(s).text.trim();
    if (text.isNotEmpty && text != _lastPartial) {
      _lastPartial = text;
      _onResult?.call(text, false); // live partial
    }
    if (rec.isEndpoint(s)) {
      _finalize(); // natural pause -> final result -> auto-send
    }
  }

  /// Emit the final transcript, stop capture, clean up, fire onDone. Idempotent.
  void _finalize() {
    if (!_listening) return;
    _listening = false;
    final rec = _recognizer, s = _stream;
    _audioSub?.cancel();
    _audioSub = null;
    // ignore: discarded_futures
    _recorder.stop();
    if (rec != null && s != null) {
      final text = rec.getResult(s).text.trim();
      if (text.isNotEmpty) _onResult?.call(text, true);
      s.free();
    }
    _stream = null;
    final done = _onDone;
    _onDone = null;
    done?.call();
  }

  @override
  Future<void> stop() async => _finalize(); // manual finish -> finalize current decode

  @override
  void cancel() {
    _listening = false;
    _audioSub?.cancel();
    _audioSub = null;
    // ignore: discarded_futures
    _recorder.stop();
    _stream?.free();
    _stream = null;
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
