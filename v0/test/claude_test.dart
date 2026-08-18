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

ClaudeClient _client(HttpServer s) => ClaudeClient(
    apiKeyOverride: 'test-key', url: 'http://127.0.0.1:${s.port}/v1/messages');

void _reply(HttpRequest req, int status, String body) {
  req.response.statusCode = status;
  req.response.write(body);
  req.response.close();
}

String _text(String t) => jsonEncode({
      'content': [
        {'type': 'text', 'text': t}
      ]
    });

// unwrap helpers
Map<String, dynamic>? _ok(CloudResult<Map<String, dynamic>?> r) =>
    (r as CloudOk<Map<String, dynamic>?>).value;
CloudErrorKind _errKind(CloudResult<Map<String, dynamic>?> r) =>
    (r as CloudError<Map<String, dynamic>?>).kind;

/// An HttpClient whose first action throws [error] — for exercising the typed
/// mapping of transport exceptions the loopback stub can't produce on demand
/// (TLS handshake failures, connections dropped mid-exchange).
class _ThrowingHttpClient implements HttpClient {
  final Object error;
  _ThrowingHttpClient(this.error);
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> postUrl(Uri url) => Future<HttpClientRequest>.error(error);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<CloudErrorKind> _kindWhenTransportThrows(Object error) async {
  final res = await HttpOverrides.runZoned(
    () => ClaudeClient(apiKeyOverride: 'k', url: 'http://127.0.0.1:9/v1/messages')
        .validateKey(),
    createHttpClient: (_) => _ThrowingHttpClient(error),
  );
  return (res as CloudError<String>).kind;
}

void main() {
  test('200 good -> Ok(route) with slots', () async {
    final s = await _serve((r) => _reply(r, 200,
        _text('{"skillId":"create-task","slots":{"description":"buy milk"}}')));
    final res =
        _ok(await _client(s).routeResidual('jot down buy milk', _skills));
    expect(res?['skillId'], 'create-task');
    expect(res?['slots']['description'], 'buy milk');
    expect(res?['source'], 'cloud');
    await s.close(force: true);
  });

  test('200 empty content (refusal shape) -> CloudError.malformed', () async {
    final s = await _serve((r) =>
        _reply(r, 200, jsonEncode({'content': [], 'stop_reason': 'refusal'})));
    expect(_errKind(await _client(s).routeResidual('x', _skills)),
        CloudErrorKind.malformed);
    await s.close(force: true);
  });

  test('200 non-text first block -> CloudError.malformed', () async {
    final s = await _serve((r) => _reply(
        r,
        200,
        jsonEncode({
          'content': [
            {'type': 'thinking', 'text': 'hmm'}
          ]
        })));
    expect(_errKind(await _client(s).routeResidual('x', _skills)),
        CloudErrorKind.malformed);
    await s.close(force: true);
  });

  test('200 prose-wrapped JSON -> Ok, still extracts', () async {
    final s = await _serve((r) => _reply(
        r,
        200,
        _text(
            'Sure! {"skillId":"log-mood","slots":{"rating":"great"}} hope that helps')));
    expect(_ok(await _client(s).routeResidual('x', _skills))?['skillId'],
        'log-mood');
    await s.close(force: true);
  });

  test('200 unknown skillId -> Ok(null) abstain (validated against inventory)',
      () async {
    final s = await _serve(
        (r) => _reply(r, 200, _text('{"skillId":"nonexistent","slots":{}}')));
    expect(_ok(await _client(s).routeResidual('x', _skills)), isNull);
    await s.close(force: true);
  });

  test('200 skillId "none" -> Ok(null) abstain', () async {
    final s = await _serve((r) => _reply(r, 200, _text('{"skillId":"none"}')));
    expect(_ok(await _client(s).routeResidual('x', _skills)), isNull);
    await s.close(force: true);
  });

  test('leaked "none" slot value normalized to null', () async {
    final s = await _serve((r) => _reply(
        r,
        200,
        _text(
            '{"skillId":"create-task","slots":{"description":"x","dueDate":"none"}}')));
    final res = _ok(await _client(s).routeResidual('x', _skills));
    expect(res?['slots']['dueDate'], isNull);
    await s.close(force: true);
  });

  test('401 -> CloudError.badKey (actionable)', () async {
    final s =
        await _serve((r) => _reply(r, 401, '{"error":"invalid x-api-key"}'));
    expect(_errKind(await _client(s).routeResidual('x', _skills)),
        CloudErrorKind.badKey);
    await s.close(force: true);
  });

  test('429 -> CloudError.rateLimited', () async {
    final s = await _serve((r) => _reply(r, 429, 'rate limited'));
    expect(_errKind(await _client(s).routeResidual('x', _skills)),
        CloudErrorKind.rateLimited);
    await s.close(force: true);
  });

  test('500 -> CloudError.serverError', () async {
    final s = await _serve((r) => _reply(r, 500, 'boom'));
    expect(_errKind(await _client(s).routeResidual('x', _skills)),
        CloudErrorKind.serverError);
    await s.close(force: true);
  });

  test(
      '400 "credit balance too low" -> insufficientCredits (billing, not a bad key)',
      () async {
    final s = await _serve((r) => _reply(r, 400,
        '{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Claude API. Please go to Plans & Billing to purchase credits."}}'));
    expect(_errKind(await _client(s).routeResidual('x', _skills)),
        CloudErrorKind.insufficientCredits);
    await s.close(force: true);
  });

  test('validateKey probes the key and returns Ok on a 200', () async {
    final s = await _serve(
        (r) => _reply(r, 200, '{"content":[{"type":"text","text":"OK"}]}'));
    expect(await _client(s).validateKey(), isA<CloudOk<String>>());
    await s.close(force: true);
  });

  test('persistent admission controller blocks calls before HTTP', () async {
    var requests = 0;
    final server = await _serve((request) {
      requests++;
      _reply(request, 200, _text('OK'));
    });
    final dir = Directory.systemTemp.createTempSync('plenara_admission_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final usagePath = '${dir.path}/cloud-usage.json';
    final clock = () => DateTime.parse('2026-08-17T12:00:00');
    ClaudeClient client() => ClaudeClient(
          apiKeyOverride: 'test-key',
          url: 'http://127.0.0.1:${server.port}/v1/messages',
          admission: CloudAdmissionController(
            path: usagePath,
            clock: clock,
            dailyLimit: 1,
            burstLimit: 30,
          ),
        );

    expect(await client().validateKey(), isA<CloudOk<String>>());
    final blocked = await client().validateKey();

    expect(blocked, isA<CloudError<String>>());
    expect((blocked as CloudError<String>).kind, CloudErrorKind.rateLimited);
    expect(requests, 1, reason: 'the rejected call must never reach HTTP');
    expect(File(usagePath).existsSync(), isTrue);
    await server.close(force: true);
  });

  test('a corrupt admission ledger fails closed before HTTP', () async {
    var requests = 0;
    final server = await _serve((request) {
      requests++;
      _reply(request, 200, _text('OK'));
    });
    final dir =
        Directory.systemTemp.createTempSync('plenara_admission_corrupt_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final usagePath = '${dir.path}/cloud-usage.json';
    File(usagePath).writeAsStringSync('{not valid json');
    final admission = CloudAdmissionController(path: usagePath);
    final client = ClaudeClient(
      apiKeyOverride: 'test-key',
      url: 'http://127.0.0.1:${server.port}/v1/messages',
      admission: admission,
    );

    final blocked = await client.validateKey();

    expect(blocked, isA<CloudError<String>>());
    expect((blocked as CloudError<String>).kind, CloudErrorKind.rateLimited);
    expect(requests, 0, reason: 'corrupt spend state must fail closed');
    expect(admission.snapshot().dailyUsed, admission.dailyLimit);
    await server.close(force: true);
  });

  test('classifyHttp maps status+body to typed errors (pure, unit-level)', () {
    expect(classifyHttp(200, '{}'), isNull);
    expect(classifyHttp(401, 'invalid x-api-key'), CloudErrorKind.badKey);
    expect(classifyHttp(400, 'Your credit balance is too low'),
        CloudErrorKind.insufficientCredits);
    expect(classifyHttp(429, 'rate limited'), CloudErrorKind.rateLimited);
    expect(classifyHttp(429, 'please purchase credits'),
        CloudErrorKind.insufficientCredits);
    expect(classifyHttp(500, 'boom'), CloudErrorKind.serverError);
    // a plain (non-billing) 400 is a serverError, and a 5xx that merely mentions billing is NOT
    // insufficientCredits (would wrongly tell the user to add credits) — Fable review.
    expect(classifyHttp(400, 'invalid parameter: max_tokens'),
        CloudErrorKind.serverError);
    expect(classifyHttp(503, 'billing subsystem unavailable'),
        CloudErrorKind.serverError);
  });

  test(
      'usage tokens accumulate from a 200; costUsd math is correct (Haiku 4.5 pricing)',
      () async {
    final s = await _serve((r) => _reply(r, 200,
        '{"content":[{"type":"text","text":"OK"}],"usage":{"input_tokens":1000,"output_tokens":50}}'));
    final c = _client(s);
    await c.validateKey();
    expect(c.inTokens, 1000);
    expect(c.outTokens, 50);
    expect(ClaudeClient.costUsd(1000, 50),
        closeTo((1000 * 1.0 + 50 * 5.0) / 1e6, 1e-12));
    expect(c.spentUsd, closeTo(ClaudeClient.costUsd(1000, 50), 1e-12));
    await s.close(force: true);
  });

  test('a 200 with NO usage payload does not crash and accumulates nothing',
      () async {
    final s = await _serve(
        (r) => _reply(r, 200, '{"content":[{"type":"text","text":"OK"}]}'));
    final c = _client(s);
    expect(await c.validateKey(), isA<CloudOk<String>>());
    expect(c.inTokens, 0);
    await s.close(force: true);
  });

  test('malformed JSON body -> CloudError.malformed', () async {
    final s = await _serve((r) => _reply(r, 200, 'definitely not json'));
    expect(_errKind(await _client(s).routeResidual('x', _skills)),
        CloudErrorKind.malformed);
    await s.close(force: true);
  });

  test('authorCapability: good -> Ok({type, skill})', () async {
    final s = await _serve((r) => _reply(
        r, 200, _text('{"type":{"typeId":"t"},"skill":{"skillId":"s"}}')));
    final a = _ok(await _client(s).authorCapability('thing'));
    expect(a?['type'], isA<Map>());
    expect((a?['skill'] as Map)['skillId'], 's');
    await s.close(force: true);
  });

  test('authorCapability: non-map type/skill -> CloudError.malformed',
      () async {
    final s =
        await _serve((r) => _reply(r, 200, _text('{"type":"x","skill":1}')));
    expect(_errKind(await _client(s).authorCapability('thing')),
        CloudErrorKind.malformed);
    await s.close(force: true);
  });

  test('admission: future-dated ledger entries still count and are never erased (clock rollback)',
      () async {
    final dir = Directory.systemTemp.createTempSync('plenara_admission_future_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final usagePath = '${dir.path}/cloud-usage.json';
    // Two admissions stamped AFTER the current clock — a DST shift, NTP step, or
    // manual rollback. Dropping them (and rewriting them out of the file, as the
    // old filter did) would erase real spend history and fail the cap OPEN.
    const future = ['2026-08-17T13:00:00.000', '2026-08-17T13:01:00.000'];
    File(usagePath).writeAsStringSync(
        jsonEncode({'version': 1, 'admittedAt': future}));
    final c = CloudAdmissionController(
      path: usagePath,
      clock: () => DateTime.parse('2026-08-17T12:00:00'),
      dailyLimit: 3,
      burstLimit: 30,
    );
    expect(c.snapshot().dailyUsed, 2, reason: 'future entries count as spend');
    expect(c.admit(), isTrue); // 2 + this one = 3, at the cap
    expect(c.admit(), isFalse, reason: 'the cap holds despite the rollback');
    final raw = File(usagePath).readAsStringSync();
    for (final stamp in future) {
      expect(raw, contains(stamp),
          reason: 'a rewrite must never erase spend history');
    }
  });

  test('admission: the burst window is a pure rolling 10 minutes across local midnight',
      () async {
    final dir = Directory.systemTemp.createTempSync('plenara_admission_burst_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final usagePath = '${dir.path}/cloud-usage.json';
    // Three admissions just BEFORE midnight, clock now just after: all inside
    // the rolling 10-minute window, but on yesterday's side of the day boundary.
    // The old daily-then-burst filter reset the burst at midnight, allowing up
    // to 2× burstLimit in the straddling window.
    File(usagePath).writeAsStringSync(jsonEncode({
      'version': 1,
      'admittedAt': [
        '2026-08-17T23:56:00.000',
        '2026-08-17T23:58:00.000',
        '2026-08-17T23:59:00.000',
      ],
    }));
    var now = DateTime.parse('2026-08-18T00:04:00');
    final c = CloudAdmissionController(
      path: usagePath,
      clock: () => now,
      dailyLimit: 100,
      burstLimit: 3,
    );
    expect(c.snapshot().burstUsed, 3);
    expect(c.admit(), isFalse,
        reason: 'midnight must not reset the burst window');
    // Slide past the window: only the 23:59 admission is still inside it.
    now = DateTime.parse('2026-08-18T00:08:30');
    expect(c.snapshot().burstUsed, 1);
    expect(c.admit(), isTrue, reason: 'the sliding window re-admits');
  });

  test('HandshakeException/TlsException/HttpException -> offline (transient network, not malformed)',
      () async {
    // A captive portal or MITM proxy breaks the TLS handshake; a dropped
    // connection surfaces as HttpException. Both are connectivity stories with
    // retry semantics — the old catch-all mapped them to malformed ("couldn't
    // be parsed"), the wrong user story AND the wrong retry behavior.
    expect(await _kindWhenTransportThrows(const HandshakeException('boom')),
        CloudErrorKind.offline);
    expect(await _kindWhenTransportThrows(const TlsException('cert invalid')),
        CloudErrorKind.offline);
    expect(
        await _kindWhenTransportThrows(
            const HttpException('connection closed before full header')),
        CloudErrorKind.offline);
    // and the neighbors keep their mappings
    expect(
        await _kindWhenTransportThrows(
            const SocketException('network unreachable')),
        CloudErrorKind.offline);
    expect(await _kindWhenTransportThrows(const FormatException('bad')),
        CloudErrorKind.malformed);
  });

  test('routeResidual serializes EVERY shipped skill + known contacts into the prompt (request-body guard)',
      () async {
    String? captured;
    final s = await _serve((r) async {
      captured = await utf8.decoder.bind(r).join();
      _reply(r, 200, _text('{"skillId":"none"}'));
    });
    await _client(s).routeResidual('please do the thing', _skills,
        knownContacts: {'Katherine Zinger'});
    await s.close(force: true);
    final body = jsonDecode(captured!) as Map<String, dynamic>;
    final user = ((body['messages'] as List).first as Map)['content'] as String;
    expect(_skills.keys, isNotEmpty, reason: 'sanity: shipped skills loaded');
    for (final skillId in _skills.keys) {
      expect(user, contains(skillId),
          reason: 'the residual prompt must offer the FULL inventory ($skillId)');
    }
    expect(user, contains('"Katherine Zinger"'),
        reason: 'known contacts steer entity resolution');
    expect(user, contains('please do the thing'));
    expect(body['system'], contains('intent router'));
  });

  test('connection refused -> CloudError.offline, no throw', () async {
    final c = ClaudeClient(
        apiKeyOverride: 'k', url: 'http://127.0.0.1:1/v1/messages');
    expect(
        _errKind(await c.routeResidual('x', _skills)), CloudErrorKind.offline);
  });

  test('empty key -> CloudError.noKey with no network call', () async {
    final c =
        ClaudeClient(apiKeyOverride: '', url: 'http://127.0.0.1:1/unused');
    expect(c.available, isFalse);
    expect(_errKind(await c.routeResidual('x', _skills)), CloudErrorKind.noKey);
    expect(_errKind(await c.authorCapability('x')), CloudErrorKind.noKey);
  });
}
