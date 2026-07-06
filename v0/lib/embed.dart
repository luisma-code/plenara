/// Plenara v0 — embedding client for retrieval (Spec 03 §7.3 / findings §13).
/// Talks to a local llama-server serving bge-small (the dedicated ~80MB retrieval
/// model). This is the cold-start candidate generator; the corpus fast-path is
/// the primary router. On a real device this is an in-process model; here it's a
/// local HTTP server for iteration speed.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

const embedUrl = 'http://127.0.0.1:8091/v1/embeddings';

Future<List<double>?> embed(String text, {String url = embedUrl}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client.postUrl(Uri.parse(url));
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode({'input': text})));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    final data = (jsonDecode(body)['data'] as List)[0]['embedding'] as List;
    return data.map((e) => (e as num).toDouble()).toList();
  } on Exception {
    return null; // embed server down -> retrieval simply unavailable (offline-friendly)
  } finally {
    client.close();
  }
}

double cosine(List<double> a, List<double> b) {
  double dot = 0, na = 0, nb = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return (na == 0 || nb == 0) ? 0 : dot / (sqrt(na) * sqrt(nb));
}
