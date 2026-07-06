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

class ClaudeClient {
  final String? key = apiKey();
  bool get available => key != null;

  static const _sys =
      'You are the intent router for a personal-assistant app. Given the user\'s '
      'utterance and the app\'s full capability inventory (each with an id, a '
      'description, and its input slot names), respond with ONLY a JSON object: '
      '{"skillId": "<id or none>", "slots": {<slotName>: <literal value>, ...}}. '
      'Pick the single best capability and extract its input slots as literal '
      'values from the utterance (dates as YYYY-MM-DD; numeric quantities like a '
      'distance as a plain number with no unit, e.g. 6 not "6k"). Use "none" if it '
      'is not one of these capabilities or is a general/world question. Output only JSON.';

  /// Full-inventory residual routing. Returns {skillId, slots} or null.
  Future<Map<String, dynamic>?> routeResidual(
      String utterance, Map<String, Map<String, dynamic>> skills) async {
    if (key == null) return null;
    final inv = skills.values.map((s) {
      final ins = (s['inputs'] as List? ?? []).map((i) => i['name']).join(', ');
      return '- ${s['skillId']}: ${s['displayName']} (inputs: ${ins.isEmpty ? 'none' : ins})';
    }).join('\n');
    final body = jsonEncode({
      'model': 'claude-haiku-4-5',
      'max_tokens': 200,
      'system': _sys,
      'messages': [
        {'role': 'user', 'content': 'Capabilities:\n$inv\n\nUtterance: "$utterance"\n\nJSON:'}
      ],
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.parse('https://api.anthropic.com/v1/messages'));
      req.headers
        ..set('x-api-key', key!)
        ..set('anthropic-version', '2023-06-01')
        ..contentType = ContentType.json;
      req.add(utf8.encode(body));
      final resp = await req.close();
      final raw = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) return null;
      final text = ((jsonDecode(raw)['content'] as List)[0]['text'] as String).trim();
      final jsonStr = RegExp(r'\{.*\}', dotAll: true).firstMatch(text)?.group(0);
      if (jsonStr == null) return null;
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (parsed['skillId'] == null || parsed['skillId'] == 'none') return null;
      if (!skills.containsKey(parsed['skillId'])) return null;
      return {
        'skillId': parsed['skillId'],
        'slots': (parsed['slots'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
        'source': 'cloud',
      };
    } on Exception {
      return null;
    } finally {
      client.close();
    }
  }
}
