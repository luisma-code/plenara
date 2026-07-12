/// The macOS notification backend for the [NotificationScheduler] seam — the Apple counterpart to
/// `windows_scheduler.dart`, the razor-thin OS shim. All the reconcile/dedupe/cancel LOGIC lives in
/// v0 (`reminders.dart`) and is CI-tested against `FakeScheduler`; this maps schedule/cancel/armed
/// 1:1 onto `flutter_local_notifications`' Darwin scheduled-notification API (UNUserNotificationCenter).
///
/// Instrumented like the Windows shim: every init/schedule/cancel result goes to the diagnostics log.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:plenara/reminders.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app_log.dart';

class MacToastScheduler implements NotificationScheduler {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final Map<String, DateTime> _armed = {};
  bool _ready = false;

  // Deterministic id per ref (not a running counter) so the SAME reminder re-uses the SAME
  // notification id across restarts — zonedSchedule overwrites, no duplicate.
  int _idFor(String ref) => ref.hashCode & 0x7fffffff;

  Future<bool> _ensureReady() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones(); // tz.local defaults to UTC; only the absolute instant matters
      await _plugin.initialize(
        settings: const InitializationSettings(
          macOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestSoundPermission: true,
            requestBadgePermission: false,
          ),
        ),
      );
      // Explicit permission prompt on first arm (initialize can also request; be sure).
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
      _ready = true;
      AppLog.instance.log('sched(macos): initialized (permission granted=$granted)');
      return true;
    } catch (e, st) {
      AppLog.instance.log('sched(macos): init FAILED: $e\n$st');
      return false;
    }
  }

  @override
  Future<void> schedule(String ref, DateTime when, String body) async {
    if (!await _ensureReady()) return;
    if (!when.isAfter(DateTime.now())) {
      AppLog.instance.log('sched(macos): skip past-due "$ref" @ $when (handled as in-app nudge)');
      return;
    }
    try {
      await _plugin.zonedSchedule(
        id: _idFor(ref),
        title: 'Plenara',
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: const NotificationDetails(macOS: DarwinNotificationDetails()),
        // required by the API even on macOS (steers Android scheduling; ignored here):
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      _armed[ref] = when;
      AppLog.instance.log(
          'sched(macos): ARMED "$ref" @ $when (id=${_idFor(ref)}, in ${when.difference(DateTime.now()).inSeconds}s)');
    } catch (e, st) {
      AppLog.instance.log('sched(macos): zonedSchedule FAILED for "$ref": $e\n$st');
    }
  }

  @override
  Future<void> cancel(String ref) async {
    if (!await _ensureReady()) return;
    try {
      await _plugin.cancel(id: _idFor(ref));
    } catch (e, st) {
      AppLog.instance.log('sched(macos): cancel FAILED for "$ref": $e\n$st');
    }
    _armed.remove(ref);
  }

  @override
  Map<String, DateTime> armed() => Map.of(_armed);
}
