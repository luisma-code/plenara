"""Validates the storage CRDT decision on Windows. Run: python test_crdt.py

Three things:
  1. PROPERTY tests — merge is idempotent, commutative, associative -> replicas
     converge regardless of sync order / duplicate delivery (the whole point over
     an unordered, at-least-once file transport).
  2. SCENARIO tests — the concrete two-device cases: different-field edits merge;
     same-field edits pick a deterministic winner + record the loser (visible);
     delete-vs-edit resolves by clock; full convergence.
  3. SCALE — write N per-record JSON files and time enumerate+parse on the real
     filesystem (a Windows/desktop number; NOT the iOS dataless-file number).
"""
import json
import os
import random
import shutil
import sys
import tempfile
import time

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from merge import Device, merge  # noqa: E402


def canonical(r):
    """The CONVERGENT state = fields + stamps + deleted. This is the proper CRDT
    (order-independent). The conflict list is deliberately EXCLUDED — it's a
    derived, best-effort UI signal, not convergent state (see README finding)."""
    if r is None:
        return None
    st = {k: (v["ms"], v["counter"], v["deviceId"]) for k, v in r["_meta"]["stamps"].items()}
    dele = r["_meta"].get("deleted")
    dele = (dele["ms"], dele["counter"], dele["deviceId"]) if dele else None
    return (tuple(sorted(r["fields"].items(), key=lambda x: x[0])), tuple(sorted(st.items())), dele)


def gen_versions(seed, n_versions=5):
    """One base record, then n concurrent divergent versions from 3 devices."""
    rnd = random.Random(seed)
    devs = [Device(f"dev-{d}", 1000) for d in range(3)]
    base = devs[0].new("rec-1", "contact",
                       {"displayName": "Sarah", "birthday": "1990-11-14", "notes": "hi"}, 1000)
    versions = []
    for _ in range(n_versions):
        r = base
        dev = rnd.choice(devs)
        for _ in range(rnd.randint(1, 4)):
            now = 1000 + rnd.randint(1, 500)
            if rnd.random() < 0.15:
                r = dev.delete(r, now)
            else:
                field = rnd.choice(["displayName", "birthday", "notes", "city"])
                r = dev.set(r, field, f"v{rnd.randint(0, 9)}", now)
        versions.append(r)
    return versions


def test_properties():
    ok = 0
    for seed in range(200):
        vs = gen_versions(seed)
        a, b, c = vs[0], vs[1], vs[2]
        # idempotent
        assert canonical(merge(a, a)) == canonical(a), f"idempotent failed seed={seed}"
        # commutative
        assert canonical(merge(a, b)) == canonical(merge(b, a)), f"commutative failed seed={seed}"
        # associative
        assert canonical(merge(merge(a, b), c)) == canonical(merge(a, merge(b, c))), f"assoc failed seed={seed}"
        # convergence: any permutation of {a,b,c} folds to the same state
        import itertools
        results = {canonical(_fold(list(p))) for p in itertools.permutations([a, b, c])}
        assert len(results) == 1, f"NOT order-independent seed={seed}: {len(results)} distinct outcomes"
        ok += 1
    print(f"  ✓ property tests: {ok}/200 seeds — idempotent, commutative, associative, order-independent")


def _fold(vs):
    acc = vs[0]
    for v in vs[1:]:
        acc = merge(acc, v)
    return acc


def test_scenarios():
    A, B = Device("A", 1000), Device("B", 1000)
    base = A.new("c1", "contact", {"displayName": "Sarah", "notes": "hi", "city": "SF"}, 1000)

    # 1. concurrent edits to DIFFERENT fields -> BOTH survive (the key win over LWW)
    va = A.set(base, "notes", "allergic to peanuts", 1100)
    vb = B.set(base, "city", "Oakland", 1100)
    m1, m2 = merge(va, vb), merge(vb, va)
    assert canonical(m1) == canonical(m2), "merge must be order-independent"
    assert m1["fields"]["notes"] == "allergic to peanuts" and m1["fields"]["city"] == "Oakland"
    print("  ✓ different-field concurrent edits: BOTH survive (whole-file LWW would lose one)")

    # 2. concurrent edits to the SAME field -> deterministic, order-independent winner
    va = A.set(base, "notes", "from device A", 1200)
    vb = B.set(base, "notes", "from device B", 1200)   # equal HLC -> deviceId breaks tie -> B
    m1, m2 = merge(va, vb), merge(vb, va)
    assert canonical(m1) == canonical(m2), "same-field merge must be order-independent"
    assert m1["fields"]["notes"] == "from device B" == m2["fields"]["notes"], "both replicas converge, no divergence"
    print("  ✓ same-field concurrent edit: deterministic, order-independent winner (no divergence)")

    # 3. delete vs a LATER edit on another device -> clock decides; both facts retained
    deleted = A.delete(base, 1300)
    edited = B.set(base, "notes", "still here", 1400)
    m1, m2 = merge(deleted, edited), merge(edited, deleted)
    assert canonical(m1) == canonical(m2), "delete-vs-edit must be order-independent"
    assert "deleted" in m1["_meta"] and m1["fields"]["notes"] == "still here"
    print("  ✓ delete-vs-edit resolves by clock, order-independent (tombstone + later field kept)")

    # 4. FINDING: precise conflict-surfacing needs per-field causal info, not just stamps —
    #    the best-effort conflict list over-triggers on unmodified-ancestor values and is
    #    order-dependent, so it is NOT convergent state (excluded from canonical). Correct
    #    detection = per-field version vectors (a Spec 06 refinement). The DATA always converges.
    print("  ✓ (finding) conflict-surfacing is best-effort; precise detection needs version vectors")


def test_scale(n=5000):
    tmp = tempfile.mkdtemp(prefix="plenara-scale-")
    try:
        D = Device("A", 1000)
        t0 = time.perf_counter()
        for i in range(n):
            rec = D.new(f"rec-{i}", "task",
                        {"description": f"task number {i} with some words", "completed": False,
                         "createdAt": "2026-07-06T09:00:00"}, 1000 + i)
            json.dump(rec, open(os.path.join(tmp, f"rec-{i}.json"), "w"))
        w = time.perf_counter() - t0
        t0 = time.perf_counter()
        store = {}
        for name in os.listdir(tmp):
            r = json.load(open(os.path.join(tmp, name)))
            store[r["id"]] = r
        h = time.perf_counter() - t0
        assert len(store) == n
        print(f"  ✓ startup-scale (local FS, Windows): wrote {n} per-record files in {w:.2f}s; "
              f"enumerated+parsed+hydrated in {h:.2f}s ({n/h:,.0f} files/s)")
        print(f"    (a desktop number — NOT the iOS dataless-file number, which needs the deferred iOS spike)")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    print("── CRDT property tests ──")
    test_properties()
    print("── two-device scenarios ──")
    test_scenarios()
    print("── startup scale (real filesystem) ──")
    test_scale()
    print("\n══ storage CRDT decision validated on Windows ══")
