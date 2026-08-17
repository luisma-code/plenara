/// Device-local persistence for an authored but not-yet-activated capability.
///
/// Cloud authoring may finish after the initiating interactive turn and its
/// validated preview must survive an app restart. The draft is deliberately
/// kept outside the synced definition folders: activation is the only door
/// that promotes it into the live capability registry.
library;

import 'dart:convert';
import 'dart:io';

import 'store.dart' show writeJsonAtomic;

class CapabilityDraftStore {
  final String? path;
  final List<String> issues = [];
  Map<String, dynamic>? _active;

  CapabilityDraftStore({this.path}) {
    if (path == null) return;
    final file = File(path!);
    if (!file.existsSync()) return;
    try {
      _active = Map<String, dynamic>.from(
        jsonDecode(file.readAsStringSync()) as Map,
      );
    } catch (error) {
      issues.add('Capability draft could not be read: $error');
    }
  }

  Map<String, dynamic>? get active =>
      _active == null ? null : Map<String, dynamic>.from(_active!);

  void save(Map<String, dynamic> draft) {
    _active = Map<String, dynamic>.from(draft);
    if (path == null) return;
    final file = File(path!);
    file.parent.createSync(recursive: true);
    writeJsonAtomic(file, _active!);
  }

  void clear() {
    _active = null;
    if (path == null) return;
    final file = File(path!);
    if (file.existsSync()) file.deleteSync();
  }
}
