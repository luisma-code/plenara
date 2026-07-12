// The symbolic glyph vocabulary (Spec 15 §5A) as DATA — not render code. A glyph is a brief
// line-figure Plena traces from her own substance then releases. Each is defined by ordered
// strokes (a comet flies each) + dot marks, in normalized presence space [-1,1] (y down), with
// per-part delays so multi-part figures draw in order ("the eyes land, then the smile sweeps").
//
// Coverage: the 15 CORE glyphs (Spec 15 §5A.8) plus the extended set — including the detail-heavy
// † figures (gift, laurel, cake, teacup, clasp, balloon, open-book), authored here as spare
// emblems. Some † figures read best at higher mote counts; the exact forms are a first pass and
// the natural thing to refine by eye (the dev preview: long-press Plena).
import 'dart:math' as math;
import 'dart:ui' show Offset;

class GlyphStroke {
  final List<Offset> pts;
  final double delayMs; // when this stroke starts, from glyph start
  final double drawMs; // how long the comet takes to sweep it
  const GlyphStroke(this.pts, {this.delayMs = 0, this.drawMs = 640});
}

class GlyphDot {
  final Offset at;
  final double delayMs;
  const GlyphDot(this.at, {this.delayMs = 0});
}

class GlyphDef {
  final String id;
  final String
  occasion; // WHY it fires — the definition is the occasion (Spec 15 §5A.1)
  final bool core; // ships first (§5A.8)
  final List<GlyphStroke> strokes;
  final List<GlyphDot> dots;
  const GlyphDef(
    this.id,
    this.occasion, {
    this.core = false,
    this.strokes = const [],
    this.dots = const [],
  });

  double get lastFill {
    var m = 0.0;
    for (final s in strokes) {
      m = math.max(m, s.delayMs + s.drawMs);
    }
    for (final d in dots) {
      m = math.max(m, d.delayMs + 120);
    }
    return m;
  }
}

// ---- generators (all in normalized [-1,1], y down) ----
Offset _p(double x, double y) => Offset(x, y);
List<Offset> _line(Offset a, Offset b) => [a, b];
List<Offset> _arc(
  double cx,
  double cy,
  double r,
  double a0,
  double a1, [
  int n = 28,
]) => [
  for (var i = 0; i < n; i++)
    Offset(
      cx + r * math.cos(a0 + (a1 - a0) * i / (n - 1)),
      cy + r * math.sin(a0 + (a1 - a0) * i / (n - 1)),
    ),
];
List<Offset> _circle(double cx, double cy, double r, [int n = 34]) =>
    _arc(cx, cy, r, -math.pi / 2, -math.pi / 2 + math.pi * 2, n);
List<Offset> _star() {
  const R = 0.62, r = 0.25;
  return [
    for (var i = 0; i <= 10; i++)
      Offset(
        (i.isOdd ? r : R) * math.cos(-math.pi / 2 + i * math.pi / 5),
        (i.isOdd ? r : R) * math.sin(-math.pi / 2 + i * math.pi / 5),
      ),
  ];
}

List<Offset> _heart([int n = 80]) => [
  for (var i = 0; i < n; i++)
    () {
      final t = i / (n - 1) * math.pi * 2;
      final x = 16 * math.pow(math.sin(t), 3).toDouble();
      final y =
          13 * math.cos(t) -
          5 * math.cos(2 * t) -
          2 * math.cos(3 * t) -
          math.cos(4 * t);
      return Offset(x * 0.05, -y * 0.05);
    }(),
];
List<Offset> _spiral(double turns, double r, [int n = 48]) => [
  for (var i = 0; i < n; i++)
    () {
      final t = i / (n - 1);
      final a = t * turns * math.pi * 2;
      final rr = r * t;
      return Offset(rr * math.cos(a), rr * math.sin(a));
    }(),
];

// a pointed-leaf blade (vesica): down the left edge, back up the right — a closed figure whose
// width swells at the middle and pinches to a point top and bottom. Pair with a midrib line.
List<Offset> _leafBlade([double w = .32, int n = 30]) => [
  for (var i = 0; i <= n; i++)
    Offset(-w * math.sin(math.pi * i / n), -.5 + i / n), // left edge, top → bottom
  for (var i = 0; i <= n; i++)
    Offset(w * math.sin(math.pi * i / n), .5 - i / n), // right edge, bottom → top
];

GlyphStroke _s(List<Offset> pts, {double delay = 0, double draw = 640}) =>
    GlyphStroke(pts, delayMs: delay, drawMs: draw);

/// The vocabulary, keyed by id. `occasion` is the trigger; the app maps a turn to one of these
/// (apt-or-absent) — most turns map to none.
final Map<String, GlyphDef> kGlyphs = {
  // ---------------- CORE (15) ----------------
  'smile': GlyphDef(
    'smile',
    'greeting — first open of the day',
    core: true,
    dots: [GlyphDot(_p(-.22, -.20)), GlyphDot(_p(.22, -.20), delayMs: 130)],
    strokes: [
      _s(_arc(0, -.02, .5, 0.5, math.pi - 0.5, 40), delay: 380, draw: 640),
    ],
  ),
  'check': GlyphDef(
    'check',
    'a meaningful task completed',
    core: true,
    strokes: [
      _s([_p(-.34, .04), _p(-.08, .32), _p(.42, -.34)], draw: 620),
    ],
  ),
  'heart': GlyphDef(
    'heart',
    'closeness logged with a loved one',
    core: true,
    strokes: [_s(_heart(), draw: 1000)],
  ),
  'wave': GlyphDef(
    'wave',
    'farewell — goodnight sign-off',
    core: true,
    // a SMOOTH undulating ribbon (a hand waving), not a sharp zigzag — 2 gentle cycles
    strokes: [
      _s([
        for (var i = 0; i < 46; i++)
          Offset(-.55 + 1.1 * i / 45, -.24 * math.sin(i / 45 * math.pi * 4)),
      ], draw: 820),
    ],
  ),
  'spark': GlyphDef(
    'spark',
    'a small delight the assistant found',
    core: true,
    strokes: [
      _s(_line(_p(0, -.5), _p(0, .5)), draw: 220),
      _s(_line(_p(-.5, 0), _p(.5, 0)), delay: 180, draw: 220),
      _s(_line(_p(-.34, -.34), _p(.34, .34)), delay: 360, draw: 200),
      _s(_line(_p(-.34, .34), _p(.34, -.34)), delay: 520, draw: 200),
    ],
  ),
  'question': GlyphDef(
    'question',
    'a clarification asked (accompanies the chips)',
    core: true,
    dots: [GlyphDot(_p(0, .5), delayMs: 620)],
    strokes: [
      _s(_arc(0, -.18, .3, math.pi, -0.2, 22)..addAll([_p(0, .18)]), draw: 560),
    ],
  ),
  'ellipsis': GlyphDef(
    'ellipsis',
    'thinking-hard — a long cloud round-trip',
    core: true,
    dots: [
      GlyphDot(_p(-.35, 0)),
      GlyphDot(_p(0, 0), delayMs: 180),
      GlyphDot(_p(.35, 0), delayMs: 360),
    ],
  ),
  'sunrise': GlyphDef(
    'sunrise',
    'the morning brief delivered',
    core: true,
    strokes: [
      _s(_line(_p(-.55, .22), _p(.55, .22)), draw: 320),
      _s(_arc(0, .22, .34, math.pi, 0, 22), delay: 300, draw: 420),
      _s(_line(_p(-.5, -.05), _p(-.6, -.15)), delay: 700, draw: 120),
      _s(_line(_p(0, -.2), _p(0, -.32)), delay: 780, draw: 120),
      _s(_line(_p(.5, -.05), _p(.6, -.15)), delay: 860, draw: 120),
    ],
  ),
  'crescent': GlyphDef(
    'crescent',
    'evening wind-down / rest nudge',
    core: true,
    strokes: [
      _s(_arc(0, 0, .5, -math.pi / 2, math.pi / 2, 24), draw: 460),
      _s(
        _arc(.16, 0, .42, -math.pi / 2, math.pi / 2, 22),
        delay: 360,
        draw: 420,
      ),
    ],
  ),
  'star': GlyphDef(
    'star',
    'a streak milestone reached (7 / 30 / 100 days)',
    core: true,
    strokes: [_s(_star(), draw: 900)],
  ),
  'candle': GlyphDef(
    'candle',
    "a birthday surfaces today",
    core: true,
    // a candle with real body width + a teardrop flame (was a lollipop: one line + a ring)
    strokes: [
      _s(_line(_p(-.13, .42), _p(-.13, -.12)), draw: 300), // left body
      _s(_line(_p(.13, .42), _p(.13, -.12)), delay: 160, draw: 300), // right body
      _s(_line(_p(-.13, .42), _p(.13, .42)), delay: 360, draw: 150), // base
      _s(_line(_p(-.13, -.12), _p(.13, -.12)), delay: 460, draw: 150), // rim
      _s(_line(_p(0, -.12), _p(0, -.2)), delay: 600, draw: 120), // wick
      _s([_p(0, -.2), _p(-.07, -.3), _p(0, -.44), _p(.07, -.3), _p(0, -.2)],
          delay: 720, draw: 360), // teardrop flame
    ],
  ),
  'nod': GlyphDef(
    'nod',
    'assent — a "got it" moment',
    core: true,
    strokes: [_s(_arc(0, -.35, .4, 0.35, math.pi - 0.35, 22), draw: 520)],
  ),
  'ripple': GlyphDef(
    'ripple',
    '"I heard you" — a weighty spoken entry lands',
    core: true,
    strokes: [
      _s(_arc(0, 0, .2, math.pi * .8, math.pi * 2.2, 18), draw: 340),
      _s(
        _arc(0, 0, .4, math.pi * .8, math.pi * 2.2, 22),
        delay: 260,
        draw: 380,
      ),
      _s(
        _arc(0, 0, .6, math.pi * .8, math.pi * 2.2, 26),
        delay: 560,
        draw: 420,
      ),
    ],
  ),
  'settle': GlyphDef(
    'settle',
    'softening bad news — a lapsed streak, a miss',
    core: true,
    strokes: [_s(_arc(0, .5, .5, -math.pi + 0.5, -0.5, 24), draw: 760)],
  ),
  'quill': GlyphDef(
    'quill',
    'a journal entry saved',
    core: true,
    // a feather: a rachis (writing tip at lower-left) with barbs fanning off both sides — was a
    // bare diagonal slash + a floating dot, which read as a stroke, not a quill.
    strokes: [
      _s([_p(-.42, .46), _p(.42, -.46)], draw: 520), // rachis
      _s([_p(-.04, .06), _p(.12, .08)], delay: 420, draw: 110), // right barbs, tip → base
      _s([_p(.1, -.1), _p(.26, -.08)], delay: 480, draw: 110),
      _s([_p(.24, -.26), _p(.4, -.24)], delay: 540, draw: 110),
      _s([_p(-.04, .06), _p(-.12, -.08)], delay: 600, draw: 110), // left barbs
      _s([_p(.1, -.1), _p(.02, -.24)], delay: 660, draw: 110),
      _s([_p(.24, -.26), _p(.16, -.4)], delay: 720, draw: 110),
    ],
  ),

  // ---------------- EXTENDED (readable) ----------------
  'warm-smile': GlyphDef(
    'warm-smile',
    'reunion — first open after days away',
    dots: [
      GlyphDot(_p(-.22, -.2), delayMs: 620),
      GlyphDot(_p(.22, -.2), delayMs: 720),
    ],
    strokes: [_s(_arc(0, -.02, .52, 0.5, math.pi - 0.5, 40), draw: 620)],
  ),
  'wink': GlyphDef(
    'wink',
    "a light joke lands in the reply",
    dots: [GlyphDot(_p(.22, -.2), delayMs: 260)],
    strokes: [
      _s(_line(_p(-.34, -.2), _p(-.1, -.2)), draw: 200),
      _s(_arc(0, -.02, .5, 0.6, math.pi - 0.6, 34), delay: 360, draw: 560),
    ],
  ),
  'double-check': GlyphDef(
    'double-check',
    'list cleared — every task of the day done',
    strokes: [
      _s([_p(-.44, .0), _p(-.24, .24), _p(.08, -.28)], draw: 420),
      _s([_p(-.06, .04), _p(.16, .3), _p(.5, -.3)], delay: 360, draw: 460),
    ],
  ),
  'up-arrow': GlyphDef(
    'up-arrow',
    'a weekly review shows an improving trend',
    strokes: [
      _s(_line(_p(0, .45), _p(0, -.45)), draw: 380),
      _s(_line(_p(-.28, -.16), _p(0, -.45)), delay: 360, draw: 200),
      _s(_line(_p(.28, -.16), _p(0, -.45)), delay: 520, draw: 200),
    ],
  ),
  'flag': GlyphDef(
    'flag',
    'a goal completed — a finish line',
    strokes: [
      _s(_line(_p(-.4, .5), _p(-.4, -.45)), draw: 420),
      _s([_p(-.4, -.4), _p(.35, -.25), _p(-.4, -.1)], delay: 400, draw: 420),
    ],
  ),
  'rising-bars': GlyphDef(
    'rising-bars',
    'a positive week across habits',
    strokes: [
      _s(_line(_p(-.4, .4), _p(-.4, .1)), draw: 220),
      _s(_line(_p(0, .4), _p(0, -.1)), delay: 220, draw: 260),
      _s(_line(_p(.4, .4), _p(.4, -.35)), delay: 480, draw: 300),
    ],
  ),
  'spiral': GlyphDef(
    'spiral',
    'thinking-hard — a dialect alternative to ellipsis',
    strokes: [_s(_spiral(1.6, .55), draw: 900)],
  ),
  'orbit': GlyphDef(
    'orbit',
    'a long background op begins',
    dots: [GlyphDot(_p(0, 0))],
    strokes: [_s(_circle(0, 0, .5, 34), delay: 200, draw: 700)],
  ),
  'small-check': GlyphDef(
    'small-check',
    'a capture worth marking (a flagged item)',
    strokes: [
      _s([_p(-.17, .02), _p(-.04, .16), _p(.21, -.17)], draw: 360),
    ],
  ),
  'up-tick': GlyphDef(
    'up-tick',
    'encouragement — progress on something hard',
    strokes: [
      _s([_p(-.4, .1), _p(.1, .1), _p(.35, -.28)], draw: 460),
    ],
  ),
  'leaf': GlyphDef(
    'leaf',
    'a rest day honored',
    // a closed blade + a midrib (was a bare vein between two open arcs → read as a "ϕ")
    strokes: [
      _s(_leafBlade(), draw: 720),
      _s(_line(_p(0, -.44), _p(0, .44)), delay: 520, draw: 320),
    ],
  ),
  'bell': GlyphDef(
    'bell',
    'a reminder the user asked to be sure about',
    strokes: [
      _s(_arc(0, .1, .38, math.pi, 0, 22), draw: 460),
      _s(_line(_p(-.38, .1), _p(.38, .1)), delay: 420, draw: 220),
    ],
    dots: [GlyphDot(_p(0, .26), delayMs: 640)],
  ),
  'seedling': GlyphDef(
    'seedling',
    'a new habit created — day zero',
    strokes: [
      _s(_line(_p(0, .45), _p(0, -.2)), draw: 380),
      _s(_arc(-.16, -.2, .18, 0, -math.pi, 12), delay: 360, draw: 240),
      _s(_arc(.16, -.2, .18, math.pi, 0, 12), delay: 560, draw: 240),
    ],
  ),
  'bridge': GlyphDef(
    'bridge',
    'reconnection — a reach-out after a long gap',
    dots: [GlyphDot(_p(-.5, .1)), GlyphDot(_p(.5, .1), delayMs: 120)],
    strokes: [_s(_arc(0, .1, .5, math.pi, 0, 24), delay: 320, draw: 560)],
  ),
  'meeting-line': GlyphDef(
    'meeting-line',
    'a new person added to the circle',
    dots: [GlyphDot(_p(-.45, 0)), GlyphDot(_p(.45, 0), delayMs: 120)],
    strokes: [_s(_line(_p(-.4, 0), _p(.4, 0)), delay: 320, draw: 460)],
  ),
  'linked-rings': GlyphDef(
    'linked-rings',
    'two people connected — an introduction',
    strokes: [
      _s(_circle(-.2, 0, .3, 26), draw: 520),
      _s(_circle(.2, 0, .3, 26), delay: 460, draw: 520),
    ],
  ),
  'target': GlyphDef(
    'target',
    'a goal set — the moment of commitment',
    strokes: [
      _s(_circle(0, 0, .55, 30), draw: 520),
      _s(_circle(0, 0, .28, 22), delay: 460, draw: 420),
    ],
    dots: [GlyphDot(_p(0, 0), delayMs: 900)],
  ),
  'clock': GlyphDef(
    'clock',
    'a far-ahead promise made',
    strokes: [
      _s(_circle(0, 0, .5, 30), draw: 560),
      _s(_line(_p(0, 0), _p(0, -.3)), delay: 520, draw: 200),
      _s(_line(_p(0, 0), _p(.24, .06)), delay: 700, draw: 200),
    ],
  ),
  'hourglass': GlyphDef(
    'hourglass',
    'a gentle deadline approaches',
    strokes: [
      _s([_p(-.35, -.45), _p(.35, -.45), _p(0, 0), _p(-.35, -.45)], draw: 480),
      _s(
        [_p(-.35, .45), _p(.35, .45), _p(0, 0), _p(-.35, .45)],
        delay: 440,
        draw: 480,
      ),
    ],
  ),
  'enso': GlyphDef(
    'enso',
    'day closed — the evening review completes',
    strokes: [
      _s(
        _arc(
          0,
          0,
          .55,
          -math.pi / 2 + 0.3,
          -math.pi / 2 + math.pi * 2 - 0.15,
          40,
        ),
        draw: 1000,
      ),
    ],
  ),
  'breath-tilde': GlyphDef(
    'breath-tilde',
    'a breathing / unwind prompt accepted',
    strokes: [
      _s([
        for (var i = 0; i < 40; i++)
          Offset(-.6 + 1.2 * i / 39, 0.18 * math.sin(i / 39 * math.pi * 3)),
      ], draw: 900),
    ],
  ),
  'snooze-arc': GlyphDef(
    'snooze-arc',
    'a reminder snoozed — set aside, not lost',
    dots: [GlyphDot(_p(.5, .28), delayMs: 560)],
    strokes: [_s(_arc(0, -.1, .5, -math.pi + 0.2, 0.5, 26), draw: 560)],
  ),
  'undo-loop': GlyphDef(
    'undo-loop',
    'undo taken — the last act unwound',
    strokes: [
      _s(_arc(0, 0, .4, -0.4, -0.4 - math.pi * 1.5, 30), draw: 620),
      _s([_p(-.4, -.1), _p(-.28, -.24), _p(-.16, -.06)], delay: 560, draw: 200),
    ],
  ),
  'infinity': GlyphDef(
    'infinity',
    "a multi-year bond's anniversary",
    strokes: [
      _s([
        for (var i = 0; i < 60; i++)
          () {
            final t = i / 59 * math.pi * 2;
            return Offset(.55 * math.sin(t), .28 * math.sin(t) * math.cos(t));
          }(),
      ], draw: 900),
    ],
  ),
  'house': GlyphDef(
    'house',
    'a family gathering; a "home" plan',
    strokes: [
      _s([
        _p(-.4, .4),
        _p(-.4, -.05),
        _p(0, -.4),
        _p(.4, -.05),
        _p(.4, .4),
        _p(-.4, .4),
      ], draw: 820),
    ],
  ),
  'still-flame': GlyphDef(
    'still-flame',
    'remembrance — a memorial date surfaces',
    dots: [GlyphDot(_p(0, -.34), delayMs: 520)],
    strokes: [_s(_line(_p(0, .42), _p(0, -.18)), draw: 700)],
  ),
  'pulse-heart': GlyphDef(
    'pulse-heart',
    'a relationship anniversary; a long closeness streak',
    strokes: [_s(_heart(), draw: 900)],
  ),

  // ---------------- EXTENDED (the detail-heavy † set, as spare emblems) ----------------
  'gift': GlyphDef(
    'gift',
    'a gift idea captured for someone',
    strokes: [
      _s([
        _p(-.35, .42),
        _p(-.35, -.05),
        _p(.35, -.05),
        _p(.35, .42),
        _p(-.35, .42),
      ], draw: 640),
      _s(_line(_p(-.44, -.05), _p(.44, -.05)), delay: 600, draw: 200),
      _s(_line(_p(0, .42), _p(0, -.05)), delay: 780, draw: 180),
    ],
    dots: [
      GlyphDot(_p(-.1, -.16), delayMs: 900),
      GlyphDot(_p(.1, -.16), delayMs: 960),
    ],
  ),
  'laurel': GlyphDef(
    'laurel',
    'a major milestone — a year of journaling',
    // two curved branches meeting at the base, open at the top, each with leaflet ticks — a
    // wreath. (Was two bare arcs + a few dots, which read as loose parentheses.)
    strokes: [
      _s([_p(0, .42), _p(-.16, .24), _p(-.28, 0), _p(-.3, -.24), _p(-.22, -.42)], draw: 520),
      _s([_p(0, .42), _p(.16, .24), _p(.28, 0), _p(.3, -.24), _p(.22, -.42)], delay: 460, draw: 520),
      _s([_p(-.16, .24), _p(-.32, .26)], delay: 940, draw: 100), // left leaflets
      _s([_p(-.28, 0), _p(-.45, -.02)], delay: 1000, draw: 100),
      _s([_p(-.3, -.24), _p(-.44, -.32)], delay: 1060, draw: 100),
      _s([_p(.16, .24), _p(.32, .26)], delay: 1120, draw: 100), // right leaflets
      _s([_p(.28, 0), _p(.45, -.02)], delay: 1180, draw: 100),
      _s([_p(.3, -.24), _p(.44, -.32)], delay: 1240, draw: 100),
    ],
  ),
  'cake': GlyphDef(
    'cake',
    "a close person's birthday — the fuller form",
    strokes: [
      _s(_line(_p(-.4, .1), _p(.4, .1)), draw: 300),
      _s(_line(_p(-.3, -.15), _p(.3, -.15)), delay: 280, draw: 260),
      _s(_line(_p(0, -.15), _p(0, -.4)), delay: 540, draw: 200),
    ],
    dots: [GlyphDot(_p(0, -.48), delayMs: 760)],
  ),
  'teacup': GlyphDef(
    'teacup',
    'a break suggested — "you\'ve been at this a while"',
    strokes: [
      _s(_arc(0, 0, .34, 0.2, math.pi - 0.2, 20), draw: 420),
      _s(
        _arc(.4, .08, .14, -math.pi * .5, math.pi * .5, 12),
        delay: 400,
        draw: 260,
      ),
      _s(
        [
          for (var i = 0; i < 16; i++)
            Offset(
              -.05 + 0.06 * math.sin(i / 15 * math.pi * 2),
              -.28 - .28 * i / 15,
            ),
        ],
        delay: 640,
        draw: 420,
      ),
    ],
  ),
  'clasp': GlyphDef(
    'clasp',
    'comfort — a hard journal entry or a grief note',
    // two hooks interlocking (hands held) — offset so their openings embrace, not two arcs meeting
    // to a point (which read as an eye / fish).
    strokes: [
      _s(_arc(-.06, -.06, .26, math.pi * .35, math.pi * 1.55, 22), draw: 520),
      _s(_arc(.06, .06, .26, math.pi * 1.35, math.pi * 2.55, 22), delay: 480, draw: 520),
    ],
  ),
  'balloon': GlyphDef(
    'balloon',
    "a loved one's happy news, logged (engagement, a new baby)",
    strokes: [
      _s(_circle(0, -.15, .3, 26), draw: 520),
      _s(
        [
          for (var i = 0; i < 20; i++)
            Offset(0.06 * math.sin(i / 19 * math.pi * 2), .18 + .28 * i / 19),
        ],
        delay: 520,
        draw: 420,
      ),
    ],
    dots: [GlyphDot(_p(0, .16), delayMs: 500)],
  ),
  'open-book': GlyphDef(
    'open-book',
    'a journal session begins',
    strokes: [
      _s(_line(_p(0, -.35), _p(0, .35)), draw: 320),
      _s(
        _arc(-.28, 0, .32, -math.pi * .5, math.pi * .5, 16),
        delay: 300,
        draw: 380,
      ),
      _s(
        _arc(.28, 0, .32, math.pi * .5, math.pi * 1.5, 16),
        delay: 300,
        draw: 380,
      ),
    ],
  ),
};

/// Resolve a completed turn to an apt glyph, or null — Spec 15 §5A.1 "apt or absent": only a
/// clearly-fitting moment fires; the overwhelming majority of turns return null. [skill] is the
/// dispatched skill id ("a+b" for a compound turn); [reply] is the assistant's text.
GlyphDef? glyphForTurn(String? skill, String reply) {
  if (skill == null) return null;
  final r = reply.toLowerCase();
  bool said(String s) => r.contains(s);
  bool ran(String s) =>
      skill.contains(s); // contains → matches inside a compound "a+b"

  if (said('undone') || said('reverted') || said('undid') || said('reversed')) {
    return kGlyphs['undo-loop'];
  }
  // a LAPSED streak / a miss is bad news → soften it, never celebrate (checked before the star)
  if (said('lapsed') || said('missed') || said('streak ended') || said('streak reset') || said('broke your streak')) {
    return kGlyphs['settle'];
  }
  if (said('streak') || said('days running') || said('days in a row')) {
    return kGlyphs['star']; // a milestone reached
  }
  if (said("that's everything") || said('all done for the day') || said('list is clear')) {
    return kGlyphs['double-check'];
  }
  if (ran('complete-task') || ran('complete-reminder')) {
    return kGlyphs['check']; // a meaningful done
  }
  if (ran('set-goal')) return kGlyphs['target']; // the moment of commitment
  if (ran('log-journal')) return kGlyphs['quill']; // the day's writing is in
  // closeness with a partner earns the heart; a plain interaction gets only a quiet nod
  if (ran('remember-relationship') &&
      (said('wife') || said('husband') || said('partner') || said('spouse'))) {
    return kGlyphs['heart'];
  }
  if (ran('log-interaction')) return kGlyphs['nod']; // "got it — noted"
  return null; // most turns: nothing
}
