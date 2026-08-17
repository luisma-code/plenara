import 'package:flutter_test/flutter_test.dart';
import 'package:plenara_app/app_log.dart';
import 'package:plenara_app/build_channel.dart';

void main() {
  test(
    'declared external build fails closed across diagnostics and internal tools',
    () {
      expect(activeBuildChannel, BuildChannel.external);
      expect(activeDiagnosticPolicy.capturesContent, isFalse);
      expect(activeDiagnosticPolicy.allowsRawExport, isFalse);
      expect(menuActionsFor(activeBuildChannel), ['data', 'settings']);
      expect(activeBuildChannel.allowsInternalTools, isFalse);
    },
    skip: activeBuildChannel == BuildChannel.external
        ? false
        : 'run with --dart-define=PLENARA_CHANNEL=external',
  );
}
