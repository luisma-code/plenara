class SoakTrend {
  final int peakBytes;
  final int finalWindowSpreadBytes;
  final int trailingGrowthBytes;
  final double trailingSlopeBytesPerSample;
  final bool ballooning;

  const SoakTrend({
    required this.peakBytes,
    required this.finalWindowSpreadBytes,
    required this.trailingGrowthBytes,
    required this.trailingSlopeBytesPerSample,
    required this.ballooning,
  });
}

SoakTrend analyzeSoak(List<int> samples) {
  if (samples.length < 8) {
    throw ArgumentError('A soak needs at least eight samples.');
  }
  final trailing = samples.sublist(samples.length ~/ 2);
  final windowSize = (samples.length / 4).ceil();
  final finalWindow = samples.sublist(samples.length - windowSize);
  final spread = finalWindow.reduce((a, b) => a < b ? a : b);
  final ceiling = finalWindow.reduce((a, b) => a > b ? a : b);
  final slope = _leastSquaresSlope(trailing);
  final trailingGrowth = trailing.last - trailing.first;
  const mib = 1024 * 1024;
  return SoakTrend(
    peakBytes: samples.reduce((a, b) => a > b ? a : b),
    finalWindowSpreadBytes: ceiling - spread,
    trailingGrowthBytes: trailingGrowth,
    trailingSlopeBytesPerSample: slope,
    // A genuine runaway both trends upward and fails to settle into a bounded
    // final window. GC sawteeth may satisfy one condition, but not both.
    ballooning: slope > 0.75 * mib && trailingGrowth > 32 * mib,
  );
}

double _leastSquaresSlope(List<int> values) {
  final meanX = (values.length - 1) / 2;
  final meanY = values.reduce((a, b) => a + b) / values.length;
  var numerator = 0.0;
  var denominator = 0.0;
  for (var index = 0; index < values.length; index++) {
    final dx = index - meanX;
    numerator += dx * (values[index] - meanY);
    denominator += dx * dx;
  }
  return numerator / denominator;
}
