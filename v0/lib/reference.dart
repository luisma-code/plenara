/// Reference knowledge bases (Spec 13) — shipped, versioned datasets (nutrition first). A food
/// name resolves through tiers: (1) exact alias match after normalization — sync, offline, the
/// hot path; (2) embedding nearest-neighbor for near-misses — async, when the embed server is up.
/// (Tier 3, a Haiku normalize-once-and-cache, is the documented next layer.) Every result carries
/// PROVENANCE so a looked-up value is never confused with a user-entered one, and a miss is
/// honest (null) rather than a guessed number.
library;

import 'dart:convert';
import 'dart:io';

import 'embed.dart';

class ReferenceEntry {
  final String key;
  final Map<String, dynamic> data; // raw entry: kcal, serving, grams, macros, category
  final String provenance; // 'reference' (exact/alias) | 'reference~' (fuzzy/embedding)
  ReferenceEntry(this.key, this.data, this.provenance);
  num? get kcal => data['kcal'] as num?;
}

class ReferenceStore {
  final String dataset;
  final Map<String, Map<String, dynamic>> _byKey; // normalized key/alias -> entry
  final List<String> _keys; // canonical keys (for tier-2)
  final Map<String, List<double>> _keyVecs = {}; // lazy tier-2 cache
  ReferenceStore._(this.dataset, this._byKey, this._keys);

  static const _articles = {'a', 'an', 'the', 'some', 'my', 'of', 'one', 'this'};

  /// Lowercase, strip punctuation + leading articles/quantifiers so "a Banana!" -> "banana".
  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && !_articles.contains(t))
      .join(' ');

  /// Load data/reference/<name>.json. A missing/broken file -> an empty store (the feature just
  /// goes quiet — logging still works without calories).
  static ReferenceStore load(String dataDir, String name) {
    final f = File('$dataDir/reference/$name.json');
    if (!f.existsSync()) return ReferenceStore._(name, {}, const []);
    try {
      final j = jsonDecode(f.readAsStringSync());
      final byKey = <String, Map<String, dynamic>>{};
      final keys = <String>[];
      for (final e in (j['entries'] as List).cast<Map<String, dynamic>>()) {
        final k = e['key'] as String;
        keys.add(k);
        byKey[normalize(k)] = e;
        for (final a in (e['aliases'] as List? ?? const []).cast<String>()) {
          byKey.putIfAbsent(normalize(a), () => e);
        }
      }
      return ReferenceStore._(name, byKey, keys);
    } on Object {
      return ReferenceStore._(name, {}, const []);
    }
  }

  /// Build directly from parsed entries (for tests).
  static ReferenceStore fromEntries(String name, List<Map<String, dynamic>> entries) {
    final byKey = <String, Map<String, dynamic>>{};
    final keys = <String>[];
    for (final e in entries) {
      final k = e['key'] as String;
      keys.add(k);
      byKey[normalize(k)] = e;
      for (final a in (e['aliases'] as List? ?? const []).cast<String>()) {
        byKey.putIfAbsent(normalize(a), () => e);
      }
    }
    return ReferenceStore._(name, byKey, keys);
  }

  bool get isEmpty => _byKey.isEmpty;
  int get size => _keys.length;

  /// Tier 1 (sync, offline): exact match after normalization. null on a miss.
  ReferenceEntry? lookup(String name) {
    final e = _byKey[normalize(name)];
    return e == null ? null : ReferenceEntry(e['key'] as String, e, 'reference');
  }

  /// Tiers 1→2: exact, else embedding nearest-neighbor over the canonical keys (needs the embed
  /// server; keys are embedded once and cached). Returns null if both miss — an honest "unknown",
  /// never a guess. [theta] guards against a confidently-wrong far match.
  Future<ReferenceEntry?> resolve(String name, {Embedder? embedder, double theta = 0.6}) async {
    final exact = lookup(name);
    if (exact != null) return exact;
    final embed = embedder ?? embedFn;
    final qv = await embed(name);
    if (qv == null) return null; // server down -> tier-2 unavailable
    if (_keyVecs.isEmpty) {
      for (final k in _keys) {
        final v = await embed(k);
        if (v != null) _keyVecs[k] = v;
      }
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
    return ReferenceEntry(best, _byKey[normalize(best)]!, 'reference~'); // '~' = fuzzy provenance
  }
}

typedef Embedder = Future<List<double>?> Function(String text);

/// The default embedder (the shared embed() over the local server), aliased so [ReferenceStore]
/// doesn't import a function into a typedef default directly.
Future<List<double>?> embedFn(String text) => embed(text);
