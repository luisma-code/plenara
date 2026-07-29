/// The generated-figure fallback (Spec 16 §2, amended). Catalogue illustrations cover ~1/3 of
/// exercises; the rest can get a model-drawn stick figure instead of nothing.
///
/// SVG is a format that can carry script, external references and CSS, so the sanitiser is the
/// security boundary of this feature and is tested adversarially. It is an ALLOWLIST: anything not
/// explicitly permitted rejects the whole figure, and a rejected figure degrades to text — the same
/// rendering a step with no illustration already gets.
library;

import 'package:plenara/routines.dart';
import 'package:test/test.dart';

const _ok = '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">'
    '<circle cx="50" cy="20" r="8" fill="none"/>'
    '<path d="M50 28 L50 60" fill="none"/>'
    '<line x1="8" y1="78" x2="92" y2="78"/></svg>';

void main() {
  group('the sanitiser accepts only the render-only subset', () {
    test('a clean figure passes through unchanged', () {
      expect(sanitizeFigure(_ok), _ok);
    });

    test('every dangerous construct is rejected outright', () {
      final attacks = <String, String>{
        'script element': '<svg viewBox="0 0 100 100"><script>alert(1)</script></svg>',
        'event handler': '<svg viewBox="0 0 100 100"><circle cx="1" cy="1" r="1" onload="x()"/></svg>',
        'xlink:href': '<svg viewBox="0 0 100 100"><use xlink:href="#a"/></svg>',
        'plain href': '<svg viewBox="0 0 100 100"><path d="M0 0" href="http://x"/></svg>',
        'external image': '<svg viewBox="0 0 100 100"><image href="http://x/a.png"/></svg>',
        'style element': '<svg viewBox="0 0 100 100"><style>*{fill:red}</style></svg>',
        'style attribute': '<svg viewBox="0 0 100 100"><circle style="fill:url(#x)" r="1"/></svg>',
        'foreignObject': '<svg viewBox="0 0 100 100"><foreignObject><b>hi</b></foreignObject></svg>',
        'SMIL animation': '<svg viewBox="0 0 100 100"><animate attributeName="x"/></svg>',
        'data uri': '<svg viewBox="0 0 100 100"><path d="M0 0" fill="data:image/png;base64,AA"/></svg>',
        'url() reference': '<svg viewBox="0 0 100 100"><path d="M0 0" fill="url(#evil)"/></svg>',
        'javascript uri': '<svg viewBox="0 0 100 100"><path d="M0 0" fill="javascript:x"/></svg>',
        'entity declaration': '<!DOCTYPE svg [<!ENTITY x "y">]><svg viewBox="0 0 100 100"></svg>',
        'css import': '<svg viewBox="0 0 100 100"><path d="@import url(x)"/></svg>',
        'unknown element': '<svg viewBox="0 0 100 100"><iframe/></svg>',
        'unknown attribute': '<svg viewBox="0 0 100 100"><circle r="1" onmouseover="x"/></svg>',
      };
      attacks.forEach((name, svg) {
        expect(sanitizeFigure(svg), isNull, reason: 'must reject: $name');
      });
    });

    test('malformed or oversized input is rejected, not repaired', () {
      expect(sanitizeFigure(null), isNull);
      expect(sanitizeFigure(''), isNull);
      expect(sanitizeFigure('not svg at all'), isNull);
      expect(sanitizeFigure('<svg viewBox="0 0 100 100">'), isNull, reason: 'unterminated');
      expect(sanitizeFigure('<svg><circle r="1"/></svg>'), isNull, reason: 'no viewBox');
      final huge = '<svg viewBox="0 0 100 100">${'<circle r="1"/>' * 2000}</svg>';
      expect(sanitizeFigure(huge), isNull, reason: 'over the size cap');
    });

    test('the model cannot impose its own stroke colour or weight', () {
      // Colour/width are the renderer's job — that is what keeps every routine looking like one
      // product rather than drifting per generation.
      expect(sanitizeFigure('<svg viewBox="0 0 100 100"><path d="M0 0" stroke="#f00"/></svg>'),
          isNull);
      expect(sanitizeFigure('<svg viewBox="0 0 100 100"><path d="M0 0" stroke-width="9"/></svg>'),
          isNull);
    });
  });

  group('correspondence decides tween vs toggle', () {
    test('same structure, different coordinates -> tweenable', () {
      const a = '<svg viewBox="0 0 100 100"><circle cx="50" cy="20" r="8"/><path d="M50 28 L50 60"/></svg>';
      const b = '<svg viewBox="0 0 100 100"><circle cx="50" cy="30" r="8"/><path d="M50 38 L50 70"/></svg>';
      expect(figuresCorrespond(a, b), isTrue);
    });

    test('different element counts or path commands -> NOT tweenable', () {
      const a = '<svg viewBox="0 0 100 100"><circle cx="50" cy="20" r="8"/></svg>';
      const b = '<svg viewBox="0 0 100 100"><circle cx="50" cy="20" r="8"/><path d="M0 0 L1 1"/></svg>';
      expect(figuresCorrespond(a, b), isFalse);
      const c = '<svg viewBox="0 0 100 100"><path d="M50 28 L50 60"/></svg>';
      const d = '<svg viewBox="0 0 100 100"><path d="M50 28 C1 1 2 2 3 3"/></svg>';
      expect(figuresCorrespond(c, d), isFalse);
    });
  });

  group('validateFigure degrades rather than rejecting the step', () {
    test('a good pair validates and is marked tweenable', () {
      const a = '<svg viewBox="0 0 100 100"><path d="M50 28 L50 60"/></svg>';
      const b = '<svg viewBox="0 0 100 100"><path d="M50 30 L50 70"/></svg>';
      final f = validateFigure({'frameA': a, 'frameB': b});
      expect(f, isNotNull);
      expect(f!.tweenable, isTrue);
    });

    test('a hostile second frame does not poison the first — B falls back to A', () {
      final f = validateFigure({'frameA': _ok, 'frameB': '<svg viewBox="0 0 1 1"><script/></svg>'});
      expect(f, isNotNull);
      expect(f!.frameB, f.frameA, reason: 'a rejected B degrades to a static A');
    });

    test('a hostile FIRST frame rejects the whole figure', () {
      expect(validateFigure({'frameA': '<svg viewBox="0 0 1 1"><script/></svg>', 'frameB': _ok}),
          isNull);
    });

    test('a non-map or empty payload is null, never a crash', () {
      expect(validateFigure(null), isNull);
      expect(validateFigure('nope'), isNull);
      expect(validateFigure(<String, dynamic>{}), isNull);
    });
  });
}
