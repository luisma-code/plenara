import 'package:test/test.dart';

import '../bin/coverage_check.dart';

void main() {
  test('a weak tier fails even when global coverage is high', () {
    final failures = coverageFailures({
      'interpreter.dart': [50, 100],
      'session.dart': [1000, 1000],
      'claude.dart': [1000, 1000],
    });
    expect(failures, contains(contains('deterministicCore coverage')));
    expect(failures, isNot(contains(contains('global coverage'))));
  });

  test('new production files cannot disappear from the denominator', () {
    final failures = coverageFailures({
      'interpreter.dart': [100, 100],
      'session.dart': [100, 100],
      'claude.dart': [100, 100],
      'new_logic.dart': [100, 100],
    });
    expect(failures, contains('UNCLASSIFIED COVERAGE: new_logic.dart'));
  });

  test('the remaining operator-only exclusion does not weaken a measured tier',
      () {
    final failures = coverageFailures({
      'interpreter.dart': [90, 100],
      'session.dart': [90, 100],
      'claude.dart': [90, 100],
      'replay_cloud.dart': [0, 1000],
    });
    expect(failures, isEmpty);
  });

  test('the in-process embedding backend is counted as product logic', () {
    final failures = coverageFailures({
      'interpreter.dart': [90, 100],
      'session.dart': [100, 100],
      'claude.dart': [90, 100],
      'embed.dart': [0, 1000],
    });
    expect(failures, contains(contains('productLogic coverage')));
  });
}
