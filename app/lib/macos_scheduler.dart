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
  String? _unavailable; // permission denied / init failed -> surfaced via unavailableReason()

  Future<bool> _ensureReady() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones(); // tz.local defaults to UTC; only the absolute instant matters
      // (do NOT use matchDateTimeComponents while tz.local is UTC; recurrence is Dart-side today.)
      await _plugin.initialize(
        settings: const InitializationSettings(
          // don't auto-prompt on init; we request explicitly below so we can KEY readiness on it.
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
      );
      // Prompt the first time; on later launches this returns the live status WITHOUT re-prompting,
      // so if the user denies then enables it in System Settings, the next reconcile self-heals.
      final granted = await _plugin
              .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
      // KEY readiness on the grant — never claim armed if a toast can't display (the silent-lie bug).
      _ready = granted;
      _unavailable = granted
          ? null
          : "Reminders won't fire — enable notifications for Plenara in "
              'System Settings › Notifications.';
      AppLog.instance.log('sched(macos): initialized (permission granted=$granted)');
      return granted;
    } catch (e, st) {
      _unavailable = 'Notifications failed to initialize.';
      AppLog.instance.log('sched(macos): init FAILED: $e\n$st');
      return false;
    }
  }

  /// A one-shot IMMEDIATE notification — the launch smoke (a toast that silently doesn't display is
  /// otherwise invisible, exactly like the Windows shim). true iff the native call didn't throw.
  @override
  Future<bool> selfTest() async {
    if (!await _ensureReady()) {
      AppLog.instance.log('sched(macos): selfTest skipped — not ready ($_unavailable)');
      return false;
    }
    try {
      await _plugin.show(
        id: notificationId('__selftest__'),
        title: 'Plenara',
        body: 'Notifications are on ✓',
        notificationDetails: const NotificationDetails(macOS: DarwinNotificationDetails()),
      );
      return true;
    } catch (e, st) {
      AppLog.instance.log('sched(macos): selfTest show() FAILED: $e\n$st');
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
        id: notificationId(ref),
        title: 'Plenara',
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: const NotificationDetails(macOS: DarwinNotificationDetails()),
        // required by the API even on macOS (steers Android scheduling; ignored here):
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
      _armed[ref] = when;
      AppLog.instance.log(
          'sched(macos): ARMED "$ref" @ $when (id=${notificationId(ref)}, in ${when.difference(DateTime.now()).inSeconds}s)');
    } catch (e, st) {
      AppLog.instance.log('sched(macos): zonedSchedule FAILED for "$ref": $e\n$st');
    }
  }

  @override
  Future<void> cancel(String ref) async {
    if (!await _ensureReady()) return;
    try {
      await _plugin.cancel(id: notificationId(ref));
    } catch (e, st) {
      AppLog.instance.log('sched(macos): cancel FAILED for "$ref": $e\n$st');
    }
    _armed.remove(ref);
  }

  @override
  Map<String, DateTime> armed() => Map.of(_armed);

  @override
  String? unavailableReason() => _unavailable;
}
