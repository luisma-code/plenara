import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/speech_out.dart';

void main() {
  group('speakify — track-2 TTS text', () {
    test('drops bullet leaders and joins list items into flowing speech', () {
      final out = speakify('Here is what I can do:\n  • log a dinner\n  • remember a birthday');
      expect(out.contains('•'), isFalse);
      expect(out.contains('\n'), isFalse);
      // items become clauses, not choppy lines
      expect(out, contains('log a dinner'));
      expect(out, contains('remember a birthday'));
    });

    test('blank lines become sentence stops; single newlines after non-terminal text become pauses', () {
      // blank line → full stop; a mid-sentence newline → comma pause; an already-terminal line → space
      final out = speakify('All set.\n\nTell me\nwhat happened?');
      expect(out.contains('\n'), isFalse);
      expect(out, contains('All set. Tell me')); // blank line → '. '
      expect(out, contains('Tell me, what happened?')); // 'me' is non-terminal → comma pause
    });

    test('strips markdown and status emoji, expands a few symbols', () {
      final out = speakify('**Rina** & Sam — e.g. dinner ✨');
      expect(out.contains('*'), isFalse);
      expect(out.contains('✨'), isFalse);
      expect(out, contains('Rina and Sam'));
      expect(out, contains('for example'));
    });

    test('leaves plain prose essentially unchanged', () {
      expect(speakify('I logged dinner with Katherine.'), 'I logged dinner with Katherine.');
    });

    test('a stripped glyph before punctuation leaves no space — and never a literal " \$1"', () {
      // Regression: replaceAll does not interpret \$1, so the space-before-punct cleanup MUST use
      // replaceAllMapped. A trailing "✨." (emoji stripped → space before the period) is the trigger.
      final out = speakify('Saved ✨.');
      expect(out, 'Saved.');
      expect(out.contains(r'$1'), isFalse);
    });
  });
}
