/// Plenara v0 — the Storage-layer seam (Spec 04 §3.1). Business Logic (Session)
/// holds this INTERFACE, never a concrete file backend — so an iOS
/// file-coordination implementation, an in-memory test double, or the P2
/// CRDT-merge repository can slot in without touching business logic. Today the
/// only implementation wraps the per-record JSON store (store.dart).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'store.dart' as fs;

class DefinitionDocument {
  final String filename;
  final Map<String, dynamic> definition;
  const DefinitionDocument(this.filename, this.definition);
}

class MigrationBackup {
  final String recordId;
  final String typeId;
  final int fromVersion;
  final int toVersion;
  final String path;

  const MigrationBackup({
    required this.recordId,
    required this.typeId,
    required this.fromVersion,
    required this.toVersion,
    required this.path,
  });
}

class DefinitionConflict {
  final String subdir;
  final String id;
  final String canonicalPath;
  final String conflictingPath;

  const DefinitionConflict({
    required this.subdir,
    required this.id,
    required this.canonicalPath,
    required this.conflictingPath,
  });
}

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
  void removeCorpusLearned(
      String template); // §5.2 negative half: forget a bad learned template

  /// Persist an authored type/skill definition file (Spec 02 §6 authoring).
  void writeDef(String subdir, String idKey, Map<String, dynamic> def);

  /// Remove an authored definition file. Needed because activation is now VERIFIED with the user
  /// ("is that what you wanted?") — a no has to actually undo the capability, not just apologise.
  void removeDef(String subdir, String id);

  /// Append one line to the device-local turn log (dogfood telemetry: the
  /// instrument that measures the make-or-break metrics — clarify rate, cloud
  /// rate, correction rate — in real use).
  void logTurn(Map<String, dynamic> entry);
}

/// The filesystem implementation — the current per-record JSON store.
class FileStorageRepository implements StorageRepository {
  final String dataDir;
  final bool watchSupported;

  /// A DEVICE-LOCAL (non-synced) directory for artifacts that must NOT ride the sync
  /// provider: the per-install `deviceId` (a synced id makes two installs share it and
  /// silently defeats the HLC tie-break) and the `turnlog` (content-bearing telemetry
  /// that would otherwise re-upload every turn and conflict across devices). The app
  /// injects `~/.plenara` (see config.defaultDeviceDir); it defaults to [dataDir] so the
  /// CLI/tests are unchanged.
  final String deviceDir;
  final fs.HlcDevice dev;
  FileStorageRepository(this.dataDir,
      {String? deviceDir, fs.HlcDevice? device, bool? watchSupported})
      : deviceDir = deviceDir ?? dataDir,
        // dart:io recursive Directory.watch is unavailable on physical iOS.
        // Keep startup usable there; the store still reconciles on every open.
        watchSupported = watchSupported ?? !Platform.isIOS,
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
    final id =
        'dev-${List.generate(12, (_) => rnd.nextInt(16).toRadixString(16)).join()}';
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(id);
    } catch (_) {
      /* best-effort; a non-persisted id is still better than a shared constant */
    }
    return id;
  }

  /// Files that failed to parse during load (corrupt / half-synced), surfaced for repair
  /// instead of silently dropped (P2.8). The Session logs these at startup.
  final List<String> corruptFiles = [];
  final List<Map<String, dynamic>> recordConflicts = [];
  final List<DefinitionConflict> definitionConflicts = [];
  void _sink(String path, Object _) {
    if (!corruptFiles.contains(path)) corruptFiles.add(path);
  }

  @override
  Map<String, Map<String, dynamic>> loadDefs(String subdir, String key) {
    final loaded = <String, Map<String, dynamic>>{};
    final dir = Directory('$dataDir/$subdir');
    if (!dir.existsSync()) return loaded;
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final document = _readDocument(file);
      final id = document?[key];
      if (id is! String) continue;
      // Provider conflict copies and filename/id mismatches are never activated
      // by directory enumeration order. They remain on disk for explicit repair.
      if (file.uri.pathSegments.last != '$id.json') continue;
      loaded[id] = document!;
    }
    return loaded;
  }

  /// Raw definition documents preserve filenames and duplicates for the
  /// SchemaRegistry hydration boundary. Indexing first would silently erase
  /// both filename/id mismatches and duplicate ids.
  List<DefinitionDocument> loadDefDocuments(String subdir) {
    final dir = Directory('$dataDir/$subdir');
    if (!dir.existsSync()) return const [];
    final out = <DefinitionDocument>[];
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      try {
        final value =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        out.add(DefinitionDocument(file.uri.pathSegments.last, value));
      } catch (error) {
        _sink(file.path, error);
      }
    }
    return out;
  }

  @override
  Map<String, Map<String, dynamic>> loadRecords() {
    reconcileRecords();
    _scanDefinitionConflicts();
    return fs.loadRecords('$dataDir/records', onCorrupt: _sink);
  }

  @override
  void persist(Map<String, dynamic> record) {
    final document = fs.persist(record, '$dataDir/records', dev);
    _writeShadow('${record['id']}', document);
  }

  @override
  void remove(String id) {
    fs.tombstone(id, '$dataDir/records', dev);
    final file = File('$dataDir/records/$id.json');
    _writeShadow(
      id,
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
  }

  Directory get _shadowRecords => Directory('$deviceDir/sync-shadow/records');

  void _writeShadow(String id, Map<String, dynamic> document) {
    final file = File('${_shadowRecords.path}/$id.json');
    file.parent.createSync(recursive: true);
    fs.writeRecordDocument(file, document);
  }

  Map<String, dynamic>? _readDocument(File file) {
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (error) {
      _sink(file.path, error);
      return null;
    }
  }

  /// Reconcile the provider-visible record directory with this install's last
  /// observed state. The shadow is device-local, so an overwrite-style sync
  /// provider cannot erase a local branch before the CRDT sees both versions.
  bool reconcileRecords() {
    final records = Directory('$dataDir/records');
    records.createSync(recursive: true);
    _shadowRecords.createSync(recursive: true);
    final canonical = <String, Map<String, dynamic>>{};
    final variants = <String, List<(File, Map<String, dynamic>)>>{};
    final shadows = <String, Map<String, dynamic>>{};

    for (final file in records.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final document = _readDocument(file);
      if (document == null || document['id'] is! String) continue;
      final id = document['id'] as String;
      final canonicalName = '$id.json';
      if (file.uri.pathSegments.last == canonicalName) {
        canonical[id] = document;
      } else if (_isConflictCopy(file.uri.pathSegments.last, id)) {
        (variants[id] ??= []).add((file, document));
      } else {
        _sink(
          file.path,
          StateError('Record filename does not match its id.'),
        );
      }
    }
    for (final file in _shadowRecords.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final document = _readDocument(file);
      if (document != null && document['id'] is String) {
        shadows[document['id'] as String] = document;
      }
    }

    var changed = false;
    recordConflicts.clear();
    for (final id in {...canonical.keys, ...variants.keys, ...shadows.keys}) {
      Map<String, dynamic>? merged = shadows[id] ?? canonical[id];
      final candidates = <Map<String, dynamic>>[
        if (shadows[id] != null && canonical[id] != null) canonical[id]!,
        for (final variant in variants[id] ?? const []) variant.$2,
      ];
      for (final candidate in candidates) {
        if (merged == null) {
          merged = candidate;
          continue;
        }
        final result = fs.mergeRecordDocuments(merged, candidate);
        merged = result.document;
      }
      if (merged == null) continue;
      final target = File('${records.path}/$id.json');
      final current = canonical[id];
      if (current == null || jsonEncode(current) != jsonEncode(merged)) {
        fs.writeRecordDocument(target, merged);
        changed = true;
      }
      _writeShadow(id, merged);
      for (final variant in variants[id] ?? const []) {
        if (variant.$1.existsSync()) variant.$1.deleteSync();
        changed = true;
      }
      final meta = (merged['_meta'] as Map?) ?? const {};
      for (final conflict in ((meta['conflicts'] as List?) ?? const [])) {
        if (conflict is Map) {
          recordConflicts.add({
            'recordId': id,
            ...Map<String, dynamic>.from(conflict),
          });
        }
      }
      for (final stamp in [
        ...((meta['stamps'] as Map?) ?? const {}).values,
        ...((meta['fieldTombstones'] as Map?) ?? const {}).values,
        meta['deletedStamp'],
      ]) {
        dev.observe(stamp);
      }
    }
    return changed;
  }

  void clearRecordConflicts(String id, String field) {
    final file = File('$dataDir/records/$id.json');
    final document = _readDocument(file);
    if (document == null) return;
    final meta = Map<String, dynamic>.from(
      (document['_meta'] as Map?) ?? const {},
    );
    meta['conflicts'] = ((meta['conflicts'] as List?) ?? const [])
        .where((value) => value is! Map || '${value['field']}' != field)
        .toList();
    document['_meta'] = meta;
    fs.writeRecordDocument(file, document);
    _writeShadow(id, document);
    reconcileRecords();
  }

  void resolveDefinitionConflict(
    DefinitionConflict conflict, {
    required bool useConflicting,
  }) {
    final conflicting = File(conflict.conflictingPath);
    final canonical = File(conflict.canonicalPath);
    if (useConflicting) {
      final document = _readDocument(conflicting);
      if (document == null) return;
      fs.writeJsonAtomic(canonical, document);
    }
    if (conflicting.existsSync()) conflicting.deleteSync();
    _scanDefinitionConflicts();
  }

  bool _isConflictCopy(String filename, String id) {
    final lower = filename.toLowerCase();
    return lower.contains('conflicted copy') || filename == '$id 2.json';
  }

  void _scanDefinitionConflicts() {
    definitionConflicts.clear();
    for (final config in const [('types', 'typeId'), ('skills', 'skillId')]) {
      final dir = Directory('$dataDir/${config.$1}');
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync().whereType<File>()) {
        if (!file.path.endsWith('.json')) continue;
        final document = _readDocument(file);
        final id = document?[config.$2];
        if (id is! String) continue;
        final canonical = File('${dir.path}/$id.json');
        if (file.absolute.path != canonical.absolute.path) {
          definitionConflicts.add(DefinitionConflict(
            subdir: config.$1,
            id: id,
            canonicalPath: canonical.path,
            conflictingPath: file.path,
          ));
        }
      }
    }
  }

  /// Positive provider/file-system events drive refresh; no polling timer is
  /// used. Callers serialize reconciliation with active turns.
  Stream<void> watchChanges() {
    final root = Directory(dataDir)..createSync(recursive: true);
    if (!watchSupported) return const Stream<void>.empty();
    return root.watch(recursive: true).where((event) {
      final relative = event.path.startsWith(root.path)
          ? event.path.substring(root.path.length)
          : event.path;
      return relative.startsWith(
              '${Platform.pathSeparator}records${Platform.pathSeparator}') ||
          relative.startsWith(
              '${Platform.pathSeparator}types${Platform.pathSeparator}') ||
          relative.startsWith(
              '${Platform.pathSeparator}skills${Platform.pathSeparator}');
    }).map((_) {});
  }

  /// Preserve the exact pre-migration record bytes in device-local storage.
  /// Backups are immutable and deterministic, so a restart cannot overwrite
  /// the only rollback point with a partly migrated file.
  MigrationBackup backupForMigration(
    Map<String, dynamic> record,
    int toVersion,
  ) {
    final id = record['id'] as String;
    final typeId = record['typeId'] as String;
    final fromVersion = (record['_schemaVersion'] as int?) ?? 1;
    final safeId = base64Url.encode(utf8.encode(id)).replaceAll('=', '');
    final safeType = base64Url.encode(utf8.encode(typeId)).replaceAll('=', '');
    final source = File('$dataDir/records/$id.json');
    if (!source.existsSync()) {
      throw FileSystemException('Record source is missing', source.path);
    }
    final target = File(
      '$deviceDir/migration-backups/'
      '$safeType--$safeId--v$fromVersion-to-v$toVersion.json',
    );
    if (!target.existsSync()) {
      target.parent.createSync(recursive: true);
      final temp = File('${target.path}.tmp');
      temp.writeAsBytesSync(source.readAsBytesSync(), flush: true);
      temp.renameSync(target.path);
    }
    return MigrationBackup(
      recordId: id,
      typeId: typeId,
      fromVersion: fromVersion,
      toVersion: toVersion,
      path: target.path,
    );
  }

  /// Restore the exact file captured by [backupForMigration]. The descriptor
  /// must point inside this repository's device-local migration backup root.
  void restoreMigrationBackup(MigrationBackup backup) {
    final root = Directory('$deviceDir/migration-backups').absolute.path;
    final source = File(backup.path).absolute;
    if (!source.path.startsWith('$root${Platform.pathSeparator}') ||
        !source.existsSync()) {
      throw FileSystemException('Invalid migration backup', source.path);
    }
    final target = File('$dataDir/records/${backup.recordId}.json');
    target.parent.createSync(recursive: true);
    final temp = File('${target.path}.migration-restore.tmp');
    temp.writeAsBytesSync(source.readAsBytesSync(), flush: true);
    temp.renameSync(target.path);
    _writeShadow(
      backup.recordId,
      jsonDecode(target.readAsStringSync()) as Map<String, dynamic>,
    );
  }

  /// The learned corpus is a whole-file rewrite on every learn/forget. A torn write here used to
  /// be fatal at NEXT LAUNCH — Router.load jsonDecodes it during init, so truncated JSON threw
  /// before the app could open, and stayed fatal until the file was deleted by hand. Reads now
  /// degrade to "nothing learned yet" (surfaced via [corruptFiles]) and writes are atomic.
  @override
  List<dynamic> loadCorpusLearned() {
    final f = File('$dataDir/corpus-learned.json');
    if (!f.existsSync()) return <dynamic>[];
    try {
      return jsonDecode(f.readAsStringSync()) as List;
    } catch (e) {
      _sink(f.path,
          e); // P2.8 — surfaced for repair, never a silent drop and never fatal
      return <dynamic>[];
    }
  }

  @override
  void appendCorpusLearned(Map<String, dynamic> entry) {
    final list = loadCorpusLearned()..add(entry);
    fs.writeJsonAtomic(File('$dataDir/corpus-learned.json'), list);
  }

  @override
  void removeCorpusLearned(String template) {
    final list = loadCorpusLearned()
        .where((e) => e is! Map || e['template'] != template)
        .toList();
    fs.writeJsonAtomic(File('$dataDir/corpus-learned.json'), list);
  }

  @override
  void writeDef(String subdir, String idKey, Map<String, dynamic> def) {
    final f = File('$dataDir/$subdir/${def[idKey]}.json');
    f.parent.createSync(recursive: true);
    fs.writeJsonAtomic(
        f, def); // atomic: a torn type/skill file is unrecoverable
  }

  @override
  void removeDef(String subdir, String id) {
    final f = File('$dataDir/$subdir/$id.json');
    if (f.existsSync()) f.deleteSync();
  }

  @override
  void logTurn(Map<String, dynamic> entry) {
    final f = File('$deviceDir/turnlog.jsonl');
    if (deviceDir != dataDir)
      f.parent.createSync(
          recursive: true); // the injected device-local dir may not exist yet
    f.writeAsStringSync('${jsonEncode(entry)}\n', mode: FileMode.append);
  }

  /// Schedule-automation lastFired state (autoId → time), DEVICE-LOCAL: it's per-install
  /// bookkeeping (when this device last fired each schedule), not synced user data.
  Map<String, DateTime> loadAutomationState() {
    final f = File('$deviceDir/automation-state.json');
    if (!f.existsSync()) return {};
    try {
      final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return {
        for (final e in m.entries) e.key: DateTime.parse(e.value as String)
      };
    } catch (_) {
      return {}; // corrupt state -> start fresh (a missed fire, never a crash)
    }
  }

  void saveAutomationState(Map<String, DateTime> state) {
    final f = File('$deviceDir/automation-state.json');
    if (deviceDir != dataDir) f.parent.createSync(recursive: true);
    fs.writeJsonAtomic(
        f, {for (final e in state.entries) e.key: e.value.toIso8601String()});
  }
}
