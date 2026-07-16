// Plena's voice — talk-back (Spec 12 §6). A pluggable output seam: the on-device engine now
// (WinRT/SAPI on Windows, AVSpeechSynthesizer on Apple — the latter genuinely good), swappable
// for a cloud voice later without touching the app. onStart/onDone bracket each utterance so
// Plena's *speaking* animation anchors to real audio (Spec 15 §3.1 / §4.1).
import 'dart:io' show Platform;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:plenara/config.dart' as cfg;

/// Track 2: turn a DISPLAY reply into TTS-friendly text. The engine reads bullets, line breaks, and
/// symbols literally and woodenly ("bullet… bullet…", choppy line-by-line); this smooths them into
/// flowing speech — drop mote/bullet glyphs + status emoji, strip markdown syntax, join lines into
/// sentences with natural pauses, and say a few symbols as words. Pure text, no AI (code-over-AI);
/// the DISPLAYED text (track 1, shown when muted) is untouched — only what we hand the synthesizer.
String speakify(String text) {
  var s = text;
  s = s.replaceAll(RegExp(r'[✨📋🎂🎉•·–—]'), ' '); // decoration / status glyphs
  s = s.replaceAll(RegExp(r'[*_`#]'), ''); // markdown emphasis/code/heading markers
  s = s.replaceAll(RegExp(r'^\s*(?:[-–—•]|\d+[.)])\s+', multiLine: true), ''); // bullet/number leaders
  s = s
      .replaceAll('&', ' and ')
      .replaceAll('→', ' to ')
      .replaceAll('%', ' percent')
      .replaceAll(RegExp(r'\be\.g\.', caseSensitive: false), 'for example')
      .replaceAll(RegExp(r'\bi\.e\.', caseSensitive: false), 'that is');
  // Line breaks → sentence boundaries so it doesn't read choppily. Blank line = full stop; a single
  // newline after non-terminal text = a comma pause; otherwise just a space.
  s = s.replaceAll(RegExp(r'\n{2,}'), '. ');
  s = s.replaceAllMapped(RegExp(r'([^.!?:;,])\n'), (m) => '${m[1]}, ');
  s = s.replaceAll('\n', ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  // Drop a space left before punctuation (the glyph/emoji stripping creates these). NB: replaceAll
  // does NOT interpret `$1`, so this must be replaceAllMapped — else the literal "$1" gets spoken.
  s = s.replaceAllMapped(RegExp(r'\s+([.,!?;:])'), (m) => m[1]!);
  s = s.replaceAll(RegExp(r'\.{2,}'), '.').replaceAll(RegExp(r',{2,}'), ','); // tidy doubled punctuation
  return s.trim();
}

/// The installed NATURAL (Enhanced/Premium) English voices — the choices offered by the in-app voice
/// picker. Each: (name as the engine reports it, locale like "en-AU", quality label). Empty off iOS.
Future<List<({String name, String locale, String quality})>> naturalEnglishVoices() async {
  if (!Platform.isIOS) return const [];
  final out = <({String name, String locale, String quality})>[];
  try {
    final raw = await FlutterTts().getVoices;
    for (final v in (raw as List? ?? const [])) {
      final m = Map<String, dynamic>.from(v as Map);
      final locale = (m['locale'] ?? m['language'] ?? '').toString();
      if (!locale.toLowerCase().startsWith('en')) continue;
      final blob = '${m['quality'] ?? ''} ${m['name'] ?? ''} ${m['identifier'] ?? ''}'.toLowerCase();
      if (blob.contains('premium')) {
        out.add((name: '${m['name']}', locale: locale, quality: 'Premium'));
      } else if (blob.contains('enhanced')) {
        out.add((name: '${m['name']}', locale: locale, quality: 'Enhanced'));
      }
    }
  } catch (_) {/* return what we have */}
  return out;
}

abstract class SpeechOutput {
  Future<void> init();
  bool get available;
  bool get speaking;

  /// Speak [text]. [onStart] fires when audio begins; [onDone] fires exactly once when this
  /// utterance ends — whether it finishes naturally OR is stopped by a later speak()/stop() —
  /// UNLESS a newer speak() superseded it first (then the newer call owns the callbacks).
  /// Fire-and-forget: callers don't await completion.
  Future<void> speak(String text, {void Function()? onStart, void Function()? onDone});

  /// Stop the current utterance (mute / barge-in). Resolves its speak() → its onDone fires once.
  Future<void> stop();
}

/// Silent output — tests, muted mode, and platforms without a voice. speak() completes immediately.
class NoopSpeechOutput implements SpeechOutput {
  @override
  Future<void> init() async {}
  @override
  bool get available => false;
  @override
  bool get speaking => false;
  @override
  Future<void> speak(String text, {void Function()? onStart, void Function()? onDone}) async {
    onStart?.call();
    onDone?.call();
  }
  @override
  Future<void> stop() async {}
}

/// On-device TTS via flutter_tts. Completion is driven by the engine's handlers (not by awaiting
/// speak), so it works the same whether or not a platform blocks on synthesis.
class FlutterTtsSpeechOutput implements SpeechOutput {
  final void Function(String msg)? onLog;
  FlutterTtsSpeechOutput({this.onLog});

  final FlutterTts _tts = FlutterTts();
  bool _ready = false, _speaking = false;
  // Each speak() gets a generation. `awaitSpeakCompletion(true)` makes `_tts.speak()` resolve
  // PER UTTERANCE (on completion or stop), so we drive onStart/onDone from that future — not the
  // shared, un-identified engine handlers — and a stale event from a superseded utterance (gen !=
  // _gen) can never cross-fire a newer utterance's callbacks (reviewer d #4/#5).
  int _gen = 0;
  void Function()? _onStart;
  void Function()? _onDone; // the active call's onDone, so stop() can fire it exactly once

  /// iOS ONLY: force the shared audio session to .playback so Plena is audible **in silent mode**
  /// (like Siri) and through the speaker. AVSpeechSynthesizer otherwise obeys the physical ring/silent
  /// switch, and — critically — Apple Speech (STT) leaves the session in .record/.playAndRecord after
  /// listening, which respects the switch. So we re-assert this before EVERY utterance (not just at
  /// init): the last thing to touch the session before we speak wins. No-op off iOS.
  Future<void> _iosPlaybackSession() async {
    if (!Platform.isIOS) return;
    try {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [IosTextToSpeechAudioCategoryOptions.mixWithOthers],
        IosTextToSpeechAudioMode.defaultMode,
      );
    } catch (e) {
      onLog?.call('tts ios session failed: $e');
    }
  }

  /// Pick the most NATURAL English voice the device has. AVSpeechSynthesizer defaults to the robotic
  /// "compact" voice; iOS also ships far better Enhanced/Premium voices (close to Siri) — but only if
  /// the user has downloaded one (Settings → Accessibility → Spoken Content → Voices). We score by
  /// quality (premium > enhanced > compact), prefer en-US, set the winner, and log the full list so a
  /// still-robotic voice is diagnosable as "no premium voice installed" rather than a code bug.
  Future<void> _selectBestVoice() async {
    try {
      final raw = await _tts.getVoices;
      final en = <Map<String, dynamic>>[];
      for (final v in (raw as List? ?? const [])) {
        final m = Map<String, dynamic>.from(v as Map);
        final loc = (m['locale'] ?? m['language'] ?? '').toString().toLowerCase();
        if (loc.startsWith('en')) en.add(m);
      }
      // A user's explicit pick (Settings → Voice) wins over the auto-heuristic — as long as that voice
      // is still installed. This is how "I chose Matilda" beats the default en-US preference.
      final pref = cfg.loadConfig().voiceName;
      if (pref != null) {
        final match = en.where((m) => '${m['name']}' == pref).toList();
        if (match.isNotEmpty) {
          final v = match.first;
          await _tts.setVoice({'name': '${v['name']}', 'locale': '${v['locale'] ?? v['language']}'});
          onLog?.call('tts voice chosen (user pref): ${v['name']} (${v['locale'] ?? v['language']})');
          return;
        }
        onLog?.call('tts: saved voice "$pref" not installed — auto-picking instead');
      }
      int score(Map<String, dynamic> m) {
        final blob = '${m['quality'] ?? ''} ${m['name'] ?? ''} ${m['identifier'] ?? ''}'.toLowerCase();
        if (blob.contains('premium')) return 3;
        if (blob.contains('enhanced')) return 2;
        return 1;
      }
      String loc(Map<String, dynamic> m) => (m['locale'] ?? m['language'] ?? '').toString().toLowerCase();
      en.sort((a, b) {
        final s = score(b).compareTo(score(a));
        if (s != 0) return s;
        return (loc(b) == 'en-us' ? 1 : 0).compareTo(loc(a) == 'en-us' ? 1 : 0);
      });
      onLog?.call('tts voices (en): '
          '${en.map((m) => "${m['name']}/${loc(m)}/q=${m['quality'] ?? '?'}").join(' | ')}');
      if (en.isNotEmpty && score(en.first) > 1) {
        final best = en.first;
        await _tts.setVoice({'name': '${best['name']}', 'locale': '${best['locale'] ?? best['language']}'});
        onLog?.call('tts voice chosen: ${best['name']} (${loc(best)}, q=${best['quality'] ?? '?'})');
      } else {
        onLog?.call('tts: no enhanced/premium voice installed — using the default (robotic) voice');
      }
    } catch (e) {
      onLog?.call('tts voice select failed: $e');
    }
  }

  @override
  Future<void> init() async {
    try {
      await _iosPlaybackSession();
      await _tts.awaitSpeakCompletion(true); // speak() resolves when THAT utterance ends/stops
      if (Platform.isIOS) await _selectBestVoice();
      _tts.setStartHandler(() {
        _speaking = true;
        final s = _onStart;
        _onStart = null;
        s?.call(); // anchor the caller's onStart to real audio onset (reviewer d #9)
      });
      _tts.setErrorHandler((m) => onLog?.call('tts error: $m'));
      await _tts.setSpeechRate(.5); // engine-normalised-ish; tune later
      await _tts.setPitch(1.0);
      _ready = true;
      onLog?.call('tts ready');
    } catch (e) {
      onLog?.call('tts init failed: $e');
      _ready = false;
    }
  }

  @override
  bool get available => _ready;
  @override
  bool get speaking => _speaking;

  /// Point this synthesizer at a specific installed voice — used by the Settings picker to preview a
  /// choice in that exact voice. Best-effort; a bad name just leaves the current voice in place.
  Future<void> setVoiceByName(String name, String locale) async {
    try {
      await _tts.setVoice({'name': name, 'locale': locale});
    } catch (e) {
      onLog?.call('tts setVoice failed: $e');
    }
  }

  @override
  Future<void> speak(String text, {void Function()? onStart, void Function()? onDone}) async {
    if (!_ready || text.trim().isEmpty) {
      onStart?.call();
      onDone?.call();
      return;
    }
    // Claim this generation FIRST — before any await — so a prior sequence's gen-checks bail (its
    // onDone is dropped: the newer speak owns state) and a stop()/speak() arriving during our own
    // awaits below cleanly supersedes us. onDone is retained so stop() can fire it exactly once.
    final gen = ++_gen;
    _onStart = onStart;
    _onDone = onDone;
    _speaking = true;
    if (_ready) {
      try {
        await _tts.stop(); // silence any prior native utterance
      } catch (_) {/* best-effort */}
    }
    // Re-assert .playback here: if the mic just listened, the shared session is in record mode and
    // would silence her in silent mode. Making us the last writer keeps every reply audible.
    await _iosPlaybackSession();
    if (gen != _gen) return; // a newer speak()/stop() arrived during the awaits — it owns state
    // Split on blank-line boundaries into TOPIC segments and speak them with a real silent beat
    // between — so the listener hears one topic close before the next opens (the tour's privacy note
    // vs. the capabilities intro, an essence vs. its "you could say"). Each segment is speakified
    // (track 2). A single-paragraph reply is just one segment, spoken with no added pause.
    final segments = text.split(RegExp(r'\n\s*\n')).map(speakify).where((p) => p.isNotEmpty).toList();
    try {
      for (var i = 0; i < segments.length; i++) {
        if (gen != _gen) return; // superseded mid-sequence (a stop or newer speak bumped _gen)
        await _tts.speak(segments[i]); // note: on Apple this future does NOT resolve on stop — a
        // stop()/speak() supersede is what ends the loop (via the gen check), and stop() fires onDone.
        if (gen != _gen) return;
        if (i < segments.length - 1) {
          await Future.delayed(const Duration(milliseconds: 700)); // the between-topics beat
        }
      }
    } catch (e) {
      onLog?.call('tts speak failed: $e');
    }
    if (gen != _gen) return; // superseded — the newer owner will fire the right onDone
    _speaking = false;
    final done = _onDone;
    _onDone = null;
    done?.call(); // natural end: fires exactly once
  }

  @override
  Future<void> stop() async {
    // Supersede any in-flight sequence: bump the generation so its loop bails at the next gen-check
    // (crucial now that speak() is a multi-SEGMENT loop with 700ms beats — without this, a mute or
    // barge-in during a beat lets the remaining segments play, e.g. over the just-opened mic).
    _gen++;
    _onStart = null;
    _speaking = false;
    final done = _onDone;
    _onDone = null;
    if (_ready) {
      try {
        await _tts.stop();
      } catch (_) {/* best-effort */}
    }
    done?.call(); // the stopped call's onDone fires exactly once (contract), even on Apple where the
    // underlying speak future never resolves after a stop.
  }
}
