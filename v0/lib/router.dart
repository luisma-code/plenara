/// Plenara v0 — the corpus fast-path router (Spec 03 §5 + §6). Data-driven:
/// `data/corpus.json` holds slot-abstracted templates -> (skillId, typed slot
/// recipes). A template match extracts slots deterministically (dates via the
/// resolver, §6.2). This is the PRIMARY router (findings §13); retrieval is the
/// cold-start fallback added next. Corpus entries are DATA, so the "gets better"
/// loop (§5.2) just appends entries — no code change.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'embed.dart';

class CorpusEntry {
  final String skillId;
  final String template;
  final RegExp regex; // named groups per slot
  final Map<String, String> slotTypes; // slotName -> text|date|entity|quantity
  // Constant slots the template asserts regardless of the surface text — e.g. "had dinner with
  // {personName}" carries `{"kind": "dinner"}` so an OFFLINE interaction records its kind, not a
  // generic "talked to". Merged into the extracted slots at match time (never overwrites a
  // regex-captured slot). Empty for the vast majority of entries.
  final Map<String, dynamic> fixedSlots;
  // A generative-recognition target (Spec 03 §2.2a, `G-46`): when set, this entry routes to a
  // generative kind (gift_ideas, …) rather than a skill — mutually exclusive with a real [skillId]
  // (which is '' for a generative entry). Its one slot is the {contact:entity} param.
  final String? generativeKind;
  CorpusEntry(this.skillId, this.template, this.regex, this.slotTypes,
      {this.fixedSlots = const {}, this.generativeKind});
}

class Router {
  final List<CorpusEntry> corpus;
  final DateTime now;
  final Set<String> _learnedTemplates = {}; // templates added by learn() / loaded as learned
  Router(this.corpus, this.now);

  static Router load(String path, DateTime now, {String? learnedPath}) {
    final entries = <CorpusEntry>[];
    for (final e in jsonDecode(File(path).readAsStringSync()) as List) {
      entries.add(_compile(e as Map<String, dynamic>));
    }
    final learned = <String>{};
    if (learnedPath != null && File(learnedPath).existsSync()) {
      for (final e in jsonDecode(File(learnedPath).readAsStringSync()) as List) {
        final m = e as Map<String, dynamic>;
        entries.insert(0, _compile(m)); // learned tried first
        learned.add(m['template'] as String);
      }
    }
    return Router(entries, now).._learnedTemplates.addAll(learned);
  }

  bool isLearned(String template) => _learnedTemplates.contains(template);

  /// Forget a learned template (§5.2 NEGATIVE half): when a learned entry
  /// misroutes and the user corrects it, drop it so it can't misroute again.
  /// Only removes LEARNED templates — a seed template is never forgotten this way.
  bool forget(String template) {
    if (!_learnedTemplates.contains(template)) return false;
    corpus.removeWhere((c) => c.template == template);
    _learnedTemplates.remove(template);
    return true;
  }

  /// Learn a phrasing (§5.2 write path): abstract the extracted slot values back
  /// into typed placeholders and add a corpus template, so the next similar
  /// phrasing hits the fast path with no cloud call. Returns the template (for
  /// persistence) or null if nothing could be abstracted. Exact/near-exact
  /// learning; soft generalization (R9b) is deferred (findings §13).
  String? learn(String utterance, String skillId, Map<String, dynamic> slots, {Set<String> contacts = const {}}) {
    var t = utterance.trim();
    final nonNull = slots.entries.where((e) => e.value != null).toList();
    var abstracted = 0;
    for (final e in nonNull) {
      final vs = e.value.toString();
      final idx = t.toLowerCase().indexOf(vs.toLowerCase());
      if (idx >= 0) {
        // A slot value that IS a known contact abstracts to `:contact`, never `:text` — otherwise
        // a learned "what is {who:text} {q:text}" would defeat the :contact guard and hijack all
        // "what is X …" world-knowledge (Fable review, critical). Preserves the guard across learns.
        final type = contacts.contains(vs.toLowerCase()) ? 'contact' : _inferType(vs);
        t = '${t.substring(0, idx)}{${e.key}:$type}${t.substring(idx + vs.length)}';
        abstracted++;
      }
    }
    // Only learn a SAFE template (Fable review):
    //  1. EVERY non-null slot must abstract. Otherwise the template is lossy (a
    //     dropped slot — e.g. a cloud-resolved date not present in the surface)
    //     AND it persists a private slot *value* verbatim into the synced corpus
    //     (violates "store slot shapes, not values").
    //  2. At least one literal word must survive. Otherwise "call mom" ->
    //     "{description:text}" compiles to `^(.+?)$` which matches EVERY utterance
    //     and — inserted first + persisted — permanently hijacks all routing.
    if (abstracted != nonNull.length) return null;
    if (!_hasStrongLiteral(t)) return null;
    if (corpus.any((c) => c.template == t)) return null; // dedupe: nothing new to persist
    corpus.insert(0, _compile({'skillId': skillId, 'template': t}));
    _learnedTemplates.add(t);
    return t;
  }

  /// Learn a GENERATIVE-recognition template (§5.2 write path, `G-46`): the target is a
  /// [generativeKind] and the one param [contact] is abstracted to `{contact:entity}`, so the next
  /// similar phrasing recognizes the request OFFLINE (no residual classification). Same safety guards
  /// as [learn]: the contact must be a literal substring (else a resolved/renamed name — don't learn),
  /// ≥1 strong literal word must survive, and no duplicate. Returns the template to persist, or null.
  /// Recognition-only — the generation itself is never cached (§2.2a). No-contact kinds never learn
  /// (no placeholder → a zero-slot template the guards reject).
  String? learnGenerative(String utterance, String generativeKind, String? contact,
      {DateTime? clock, Set<String> contacts = const {}}) {
    final vs = contact?.trim() ?? '';
    if (vs.isEmpty) return null;
    final asOf = clock ?? now;
    final t0 = utterance.trim();
    // Find the contact as a WHOLE word/phrase, never a mid-word substring — "Ann" must not hit inside
    // "anniversary" (which would corrupt the template AND persist the name verbatim, violating "store
    // shapes not values"). The name is model-supplied, so a non-token match is realistic.
    final boundary = RegExp('\\b${RegExp.escape(vs)}\\b', caseSensitive: false);
    final m = boundary.firstMatch(t0);
    if (m == null) return null;
    final t = '${t0.substring(0, m.start)}{contact:entity}${t0.substring(m.end)}';
    if (boundary.hasMatch(t)) return null; // a second occurrence would leak the name verbatim
    if (!_hasStrongLiteral(t)) return null;
    if (corpus.any((c) => c.template == t)) return null;
    // Round-trip like learnSuggested: compile, match THIS utterance, and re-extract the contact to the
    // same span — rejecting a template that doesn't cleanly reproduce the recognition.
    final CorpusEntry e;
    try {
      e = _compile({'generativeKind': generativeKind, 'template': t});
    } catch (_) {
      return null;
    }
    final got = _extract(e, t0, asOf, contacts);
    if (got == null || got['contact']?.toString().toLowerCase() != vs.toLowerCase()) return null;
    corpus.insert(0, e);
    _learnedTemplates.add(t);
    return t;
  }

  /// Add an ALREADY-ABSTRACTED corpus template (from an instantiated template's bundled
  /// corpus, Spec 05 §6). Marked learned so it persists + loads like a learned entry, but
  /// it's curated (shipped), so it routes the new tracker's phrasings immediately.
  void addLearned(String skillId, String template) {
    if (corpus.any((c) => c.template == template)) return; // already present
    corpus.insert(0, _compile({'skillId': skillId, 'template': template}));
    _learnedTemplates.add(template);
  }

  /// Re-insert a previously-forgotten learned entry (data-view forget→undo, G-49). Rebuilds from
  /// the raw persisted map so it works for BOTH a skillId and a generativeKind entry — unlike
  /// addLearned, which only knows skillId.
  void restore(Map<String, dynamic> raw) {
    final t = raw['template'] as String?;
    if (t == null || corpus.any((c) => c.template == t)) return;
    corpus.insert(0, _compile(raw));
    _learnedTemplates.add(t);
  }

  // A name/entity capture ({personName:entity}) must look like a name, not an article/pronoun —
  // otherwise "remember {who:entity} {fact}" swallows "remember the alamo" (who="the") and
  // "note that {who:entity} {fact}" swallows "note that the meeting is at five". Reject when the
  // FIRST token is one of these (names never start with them). Keeps capture broad for real names.
  static const _entityStop = {
    'the', 'a', 'an', 'my', 'your', 'his', 'her', 'their', 'our', 'its', 'this', 'that', 'these',
    'those', 'i', 'it', 'we', 'they', 'you', 'he', 'she', 'myself', 'yourself', 'himself', 'herself',
    'itself', 'ourselves', 'themselves', 'some', 'any', 'no', 'every', 'to', 'about', 'for'
  };
  static bool _entityOk(String? raw) {
    if (raw == null || raw.isEmpty) return false;
    final first = raw.toLowerCase().split(RegExp(r'\s+')).first;
    return first.isNotEmpty && !_entityStop.contains(first);
  }

  static String _inferType(String v) {
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return 'date';
    if (RegExp(r'^\d+(\.\d+)?$').hasMatch(v)) return 'quantity';
    return 'text';
  }

  /// Compile a template like "add {description:text} to my {_:text}" into a
  /// case-insensitive anchored regex with named capture groups.
  /// The bounded regex for a `dayword` slot — the day expressions [resolveDate]
  /// understands, longest-first so "next friday" wins over "friday".
  static const _daywordPat =
      r'(?:today|tomorrow|tonight|this\s+(?:morning|afternoon|evening)|'
      r'(?:next\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))';

  /// The bounded regex for a `posword` slot — a list position by ordinal word,
  /// ordinal/plain digit, or "last". Keeps "the FIRST task" positional while "the
  /// MILK task" falls through to a by-description match.
  static const _poswordPat =
      r'(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|last|\d+(?:st|nd|rd|th)?)';

  /// The bounded regex for a `pastday` slot — a BACKWARD-looking day expression
  /// ("yesterday", "today", "last friday") for recall/history queries. Distinct from
  /// `dayword` (which looks forward for scheduling).
  static const _pastdayPat =
      r'(?:yesterday|today|(?:last\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))';

  /// The bounded regex for a `predword` slot — a CLOSED set of relational predicates, so
  /// a bare "Sarah is allergic to peanuts" records a fact with the predicate preserved.
  /// Longest alternatives first so "is allergic to" wins over "is". Paired with a
  /// :contact personName so it only annotates KNOWN people (no world-knowledge over-match).
  static const _predwordPat = r'(?:is allergic to|is married to|is engaged to|is dating|'
      r'works at|works for|works as|lives in|grew up in|is from|is into|'
      r'likes|loves|enjoys|hates|dislikes|prefers|plays|studies|studied|teaches|drives|owns)';

  /// The bounded regex for a `mealword` slot — the named meals, so "eggs for
  /// {mealType}" captures breakfast/lunch/dinner/etc. without a free-text slot.
  static const _mealwordPat = r'(?:breakfast|lunch|dinner|supper|brunch|a\s+snack|snack|dessert)';

  /// The bounded regex for a `moodword` slot — a CLOSED set of feeling adjectives, so a
  /// bare "i'm {mood}" logs a mood without swallowing "i'm going to…" or "i'm 180 lbs".
  static const _moodwordPat = r'(?:exhausted|tired|sleepy|drained|wiped|beat|spent|fried|'
      r'happy|glad|good|great|amazing|wonderful|fantastic|ecstatic|joyful|cheerful|content|'
      r'sad|down|low|blue|gloomy|miserable|depressed|lonely|upset|hurt|'
      r'anxious|stressed|worried|nervous|overwhelmed|tense|restless|'
      r'angry|mad|frustrated|annoyed|irritated|grumpy|cranky|'
      r'calm|relaxed|peaceful|chill|content|'
      r'excited|energized|energised|pumped|motivated|hopeful|refreshed|'
      r'okay|ok|fine|alright|meh|blah|bored|unmotivated|sick|unwell|terrible|awful|rough)';

  static CorpusEntry _compile(Map<String, dynamic> e) {
    final tmpl = e['template'] as String;
    final slotTypes = <String, String>{};
    final sb = StringBuffer('^');
    var i = 0, gi = 0;
    final ph = RegExp(r'\{(\w+):(\w+)\}');
    for (final m in ph.allMatches(tmpl)) {
      sb.write(_lit(tmpl.substring(i, m.start)));
      final name = m.group(1)!, type = m.group(2)!;
      final group = name == '_' ? 'ignore${gi++}' : name;
      if (name != '_') slotTypes[name] = type;
      // A `dayword` slot is CONSTRAINED to actual day expressions ("tomorrow",
      // "next friday", ...) rather than `.+?`. That lets a day sit between two
      // free-text slots and still split correctly — the router validates one regex
      // match and does NOT backtrack across alternative splits (gaps #54/#11), so a
      // greedy `.+?` day would grab "mom tomorrow" and fail. A bounded pattern makes
      // the only viable split the correct one.
      sb.write(type == 'dayword'
          ? '(?<$group>$_daywordPat)'
          : type == 'posword'
              ? '(?<$group>$_poswordPat)'
              : type == 'pastday'
                  ? '(?<$group>$_pastdayPat)'
                  : type == 'moodword'
                      ? '(?<$group>$_moodwordPat)'
                      : type == 'mealword'
                          ? '(?<$group>$_mealwordPat)'
                          : type == 'predword'
                              ? '(?<$group>$_predwordPat)'
                              : '(?<$group>.+?)');
      i = m.end;
    }
    sb.write(_lit(tmpl.substring(i)));
    sb.write(r'[.?!]?$'); // strip a trailing . ? or ! so "what's Mia allergic to?" doesn't leak "?" into the slot
    final fixed = (e['slots'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return CorpusEntry(e['skillId'] as String? ?? '', tmpl,
        RegExp(sb.toString(), caseSensitive: false), slotTypes,
        fixedSlots: fixed, generativeKind: e['generativeKind'] as String?);
  }

  /// Turn literal template text into a regex fragment, preserving whitespace
  /// boundaries as `\s+` (trimming would fuse adjacent placeholders).
  static String _lit(String s) {
    if (s.isEmpty) return '';
    if (s.trim().isEmpty) return r'\s+'; // pure separator between two placeholders
    final lead = RegExp(r'^\s').hasMatch(s) ? r'\s+' : '';
    final trail = RegExp(r'\s$').hasMatch(s) ? r'\s+' : '';
    final core = s.trim().split(RegExp(r'\s+')).map(RegExp.escape).join(r'\s+');
    return '$lead$core$trail';
  }

  // A real sentence break: terminal punctuation followed by whitespace. Decimals ("72.5")
  // and titles glued to punctuation ("e.g.") lack the trailing space, so they don't split.
  static final _sentenceSplit = RegExp(r'[.!?]+\s+');
  // A "word" for substance-counting: a run of ≥2 letters. Skips "I"/"a" and stray initials,
  // so an abbreviation segment ("Dr", "St") counts as at most one word and is not substantial.
  static final _wordRe = RegExp(r'[A-Za-z]{2,}');
  // Mid-sentence abbreviations + single-letter initials whose period is NOT a sentence break.
  // We strip the period before splitting so "at St. Jude", "5 p.m.", "J. R." don't false-split.
  static final _abbrev = RegExp(
      r'\b(?:[a-z]|dr|mr|mrs|ms|st|jr|sr|vs|no|mi|ft|dept|approx|prof|gen|sgt|ave|blvd|a\.m|p\.m|e\.g|i\.e)\.',
      caseSensitive: false);

  /// True when [u] is two or more SUBSTANTIAL sentences (each ≥2 real words) — the compound
  /// signal: multiple statements the corpus can't split, so it belongs on the cloud multi-action
  /// path. Guards against decimals, a single trailing mark, and abbreviations/initials anywhere
  /// ("note that Sam works at St. Jude in Memphis" stays ONE command).
  static bool _isCompound(String u) {
    final cleaned = u.replaceAllMapped(_abbrev, (m) => m.group(0)!.replaceAll('.', ''));
    var substantial = 0;
    for (final seg in cleaned.split(_sentenceSplit)) {
      if (_wordRe.allMatches(seg).length >= 2) substantial++;
      if (substantial >= 2) return true;
    }
    return false;
  }

  /// Returns {skillId, slots} for a corpus hit, else null (=> retrieval/clarify).
  /// [clock] is the turn's frozen now for date resolution (Spec 03 §4); defaults
  /// to the router's construction time.
  /// [contacts] is the lowercase set of known contact names + aliases; a `:contact` slot only
  /// matches one of these, so a broad "what is {who:contact} {q:text}" template is safe — it
  /// can't shadow OOD world-knowledge ("what is the capital…") or template queries ("what's my
  /// reading streak"), because "the"/"my" aren't contacts.
  Map<String, dynamic>? route(String utterance, {DateTime? clock, Set<String> contacts = const {}}) {
    final u = utterance.trim();
    final asOf = clock ?? now;
    // A COMPOUND utterance — two or more complete sentences — is not a single command.
    // The corpus fast-path's greedy `text` slots would swallow the whole thing into ONE
    // skill: "I just had dinner with X. I learned Rina is going to UW" hit
    // `i just had {food:text}` and logged the entire two-sentence blob as a meal. Hand
    // compounds to the cloud router, which decomposes them into multiple actions (dinner
    // interaction + relationship + fact). Single trailing punctuation is NOT a compound.
    if (_isCompound(u)) return null;
    // Curated SEED templates take precedence over LEARNED ones (two passes), so a broad
    // learned entry ("note {text}") can never permanently shadow a specific seed
    // ("note that {person} {fact}"). Learned templates only fast-path phrasings no seed matches.
    for (final wantLearned in const [false, true]) {
      for (final e in corpus) {
        if (_learnedTemplates.contains(e.template) != wantLearned) continue;
        final slots = _extract(e, u, asOf, contacts);
        if (slots != null) {
          // A learned generative-recognition entry (`G-46`) routes offline to its kind — the {contact}
          // slot becomes the param. The session dispatches it to the GenerativeService, same as a
          // residual-recognized one, with no cloud classification call.
          if (e.generativeKind != null) {
            return {'generativeKind': e.generativeKind, 'params': slots, 'source': 'corpus', 'template': e.template};
          }
          return {'skillId': e.skillId, 'slots': slots, 'source': 'corpus', 'template': e.template};
        }
      }
    }
    return null;
  }

  /// Match [u] against a single compiled entry and extract its resolved slots, or null if
  /// the template doesn't apply. Shared by [route] and [learnSuggested] so a learned
  /// template is validated by the SAME extraction the router uses at dispatch time.
  Map<String, dynamic>? _extract(CorpusEntry e, String u, DateTime asOf, Set<String> contacts) {
    final m = e.regex.firstMatch(u);
    if (m == null) return null;
    final slots = <String, dynamic>{};
    var ok = true;
    e.slotTypes.forEach((name, type) {
      final raw = m.namedGroup(name)?.trim();
      final v = type == 'contact'
          ? (raw != null && contacts.contains(raw.toLowerCase()) ? raw : null)
          : type == 'entity'
              ? (_entityOk(raw) ? raw : null) // a NAME slot can't start with the/a/my/I/... (G-12)
              : _resolveSlot(raw, type, asOf);
      // an unparseable date/datetime — or a :contact/:entity slot that isn't a plausible name —
      // means this template doesn't apply; fall through. (For datetime this is also the task-vs-
      // reminder discriminator: "on friday" has no time -> null -> the reminder template is
      // skipped and the date-only create-task template wins.)
      if (v == null &&
          (type == 'date' ||
              type == 'futuredate' ||
              type == 'dayword' ||
              type == 'pastday' ||
              type == 'datetime' ||
              type == 'contact' ||
              type == 'entity')) {
        ok = false;
      }
      slots[name] = v;
    });
    if (!ok) return null;
    // Fold in the template's constant slots (e.g. kind="dinner"). A regex-captured slot always
    // wins — the constant is only a default for a slot the surface text didn't supply.
    e.fixedSlots.forEach((k, val) => slots.putIfAbsent(k, () => val));
    return slots;
  }

  // The slot types a learned template may use — the closed vocabulary [_compile] understands.
  // A cloud-suggested template naming anything else is rejected (never compiled into the corpus).
  static const _knownSlotTypes = {
    'text', 'date', 'futuredate', 'datetime', 'quantity', 'entity', 'contact',
    'dayword', 'pastday', 'posword', 'moodword', 'mealword', 'predword'
  };

  // Stop-words that don't make a template specific — a template whose only literal is one of these
  // (or bare punctuation) is a near-catch-all and must never be learned.
  static const _weakLiterals = {
    'i', 'a', 'an', 'my', 'me', 'the', 'im', "i'm", 'is', 'it', 'to', 'on', 'at', 'of', 'in', 'you',
    'so', 'no', 'do', 'we', 'that', 'this', 'and', 'or', 'for', 'be', 'am', 'was', 'had', 'have'
  };
  /// True iff the template keeps at least one literal WORD (≥2 letters) that isn't a stop-word, so a
  /// learned template can't be a catch-all ("{x:text}") or near-catch-all ("i'm {mood:text}").
  static bool _hasStrongLiteral(String template) {
    final lit = template.replaceAll(RegExp(r'\{\w+:\w+\}'), ' ');
    for (final m in RegExp('[A-Za-z]{2,}').allMatches(lit)) {
      if (!_weakLiterals.contains(m.group(0)!.toLowerCase())) return true;
    }
    return false;
  }

  /// Learn a template SUGGESTED by the cloud in the same routing call (Spec 05 §5.2, the
  /// "gets better with use" loop). Unlike [learn] — which reconstructs a template by finding
  /// slot VALUES verbatim in the surface and so can't learn date/time phrasings (the resolved
  /// value isn't in the text) — this trusts the cloud's surface abstraction but VALIDATES it by
  /// round-trip: the template must compile, match the utterance, and re-extract to the EXACT
  /// same slots the turn dispatched. Returns the template (to persist) or null if it fails any
  /// guard. Safe by construction: learned templates are tried only AFTER seeds (route's second
  /// pass), so one can never shadow a built-in.
  String? learnSuggested(String utterance, String skillId, Map<String, dynamic> dispatched,
      String template, {DateTime? clock, Set<String> contacts = const {}}) {
    final t = template.trim();
    final asOf = clock ?? now;
    // 1. Only the closed slot-type vocabulary; placeholders well-formed, bounded, and NAMED
    //    (not `_`, which produces no slot so the round-trip can't validate it).
    final phs = RegExp(r'\{(\w+):(\w+)\}').allMatches(t).toList();
    if (phs.isEmpty) return null; // a template with no slots is just a memorized utterance
    if (phs.length > 4) return null; // cap: many free-text slots invite catastrophic regex backtracking
    for (final m in phs) {
      if (m.group(1) == '_' || !_knownSlotTypes.contains(m.group(2))) return null;
    }
    // 2. A STRONG literal must survive — else "{x:text}" (catch-all) or "i'm {mood:text}"
    //    (near-catch-all) gets learned + persisted + inserted-first, hijacking all routing.
    if (!_hasStrongLiteral(t)) return null;
    // 3. Nothing to add if it's already in the corpus.
    if (corpus.any((c) => c.template == t)) return null;
    // 4. It must compile, match THIS utterance, and round-trip to the SAME resolved slots.
    final CorpusEntry e;
    try {
      e = _compile({'skillId': skillId, 'template': t});
    } catch (_) {
      return null; // a malformed pattern (bad group name, etc.) is rejected, never thrown
    }
    final got = _extract(e, utterance.trim(), asOf, contacts);
    if (got == null) return null;
    for (final k in {...dispatched.keys, ...got.keys}) {
      if (dispatched[k]?.toString() != got[k]?.toString()) return null; // resolved mismatch
    }
    corpus.insert(0, e);
    _learnedTemplates.add(t);
    return t;
  }

  // ---- retrieval fallback (findings §13): a candidate generator, not a router ----
  final Map<String, List<List<double>>> _skillVecs = {};

  /// Embed each skill's anchors (humanized id + displayName + its corpus
  /// templates cleaned to phrases). Multi-vector: one vector per anchor (§13).
  Future<void> buildRetrievalIndex(Map<String, Map<String, dynamic>> skills) async {
    // Probe the embed server ONCE. If it's down (the common case — it's optional), bail
    // immediately rather than eating a 5s connection timeout PER anchor (dozens of anchors
    // = a minute-long startup hang). Retrieval is a nice-to-have suggestion layer; without
    // the server it's simply unavailable, and routing still works (corpus + cloud + clarify).
    if (await embed('probe') == null) return;
    final anchors = <String, Set<String>>{};
    for (final s in skills.values) {
      final sid = s['skillId'] as String;
      final set = anchors.putIfAbsent(sid, () => {});
      set.add(sid.replaceAll('-', ' '));
      if (s['displayName'] != null) set.add(s['displayName'] as String);
    }
    for (final e in corpus) {
      // A generative entry (G-46) has an empty skillId — never anchor it here, or retrievalSuggest
      // could return {skillId: ''} and the miss path's skills['']! null-asserts (crash → error turn).
      // Generative candidates join retrieval under their kind only at the §3.2 end-state migration.
      if (e.generativeKind != null || e.skillId.isEmpty) continue;
      final phrase = e.template
          .replaceAllMapped(RegExp(r'\{(\w+):\w+\}'), (m) => m.group(1) == '_' ? '' : m.group(1)!)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      anchors.putIfAbsent(e.skillId, () => {}).add(phrase);
    }
    for (final entry in anchors.entries) {
      final vecs = <List<double>>[];
      for (final a in entry.value) {
        final v = await embed(a);
        if (v != null) vecs.add(v);
      }
      _skillVecs[entry.key] = vecs;
    }
  }

  /// On a corpus miss: rank skills by multi-vector max-sim; return the top skill
  /// iff it clears `theta` AND beats #2 by `tau` — a *suggestion*, not a dispatch
  /// (retrieval is a weak router; §13). null => clarify.
  Future<Map<String, dynamic>?> retrievalSuggest(String utterance,
      {double theta = 0.55, double tau = 0.03}) async {
    if (_skillVecs.isEmpty) return null;
    final uv = await embed(utterance);
    if (uv == null) return null;
    final scored = _skillVecs.entries
        .map((e) => MapEntry(e.key,
            e.value.isEmpty ? 0.0 : e.value.map((v) => cosine(uv, v)).reduce(max)))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final s1 = scored[0].value;
    final s2 = scored.length > 1 ? scored[1].value : 0.0;
    return {
      'skillId': scored[0].key,
      's1': s1,
      'margin': s1 - s2,
      'confident': s1 >= theta && (s1 - s2) >= tau,
    };
  }

  dynamic _resolveSlot(String? raw, String type, DateTime asOf) {
    if (raw == null) return null;
    switch (type) {
      case 'date':
      case 'dayword': // a constrained day expression — same resolution as a date slot
        return resolveDate(raw, asOf);
      case 'futuredate': // a FORWARD-intent date — a bare month-day that passed rolls to next year
        return resolveDate(raw, asOf, preferFuture: true);
      case 'pastday': // a BACKWARD-looking day expression — a bare weekday is the PREVIOUS one
        return _resolvePastday(raw, asOf);
      case 'datetime':
        return resolveDateTime(raw, asOf);
      case 'quantity':
        final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(raw);
        return m == null ? null : num.parse(m.group(0)!);
      default: // text, entity -> the surface (entity resolution happens in the skill via read_one, G-12)
        return raw;
    }
  }

  /// Public entry for the cloud path: resolve a past-event date phrase backward (a `pastday`-typed
  /// input, e.g. `log-interaction.at`). Bare "friday" → the PREVIOUS Friday, not the next one.
  String? resolvePastday(String phrase, DateTime now) => _resolvePastday(phrase, now);

  /// Public entry for the cloud path: resolve a FORWARD-intent date (a `futuredate` input, e.g.
  /// `create-task.dueDate`). A bare month-day already past this year → next year (reviewer b #6).
  String? resolveFutureDate(String phrase, DateTime now) => resolveDate(phrase, now, preferFuture: true);

  /// Resolve a BACKWARD-looking day expression: a bare weekday ("friday") is the PREVIOUS
  /// occurrence (you logged a past interaction), not the next one; everything else
  /// ("yesterday", "today", "last friday") already resolves correctly via [resolveDate].
  String? _resolvePastday(String phrase, DateTime now) {
    final p = phrase.toLowerCase().trim();
    const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    final wd = days.indexOf(p);
    if (wd >= 0) {
      var delta = (wd + 1) - now.weekday;
      if (delta >= 0) delta -= 7; // the PREVIOUS occurrence (strictly before today)
      final d = now.add(Duration(days: delta));
      return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    return resolveDate(phrase, now);
  }

  /// The deterministic date resolver (Spec 03 §6.2). Relative to [now]. When [preferFuture]
  /// is set (a `futuredate` slot — a task due date, a reschedule), a bare month-day that
  /// already fell earlier this year rolls to next year, since a due date in the past is never
  /// what "add a todo for March 3" means. Birthdays/anchors keep the literal year (preferFuture
  /// off) and roll forward at read time via next_annual instead (reviewer b #6).
  String? resolveDate(String phrase, DateTime now, {bool preferFuture = false}) {
    var p = phrase.toLowerCase().trim();
    // Weekday ABBREVIATIONS ("sat", "on tue", "next thurs") -> full names, so the weekday
    // resolution below (which matches spelled-out days) handles them uniformly. Only a bare
    // abbreviation with an optional on/next/last prefix expands; "saturday", "may", "mar 3"
    // don't match this shape and pass through untouched.
    p = p.replaceFirstMapped(
        RegExp(r'^(last\s+|next\s+|on\s+)?(mon|tues?|weds?|thu|thur|thurs|fri|sat|sun)$'), (mm) {
      const map = {
        'mon': 'monday', 'tue': 'tuesday', 'tues': 'tuesday', 'wed': 'wednesday', 'weds': 'wednesday',
        'thu': 'thursday', 'thur': 'thursday', 'thurs': 'thursday', 'fri': 'friday',
        'sat': 'saturday', 'sun': 'sunday'
      };
      return '${mm.group(1) ?? ''}${map[mm.group(2)]}';
    });
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (p == 'today') return iso(now);
    // "tonight" / "this evening|afternoon|morning" all name TODAY's date (the time-of-day
    // is carried separately when there's a clock time).
    if (p == 'tonight' || p == 'this evening' || p == 'this afternoon' || p == 'this morning') {
      return iso(now);
    }
    if (p == 'tomorrow') return iso(now.add(const Duration(days: 1)));
    if (p == 'yesterday') return iso(now.subtract(const Duration(days: 1)));
    var m = RegExp(r'in (\d+) days?').firstMatch(p);
    if (m != null) return iso(now.add(Duration(days: int.parse(m.group(1)!))));
    const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    final lastWd = days.indexWhere((d) => p == 'last $d');
    if (lastWd >= 0) {
      var delta = (lastWd + 1) - now.weekday;
      if (delta >= 0) delta -= 7; // the PREVIOUS occurrence (strictly before today)
      return iso(now.add(Duration(days: delta)));
    }
    final wd = days.indexWhere((d) => p == d || p == 'on $d' || p == 'next $d');
    if (wd >= 0) {
      var delta = (wd + 1) - now.weekday;
      if (delta <= 0) delta += 7; // next occurrence
      return iso(now.add(Duration(days: delta)));
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(p)) return p.substring(0, 10);
    // month-name dates (for birthdays etc.): "march 3", "mar 3rd", "on july 12",
    // "3 march", "the 3rd of december". Resolved in the current year — callers that
    // care about the next annual occurrence (birthdays) roll it forward themselves.
    int monthOf(String tok) {
      const abbr = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
      return abbr.indexOf(tok.length >= 3 ? tok.substring(0, 3) : tok) + 1; // 0 = not a month
    }
    String? fromMonthDay(int mm, int dd) {
      if (mm <= 0 || dd < 1 || dd > 31) return null;
      var d = DateTime(now.year, mm, dd);
      // a due/reschedule date that already passed this year means NEXT year's occurrence
      if (preferFuture && d.isBefore(DateTime(now.year, now.month, now.day))) {
        d = DateTime(now.year + 1, mm, dd);
      }
      return iso(d);
    }
    // "march 3", "mar 3rd", "on july 12"  (month then day)
    final m1 = RegExp(r'^(?:on\s+)?([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?$').firstMatch(p);
    if (m1 != null) {
      final r = fromMonthDay(monthOf(m1.group(1)!), int.parse(m1.group(2)!));
      if (r != null) return r;
    }
    // "3 march", "the 3rd of december"  (day then month)
    final m2 = RegExp(r'^(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?([a-z]{3,9})$').firstMatch(p);
    if (m2 != null) {
      final r = fromMonthDay(monthOf(m2.group(2)!), int.parse(m2.group(1)!));
      if (r != null) return r;
    }
    return null;
  }

  /// Resolve a reminder time phrase to a full ISO datetime (Spec 03 §6.2, extended
  /// for time-of-day). A time-of-day component is REQUIRED — no clock time returns
  /// null, which is what separates a reminder ("call mom on thursday at 5pm") from
  /// a date-only task ("call mom on thursday"). An optional leading day phrase
  /// (today/tomorrow/tonight/weekday/in N days/ISO) is resolved via [resolveDate];
  /// absent, it's today, rolled to tomorrow if the time already passed.
  static const _numWords = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
    'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12,
  };

  /// Parse a spoken-word time-of-day in [p] into (hour24, minute), or null. Handles
  /// "<word> o'clock", "half past <word>", "quarter past/to <word>", "<word> thirty/
  /// fifteen/forty-five", and a bare "<word>" hour, plus an am/pm or morning/afternoon/
  /// evening/night meridian. With no meridian, hours 1–6 read as PM (the common evening-
  /// reminder intent — "remind me at five" is 5pm, not 5am); 7–12 stay as spoken.
  static (int, int)? _wordTime(String p) {
    final ws = _numWords.keys.join('|');
    int? hour, minute;
    RegExpMatch? m;
    if ((m = RegExp('\\bhalf past ($ws)\\b').firstMatch(p)) != null) {
      hour = _numWords[m!.group(1)];
      minute = 30;
    } else if ((m = RegExp('\\bquarter past ($ws)\\b').firstMatch(p)) != null) {
      hour = _numWords[m!.group(1)];
      minute = 15;
    } else if ((m = RegExp('\\bquarter to ($ws)\\b').firstMatch(p)) != null) {
      hour = (_numWords[m!.group(1)]! + 11) % 12; // hour - 1, wrapping 1 -> 12
      if (hour == 0) hour = 12;
      minute = 45;
    } else if ((m = RegExp("\\b($ws)\\s+(thirty|fifteen|forty[- ]?five)\\b").firstMatch(p)) != null) {
      hour = _numWords[m!.group(1)];
      minute = m.group(2)!.startsWith('thirty') ? 30 : (m.group(2)!.startsWith('fifteen') ? 15 : 45);
    } else if ((m = RegExp("\\b($ws)\\s*o'?clock\\b").firstMatch(p)) != null) {
      hour = _numWords[m!.group(1)];
      minute = 0;
    } else if ((m = RegExp("^(?:at\\s+)?($ws)(?:\\s+(?:[ap]\\.?m\\.?|in the (?:morning|afternoon|evening)|tonight))?\$")
            .firstMatch(p.trim())) !=
        null) {
      // a bare word-hour that is the WHOLE phrase ("five", "at five", "five pm", "nine in the
      // morning") — anchored to the end so "two apples", "five miles", "seven days" are NOT
      // misread as clock times. The meridian itself is applied by the hasPm/hasAm scan below.
      hour = _numWords[m!.group(1)];
      minute = 0;
    }
    if (hour == null) return null;
    final hasPm = RegExp(r'\bpm\b').hasMatch(p) || RegExp(r'\b(afternoon|evening|night|tonight)\b').hasMatch(p);
    final hasAm = RegExp(r'\bam\b').hasMatch(p) || RegExp(r'\bmorning\b').hasMatch(p);
    if (hasPm) {
      if (hour < 12) hour += 12;
    } else if (hasAm) {
      if (hour == 12) hour = 0;
    } else if (hour >= 1 && hour <= 6) {
      hour += 12; // meridian-less evening default
    }
    return (hour, minute ?? 0);
  }

  String? resolveDateTime(String phrase, DateTime now) {
    final p = phrase.toLowerCase().trim();
    // Relative offset: "in 20 minutes", "in an hour", "in half an hour", "20 mins", "2 hours".
    // Requires a unit word (a bare number is never a relative time), so it can't over-match.
    final rel = RegExp(r'^(?:in\s+)?(?:(\d+)|(an?)|(half an?|half a))\s+(minute|min|hour|hr)s?$').firstMatch(p);
    if (rel != null) {
      final perUnit = rel.group(4)!.startsWith('h') ? 60 : 1; // minutes per unit
      final int amount;
      if (rel.group(1) != null) {
        amount = int.parse(rel.group(1)!) * perUnit;
      } else if (rel.group(3) != null) {
        amount = (perUnit / 2).round(); // "half an hour" -> 30
      } else {
        amount = perUnit; // "an hour" / "a minute"
      }
      if (amount <= 0) return null;
      return now.add(Duration(minutes: amount)).toIso8601String();
    }
    int? hh, mm;
    if (RegExp(r'\bnoon\b').hasMatch(p)) {
      hh = 12;
      mm = 0;
    } else if (RegExp(r'\bmidnight\b').hasMatch(p)) {
      hh = 0;
      mm = 0;
    } else {
      // "5pm", "5:30 pm", "at 5 pm"
      final ampm = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b').firstMatch(p);
      if (ampm != null) {
        hh = int.parse(ampm.group(1)!);
        mm = ampm.group(2) == null ? 0 : int.parse(ampm.group(2)!);
        if (hh == 12) hh = 0; // 12am -> 0, 12pm -> 12 (added below)
        if (ampm.group(3) == 'pm') hh += 12;
      } else {
        // 24-hour "17:00" — require the colon so a bare "5" is never a time
        final h24 = RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(p);
        if (h24 != null) {
          hh = int.parse(h24.group(1)!);
          mm = int.parse(h24.group(2)!);
        }
      }
    }
    // WORD times ("five o'clock", "half past six", "quarter to seven", "eight thirty",
    // "five pm") — a spoken word-hour is unambiguously a time (you never say "five" as a
    // date), so unlike a bare DIGIT it can safely resolve without breaking the task-vs-
    // reminder discriminator. Only reached when no digit time matched.
    var usedWordTime = false;
    if (hh == null) {
      final wt = _wordTime(p);
      if (wt != null) {
        hh = wt.$1;
        mm = wt.$2;
        usedWordTime = true;
      }
    }
    if (hh == null || mm == null) return null; // no time-of-day -> not a datetime
    if (hh > 23 || mm > 59) return null;
    // strip the time + connective words to leave a (possibly empty) date phrase
    var dateWords = p
        .replaceAll(RegExp(r'\b\d{1,2}(?::\d{2})?\s*(am|pm)\b'), ' ')
        .replaceAll(RegExp(r'\b\d{1,2}:\d{2}\b'), ' ')
        .replaceAll(
            RegExp(r'\b(noon|midnight|at|tonight|this (?:evening|afternoon|morning))\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (usedWordTime) {
      dateWords = dateWords
          .replaceAll(
              RegExp(r"\b(half past|quarter past|quarter to|o'?clock|thirty|fifteen|"
                  r"forty[- ]?five|am|pm|in the (?:morning|afternoon|evening)|at night|"
                  r'one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b'),
              ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    final resolvedDay = dateWords.isEmpty ? null : resolveDate(dateWords, now);
    final base = resolvedDay != null ? DateTime.parse(resolvedDay) : now;
    var dt = DateTime(base.year, base.month, base.day, hh, mm);
    // a time-only reminder already past today rolls to tomorrow (the natural read
    // of "remind me at 8am" said in the afternoon); an explicit day is honored as-is.
    if (resolvedDay == null && !dt.isAfter(now)) dt = dt.add(const Duration(days: 1));
    String two(int x) => x.toString().padLeft(2, '0');
    return '${dt.year.toString().padLeft(4, '0')}-${two(dt.month)}-${two(dt.day)}'
        'T${two(dt.hour)}:${two(dt.minute)}:00';
  }
}
