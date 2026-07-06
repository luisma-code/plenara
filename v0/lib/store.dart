/// Plenara v0 — Storage (Spec 04 §3.1 + the CRDT decision). Per-record JSON
/// files in a folder; the in-memory store is flat records; on disk each record
/// is `{id, typeId, fields, _meta}` where `_meta.stamps` carries the per-field
/// HLC used by the merge (spikes/storage-crdt). v0 is single-device, so load is
/// a plain read; the merge is exercised at P2.
library;

import 'dart:convert';
import 'dart:io';

class HlcDevice {
  final String id;
  int _ms = 0, _counter = 0;
  HlcDevice(this.id);
  Map<String, dynamic> stamp() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs > _ms) {
      _ms = nowMs;
      _counter = 0;
    } else {
      _counter++;
    }
    return {'ms': _ms, 'counter': _counter, 'deviceId': id};
  }
}

Map<String, Map<String, dynamic>> loadDefs(String dir, String key) {
  final out = <String, Map<String, dynamic>>{};
  for (final f in Directory(dir).listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    final d = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    out[d[key] as String] = d;
  }
  return out;
}

/// Per-record files `{id,typeId,fields,_meta}` -> flat in-memory records.
Map<String, Map<String, dynamic>> loadRecords(String dir) {
  final store = <String, Map<String, dynamic>>{};
  final d = Directory(dir);
  if (!d.existsSync()) return store;
  for (final f in d.listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    final rec = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    store[rec['id'] as String] = {
      'id': rec['id'],
      'typeId': rec['typeId'],
      ...(rec['fields'] as Map).cast<String, dynamic>(),
    };
  }
  return store;
}

/// Reverse a turn from its before-images (Spec 02 §5.4 / Spec 04 §3.11): a
/// created record (prior == null) is deleted; an updated one is restored. Applies
/// to both the in-memory store and the persisted files.
void undoTurn(Map<String, Map<String, dynamic>?> before, String dir, HlcDevice dev,
    Map<String, Map<String, dynamic>> store) {
  before.forEach((id, prior) {
    if (prior == null) {
      store.remove(id);
      final f = File('$dir/$id.json');
      if (f.existsSync()) f.deleteSync();
    } else {
      store[id] = Map<String, dynamic>.from(prior);
      persist(prior, dir, dev);
    }
  });
}

/// Flat record -> per-record file, stamping each field (the CRDT `_meta` block).
void persist(Map<String, dynamic> flat, String dir, HlcDevice dev) {
  Directory(dir).createSync(recursive: true);
  final fields = <String, dynamic>{};
  final stamps = <String, dynamic>{};
  flat.forEach((k, v) {
    if (k == 'id' || k == 'typeId') return;
    fields[k] = v;
    stamps[k] = dev.stamp();
  });
  final onDisk = {
    'id': flat['id'],
    'typeId': flat['typeId'],
    'fields': fields,
    '_meta': {'stamps': stamps, 'conflicts': []},
  };
  File('$dir/${flat['id']}.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(onDisk));
}
