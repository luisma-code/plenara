/// Initializes a disposable copy of a Plenara data folder with the shipping
/// engine and reports only aggregate validation results. The source folder must
/// be copied before invoking this tool: initialization may perform migrations.
library;

import 'dart:io';

import 'package:plenara/session.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'usage: dart run bin/verify_data_copy.dart <data-copy> <device-dir>',
    );
    exitCode = 64;
    return;
  }

  final data = Directory(arguments[0]);
  final device = Directory(arguments[1])..createSync(recursive: true);
  if (!data.existsSync()) {
    stderr.writeln('data copy does not exist');
    exitCode = 66;
    return;
  }

  final session = Session(data.path, deviceDir: device.path);
  await session.init(retrieval: false);
  stdout.writeln(
    'records=${session.store.length} '
    'types=${session.types.length} '
    'skills=${session.skills.length} '
    'migrationBackups=${session.migrationBackups.length} '
    'repairIssues=${session.repairIssues.length} '
    '(storage=${session.corruptFiles.length}, '
    'schema=${session.schemaRegistry.issues.length}, '
    'migration=${session.migrationRepairItems.length}, '
    'execution=${session.executionRepairIssues.length}, '
    'conversation=${session.conversationLedger.issues.length})',
  );
  if (session.migrationRepairItems.isNotEmpty) {
    stdout.writeln(
      'migrationCodes=${session.migrationRepairItems.map((item) => '${item.typeId}:${item.code}').join(',')}',
    );
  }
  if (session.repairIssues.isNotEmpty) exitCode = 1;
}
