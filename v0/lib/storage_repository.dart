/// Plenara v0 — the Storage-layer seam (Spec 04 §3.1). Business Logic (Session)
/// holds this INTERFACE, never a concrete file backend — so an iOS
/// file-coordination implementation, an in-memory test double, or the P2
/// CRDT-merge repository can slot in without touching business logic. Today the
/// only implementation wraps the per-record JSON store (store.dart).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
  void removeCorpusLearned(String template); // §5.2 negative half: forget a bad learned template

  /// Persist an authored type/skill definition file (Spec 02 §6 authoring).
  void writeDef(String subdir, String idKey, Map<String, dynamic> def);

  /// Append one line to the device-local turn log (dogfood telemetry: the
  /// instrument that measures the make-or-break metrics — clarify rate, cloud
  /// rate, correction rate — in real use).
  void logTurn(Map<String, dynamic> entry);
}

/// The filesystem implementation — the current per-record JSON store.
class FileStorageRepository implements StorageRepository {
  final String dataDir;

  /// A DEVICE-LOCAL (non-synced) directory for artifacts that must NOT ride the sync
  /// provider: the per-install `deviceId` (a synced id makes two installs share it and
  /// silently defeats the HLC tie-break) and the `turnlog` (content-bearing telemetry
  /// that would otherwise re-upload every turn and conflict across devices). The app
  /// injects `~/.plenara` (see config.defaultDeviceDir); it defaults to [dataDir] so the
  /// CLI/tests are unchanged.
  final String deviceDir;
  final fs.HlcDevice dev;
  FileStorageRepository(this.dataDir, {String? deviceDir, fs.HlcDevice? device})
      : deviceDir = deviceDir ?? dataDir,
        dev = device ?? fs.HlcDevice(_deviceId(deviceDir ?? dataDir));

  /// A STABLE, per-install device id (persisted in the DEVICE-LOCAL dir), NOT the constant
  /// 'this-device'. The HLC deviceId exists solely to tie-break concurrent per-field
  /// stamps across devices; a shared constant makes two synced installs produce
  /// indistinguishable stamps and silently lose the CRDT tie-break. It must live OUTSIDE
  /// the synced folder — a synced `.device-id` is read by the second install and collides.
  static String _deviceId(String deviceDir) {
    final f = File('$deviceDir/.device-id');
    try {
      if (f.existsSync()) {
        final id = f.readAsStringSync().trim();
        if (id.isNotEmpty) return id;
      }
    } catch (_) {/* fall through to mint a fresh one */}
    final rnd = Random();
    final id = 'dev-${List.generate(12, (_) => rnd.nextInt(16).toRadixString(16)).join()}';
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(id);
    } catch (_) {/* best-effort; a non-persisted id is still better than a shared constant */}
    return id;
  }

  /// Files that failed to parse during load (corrupt / half-synced), surfaced for repair
  /// instead of silently dropped (P2.8). The Session logs these at startup.
  final List<String> corruptFiles = [];
  void _sink(String path, Object _) => corruptFiles.add(path);

  @override
  Map<String, Map<String, dynamic>> loadDefs(String subdir, String key) =>
      fs.loadDefs('$dataDir/$subdir', key, onCorrupt: _sink);

  @override
  Map<String, Map<String, dynamic>> loadRecords() => fs.loadRecords('$dataDir/records', onCorrupt: _sink);

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
  void removeCorpusLearned(String template) {
    final list = loadCorpusLearned().where((e) => (e as Map)['template'] != template).toList();
    File('$dataDir/corpus-learned.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(list));
  }

  @override
  void writeDef(String subdir, String idKey, Map<String, dynamic> def) {
    final f = File('$dataDir/$subdir/${def[idKey]}.json');
    f.parent.createSync(recursive: true);
    fs.writeJsonAtomic(f, def); // atomic: a torn type/skill file is unrecoverable
  }

  @override
  void logTurn(Map<String, dynamic> entry) {
    final f = File('$deviceDir/turnlog.jsonl');
    if (deviceDir != dataDir) f.parent.createSync(recursive: true); // the injected device-local dir may not exist yet
    f.writeAsStringSync('${jsonEncode(entry)}\n', mode: FileMode.append);
  }
}
