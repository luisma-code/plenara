/// Unit tests for the live ClaudeClient against a local stub HTTP server (the
/// client code was previously untested — replay only covers post-processed
/// results). Every failure shape must return null and NEVER throw (Spec 04 §3.5).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:plenara/store.dart';
import 'package:test/test.dart';

final _skills = loadDefs('data/skills', 'skillId');

Future<HttpServer> _serve(void Function(HttpRequest) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

ClaudeClient _client(HttpServer s) =>
    ClaudeClient(apiKeyOverride: 'test-key', url: 'http://127.0.0.1:${s.port}/v1/messages');

void _reply(HttpRequest req, int status, String body) {
  req.response.statusCode = status;
  req.response.write(body);
  req.response.close();
}

String _text(String t) => jsonEncode({'content': [{'type': 'text', 'text': t}]});

void main() {
  test('200 good -> routes with slots', () async {
    final s = await _serve((r) => _reply(r, 200, _text('{"skillId":"create-task","slots":{"description":"buy milk"}}')));
    final res = await _client(s).routeResidual('jot down buy milk', _skills);
    expect(res?['skillId'], 'create-task');
    expect(res?['slots']['description'], 'buy milk');
    expect(res?['source'], 'cloud');
    await s.close(force: true);
  });

  test('200 empty content array (refusal shape) -> null, no throw', () async {
    final s = await _serve((r) => _reply(r, 200, jsonEncode({'content': [], 'stop_reason': 'refusal'})));
    expect(await _client(s).routeResidual('x', _skills), isNull);
    await s.close(force: true);
  });

  test('200 non-text first block -> null', () async {
    final s = await _serve((r) => _reply(r, 200, jsonEncode({'content': [{'type': 'thinking', 'text': 'hmm'}]})));
    expect(await _client(s).routeResidual('x', _skills), isNull);
    await s.close(force: true);
  });

  test('200 prose-wrapped JSON -> still extracts', () async {
    final s = await _serve((r) => _reply(r, 200, _text('Sure! {"skillId":"log-mood","slots":{"rating":"great"}} hope that helps')));
    expect((await _client(s).routeResidual('x', _skills))?['skillId'], 'log-mood');
    await s.close(force: true);
  });

  test('200 unknown skillId -> null (validated against inventory)', () async {
    final s = await _serve((r) => _reply(r, 200, _text('{"skillId":"nonexistent","slots":{}}')));
    expect(await _client(s).routeResidual('x', _skills), isNull);
    await s.close(force: true);
  });

  test('200 skillId "none" -> null (abstain)', () async {
    final s = await _serve((r) => _reply(r, 200, _text('{"skillId":"none"}')));
    expect(await _client(s).routeResidual('x', _skills), isNull);
    await s.close(force: true);
  });

  test('leaked "none" slot value normalized to null', () async {
    final s = await _serve((r) => _reply(r, 200, _text('{"skillId":"create-task","slots":{"description":"x","dueDate":"none"}}')));
    final res = await _client(s).routeResidual('x', _skills);
    expect(res?['slots']['dueDate'], isNull);
    await s.close(force: true);
  });

  test('429 / 500 -> null, no throw', () async {
    final s = await _serve((r) => _reply(r, 429, 'rate limited'));
    expect(await _client(s).routeResidual('x', _skills), isNull);
    await s.close(force: true);
  });

  test('malformed JSON body -> null, no throw', () async {
    final s = await _serve((r) => _reply(r, 200, 'definitely not json'));
    expect(await _client(s).routeResidual('x', _skills), isNull);
    await s.close(force: true);
  });

  test('authorCapability: good -> {type, skill}', () async {
    final s = await _serve((r) => _reply(r, 200, _text('{"type":{"typeId":"t"},"skill":{"skillId":"s"}}')));
    final a = await _client(s).authorCapability('thing');
    expect(a?['type'], isA<Map>());
    expect((a?['skill'] as Map)['skillId'], 's');
    await s.close(force: true);
  });

  test('authorCapability: non-map type/skill -> null', () async {
    final s = await _serve((r) => _reply(r, 200, _text('{"type":"x","skill":1}')));
    expect(await _client(s).authorCapability('thing'), isNull);
    await s.close(force: true);
  });

  test('connection refused -> null, no throw', () async {
    final c = ClaudeClient(apiKeyOverride: 'k', url: 'http://127.0.0.1:1/v1/messages');
    expect(await c.routeResidual('x', _skills), isNull);
  });

  test('empty key -> null with no network call', () async {
    final c = ClaudeClient(apiKeyOverride: '', url: 'http://127.0.0.1:1/unused');
    expect(c.available, isFalse);
    expect(await c.routeResidual('x', _skills), isNull);
    expect(await c.authorCapability('x'), isNull);
  });
}
