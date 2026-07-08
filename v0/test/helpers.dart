/// Shared test helpers.
library;

import 'dart:io';

/// Basename of a path, cross-platform (File.path uses `\` on Windows).
String basename(String p) => p.replaceAll('\\', '/').split('/').last;

/// Build an isolated temp data dir (copy of types + skills + corpus.json, empty
/// records/) so Session/store tests never touch or pollute the real seed data
/// and can run in parallel. Returns the dir path.
String makeTempDataDir() {
  final tmp = Directory.systemTemp.createTempSync('plenara_test_');
  for (final sub in const ['types', 'skills', 'templates']) {
    final src = Directory('data/$sub');
    if (!src.existsSync()) continue;
    final dst = Directory('${tmp.path}/$sub')..createSync(recursive: true);
    for (final f in src.listSync().whereType<File>()) {
      f.copySync('${dst.path}/${basename(f.path)}');
    }
  }
  File('data/corpus.json').copySync('${tmp.path}/corpus.json');
  Directory('${tmp.path}/records').createSync();
  return tmp.path;
}
