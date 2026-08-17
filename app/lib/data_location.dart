import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:plenara/config.dart';

const _channel = MethodChannel('com.plenara/data-folder');

String dataRootForSelection(String selectedPath) {
  final selected = Directory(selectedPath).absolute;
  final parts = selected.uri.pathSegments
      .where((part) => part.isNotEmpty)
      .toList();
  final name = parts.isEmpty ? null : parts.last.toLowerCase();
  if (name == 'plenara' ||
      Directory('${selected.path}/records').existsSync() ||
      Directory('${selected.path}/types').existsSync()) {
    return selected.path;
  }
  return '${selected.path}${Platform.pathSeparator}Plenara';
}

class DataFolderAccess {
  const DataFolderAccess();

  Future<String?> restoreSelection() async {
    if (!Platform.isIOS) return null;
    return _channel.invokeMethod<String>('restore');
  }

  Future<String?> chooseSelection() async {
    if (Platform.isIOS) return _channel.invokeMethod<String>('choose');
    return getDirectoryPath(confirmButtonText: 'Use this location');
  }
}

class DataFolderSwitchResult {
  final String dataDir;
  final bool copiedExistingData;
  final bool adoptedExistingData;

  const DataFolderSwitchResult({
    required this.dataDir,
    required this.copiedExistingData,
    required this.adoptedExistingData,
  });
}

Future<DataFolderSwitchResult> switchDataFolder({
  required String currentDataDir,
  required String selectedPath,
  String? configPath,
}) async {
  final current = Directory(currentDataDir).absolute;
  final target = Directory(dataRootForSelection(selectedPath)).absolute;
  if (target.path == current.path) {
    saveConfig(
      dataDir: target.path,
      dataFolderSelected: true,
      configPath: configPath,
    );
    if (Platform.isIOS || Platform.isAndroid) dataDirOverride = target.path;
    return DataFolderSwitchResult(
      dataDir: target.path,
      copiedExistingData: false,
      adoptedExistingData: false,
    );
  }
  if (target.path.startsWith('${current.path}${Platform.pathSeparator}')) {
    throw StateError(
      'Choose a folder outside the current Plenara data folder.',
    );
  }

  final targetHasData =
      target.existsSync() &&
      target.listSync().any(
        (entity) => entity is File || entity is Directory || entity is Link,
      );
  final targetLooksLikePlenara = _looksLikePlenaraRoot(target);
  if (targetHasData && !targetLooksLikePlenara) {
    throw StateError(
      'That Plenara folder contains an incomplete or unrelated data set.',
    );
  }
  if (!targetHasData) {
    final staging = Directory('${target.path}.importing');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    if (current.existsSync()) _copyTree(current, staging);
    if (!_looksLikePlenaraRoot(staging)) {
      staging.deleteSync(recursive: true);
      throw StateError('The current Plenara data set is incomplete.');
    }
    if (target.existsSync()) target.deleteSync(recursive: true);
    staging.renameSync(target.path);
  }

  final probe = File('${target.path}${Platform.pathSeparator}.write-probe');
  probe.writeAsStringSync('ok', flush: true);
  probe.deleteSync();
  saveConfig(
    dataDir: target.path,
    dataFolderSelected: true,
    configPath: configPath,
  );
  if (Platform.isIOS || Platform.isAndroid) dataDirOverride = target.path;
  return DataFolderSwitchResult(
    dataDir: target.path,
    copiedExistingData: !targetHasData,
    adoptedExistingData: targetHasData,
  );
}

bool _looksLikePlenaraRoot(Directory root) =>
    Directory('${root.path}${Platform.pathSeparator}records').existsSync() &&
    (Directory('${root.path}${Platform.pathSeparator}types').existsSync() ||
        File('${root.path}${Platform.pathSeparator}corpus.json').existsSync());

void _copyTree(Directory source, Directory target) {
  for (final entity in source.listSync(recursive: false, followLinks: false)) {
    final name = entity.uri.pathSegments.where((p) => p.isNotEmpty).last;
    if (entity is Directory) {
      final child = Directory('${target.path}${Platform.pathSeparator}$name')
        ..createSync(recursive: true);
      _copyTree(entity, child);
    } else if (entity is File) {
      final destination = File('${target.path}${Platform.pathSeparator}$name');
      destination.parent.createSync(recursive: true);
      final temp = File('${destination.path}.copying');
      temp.writeAsBytesSync(entity.readAsBytesSync(), flush: true);
      if (destination.existsSync()) destination.deleteSync();
      temp.renameSync(destination.path);
    }
  }
}
