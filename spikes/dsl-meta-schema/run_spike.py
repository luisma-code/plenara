"""Drives the 3 hand-encoded tasks through the throwaway interpreter and asserts
outcomes. Run: python run_spike.py
"""
import glob
import json
import os
import sys
from datetime import datetime, timedelta

sys.stdout.reconfigure(encoding="utf-8")

from interpreter import Interpreter, ResolveError

HERE = os.path.dirname(os.path.abspath(__file__))
NOW = datetime(2026, 7, 6, 9, 0, 0)   # frozen system input (a Monday)


def load(kind):
    out = {}
    for path in sorted(glob.glob(os.path.join(HERE, kind, "*.json"))):
        d = json.load(open(path, encoding="utf-8"))
        out[d.get("typeId") or d["skillId"]] = d
    return out


def seed_store():
    """A pre-existing store: Sarah exists; some workouts across two weeks."""
    d = lambda days: (NOW.date() + timedelta(days=days)).isoformat()
    recs = [
        {"id": "contact-seed1", "typeId": "contact", "displayName": "Sarah Mitchell", "birthday": "1990-11-14"},
        {"id": "workout-seed1", "typeId": "workout", "activity": "run", "distance": 5, "date": d(0)},    # this week
        {"id": "workout-seed2", "typeId": "workout", "activity": "run", "distance": 3, "date": d(1)},    # this week
        {"id": "workout-seed3", "typeId": "workout", "activity": "run", "distance": 10, "date": d(-8)},  # last week
        {"id": "workout-seed4", "typeId": "workout", "activity": "walk", "distance": 2, "date": d(0)},   # not a run
    ]
    return {r["id"]: r for r in recs}


def run(interp, skills, store, skill_id, slots):
    plan, _ = interp.resolve(skills[skill_id], slots, store)
    interp.execute(plan, store)
    return plan


def main():
    types, skills = load("types"), load("skills")
    print(f"loaded {len(types)} type defs + {len(skills)} skill defs (all as JSON data)\n")
    store = seed_store()
    interp = Interpreter(types, NOW)
    ok = 0

    # --- Static validation gate (authoring-time): all 3 skills must pass ---
    print("── Static validation (Spec 02 §6.4): all authored skills ──")
    for sid, sk in skills.items():
        interp.validate_skill(sk)
    print(f"  ✓ {len(skills)}/{len(skills)} skills pass static entityRef (G-17) validation\n")

    # --- Task 1: simple write + default + date label ---
    print("── Task 1: create-task ──")
    plan = run(interp, skills, store, "create-task",
               {"description": "call the plumber", "dueDate": "2026-07-09"})
    task = plan["writes"][0]
    print("  plan writes:", json.dumps(plan["writes"]))
    print("  says:", plan["confirmation"])
    assert task["completed"] is False, "schema default 'completed=false' not applied (G-02)"
    assert task["description"] == "call the plumber"
    assert "Thursday" in plan["confirmation"], "date label wrong"
    print("  ✓ write + schema-default + format_date label\n"); ok += 1

    # --- Task 2: resolve-or-create + multi-write + entityRefs ---
    print("── Task 2: remember-person-fact (Mia is Sarah's daughter, allergic to peanuts) ──")
    plan = run(interp, skills, store, "remember-person-fact",
               {"personName": "Mia", "fact": "is allergic to peanuts",
                "relationTo": "Sarah Mitchell", "relationType": "daughter"})
    kinds = [w["typeId"] for w in plan["writes"]]
    print("  plan writes:", json.dumps(plan["writes"]))
    print("  says:", plan["confirmation"])
    assert kinds == ["contact", "contact_fact", "contact_relationship"], f"unexpected writes {kinds}"
    mia = plan["writes"][0]
    fact = plan["writes"][1]
    rel = plan["writes"][2]
    assert fact["subject"] == mia["id"], "fact.subject entityRef not the minted Mia id (G-17)"
    assert rel["to"] == mia["id"] and rel["from"] == "contact-seed1", "relationship refs wrong (Sarah resolved from store)"
    assert isinstance(fact["subject"], str), "entityRef must be an id string (G-17)"
    print("  ✓ resolve-or-create (Mia minted, Sarah found) + 3 writes + entityRefs by resolved id\n"); ok += 1

    # --- Task 3: read-only aggregation with foreach + filter ---
    print("── Task 3: count-runs-this-week ──")
    before = len(store)
    plan = run(interp, skills, store, "count-runs-this-week", {})
    print("  says:", plan["confirmation"])
    assert plan["writes"] == [], "aggregation must be read-only (no writes)"
    assert len(store) == before, "read-only skill mutated the store"
    assert "8 km" in plan["confirmation"], f"expected 8 km this week, got: {plan['confirmation']}"
    print("  ✓ read_many+filter + foreach + branch(date>=weekStart) + accumulate, read-only\n"); ok += 1

    # --- Negative: the semantic entityRef validator (G-17) must fire ---
    print("── Guard: entityRef fed by an unresolved NAME must fail validation (G-17) ──")
    bad = {"skillId": "bad", "inputs": [],
           "steps": {"main": [
               {"op": "write_record", "typeId": "contact_fact",
                "fields": {"subject": {"var": "rawName"}, "fact": "x"}, "into": "f"}]}}
    try:
        interp.validate_skill(bad)
        raise AssertionError("static validator did NOT reject an entityRef fed by a raw name var")
    except ResolveError as e:
        assert "G-17" in str(e)
        print(f"  ✓ rejected at authoring time (static, not runtime): {e}\n"); ok += 1

    print(f"══ {ok}/4 checks passed ══")


if __name__ == "__main__":
    main()
