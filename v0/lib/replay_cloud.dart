/// Plenara v0 — record/replay for the cloud seam (the VCR/cassette pattern).
///
/// [RecordingCloud] wraps a live client and captures every result to a fixture.
/// [ReplayCloud] serves those captured results with NO network — so cloud-path
/// tests (residual routing, authoring) are deterministic, free, and fast, yet
/// run the real `Session` code against genuine recorded model outputs (catching
/// real schema drift, not hand-faked shapes). A recorded `null` replays as null;
/// an input that was never recorded throws, so a missing fixture fails loudly
/// instead of masquerading as "offline".
library;

import 'dart:convert';
import 'dart:io';

import 'claude.dart';

/// A stable signature of the capability inventory — routing depends on it, so it
/// is part of the key (authoring grows the inventory, which must be a new key).
String invSig(Map<String, Map<String, dynamic>> skills) {
  final ids = skills.keys.toList()..sort();
  return ids.join(',');
}

String cloudKey(String method, String primary, String extra) => '$method$extra$primary';

class RecordingCloud implements CloudClient {
  final CloudClient inner;
  final Map<String, dynamic> recorded = {};
  RecordingCloud(this.inner);

  @override
  Future<Map<String, dynamic>?> routeResidual(
      String utterance, Map<String, Map<String, dynamic>> skills) async {
    final r = await inner.routeResidual(utterance, skills);
    recorded[cloudKey('route', utterance, invSig(skills))] = r;
    return r;
  }

  @override
  Future<Map<String, dynamic>?> authorCapability(String description, {String? priorError}) async {
    final r = await inner.authorCapability(description, priorError: priorError);
    recorded[cloudKey('author', description, priorError ?? '')] = r;
    return r;
  }

  void save(String path) {
    File(path).parent.createSync(recursive: true);
    File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(recorded));
  }
}

class ReplayCloud implements CloudClient {
  final Map<String, dynamic> _rec;
  ReplayCloud(this._rec);

  factory ReplayCloud.load(String path) => ReplayCloud(
      (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, dynamic>());

  Map<String, dynamic>? _get(String key) {
    if (!_rec.containsKey(key)) {
      throw StateError('no cloud fixture for key "$key" — add the input to '
          'lib/fixture_inputs.dart and re-run bin/record_fixtures.dart');
    }
    final v = _rec[key];
    return v == null ? null : (v as Map).cast<String, dynamic>();
  }

  @override
  Future<Map<String, dynamic>?> routeResidual(
          String utterance, Map<String, Map<String, dynamic>> skills) async =>
      _get(cloudKey('route', utterance, invSig(skills)));

  @override
  Future<Map<String, dynamic>?> authorCapability(String description, {String? priorError}) async =>
      _get(cloudKey('author', description, priorError ?? ''));
}
