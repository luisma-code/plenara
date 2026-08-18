// INTERNAL-ONLY development surfaces: the live tuning sheet and the Dev harness.
//
// COMPILE-TIME REACHABILITY MATTERS HERE. Both entry points below are only ever
// called from behind the `!isExternalBuild` compile-time constant (see
// `_menuButton` in main.dart). That is what lets AOT tree-shake this whole file
// — and its 'Dev harness' / 'Tune Plena' strings — out of an external binary;
// `tool/external_release_gate.sh` scans the compiled artifact for exactly those
// strings. Never call these from a runtime-only gate, and never widen the guard.
import 'package:flutter/material.dart';

import 'glyphs.dart';
import 'plena.dart';
import 'speech_out.dart';

/// Everything the dev sheets need to reach back into [ChatScreen]'s state. The
/// screen owns the state; the sheets only read and write it, always inside the
/// screen's own `setState` via [applyToScreen].
class DevHarnessBinding {
  /// The screen's `setState` — the sheets mutate screen state only through it.
  final void Function(VoidCallback) applyToScreen;
  final PresenceTuning Function() readTuning;
  final void Function(PresenceTuning) writeTuning;
  final PresenceState? Function() readForceState;
  final void Function(PresenceState?) writeForceState;
  final double? Function() readForceDifficulty;
  final void Function(double?) writeForceDifficulty;
  final String? Function() readCaption;
  final bool Function() readDisplayIsList;
  final void Function(String? caption, bool isList) writeDisplay;
  final SpeechOutput? Function() readVoice;
  final void Function(GlyphDef) fireGlyph;

  const DevHarnessBinding({
    required this.applyToScreen,
    required this.readTuning,
    required this.writeTuning,
    required this.readForceState,
    required this.writeForceState,
    required this.readForceDifficulty,
    required this.writeForceDifficulty,
    required this.readCaption,
    required this.readDisplayIsList,
    required this.writeDisplay,
    required this.readVoice,
    required this.fireGlyph,
  });
}

/// A live tuning sheet for Plena — the mockup's knobs in the app, so the feel is dialed by eye
/// without a rebuild. Changes apply to _tuning immediately (Plena reads it every frame).
void openTuningSheet(BuildContext context, DevHarnessBinding binding) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        Widget row(
          String label,
          double value,
          double min,
          double max,
          PresenceTuning Function(double) apply,
        ) => Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(label, style: Theme.of(ctx).textTheme.bodyMedium),
            ),
            Expanded(
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: (v) {
                  binding.applyToScreen(() => binding.writeTuning(apply(v)));
                  setSheet(() {});
                },
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                value.toStringAsFixed(value >= 10 ? 0 : 2),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        );
        final t = binding.readTuning();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tune Plena', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              row('Hue', t.hue, 0, 360, (v) => t.copyWith(hue: v)),
              row('Vibrance', t.sat, .3, 1, (v) => t.copyWith(sat: v)),
              row(
                'Brightness',
                t.bright,
                .4,
                1.9,
                (v) => t.copyWith(bright: v),
              ),
              row('Breadth', t.breadth, .5, 1.7, (v) => t.copyWith(breadth: v)),
              row('Gravity', t.gravity, .25, 2, (v) => t.copyWith(gravity: v)),
              row('Looseness', t.loose, .3, 2.6, (v) => t.copyWith(loose: v)),
              row('Trail', t.trail, 0, 1, (v) => t.copyWith(trail: v)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    binding.applyToScreen(
                      () => binding.writeTuning(const PresenceTuning()),
                    );
                    setSheet(() {});
                  },
                  child: const Text('Reset'),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// The Dev harness — drive the UI directly (states, difficulty, glyphs, display modes, voice)
/// without going through the engine, so you can exercise every visual by hand. The barrier is
/// transparent and the sheet half-height, so Plena stays lit and visible above it while you poke.
void openDevHarnessSheet(BuildContext context, DevHarnessBinding binding) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    barrierColor: Colors.transparent, // keep Plena visible while harnessing
    backgroundColor: const Color(0xFF17130F).withValues(alpha: .96),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final tt = Theme.of(ctx).textTheme;
        void both(VoidCallback fn) {
          binding.applyToScreen(fn);
          setSheet(() {});
        }

        Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(
            s.toUpperCase(),
            style: tt.labelSmall?.copyWith(
              letterSpacing: 1.4,
              color: Colors.white54,
            ),
          ),
        );
        Widget pick(String text, bool on, VoidCallback onTap) => ChoiceChip(
          label: Text(text),
          selected: on,
          onSelected: (_) => onTap(),
        );

        final voice = binding.readVoice();
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * .52,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dev harness', style: tt.titleMedium),
                  Text(
                    'Force the UI directly — no turn required.',
                    style: tt.bodySmall?.copyWith(color: Colors.white54),
                  ),

                  label('Presence state'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      pick(
                        'Live',
                        binding.readForceState() == null,
                        () => both(() => binding.writeForceState(null)),
                      ),
                      for (final s in PresenceState.values)
                        pick(
                          s.name,
                          binding.readForceState() == s,
                          () => both(() => binding.writeForceState(s)),
                        ),
                    ],
                  ),

                  label('Difficulty (0 effortless → 4 can\'t)'),
                  Row(
                    children: [
                      pick(
                        'Live',
                        binding.readForceDifficulty() == null,
                        () => both(() => binding.writeForceDifficulty(null)),
                      ),
                      Expanded(
                        child: Slider(
                          value: (binding.readForceDifficulty() ?? 0).clamp(
                            0,
                            4,
                          ),
                          min: 0,
                          max: 4,
                          divisions: 4,
                          label: (binding.readForceDifficulty() ?? 0)
                              .toStringAsFixed(0),
                          onChanged: (v) =>
                              both(() => binding.writeForceDifficulty(v)),
                        ),
                      ),
                    ],
                  ),

                  label('Display over the void'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      pick(
                        'Clear',
                        binding.readCaption() == null,
                        () => both(() => binding.writeDisplay(null, false)),
                      ),
                      pick(
                        'Caption',
                        binding.readCaption() != null &&
                            !binding.readDisplayIsList(),
                        () => both(
                          () => binding.writeDisplay(
                            'Logged dinner with Katherine — Rina got into UW.',
                            false,
                          ),
                        ),
                      ),
                      pick(
                        'List (ease to corner)',
                        binding.readDisplayIsList(),
                        () => both(
                          () => binding.writeDisplay(
                            'Interactions with Katherine:\n  • dinner (Sun)\n'
                            '  • coffee (Fri)\n  • call (Wed)',
                            true,
                          ),
                        ),
                      ),
                    ],
                  ),

                  label('Voice'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: (voice?.available ?? false)
                            ? () => voice?.speak(
                                'This is Plena — testing, one two three.',
                              )
                            : null,
                        child: const Text('Speak a test line'),
                      ),
                      OutlinedButton(
                        onPressed: () => voice?.stop(),
                        child: const Text('Stop'),
                      ),
                      FilledButton.tonal(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          openTuningSheet(context, binding);
                        },
                        child: const Text('Tune Plena…'),
                      ),
                    ],
                  ),

                  label('Fire a gesture (${kGlyphs.length} glyphs)'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in kGlyphs.entries)
                        ActionChip(
                          label: Text(e.key),
                          tooltip: e.value.occasion,
                          onPressed: () => binding.fireGlyph(e.value),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
