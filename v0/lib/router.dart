/// Plenara v0 — the corpus fast-path router (Spec 03 §5 + §6). Data-driven:
/// `data/corpus.json` holds slot-abstracted templates -> (skillId, typed slot
/// recipes). A template match extracts slots deterministically (dates via the
/// resolver, §6.2). This is the PRIMARY router (findings §13); retrieval is the
/// cold-start fallback added next. Corpus entries are DATA, so the "gets better"
/// loop (§5.2) just appends entries — no code change.
library;

import 'dart:convert';
import 'dart:io';

class CorpusEntry {
  final String skillId;
  final RegExp regex; // named groups per slot
  final Map<String, String> slotTypes; // slotName -> text|date|entity|quantity
  CorpusEntry(this.skillId, this.regex, this.slotTypes);
}

class Router {
  final List<CorpusEntry> corpus;
  final DateTime now;
  Router(this.corpus, this.now);

  static Router load(String path, DateTime now) {
    final raw = jsonDecode(File(path).readAsStringSync()) as List;
    final entries = raw.map((e) => _compile(e as Map<String, dynamic>)).toList();
    return Router(entries, now);
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
    return CorpusEntry(e['skillId'] as String,
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
  Map<String, dynamic>? route(String utterance) {
    final u = utterance.trim();
    for (final e in corpus) {
      final m = e.regex.firstMatch(u);
      if (m == null) continue;
      final slots = <String, dynamic>{};
      var ok = true;
      e.slotTypes.forEach((name, type) {
        final raw = m.namedGroup(name)?.trim();
        final v = _resolveSlot(raw, type);
        if (v == null && type == 'date') ok = false; // unparseable date -> not this template
        slots[name] = v;
      });
      if (ok) return {'skillId': e.skillId, 'slots': slots, 'source': 'corpus'};
    }
    return null;
  }

  dynamic _resolveSlot(String? raw, String type) {
    if (raw == null) return null;
    switch (type) {
      case 'date':
        return resolveDate(raw, now);
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
    return null;
  }
}
