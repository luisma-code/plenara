import 'dart:convert';
import 'dart:io';

import 'package:plenara/embed.dart';
import 'package:test/test.dart';

void main() {
  test('in-process representation separates an intent paraphrase from noise',
      () async {
    const backend = InProcessEmbeddingBackend();
    final task = (await backend.embed('add a task'))!;
    final paraphrase = (await backend.embed('capture a todo'))!;
    final unrelated = (await backend.embed('weather in Barcelona'))!;

    expect(cosine(task, task), closeTo(1, 0.000001));
    expect(cosine(task, paraphrase), greaterThan(0.8));
    expect(cosine(task, unrelated), lessThan(0.25));
    expect(await backend.embed('---'), isNull);
    expect(cosine([1], [1, 2]), 0);
  });

  test('development HTTP adapter shares the backend contract', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'data': [
            {
              'embedding': [0.25, 0.75]
            }
          ]
        }));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final result = await HttpEmbeddingBackend(
      url: 'http://127.0.0.1:${server.port}/v1/embeddings',
    ).embed('hello');

    expect(result, [0.25, 0.75]);
  });

  test('development HTTP adapter contains connection failures', () async {
    final result = await const HttpEmbeddingBackend(
      url: 'http://127.0.0.1:1/v1/embeddings',
    ).embed('hello');
    expect(result, isNull);
  });

  test('a malformed response SHAPE degrades to null (TypeError is an Error, not an Exception)',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'data': 'not a list'})); // shape mismatch -> TypeError
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final result = await HttpEmbeddingBackend(
      url: 'http://127.0.0.1:${server.port}/v1/embeddings',
    ).embed('hello');
    expect(result, isNull); // the old `on Exception` clause let the TypeError escape
  });

  test('a hung embedding server times out to null (response-side deadline)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {/* accept and never respond */});
    addTearDown(() => server.close(force: true));

    final result = await HttpEmbeddingBackend(
      url: 'http://127.0.0.1:${server.port}/v1/embeddings',
      timeout: const Duration(milliseconds: 200),
    ).embed('hello');
    expect(result, isNull);
  });
}
