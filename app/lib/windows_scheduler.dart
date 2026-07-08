/// The real Windows toast backend for the [NotificationScheduler] seam — the
/// razor-thin OS shim the whole reminder subsystem was built and tested behind a
/// fake for. All the reconcile/dedupe/cancel LOGIC lives in v0 (`reminders.dart`)
/// and is CI-tested against `FakeScheduler`; this just maps schedule/cancel/armed
/// 1:1 onto the native Windows scheduled-toast API (which needs ATL to compile).
library;

import 'package:flutter_local_notifications_windows/flutter_local_notifications_windows.dart';
import 'package:plenara/reminders.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class WindowsToastScheduler implements NotificationScheduler {
  final FlutterLocalNotificationsWindows _plugin = FlutterLocalNotificationsWindows();
  // ref -> the time it's armed for. Mirrors the OS's scheduled set so reconcile can
  // diff synchronously (the plugin's own query is async; this stays in step via
  // schedule/cancel, and reconcile-on-open re-derives from records anyway).
  final Map<String, DateTime> _armed = {};
  bool _ready = false;

  // A fixed COM activator GUID for Plenara (identifies our toast activator). Stable
  // across runs so scheduled toasts survive a restart.
  static const _guid = 'b7f6a1e2-9c34-4d55-8a6b-2f1e0c3d4a5b';

  // Deterministic id per ref (not a running counter) so the SAME reminder re-uses the
  // SAME notification id across app restarts — zonedSchedule then overwrites the OS
  // entry instead of leaving a duplicate.
  int _idFor(String ref) => ref.hashCode & 0x7fffffff;

  Future<void> _ensureReady() async {
    if (_ready) return;
    tzdata.initializeTimeZones(); // tz.local defaults to UTC; only the absolute instant matters below
    await _plugin.initialize(
      settings: const WindowsInitializationSettings(
        appName: 'Plenara',
        appUserModelId: 'Plenara.App',
        guid: _guid,
      ),
    );
    _ready = true;
  }

  @override
  Future<void> schedule(String ref, DateTime when, String body) async {
    await _ensureReady();
    // Past-due reminders are surfaced as in-app on-open nudges (pendingNudges), not OS
    // toasts — and the native API rejects scheduling in the past. So only arm the future.
    if (!when.isAfter(DateTime.now())) return;
    // TZDateTime.from preserves the absolute instant regardless of tz.local, so the toast
    // fires at the right wall-clock moment without detecting the Windows timezone name.
    await _plugin.zonedSchedule(
      id: _idFor(ref),
      title: 'Plenara',
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.local),
    );
    _armed[ref] = when;
  }

  @override
  Future<void> cancel(String ref) async {
    await _ensureReady();
    await _plugin.cancel(id: _idFor(ref));
    _armed.remove(ref);
  }

  @override
  Map<String, DateTime> armed() => Map.of(_armed);
}
