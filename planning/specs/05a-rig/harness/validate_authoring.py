"""Validate authored artifacts from a results/<example>.json against the closed
DSL vocabulary and schema rules. Reports per-model PASS / ISSUES so we can see
which Claude versions emit interpreter-valid skills (the 'AI authors, code
executes' bet)."""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:  # noqa: BLE001
    pass

CLOSED_OPS = {"read_one", "read_many", "read_related", "write_record",
              "delete_record", "compute", "format", "set", "branch", "foreach"}
VALUE_TYPES = {"text", "number", "decimal", "boolean", "datetime", "date",
               "duration", "enum", "entityRef", "tag", "attachment", "json"}


def strip_fences(t):
    t = t.strip()
    m = re.search(r"```(?:json)?\s*(.*?)```", t, re.DOTALL)
    if m:
        return m.group(1).strip()
    return t


def walk_ops(steps):
    ops = []
    if isinstance(steps, dict):
        for _label, seq in steps.items():
            for st in (seq or []):
                if isinstance(st, dict) and "op" in st:
                    ops.append(st["op"])
    return ops


def validate(art):
    issues = []
    # A decline is a valid authoring outcome (safety refusal) — no type/skill expected.
    declined = (art.get("safetyAssessment") or {}).get("level") == "decline"
    if "safetyAssessment" not in art:
        issues.append("missing safetyAssessment")
    if not declined and "type" not in art and "skill" not in art:
        issues.append("no type or skill authored")
    t = art.get("type", {})
    if t:
        if not t.get("typeId"):
            issues.append("type.typeId missing")
        if len(t.get("examplePhrases", [])) < 3:
            issues.append("type.examplePhrases < 3")
        for a in t.get("attributes", []):
            vt = a.get("valueType")
            if vt not in VALUE_TYPES:
                issues.append(f"attr '{a.get('name')}' bad valueType '{vt}'")
            if vt == "enum" and not a.get("enumValues"):
                issues.append(f"enum attr '{a.get('name')}' missing enumValues")
            if vt == "entityRef" and not a.get("refType"):
                issues.append(f"entityRef attr '{a.get('name')}' missing refType")
    s = art.get("skill", {})
    if s:
        if not s.get("skillId"):
            issues.append("skill.skillId missing")
        if "writes" not in s:
            issues.append("skill.writes missing")
        ops = walk_ops(s.get("steps", {}))
        if not ops:
            issues.append("skill has no ops")
        bad = [o for o in ops if o not in CLOSED_OPS]
        if bad:
            issues.append(f"OUT-OF-VOCAB ops: {sorted(set(bad))}")
        # writes-declared closure: every write_record typeId must be declared
        declared_w = set(s.get("writes", []))
        for _label, seq in (s.get("steps", {}) or {}).items():
            for st in (seq or []):
                if isinstance(st, dict) and st.get("op") == "write_record":
                    if st.get("typeId") and st["typeId"] not in declared_w:
                        issues.append(f"write to undeclared type '{st['typeId']}'")
    return issues


def main():
    path = os.path.join(lib.RIG, "results", sys.argv[1] + ".json")
    data = json.load(open(path, encoding="utf-8"))
    for step in data["steps"]:
        author_rows = [r for r in step.get("claude", []) if "text" in r]
        if not author_rows:
            continue
        print(f"\n=== {data['example']} / step '{step['id']}' — DSL validation ===\n")
        print("| model | JSON | fenced | ops used | verdict |")
        print("|---|---|---|---|---|")
        for r in author_rows:
            raw = strip_fences(r["text"])
            fenced = "yes" if r["text"].strip().startswith("```") else "no"
            try:
                art = json.loads(raw)
            except Exception as e:  # noqa: BLE001
                print(f"| {r['model']} | FAIL | {fenced} | — | ✗ unparseable: {str(e)[:30]} |")
                continue
            ops = sorted(set(walk_ops(art.get("skill", {}).get("steps", {}))))
            issues = validate(art)
            verdict = "✓ valid" if not issues else "✗ " + "; ".join(issues)
            print(f"| {r['model']} | ok | {fenced} | {','.join(ops) or '—'} | {verdict} |")


if __name__ == "__main__":
    main()
