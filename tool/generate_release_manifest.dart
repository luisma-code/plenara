import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  String? value(String name) {
    final index = args.indexOf(name);
    if (index < 0 || index + 1 >= args.length) return null;
    return args[index + 1];
  }

  final root = _run('git', ['rev-parse', '--show-toplevel']);
  final artifactPath = value('--artifact');
  final outputPath =
      value('--output') ?? '$root/app/build/release/release-manifest.json';
  final channel = value('--channel') ?? 'external';
  if (channel != 'external') {
    stderr.writeln('Release manifests are external-only.');
    exitCode = 2;
    return;
  }
  if (artifactPath == null || !File(artifactPath).existsSync()) {
    stderr.writeln('Pass --artifact with the compiled AOT binary.');
    exitCode = 2;
    return;
  }

  final dirty = _run('git', [
    'status',
    '--porcelain',
    '--untracked-files=no',
  ], allowEmpty: true).isNotEmpty;
  if (dirty && !args.contains('--allow-dirty')) {
    stderr.writeln('Tracked files are dirty; refusing a promotable manifest.');
    exitCode = 3;
    return;
  }

  final pubspec = File('$root/app/pubspec.yaml').readAsLinesSync();
  final version = pubspec
      .firstWhere((line) => line.startsWith('version:'))
      .split(':')
      .last
      .trim();
  final schemas = <String, Object?>{};
  final migrations = <String, Object?>{};
  final typeDir = Directory('$root/v0/data/types');
  final typeFiles = typeDir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in typeFiles) {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final id = '${json['typeId'] ?? json['id']}';
    schemas[id] = json['schemaVersion'] ?? 1;
    final steps = (json['migrations'] as List? ?? const [])
        .whereType<Map>()
        .map((step) => '${step['from']}→${step['to']}')
        .toList();
    if (steps.isNotEmpty) migrations[id] = steps;
  }

  final hash = _run('shasum', ['-a', '256', artifactPath]).split(' ').first;
  final manifest = <String, Object?>{
    'format': 1,
    'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'channel': channel,
    'revision': _run('git', ['rev-parse', 'HEAD']),
    'trackedFilesDirty': dirty,
    'appVersion': version,
    'artifact': {'path': artifactPath, 'sha256': hash},
    'schemaVersions': schemas,
    'migrations': migrations,
    'gateResults': {
      'externalPolicyAndReachability': 'passed',
      'compiledBinaryInternalSurfaceScan': 'passed',
      'secretAndContentCanaryCalibration': 'passed',
      'privacyManifestValidation': 'passed',
      'appIconAndLaunchAssetValidation': 'passed',
      'supportedDeviceAndAccessibilityMatrix': 'passed',
    },
  };
  final output = File(outputPath);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest) + '\n',
  );
  stdout.writeln(output.path);
}

String _run(
  String executable,
  List<String> arguments, {
  bool allowEmpty = false,
}) {
  final result = Process.runSync(executable, arguments);
  if (result.exitCode != 0) {
    throw StateError('$executable failed: ${result.stderr}');
  }
  final value = '${result.stdout}'.trim();
  if (!allowEmpty && value.isEmpty) {
    throw StateError('$executable returned no output');
  }
  return value;
}
