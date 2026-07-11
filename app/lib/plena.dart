// Plena — the living presence (Spec 15). A particle swarm ("the murmuration") whose motion,
// hue, and luminance express the app's turn state, and who — on an apt occasion — flies out and
// traces a symbolic GLYPH from her own substance, then lets it drift home and rejoin (§5A).
// Rendered with drawAtlas for one cheap pass.
//
// Still deferred to a later tuning pass (Spec 15 §6): the comet-trail *persistence* and the in-app
// tuning controls. The director → PresenceFrame → renderer split is final in shape, so those are
// additive, not a rewrite.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'glyphs.dart';

/// The four base states of Spec 12 / Spec 15 §3.1. Everything else is a modifier (difficulty).
enum PresenceState { idle, listening, thinking, speaking }

/// Live aesthetic controls (the mockup's knobs, brought into the app so the feel is tunable
/// without a rebuild). Defaults are the values dialed in during the mockup pass.
class PresenceTuning {
  final double hue; // 0..360 base hue (difficulty cools it)
  final double sat; // 0..1 vibrance
  final double bright; // 0.4..1.9 glow
  final double breadth; // 0.5..1.7 how much of the region she spans
  final double gravity; // 0.25..2 core cohesion
  final double loose; // 0.3..2.6 flow/wander
  final double trail; // 0..1 how much she leaves behind as she moves
  const PresenceTuning({
    this.hue = 34,
    this.sat = .9,
    this.bright = 1.15,
    this.breadth = 1.15,
    this.gravity = .75,
    this.loose = 1.45,
    this.trail = .5,
  });
  PresenceTuning copyWith({
    double? hue,
    double? sat,
    double? bright,
    double? breadth,
    double? gravity,
    double? loose,
    double? trail,
  }) => PresenceTuning(
    hue: hue ?? this.hue,
    sat: sat ?? this.sat,
    bright: bright ?? this.bright,
    breadth: breadth ?? this.breadth,
    gravity: gravity ?? this.gravity,
    loose: loose ?? this.loose,
    trail: trail ?? this.trail,
  );
}

/// The whole contract between "what Plena feels" and "how she looks" (Spec 15 §2.4). Smoothed
/// toward a per-state target by the director; the renderer only reads it.
class _Frame {
  double energy = .10,
      tempo = 1,
      coherence = .80,
      turbulence = .05,
      luminance = .42,
      spread = .52,
      lean = 0;
}

class _Target {
  final double energy, tempo, coherence, turbulence, luminance, spread, lean;
  const _Target(
    this.energy,
    this.tempo,
    this.coherence,
    this.turbulence,
    this.luminance,
    this.spread,
    this.lean,
  );
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

  /// The glyph to trace next, fired by bumping [glyphNonce] (a fresh value each time). Null or an
  /// unchanged nonce plays nothing — most turns pass none (apt-or-absent, §5A.1).
  final GlyphDef? glyph;
  final int glyphNonce;
  final PresenceTuning tuning;
  const PresenceView({
    super.key,
    this.state = PresenceState.idle,
    this.difficulty = 0,
    this.animate = true,
    this.glyph,
    this.glyphNonce = 0,
    this.tuning = const PresenceTuning(),
  });
  @override
  State<PresenceView> createState() => _PresenceViewState();
}

/// A glyph in flight: Plena's core rides the ordered path targets by their fill-time; travelling
/// motes deposit at each to hold the figure, then release and rejoin.
class _GlyphRun {
  final List<double> tx = [], ty = [], tf = []; // target x, y, fill-time(ms)
  final List<bool> filled = [];
  late final List<int>
  travellers; // shuffled traveller indices, consumed as deposits
  int dc = 0; // deposit cursor
  double ms = 0; // elapsed since start
  late final double lastFill, flourishStart, flourishEnd, holdEnd, endAt;
  bool flit = false, released = false;
}

class _PresenceViewState extends State<PresenceView>
    with SingleTickerProviderStateMixin {
  static const _n =
      1400; // mote budget (Spec 15 §9.2 T1-ish; tune per platform later)
  final _p = Float32List(_n * 4); // x,y,vx,vy in normalized [-1,1] space
  final _mode = Int8List(_n); // 0 free, 1 deposited into a glyph
  final _trav = Int8List(_n); // 1 while flying the glyph path
  final _tgt = Float32List(_n * 2); // deposit target (x,y) for mode==1
  double _coreX = 0,
      _coreY = 0; // Plena's centre of mass (flies the path during a glyph)
  _GlyphRun? _run;
  final _f = _Frame();
  final _rng = math.Random(
    7,
  ); // fixed seed → the same Plena each run (Spec 15 §5.4)
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
      final a = _rng.nextDouble() * math.pi * 2,
          r = math.sqrt(_rng.nextDouble()) * .5;
      _p[i * 4] = math.cos(a) * r;
      _p[i * 4 + 1] = math.sin(a) * r;
    }
    _makeSprite(64).then((img) {
      if (mounted) {
        setState(() => _sprite = img);
        _repaint.value++;
      }
    });
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
    if (_animating &&
        widget.glyph != null &&
        widget.glyphNonce != old.glyphNonce) {
      _startGlyph(widget.glyph!);
    }
  }

  /// Start/stop the ticker to match [_animating]; when static, snap the frame to the current
  /// state's target so a still Plena still reads as idle/listening/thinking/speaking.
  void _sync() {
    if (_animating && !_running) {
      _running = true;
      _last = Duration.zero;
      _ticker.start();
    } else if (!_animating && _running) {
      _running = false;
      _ticker.stop();
    }
    if (!_animating) {
      _snap();
    }
  }

  void _snap() {
    final t = _targets[widget.state]!;
    _f.energy = t.energy;
    _f.tempo = t.tempo;
    _f.coherence = t.coherence;
    _f.turbulence = math.min(1, t.turbulence + widget.difficulty * .11);
    _f.luminance = t.luminance;
    _f.spread = t.spread;
    _f.lean = t.lean;
    _repaint.value++;
  }

  // ---- glyph flight (Spec 15 §5A.4) ----
  Offset _along(List<Offset> pts, List<double> cum, double tot, double u) {
    final d = u * tot;
    var i = 1;
    while (i < cum.length && cum[i] < d) {
      i++;
    }
    if (i >= cum.length) return pts.last;
    final seg = cum[i] - cum[i - 1];
    final t = seg.abs() < 1e-9 ? 0.0 : (d - cum[i - 1]) / seg;
    return Offset(
      pts[i - 1].dx + (pts[i].dx - pts[i - 1].dx) * t,
      pts[i - 1].dy + (pts[i].dy - pts[i - 1].dy) * t,
    );
  }

  Offset _corePath(_GlyphRun r) {
    if (r.tf.isEmpty) return Offset.zero;
    if (r.ms <= r.tf.first) return Offset(r.tx.first, r.ty.first);
    for (var i = 0; i < r.tf.length - 1; i++) {
      if (r.ms < r.tf[i + 1]) {
        final span = r.tf[i + 1] - r.tf[i];
        final f = span.abs() < 1e-9 ? 0.0 : (r.ms - r.tf[i]) / span;
        return Offset(
          r.tx[i] + (r.tx[i + 1] - r.tx[i]) * f,
          r.ty[i] + (r.ty[i + 1] - r.ty[i]) * f,
        );
      }
    }
    return Offset(r.tx.last, r.ty.last);
  }

  void _startGlyph(GlyphDef g) {
    final pts = <List<double>>[]; // [x, y, fillTimeMs]
    for (final d in g.dots) {
      for (var k = 0; k < 20; k++) {
        final a = _rng.nextDouble() * math.pi * 2,
            r = math.sqrt(_rng.nextDouble()) * .05;
        pts.add([
          d.at.dx + math.cos(a) * r,
          d.at.dy + math.sin(a) * r,
          d.delayMs + k * 3.0,
        ]);
      }
    }
    for (final s in g.strokes) {
      final cum = <double>[0];
      var tot = 0.0;
      for (var i = 1; i < s.pts.length; i++) {
        tot += (s.pts[i] - s.pts[i - 1]).distance;
        cum.add(tot);
      }
      final n = math.max(18, math.min(200, (tot * 115).round()));
      for (var k = 0; k < n; k++) {
        final u = n == 1 ? 0.0 : k / (n - 1);
        final p = _along(s.pts, cum, tot, u);
        pts.add([p.dx, p.dy, s.delayMs + u * s.drawMs]);
      }
    }
    pts.sort((a, b) => a[2].compareTo(b[2]));
    final cap = math.min(600, pts.length);
    final run = _GlyphRun();
    for (var i = 0; i < cap; i++) {
      final j = pts.length == cap ? i : (i * pts.length / cap).floor();
      run.tx.add(pts[j][0]);
      run.ty.add(pts[j][1]);
      run.tf.add(pts[j][2]);
      run.filled.add(false);
    }
    final idx = List<int>.generate(_n, (i) => i);
    for (var i = _n - 1; i > 0; i--) {
      final j = _rng.nextInt(i + 1);
      final t = idx[i];
      idx[i] = idx[j];
      idx[j] = t;
    }
    final nt = (_n * 0.70).floor();
    for (var i = 0; i < _n; i++) {
      _mode[i] = 0;
      _trav[i] = 0;
    }
    for (var i = 0; i < nt; i++) {
      _trav[idx[i]] = 1;
    }
    run.travellers = idx.sublist(0, nt);
    run.lastFill = run.tf.isEmpty ? 0 : run.tf.last;
    run.flourishStart = run.lastFill + 140;
    run.flourishEnd = run.lastFill + 140 + 480;
    run.holdEnd = run.lastFill + 140 + 480 + 520;
    run.endAt = run.lastFill + 140 + 480 + 520 + 1100;
    _run = run;
  }

  Future<ui.Image> _makeSprite(int size) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final r = size / 2.0;
    c.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(r, r),
          r,
          const [Color(0xFFFFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
          const [0.0, .45, 1.0],
        ),
    );
    return rec.endRecording().toImage(size, size);
  }

  void _onTick(Duration now) {
    final dt = _last == Duration.zero
        ? 1 / 60
        : (now - _last).inMicroseconds / 1e6;
    _last = now;
    // fixed 60 Hz substeps → framerate-independent motion (stable on 120 Hz displays)
    _acc += dt.clamp(0.0, 0.1);
    var steps = 0;
    while (_acc >= 1 / 60 && steps < 4) {
      _step();
      _acc -= 1 / 60;
      steps++;
    }
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
    _f.turbulence = lp(
      _f.turbulence,
      math.min(1, t.turbulence + widget.difficulty * .11),
      k,
    );
    _f.luminance = lp(_f.luminance, t.luminance, k);
    _f.spread = lp(_f.spread, t.spread, k);
    _f.lean = lp(_f.lean, t.lean, .06);
    if (_reduce) {
      return; // reduced motion: params settle, motes hold still (Spec 15 §8.3)
    }

    // ---- glyph state machine: Plena flies the path, sheds her tail, flourishes, rejoins ----
    final run = _run;
    if (run != null) {
      run.ms += 1000 / 60;
      Offset ct;
      if (run.ms < run.lastFill) {
        ct = _corePath(run);
      } else if (run.ms < run.flourishEnd) {
        final w =
            math.sin((run.ms - run.lastFill) * .03) *
            .05; // a pleased flitter at the end
        ct = Offset(run.tx.last + w, run.ty.last - w.abs() * .6);
      } else {
        ct = Offset.zero; // home
      }
      final eK = run.ms < run.lastFill ? .34 : .12;
      _coreX += (ct.dx - _coreX) * eK;
      _coreY += (ct.dy - _coreY) * eK;
      for (var i = 0; i < run.tf.length; i++) {
        // deposit: hand a travelling mote to the shape
        if (run.filled[i] || run.ms < run.tf[i]) continue;
        while (run.dc < run.travellers.length) {
          final pi = run.travellers[run.dc++];
          if (_mode[pi] == 0) {
            _mode[pi] = 1;
            _tgt[pi * 2] = run.tx[i];
            _tgt[pi * 2 + 1] = run.ty[i];
            run.filled[i] = true;
            break;
          }
        }
      }
      if (!run.flit && run.ms >= run.flourishStart) {
        run.flit = true;
        for (var i = 0; i < _n; i++) {
          if (_trav[i] == 1 && _mode[i] == 0) {
            _p[i * 4 + 2] += (_rng.nextDouble() - .5) * .055;
            _p[i * 4 + 3] += (_rng.nextDouble() - .5) * .055;
          }
        }
      }
      if (!run.released && run.ms >= run.holdEnd) {
        run.released = true;
        for (var i = 0; i < _n; i++) {
          _mode[i] = 0;
          _trav[i] = 0;
        }
      }
      if (run.ms >= run.endAt) {
        _run = null;
        for (var i = 0; i < _n; i++) {
          _mode[i] = 0;
          _trav[i] = 0;
        }
      }
    } else {
      _coreX += (0 - _coreX) * .05;
      _coreY += (0 - _coreY) * .05;
    }
    final gActive = _run != null;

    final tn = widget.tuning;
    final rt = (.10 + (1 - _f.coherence) * .42) * tn.breadth;
    final flow = (.0016 + .0026 * _f.energy) * _f.tempo * tn.loose;
    final jit = _f.turbulence * .010 * tn.loose;
    final grav = 0.014 * tn.gravity;
    // slow global phase for the flow field — derived from tempo, no wall-clock needed
    _phase += (1 / 60) * _f.tempo;
    final tt = _phase;
    for (var i = 0; i < _n; i++) {
      var x = _p[i * 4],
          y = _p[i * 4 + 1],
          vx = _p[i * 4 + 2],
          vy = _p[i * 4 + 3];
      if (gActive && _mode[i] == 1) {
        // deposited: hold the figure softly (Plena's wispy tail)
        x += (_tgt[i * 2] - x) * .15 + (_rng.nextDouble() - .5) * .0022;
        y += (_tgt[i * 2 + 1] - y) * .15 + (_rng.nextDouble() - .5) * .0022;
        _p[i * 4] = x;
        _p[i * 4 + 1] = y;
        _p[i * 4 + 2] = 0;
        _p[i * 4 + 3] = 0;
        continue;
      }
      // attraction centre: travellers chase Plena's flying core; everyone else holds home
      var ax = 0.0, ay = 0.0, rti = rt, gi = grav, fli = flow;
      if (gActive && _trav[i] == 1) {
        ax = _coreX;
        ay = _coreY;
        rti = .05;
        gi = grav * 2.4;
        fli = flow * .5;
      }
      final fx = math.sin(y * 3.1 + tt * 1.7) * math.cos(x * 2.3 - tt * 1.1);
      final fy = math.cos(x * 2.7 + tt * 1.3) * math.sin(y * 2.1 + tt * 0.9);
      vx += fx * fli + (_rng.nextDouble() - .5) * jit;
      vy += fy * fli + (_rng.nextDouble() - .5) * jit;
      final dx = ax - x, dy = ay - y, dl = math.sqrt(dx * dx + dy * dy);
      if (dl > 1e-3) {
        final pull = (dl - rti) * gi * (0.4 + _f.coherence);
        vx += (dx / dl) * pull;
        vy += (dy / dl) * pull;
      }
      vx *= .905;
      vy *= .905;
      x += vx;
      y += vy;
      _p[i * 4] = x;
      _p[i * 4 + 1] = y;
      _p[i * 4 + 2] = vx;
      _p[i * 4 + 3] = vy;
    }
  }

  double _phase = 0;

  /// Vital ramp: the tuned base hue, cooling toward pre-dawn blue as difficulty climbs (§4.3).
  Color get _color {
    final tn = widget.tuning;
    final hue =
        tn.hue + (214.0 - tn.hue) * math.min(1, widget.difficulty * .22);
    final sat = (tn.sat * (widget.difficulty >= 4 ? .8 : 1)).clamp(0.0, 1.0);
    return HSLColor.fromAHSL(1, ((hue % 360) + 360) % 360, sat, .56).toColor();
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
  _PlenaPainter(this.s, {required Listenable repaint})
    : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, mind = math.min(w, h);
    final tn = s.widget.tuning;
    // warm near-black ground — Plena is self-luminous on dark (Spec 15 §9, §10.1)
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0A0908),
    );
    final f = s._f;
    final scale = mind * 0.58 * tn.breadth; // Breadth
    final cx = w * .5, cy = h * .5 - f.lean * mind * .28;
    final rgb = s._color;
    final bri = tn.bright;

    // ambient hue aura — carries colour even where motes thin out (the mockup's fireball fix)
    final auraA = ((.05 + .12 * f.luminance) * bri).clamp(0.0, .6);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(Offset(cx, cy), scale * 1.15, [
          rgb.withValues(alpha: auraA),
          rgb.withValues(alpha: 0),
        ]),
    );

    final sprite = s._sprite;
    if (sprite == null) return;
    final src = Rect.fromLTWH(
      0,
      0,
      sprite.width.toDouble(),
      sprite.height.toDouble(),
    );
    final transforms = <RSTransform>[];
    final rects = <Rect>[];
    final colors = <Color>[];
    final gActive = s._run != null;
    final rt = (.10 + (1 - f.coherence) * .42) * tn.breadth;
    // Trail: a few fainter echoes behind each mote along its velocity — she leaves a bit of
    // herself behind as she moves. Length scales with the Trail knob and the mote's speed.
    final trailSteps = tn.trail <= .02
        ? 0
        : (1 + (tn.trail * 3).round()).clamp(1, 4);

    void emit(double px, double py, double sz, Color c) {
      transforms.add(
        RSTransform.fromComponents(
          rotation: 0,
          scale: (sz * 2) / sprite.width,
          anchorX: sprite.width / 2,
          anchorY: sprite.height / 2,
          translateX: px,
          translateY: py,
        ),
      );
      rects.add(src);
      colors.add(c);
    }

    for (var i = 0; i < _PresenceViewState._n; i++) {
      final x = s._p[i * 4], y = s._p[i * 4 + 1];
      final px = cx + x * scale, py = cy + y * scale;
      double a, sz;
      final deposited = gActive && s._mode[i] == 1;
      if (deposited) {
        // deposited: Plena's TAIL — faint, wispy, holds the figure
        a = (.19 * f.luminance + .06).clamp(0.0, .28) * bri;
        sz = mind * (.013 + .02 * f.luminance);
      } else {
        // feather relative to this mote's attraction centre (the flying core for travellers)
        final ax = gActive && s._trav[i] == 1 ? s._coreX : 0.0;
        final ay = gActive && s._trav[i] == 1 ? s._coreY : 0.0;
        final rti = gActive && s._trav[i] == 1 ? .05 : rt;
        final dl = math.sqrt((x - ax) * (x - ax) + (y - ay) * (y - ay));
        final feather = (1 - (math.max(0, dl - rti * 1.1)) / (.62 * tn.breadth))
            .clamp(0.0, 1.0);
        a = ((.05 + .11 * f.energy) * feather * bri).clamp(0.0, .62);
        sz = mind * (.010 + .024 * f.luminance) * (.7 + .5 * feather);
      }
      if (a <= .004) continue;
      // trailing echoes (skip for deposits — they already hold still)
      if (trailSteps > 0 && !deposited) {
        final vx = s._p[i * 4 + 2], vy = s._p[i * 4 + 3];
        for (var t = 1; t <= trailSteps; t++) {
          final back = t * (3.0 + 9.0 * tn.trail);
          emit(
            px - vx * scale * back,
            py - vy * scale * back,
            sz * (1 - .12 * t),
            rgb.withValues(alpha: a * (.5 / (t + 1))),
          );
        }
      }
      emit(px, py, sz, rgb.withValues(alpha: a));
    }
    canvas.drawAtlas(
      sprite,
      transforms,
      rects,
      colors,
      BlendMode.modulate,
      null,
      Paint()..blendMode = BlendMode.plus,
    );
  }

  @override
  bool shouldRepaint(covariant _PlenaPainter old) => false; // driven by the repaint Listenable
}
