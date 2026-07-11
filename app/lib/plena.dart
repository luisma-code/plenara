// Plena — the living presence (Spec 15). A particle swarm ("the murmuration") whose motion,
// hue, and luminance express the app's turn state. This is the first integration slice: the
// animated swarm driven by the real PresenceState, rendered with drawAtlas for one cheap pass.
//
// Deliberately deferred to a later tuning pass (Spec 15 §5A / §6): the comet-trail persistence,
// the glyph vocabulary (fly-out-and-draw), and the in-app tuning controls. The director →
// PresenceFrame → renderer split is final in shape, so those are additive, not a rewrite.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The four base states of Spec 12 / Spec 15 §3.1. Everything else is a modifier (difficulty).
enum PresenceState { idle, listening, thinking, speaking }

/// The whole contract between "what Plena feels" and "how she looks" (Spec 15 §2.4). Smoothed
/// toward a per-state target by the director; the renderer only reads it.
class _Frame {
  double energy = .10, tempo = 1, coherence = .80, turbulence = .05, luminance = .42, spread = .52, lean = 0;
}

class _Target {
  final double energy, tempo, coherence, turbulence, luminance, spread, lean;
  const _Target(this.energy, this.tempo, this.coherence, this.turbulence, this.luminance, this.spread, this.lean);
}

const _targets = <PresenceState, _Target>{
  PresenceState.idle: _Target(.10, 1.00, .80, .05, .42, .52, .00),
  PresenceState.listening: _Target(.34, 1.05, .90, .10, .56, .42, .16),
  PresenceState.thinking: _Target(.17, 0.70, .88, .22, .36, .46, .00),
  PresenceState.speaking: _Target(.55, 1.10, .55, .13, .62, .56, .08),
};

/// Plena, sized into a bounded region (the upper band of the Stage, Spec 15 §2.1). Give her
/// [state] and an optional [difficulty] (0..4); she does the rest.
class PresenceView extends StatefulWidget {
  final PresenceState state;
  final double difficulty; // 0 effortless .. 4 can't (Spec 15 §4.2)
  /// Animate continuously (production). When false — injected in tests, and honoured for OS
  /// reduced-motion — Plena renders a STATIC frame for the current state and runs no ticker,
  /// so `pumpAndSettle` terminates and accessibility is respected (Spec 15 §8.3).
  final bool animate;
  const PresenceView(
      {super.key, this.state = PresenceState.idle, this.difficulty = 0, this.animate = true});
  @override
  State<PresenceView> createState() => _PresenceViewState();
}

class _PresenceViewState extends State<PresenceView> with SingleTickerProviderStateMixin {
  static const _n = 1400; // mote budget (Spec 15 §9.2 T1-ish; tune per platform later)
  final _p = Float32List(_n * 4); // x,y,vx,vy in normalized [-1,1] space
  final _f = _Frame();
  final _rng = math.Random(7); // fixed seed → the same Plena each run (Spec 15 §5.4)
  final _repaint = ValueNotifier<int>(0);
  late final Ticker _ticker;
  bool _running = false;
  ui.Image? _sprite;
  Duration _last = Duration.zero;
  double _acc = 0;
  bool _reduce = false;

  bool get _animating => widget.animate && !_reduce;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _n; i++) {
      final a = _rng.nextDouble() * math.pi * 2, r = math.sqrt(_rng.nextDouble()) * .5;
      _p[i * 4] = math.cos(a) * r;
      _p[i * 4 + 1] = math.sin(a) * r;
    }
    _makeSprite(64).then((img) { if (mounted) { setState(() => _sprite = img); _repaint.value++; } });
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(covariant PresenceView old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// Start/stop the ticker to match [_animating]; when static, snap the frame to the current
  /// state's target so a still Plena still reads as idle/listening/thinking/speaking.
  void _sync() {
    if (_animating && !_running) { _running = true; _last = Duration.zero; _ticker.start(); }
    else if (!_animating && _running) { _running = false; _ticker.stop(); }
    if (!_animating) { _snap(); }
  }

  void _snap() {
    final t = _targets[widget.state]!;
    _f.energy = t.energy; _f.tempo = t.tempo; _f.coherence = t.coherence;
    _f.turbulence = math.min(1, t.turbulence + widget.difficulty * .11);
    _f.luminance = t.luminance; _f.spread = t.spread; _f.lean = t.lean;
    _repaint.value++;
  }

  Future<ui.Image> _makeSprite(int size) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final r = size / 2.0;
    c.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()
        ..shader = ui.Gradient.radial(Offset(r, r), r,
            const [Color(0xFFFFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)], const [0.0, .45, 1.0]),
    );
    return rec.endRecording().toImage(size, size);
  }

  void _onTick(Duration now) {
    final dt = _last == Duration.zero ? 1 / 60 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    // fixed 60 Hz substeps → framerate-independent motion (stable on 120 Hz displays)
    _acc += dt.clamp(0.0, 0.1);
    var steps = 0;
    while (_acc >= 1 / 60 && steps < 4) { _step(); _acc -= 1 / 60; steps++; }
    _repaint.value++;
  }

  void _step() {
    final t = _targets[widget.state]!;
    final k = widget.state == PresenceState.listening
        ? .22
        : widget.state == PresenceState.speaking
            ? .13
            : .06;
    double lp(double a, double b, double f) => a + (b - a) * f;
    _f.energy = lp(_f.energy, t.energy, k);
    _f.tempo = lp(_f.tempo, t.tempo, k);
    _f.coherence = lp(_f.coherence, t.coherence, k);
    _f.turbulence = lp(_f.turbulence, math.min(1, t.turbulence + widget.difficulty * .11), k);
    _f.luminance = lp(_f.luminance, t.luminance, k);
    _f.spread = lp(_f.spread, t.spread, k);
    _f.lean = lp(_f.lean, t.lean, .06);
    if (_reduce) return; // reduced motion: params settle, motes hold still (Spec 15 §8.3)

    final rt = (.10 + (1 - _f.coherence) * .42);
    final flow = (.0016 + .0026 * _f.energy) * _f.tempo * 1.35;
    final jit = _f.turbulence * .010 * 1.35;
    const grav = 0.014 * 0.8;
    // slow global phase for the flow field — derived from tempo, no wall-clock needed
    _phase += (1 / 60) * _f.tempo;
    final tt = _phase;
    for (var i = 0; i < _n; i++) {
      var x = _p[i * 4], y = _p[i * 4 + 1], vx = _p[i * 4 + 2], vy = _p[i * 4 + 3];
      final fx = math.sin(y * 3.1 + tt * 1.7) * math.cos(x * 2.3 - tt * 1.1);
      final fy = math.cos(x * 2.7 + tt * 1.3) * math.sin(y * 2.1 + tt * 0.9);
      vx += fx * flow + (_rng.nextDouble() - .5) * jit;
      vy += fy * flow + (_rng.nextDouble() - .5) * jit;
      final dl = math.sqrt(x * x + y * y);
      if (dl > 1e-3) {
        final pull = (dl - rt) * grav * (0.4 + _f.coherence);
        vx += (-x / dl) * pull;
        vy += (-y / dl) * pull;
      }
      vx *= .905; vy *= .905;
      x += vx; y += vy;
      _p[i * 4] = x; _p[i * 4 + 1] = y; _p[i * 4 + 2] = vx; _p[i * 4 + 3] = vy;
    }
  }

  double _phase = 0;

  /// Vital ramp: warm at rest, cooling toward pre-dawn blue as difficulty climbs (Spec 15 §4.3).
  Color get _color {
    final hue = 34.0 + (214.0 - 34.0) * math.min(1, widget.difficulty * .22);
    final sat = 0.9 * (widget.difficulty >= 4 ? .8 : 1);
    return HSLColor.fromAHSL(1, hue, sat, .56).toColor();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    _sprite?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _PlenaPainter(this, repaint: _repaint),
          size: Size.infinite,
        ),
      );
}

class _PlenaPainter extends CustomPainter {
  final _PresenceViewState s;
  _PlenaPainter(this.s, {required Listenable repaint}) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, mind = math.min(w, h);
    // warm near-black ground — Plena is self-luminous on dark (Spec 15 §9, §10.1)
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0A0908));
    final f = s._f;
    final scale = mind * 0.62;
    final cx = w * .5, cy = h * .5 - f.lean * mind * .28;
    final rgb = s._color;

    // ambient hue aura — carries colour even where motes thin out (the mockup's fireball fix)
    final auraA = (.05 + .12 * f.luminance);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(Offset(cx, cy), scale * 1.15,
            [rgb.withValues(alpha: auraA), rgb.withValues(alpha: 0)]),
    );

    final sprite = s._sprite;
    if (sprite == null) return;
    final src = Rect.fromLTWH(0, 0, sprite.width.toDouble(), sprite.height.toDouble());
    final transforms = <RSTransform>[];
    final rects = <Rect>[];
    final colors = <Color>[];
    for (var i = 0; i < _PresenceViewState._n; i++) {
      final x = s._p[i * 4], y = s._p[i * 4 + 1];
      final dl = math.sqrt(x * x + y * y);
      final rt = (.10 + (1 - f.coherence) * .42);
      final feather = (1 - (math.max(0, dl - rt * 1.1)) / .62).clamp(0.0, 1.0);
      final a = ((.05 + .11 * f.energy) * feather).clamp(0.0, .62);
      if (a <= .004) continue;
      final sz = mind * (.010 + .024 * f.luminance) * (.7 + .5 * feather);
      final px = cx + x * scale, py = cy + y * scale;
      transforms.add(RSTransform.fromComponents(
          rotation: 0,
          scale: (sz * 2) / sprite.width,
          anchorX: sprite.width / 2,
          anchorY: sprite.height / 2,
          translateX: px,
          translateY: py));
      rects.add(src);
      colors.add(rgb.withValues(alpha: a));
    }
    canvas.drawAtlas(sprite, transforms, rects, colors, BlendMode.modulate, null,
        Paint()..blendMode = BlendMode.plus);
  }

  @override
  bool shouldRepaint(covariant _PlenaPainter old) => false; // driven by the repaint Listenable
}
