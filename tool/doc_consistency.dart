import 'dart:io';

/// Cheap, deterministic guards for cross-document claims that must not drift.
///
/// This is intentionally narrower than prose review: it protects exact invariants
/// that have already drifted once, and verifies every relative Markdown link in
/// the active documentation set.
void main() {
  final root = _repoRoot();
  final errors = <String>[];

  const activeDocs = <String>[
    'README.md',
    'app/README.md',
    'CLAUDE.md',
    'DOGFOOD.md',
    'PRIVACY.md',
    'RELEASING.md',
    'TESTFLIGHT.md',
    'WORK-CAPSULE.md',
    'planning/implementation-plan-2026-08-17.md',
    'planning/plenara_research.md',
    'planning/specs/01-meta-schema-type-system.md',
    'planning/specs/02-skill-dsl.md',
    'planning/specs/03-nlu-intent.md',
    'planning/specs/04-architecture.md',
    'planning/specs/05-functional.md',
    'planning/specs/06-data-sync.md',
    'planning/specs/07-ui-design-language.md',
    'planning/specs/08-ai-cost-privacy.md',
    'planning/specs/09-test.md',
    'planning/specs/10-security-privacy-threat-model.md',
    'planning/specs/11-feedback-diagnostics.md',
    'planning/specs/12-voice.md',
    'planning/specs/13-reference-knowledge-bases.md',
    'planning/specs/14-voice-input.md',
    'planning/specs/15-presence.md',
    'planning/specs/16-routines.md',
    'planning/specs/17-living-planner.md',
    'planning/specs/storage-sync-assessment.md',
  ];

  var linkCount = 0;
  final markdownLink = RegExp(r'\[[^\]]+\]\(([^)]+)\)');
  for (final relative in activeDocs) {
    final file = File('${root.path}/$relative');
    if (!file.existsSync()) {
      errors.add('$relative: active document is missing');
      continue;
    }
    final text = file.readAsStringSync();
    for (final match in markdownLink.allMatches(text)) {
      var target = match.group(1)!.trim();
      if (target.startsWith('<') && target.endsWith('>')) {
        target = target.substring(1, target.length - 1);
      }
      if (target.startsWith('http://') ||
          target.startsWith('https://') ||
          target.startsWith('mailto:') ||
          target.startsWith('#') ||
          target.startsWith('/')) {
        continue;
      }
      // Local links in these docs do not use Markdown titles. Decode the only
      // escape needed by the repository and ignore an optional anchor.
      target = target.split('#').first.replaceAll('%20', ' ');
      if (target.isEmpty) continue;
      linkCount++;
      final resolved = File('${file.parent.path}/$target');
      final directory = Directory('${file.parent.path}/$target');
      if (!resolved.existsSync() && !directory.existsSync()) {
        errors.add('$relative: broken relative link `$target`');
      }
    }
  }

  const staleClaims = <String, List<String>>{
    'CLAUDE.md': ['Text/subtitles are overlays — UI is never compromised'],
    'PRIVACY.md': [
      'Credentials, raw audio, and interim speech transcripts are excluded',
    ],
    'DOGFOOD.md': [
      '"apiKey": "sk-ant',
      'Optional: the retrieval fallback wants',
    ],
    'planning/implementation-plan-2026-08-17.md': [
      'Increments 0–4 are implemented',
      'leaving the raw-audio and interim-transcript prohibitions unchanged',
    ],
    'planning/plenara_research.md': [
      'The visual design of the main UI is never altered to accommodate',
    ],
    'planning/specs/02-skill-dsl.md': [
      '"compiledFormVersion": 1',
      'The action plan is persisted in the compiled numeric form',
    ],
    'planning/specs/04-architecture.md': ['Plenara is push-to-talk-first'],
    'planning/specs/07-ui-design-language.md': ['assumes push-to-talk (v1)'],
    'planning/specs/10-security-privacy-threat-model.md': [
      'v0: in-memory ring only',
      'ten operations',
      'two-layer enforcement',
    ],
    'planning/specs/11-feedback-diagnostics.md': [
      'repeated in the app greeting',
      'rotation (D12) is still pending',
    ],
    'planning/specs/12-voice.md': ['### 3.1 Push-to-talk is primary'],
    'planning/specs/06-data-sync.md': [
      'index/                              ← CapabilityIndex binaries',
      'Hydration parses run on the IO/crypto worker isolates',
    ],
  };
  var staleChecks = 0;
  for (final entry in staleClaims.entries) {
    final text = File('${root.path}/${entry.key}').readAsStringSync();
    for (final claim in entry.value) {
      staleChecks++;
      if (text.contains(claim)) {
        errors.add('${entry.key}: retired claim returned: `$claim`');
      }
    }
  }

  const archiveDocs = <String>[
    'HANDOFF.md',
    'SESSION-HANDOFF.md',
    'TRANSITION.md',
  ];
  for (final relative in archiveDocs) {
    final text = File('${root.path}/$relative').readAsStringSync();
    if ((!text.contains('Historical') && !text.contains('Archived')) ||
        !text.contains('WORK-CAPSULE.md')) {
      errors.add(
        '$relative: historical banner or current-state pointer is missing',
      );
    }
  }

  final engineKinds = _setLiteral(
    File('${root.path}/v0/lib/claude.dart').readAsStringSync(),
    r'static const _generativeKinds\s*=\s*\{([\s\S]*?)\};',
    'v0/lib/claude.dart _generativeKinds',
    errors,
  );
  final assemblerKinds = _mapKeys(
    File('${root.path}/v0/lib/generative.dart').readAsStringSync(),
    r'const generativeDataClasses\s*=\s*<String, Set<String>>\{([\s\S]*?)\n\};',
    'v0/lib/generative.dart generativeDataClasses',
    errors,
  );
  final settingsKinds = _mapKeys(
    File('${root.path}/app/lib/settings_view.dart').readAsStringSync(),
    r'static const _cloudNames\s*=\s*<String, String>\{([\s\S]*?)\n  \};',
    'app/lib/settings_view.dart _cloudNames',
    errors,
  );
  final specText = File(
    '${root.path}/planning/specs/08-ai-cost-privacy.md',
  ).readAsStringSync();
  final marker = RegExp(
    r'IMPLEMENTED_GENERATIVE_KINDS:\s*([^\n-]+)',
  ).firstMatch(specText);
  final specKinds = marker == null
      ? <String>{}
      : marker
            .group(1)!
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet();
  if (marker == null) {
    errors.add(
      'planning/specs/08-ai-cost-privacy.md: implemented-kind marker is missing',
    );
  }
  _sameSet('cloud engine', engineKinds, 'assemblers', assemblerKinds, errors);
  _sameSet(
    'cloud engine',
    engineKinds,
    'Settings labels',
    settingsKinds,
    errors,
  );
  _sameSet('cloud engine', engineKinds, 'Spec 08 marker', specKinds, errors);

  stdout.writeln(
    'doc consistency: ${activeDocs.length} active docs, $linkCount relative links, '
    '$staleChecks retired-claim guards, ${engineKinds.length} cloud kinds',
  );
  stdout.writeln('cloud kinds: ${(engineKinds.toList()..sort()).join(', ')}');
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln('!! $error');
    }
    exitCode = 1;
  }
}

Directory _repoRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (Directory('${current.path}/.git').existsSync()) return current;
    if (current.parent.path == current.path) {
      stderr.writeln('Run this tool inside the Plenara repository.');
      exit(2);
    }
    current = current.parent;
  }
}

Set<String> _setLiteral(
  String text,
  String pattern,
  String label,
  List<String> errors,
) {
  final body = RegExp(pattern).firstMatch(text)?.group(1);
  if (body == null) {
    errors.add('$label: declaration not found');
    return {};
  }
  return RegExp(
    r"'([^']+)'",
  ).allMatches(body).map((match) => match.group(1)!).toSet();
}

Set<String> _mapKeys(
  String text,
  String pattern,
  String label,
  List<String> errors,
) {
  final body = RegExp(pattern).firstMatch(text)?.group(1);
  if (body == null) {
    errors.add('$label: declaration not found');
    return {};
  }
  return RegExp(
    r"^\s*'([^']+)'\s*:",
    multiLine: true,
  ).allMatches(body).map((match) => match.group(1)!).toSet();
}

void _sameSet(
  String leftLabel,
  Set<String> left,
  String rightLabel,
  Set<String> right,
  List<String> errors,
) {
  if (left.length == right.length && left.containsAll(right)) return;
  final missing = left.difference(right).toList()..sort();
  final extra = right.difference(left).toList()..sort();
  errors.add(
    '$rightLabel differs from $leftLabel '
    '(missing: ${missing.isEmpty ? 'none' : missing.join(', ')}; '
    'extra: ${extra.isEmpty ? 'none' : extra.join(', ')})',
  );
}
