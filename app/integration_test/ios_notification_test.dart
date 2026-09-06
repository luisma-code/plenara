import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:plenara_app/ios_scheduler.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS schedules, recovers, and cancels a durable reminder', (
    tester,
  ) async {
    expect(
      Platform.isIOS,
      isTrue,
      reason: 'this integration check targets an iOS simulator',
    );
    final scheduler = IosNotificationScheduler();
    const ref = 'integration-reminder-recovery';
    final when = DateTime.now().add(const Duration(minutes: 10));
    addTearDown(() => scheduler.cancel(ref));

    await scheduler.cancel(ref);
    await scheduler.schedule(ref, when, 'Integration reminder');
    final recovered = await scheduler.pending();
    expect(scheduler.unavailableReason(), isNull);
    expect(recovered.keys, contains(ref));
    expect(
      recovered[ref]!.difference(when).abs(),
      lessThan(const Duration(seconds: 1)),
    );

    await scheduler.cancel(ref);
    expect((await scheduler.pending()).keys, isNot(contains(ref)));
  });
}
