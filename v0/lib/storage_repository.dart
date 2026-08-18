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

  /// Channel gate for the content-bearing turnlog (Spec 11): internal/dev
  /// builds keep it (Luis is the sole beta tester); EXTERNAL builds pass false
  /// and [logTurn] then writes nothing at all — a complete no-op, not an
  /// empty or scrubbed file.
  final bool enableTurnlog;
  final fs.HlcDevice dev;
  FileStorageRepository(this.dataDir,
      {String? deviceDir,
      fs.HlcDevice? device,
      bool? watchSupported,
      this.enableTurnlog = true})
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

  /// Files that failed to load (corrupt / half-synced / shape-defective), surfaced for
  /// repair instead of silently dropped (P2.8). The Session logs these at startup.
  /// Each entry is `path: error` — the CAUSE rides along, so the startup log says
  /// WHY a file was skipped, not just which one. Deduplicated per path.
  final List<String> corruptFiles = [];
  final Set<String> _corruptPaths = {};
  final List<Map<String, dynamic>> recordConflicts = [];
  final List<DefinitionConflict> definitionConflicts = [];
  void _sink(String path, Object error) {
    if (_corruptPaths.add(path)) corruptFiles.add('$path: $error');
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
      // Provider conflict copies, filename/id mismatches, and id-less files are
      // never activated by directory enumeration order. They remain on disk for
      // explicit repair — and they are SURFACED (not silently skipped) by
      // _scanDefinitionConflicts, which runs on every loadRecords.
      if (id is! String) continue;
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
    _recoverCanonicalFromShadow('${record['id']}');
    final document = fs.persist(record, '$dataDir/records', dev);
    _writeShadow('${record['id']}', document);
  }

  @override
  void remove(String id) {
    _recoverCanonicalFromShadow(id);
    fs.tombstone(id, '$dataDir/records', dev);
    final file = File('$dataDir/records/$id.json');
    _writeShadow(
      id,
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
  }

  /// The canonical record file is the prior envelope for persist/tombstone.
  /// When it exists but cannot be parsed (a torn provider write), restore the
  /// device-local shadow — this install's last observed envelope, kept for
  /// exactly this — over it BEFORE rewriting. Without the fallback the rewrite
  /// resets the version vector to {dev: 1}, a peer's copy then strictly
  /// dominates it, and the user's edit (or delete) is silently discarded on
  /// the next sync. The torn canonical is still surfaced via [corruptFiles].
  void _recoverCanonicalFromShadow(String id) {
    final file = File('$dataDir/records/$id.json');
    if (!file.existsSync()) return;
    Object error;
    try {
      jsonDecode(file.readAsStringSync());
      return; // readable — the normal prior-envelope path handles it
    } catch (e) {
      error = e;
    }
    _sink(file.path, error);
    try {
      final shadow = File('${_shadowRecords.path}/$id.json');
      final document =
          jsonDecode(shadow.readAsStringSync()) as Map<String, dynamic>;
      fs.writeRecordDocument(file, document);
    } catch (_) {
      // No usable shadow either: the rewrite restamps from scratch, which is
      // the pre-existing (worst-case) behavior.
    }
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

    // Two passes: the OneDrive conflict pattern is only safe to recognize when
    // its stem id exists canonically, so every readable document is gathered
    // before any filename is classified.
    final readable = <(File, Map<String, dynamic>, String)>[];
    for (final file in records.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final document = _readDocument(file);
      if (document == null) continue; // parse failure already surfaced
      if (document['id'] is! String) {
        // Shape defect: valid JSON, unusable envelope. Surfaced the same way
        // loadRecords surfaces it, so reconcile never silently declines a file
        // and then leaves it behind for a later reader to trip over.
        _sink(
          file.path,
          StateError('Record id is missing or not a string.'),
        );
        continue;
      }
      readable.add((file, document, document['id'] as String));
    }
    final canonicalIds = {
      for (final entry in readable)
        if (entry.$1.uri.pathSegments.last == '${entry.$3}.json') entry.$3,
    };
    for (final (file, document, id) in readable) {
      if (file.uri.pathSegments.last == '$id.json') {
        canonical[id] = document;
      } else if (_isConflictCopy(
        file.uri.pathSegments.last,
        id,
        canonicalExists: canonicalIds.contains(id),
      )) {
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

  /// Does [filename] look like a sync provider's conflict copy of record [id]?
  /// [id] is the id the DOCUMENT declares for itself, so every pattern below is
  /// anchored on the record's own id — a file about a different record can
  /// never match. Known provider spellings:
  ///   - Dropbox:   '<id> (<host>'s conflicted copy <date>).json'
  ///   - iCloud:    '<id> N.json' for N >= 2 (iCloud numbers duplicates from 2)
  ///   - Syncthing: '<id>.sync-conflict-<yyyymmdd>-<hhmmss>-<device>.json'
  ///   - OneDrive:  '<id>-<ComputerName>.json'
  /// The OneDrive shape is a bare hyphen suffix, which a legitimate hyphenated
  /// record id could also produce ('task-1-old.json' is the canonical name of
  /// id 'task-1-old'). It therefore matches ONLY when [canonicalExists] — the
  /// stem id has a canonical '<id>.json' in this records directory — so an
  /// orphaned hyphen-named file is surfaced for repair instead of deleted.
  bool _isConflictCopy(
    String filename,
    String id, {
    required bool canonicalExists,
  }) {
    if (filename.toLowerCase().contains('conflicted copy')) return true;
    final stem = RegExp.escape(id);
    if (RegExp('^$stem ([2-9]|[1-9][0-9]+)\\.json\$').hasMatch(filename)) {
      return true;
    }
    if (RegExp('^$stem\\.sync-conflict-[0-9]{8}-[0-9]{6}-[A-Za-z0-9]+\\.json\$')
        .hasMatch(filename)) {
      return true;
    }
    return canonicalExists && RegExp('^$stem-.+\\.json\$').hasMatch(filename);
  }

  void _scanDefinitionConflicts() {
    definitionConflicts.clear();
    // Every synced definition directory is scanned — templates and automations
    // conflict in a provider folder exactly as often as types and skills do.
    for (final config in const [
      ('types', 'typeId'),
      ('skills', 'skillId'),
      ('templates', 'templateId'),
      ('automations', 'automationId'),
    ]) {
      final dir = Directory('$dataDir/${config.$1}');
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync().whereType<File>()) {
        if (!file.path.endsWith('.json')) continue;
        final document = _readDocument(file);
        if (document == null) continue; // parse failure already surfaced
        final id = document[config.$2];
        if (id is! String) {
          // Valid JSON with no usable id: loadDefs can never activate it, so
          // it must be a visible repair item rather than a silent skip.
          _sink(
            file.path,
            StateError('Definition lacks a string ${config.$2}.'),
          );
          continue;
        }
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

  /// Secret strings registered for turnlog redaction (e.g. the live API key,
  /// registered by the app at startup). Raw audio and SECRETS are forbidden in
  /// EVERY diagnostic channel (Spec 11 Class S) — including the internal one.
  final List<String> _turnlogSecrets = [];

  /// Register a secret value that must never reach the turnlog bytes. Empty or
  /// near-empty strings are ignored (replacing them would shred the log).
  void registerTurnlogSecret(String secret) {
    final value = secret.trim();
    if (value.length >= 4 && !_turnlogSecrets.contains(value)) {
      _turnlogSecrets.add(value);
    }
  }

  /// Credential shapes that are Class S regardless of registration: Anthropic
  /// keys, bearer tokens, x-api-key headers, and PEM private-key blocks.
  static final List<RegExp> _turnlogSecretPatterns = [
    RegExp(r'sk-ant-[A-Za-z0-9-]+'),
    RegExp(r'bearer\s+\S+', caseSensitive: false),
    RegExp(r'x-api-key\s*[:=]\s*\S+', caseSensitive: false),
    // From BEGIN to the matching END inclusive; an unterminated block is
    // redacted through to the end of the entry.
    RegExp(r'-*BEGIN [A-Z ]*PRIVATE KEY[\s\S]*?(?:END [A-Z ]*PRIVATE KEY-*|$)'),
  ];

  /// The Class S boundary, applied BEFORE serialization: every string value in
  /// the entry (recursively, keys included) is scrubbed, whatever code path
  /// produced the entry. Redacting the serialized line instead would let a
  /// whitespace-greedy pattern eat across JSON delimiters.
  Object? _redactTurnlogValue(Object? value) {
    if (value is String) {
      var out = value;
      for (final secret in _turnlogSecrets) {
        out = out.replaceAll(secret, '[redacted]');
      }
      for (final pattern in _turnlogSecretPatterns) {
        out = out.replaceAll(pattern, '[redacted]');
      }
      return out;
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          '${_redactTurnlogValue('${entry.key}')}':
              _redactTurnlogValue(entry.value),
      };
    }
    if (value is List) return value.map(_redactTurnlogValue).toList();
    return value;
  }

  @override
  void logTurn(Map<String, dynamic> entry) {
    if (!enableTurnlog) return; // external build: the channel does not exist
    final f = File('$deviceDir/turnlog.jsonl');
    if (deviceDir != dataDir)
      f.parent.createSync(
          recursive: true); // the injected device-local dir may not exist yet
    f.writeAsStringSync('${jsonEncode(_redactTurnlogValue(entry))}\n',
        mode: FileMode.append);
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
