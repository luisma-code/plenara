/// The real Windows toast backend for the [NotificationScheduler] seam — the
/// razor-thin OS shim the whole reminder subsystem was built and tested behind a
/// fake for. All the reconcile/dedupe/cancel LOGIC lives in v0 (`reminders.dart`)
/// and is CI-tested against `FakeScheduler`; this maps schedule/cancel/armed 1:1
/// onto the native Windows scheduled-toast API (which needs ATL to compile).
///
/// Heavily instrumented: every init/schedule/cancel result goes to the diagnostics
/// log, because a toast that silently doesn't display (the classic unpackaged-AUMID
/// case) is otherwise invisible.
library;

import 'package:flutter_local_notifications_windows/flutter_local_notifications_windows.dart';
import 'package:plenara/reminders.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app_log.dart';

class WindowsToastScheduler implements NotificationScheduler {
  final FlutterLocalNotificationsWindows _plugin = FlutterLocalNotificationsWindows();
  final Map<String, DateTime> _armed = {};
  bool _ready = false;

  // A fixed COM activator GUID for Plenara (identifies our toast activator). Stable
  // across runs so scheduled toasts survive a restart.
  static const _guid = 'b7f6a1e2-9c34-4d55-8a6b-2f1e0c3d4a5b';

  // Deterministic id per ref (not a running counter) so the SAME reminder re-uses the
  // SAME notification id across restarts — zonedSchedule overwrites, no duplicate.
  int _idFor(String ref) => ref.hashCode & 0x7fffffff;

  Future<bool> _ensureReady() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones(); // tz.local defaults to UTC; only the absolute instant matters
      final ok = await _plugin.initialize(
        settings: const WindowsInitializationSettings(
          appName: 'Plenara',
          appUserModelId: 'Plenara.App',
          guid: _guid,
        ),
      );
      _ready = ok;
      AppLog.instance.log('sched: plugin.initialize() -> $ok (aumid=Plenara.App)');
      return ok;
    } catch (e, st) {
      AppLog.instance.log('sched: plugin.initialize FAILED: $e\n$st');
      return false;
    }
  }

  /// A one-shot IMMEDIATE toast — a launch-time self-test so we can tell display works
  /// without waiting for a scheduled reminder. Returns true if the native call didn't throw.
  Future<bool> selfTest() async {
    if (!await _ensureReady()) {
      AppLog.instance.log('sched: selfTest skipped — not ready');
      return false;
    }
    try {
      await _plugin.show(id: 999999, title: 'Plenara', body: 'Notifications are on ✓');
      AppLog.instance.log('sched: selfTest show() returned without error');
      return true;
    } catch (e, st) {
      AppLog.instance.log('sched: selfTest show() FAILED: $e\n$st');
      return false;
    }
  }

  @override
  Future<void> schedule(String ref, DateTime when, String body) async {
    if (!await _ensureReady()) return;
    if (!when.isAfter(DateTime.now())) {
      AppLog.instance.log('sched: skip past-due "$ref" @ $when (handled as in-app nudge)');
      return;
    }
    try {
      await _plugin.zonedSchedule(
        id: _idFor(ref),
        title: 'Plenara',
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
      );
      _armed[ref] = when;
      AppLog.instance.log('sched: ARMED "$ref" @ $when (id=${_idFor(ref)}, in ${when.difference(DateTime.now()).inSeconds}s)');
    } catch (e, st) {
      AppLog.instance.log('sched: zonedSchedule FAILED for "$ref": $e\n$st');
    }
  }

  @override
  Future<void> cancel(String ref) async {
    if (!await _ensureReady()) return;
    try {
      // NOTE: unpackaged (no MSIX identity) -> native cancel is a no-op; a scheduled toast
      // can't be recalled. In-memory state stays correct; MSIX packaging gives real cancel.
      await _plugin.cancel(id: _idFor(ref));
    } catch (e, st) {
      AppLog.instance.log('sched: cancel FAILED for "$ref": $e\n$st');
    }
    _armed.remove(ref);
  }

  @override
  Map<String, DateTime> armed() => Map.of(_armed);
}
