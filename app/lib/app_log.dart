/// Plenara app diagnostics. Development/Internal builds intentionally retain content-bearing raw
/// traces for single-user dogfood. External builds capture none until the typed safe bundle lands.
/// Secrets are forbidden at this boundary in every channel.
library;

import 'dart:io';

import 'package:plenara/config.dart' as cfg;

import 'build_channel.dart';

class DiagnosticPolicy {
  final BuildChannel channel;
  final bool capturesContent;
  final bool allowsRawExport;
  final bool verbose;
  final Duration maxAge;
  final int maxBytes;

  const DiagnosticPolicy({
    required this.channel,
    required this.capturesContent,
    required this.allowsRawExport,
    required this.verbose,
    this.maxAge = const Duration(days: 30),
    this.maxBytes = 100 * 1024 * 1024,
  });
}

DiagnosticPolicy diagnosticPolicyFor(BuildChannel channel) => DiagnosticPolicy(
  channel: channel,
  capturesContent: channel.capturesContentDiagnostics,
  allowsRawExport: channel.allowsRawDiagnosticExport,
  verbose: channel != BuildChannel.external,
);

DiagnosticPolicy get activeDiagnosticPolicy =>
    diagnosticPolicyFor(activeBuildChannel);

class AppLog {
  final File file;
  final DiagnosticPolicy policy;
  final DateTime Function() _now;
  final Set<String> _registeredSecrets = {};

  AppLog._(this.file, this.policy, this._now);

  bool get verbose => policy.verbose;

  static AppLog? _instance;
  static AppLog get instance => _instance ??= _create();

  static AppLog _create() {
    // On iOS the diag log must be RETRIEVABLE without a cable (TestFlight) — write it into the app's
    // Documents dir, which the Files app exposes (Info.plist UIFileSharingEnabled +
    // LSSupportsOpeningDocumentsInPlace). iOS has no HOME env var, so we use the app-injected
    // [cfg.homeOverride] (the real Documents dir, set by main() via path_provider). Falling back to
    // systemTemp would land in the sandbox tmp/ — hidden and reaped (that's where early builds' logs
    // vanished). Elsewhere (macOS/Windows) systemTemp is fine and keeps logs out of the user's folders.
    final base = Platform.isIOS
        ? (cfg.homeOverride ?? Directory.systemTemp.path)
        : Directory.systemTemp.path;
    final dir = Directory('$base${Platform.pathSeparator}plenara-logs');
    try {
      dir.createSync(recursive: true);
    } catch (_) {}
    final policy = activeDiagnosticPolicy;
    _prune(dir, policy, DateTime.now());
    // sortable, filename-safe timestamp; newest file = latest run
    final ts = DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-');
    final f = File('${dir.path}${Platform.pathSeparator}plenara-$ts.log');
    if (policy.capturesContent) {
      try {
        f.writeAsStringSync(
          '=== Plenara diagnostics — ${DateTime.now()} — channel=${policy.channel.name} ===\n',
        );
      } catch (_) {}
    }
    return AppLog._(f, policy, DateTime.now);
  }

  /// Test constructor: real files and the real boundary, without mutating the process singleton.
  AppLog.forTest(Directory dir, this.policy, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      file = File('${dir.path}${Platform.pathSeparator}test.log') {
    dir.createSync(recursive: true);
  }

  void registerSecret(String? value) {
    final v = value?.trim();
    if (v != null && v.length >= 4) _registeredSecrets.add(v);
  }

  String _safe(String message) {
    var out = message;
    for (final secret in _registeredSecrets) {
      out = out.replaceAll(secret, '[secret]');
    }
    out = out
        .replaceAll(
          RegExp(r'(authorization\s*:\s*bearer\s+)\S+', caseSensitive: false),
          r'$1[secret]',
        )
        .replaceAll(
          RegExp(
            r'((?:x-api-key|api[_-]?key)\s*[:=]\s*)\S+',
            caseSensitive: false,
          ),
          r'$1[secret]',
        )
        .replaceAll(RegExp(r'sk-ant-[A-Za-z0-9_-]{12,}'), '[secret]')
        .replaceAll(
          RegExp(
            r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
          ),
          '[private-key-removed]',
        );
    return out;
  }

  void log(String msg) {
    // Compile-time boundary first: in an external AOT build the content-bearing
    // write path and its call-site strings can be tree-shaken, not merely muted.
    if (isExternalBuild) return;
    if (!policy.capturesContent) return;
    final line = '${_now().toIso8601String()}  ${_safe(msg)}\n';
    try {
      file.writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  /// A verbose trace — written only when [verbose] is on (dev/dogfood), silent in retail.
  void debug(String msg) {
    if (isExternalBuild) return;
    if (verbose) log(msg);
  }

  void call(String msg) => log(msg);

  static void pruneForTest(
    Directory dir,
    DiagnosticPolicy policy,
    DateTime now,
  ) => _prune(dir, policy, now);

  static void _prune(Directory dir, DiagnosticPolicy policy, DateTime now) {
    if (!dir.existsSync()) return;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.log'))
        .toList();
    if (!policy.capturesContent) {
      for (final file in files) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
      return;
    }
    for (final f in files) {
      try {
        if (now.difference(f.lastModifiedSync()) > policy.maxAge) {
          f.deleteSync();
        }
      } catch (_) {}
    }
    final kept =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.log'))
            .toList()
          ..sort(
            (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
          );
    var total = kept.fold<int>(0, (sum, f) {
      try {
        return sum + f.lengthSync();
      } catch (_) {
        return sum;
      }
    });
    for (final f in kept) {
      if (total <= policy.maxBytes) break;
      try {
        final size = f.lengthSync();
        f.deleteSync();
        total -= size;
      } catch (_) {}
    }
  }
}
