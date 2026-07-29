/// Plenara v0 — Routines (Spec 16): the exercise catalogue, the deterministic shortlist that
/// grounds routine authoring, the validator that gates what the cloud returns, and the Layer-1
/// safety rule.
///
/// The shape of this feature follows from one empirical finding (the 2026-07-28 figure spike): a
/// model CAN author safe, tweenable SVG stick figures, but lying-down poses are unreadable and
/// neither explicit projection geometry nor a render-and-critique vision loop fixes them. So the
/// model does NOT draw. It SELECTS from a shipped, illustrated catalogue — which makes figure
/// quality a property of the data rather than a per-generation gamble, keeps replay offline
/// forever, and keeps "capabilities are data" literally true (principle 4).
///
/// The division of labour is the project's "code over AI" principle applied directly:
///   * CODE narrows 640 exercises to a scored shortlist (deterministic, free, offline);
///   * the MODEL sequences and phrases a routine from that shortlist (the part code can't do);
///   * CODE validates every field of what comes back against the catalogue and the schema.
/// A model can therefore never invent an exercise, an image, or a step the app cannot speak.
library;

import 'dart:convert';
import 'dart:io';

/// One catalogue exercise. [image] is null for ~2/3 of the catalogue — those steps render
/// text-only, which is a first-class path, not a failure (Luis's explicit call).
class Exercise {
  final String key, name, category, instructions;
  final List<String> muscles, equipment;
  final String? image, imageAuthor;
  const Exercise({
    required this.key,
    required this.name,
    required this.category,
    required this.instructions,
    required this.muscles,
    required this.equipment,
    this.image,
    this.imageAuthor,
  });

  static Exercise fromJson(Map<String, dynamic> j) => Exercise(
        key: j['key'] as String,
        name: j['name'] as String,
        category: (j['category'] as String?) ?? '',
        instructions: (j['instructions'] as String?) ?? '',
        muscles: ((j['muscles'] as List?) ?? const []).map((e) => '$e').toList(),
        equipment: ((j['equipment'] as List?) ?? const []).map((e) => '$e').toList(),
        image: j['image'] as String?,
        imageAuthor: j['imageAuthor'] as String?,
      );
}

/// The shipped exercise catalogue (wger/Everkinetic, CC BY-SA 4.0).
class ExerciseCatalogue {
  final List<Exercise> all;
  final Map<String, Exercise> byKey;
  final String attribution;
  ExerciseCatalogue(this.all, this.attribution)
      : byKey = {for (final e in all) e.key: e};

  static ExerciseCatalogue empty() => ExerciseCatalogue(const [], '');

  /// Load from the data dir. A missing or corrupt catalogue yields an EMPTY one rather than
  /// throwing: routine authoring then declines honestly, and nothing else in the app is affected
  /// (same posture as a missing reference dataset, Spec 13).
  static ExerciseCatalogue load(String dataDir) {
    final f = File('$dataDir/reference/exercises.json');
    if (!f.existsSync()) return empty();
    try {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final entries = (j['entries'] as List).cast<Map<String, dynamic>>();
      return ExerciseCatalogue(
        [for (final e in entries) Exercise.fromJson(e)],
        (j['attribution'] as String?) ?? '',
      );
    } catch (_) {
      return empty();
    }
  }

  bool get isEmpty => all.isEmpty;

  /// Words that mark an exercise as stretch/mobility work rather than loaded strength work.
  static const _stretchy = ['stretch', 'pose', 'mobility', 'yoga', 'foam roller', 'rotation', 'twist'];

  static bool _isStretch(Exercise e) {
    final n = e.name.toLowerCase();
    return _stretchy.any(n.contains);
  }

  /// A deterministic, offline shortlist for [focus] — this is the "code over AI" half. Scoring is
  /// blunt on purpose: a name hit beats a muscle hit beats a category hit, an illustrated entry
  /// outranks an unillustrated one at equal relevance (so routines get pictures where possible),
  /// and ties break alphabetically so the same request yields the same shortlist every time.
  List<Exercise> candidates(String focus, {String kind = 'stretch', int limit = 60}) {
    final terms = focus
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((t) => t.length > 2)
        .toList();
    int score(Exercise e) {
      final name = e.name.toLowerCase();
      final muscles = e.muscles.join(' ').toLowerCase();
      final cat = e.category.toLowerCase();
      var s = 0;
      for (final t in terms) {
        if (name.contains(t)) s += 10;
        if (muscles.contains(t)) s += 6;
        if (cat.contains(t)) s += 3;
      }
      // Keep the shortlist in the right register: a "stretch routine" should not be shortlisted
      // with barbell work, and vice versa.
      final stretchy = _isStretch(e);
      if (kind == 'strength' && stretchy) s -= 6;
      if (kind != 'strength' && stretchy) s += 5;
      if (e.image != null) s += 2; // prefer illustrated, but never at the cost of relevance
      return s;
    }

    final scored = [for (final e in all) (e, score(e))]..removeWhere((p) => p.$2 <= 0);
    scored.sort((a, b) => a.$2 != b.$2 ? b.$2.compareTo(a.$2) : a.$1.name.compareTo(b.$1.name));
    // If the focus matched nothing at all, fall back to the register's illustrated entries so the
    // model still has something real to choose from rather than being handed an empty list.
    if (scored.isEmpty) {
      final fallback = all.where((e) => e.image != null && (_isStretch(e) == (kind != 'strength'))).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return fallback.take(limit).toList();
    }
    return [for (final p in scored.take(limit)) p.$1];
  }

  /// The shortlist rendered for the prompt — compact, and ONLY the fields the model needs to pick
  /// and sequence. Instructions are omitted: they are copied from the catalogue at validation
  /// time, never echoed back by the model (that keeps output tokens down AND makes it impossible
  /// for the model to quietly rewrite safety-relevant wording).
  static String promptCatalogue(List<Exercise> xs) => [
        for (final e in xs)
          '${e.key} | ${e.name} | ${e.category}'
              '${e.muscles.isEmpty ? '' : ' | ${e.muscles.join(", ")}'}'
              '${e.equipment.isEmpty ? '' : ' | needs: ${e.equipment.join(", ")}'}'
      ].join('\n');
}

/// A validated routine, ready to write as records.
class AuthoredRoutine {
  final String title, focusArea, kind, safetyNote;
  final num estMinutes;
  final List<AuthoredStep> steps;
  const AuthoredRoutine({
    required this.title,
    required this.focusArea,
    required this.kind,
    required this.safetyNote,
    required this.estMinutes,
    required this.steps,
  });
}

class AuthoredStep {
  final int order;
  final String name, instruction, side;
  final String? exerciseKey;
  final int? durationSeconds, reps;
  const AuthoredStep({
    required this.order,
    required this.name,
    required this.instruction,
    required this.side,
    this.exerciseKey,
    this.durationSeconds,
    this.reps,
  });
}

/// Thrown by [validateRoutine]. The message is fed back to the model for ONE re-author attempt
/// (the same gated retry authoring already uses), and shown to no one.
class RoutineInvalid implements Exception {
  final String message;
  RoutineInvalid(this.message);
  @override
  String toString() => message;
}

/// Strip control characters and collapse whitespace. Model output reaches the TTS engine and the
/// synced record store; a newline or control char in a "title" is at best ugly and at worst a way
/// to smuggle structure into something rendered or spoken.
String _clean(String? v) =>
    (v ?? '').replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

String _clip(String v, int max) => v.length <= max ? v : v.substring(0, max).trim();

/// Tolerant int coercion. The model returns JSON; a number arriving as a string is sloppy, not
/// hostile, and should feed the retry as a validation error rather than crash out of it.
int? _asInt(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return num.tryParse('$v'.trim())?.toInt();
}

const _kinds = {'stretch', 'strength', 'mobility'};
const _sides = {'both', 'left', 'right', 'alternating'};
const _maxSteps = 12;

/// Deterministically validate what the cloud returned. Everything the user will ever see or hear
/// is checked here, because after this point the routine is ordinary data replayed forever.
AuthoredRoutine validateRoutine(Map<String, dynamic> json, ExerciseCatalogue cat) {
  String req(String k) {
    final v = json[k];
    if (v is! String || v.trim().isEmpty) throw RoutineInvalid("missing '$k'");
    return v.trim();
  }

  final title = _clean(req('title'));
  if (title.isEmpty) throw RoutineInvalid("missing 'title'");
  if (title.length > 60) throw RoutineInvalid('title is too long');
  final kind = _clean(req('kind')).toLowerCase();
  if (!_kinds.contains(kind)) throw RoutineInvalid("kind must be one of ${_kinds.join('/')}");
  final rawSteps = json['steps'];
  if (rawSteps is! List || rawSteps.isEmpty) throw RoutineInvalid('no steps');
  if (rawSteps.length > _maxSteps) throw RoutineInvalid('more than $_maxSteps steps');

  final steps = <AuthoredStep>[];
  var order = 0;
  for (final raw in rawSteps) {
    if (raw is! Map) throw RoutineInvalid('a step was not an object');
    final s = raw.cast<String, dynamic>();
    final key = s['exerciseKey'] == null ? null : '${s['exerciseKey']}';
    // A step may only name an exercise that EXISTS in the shipped catalogue. This is the rule that
    // makes "the model cannot invent an exercise" true rather than hoped for.
    final ex = (key == null || key.isEmpty) ? null : cat.byKey[key];
    if (key != null && key.isNotEmpty && ex == null) {
      throw RoutineInvalid("exerciseKey '$key' is not in the catalogue");
    }
    final name = _clean(s['name'] == null ? null : '${s['name']}');
    if (name.isEmpty) throw RoutineInvalid('a step has no name');
    // BOUND every model-supplied free-text field that the app will SPEAK or store forever. The
    // step name is read aloud verbatim by announce(); an unbounded field there is a channel for
    // whatever a steered model wants to put in the user's ear.
    if (name.length > 60) throw RoutineInvalid("step name is too long");
    // Instructions come from the CATALOGUE when an exercise is named, so the model cannot reword
    // safety-relevant guidance; a model-written instruction is only accepted for a step with no
    // catalogue exercise (a plain hold or a breather).
    final instruction = ex != null
        ? ex.instructions // from the CATALOGUE — the model cannot reword a real movement
        : _clean(s['instruction'] == null ? null : '${s['instruction']}');
    if (ex == null && instruction.length > 500) {
      throw RoutineInvalid("step '$name' has an over-long instruction");
    }
    // Every step must stand alone FOR THE EAR — screen-off runs are first class and the figure is
    // never the sole carrier of the movement (Spec 16). A step we cannot speak is invalid.
    if (instruction.length < 15) {
      throw RoutineInvalid("step '$name' has no usable spoken instruction");
    }
    final side = s['side'] == null ? 'both' : '${s['side']}';
    if (!_sides.contains(side)) throw RoutineInvalid("side must be one of ${_sides.join('/')}");
    final dur = _asInt(s['durationSeconds']);
    final reps = _asInt(s['reps']);
    if (dur == null && reps == null) {
      throw RoutineInvalid("step '$name' needs durationSeconds or reps");
    }
    if (dur != null && (dur < 5 || dur > 600)) throw RoutineInvalid('durationSeconds out of range');
    if (reps != null && (reps < 1 || reps > 100)) throw RoutineInvalid('reps out of range');
    steps.add(AuthoredStep(
      order: ++order,
      name: name,
      instruction: instruction,
      side: side,
      exerciseKey: ex?.key,
      durationSeconds: dur,
      reps: reps,
    ));
  }

  // A raw cast here threw TypeError on a type-confused field ("10" instead of 10), which escaped
  // the RoutineInvalid catch and so BYPASSED the gated retry that exists precisely for malformed
  // model output. Coerce, then range-check: an unbounded value is spoken ("about 1000000000
  // minutes") and rendered in the routine list.
  final estRaw = json['estMinutes'];
  var est = estRaw is num ? estRaw : num.tryParse('${estRaw ?? ''}');
  if (est == null || est <= 0 || est > 180) est = _estimateMinutes(steps);
  return AuthoredRoutine(
    title: title,
    focusArea: _clip(_clean(json['focusArea'] == null ? null : '${json['focusArea']}'), 80),
    kind: kind,
    // The standing disclaimer is OURS, not the model's — a safety line the model could reword is
    // not a safety line. Any note it returns is additive colour, never a replacement.
    safetyNote: standingSafetyNote,
    estMinutes: est,
    steps: steps,
  );
}

/// Shown at the top of every routine and spoken once on a routine's first run. Deliberately fixed
/// in code: a disclaimer the authoring model can rewrite is not a disclaimer.
const standingSafetyNote =
    'Best-effort guidance, not medical advice — check with a physio or trainer, '
    'and stop if anything hurts.';

num _estimateMinutes(List<AuthoredStep> steps) {
  var secs = 0;
  for (final s in steps) {
    secs += s.durationSeconds ?? (s.reps! * 4); // ~4s per rep is close enough for a "≈10 min"
    secs += 15; // transition between steps
  }
  return (secs / 60).ceil();
}

/// LAYER 1 (deterministic, pre-spend): injury / medical framing. Keyed on FRAMING, not topic —
/// "low back", "shoulders" and "stability" are ordinary wellness asks and must pass untouched;
/// "my herniated disc" is a request for treatment and must not be answered with one.
///
/// This gate REFUSES; it does not sanitise. When it fires nothing is sent to the cloud at all.
/// When it MISSES, the utterance goes out verbatim — so the privacy property of this feature is
/// literally the recall of this pattern. That is why the lexicon is deliberately broad: a false
/// positive costs one redirect the user can rephrase past, a false negative ships someone's
/// medical detail to a third party.
///
/// PREVENTION IS NOT INJURY. "a warm-up for injury prevention" is the canonical reason people ask
/// for a warm-up, so the prevention framing is excluded before anything else is considered.
/// Framings that LOOK medical to the lexicon but are ordinary wellness asks. "wear and tear" is
/// how people describe getting older, not a torn anything.
final _benignRe = RegExp(
    r'\b(?:prevent\w*|avoid\w*|prehab|reduce the risk|stay injury[- ]free|keep from'
    r'|wear and tear|general maintenance)\b',
    caseSensitive: false);

final _injuryRe = RegExp(
    r'\b('
    // named conditions — matched as STEMS, because inflections vary ("hernia"/"herniated",
    // "arthritis"/"osteoarthritis", "tendonitis"/"tendinopathy").
    r'herni\w*|bulging disc|slipp?ed (?:a )?disc|sciatica|pinched nerve|nerve pain|'
    r'\w*arthriti\w*|tendo?[ni]\w*|bursitis|impingement|scoliosis|stenosis|fasciitis|'
    r'frozen shoulder|tennis elbow|golfer.s elbow|carpal tunnel|shin splints|whiplash|'
    r'acl|mcl|pcl|meniscus|rotator cuff|labrum|hamstring pull|'
    // events and states
    r'torn|tear(?:s|ing)?|rupture[ds]?|sprain\w*|strain\w*|fracture[ds]?|broken \w+|'
    r'disloca\w*|pulled (?:a |my )?\w+|tweaked (?:a |my )?\w+|'
    r'surgery|surgical|post[- ]?op|operation|replacement|physio(?:therapy)?|physical therapy|'
    r'rehab\w*|recovering from|recovery from|accident|'
    r'pregnan\w*|postpartum|post[- ]?natal|concussion|'
    // symptom framing — how people actually describe it
    r'numb\w*|tingl\w*|pins and needles|inflam\w*|swollen|swelling|stiff\w*|'
    r'sore\w*|ach(?:e|es|ing|y)|dodgy \w+|bad (?:back|knee|shoulder|hip|neck|ankle|wrist)|'
    r'(?:my|this|the)\s+\w*\s*(?:pain|injur\w*|hurts?|aching|agony)|'
    r'(?:in|with|from)\s+pain|painful|injur\w*|it hurts|killing me|'
    r'flare[- ]?up|chronic'
    r')\b',
    caseSensitive: false);

/// True when the request is asking for help with an injury or medical condition, rather than
/// ordinary wellness work. See the note above: this is a refuse-gate, not a sanitiser.
bool looksLikeInjuryRequest(String utterance) {
  if (_benignRe.hasMatch(utterance)) return false; // "warm-up for injury prevention" is fine
  return _injuryRe.hasMatch(utterance);
}

/// ---------------------------------------------------------------------------------------------
/// The routine PLAYER's state (Spec 16). Deliberately NOT a skill: the closed DSL vocabulary has
/// no timer and no suspended interactive state, and Spec 02 §8.4 names "that would require a
/// timer" as its canonical honest refusal. So the player is a conversational MODE in the Session —
/// the direct sibling of the shipped Tour — and the interpreter's opcode set stays untouched.
///
/// This class holds only state and step arithmetic (pure, testable). The Session owns the turn
/// interception, the spoken cues, and the completion write.
class RoutineRun {
  final String routineId, title;
  final List<Map<String, dynamic>> steps; // routine_step records, already ordered
  final DateTime startedAt;
  int index = 0;
  bool paused = false;
  final Set<String> skipped = {};
  final Set<String> completed = {};

  RoutineRun({
    required this.routineId,
    required this.title,
    required this.steps,
    required this.startedAt,
  });

  bool get isDone => index >= steps.length;
  Map<String, dynamic>? get current => isDone ? null : steps[index];
  int get position => index + 1;
  int get total => steps.length;

  /// Seconds this step should hold, or null for a rep-based step (which waits for the user).
  int? get currentSeconds => (current?['durationSeconds'] as num?)?.toInt();
  int? get currentReps => (current?['reps'] as num?)?.toInt();

  /// The catalogue key of the current step, if it has one — drives which illustration to show.
  String? get currentExerciseKey => current?['exerciseKey'] as String?;

  void markDone() {
    final c = current;
    if (c != null) completed.add(c['id'] as String);
    index++;
  }

  void markSkipped() {
    final c = current;
    if (c != null) skipped.add(c['id'] as String);
    index++;
  }

  /// Step back one. Un-records the step being returned to, so finishing after a "back" doesn't
  /// double-count it — the session log has to match what actually happened.
  bool back() {
    if (index == 0) return false;
    index--;
    final c = current;
    if (c != null) {
      completed.remove(c['id']);
      skipped.remove(c['id']);
    }
    return true;
  }

  /// What Plena says when a step begins. Ear-first: the name, the instruction, then the ask.
  String announce() {
    final c = current;
    if (c == null) return '';
    final n = '${c['name']}';
    final instr = spokenInstruction('${c['instruction'] ?? ''}');
    final side = '${c['side'] ?? 'both'}';
    final sideNote = side == 'left' || side == 'right' ? ' On your $side side.' : '';
    final secs = currentSeconds, reps = currentReps;
    final ask = secs != null
        ? ' Hold for ${_spokenDuration(secs)}.'
        : ' ${reps ?? ''} reps — say "next" when you\'re through.';
    return 'Step $position of $total — $n. $instr$sideNote$ask';
  }
}

String _spokenDuration(int seconds) {
  if (seconds < 60) return '$seconds seconds';
  final m = seconds ~/ 60, s = seconds % 60;
  if (s == 0) return m == 1 ? 'a minute' : '$m minutes';
  return '$m minute${m == 1 ? '' : 's'} $s seconds';
}

/// Trim a catalogue instruction down to something you'd actually want SAID to you mid-stretch.
///
/// The catalogue's wording is written to be read on a page: multi-sentence, often with
/// "Starting position:" / "Steps:" / "Tips:" scaffolding, and sometimes a paragraph about leaving
/// the pose. Spoken in full, that is a wall of text while you're on the floor waiting to move. The
/// full text stays on the record (the card shows all of it) — only the SPOKEN line is trimmed.
String spokenInstruction(String raw, {int maxChars = 220}) {
  var t = raw.trim();
  if (t.isEmpty) return t;
  // Drop the trailing "Tips: …" tail — useful to read, noise to hear.
  final tip = RegExp(r'\b(?:Tips?|Note|Variation|Caution)\s*:', caseSensitive: false).firstMatch(t);
  if (tip != null && tip.start > 40) t = t.substring(0, tip.start).trim();
  // Drop section labels that only make sense in print.
  t = t.replaceAll(RegExp(r'\b(?:Starting position|Steps|Execution|Preparation)\s*:\s*',
      caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= maxChars) return t;
  // Cut at the last sentence end inside the budget, so we never stop mid-instruction.
  final cut = t.substring(0, maxChars);
  final lastStop = cut.lastIndexOf(RegExp(r'[.!?]'));
  return (lastStop > 60 ? cut.substring(0, lastStop + 1) : '${cut.trimRight()}…').trim();
}

/// ---------------------------------------------------------------------------------------------
/// FIGURE FALLBACK (Spec 16 §2, amended). ~2 in 3 catalogue exercises have no illustration. The
/// 2026-07-28 spike showed a model can author stick figures that are safe (19/19 passed a strict
/// render-only subset) and tweenable (18/19 keyframe pairs structurally corresponding) — its
/// weakness was only that supine poses read worse than the catalogue's professional line art.
/// Against a *drawn* figure they lose; against NOTHING, which is what these steps get today, they
/// win. So they are a fallback tier, never a replacement:
///
///     catalogue illustration  >  generated figure  >  text only
///
/// SECURITY POSTURE: SVG is a format that can carry script, external references and CSS. Nothing
/// here trusts the model. The sanitiser is an ALLOWLIST — unknown element, unknown attribute, or
/// any banned construct anywhere in the string rejects the whole figure — and stroke colour and
/// width are imposed by the renderer, never authored, so every figure looks like one product.
/// A rejected figure degrades to text, exactly like a missing one.

/// Elements a figure may contain. Anything else — including `<style>`, `<image>`, `<use>`,
/// `<foreignObject>`, `<script>`, `<animate>` — rejects the figure.
const _svgElements = {'svg', 'g', 'path', 'line', 'polyline', 'circle', 'ellipse'};

/// Attributes a figure may carry. Geometry and nothing else. No `style`, no `class`, no `id`,
/// no presentation attributes that could pull in a resource.
const _svgAttrs = {
  'viewBox', 'xmlns', 'd', 'points', 'x1', 'y1', 'x2', 'y2',
  'cx', 'cy', 'r', 'rx', 'ry', 'transform', 'fill', 'stroke-linecap',
};

/// Constructs that reject a figure outright, wherever they appear. Belt to the allowlist's braces:
/// a parser quirk that hid one of these from element/attribute walking still can't get it through.
final _svgBanned = RegExp(
    r'<\s*(?:script|style|image|use|foreignObject|animate|animateTransform|set|handler)\b'
    r'|xlink:href|\bhref\s*=|\son[a-z]+\s*='
    r'|url\(|data:|javascript:|expression\(|@import|&#|<!ENTITY|<!DOCTYPE',
    caseSensitive: false);

const maxFigureBytes = 8000;

/// Returns the figure unchanged if it is safe to render, or null if anything at all is off.
/// Deliberately all-or-nothing: a partially-scrubbed drawing is not worth the reasoning burden.
String? sanitizeFigure(String? svg) {
  final s = (svg ?? '').trim();
  if (s.isEmpty || s.length > maxFigureBytes) return null;
  if (!s.startsWith('<svg') || !s.contains('</svg>')) return null;
  if (_svgBanned.hasMatch(s)) return null;
  // Element + attribute allowlist, checked by walking the actual markup rather than by regex.
  for (final m in RegExp(r'<\s*([a-zA-Z][\w:-]*)([^>]*)>').allMatches(s)) {
    final tag = m.group(1)!;
    if (!_svgElements.contains(tag)) return null;
    for (final a in RegExp(r'([a-zA-Z][\w:-]*)\s*=').allMatches(m.group(2) ?? '')) {
      if (!_svgAttrs.contains(a.group(1))) return null;
    }
  }
  // A viewBox is required: without it the renderer cannot scale the figure predictably.
  if (!RegExp(r'viewBox\s*=\s*"[-\d.\s]+"').hasMatch(s)) return null;
  return s;
}

/// True when [a] and [b] can be TWEENED — same elements in the same order with the same path
/// command letters and point counts, differing only in coordinates. When this holds the renderer
/// interpolates and the figure genuinely moves; when it doesn't, it falls back to a two-frame
/// toggle, which still reads as movement.
bool figuresCorrespond(String a, String b) {
  List<String> sig(String s) => [
        for (final m in RegExp(r'<\s*([a-zA-Z][\w:-]*)([^>]*)>').allMatches(s))
          if (m.group(1) == 'path')
            'path:${RegExp(r'[A-Za-z]').allMatches(RegExp(r'd\s*=\s*"([^"]*)"').firstMatch(m.group(2) ?? '')?.group(1) ?? '').map((x) => x.group(0)).join()}'
          else if (m.group(1) == 'polyline')
            'polyline:${RegExp(r'[-\d.]+').allMatches(RegExp(r'points\s*=\s*"([^"]*)"').firstMatch(m.group(2) ?? '')?.group(1) ?? '').length}'
          else
            m.group(1)!,
      ];
  final sa = sig(a), sb = sig(b);
  if (sa.isEmpty || sa.length != sb.length) return false;
  for (var i = 0; i < sa.length; i++) {
    if (sa[i] != sb[i]) return false;
  }
  return true;
}

/// One validated figure for a step: two frames, and whether they can be interpolated.
class StepFigure {
  final String frameA, frameB;
  final bool tweenable;
  const StepFigure(this.frameA, this.frameB, this.tweenable);
}

/// Validate a model-authored figure pair. Null when either frame fails the subset — presentation
/// degrades, it never rejects the step.
StepFigure? validateFigure(Object? raw) {
  if (raw is! Map) return null;
  final a = sanitizeFigure(raw['frameA'] as String?);
  if (a == null) return null;
  final b = sanitizeFigure(raw['frameB'] as String?) ?? a; // a single-frame figure is fine
  return StepFigure(a, b, figuresCorrespond(a, b));
}
