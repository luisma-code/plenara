import 'package:flutter/foundation.dart';

const String _declaredBuildChannel = String.fromEnvironment('PLENARA_CHANNEL');

/// Compile-time release boundary. Keep security-sensitive call sites behind this
/// constant as well as the typed policy: AOT can then remove internal-only code
/// from an external binary instead of merely hiding its controls at runtime.
///
/// FAIL-CLOSED: only the explicitly recognized internal channel names (exact,
/// lowercase — the values our build scripts pass) or an undeclared debug build
/// compile the internal code in. Anything else — including an unknown or
/// misspelled PLENARA_CHANNEL — gates as external, while [parseBuildChannel]
/// still throws loudly at runtime so the misconfiguration cannot go unnoticed.
/// (The old allow-list of external names inverted this: an unknown channel
/// compiled the internal code in while the runtime parser threw.)
const bool isExternalBuild =
    !(_declaredBuildChannel == 'development' ||
        _declaredBuildChannel == 'dev' ||
        _declaredBuildChannel == 'internal' ||
        _declaredBuildChannel == 'dogfood' ||
        (_declaredBuildChannel == '' && !kReleaseMode));

/// The same gate as a testable function. Keep in lockstep with
/// [isExternalBuild] — the const cannot call a function, so the truth table
/// lives twice and a test asserts they agree for the compiled channel.
@visibleForTesting
bool externalBuildGateFor(String raw, {required bool releaseMode}) =>
    !(raw == 'development' ||
        raw == 'dev' ||
        raw == 'internal' ||
        raw == 'dogfood' ||
        (raw == '' && !releaseMode));

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

BuildChannel get activeBuildChannel =>
    parseBuildChannel(_declaredBuildChannel, releaseMode: kReleaseMode);

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
