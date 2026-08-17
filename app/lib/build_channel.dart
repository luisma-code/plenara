import 'package:flutter/foundation.dart';

/// One compile-time owner for product reachability. Internal/TestFlight builds deliberately retain
/// content-bearing diagnostics and visual tuning tools; external builds fail closed.
enum BuildChannel { development, internal, external }

BuildChannel parseBuildChannel(String raw, {required bool releaseMode}) {
  switch (raw.trim().toLowerCase()) {
    case 'development':
    case 'dev':
      return BuildChannel.development;
    case 'internal':
    case 'dogfood':
      return BuildChannel.internal;
    case 'external':
    case 'release':
      return BuildChannel.external;
    case '':
      return releaseMode ? BuildChannel.external : BuildChannel.development;
    default:
      throw StateError(
        'Unknown PLENARA_CHANNEL "$raw". Use development, internal, or external.',
      );
  }
}

BuildChannel get activeBuildChannel => parseBuildChannel(
  const String.fromEnvironment('PLENARA_CHANNEL'),
  releaseMode: kReleaseMode,
);

extension BuildChannelPolicy on BuildChannel {
  bool get allowsInternalTools => this != BuildChannel.external;
  bool get capturesContentDiagnostics => this != BuildChannel.external;
  bool get allowsRawDiagnosticExport => this != BuildChannel.external;
}

List<String> menuActionsFor(BuildChannel channel) => [
  if (channel.allowsInternalTools) 'harness',
  if (channel.allowsInternalTools) 'tune',
  'data',
  'settings',
];
