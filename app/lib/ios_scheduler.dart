/// The iOS `UNUserNotificationCenter` adapter for Plenara reminders.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:plenara/reminders.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app_log.dart';

class IosNotificationScheduler
    implements NotificationScheduler, PendingNotificationScheduler {
  IosNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final Map<String, DateTime> _armed = {};
  bool _ready = false;
  String? _unavailable;

  Future<bool> _ensureReady() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
      );
      final granted =
          await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
      _ready = granted;
      _unavailable = granted
          ? null
          : "Reminders won't fire — enable notifications for Plenara in "
                'Settings › Notifications.';
      AppLog.instance.log(
        'sched(ios): initialized (permission granted=$granted)',
      );
      return granted;
    } catch (e, st) {
      _unavailable = 'Notifications failed to initialize.';
      AppLog.instance.log('sched(ios): init FAILED: $e\n$st');
      return false;
    }
  }

  @override
  Future<bool> selfTest() async {
    if (!await _ensureReady()) return false;
    try {
      await _plugin.show(
        id: notificationId('__selftest__'),
        title: 'Plenara',
        body: 'Notifications are on ✓',
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(),
        ),
      );
      return true;
    } catch (e, st) {
      AppLog.instance.log('sched(ios): selfTest FAILED: $e\n$st');
      return false;
    }
  }

  @override
  Future<void> schedule(String ref, DateTime when, String body) async {
    if (!await _ensureReady()) return;
    if (!when.isAfter(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id: notificationId(ref),
        title: 'Plenara',
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: notificationPayload(ref, when),
      );
      _armed[ref] = when;
      AppLog.instance.log('sched(ios): ARMED "$ref" @ $when');
    } catch (e, st) {
      AppLog.instance.log('sched(ios): schedule FAILED for "$ref": $e\n$st');
    }
  }

  @override
  Future<void> cancel(String ref) async {
    if (!await _ensureReady()) return;
    try {
      await _plugin.cancel(id: notificationId(ref));
      _armed.remove(ref);
    } catch (e, st) {
      AppLog.instance.log('sched(ios): cancel FAILED for "$ref": $e\n$st');
    }
  }

  @override
  Map<String, DateTime> armed() => Map.of(_armed);

  @override
  Future<Map<String, DateTime>> pending() async {
    if (!await _ensureReady()) return const {};
    try {
      final recovered = <String, DateTime>{};
      for (final request in await _plugin.pendingNotificationRequests()) {
        final parsed = parseNotificationPayload(request.payload);
        if (parsed == null || notificationId(parsed.ref) != request.id) {
          // This app owns its whole notification queue. Clear pre-payload and
          // corrupt requests once so an upgrade cannot leave an untraceable
          // reminder behind to ghost-fire after its record was deleted.
          await _plugin.cancel(id: request.id);
          continue;
        }
        recovered[parsed.ref] = parsed.when;
      }
      _armed
        ..clear()
        ..addAll(recovered);
      return Map.of(_armed);
    } catch (e, st) {
      AppLog.instance.log('sched(ios): pending query FAILED: $e\n$st');
      return Map.of(_armed);
    }
  }

  @override
  String? unavailableReason() => _unavailable;
}
