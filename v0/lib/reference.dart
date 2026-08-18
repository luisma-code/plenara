/// Reference knowledge bases (Spec 13) — shipped, versioned datasets (nutrition first). A food
/// name resolves through tiers: (1) exact alias match after normalization — sync, offline, the
/// hot path; (2) in-process embedding nearest-neighbor for near-misses.
/// (Tier 3, a Haiku normalize-once-and-cache, is the documented next layer.) Every result carries
/// PROVENANCE so a looked-up value is never confused with a user-entered one, and a miss is
/// honest (null) rather than a guessed number.
library;

import 'dart:convert';
import 'dart:io';

import 'embed.dart';

class ReferenceEntry {
  final String key;
  final Map<String, dynamic>
      data; // raw entry: kcal, serving, grams, macros, category
  final String
      provenance; // 'reference' (exact/alias) | 'reference~' (fuzzy/embedding)
  ReferenceEntry(this.key, this.data, this.provenance);
  num? get kcal => data['kcal'] as num?;
}

class ReferenceStore {
  final String dataset;
  final Map<String, Map<String, dynamic>>
      _byKey; // normalized key/alias -> entry
  final List<String> _keys; // canonical keys (for tier-2)
  final Map<String, List<double>> _keyVecs = {}; // lazy tier-2 cache
  bool _vecsBuilt =
      false; // true only once EVERY key embedded (a partial cache must retry)
  ReferenceStore._(this.dataset, this._byKey, this._keys);

  static const _articles = {
    'a',
    'an',
    'the',
    'some',
    'my',
    'of',
    'one',
    'this'
  };

  /// Lowercase; punctuation -> space (so "stir-fry" -> "stir fry" matches the alias); drop
  /// articles/quantifiers and bare digit counts (so "a Banana!" -> "banana", "2 eggs" -> "eggs").
  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((t) =>
          t.isNotEmpty &&
          !_articles.contains(t) &&
          !RegExp(r'^\d+$').hasMatch(t))
      .join(' ');

  /// Load data/reference/<name>.json. A missing/broken file -> an empty store (the feature just
  /// goes quiet — logging still works without calories).
  static ReferenceStore load(String dataDir, String name) {
    final f = File('$dataDir/reference/$name.json');
    if (!f.existsSync()) return ReferenceStore._(name, {}, const []);
    try {
      final j = jsonDecode(f.readAsStringSync());
      return _build(name, (j['entries'] as List).cast<Map<String, dynamic>>());
    } on Object {
      return ReferenceStore._(name, {}, const []);
    }
  }

  /// Build directly from parsed entries (for tests).
  static ReferenceStore fromEntries(
          String name, List<Map<String, dynamic>> entries) =>
      _build(name, entries);

  /// Every canonical key that is REGISTERED must resolve back to its own entry
  /// through [normalize] — tier-2 depends on that round trip. Two defect shapes
  /// are therefore skipped deterministically, whole-entry, at build time:
  ///   - a key normalizing to '' (it could never be resolved at all; leaving it
  ///     in the tier-2 list made resolve() throw on a null-assert);
  ///   - a later key colliding with an earlier canonical key after
  ///     normalization (FIRST entry wins; keeping both let tier-2 return one
  ///     entry's data under the other entry's name).
  static ReferenceStore _build(
      String name, Iterable<Map<String, dynamic>> entries) {
    final byKey = <String, Map<String, dynamic>>{};
    final keys = <String>[];
    final canonical = <String>{};
    for (final e in entries) {
      final k = e['key'] as String;
      final nk = normalize(k);
      if (nk.isEmpty) continue;
      if (!canonical.add(nk)) continue; // collision: first entry wins
      keys.add(k);
      byKey[nk] = e; // a canonical key beats an earlier alias for this slot
      for (final a in (e['aliases'] as List? ?? const []).cast<String>()) {
        final na = normalize(a);
        if (na.isNotEmpty) byKey.putIfAbsent(na, () => e);
      }
    }
    return ReferenceStore._(name, byKey, keys);
  }

  bool get isEmpty => _byKey.isEmpty;
  int get size => _keys.length;

  /// Tier 1 (sync, offline): exact match after normalization. null on a miss.
  ReferenceEntry? lookup(String name) {
    final e = _byKey[normalize(name)];
    return e == null
        ? null
        : ReferenceEntry(e['key'] as String, e, 'reference');
  }

  /// Tiers 1→2: exact, else embedding nearest-neighbor over the canonical keys (needs the embed
  /// server; keys are embedded once and cached). Returns null if both miss — an honest "unknown",
  /// never a guess. [theta] guards against a confidently-wrong far match.
  Future<ReferenceEntry?> resolve(String name,
      {Embedder? embedder, double theta = 0.6}) async {
    final exact = lookup(name);
    if (exact != null) return exact;
    final embed = embedder ?? embedFn;
    final qv = await embed(name);
    if (qv == null) return null; // server down -> tier-2 unavailable
    if (!_vecsBuilt) {
      var allOk = true;
      for (final k in _keys) {
        if (_keyVecs.containsKey(k)) continue;
        final v = await embed(k);
        if (v != null) {
          _keyVecs[k] = v;
        } else {
          allOk =
              false; // server died mid-build -> retry the missing keys next call
        }
      }
      _vecsBuilt = allOk;
    }
    String? best;
    var bestSim = 0.0;
    for (final e in _keyVecs.entries) {
      final sim = cosine(qv, e.value);
      if (sim > bestSim) {
        bestSim = sim;
        best = e.key;
      }
    }
    if (best == null || bestSim < theta) return null;
    // _build guarantees every registered key round-trips through normalize();
    // stay defensive anyway — an honest null beats a throw in the food path.
    final entry = _byKey[normalize(best)];
    if (entry == null) return null;
    return ReferenceEntry(best, entry, 'reference~'); // '~' = fuzzy provenance
  }
}

typedef Embedder = Future<List<double>?> Function(String text);

/// The default embedder (the shared in-process embed()), aliased so [ReferenceStore]
/// doesn't import a function into a typedef default directly.
Future<List<double>?> embedFn(String text) => embed(text);
