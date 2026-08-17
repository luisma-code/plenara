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

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:plenara/routines.dart' show sanitizeFigure;

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
  final String? figureSvgB;
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
    this.figureSvgB,
  });
}

/// Decode only the first frame of an animated catalogue image. The three GIF
/// payloads are intentionally frozen: an instructional surface must not loop
/// forever, and Reduce Motion must never depend on the filename extension.
class FirstFrameAsset extends StatefulWidget {
  final String asset;
  const FirstFrameAsset({super.key, required this.asset});

  @override
  State<FirstFrameAsset> createState() => _FirstFrameAssetState();
}

class _FirstFrameAssetState extends State<FirstFrameAsset> {
  ui.Image? _image;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FirstFrameAsset oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset == widget.asset) return;
    _image?.dispose();
    _image = null;
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final data = await rootBundle.load(widget.asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || generation != _loadGeneration) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      // The spoken/written instruction remains the source of truth.
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _image == null
      ? const SizedBox.shrink()
      : RawImage(image: _image, fit: BoxFit.contain);
}

/// Renders a model-drawn figure. **This is where stroke colour and width are imposed**, and it has
/// to be done by wrapping the markup — not with a ColorFilter.
///
/// flutter_svg has no CSS. A path with `fill="none"` and no stroke attributes computes a null paint
/// and is never drawn: it renders as literally nothing. The authoring prompt mandates exactly that
/// shape (fill none, never author a stroke) and the sanitiser rejects figures that set stroke — so
/// every compliant figure painted zero pixels. The readability spike missed it because it rendered
/// in a browser with a stylesheet.
///
/// Wrapping in a `<g>` we control keeps the design intent — the model cannot choose colour or
/// weight, so every figure looks like one product — while actually producing a visible stroke.
class FigureView extends StatelessWidget {
  final String svg;
  final Color color;
  const FigureView({
    super.key,
    required this.svg,
    this.color = const Color(0xFFEAE2D8),
  });

  static const _strokeWidth = '2.4';

  /// Inject our own stroke group just inside the root `<svg>`. Purely additive: children never
  /// set stroke (the sanitiser forbids it), so nothing can override this.
  /// Exposed so a test can rasterise exactly what gets rendered.
  String get strokedMarkup {
    // Re-sanitise on the READ path. Figures are persisted as plaintext JSON in the user's SYNCED
    // folder, so a second device, the sync provider, or a text editor can change them after the
    // authoring-time check. Trusting stored data because it was clean when written is the mistake.
    final safe = sanitizeFigure(svg);
    if (safe == null) return '';
    final open = RegExp(r'<svg[^>]*>').firstMatch(safe);
    if (open == null) return '';
    final hex =
        '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final head = safe.substring(0, open.end);
    final body = safe.substring(open.end, safe.lastIndexOf('</svg>'));
    return '$head<g fill="none" stroke="$hex" stroke-width="$_strokeWidth" '
        'stroke-linecap="round" stroke-linejoin="round">$body</g></svg>';
  }

  @override
  Widget build(BuildContext context) {
    final markup = strokedMarkup;
    if (markup.isEmpty) {
      return const SizedBox.shrink(); // degrade to text, as a missing figure does
    }
    return SvgPicture.string(
      markup,
      fit: BoxFit.contain,
      placeholderBuilder: (_) => const SizedBox.shrink(),
    );
  }
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
      return s < 60
          ? '${s}s'
          : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }
    return step.reps == null ? '' : '${step.reps} reps';
  }

  @override
  Widget build(BuildContext context) {
    final img = step.imageAsset;
    final svg = step.figureSvg;
    final svgB = step.figureSvgB;
    const animatedCatalogueAssets = {
      'assets/exercises/dumbbell-rear-delt-row.png',
      'assets/exercises/dumbbell-wide-bicep-curls.png',
      'assets/exercises/smith-machine-split-squat.png',
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 88, 26, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'step ${step.position} of ${step.total} · ${step.routineTitle}'
                  .toUpperCase(),
              key: const Key('routine-step-header'),
              style: const TextStyle(
                color: Color(0xFFBDB3A7),
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
            Expanded(
              child: Center(
                child: img == null && svg != null
                    // A drawn figure. Rendered by a STATIC rasterizer — flutter_svg executes
                    // nothing — and only after the engine's allowlist has already accepted it.
                    ? svgB == null
                          ? FigureView(svg: svg)
                          : Row(
                              key: const Key('routine-ab-poses'),
                              children: [
                                Expanded(
                                  child: _LabeledPose(
                                    label: 'Start',
                                    child: FigureView(svg: svg),
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: _LabeledPose(
                                    label: 'Finish',
                                    child: FigureView(svg: svgB),
                                  ),
                                ),
                              ],
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
                        child: animatedCatalogueAssets.contains(img)
                            ? FirstFrameAsset(asset: img)
                            : Image.asset(
                                img,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                      )
                    // No illustration for this movement: the words carry it, which they must do
                    // anyway for a screen-off run.
                    : const SizedBox.shrink(),
              ),
            ),
            Text(
              step.name,
              key: const Key('routine-step-name'),
              style: const TextStyle(
                color: Color(0xFFEAE2D8),
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              step.side == 'left' || step.side == 'right'
                  ? '${step.instruction}  (${step.side} side)'
                  : step.instruction,
              style: const TextStyle(
                color: Color(0xFFA9A9BB),
                fontSize: 14.5,
                height: 1.45,
              ),
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
                Text(
                  _amount,
                  style: const TextStyle(
                    color: Color(0xFFEAE2D8),
                    fontSize: 16,
                    fontFeatures: [],
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      key: const Key('routine-stop'),
                      onPressed: onStop,
                      child: const Text(
                        'Stop',
                        style: TextStyle(color: Color(0xFFBDB3A7)),
                      ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        'Next',
                        style: TextStyle(color: Color(0xFFEAE2D8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledPose extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledPose({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label position',
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(child: child),
        const SizedBox(height: 6),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFFBDB3A7),
            fontSize: 11,
            letterSpacing: 1.2,
          ),
        ),
      ],
    ),
  );
}
