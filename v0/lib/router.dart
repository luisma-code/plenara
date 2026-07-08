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
  CorpusEntry(this.skillId, this.template, this.regex, this.slotTypes);
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
  String? learn(String utterance, String skillId, Map<String, dynamic> slots) {
    var t = utterance.trim();
    final nonNull = slots.entries.where((e) => e.value != null).toList();
    var abstracted = 0;
    for (final e in nonNull) {
      final vs = e.value.toString();
      final idx = t.toLowerCase().indexOf(vs.toLowerCase());
      if (idx >= 0) {
        t = '${t.substring(0, idx)}{${e.key}:${_inferType(vs)}}${t.substring(idx + vs.length)}';
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
    if (t.replaceAll(RegExp(r'\{\w+:\w+\}'), ' ').trim().isEmpty) return null;
    if (corpus.any((c) => c.template == t)) return null; // dedupe: nothing new to persist
    corpus.insert(0, _compile({'skillId': skillId, 'template': t}));
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

  static String _inferType(String v) {
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return 'date';
    if (RegExp(r'^\d+(\.\d+)?$').hasMatch(v)) return 'quantity';
    return 'text';
  }

  /// Compile a template like "add {description:text} to my {_:text}" into a
  /// case-insensitive anchored regex with named capture groups.
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
      sb.write('(?<$group>.+?)');
      i = m.end;
    }
    sb.write(_lit(tmpl.substring(i)));
    sb.write(r'\.?$');
    return CorpusEntry(e['skillId'] as String, tmpl,
        RegExp(sb.toString(), caseSensitive: false), slotTypes);
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
    // Curated SEED templates take precedence over LEARNED ones (two passes), so a broad
    // learned entry ("note {text}") can never permanently shadow a specific seed
    // ("note that {person} {fact}"). Learned templates only fast-path phrasings no seed matches.
    for (final wantLearned in const [false, true]) {
      for (final e in corpus) {
        if (_learnedTemplates.contains(e.template) != wantLearned) continue;
        final m = e.regex.firstMatch(u);
        if (m == null) continue;
        final slots = <String, dynamic>{};
        var ok = true;
        e.slotTypes.forEach((name, type) {
          final raw = m.namedGroup(name)?.trim();
          final v = type == 'contact'
              ? (raw != null && contacts.contains(raw.toLowerCase()) ? raw : null)
              : _resolveSlot(raw, type, asOf);
          // an unparseable date/datetime — or a :contact slot that isn't a known person — means
          // this template doesn't apply; fall through. (For datetime this is also the task-vs-
          // reminder discriminator: "on friday" has no time -> null -> the reminder template is
          // skipped and the date-only create-task template wins.)
          if (v == null && (type == 'date' || type == 'datetime' || type == 'contact')) ok = false;
          slots[name] = v;
        });
        if (ok) return {'skillId': e.skillId, 'slots': slots, 'source': 'corpus', 'template': e.template};
      }
    }
    return null;
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
        return resolveDate(raw, asOf);
      case 'datetime':
        return resolveDateTime(raw, asOf);
      case 'quantity':
        final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(raw);
        return m == null ? null : num.parse(m.group(0)!);
      default: // text, entity -> the surface (entity resolution happens in the skill via read_one, G-12)
        return raw;
    }
  }

  /// The deterministic date resolver (Spec 03 §6.2). Relative to [now].
  String? resolveDate(String phrase, DateTime now) {
    final p = phrase.toLowerCase().trim();
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (p == 'today') return iso(now);
    if (p == 'tomorrow') return iso(now.add(const Duration(days: 1)));
    if (p == 'yesterday') return iso(now.subtract(const Duration(days: 1)));
    var m = RegExp(r'in (\d+) days?').firstMatch(p);
    if (m != null) return iso(now.add(Duration(days: int.parse(m.group(1)!))));
    const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
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
    String? fromMonthDay(int mm, int dd) =>
        (mm > 0 && dd >= 1 && dd <= 31) ? iso(DateTime(now.year, mm, dd)) : null;
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
  String? resolveDateTime(String phrase, DateTime now) {
    final p = phrase.toLowerCase().trim();
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
    if (hh == null || mm == null) return null; // no time-of-day -> not a datetime
    if (hh > 23 || mm > 59) return null;
    // strip the time + connective words to leave a (possibly empty) date phrase
    final dateWords = p
        .replaceAll(RegExp(r'\b\d{1,2}(?::\d{2})?\s*(am|pm)\b'), ' ')
        .replaceAll(RegExp(r'\b\d{1,2}:\d{2}\b'), ' ')
        .replaceAll(
            RegExp(r'\b(noon|midnight|at|tonight|this (?:evening|afternoon|morning))\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
