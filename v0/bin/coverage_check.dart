/// Coverage gate with owned per-tier and global floors (Spec 09 §8).
library;

import 'dart:io';

enum CoverageTier { deterministicCore, productLogic, transport }

const tierFloors = <CoverageTier, double>{
  CoverageTier.deterministicCore: 90,
  CoverageTier.productLogic: 80,
  CoverageTier.transport: 60,
};

const fileTiers = <String, CoverageTier>{
  'interpreter.dart': CoverageTier.deterministicCore,
  'store.dart': CoverageTier.deterministicCore,
  'reminders.dart': CoverageTier.deterministicCore,
  'dates.dart': CoverageTier.deterministicCore,
  'session.dart': CoverageTier.productLogic,
  'people.dart': CoverageTier.productLogic,
  'generative.dart': CoverageTier.productLogic,
  'storage_repository.dart': CoverageTier.productLogic,
  'turnlog.dart': CoverageTier.productLogic,
  'config.dart': CoverageTier.productLogic,
  'routines.dart': CoverageTier.productLogic,
  'automations.dart': CoverageTier.productLogic,
  'reference.dart': CoverageTier.productLogic,
  'content_search.dart': CoverageTier.productLogic,
  'migration.dart': CoverageTier.productLogic,
  'execution_coordinator.dart': CoverageTier.productLogic,
  'schema_registry.dart': CoverageTier.productLogic,
  'value_codec.dart': CoverageTier.productLogic,
  'conversation_ledger.dart': CoverageTier.productLogic,
  'operation_center.dart': CoverageTier.productLogic,
  'plan_proposal.dart': CoverageTier.productLogic,
  'weekly_review.dart': CoverageTier.productLogic,
  'capability_draft_store.dart': CoverageTier.productLogic,
  'planning_artifact.dart': CoverageTier.productLogic,
  'planner.dart': CoverageTier.productLogic,
  'router.dart': CoverageTier.productLogic,
  'embed.dart': CoverageTier.productLogic,
  'cron.dart': CoverageTier.productLogic,
  'claude.dart': CoverageTier.transport,
};

/// Operator/temporary integration code excluded until replay recording is split
/// from its product replay seam.
const coverageExclusions = {'fixture_inputs.dart', 'replay_cloud.dart'};

double percentage(List<int> value) =>
    value[1] == 0 ? 100 : 100 * value[0] / value[1];

List<String> coverageFailures(
  Map<String, List<int>> perFile, {
  double globalFloor = 80,
  Map<CoverageTier, double> floors = tierFloors,
}) {
  final failures = <String>[];
  final tierTotals = <CoverageTier, List<int>>{
    for (final tier in CoverageTier.values) tier: [0, 0],
  };
  var globalHit = 0;
  var globalFound = 0;
  for (final entry in perFile.entries) {
    final name = entry.key.split(RegExp(r'[\\/]')).last;
    if (coverageExclusions.contains(name)) continue;
    final tier = fileTiers[name];
    if (tier == null) {
      failures.add('UNCLASSIFIED COVERAGE: $name');
      continue;
    }
    tierTotals[tier]![0] += entry.value[0];
    tierTotals[tier]![1] += entry.value[1];
    globalHit += entry.value[0];
    globalFound += entry.value[1];
  }
  for (final tier in CoverageTier.values) {
    final actual = percentage(tierTotals[tier]!);
    final floor = floors[tier]!;
    if (actual < floor) {
      failures.add(
        '${tier.name} coverage ${actual.toStringAsFixed(1)}% < ${floor.toStringAsFixed(0)}%',
      );
    }
  }
  final global = percentage([globalHit, globalFound]);
  if (global < globalFloor) {
    failures.add(
      'global coverage ${global.toStringAsFixed(1)}% < ${globalFloor.toStringAsFixed(0)}%',
    );
  }
  return failures;
}

void main(List<String> args) {
  final globalFloor = args.isNotEmpty ? double.parse(args.first) : 80.0;
  final file = File('coverage/lcov.info');
  if (!file.existsSync()) {
    stderr.writeln('coverage/lcov.info not found — generate coverage first.');
    exit(2);
  }
  String? source;
  var found = 0;
  final perFile = <String, List<int>>{};
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      source = line.substring(3);
      found = 0;
    } else if (line.startsWith('LF:')) {
      found = int.parse(line.substring(3));
    } else if (line.startsWith('LH:') && source != null) {
      perFile[source] = [int.parse(line.substring(3)), found];
    }
  }
  final included = perFile.entries.where((entry) {
    final name = entry.key.split(RegExp(r'[\\/]')).last;
    return !coverageExclusions.contains(name);
  }).toList()
    ..sort((a, b) => percentage(a.value).compareTo(percentage(b.value)));
  for (final entry in included) {
    final name = entry.key.split(RegExp(r'[\\/]')).last;
    print(
      '${percentage(entry.value).toStringAsFixed(1).padLeft(6)}%  $name  '
      '(${entry.value[0]}/${entry.value[1]})',
    );
  }
  for (final tier in CoverageTier.values) {
    final files = included.where(
      (entry) => fileTiers[entry.key.split(RegExp(r'[\\/]')).last] == tier,
    );
    final hit = files.fold<int>(0, (sum, entry) => sum + entry.value[0]);
    final total = files.fold<int>(0, (sum, entry) => sum + entry.value[1]);
    print(
      '${tier.name}: ${percentage([hit, total]).toStringAsFixed(1)}% '
      '(floor ${tierFloors[tier]!.toStringAsFixed(0)}%)',
    );
  }
  final failures = coverageFailures(perFile, globalFloor: globalFloor);
  if (failures.isNotEmpty) {
    for (final failure in failures) {
      stderr.writeln('COVERAGE FAILURE: $failure');
    }
    exit(1);
  }
  print('OK — every tier and the global coverage floor passed.');
}
