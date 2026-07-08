/// Content search over free-text records (F-12) — "find that note about the cabin trip". A
/// SEMANTIC layer (embed + cosine nearest-neighbor) when an embedding backend is available, with
/// an always-on KEYWORD fallback so search still works offline without the embed server. The
/// embedder is a seam so tests — and a dogfood build with no server — don't require the model.
library;

import 'embed.dart';

typedef Embedder = Future<List<double>?> Function(String text);

class ContentSearchIndex {
  final Embedder _embed;
  final Map<String, List<double>> _vecs = {}; // recordId -> content vector
  ContentSearchIndex({Embedder? embedder}) : _embed = embedder ?? embed;

  bool get isEmpty => _vecs.isEmpty;

  /// The searchable free-text of a record (null = not a searchable record).
  static String? contentOf(Map<String, dynamic> r) {
    final v = switch (r['typeId']) {
      'journal_entry' => r['entry'],
      'contact_fact' => r['fact'],
      'task' => r['description'],
      'interaction' => r['note'],
      'reminder' => r['text'],
      _ => null,
    };
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Embed every searchable record. Skips records whose embed fails (server down -> the index
  /// stays empty -> callers keyword-fall-back). Idempotent per id.
  Future<void> build(Iterable<Map<String, dynamic>> records) async {
    for (final r in records) {
      final id = r['id'] as String?;
      final c = contentOf(r);
      if (id == null || c == null || _vecs.containsKey(id)) continue;
      final v = await _embed(c);
      if (v != null) _vecs[id] = v;
    }
  }

  /// Semantic ranking of indexed records by cosine similarity to [query]; returns record ids
  /// scoring >= [theta], best first. Returns null when embeddings are unavailable (empty index
  /// OR the query won't embed) — the signal for the caller to keyword-fall-back.
  Future<List<String>?> search(String query, {double theta = 0.35, int k = 5}) async {
    if (_vecs.isEmpty) return null;
    final qv = await _embed(query);
    if (qv == null) return null;
    final scored = _vecs.entries
        .map((e) => MapEntry(e.key, cosine(qv, e.value)))
        .where((e) => e.value >= theta)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return scored.take(k).map((e) => e.key).toList();
  }

  static const _stop = {
    'the', 'and', 'that', 'this', 'for', 'with', 'was', 'were', 'are', 'you', 'your', 'from',
    'have', 'had', 'his', 'her', 'their', 'its', 'about', 'note', 'notes', 'entry', 'when', 'what'
  };

  /// Always-available keyword fallback: rank records by how many meaningful query terms (length
  /// > 2, non-stopword) their content contains. Deterministic, offline, no model — so search
  /// never silently fails.
  static List<String> keywordSearch(String query, Iterable<Map<String, dynamic>> records, {int k = 5}) {
    final terms = query.toLowerCase().split(RegExp(r'\W+')).where((t) => t.length > 2 && !_stop.contains(t)).toSet();
    if (terms.isEmpty) return const [];
    final scored = <MapEntry<String, int>>[];
    for (final r in records) {
      final c = contentOf(r)?.toLowerCase();
      final id = r['id'] as String?;
      if (c == null || id == null) continue;
      final hits = terms.where(c.contains).length;
      if (hits > 0) scored.add(MapEntry(id, hits));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(k).map((e) => e.key).toList();
  }
}
