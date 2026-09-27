import 'package:flutter/foundation.dart';

/// Notification taps carry only a planner record id, never a raw command.
final guideNotificationFocus = ValueNotifier<String?>(null);
