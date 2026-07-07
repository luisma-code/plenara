/// Plenara v0 — the ClaudeClient (Spec 04 §3.5). The single cloud seam. Used
/// here for RESIDUAL routing (findings §13 E4: Haiku over the full inventory ~94%
/// on cold-start), turning a novel phrasing the corpus/retrieval can't handle
/// into a real route+slots — online only, BYOK. Offline or keyless -> null, and
/// the caller degrades to clarify (no silent failure; the free tier never blocks).
library;

import 'dart:convert';
import 'dart:io';

String? apiKey() {
  final env = Platform.environment['ANTHROPIC_API_KEY'];
  if (env != null && env.isNotEmpty) return env.trim();
  // v0 dev convenience: read the BYOK key from the rig's gitignored .env
  for (final p in const [
    '../planning/specs/05a-rig/.env',
    r'Z:\code\plenara\planning\specs\05a-rig\.env', // absolute fallback (UI runs from a build dir)
  ]) {
    final f = File(p);
    if (!f.existsSync()) continue;
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
  Future<Map<String, dynamic>?> routeResidual(
      String utterance, Map<String, Map<String, dynamic>> skills);
  Future<Map<String, dynamic>?> authorCapability(String description, {String? priorError});
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
  valueType in: text|date|decimal|integer|boolean. Always include a "loggedAt" date attribute (required:true).

skillDef uses ONLY this closed op vocabulary:
  {"op":"compute","fn":<now|today|format_date|add|count>,"args":[...],"into":"var"}
  {"op":"write_record","typeId":"...","fields":{"<attr>":{"var":"<slot>"}|<literal>},"into":"var"}
  {"op":"format","template":"... {slotOrVar} ...","into":"confirmation"}
Shape: {"skillId","displayName","inputs":[{"name","required"}],"examplePhrases":[3 strings],"steps":{"main":[<ops>]}}
Author a LOGGING skill: compute today into a var, write_record capturing the input value(s) + that date
into the type, then a format op that sets "confirmation". Reference inputs as {"var":"<slotName>"}.
Output only JSON, no prose.''';

  /// Author a new type + skill from a described need (Spec 02 §6). Returns
  /// {type, skill} maps, or null. Deterministic validation happens in the caller.
  @override
  Future<Map<String, dynamic>?> authorCapability(String description, {String? priorError}) async {
    final fix = priorError == null
        ? ''
        : '\nYour previous attempt FAILED deterministic validation with: "$priorError". '
            'Return corrected JSON that fixes exactly that.';
    final out = await _message(_authorSys, 'Capability to build: "$description"$fix', maxTokens: 900);
    if (out == null) return null;
    final type = out['type'], skill = out['skill'];
    if (type is! Map || skill is! Map) return null;
    return {'type': type.cast<String, dynamic>(), 'skill': skill.cast<String, dynamic>()};
  }

  /// The single HTTP path. NEVER throws (Spec 04 §3.5): any failure — offline,
  /// non-200, timeout, malformed/refusal (200 with empty or non-text content) —
  /// returns null. Extracts the first `text` block and the JSON object within it.
  Future<Map<String, dynamic>?> _message(String sys, String user, {int maxTokens = 200}) async {
    if (key == null || key!.isEmpty) return null;
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
        if (resp.statusCode != 200) return null;
        final decoded = jsonDecode(raw);
        final content = decoded is Map ? decoded['content'] : null;
        if (content is! List) return null; // refusal / unexpected shape
        final block = content.firstWhere(
            (b) => b is Map && b['type'] == 'text' && b['text'] is String,
            orElse: () => null);
        if (block == null) return null; // no text block (e.g. stop_reason: refusal)
        final jsonStr = RegExp(r'\{.*\}', dotAll: true).firstMatch((block['text'] as String).trim())?.group(0);
        return jsonStr == null ? null : jsonDecode(jsonStr) as Map<String, dynamic>;
      }).timeout(const Duration(seconds: 30)); // bounds the whole exchange, not just connect
    } catch (_) {
      return null; // catches Exception AND Error (e.g. a shape TypeError) and TimeoutException
    } finally {
      client.close();
    }
  }

  static const _sentinels = {'none', 'null', ''};

  /// Full-inventory residual routing. Returns {skillId, slots} or null.
  @override
  Future<Map<String, dynamic>?> routeResidual(
      String utterance, Map<String, Map<String, dynamic>> skills) async {
    final inv = skills.values.map((s) {
      final ins = (s['inputs'] as List? ?? []).map((i) => i['name']).join(', ');
      return '- ${s['skillId']}: ${s['displayName']} (inputs: ${ins.isEmpty ? 'none' : ins})';
    }).join('\n');
    final parsed = await _message(_sys, 'Capabilities:\n$inv\n\nUtterance: "$utterance"\n\nJSON:');
    if (parsed == null || parsed['skillId'] == null || parsed['skillId'] == 'none') return null;
    if (!skills.containsKey(parsed['skillId'])) return null;
    final slots = (parsed['slots'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    // the model sometimes leaks the 'none' sentinel into a slot value; normalize
    // those to a real null so they can't crash a downstream resolver.
    slots.updateAll((k, v) =>
        (v is String && _sentinels.contains(v.trim().toLowerCase())) ? null : v);
    return {'skillId': parsed['skillId'], 'slots': slots, 'source': 'cloud'};
  }
}
