"""THROWAWAY Phase-0 spike: the state-based CRDT merge for per-record files.

Validates the storage/sync DECISION (planning/specs/storage-sync-assessment.md)
on the Windows box — the substitute for the (hardware-blocked) iOS spike on
everything except iOS-specific dataless-file behavior.

Model: a record is `{id, typeId, fields, _meta}` where `_meta` carries, per
field, a Hybrid Logical Clock stamp `(ms, counter, deviceId)`. Merge is a
per-field Last-Write-Wins register in a map (a well-known CRDT): for each field
take the value with the greater HLC; ties break deterministically by deviceId;
the loser is stashed in `_meta.conflicts` so a real concurrent same-field edit is
VISIBLE (AttentionSurface), never silently dropped. Deletes are tombstones with
their own HLC, so delete-vs-edit resolves by clock like any field.

The provider's file-sync is the anti-entropy channel; merge runs at load. Because
LWW-register maps are commutative, associative, and idempotent, sync order and
duplicate delivery don't matter — which is exactly what an unordered, at-least-
once, whole-file transport (iCloud/OneDrive/Drive) gives you.
"""
from __future__ import annotations


def hlc_gt(a, b):
    """Compare HLC stamps (ms, counter, deviceId); total order, deterministic."""
    return (a["ms"], a["counter"], a["deviceId"]) > (b["ms"], b["counter"], b["deviceId"])


def merge(a, b):
    """Merge two versions of the same record id. Pure; returns a new record."""
    if a is None:
        return b
    if b is None:
        return a
    assert a["id"] == b["id"], "cannot merge different record ids"

    out_fields, out_stamps, conflicts = {}, {}, []
    names = set(a["fields"]) | set(b["fields"])
    ma, mb = a["_meta"]["stamps"], b["_meta"]["stamps"]

    for name in names:
        sa, sb = ma.get(name), mb.get(name)
        if sa and sb and sa != sb:            # both sides have a stamp -> a real race?
            if hlc_gt(sa, sb):
                win_v, win_s, lose_v, lose_s = a["fields"][name], sa, b["fields"].get(name), sb
            else:
                win_v, win_s, lose_v, lose_s = b["fields"][name], sb, a["fields"].get(name), sa
            out_fields[name], out_stamps[name] = win_v, win_s
            # Record only the LOSER (its own value + stamp). The winner is
            # order-dependent (an intermediate merge winner can itself later lose),
            # so recording "kept" breaks associativity; a value is a loser iff some
            # higher-stamped different write to its field exists — order-independent.
            if win_v != lose_v:               # concurrent DIFFERENT values on one field
                conflicts.append({"field": name, "value": lose_v, "at": lose_s})
        elif sa:
            out_fields[name], out_stamps[name] = a["fields"].get(name), sa
        elif sb:
            out_fields[name], out_stamps[name] = b["fields"].get(name), sb

    # tombstone: a delete is a field-like stamp on "_deleted"; clock decides
    da, db = a["_meta"].get("deleted"), b["_meta"].get("deleted")
    deleted = None
    if da and db:
        deleted = da if hlc_gt(da, db) else db
    else:
        deleted = da or db

    prior = a["_meta"].get("conflicts", []) + b["_meta"].get("conflicts", [])
    meta = {"stamps": out_stamps, "conflicts": _dedupe(prior + conflicts)}
    if deleted:
        meta["deleted"] = deleted
    return {"id": a["id"], "typeId": a["typeId"], "fields": out_fields, "_meta": meta}


def _dedupe(rows):
    seen, out = set(), []
    for r in rows:
        # a write's stamp is globally unique (ms, counter, deviceId), so (field, stamp)
        # identifies a dropped write exactly — order-independent.
        k = (r["field"], r["at"]["ms"], r["at"]["counter"], r["at"]["deviceId"])
        if k not in seen:
            seen.add(k)
            out.append(r)
    return out


class Device:
    """Mints monotonic HLC stamps for one device and applies local edits."""
    def __init__(self, device_id, clock_ms):
        self.id = device_id
        self._ms = clock_ms
        self._counter = 0

    def _stamp(self, now_ms):
        # HLC: physical time, but never goes backward; counter breaks equal ms
        if now_ms > self._ms:
            self._ms, self._counter = now_ms, 0
        else:
            self._counter += 1
        return {"ms": self._ms, "counter": self._counter, "deviceId": self.id}

    def new(self, rec_id, type_id, fields, now_ms):
        r = {"id": rec_id, "typeId": type_id, "fields": {}, "_meta": {"stamps": {}, "conflicts": []}}
        for k, v in fields.items():
            r["fields"][k] = v
            r["_meta"]["stamps"][k] = self._stamp(now_ms)
        return r

    def set(self, rec, name, value, now_ms):
        rec = _clone(rec)
        rec["fields"][name] = value
        rec["_meta"]["stamps"][name] = self._stamp(now_ms)
        return rec

    def delete(self, rec, now_ms):
        rec = _clone(rec)
        rec["_meta"]["deleted"] = self._stamp(now_ms)
        return rec


def _clone(r):
    return {"id": r["id"], "typeId": r["typeId"],
            "fields": dict(r["fields"]),
            "_meta": {"stamps": dict(r["_meta"]["stamps"]),
                      "conflicts": list(r["_meta"].get("conflicts", [])),
                      **({"deleted": r["_meta"]["deleted"]} if "deleted" in r["_meta"] else {})}}
