import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Selected Calendar and Reminders browsing crosses the real native bridge',
    (tester) async {
      expect(Platform.isIOS, isTrue);
      const channel = MethodChannel('com.plenara/guide-sources');
      // Run only on the task's dedicated simulator, pre-authorized for these
      // sources. This verifies data access, not the OS permission-sheet choice.
      for (final kind in ['calendar', 'reminders']) {
        final value = await channel.invokeListMethod<dynamic>('select', {
          'kind': kind,
        });
        expect(value, isNotNull);
        expect(value!.length, lessThanOrEqualTo(100));
        for (final item in value) {
          expect(item, isA<Map>());
          expect(
            (item as Map)['kind'],
            kind == 'calendar' ? 'calendar' : 'reminder',
          );
        }
      }
      expect(await channel.invokeMethod<String>('draft'), isNull);
    },
  );
}
