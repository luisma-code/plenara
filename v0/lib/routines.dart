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

  final title = req('title');
  if (title.length > 60) throw RoutineInvalid('title is too long');
  final kind = req('kind');
  if (!_kinds.contains(kind)) throw RoutineInvalid("kind must be one of ${_kinds.join('/')}");
  final rawSteps = json['steps'];
  if (rawSteps is! List || rawSteps.isEmpty) throw RoutineInvalid('no steps');
  if (rawSteps.length > _maxSteps) throw RoutineInvalid('more than $_maxSteps steps');

  final steps = <AuthoredStep>[];
  var order = 0;
  for (final raw in rawSteps) {
    if (raw is! Map) throw RoutineInvalid('a step was not an object');
    final s = raw.cast<String, dynamic>();
    final key = s['exerciseKey'] as String?;
    // A step may only name an exercise that EXISTS in the shipped catalogue. This is the rule that
    // makes "the model cannot invent an exercise" true rather than hoped for.
    final ex = (key == null || key.isEmpty) ? null : cat.byKey[key];
    if (key != null && key.isNotEmpty && ex == null) {
      throw RoutineInvalid("exerciseKey '$key' is not in the catalogue");
    }
    final name = (s['name'] as String?)?.trim();
    if (name == null || name.isEmpty) throw RoutineInvalid('a step has no name');
    // Instructions come from the CATALOGUE when an exercise is named, so the model cannot reword
    // safety-relevant guidance; a model-written instruction is only accepted for a step with no
    // catalogue exercise (a plain hold or a breather).
    final instruction = ex != null
        ? ex.instructions
        : ((s['instruction'] as String?)?.trim() ?? '');
    // Every step must stand alone FOR THE EAR — screen-off runs are first class and the figure is
    // never the sole carrier of the movement (Spec 16). A step we cannot speak is invalid.
    if (instruction.length < 15) {
      throw RoutineInvalid("step '$name' has no usable spoken instruction");
    }
    final side = (s['side'] as String?) ?? 'both';
    if (!_sides.contains(side)) throw RoutineInvalid("side must be one of ${_sides.join('/')}");
    final dur = (s['durationSeconds'] as num?)?.toInt();
    final reps = (s['reps'] as num?)?.toInt();
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

  final est = (json['estMinutes'] as num?) ?? _estimateMinutes(steps);
  return AuthoredRoutine(
    title: title,
    focusArea: (json['focusArea'] as String?)?.trim() ?? '',
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
/// "low back" and "shoulders" are ordinary wellness asks and must pass untouched; "my herniated
/// disc" is a request for treatment and must not be answered with one.
///
/// Returns true when the request is asking for help with an injury or medical condition. The
/// caller offers a general-wellness routine instead AND strips the condition from the prompt, so
/// the medical detail never leaves the device (Spec 08 §5.1).
final _injuryRe = RegExp(
    r'\b('
    r'herniat\w*|bulging disc|slipped disc|sciatica|pinched nerve|'
    r'torn|tear|rupture[ds]?|sprain\w*|strain\w*|fracture[ds]?|broken \w+|'
    r'surgery|post[- ]?op|operation|physio(?:therapy)?|rehab\w*|'
    r'arthritis|tendonitis|tendinitis|bursitis|impingement|scoliosis|stenosis|'
    r'frozen shoulder|plantar fasciitis|acl|mcl|meniscus|rotator cuff|'
    r'pregnan\w*|concussion|'
    r'(?:my|this|the)\s+\w*\s*(?:pain|injur\w*|hurts?|aching|agony)|'
    r'(?:in|with|from)\s+pain|painful|injured|injury'
    r')\b',
    caseSensitive: false);

bool looksLikeInjuryRequest(String utterance) => _injuryRe.hasMatch(utterance);

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
