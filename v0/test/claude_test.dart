/// Unit tests for the live ClaudeClient against a local stub HTTP server. Every
/// outcome maps to a TYPED CloudResult (Spec 04 §3.5): a genuine value or abstain
/// (CloudOk), or a named failure (CloudError.kind) — never a thrown exception and
/// never a bare null that conflates "the model abstained" with "we never heard back".
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

// unwrap helpers
Map<String, dynamic>? _ok(CloudResult<Map<String, dynamic>?> r) => (r as CloudOk<Map<String, dynamic>?>).value;
CloudErrorKind _errKind(CloudResult<Map<String, dynamic>?> r) => (r as CloudError<Map<String, dynamic>?>).kind;

void main() {
  test('200 good -> Ok(route) with slots', () async {
    final s = await _serve((r) => _reply(r, 200, _text('{"skillId":"create-task","slots":{"description":"buy milk"}}')));
    final res = _ok(await _client(s).routeResidual('jot down buy milk', _skills));
    expect(res?['skillId'], 'create-task');
    expect(res?['slots']['description'], 'buy milk');
    expect(res?['source'], 'cloud');
    await s.close(force: true);
  });

  test('200 empty content (refusal shape) -> CloudError.malformed', () async {
    final s = await _serve((r) => _reply(r, 200, jsonEncode({'content': [], 'stop_reason': 'refusal'})));
    expect(_errKind(await _client(s).routeResidual('x', _skills)), CloudErrorKind.malformed);
    await s.close(force: true);
  });

  test('200 non-text first block -> CloudError.malformed', () async {
    final s = await _serve((r) => _reply(r, 200, jsonEncode({'content': [{'type': 'thinking', 'text': 'hmm'}]})));
    expect(_errKind(await _client(s).routeResidual('x', _skills)), CloudErrorKind.malformed);
    await s.close(force: true);
  });

  test('200 prose-wrapped JSON -> Ok, still extracts', () async {
    final s = await _serve((r) => _reply(r, 200, _text('Sure! {"skillId":"log-mood","slots":{"rating":"great"}} hope that helps')));
    expect(_ok(await _client(s).routeResidual('x', _skills))?['skillId'], 'log-mood');
    await s.close(force: true);
  });

  test('200 unknown skillId -> Ok(null) abstain (validated against inventory)', () async {
    final s = await _serve((r) => _reply(r, 200, _text('{"skillId":"nonexistent","slots":{}}')));
    expect(_ok(await _client(s).routeResidual('x', _skills)), isNull);
    await s.close(force: true);
  });

  test('200 skillId "none" -> Ok(null) abstain', () async {
    final s = await _serve((r) => _reply(r, 200, _text('{"skillId":"none"}')));
    expect(_ok(await _client(s).routeResidual('x', _skills)), isNull);
    await s.close(force: true);
  });

  test('leaked "none" slot value normalized to null', () async {
    final s = await _serve((r) => _reply(r, 200, _text('{"skillId":"create-task","slots":{"description":"x","dueDate":"none"}}')));
    final res = _ok(await _client(s).routeResidual('x', _skills));
    expect(res?['slots']['dueDate'], isNull);
    await s.close(force: true);
  });

  test('401 -> CloudError.badKey (actionable)', () async {
    final s = await _serve((r) => _reply(r, 401, '{"error":"invalid x-api-key"}'));
    expect(_errKind(await _client(s).routeResidual('x', _skills)), CloudErrorKind.badKey);
    await s.close(force: true);
  });

  test('429 -> CloudError.rateLimited', () async {
    final s = await _serve((r) => _reply(r, 429, 'rate limited'));
    expect(_errKind(await _client(s).routeResidual('x', _skills)), CloudErrorKind.rateLimited);
    await s.close(force: true);
  });

  test('500 -> CloudError.serverError', () async {
    final s = await _serve((r) => _reply(r, 500, 'boom'));
    expect(_errKind(await _client(s).routeResidual('x', _skills)), CloudErrorKind.serverError);
    await s.close(force: true);
  });

  test('malformed JSON body -> CloudError.malformed', () async {
    final s = await _serve((r) => _reply(r, 200, 'definitely not json'));
    expect(_errKind(await _client(s).routeResidual('x', _skills)), CloudErrorKind.malformed);
    await s.close(force: true);
  });

  test('authorCapability: good -> Ok({type, skill})', () async {
    final s = await _serve((r) => _reply(r, 200, _text('{"type":{"typeId":"t"},"skill":{"skillId":"s"}}')));
    final a = _ok(await _client(s).authorCapability('thing'));
    expect(a?['type'], isA<Map>());
    expect((a?['skill'] as Map)['skillId'], 's');
    await s.close(force: true);
  });

  test('authorCapability: non-map type/skill -> CloudError.malformed', () async {
    final s = await _serve((r) => _reply(r, 200, _text('{"type":"x","skill":1}')));
    expect(_errKind(await _client(s).authorCapability('thing')), CloudErrorKind.malformed);
    await s.close(force: true);
  });

  test('connection refused -> CloudError.offline, no throw', () async {
    final c = ClaudeClient(apiKeyOverride: 'k', url: 'http://127.0.0.1:1/v1/messages');
    expect(_errKind(await c.routeResidual('x', _skills)), CloudErrorKind.offline);
  });

  test('empty key -> CloudError.noKey with no network call', () async {
    final c = ClaudeClient(apiKeyOverride: '', url: 'http://127.0.0.1:1/unused');
    expect(c.available, isFalse);
    expect(_errKind(await c.routeResidual('x', _skills)), CloudErrorKind.noKey);
    expect(_errKind(await c.authorCapability('x')), CloudErrorKind.noKey);
  });
}
