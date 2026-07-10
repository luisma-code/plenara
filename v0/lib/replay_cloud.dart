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

  // Recording runs once with a valid key online, so every result must be a CloudOk;
  // a CloudError mid-record means the key/network is bad — fail loudly, don't bake it in.
  Map<String, dynamic>? _unwrap(CloudResult<Map<String, dynamic>?> r, String what) => switch (r) {
        CloudError(:final kind) =>
          throw StateError('recording $what hit $kind — fix the key/network and re-record'),
        CloudOk(:final value) => value,
      };

  @override
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
      String utterance, Map<String, Map<String, dynamic>> skills,
      {Set<String> knownContacts = const {}}) async {
    final r = await inner.routeResidual(utterance, skills, knownContacts: knownContacts);
    recorded[cloudKey('route', utterance, invSig(skills))] = _unwrap(r, 'route "$utterance"');
    return r;
  }

  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String description, {String? priorError}) async {
    final r = await inner.authorCapability(description, priorError: priorError);
    recorded[cloudKey('author', description, priorError ?? '')] = _unwrap(r, 'author "$description"');
    return r;
  }

  // Generative output is grounded in dynamic per-session context, so it is NOT part of
  // the deterministic cassette (those flows are tested with a fake generative cloud);
  // recording just passes through so a live run still works.
  @override
  Future<CloudResult<String>> generate(String kind, String context) => inner.generate(kind, context);

  void save(String path) {
    File(path).parent.createSync(recursive: true);
    File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(recorded));
  }
}

/// Replays recorded results. Every recorded value is a genuine model answer (the
/// cassette was captured online with a valid key), so it replays as [CloudOk] —
/// a recorded null being a real "abstain". A missing key throws so a gap fails
/// loudly instead of masquerading as a cloud outage.
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
  Future<CloudResult<Map<String, dynamic>?>> routeResidual(
          String utterance, Map<String, Map<String, dynamic>> skills,
          {Set<String> knownContacts = const {}}) async =>
      CloudOk(_get(cloudKey('route', utterance, invSig(skills))));

  @override
  Future<CloudResult<Map<String, dynamic>?>> authorCapability(String description, {String? priorError}) async =>
      CloudOk(_get(cloudKey('author', description, priorError ?? '')));

  // Not cassette-backed (see RecordingCloud.generate): generative flows use a fake cloud
  // in tests. If a replay-backed path ever reaches here, fail loudly rather than fake it.
  @override
  Future<CloudResult<String>> generate(String kind, String context) async =>
      throw StateError('ReplayCloud has no generative fixtures — generative flows must use a fake cloud');
}
