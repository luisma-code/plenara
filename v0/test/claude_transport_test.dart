/// Transport-tier coverage for the live ClaudeClient paths that had none:
/// routine/figure authoring (Spec 16) against a local stub server, the _rawText
/// timeout branch, burst admission, Sonnet token accounting, the per-kind
/// generate() system prompts, and the max_tokens truncation flag. Every outcome
/// is a TYPED CloudResult (Spec 04 §3.5) — never a thrown exception.
import 'dart:convert';
import 'dart:io';

import 'package:plenara/claude.dart';
import 'package:test/test.dart';

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

String _text(String t, {String? stopReason}) => jsonEncode({
      'content': [
        {'type': 'text', 'text': t}
      ],
      if (stopReason != null) 'stop_reason': stopReason,
    });

// A realistic authored-routine payload: keys as the catalogue would carry them.
const _routineJson = '{"title":"Low-back loosener","focusArea":"lower back",'
    '"kind":"stretch","estMinutes":12,"steps":['
    '{"exerciseKey":"cat_cow","name":"Cat-cow","durationSeconds":60,"side":"both"},'
    '{"exerciseKey":"childs_pose","name":"Child\'s pose","durationSeconds":45,"side":"both"},'
    '{"exerciseKey":"supine_twist","name":"Supine twist","durationSeconds":40,"side":"alternating"},'
    '{"exerciseKey":"knee_to_chest","name":"Knee to chest","reps":8,"side":"left"}]}';

const _catalogue = 'cat_cow | Cat-cow | mobility | back | none\n'
    'childs_pose | Child\'s pose | stretch | back | none\n'
    'supine_twist | Supine twist | stretch | back | none\n'
    'knee_to_chest | Knee to chest | stretch | back | none';

void main() {
  group('authorRoutine (Spec 16) — typed results over the stub server', () {
    test('a good routine payload -> CloudOk(routine), request selects Sonnet',
        () async {
      String? captured;
      final s = await _serve((r) async {
        captured = await utf8.decoder.bind(r).join();
        _reply(r, 200, _text(_routineJson));
      });
      final res = await _client(s)
          .authorRoutine('something for my lower back', _catalogue);
      await s.close(force: true);
      expect(res, isA<CloudOk<Map<String, dynamic>>>());
      final routine = (res as CloudOk<Map<String, dynamic>>).value;
      expect(routine['title'], 'Low-back loosener');
      expect((routine['steps'] as List), hasLength(4));
      final body = jsonDecode(captured!) as Map<String, dynamic>;
      // Composition-class authoring runs on the STRONGER model (G-29), never the
      // Haiku router tier — a silent downgrade here degrades every routine.
      expect(body['model'], contains('sonnet'));
      expect(body['messages'].first['content'], contains('lower back'));
      expect(body['messages'].first['content'], contains('cat_cow'));
    });

    test('a payload with no steps array -> CloudError.malformed', () async {
      final s = await _serve(
          (r) => _reply(r, 200, _text('{"title":"empty routine"}')));
      final res = await _client(s).authorRoutine('x', _catalogue);
      await s.close(force: true);
      expect(res, isA<CloudError<Map<String, dynamic>>>());
      expect((res as CloudError<Map<String, dynamic>>).kind,
          CloudErrorKind.malformed);
    });

    test('a refusal shape (empty content) -> CloudError.malformed', () async {
      final s = await _serve((r) => _reply(
          r, 200, jsonEncode({'content': [], 'stop_reason': 'refusal'})));
      final res = await _client(s).authorRoutine('x', _catalogue);
      await s.close(force: true);
      expect((res as CloudError<Map<String, dynamic>>).kind,
          CloudErrorKind.malformed);
    });

    test('a 500 -> CloudError.serverError', () async {
      final s = await _serve((r) => _reply(r, 500, 'boom'));
      final res = await _client(s).authorRoutine('x', _catalogue);
      await s.close(force: true);
      expect((res as CloudError<Map<String, dynamic>>).kind,
          CloudErrorKind.serverError);
    });

    test('priorError is fed back into the re-author prompt', () async {
      String? captured;
      final s = await _serve((r) async {
        captured = await utf8.decoder.bind(r).join();
        _reply(r, 200, _text(_routineJson));
      });
      await _client(s).authorRoutine('x', _catalogue,
          priorError: 'step 2 exerciseKey not in catalogue');
      await s.close(force: true);
      expect(jsonDecode(captured!)['messages'].first['content'],
          contains('step 2 exerciseKey not in catalogue'));
    });
  });

  group('authorFigures (Spec 16 §2) — typed results over the stub server', () {
    test('a good figures payload -> CloudOk, request selects Sonnet', () async {
      String? captured;
      final s = await _serve((r) async {
        captured = await utf8.decoder.bind(r).join();
        _reply(
            r,
            200,
            _text(jsonEncode({
              'figures': [
                {
                  'name': 'Cat-cow',
                  'frameA': '<svg viewBox="0 0 100 100"></svg>',
                  'frameB': '<svg viewBox="0 0 100 100"></svg>'
                }
              ]
            })));
      });
      final res = await _client(s).authorFigures(['Cat-cow']);
      await s.close(force: true);
      expect(res, isA<CloudOk<Map<String, dynamic>>>());
      expect(
          ((res as CloudOk<Map<String, dynamic>>).value['figures'] as List)
              .single['name'],
          'Cat-cow');
      expect(jsonDecode(captured!)['model'], contains('sonnet'));
    });

    test('a rejected-SVG payload (figures not a list) -> typed malformed degrade',
        () async {
      // The model answered with a bare SVG instead of the figures array. The
      // client must DEGRADE typed (figures are presentation; the caller falls
      // back to text) — never throw, never pretend success.
      final s = await _serve((r) =>
          _reply(r, 200, _text('{"figures":"<svg viewBox=\\"0 0 100 100\\"/>"}')));
      final res = await _client(s).authorFigures(['Cat-cow']);
      await s.close(force: true);
      expect(res, isA<CloudError<Map<String, dynamic>>>());
      expect((res as CloudError<Map<String, dynamic>>).kind,
          CloudErrorKind.malformed);
    });

    test('a 500 -> CloudError.serverError, never an exception', () async {
      final s = await _serve((r) => _reply(r, 500, 'boom'));
      final res = await _client(s).authorFigures(['Cat-cow']);
      await s.close(force: true);
      expect((res as CloudError<Map<String, dynamic>>).kind,
          CloudErrorKind.serverError);
    });
  });

  group('the timeout branch of _rawText', () {
    test(
        'a hung server -> CloudErrorKind.timeout, and a LATE usage payload never increments the token counters',
        () async {
      HttpRequest? pending;
      final s = await _serve((r) {
        pending = r; // accept and never respond
      });
      final c = ClaudeClient(
          apiKeyOverride: 'test-key',
          url: 'http://127.0.0.1:${s.port}/v1/messages',
          requestTimeout: const Duration(milliseconds: 250));
      final res = await c.generate('briefing', 'Date: 2026-08-18');
      expect(res, isA<CloudError<String>>());
      expect((res as CloudError<String>).kind, CloudErrorKind.timeout);
      // The response lands AFTER the deadline. The timed-out request was
      // force-aborted, so its tokens must not be misattributed to the next
      // turn's cost snapshot (the regression the force-close guards against).
      try {
        pending?.response.write(
            '{"content":[{"type":"text","text":"late"}],"usage":{"input_tokens":999,"output_tokens":999}}');
        await pending?.response.close();
      } catch (_) {/* the aborted socket may already be gone */}
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(c.inTokens, 0, reason: 'late usage must not count');
      expect(c.outTokens, 0);
      await s.close(force: true);
    });
  });

  group('burst admission (in-memory ledger, injected clock)', () {
    test(
        'crossing burstLimit denies despite daily headroom; the sliding window re-admits; snapshot agrees',
        () {
      var now = DateTime.parse('2026-08-18T10:00:00');
      final c = CloudAdmissionController(
        clock: () => now,
        dailyLimit: 100, // never the binding constraint here
        burstLimit: 3,
      );
      expect(c.admit(), isTrue); // 10:00
      now = DateTime.parse('2026-08-18T10:03:00');
      expect(c.admit(), isTrue);
      now = DateTime.parse('2026-08-18T10:06:00');
      expect(c.admit(), isTrue);
      expect(c.snapshot().burstUsed, 3);
      now = DateTime.parse('2026-08-18T10:08:00');
      expect(c.admit(), isFalse, reason: '3 in the last 10 minutes = at the cap');
      expect(c.snapshot().burstUsed, 3);
      expect(c.snapshot().dailyUsed, 3, reason: 'the denial was never recorded');
      // 10:00 falls out of the window at 10:10:01 -> one slot frees up.
      now = DateTime.parse('2026-08-18T10:11:00');
      expect(c.snapshot().burstUsed, 2);
      expect(c.admit(), isTrue, reason: 'the window slides, not resets');
      expect(c.snapshot().burstUsed, 3);
    });
  });

  group('Sonnet token accounting', () {
    test(
        'authorRoutine usage lands on the SONNET counters and prices; Haiku counters untouched',
        () async {
      final s = await _serve((r) => _reply(
          r,
          200,
          jsonEncode({
            'content': [
              {'type': 'text', 'text': _routineJson}
            ],
            'usage': {'input_tokens': 2000, 'output_tokens': 400}
          })));
      final c = _client(s);
      await c.authorRoutine('x', _catalogue);
      await s.close(force: true);
      expect(c.sonnetInTokens, 2000);
      expect(c.sonnetOutTokens, 400);
      expect(c.inTokens, 0, reason: 'never the Haiku ledger');
      expect(c.outTokens, 0);
      // Sonnet pricing (3/15 per MTok), NOT Haiku (1/5): under-pricing the one
      // paid call in the feature made the running total untrustworthy.
      expect(c.spentUsd, closeTo((2000 * 3.0 + 400 * 15.0) / 1e6, 1e-12));
      expect(c.spentUsd, closeTo(ClaudeClient.sonnetCostUsd(2000, 400), 1e-12));
    });
  });

  group('generate() on the real client', () {
    test('the per-kind system prompt is actually sent', () async {
      String? captured;
      final s = await _serve((r) async {
        captured = await utf8.decoder.bind(r).join();
        _reply(r, 200, _text('Some warm ideas.'));
      });
      final res = await _client(s).generate('gift_ideas', 'Person: Sarah');
      await s.close(force: true);
      expect(res, isA<CloudOk<String>>());
      final body = jsonDecode(captured!) as Map<String, dynamic>;
      expect(body['system'], contains('thoughtful gift ideas'),
          reason: 'the reviewed per-kind prompt, not a generic fallback');
      expect(body['messages'].first['content'], 'Person: Sarah');
      expect(body['model'], contains('haiku'));
    });

    test('an unknown kind -> typed error, and NO request is spent on it',
        () async {
      var requests = 0;
      final s = await _serve((r) {
        requests++;
        _reply(r, 200, _text('should never happen'));
      });
      final res = await _client(s).generate('mystery_kind', 'context');
      await s.close(force: true);
      expect(res, isA<CloudError<String>>());
      expect((res as CloudError<String>).kind, CloudErrorKind.malformed);
      expect(res.detail, contains('mystery_kind'));
      expect(requests, 0,
          reason: 'an unreviewed prompt path must never reach the network');
    });
  });

  group('max_tokens truncation is never silent (plain-text path)', () {
    test('stop_reason max_tokens -> CloudOk.truncated is true', () async {
      final s = await _serve((r) => _reply(r, 200,
          _text('Here are some ideas: first,', stopReason: 'max_tokens')));
      final res = await _client(s).generate('gift_ideas', 'Person: Sarah');
      await s.close(force: true);
      expect(res, isA<CloudOk<String>>());
      final ok = res as CloudOk<String>;
      expect(ok.value, contains('first'));
      expect(ok.truncated, isTrue,
          reason: 'a mid-sentence cut must be visible to the caller');
    });

    test('a normal end_turn stop -> truncated is false', () async {
      final s = await _serve((r) =>
          _reply(r, 200, _text('A complete answer.', stopReason: 'end_turn')));
      final res = await _client(s).generate('gift_ideas', 'Person: Sarah');
      await s.close(force: true);
      expect((res as CloudOk<String>).truncated, isFalse);
    });
  });
}
