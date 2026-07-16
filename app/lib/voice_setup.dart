import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:plenara/config.dart';

import 'speech_out.dart';

/// Shared "Plena's voice" surface, used in both onboarding and Settings. Two states:
///  - no natural voice installed → a nudge to download one (iOS ships only the robotic compact voice
///    by default; the Siri-caliber Enhanced/Premium voices are a free one-time download, and there's
///    no App-Store-safe way to deep-link the Voices page, so we spell out the path);
///  - one or more natural voices installed → a PICKER, because iOS won't tell an app which voice the
///    user set as their system default, so the user chooses here (e.g. Australian "Matilda" over the
///    auto-picked US voice). The choice persists in config and loads on next launch.
///
/// Re-checks on resume so the card updates the moment a voice is downloaded. [hideWhenNatural] —
/// onboarding passes true (collapse once any natural voice exists); Settings passes false (always
/// show the picker so the state is legible).
class VoiceUpgradeCard extends StatefulWidget {
  final bool hideWhenNatural;
  const VoiceUpgradeCard({super.key, this.hideWhenNatural = false});
  @override
  State<VoiceUpgradeCard> createState() => _VoiceUpgradeCardState();
}

class _VoiceUpgradeCardState extends State<VoiceUpgradeCard> with WidgetsBindingObserver {
  bool _loaded = false;
  List<({String name, String locale, String quality})> _voices = const [];
  String? _selected; // persisted voice-name pref (null = app auto-picks)
  FlutterTtsSpeechOutput? _preview;
  String? _previewing; // name currently previewing

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preview?.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(); // caught a just-downloaded voice
  }

  Future<void> _refresh() async {
    final voices = await naturalEnglishVoices();
    final pref = loadConfig().voiceName;
    if (mounted) {
      setState(() {
        _voices = voices;
        _selected = pref;
        _loaded = true;
      });
    }
  }

  static String _accent(String locale) => switch (locale.toLowerCase()) {
        'en-us' => 'American',
        'en-au' => 'Australian',
        'en-gb' => 'British',
        'en-ie' => 'Irish',
        'en-in' => 'Indian',
        'en-za' => 'South African',
        _ => locale,
      };

  Future<void> _choose(({String name, String locale, String quality}) v) async {
    saveConfig(voiceName: v.name); // persists; the live app voice picks it up on next launch
    setState(() {
      _selected = v.name;
      _previewing = v.name;
    });
    final tts = _preview ??= FlutterTtsSpeechOutput();
    await tts.init();
    await tts.setVoiceByName(v.name, v.locale);
    await tts.speak(
      "Hi, I'm Plena — this is how I'll sound.",
      onDone: () {
        if (mounted) setState(() => _previewing = null);
      },
    );
  }

  Future<void> _previewCurrent() async {
    setState(() => _previewing = '__current__');
    final tts = _preview ??= FlutterTtsSpeechOutput();
    await tts.init();
    await tts.speak(
      "Hi, I'm Plena. This is how I sound right now — download a Premium voice and I'll sound far more natural.",
      onDone: () {
        if (mounted) setState(() => _previewing = null);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Off iOS (desktop engines don't have the compact/premium split) there's nothing to nudge or pick
    // — render nothing rather than iOS-only download instructions. Also don't flash a card in then out.
    if (!_loaded || !Platform.isIOS) return const SizedBox.shrink();
    if (_voices.isEmpty) return _downloadCard(cs); // no natural voice yet → nudge (onboarding + Settings)
    if (widget.hideWhenNatural) return const SizedBox.shrink(); // has one → onboarding collapses
    return _pickerCard(cs); // has one → Settings shows the picker
  }

  Widget _pickerCard(ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Text('Choose the voice Plena speaks in. Tap one to hear it.',
                style: TextStyle(color: cs.outline, fontSize: 13)),
          ),
          for (final v in _voices)
            ListTile(
              key: Key('voice-${v.name}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              dense: true,
              leading: Icon(
                _selected == v.name ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: _selected == v.name ? cs.primary : cs.outline,
              ),
              title: Text(v.name.replaceAll(RegExp(r'\s*\((Premium|Enhanced)\)'), '')),
              subtitle: Text('${_accent(v.locale)} · ${v.quality}'),
              trailing: _previewing == v.name
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.volume_up, color: cs.outline),
              onTap: () => _choose(v),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text('Reopen Plenara if a reply is still in the previous voice.',
                style: TextStyle(color: cs.outline, fontSize: 12)),
          ),
        ]),
      ),
    );
  }

  Widget _downloadCard(ColorScheme cs) {
    Widget step(String n, String t) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n. ', style: const TextStyle(fontWeight: FontWeight.bold)),
            Expanded(child: Text(t)),
          ]),
        );
    return Card(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.record_voice_over, color: cs.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Give Plena a natural voice', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 8),
          const Text("Right now Plena uses iOS's basic built-in voice — a bit robotic. Apple's natural "
              '“Premium” voices sound close to Siri and are a free one-time download:'),
          const SizedBox(height: 8),
          step('1', 'Open Settings → Accessibility → Spoken Content (or “Read & Speak”) → Voices → English.'),
          step('2', 'Tap a Premium voice — Zoe, Evan, Matilda, Nathan… — and download it.'),
          step('3', 'Come back here; you can then pick which one Plena uses.'),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('preview-voice'),
              onPressed: _previewing != null ? null : _previewCurrent,
              icon: _previewing == '__current__'
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.volume_up, size: 18),
              label: const Text('Hear how she sounds now'),
            ),
          ),
        ]),
      ),
    );
  }
}
