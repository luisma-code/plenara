/// Runs the current schema migration against a disposable copy of the configured
/// dogfood folder. The source is snapshotted before and after so this operator
/// check cannot quietly become a live-data migration path.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:plenara/config.dart';
import 'package:plenara/session.dart';

Future<Map<String, Uint8List>> _snapshot(Directory root) async {
  final files = <String, Uint8List>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = entity.path.substring(root.path.length + 1);
    files[relative] = await entity.readAsBytes();
  }
  return files;
}

Future<void> _copyTree(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final target = '${destination.path}${Platform.pathSeparator}$relative';
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
    } else if (entity is File) {
      await File(target).parent.create(recursive: true);
      await entity.copy(target);
    }
  }
}

bool _sameSnapshot(Map<String, Uint8List> left, Map<String, Uint8List> right) {
  if (left.length != right.length ||
      !left.keys.toSet().containsAll(right.keys)) {
    return false;
  }
  for (final entry in left.entries) {
    final other = right[entry.key];
    if (other == null || other.length != entry.value.length) return false;
    for (var index = 0; index < other.length; index++) {
      if (other[index] != entry.value[index]) return false;
    }
  }
  return true;
}

Future<void> main() async {
  final source = Directory(loadConfig().dataDir);
  if (!source.existsSync()) {
    stderr.writeln('Configured data folder does not exist.');
    exitCode = 2;
    return;
  }

  final before = await _snapshot(source);
  final scratch =
      await Directory.systemTemp.createTemp('plenara_migration_smoke_');
  try {
    final copy = Directory('${scratch.path}${Platform.pathSeparator}data');
    await _copyTree(source, copy);
    ensureSeeded(copy.path, 'data');
    final session = Session(
      copy.path,
      deviceDir: '${scratch.path}${Platform.pathSeparator}device',
    );
    await session.init(retrieval: false);

    final tasks = session.store.values
        .where((record) => record['typeId'] == 'task')
        .toList();
    final taskVersion = session.types['task']?['schemaVersion'];
    final wrongVersion =
        tasks.where((record) => record['_schemaVersion'] != taskVersion).length;
    final after = await _snapshot(source);
    final sourceUnchanged = _sameSnapshot(before, after);

    stdout.writeln(
      'records=${session.store.length} tasks=${tasks.length} '
      'taskVersion=$taskVersion backups=${session.migrationBackups.length} '
      'repairIssues=${session.repairIssues.length} sourceUnchanged=$sourceUnchanged',
    );
    if (session.repairIssues.isNotEmpty ||
        wrongVersion != 0 ||
        !sourceUnchanged) {
      exitCode = 1;
    }
  } finally {
    await scratch.delete(recursive: true);
  }
}
