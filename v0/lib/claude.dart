/// Plenara v0 — the ClaudeClient (Spec 04 §3.5). The single cloud seam. Used for
/// RESIDUAL routing (findings §13 E4) and authoring, turning a novel phrasing the
/// corpus/retrieval can't handle into a route+slots — online only, BYOK.
///
/// Failures are TYPED, never exceptions and never a bare null (Spec 04 §3.5): every
/// call returns a [CloudResult] — [CloudOk] carrying the value (a route/authored
/// capability, or a null value meaning the model deliberately ABSTAINED), or
/// [CloudError] naming WHY (offline / bad key / rate-limited / …). The caller can
/// then tell the user the truth instead of silently degrading to "I didn't catch
/// that" (the no-silent-failure principle, at the seam where it matters most).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Why a cloud call could not produce an answer. `noKey`/`badKey` are actionable
/// by the user; `offline`/`timeout`/`rateLimited`/`serverError` are transient;
/// `malformed` means a 200 whose body we couldn't turn into a decision.
enum CloudErrorKind { noKey, offline, timeout, badKey, rateLimited, serverError, malformed }

/// Result of a cloud call — a value or a named failure, never a thrown exception.
sealed class CloudResult<T> {
  const CloudResult();
}

/// Success. A null [value] from a router call means the model ABSTAINED ("none") —
/// a real answer ("not one of my capabilities"), distinct from never hearing back.
final class CloudOk<T> extends CloudResult<T> {
  final T value;
  const CloudOk(this.value);
}

/// A named failure. [detail] is for logs, never required for the user message.
final class CloudError<T> extends CloudResult<T> {
  final CloudErrorKind kind;
  final String? detail;
  const CloudError(this.kind, [this.detail]);
}

String? apiKey() {
  final env = Platform.environment['ANTHROPIC_API_KEY'];
  if (env != null && env.isNotEmpty) return env.trim();
  // v0 dev convenience for the rig (tests/recorder run from v0/): read the BYOK key
  // from the gitignored rig .env via a RELATIVE path only. A machine-specific
  // absolute path was removed deliberately — baked into the app binary it would let
  // the production app silently borrow the rig key and mask a real noKey/badKey.
  final f = File('../planning/specs/05a-rig/.env');
  if (f.existsSync()) {
    for (final line in f.readAsLinesSync()) {
      if (line.startsWith('ANTHROPIC_API_KEY')) {
        return line.split('=')[1].trim().replaceAll('"', '').replaceAll("'", '');
      }
    }
  }
  return null;
}

/// The single cloud seam, as an interface so callers can inject a replay/mock
/// implementation (lib/replay_cloud.dart) instead of hitting the network in tests.
abstract interface class CloudClient {
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
      String utterance, Map<String, Map<String, dynamic>> skills);
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String description, {String? priorError});

  /// Free-text generation for a grounded generative kind (Spec 04 §3.10) — e.g.
  /// 'gift_ideas', 'briefing'. [context] is the grounded facts assembled by the caller;
  /// the model must use ONLY those. Returns the assistant text, or a typed CloudError.
  Future<CloudResult<String>> generate(String kind, String context);
}

class ClaudeClient implements CloudClient {
  final String? key;
  final String _url;
  ClaudeClient({String? apiKeyOverride, String? url})
      : key = apiKeyOverride ?? apiKey(),
        _url = url ?? 'https://api.anthropic.com/v1/messages';
  bool get available => key != null && key!.isNotEmpty;

  static const _sys =
      'You are the intent router for a personal-assistant app. Given the user\'s '
      'utterance and the app\'s full capability inventory (each with an id, a '
      'description, and its input slot names), respond with ONLY a JSON object: '
      '{"skillId": "<id or none>", "slots": {<slotName>: <literal value>, ...}}. '
      'Pick the single best capability and extract its input slots from the '
      'utterance. Rules: dates as YYYY-MM-DD; a numeric quantity like a distance '
      'as a plain number with no unit (6 not "6k"); a TEXT slot (a mood rating, a '
      'name, a description) is the user\'s OWN words verbatim — never a number or a '
      'paraphrase; use JSON null (not the string "none") for a slot with no value. '
      'Use skillId "none" if it is not one of these capabilities or is a '
      'general/world question. Output only JSON.';

  static const _authorSys = '''
You author capabilities for a personal-assistant app as DATA (never code). Given a
described need, output ONLY a JSON object: {"type": <typeDef>, "skill": <skillDef>}.

typeDef: {"typeId","displayName","attributes":[{"name","valueType","required",("default"?)}]}
  valueType in: text|number|decimal|date|datetime|boolean|duration|enum (Spec 01 §3; use `number`
  for approximate quantities, `decimal` only for money, `duration` for time spans in seconds).
  Always include a "loggedAt" date attribute (required:true).

skillDef uses ONLY this closed op vocabulary:
  {"op":"compute","fn":<now|today|format_date|add|count>,"args":[...],"into":"var"}
  {"op":"write_record","typeId":"...","fields":{"<attr>":{"var":"<slot>"}|<literal>},"into":"var"}
  {"op":"format","template":"... {slotOrVar} ...","into":"confirmationText"}
Shape: {"skillId","displayName","reads":[<typeIds read>],"writes":[<typeIds written>],"inputs":[{"name","required"}],"examplePhrases":[3 strings],"steps":{"main":[<ops>]}}
Author a LOGGING skill: compute today into a var, write_record capturing the input value(s) + that date
into the type, then a format op that sets "confirmationText". Reference inputs as {"var":"<slotName>"}.
"reads" is [] and "writes" is [the new typeId] for a logging skill. Output only JSON, no prose.''';

  /// Author a new type + skill from a described need (Spec 02 §6). Ok({type, skill})
  /// on success, or a typed CloudError. Deterministic validation happens in the caller.
  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String description, {String? priorError}) async {
    final fix = priorError == null
        ? ''
        : '\nYour previous attempt FAILED deterministic validation with: "$priorError". '
            'Return corrected JSON that fixes exactly that.';
    final res = await _message(_authorSys, 'Capability to build: "$description"$fix', maxTokens: 900);
    switch (res) {
      case CloudError(:final kind, :final detail):
        return CloudError(kind, detail);
      case CloudOk(:final value):
        final type = value['type'], skill = value['skill'];
        if (type is! Map || skill is! Map) {
          return const CloudError(CloudErrorKind.malformed, 'response was not a {type, skill} capability');
        }
        return CloudOk({'type': type.cast<String, dynamic>(), 'skill': skill.cast<String, dynamic>()});
    }
  }

  /// The single HTTP path. NEVER throws (Spec 04 §3.5): every failure maps to a
  /// typed [CloudError]. On 200 with a usable JSON object, [CloudOk] of that object.
  /// The raw text-returning HTTP path. NEVER throws (Spec 04 §3.5): every failure maps
  /// to a typed [CloudError]. On 200 with a usable text block, [CloudOk] of that text.
  /// [_message] (JSON) and [generate] (free text) both build on this.
  Future<CloudResult<String>> _rawText(String sys, String user, {int maxTokens = 200}) async {
    if (key == null || key!.isEmpty) return const CloudError(CloudErrorKind.noKey);
    final body = jsonEncode({
      'model': 'claude-haiku-4-5',
      'max_tokens': maxTokens,
      'system': sys,
      'messages': [{'role': 'user', 'content': user}],
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      return await Future(() async {
        final req = await client.postUrl(Uri.parse(_url));
        req.headers
          ..set('x-api-key', key!)
          ..set('anthropic-version', '2023-06-01')
          ..contentType = ContentType.json;
        req.add(utf8.encode(body));
        final resp = await req.close();
        final raw = await resp.transform(utf8.decoder).join();
        final code = resp.statusCode;
        if (code == 401 || code == 403) return CloudError<String>(CloudErrorKind.badKey, 'HTTP $code');
        if (code == 429) return const CloudError<String>(CloudErrorKind.rateLimited);
        if (code != 200) return CloudError<String>(CloudErrorKind.serverError, 'HTTP $code');
        final decoded = jsonDecode(raw);
        final content = decoded is Map ? decoded['content'] : null;
        if (content is! List) return const CloudError<String>(CloudErrorKind.malformed, 'no content array');
        final block = content.firstWhere(
            (b) => b is Map && b['type'] == 'text' && b['text'] is String,
            orElse: () => null);
        if (block == null) return const CloudError<String>(CloudErrorKind.malformed, 'no text block (refusal?)');
        return CloudOk<String>((block['text'] as String).trim());
      }).timeout(const Duration(seconds: 30)); // bounds the whole exchange, not just connect
    } on TimeoutException catch (_) {
      return const CloudError(CloudErrorKind.timeout);
    } on SocketException catch (e) {
      return CloudError(CloudErrorKind.offline, e.message);
    } catch (e) {
      return CloudError(CloudErrorKind.malformed, e.toString());
    } finally {
      client.close();
    }
  }

  /// JSON path (routing/authoring): extracts the first JSON object from the model text.
  Future<CloudResult<Map<String, dynamic>>> _message(String sys, String user, {int maxTokens = 200}) async {
    switch (await _rawText(sys, user, maxTokens: maxTokens)) {
      case CloudError(:final kind, :final detail):
        return CloudError(kind, detail);
      case CloudOk(:final value):
        try {
          final jsonStr = RegExp(r'\{.*\}', dotAll: true).firstMatch(value)?.group(0);
          if (jsonStr == null) return const CloudError(CloudErrorKind.malformed, 'no JSON object in text');
          final obj = jsonDecode(jsonStr);
          if (obj is! Map<String, dynamic>) {
            return const CloudError(CloudErrorKind.malformed, 'JSON was not an object');
          }
          return CloudOk<Map<String, dynamic>>(obj);
        } catch (e) {
          return CloudError(CloudErrorKind.malformed, e.toString());
        }
    }
  }

  static const _genSys = <String, String>{
    'gift_ideas':
        'You suggest thoughtful gift ideas for someone the user cares about. Use ONLY the '
        'facts provided about them — never invent details. Give 3-4 concrete ideas, each '
        'tied to a specific fact ("because they …"). If the facts are thin, say so honestly '
        'and suggest what to learn. Warm, concise, plain text (no preamble).',
    'briefing':
        'You write a short, warm daily briefing from the user\'s own data provided below. '
        'Use ONLY what is given — never invent. Lead with what needs attention today '
        '(due/overdue, reminders, birthdays), then a brief encouraging note. Plain text, concise.',
    'reconnect':
        'You help the user reconnect with someone they care about. Using ONLY the facts and '
        'the time-since-last-contact provided, suggest 2-3 warm, specific ways to reach out '
        '(reference a real shared detail; if it has been a while, acknowledge that gently). '
        'Never invent facts. Warm, concrete, plain text.',
  };

  @override
  Future<CloudResult<String>> generate(String kind, String context) =>
      _rawText(_genSys[kind] ?? 'You are a warm, grounded personal assistant. Use ONLY the facts given.',
          context, maxTokens: 400);

  static const _sentinels = {'none', 'null', ''};

  /// Full-inventory residual routing. Ok({skillId, slots}) on a route, Ok(null) when
  /// the model abstains (or names an id we don't have), or a typed CloudError.
  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
      String utterance, Map<String, Map<String, dynamic>> skills) async {
    final inv = skills.values.map((s) {
      final ins = (s['inputs'] as List? ?? []).map((i) => i['name']).join(', ');
      return '- ${s['skillId']}: ${s['displayName']} (inputs: ${ins.isEmpty ? 'none' : ins})';
    }).join('\n');
    final res = await _message(_sys, 'Capabilities:\n$inv\n\nUtterance: "$utterance"\n\nJSON:');
    switch (res) {
      case CloudError(:final kind, :final detail):
        return CloudError(kind, detail);
      case CloudOk(:final value):
        final parsed = value;
        if (parsed['skillId'] == null || parsed['skillId'] == 'none' || !skills.containsKey(parsed['skillId'])) {
          return const CloudOk<Map<String, dynamic>?>(null); // the model abstained
        }
        final slots = (parsed['slots'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        // the model sometimes leaks the 'none' sentinel into a slot value; normalize
        // those to a real null so they can't crash a downstream resolver.
        slots.updateAll((k, v) =>
            (v is String && _sentinels.contains(v.trim().toLowerCase())) ? null : v);
        return CloudOk<Map<String, dynamic>?>({'skillId': parsed['skillId'], 'slots': slots, 'source': 'cloud'});
    }
  }
}
