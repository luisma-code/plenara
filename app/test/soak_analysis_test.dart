import 'package:flutter_test/flutter_test.dart';

import '../tool/soak_analysis.dart';

void main() {
  const mib = 1024 * 1024;

  test('calibration: a known runaway is rejected', () {
    final samples = [for (var i = 0; i < 24; i++) (120 + i * 8) * mib];
    expect(analyzeSoak(samples).ballooning, isTrue);
  });

  test('calibration: a plateau with GC sawteeth is accepted', () {
    final samples = [
      for (var i = 0; i < 24; i++)
        (i < 6 ? 140 + i * 12 : 210 + (i % 4) * 3) * mib,
    ];
    expect(analyzeSoak(samples).ballooning, isFalse);
  });
}
