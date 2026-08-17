/// Plenara v0 — offline embedding seam for retrieval and semantic search.
/// Production uses the deterministic in-process backend below: no companion
/// server, network, model download, or startup timeout. The HTTP backend remains
/// available only for measured model experiments behind the same interface.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

const embedUrl = 'http://127.0.0.1:8091/v1/embeddings';

abstract interface class EmbeddingBackend {
  Future<List<double>?> embed(String text);
}

/// A compact feature-hashing sentence representation. This is the deterministic
/// availability floor while a packaged sentence-transformer is evaluated. Word
/// and adjacent-word features preserve intent vocabulary; light character
/// trigrams tolerate common STT spelling variation.
class InProcessEmbeddingBackend implements EmbeddingBackend {
  final int dimensions;
  const InProcessEmbeddingBackend({this.dimensions = 384});

  static const _aliases = <String, String>{
    'todo': 'task',
    'todos': 'task',
    'tasks': 'task',
    'capture': 'add',
    'record': 'add',
    'remember': 'add',
    'jot': 'add',
    'note': 'add',
    'ping': 'remind',
    'nudge': 'remind',
    'alert': 'remind',
    'notification': 'remind',
    'finished': 'complete',
    'finish': 'complete',
    'done': 'complete',
    'show': 'list',
    'display': 'list',
  };

  @override
  Future<List<double>?> embed(String text) async {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'\{\w+:\w+\}'), ' value ')
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .map((word) => _aliases[word] ?? word)
        .toList(growable: false);
    if (words.isEmpty) return null;
    final vector = List<double>.filled(dimensions, 0);
    void add(String feature, double weight) {
      final hash = _fnv1a(feature);
      final index = hash % dimensions;
      vector[index] += ((hash >> 8) & 1) == 0 ? weight : -weight;
    }

    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      add('w:$word', 1.8);
      if (index + 1 < words.length) add('b:$word ${words[index + 1]}', 1.1);
      final padded = '^$word\$';
      for (var char = 0; char + 3 <= padded.length; char++) {
        add('c:${padded.substring(char, char + 3)}', 0.12);
      }
    }
    return vector;
  }

  static int _fnv1a(String value) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(value)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}

class HttpEmbeddingBackend implements EmbeddingBackend {
  final String url;
  const HttpEmbeddingBackend({this.url = embedUrl});

  @override
  Future<List<double>?> embed(String text) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(Uri.parse(url));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({'input': text})));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      final data = (jsonDecode(body)['data'] as List)[0]['embedding'] as List;
      return data.map((value) => (value as num).toDouble()).toList();
    } on Exception {
      return null;
    } finally {
      client.close();
    }
  }
}

const _productionBackend = InProcessEmbeddingBackend();

Future<List<double>?> embed(String text) => _productionBackend.embed(text);

double cosine(List<double> a, List<double> b) {
  if (a.length != b.length) return 0;
  double dot = 0, na = 0, nb = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return (na == 0 || nb == 0) ? 0 : dot / (sqrt(na) * sqrt(nb));
}
