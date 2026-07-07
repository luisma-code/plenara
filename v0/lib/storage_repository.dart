/// Plenara v0 — the Storage-layer seam (Spec 04 §3.1). Business Logic (Session)
/// holds this INTERFACE, never a concrete file backend — so an iOS
/// file-coordination implementation, an in-memory test double, or the P2
/// CRDT-merge repository can slot in without touching business logic. Today the
/// only implementation wraps the per-record JSON store (store.dart).
library;

import 'dart:convert';
import 'dart:io';

import 'store.dart' as fs;

abstract interface class StorageRepository {
  /// Load type/skill definition files under [subdir], indexed by [key].
  Map<String, Map<String, dynamic>> loadDefs(String subdir, String key);

  /// Hydrate the in-memory record store from disk (tombstones excluded).
  Map<String, Map<String, dynamic>> loadRecords();

  /// Upsert one record, write-through (per-field HLC stamped, atomic).
  void persist(Map<String, dynamic> record);

  /// Delete one record via a tombstone (never a hard delete — that resurrects on sync).
  void remove(String id);

  /// The learned-corpus append log (NLU corrections corpus, Spec 03 §5).
  List<dynamic> loadCorpusLearned();
  void appendCorpusLearned(Map<String, dynamic> entry);

  /// Persist an authored type/skill definition file (Spec 02 §6 authoring).
  void writeDef(String subdir, String idKey, Map<String, dynamic> def);
}

/// The filesystem implementation — the current per-record JSON store.
class FileStorageRepository implements StorageRepository {
  final String dataDir;
  final fs.HlcDevice dev;
  FileStorageRepository(this.dataDir, {fs.HlcDevice? device})
      : dev = device ?? fs.HlcDevice('this-device');

  @override
  Map<String, Map<String, dynamic>> loadDefs(String subdir, String key) =>
      fs.loadDefs('$dataDir/$subdir', key);

  @override
  Map<String, Map<String, dynamic>> loadRecords() => fs.loadRecords('$dataDir/records');

  @override
  void persist(Map<String, dynamic> record) => fs.persist(record, '$dataDir/records', dev);

  @override
  void remove(String id) => fs.tombstone(id, '$dataDir/records', dev);

  @override
  List<dynamic> loadCorpusLearned() {
    final f = File('$dataDir/corpus-learned.json');
    return f.existsSync() ? (jsonDecode(f.readAsStringSync()) as List) : <dynamic>[];
  }

  @override
  void appendCorpusLearned(Map<String, dynamic> entry) {
    final list = loadCorpusLearned()..add(entry);
    File('$dataDir/corpus-learned.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(list));
  }

  @override
  void writeDef(String subdir, String idKey, Map<String, dynamic> def) {
    File('$dataDir/$subdir/${def[idKey]}.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(def));
  }
}
