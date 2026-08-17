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

  /// Advance this clock past an observed remote stamp before issuing another
  /// local stamp. This is the receive half of the HLC contract: a causally
  /// later local edit can never sort before the remote state it was based on.
  void observe(Object? raw) {
    if (raw is! Map) return;
    final remoteMs = raw['ms'];
    final remoteCounter = raw['counter'];
    if (remoteMs is! int || remoteCounter is! int) return;
    final wall = DateTime.now().millisecondsSinceEpoch;
    final nextMs = [wall, _ms, remoteMs].reduce((a, b) => a > b ? a : b);
    if (nextMs == _ms && nextMs == remoteMs) {
      _counter = (_counter > remoteCounter ? _counter : remoteCounter) + 1;
    } else if (nextMs == _ms) {
      _counter++;
    } else if (nextMs == remoteMs) {
      _counter = remoteCounter + 1;
    } else {
      _counter = 0;
    }
    _ms = nextMs;
  }
}

class RecordMergeResult {
  final Map<String, dynamic> document;
  final List<Map<String, dynamic>> newConflicts;

  const RecordMergeResult(this.document, this.newConflicts);
}

int compareHlc(Object? left, Object? right) {
  int value(Object? raw, String key) =>
      raw is Map && raw[key] is int ? raw[key] as int : 0;
  String device(Object? raw) => raw is Map ? '${raw['deviceId'] ?? ''}' : '';
  final ms = value(left, 'ms').compareTo(value(right, 'ms'));
  if (ms != 0) return ms;
  final counter = value(left, 'counter').compareTo(value(right, 'counter'));
  if (counter != 0) return counter;
  return device(left).compareTo(device(right));
}

Map<String, int> _versionVector(Map<String, dynamic> document) => {
      for (final entry
          in ((document['_meta'] as Map?)?['vv'] as Map? ?? const {}).entries)
        '${entry.key}': entry.value is int ? entry.value as int : 0,
    };

bool _strictlyDominates(Map<String, int> left, Map<String, int> right) {
  if (left.isEmpty || right.isEmpty) return false;
  var greater = false;
  for (final key in {...left.keys, ...right.keys}) {
    final a = left[key] ?? 0;
    final b = right[key] ?? 0;
    if (a < b) return false;
    if (a > b) greater = true;
  }
  return greater;
}

Map<String, int> _mergedVector(
  Map<String, dynamic> left,
  Map<String, dynamic> right,
) {
  final a = _versionVector(left), b = _versionVector(right);
  return {
    for (final key in {...a.keys, ...b.keys})
      key: (a[key] ?? 0) > (b[key] ?? 0) ? a[key]! : b[key]!,
  };
}

Object? _highestLiveStamp(Map<String, dynamic> document) {
  final meta = (document['_meta'] as Map?) ?? const {};
  final candidates = <Object?>[
    ...((meta['stamps'] as Map?) ?? const {}).values,
    ...((meta['fieldTombstones'] as Map?) ?? const {}).values,
  ];
  if (candidates.isEmpty) return null;
  candidates.sort(compareHlc);
  return candidates.last;
}

Map<String, dynamic> _copyDocument(Map<String, dynamic> source) =>
    jsonDecode(jsonEncode(source)) as Map<String, dynamic>;

List<Map<String, dynamic>> _conflictsOf(Map<String, dynamic> document) =>
    ((document['_meta'] as Map?)?['conflicts'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

List<Map<String, dynamic>> _unionConflicts(
  Iterable<Map<String, dynamic>> values,
) {
  final byKey = <String, Map<String, dynamic>>{};
  for (final value in values) {
    final key = jsonEncode({
      'field': value['field'],
      'value': value['value'],
    });
    final existing = byKey[key];
    if (existing == null || compareHlc(value['stamp'], existing['stamp']) > 0) {
      byKey[key] = value;
    }
  }
  final keys = byKey.keys.toList()..sort();
  return [for (final key in keys) byKey[key]!];
}

List<Map<String, dynamic>> _unresolvedConflicts(
  Iterable<Map<String, dynamic>> conflicts,
  Map<String, dynamic> liveFields,
) =>
    _unionConflicts(conflicts)
        .where((conflict) =>
            !liveFields.containsKey('${conflict['field']}') ||
            !_sameJson(liveFields['${conflict['field']}'], conflict['value']))
        .toList();

/// Pure state-CRDT merge for two versions of one record. It is deliberately
/// independent of paths and providers so commutativity, associativity, and
/// idempotence can be property-tested in memory.
RecordMergeResult mergeRecordDocuments(
  Map<String, dynamic> left,
  Map<String, dynamic> right,
) {
  if ('${left['id']}' != '${right['id']}') {
    throw ArgumentError('Cannot merge records with different ids.');
  }
  final leftType = left['typeId'], rightType = right['typeId'];
  if (leftType != null && rightType != null && leftType != rightType) {
    throw StateError('Record ${left['id']} has conflicting type ids.');
  }
  final leftMeta = Map<String, dynamic>.from(
    (left['_meta'] as Map?) ?? const {},
  );
  final rightMeta = Map<String, dynamic>.from(
    (right['_meta'] as Map?) ?? const {},
  );
  final inherited = _unionConflicts([
    ..._conflictsOf(left),
    ..._conflictsOf(right),
  ]);
  final vv = _mergedVector(left, right);
  final leftDeleted = leftMeta['deleted'] == true;
  final rightDeleted = rightMeta['deleted'] == true;

  Map<String, dynamic> finish(
    Map<String, dynamic> chosen, {
    bool clearDeleted = false,
    List<Map<String, dynamic>> added = const [],
  }) {
    final result = _copyDocument(chosen);
    final meta = Map<String, dynamic>.from(
      (result['_meta'] as Map?) ?? const {},
    );
    if (vv.isNotEmpty) meta['vv'] = vv;
    final liveFields = Map<String, dynamic>.from(
      (result['fields'] as Map?) ?? const {},
    );
    final conflicts = _unresolvedConflicts(
      [...inherited, ...added],
      liveFields,
    );
    meta['conflicts'] = conflicts;
    if (clearDeleted) {
      meta.remove('deleted');
      meta.remove('deletedStamp');
    }
    result['_meta'] = meta;
    return result;
  }

  if (leftDeleted || rightDeleted) {
    if (leftDeleted && rightDeleted) {
      final chosen = compareHlc(
                leftMeta['deletedStamp'],
                rightMeta['deletedStamp'],
              ) >=
              0
          ? left
          : right;
      return RecordMergeResult(finish(chosen), const []);
    }
    final deleted = leftDeleted ? left : right;
    final live = leftDeleted ? right : left;
    final deleteStamp =
        ((deleted['_meta'] as Map?) ?? const {})['deletedStamp'];
    final liveStamp = _highestLiveStamp(live);
    if (compareHlc(deleteStamp, liveStamp) >= 0) {
      return RecordMergeResult(finish(deleted), const []);
    }
    return RecordMergeResult(finish(live, clearDeleted: true), const []);
  }

  final leftVv = _versionVector(left), rightVv = _versionVector(right);
  if (_strictlyDominates(leftVv, rightVv)) {
    return RecordMergeResult(finish(left), const []);
  }
  if (_strictlyDominates(rightVv, leftVv)) {
    return RecordMergeResult(finish(right), const []);
  }
  if (_sameJson(left, right)) {
    return RecordMergeResult(finish(left), const []);
  }

  final leftFields = Map<String, dynamic>.from(
    (left['fields'] as Map?) ?? const {},
  );
  final rightFields = Map<String, dynamic>.from(
    (right['fields'] as Map?) ?? const {},
  );
  final leftStamps = Map<String, dynamic>.from(
    (leftMeta['stamps'] as Map?) ?? const {},
  );
  final rightStamps = Map<String, dynamic>.from(
    (rightMeta['stamps'] as Map?) ?? const {},
  );
  final leftTombs = Map<String, dynamic>.from(
    (leftMeta['fieldTombstones'] as Map?) ?? const {},
  );
  final rightTombs = Map<String, dynamic>.from(
    (rightMeta['fieldTombstones'] as Map?) ?? const {},
  );
  final fields = <String, dynamic>{};
  final stamps = <String, dynamic>{};
  final tombstones = <String, dynamic>{};
  final added = <Map<String, dynamic>>[];
  final keys = {
    ...leftFields.keys,
    ...rightFields.keys,
    ...leftTombs.keys,
    ...rightTombs.keys,
  }.toList()
    ..sort();

  for (final key in keys) {
    final leftHas = leftFields.containsKey(key);
    final rightHas = rightFields.containsKey(key);
    final leftStamp = leftHas ? leftStamps[key] : leftTombs[key];
    final rightStamp = rightHas ? rightStamps[key] : rightTombs[key];
    if (leftHas && rightHas && _sameJson(leftFields[key], rightFields[key])) {
      final takeLeft = compareHlc(leftStamp, rightStamp) >= 0;
      fields[key] = takeLeft ? leftFields[key] : rightFields[key];
      stamps[key] = takeLeft ? leftStamp : rightStamp;
      continue;
    }
    var order = compareHlc(leftStamp, rightStamp);
    if (order == 0 && leftHas && rightHas) {
      order =
          jsonEncode(leftFields[key]).compareTo(jsonEncode(rightFields[key]));
    }
    final takeLeft = order >= 0;
    final winnerHas = takeLeft ? leftHas : rightHas;
    final winnerValue = takeLeft ? leftFields[key] : rightFields[key];
    final winnerStamp = takeLeft ? leftStamp : rightStamp;
    final loserHas = takeLeft ? rightHas : leftHas;
    final loserValue = takeLeft ? rightFields[key] : leftFields[key];
    final loserStamp = takeLeft ? rightStamp : leftStamp;
    if (winnerHas) {
      fields[key] = winnerValue;
      stamps[key] = winnerStamp;
    } else if (winnerStamp != null) {
      tombstones[key] = winnerStamp;
    }
    if ((leftHas &&
            rightHas &&
            !_sameJson(leftFields[key], rightFields[key])) ||
        (!winnerHas && loserHas)) {
      added.add({
        'field': key,
        'value': loserValue,
        'stamp': loserStamp,
      });
    }
  }

  final result = <String, dynamic>{
    'id': left['id'],
    'typeId': leftType ?? rightType,
    'schemaVersion': [
      left['schemaVersion'] is int ? left['schemaVersion'] as int : 1,
      right['schemaVersion'] is int ? right['schemaVersion'] as int : 1,
    ].reduce((a, b) => a > b ? a : b),
    if (left['createdAt'] != null || right['createdAt'] != null)
      'createdAt': [left['createdAt'], right['createdAt']]
          .where((value) => value != null)
          .map((value) => '$value')
          .reduce((a, b) => a.compareTo(b) <= 0 ? a : b),
    'fields': fields,
    '_meta': {
      if (vv.isNotEmpty) 'vv': vv,
      'stamps': stamps,
      'conflicts': _unresolvedConflicts([...inherited, ...added], fields),
      if (tombstones.isNotEmpty) 'fieldTombstones': tombstones,
    },
  };
  return RecordMergeResult(result, List.unmodifiable(added));
}

/// A sink for files that fail to load — invoked instead of silently dropping them, so
/// P2.8 (no silent failure) holds: the caller surfaces them for repair.
typedef CorruptSink = void Function(String path, Object error);

Map<String, Map<String, dynamic>> loadDefs(String dir, String key,
    {CorruptSink? onCorrupt}) {
  final out = <String, Map<String, dynamic>>{};
  final d = Directory(dir);
  if (!d.existsSync())
    return out; // an optional subdir (e.g. templates) may be absent
  for (final f in d.listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    try {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      out[j[key] as String] =
          j; // a corrupt/half-synced DEF must NOT throw the whole load
    } catch (e) {
      onCorrupt?.call(
          f.path, e); // surface it (P2.8) rather than crashing startup
    }
  }
  return out;
}

/// Write [json] via a temp file + atomic rename so a crash mid-write can't leave a
/// half-written definition (a torn type file is the worst torn file — every record of
/// that type reads against it). Public wrapper over the record store's atomic write.
void writeJsonAtomic(File file, Object? json) => _atomicWrite(file, json);

/// Per-record files `{id,typeId,fields,_meta}` -> flat in-memory records.
/// Tombstoned records are skipped (a delete stays present-but-invisible), and a
/// single corrupt/partial file is skipped rather than throwing (the folder is a
/// cloud-sync target, so half-written files are expected, not exotic).
Map<String, Map<String, dynamic>> loadRecords(String dir,
    {CorruptSink? onCorrupt}) {
  final store = <String, Map<String, dynamic>>{};
  final d = Directory(dir);
  if (!d.existsSync()) return store;
  for (final f in d.listSync().whereType<File>()) {
    if (!f.path.endsWith('.json')) continue;
    Map<String, dynamic> rec;
    try {
      rec = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (e) {
      onCorrupt?.call(f.path,
          e); // surface it (P2.8), don't brick the whole load OR drop silently
      continue;
    }
    final meta = rec['_meta'];
    if (meta is Map && meta['deleted'] == true)
      continue; // tombstone -> not in the live store
    final fields =
        (rec['fields'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final schemaVersion = rec['schemaVersion'] ?? fields['_schemaVersion'];
    store[rec['id'] as String] = {
      'id': rec['id'],
      'typeId': rec['typeId'],
      if (rec['createdAt'] != null && !fields.containsKey('createdAt'))
        'createdAt': rec['createdAt'],
      for (final entry in fields.entries)
        if (entry.key != '_schemaVersion') entry.key: entry.value,
      if (schemaVersion != null) '_schemaVersion': schemaVersion,
    };
  }
  return store;
}

/// Reverse a turn from its before-images (Spec 02 §5.4 / Spec 04 §3.11): a
/// created record (prior == null) is TOMBSTONED; an updated one is restored.
void undoTurn(Map<String, Map<String, dynamic>?> before, String dir,
    HlcDevice dev, Map<String, Map<String, dynamic>> store) {
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

/// Structural (deep) equality for decoded-JSON values. `==` on List/Map is IDENTITY
/// in Dart, so a `tag`/`list`/`json` field would compare unequal to its own reloaded
/// self and get re-stamped on every write — collapsing those fields back to
/// whole-record LWW, which is exactly what per-field stamps exist to avoid.
bool _sameJson(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List) {
    if (b is! List || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map) {
    if (b is! Map || a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_sameJson(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

/// Flat record -> per-record file. Stamps ONLY fields whose value changed
/// (carrying prior stamps + conflicts forward), so the per-field `_meta` is
/// meaningful at merge time rather than collapsing to whole-record LWW.
///
/// A field that DISAPPEARS from [flat] (the user cleared an optional value) is
/// recorded in `_meta.fieldTombstones` with the stamp of its removal. Dropping it
/// silently — value and stamp both gone — leaves the merge nothing to compare, so
/// a peer's older value for that field resurrects on the next sync: a cleared
/// field un-clears itself. The tombstone is stamped ONCE, at the moment of
/// removal, and carried forward unchanged after that (re-stamping every write
/// would resurrect the same bug in mirror image).
Map<String, dynamic> persist(
    Map<String, dynamic> flat, String dir, HlcDevice dev) {
  Directory(dir).createSync(recursive: true);
  final file = File('$dir/${flat['id']}.json');
  Map<String, dynamic> priorFields = const {},
      priorStamps = const {},
      priorTombs = const {};
  List<dynamic> priorConflicts = const [];
  Map<String, int> priorVector = const {};
  Object? createdAt;
  if (file.existsSync()) {
    try {
      final prev = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      createdAt = prev['createdAt'];
      priorFields = Map<String, dynamic>.from(
          (prev['fields'] as Map?)?.cast<String, dynamic>() ?? const {});
      priorFields.remove('_schemaVersion'); // legacy pre-envelope placement
      createdAt ??= priorFields.remove('createdAt');
      final m = prev['_meta'];
      if (m is Map) {
        priorStamps =
            (m['stamps'] as Map?)?.cast<String, dynamic>() ?? const {};
        priorConflicts = (m['conflicts'] as List?) ?? const [];
        priorTombs =
            (m['fieldTombstones'] as Map?)?.cast<String, dynamic>() ?? const {};
        priorVector = {
          for (final entry in ((m['vv'] as Map?) ?? const {}).entries)
            '${entry.key}': entry.value is int ? entry.value as int : 0,
        };
        for (final stamp in [
          ...priorStamps.values,
          ...priorTombs.values,
          m['deletedStamp'],
        ]) {
          dev.observe(stamp);
        }
      }
    } catch (_) {/* prior unreadable -> treat all fields as changed */}
  }
  createdAt ??= flat['createdAt'] ?? DateTime.now().toUtc().toIso8601String();
  final fields = <String, dynamic>{};
  final stamps = <String, dynamic>{};
  flat.forEach((k, v) {
    if (k == 'id' ||
        k == 'typeId' ||
        k == '_schemaVersion' ||
        k == 'createdAt') {
      return;
    }
    fields[k] = v;
    final unchanged = priorStamps[k] != null &&
        priorFields.containsKey(k) &&
        _sameJson(priorFields[k], v);
    stamps[k] = unchanged ? priorStamps[k] : dev.stamp();
  });
  // Fields that were present (or already tombstoned) and are absent now.
  final tombstones = <String, dynamic>{};
  for (final k in {...priorFields.keys, ...priorTombs.keys}) {
    if (fields.containsKey(k))
      continue; // came back -> live again, no tombstone
    tombstones[k] = priorTombs[k] ?? dev.stamp(); // stamp once, at removal
  }
  final document = <String, dynamic>{
    'id': flat['id'],
    'typeId': flat['typeId'],
    'schemaVersion': flat['_schemaVersion'] ?? 1,
    'createdAt': createdAt,
    'fields': fields,
    '_meta': {
      'vv': {
        ...priorVector,
        dev.id: (priorVector[dev.id] ?? 0) + 1,
      },
      'stamps': stamps,
      'conflicts': priorConflicts,
      if (tombstones.isNotEmpty) 'fieldTombstones': tombstones,
    },
  };
  _atomicWrite(file, document);
  return document;
}

/// Mark a record deleted (a tombstone kept for CRDT convergence) instead of
/// removing the file — a hard delete resurrects on the next sync restore.
void tombstone(String id, String dir, HlcDevice dev) {
  final file = File('$dir/$id.json');
  // Write the tombstone UNCONDITIONALLY — even if the record isn't on disk locally.
  // A delete that arrives for a record synced-in-but-not-yet-persisted must still leave
  // a tombstone, or the record resurrects on the next sync restore.
  Map<String, dynamic> rec;
  try {
    rec = file.existsSync()
        ? (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)
        : <String, dynamic>{'id': id};
  } catch (_) {
    rec = <String, dynamic>{'id': id};
  }
  final meta =
      (rec['_meta'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
  for (final stamp in [
    ...((meta['stamps'] as Map?) ?? const {}).values,
    ...((meta['fieldTombstones'] as Map?) ?? const {}).values,
    meta['deletedStamp'],
  ]) {
    dev.observe(stamp);
  }
  final vector = {
    for (final entry in ((meta['vv'] as Map?) ?? const {}).entries)
      '${entry.key}': entry.value is int ? entry.value as int : 0,
  };
  meta['vv'] = {...vector, dev.id: (vector[dev.id] ?? 0) + 1};
  meta['deleted'] = true;
  meta['deletedStamp'] = dev.stamp();
  rec['_meta'] = meta;
  _atomicWrite(file, rec);
}

/// Replace one record document without restamping it. Used only after a pure
/// merge has produced the converged CRDT state.
void writeRecordDocument(File file, Map<String, dynamic> document) =>
    _atomicWrite(file, document);

/// Write via a temp file + rename so a crash mid-write can't leave a half-written
/// (corrupt) file — at worst the temp file is orphaned.
void _atomicWrite(File file, Object? json) {
  final tmp = File('${file.path}.tmp');
  tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  try {
    // Atomic replace where the OS supports it (POSIX rename overwrites in one step).
    tmp.renameSync(file.path);
  } on FileSystemException {
    // Windows: rename fails if the destination exists. Move the current file ASIDE first
    // (not delete-then-rename) so a crash mid-replace leaves the data recoverable in the
    // .bak or .tmp — never a window where the record is simply gone.
    final bak = File('${file.path}.bak');
    if (bak.existsSync()) bak.deleteSync();
    if (file.existsSync()) file.renameSync(bak.path);
    tmp.renameSync(file.path);
    if (bak.existsSync()) bak.deleteSync();
  }
}
