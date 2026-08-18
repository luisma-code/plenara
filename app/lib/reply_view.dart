// The reply register (Fable's list redesign): how the current exchange is SET
// over the void. Pure presentation — no state, no session, no timers — so the
// three registers (caption / list / prose) can be reasoned about and tested on
// their own, apart from the turn machinery that decides what text to show.
import 'package:flutter/material.dart';

import 'plena.dart';

/// The ink every void surface writes in — the reply column and the input box.
const Color voidInk = Color(0xFFEAE2D8);

// Heavy shadow under all void text — insurance against a stray mote drifting beneath the column.
const List<Shadow> voidShadows = [
  Shadow(blurRadius: 22, color: Colors.black),
  Shadow(blurRadius: 8, color: Colors.black),
];
const TextStyle captionStyle = TextStyle(
  color: voidInk,
  fontSize: 24,
  height: 1.5,
  fontWeight: FontWeight.w300,
  shadows: voidShadows,
);

/// The current exchange, in one of three registers (Fable's list redesign):
/// - **caption** (short reply): centered in the lower third — already reads well.
/// - **list / prose** ([list] true — Plena has eased to the upper-right): a left-hand reading
///   column over the same void. Lists get "mote" marks in Plena's hue + hanging indent; prose is
///   set as paragraphs. No opaque box — the Scaffold is the one ground.
Widget voidText(
  String text, {
  required bool list,
  required PresenceTuning tuning,
  double bottomInset = 0,
}) {
  if (!list) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: const Alignment(0, 0.5),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Text(text, textAlign: TextAlign.center, style: captionStyle),
        ),
      ),
    );
  }
  return Padding(
    padding: EdgeInsets.fromLTRB(64, 104, 64, 120 + bottomInset),
    child: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(child: replyBody(text, tuning)),
      ),
    ),
  );
}

// Bullet lines: "•", "-", "–", or "1." / "1)" leaders (the engine emits "  • item").
final RegExp _bulletRe = RegExp(r'^\s*([•\-–]|\d+[.)])\s+');

/// Compose the yielded reply body: prose as paragraphs, lists as lead-in + mote-marked items.
Widget replyBody(String text, PresenceTuning tuning) {
  final lines = text.split('\n');
  final hasList = lines.any(_bulletRe.hasMatch);
  if (!hasList) {
    final paras = text
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in paras)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              p,
              style: const TextStyle(
                color: voidInk,
                fontSize: 20,
                height: 1.55,
                fontWeight: FontWeight.w300,
                shadows: voidShadows,
              ),
            ),
          ),
      ],
    );
  }
  // Parse into a lead-in (non-bullet text before the first item), the items, and a footer
  // (non-bullet text AFTER the items — e.g. help's "And 'undo that' reverses the last thing").
  // Only INDENTED non-bullet lines fold into the previous item as wrapped continuations; a
  // flush-left trailing line is a footer, not part of the last bullet (Fable review #8).
  final leadIn = <String>[];
  final items = <String>[];
  final footer = <String>[];
  var seenItem = false;
  for (final l in lines) {
    final m = _bulletRe.firstMatch(l);
    if (m != null) {
      seenItem = true;
      items.add(l.substring(m.end).trim());
    } else if (l.trim().isEmpty) {
      continue;
    } else if (!seenItem) {
      leadIn.add(l.trim());
    } else if (RegExp(r'^\s').hasMatch(l) && items.isNotEmpty) {
      items[items.length - 1] +=
          ' ${l.trim()}'; // an indented continuation of the last bullet
    } else {
      footer.add(
        l.trim(),
      ); // a flush-left line after the bullets → a footer paragraph
    }
  }
  final marker = HSLColor.fromAHSL(
    1,
    tuning.hue % 360,
    tuning.sat.clamp(0.0, 1.0),
    .56,
  ).toColor();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (leadIn.isNotEmpty) ...[
        Text(
          leadIn.join(' '),
          style: const TextStyle(
            color: Color(0x9EEAE2D8),
            fontSize: 15,
            letterSpacing: 0.3,
            fontWeight: FontWeight.w400,
            shadows: voidShadows,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 18),
          child: Container(
            width: 24,
            height: 1,
            color: marker.withValues(alpha: 0.25),
          ),
        ),
      ],
      for (var i = 0; i < items.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 3.5,
                      height: 3.5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: marker.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  items[i],
                  style: const TextStyle(
                    color: voidInk,
                    fontSize: 19,
                    height: 1.38,
                    fontWeight: FontWeight.w300,
                    shadows: voidShadows,
                  ),
                ),
              ),
            ],
          ),
        ),
      if (footer.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            footer.join(' '),
            style: const TextStyle(
              color: Color(0xC8EAE2D8),
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w300,
              shadows: voidShadows,
            ),
          ),
        ),
    ],
  );
}
