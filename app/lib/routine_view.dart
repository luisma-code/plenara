/// The routine player's visual surface (Spec 16). A Y1 "guest" over the void: Plena eases to her
/// corner exactly as she does for a list reply, and the step hovers in the space she vacates.
///
/// Two deliberate choices worth keeping:
///  * The figure is CONTENT, not a presence glyph. Plena's glyph system has hard rarity caps and an
///    apt-or-absent rule; a functional exercise diagram every 45 seconds would shred them. So this
///    renders in a Plena-ADJACENT idiom (thin light strokes on the void) without pretending to be
///    part of her.
///  * The illustration is recoloured with a RENDER-TIME filter, never by shipping altered files.
///    The assets are CC BY-SA 4.0, and share-alike attaches to adaptations — displaying the work
///    with a display transform is a cleaner position than distributing a modified copy.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Everything the card needs, lifted out of the engine's records so this widget stays dumb.
class RoutineStepView {
  final String routineTitle, name, instruction;
  final int position, total;
  final int? durationSeconds, reps;
  final String side;
  /// Bundled asset path for the catalogue illustration, or null.
  final String? imageAsset;
  /// A model-drawn stick figure for a movement the catalogue could not illustrate — the fallback
  /// tier (catalogue image > drawn figure > text only). Already sanitised against a strict
  /// render-only allowlist in the engine; stroke colour and width are imposed HERE, never authored,
  /// so every generated figure looks like one product.
  final String? figureSvg;
  const RoutineStepView({
    required this.routineTitle,
    required this.name,
    required this.instruction,
    required this.position,
    required this.total,
    required this.side,
    this.durationSeconds,
    this.reps,
    this.imageAsset,
    this.figureSvg,
  });
}

class RoutineStepCard extends StatelessWidget {
  final RoutineStepView step;
  final VoidCallback onNext;
  final VoidCallback onStop;
  /// 0..1 through the current timed step; null for a rep-based step (which waits for you).
  final double? progress;
  const RoutineStepCard({
    super.key,
    required this.step,
    required this.onNext,
    required this.onStop,
    this.progress,
  });

  String get _amount {
    if (step.durationSeconds != null) {
      final s = step.durationSeconds!;
      return s < 60 ? '${s}s' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }
    return step.reps == null ? '' : '${step.reps} reps';
  }

  @override
  Widget build(BuildContext context) {
    final img = step.imageAsset;
    final svg = step.figureSvg;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 88, 26, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('step ${step.position} of ${step.total} · ${step.routineTitle}'.toUpperCase(),
                key: const Key('routine-step-header'),
                style: const TextStyle(
                    color: Color(0x996F6F85), fontSize: 11, letterSpacing: 1.2)),
            Expanded(
              child: Center(
                child: img == null && svg != null
                    // A drawn figure. Rendered by a STATIC rasterizer — flutter_svg executes
                    // nothing — and only after the engine's allowlist has already accepted it.
                    ? SvgPicture.string(
                        svg,
                        fit: BoxFit.contain,
                        theme: const SvgTheme(currentColor: Color(0xFFEAE2D8)),
                        colorFilter: const ColorFilter.mode(Color(0xFFEAE2D8), BlendMode.srcIn),
                        placeholderBuilder: (_) => const SizedBox.shrink(),
                      )
                    : img != null
                    ? ColorFiltered(
                        // invert() turns the catalogue's dark-on-transparent line art into light
                        // strokes that sit directly on the void — no card, no white slab.
                        colorFilter: const ColorFilter.matrix(<double>[
                          -1, 0, 0, 0, 255, //
                          0, -1, 0, 0, 255, //
                          0, 0, -1, 0, 255, //
                          0, 0, 0, 1, 0, //
                        ]),
                        // errorBuilder, not an existence check: a missing asset must degrade to
                        // the text-only rendering rather than throw mid-workout.
                        child: Image.asset(img, fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      )
                    // No illustration for this movement: the words carry it, which they must do
                    // anyway for a screen-off run.
                    : const SizedBox.shrink(),
              ),
            ),
            Text(step.name,
                key: const Key('routine-step-name'),
                style: const TextStyle(
                    color: Color(0xFFEAE2D8), fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              step.side == 'left' || step.side == 'right'
                  ? '${step.instruction}  (${step.side} side)'
                  : step.instruction,
              style: const TextStyle(color: Color(0xFFA9A9BB), fontSize: 14.5, height: 1.45),
            ),
            const SizedBox(height: 18),
            if (progress != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress!.clamp(0, 1),
                  minHeight: 3,
                  backgroundColor: const Color(0x22FFFFFF),
                  valueColor: const AlwaysStoppedAnimation(Color(0x88CFD6FF)),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_amount,
                    style: const TextStyle(
                        color: Color(0xFFEAE2D8), fontSize: 16, fontFeatures: [])),
                Row(children: [
                  TextButton(
                    key: const Key('routine-stop'),
                    onPressed: onStop,
                    child: const Text('Stop', style: TextStyle(color: Color(0x886F6F85))),
                  ),
                  const SizedBox(width: 8),
                  // The touch parallel to saying "next". Tap-anywhere stays the MIC gesture, so
                  // stepping needs its own target — and the timer means neither is required.
                  OutlinedButton(
                    key: const Key('routine-next'),
                    onPressed: onNext,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0x33FFFFFF)),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    ),
                    child: const Text('Next', style: TextStyle(color: Color(0xFFEAE2D8))),
                  ),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
