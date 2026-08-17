import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/build_channel.dart';

void main() {
  test(
    'debug defaults to development and release defaults fail-closed to external',
    () {
      expect(
        parseBuildChannel('', releaseMode: false),
        BuildChannel.development,
      );
      expect(parseBuildChannel('', releaseMode: true), BuildChannel.external);
      expect(
        isExternalBuild,
        isFalse,
        reason: 'ordinary test build is development',
      );
    },
  );

  test(
    'only development/internal expose content diagnostics and internal tools',
    () {
      for (final channel in [BuildChannel.development, BuildChannel.internal]) {
        expect(channel.capturesContentDiagnostics, isTrue);
        expect(channel.allowsRawDiagnosticExport, isTrue);
        expect(channel.allowsInternalTools, isTrue);
      }
      expect(BuildChannel.external.capturesContentDiagnostics, isFalse);
      expect(BuildChannel.external.allowsRawDiagnosticExport, isFalse);
      expect(BuildChannel.external.allowsInternalTools, isFalse);
      expect(menuActionsFor(BuildChannel.external), ['data', 'settings']);
    },
  );

  test('unknown explicit channels fail instead of silently enabling tools', () {
    expect(
      () => parseBuildChannel('mystery', releaseMode: true),
      throwsStateError,
    );
  });
}
