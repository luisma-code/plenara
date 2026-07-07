/// Plenara v0 — Storage (Spec 04 §3.1 + the storage-sync CRDT decision). Per-record
/// JSON files in a folder; the in-memory store is flat records; on disk each record
/// is `{id, typeId, fields, _meta}` where `_meta.stamps` carries the per-field HLC
/// the P2 merge needs. v0 is single-device, so this is the format contract, not the
/// merge — but the write path is now faithful to it: stamp-ON-CHANGE (unchanged
/// fields keep their prior stamp), deletes are TOMBSTONES (not hard deletes, which
/// resurrect on sync restore), writes are atomic, and a corrupt/half-synced file is
/// skipped rather than bricking startup.
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
/// Tombstoned records are skipped (a delete stays present-but-invisible), and a
/// single corrupt/partial file is skipped rather than throwing (the folder is a
/// cloud-sync target, so half-written files are expected, not exotic).
Map<String, Map<String, dynamic>> loadRecords(String dir) {
  final store = <String, Map<String, dynamic>>{};
  final d = Directory(dir);
  if (!d.existsSync()) return store;
  for (final f in d.listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    Map<String, dynamic> rec;
    try {
      rec = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      continue; // skip a corrupt/half-synced file; don't brick the whole load
    }
    final meta = rec['_meta'];
    if (meta is Map && meta['deleted'] == true) continue; // tombstone -> not in the live store
    store[rec['id'] as String] = {
      'id': rec['id'],
      'typeId': rec['typeId'],
      ...((rec['fields'] as Map?)?.cast<String, dynamic>() ?? const {}),
    };
  }
  return store;
}

/// Reverse a turn from its before-images (Spec 02 §5.4 / Spec 04 §3.11): a
/// created record (prior == null) is TOMBSTONED; an updated one is restored.
void undoTurn(Map<String, Map<String, dynamic>?> before, String dir, HlcDevice dev,
    Map<String, Map<String, dynamic>> store) {
  before.forEach((id, prior) {
    if (prior == null) {
      store.remove(id);
      tombstone(id, dir, dev);
    } else {
      store[id] = Map<String, dynamic>.from(prior);
      persist(prior, dir, dev);
    }
  });
}

/// Flat record -> per-record file. Stamps ONLY fields whose value changed
/// (carrying prior stamps + conflicts forward), so the per-field `_meta` is
/// meaningful at merge time rather than collapsing to whole-record LWW.
void persist(Map<String, dynamic> flat, String dir, HlcDevice dev) {
  Directory(dir).createSync(recursive: true);
  final file = File('$dir/${flat['id']}.json');
  Map<String, dynamic> priorFields = const {}, priorStamps = const {};
  List<dynamic> priorConflicts = const [];
  if (file.existsSync()) {
    try {
      final prev = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      priorFields = (prev['fields'] as Map?)?.cast<String, dynamic>() ?? const {};
      final m = prev['_meta'];
      if (m is Map) {
        priorStamps = (m['stamps'] as Map?)?.cast<String, dynamic>() ?? const {};
        priorConflicts = (m['conflicts'] as List?) ?? const [];
      }
    } catch (_) {/* prior unreadable -> treat all fields as changed */}
  }
  final fields = <String, dynamic>{};
  final stamps = <String, dynamic>{};
  flat.forEach((k, v) {
    if (k == 'id' || k == 'typeId') return;
    fields[k] = v;
    final unchanged = priorStamps[k] != null && priorFields.containsKey(k) && priorFields[k] == v;
    stamps[k] = unchanged ? priorStamps[k] : dev.stamp();
  });
  _atomicWrite(file, {
    'id': flat['id'],
    'typeId': flat['typeId'],
    'fields': fields,
    '_meta': {'stamps': stamps, 'conflicts': priorConflicts},
  });
}

/// Mark a record deleted (a tombstone kept for CRDT convergence) instead of
/// removing the file — a hard delete resurrects on the next sync restore.
void tombstone(String id, String dir, HlcDevice dev) {
  final file = File('$dir/$id.json');
  if (!file.existsSync()) return;
  try {
    final rec = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final meta = (rec['_meta'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    meta['deleted'] = true;
    meta['deletedStamp'] = dev.stamp();
    rec['_meta'] = meta;
    _atomicWrite(file, rec);
  } catch (_) {/* unreadable -> leave as-is */}
}

/// Write via a temp file + rename so a crash mid-write can't leave a half-written
/// (corrupt) file — at worst the temp file is orphaned.
void _atomicWrite(File file, Map<String, dynamic> json) {
  final tmp = File('${file.path}.tmp');
  tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  if (file.existsSync()) file.deleteSync();
  tmp.renameSync(file.path);
}
