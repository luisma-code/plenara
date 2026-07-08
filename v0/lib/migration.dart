/// Plenara v0 — migrate-on-read (Spec 01 §7.4 / Spec 06 D12). Brings a record written under an
/// older schema forward to its type's current `schemaVersion`: ensures every current attribute is
/// present (a missing one takes its declared `default`, else null) and stamps the record's
/// version. ADDITIVE only — a removed attribute is left in place (harmless, ignored on read); a
/// renamed/retyped attribute needs a declared migration step (deferred, Spec 01 §7.4 open). A
/// record already AT its type's version is returned untouched; a FUTURE-versioned record (written
/// by a newer app) is left intact and surfaced rather than mangled (Spec 06 D12 `versionTooNew`).
library;

/// The version a record was written under (`_schemaVersion`, absent ⇒ 1 per Spec 06 D6).
int recordVersion(Map<String, dynamic> record) => (record['_schemaVersion'] as int?) ?? 1;

/// A type's current schema version (absent ⇒ 1).
int typeVersion(Map<String, dynamic> typeDef) => (typeDef['schemaVersion'] as int?) ?? 1;

/// True when a record is written under a HIGHER version than the type in hand — a newer app
/// touched the synced folder; the record is parked, not migrated (Spec 06 D12).
bool isFutureVersioned(Map<String, dynamic> record, Map<String, dynamic> typeDef) =>
    recordVersion(record) > typeVersion(typeDef);

/// Bring [record] (a flat `{id, typeId, ...fields, _schemaVersion}`) forward to [typeDef]'s
/// version. Returns the (possibly new) record and whether it changed (so the caller re-persists
/// only what moved).
({Map<String, dynamic> record, bool changed}) migrateRecord(
    Map<String, dynamic> record, Map<String, dynamic> typeDef) {
  final rv = recordVersion(record), tv = typeVersion(typeDef);
  if (rv >= tv) return (record: record, changed: false); // current OR future-versioned → untouched
  final out = Map<String, dynamic>.of(record);
  for (final a in ((typeDef['attributes'] as List?) ?? const []).whereType<Map>()) {
    final name = a['name'] as String?;
    if (name == null || out.containsKey(name)) continue;
    out[name] = a['default']; // a newly-added attribute → its declared default, else null
  }
  out['_schemaVersion'] = tv;
  return (record: out, changed: true);
}
