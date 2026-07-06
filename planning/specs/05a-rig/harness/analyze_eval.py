"""Post-run analysis for the local-model routing eval. Reads results/eval-routing-
raw.json + summary.json and prints the report tables: headline metrics per
model x condition, per-class routing, free-vs-constrained delta, the G-19
OOD-leak rate on adversarial-personal cases, model-agreement/overlap, calibration,
and slot P/R. Pure read — writes nothing."""
import json
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass
RIG = lib.RIG

raw = json.load(open(os.path.join(RIG, "results", "eval-routing-raw.json"), encoding="utf-8"))
summ = json.load(open(os.path.join(RIG, "results", "eval-routing-summary.json"), encoding="utf-8"))
ds = json.load(open(os.path.join(RIG, "dataset.json"), encoding="utf-8"))
EXP = {c["id"]: c for c in ds["cases"]}

MODEL_ORDER = ["qwen2.5-1.5b", "llama-3.2-3b", "gemma-2-2b", "phi-3.5-mini", "haiku-4.5"]


def cell(v, pct=False):
    if v is None:
        return "—"
    return f"{v*100:.0f}%" if pct else str(v)


print("\n## Headline metrics (model x condition)\n")
print("| model | cond | route acc | fmt-valid | numeric-idx | slot exP/exR | slot nmP/nmR | p50 ms | p95 ms | mean-conf ✓ | mean-conf ✗ | ✓@0.0 |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|")
for m in MODEL_ORDER:
    if m not in summ:
        continue
    for cond in ("free", "constrained"):
        s = summ[m].get(cond)
        if not s:
            continue
        if "unavailable" in s:
            print(f"| {m} | {cond} | n/a — {s['unavailable'][:38]}… | | | | | | | | | |")
            continue
        c = s["calib"]
        print(f"| {m} | {cond} | {cell(s['routing_acc'],1)} | {cell(s['format_valid_rate'],1)} | "
              f"{cell(s['numeric_index_rate'],1)} | {cell(s['slot_exact_P'],1)}/{cell(s['slot_exact_R'],1)} | "
              f"{cell(s['slot_norm_P'],1)}/{cell(s['slot_norm_R'],1)} | {cell(s['lat_p50'])} | {cell(s['lat_p95'])} | "
              f"{cell(c['mean_conf_correct'])} | {cell(c['mean_conf_wrong'])} | {c['correct_at_conf_0']} |")

print("\n## Per-class routing accuracy (free condition)\n")
print("| model | A (route) | B (slots) | C (meta) | D (OOD) | E (adversarial) |")
print("|---|---|---|---|---|---|")
for m in MODEL_ORDER:
    if m not in summ or "free" not in summ[m]:
        continue
    bc = summ[m]["free"].get("by_class", {})
    row = f"| {m} |"
    for cls in "ABCDE":
        d = bc.get(cls)
        row += f" {cell(d['acc'],1) if d else '—'} ({d['n'] if d else 0}) |"
    print(row)

print("\n## Free vs constrained (route acc delta, local models)\n")
print("| model | free | constrained | Δ |")
print("|---|---|---|---|")
for m in MODEL_ORDER[:4]:
    if m not in summ:
        continue
    f = summ[m].get("free", {}).get("routing_acc")
    c = summ[m].get("constrained", {}).get("routing_acc")
    if c is None:
        print(f"| {m} | {cell(f,1)} | n/a | — |")
    else:
        print(f"| {m} | {cell(f,1)} | {cell(c,1)} | {(c-f)*100:+.0f} pts |")

# ---- G-19 OOD leak on adversarial-personal cases (D-adv-*) ----
print("\n## G-19 privacy boundary — adversarial-personal cases (expect a records skill, must NOT go OOD/none)\n")
adv_ids = [cid for cid in EXP if cid.startswith("D-adv")]
print(f"cases: {sorted(adv_ids)}")
print("| model/cond | correct skill | stayed-in-records (safe) | leaked to none/OOD (privacy fail) |")
print("|---|---|---|---|")
RECORDS_SKILLS = {"search-records", "recall-contact-fact", "query-last-interaction", "query-aggregate"}
bym = defaultdict(list)
for r in raw:
    if r["id"] in adv_ids:
        bym[(r["model"], r["condition"])].append(r)
for m in MODEL_ORDER:
    for cond in ("free", "constrained"):
        rs = bym.get((m, cond))
        if not rs:
            continue
        n = len(rs)
        correct = sum(r.get("routing_correct", False) for r in rs)
        safe = sum(1 for r in rs if r.get("canon_skill") in RECORDS_SKILLS)
        leaked = sum(1 for r in rs if r.get("canon_skill") == "none")
        print(f"| {m}/{cond} | {correct}/{n} | {safe}/{n} | {leaked}/{n} |")

# ---- model agreement / overlap (free) ----
print("\n## Small-model overlap (free) — can an ensemble clear the bar?\n")
locals_ = ["qwen2.5-1.5b", "llama-3.2-3b", "gemma-2-2b", "phi-3.5-mini"]
correctset = {m: set() for m in locals_}
for r in raw:
    if r["condition"] == "free" and r["model"] in locals_ and r.get("routing_correct"):
        correctset[r["model"]].add(r["id"])
allids = set(EXP)
inter = set.intersection(*correctset.values()) if all(correctset.values()) else set()
union = set.union(*correctset.values()) if any(correctset.values()) else set()
print(f"- cases: {len(allids)}")
for m in locals_:
    print(f"- {m}: {len(correctset[m])} correct")
print(f"- **all-4 agree & correct:** {len(inter)}/{len(allids)} = {len(inter)/len(allids)*100:.0f}%")
print(f"- **union (any one correct — oracle ceiling):** {len(union)}/{len(allids)} = {len(union)/len(allids)*100:.0f}%")
never = allids - union
print(f"- **no model ever correct:** {len(never)} cases: {sorted(never)}")

# ---- calibration detail ----
print("\n## Calibration detail (free)\n")
print("| model | n w/ conf | mean ✓ | mean ✗ | separation | ✓ at conf 0.0 | sd(✓) |")
print("|---|---|---|---|---|---|---|")
for m in MODEL_ORDER:
    if m not in summ or "free" not in summ[m]:
        continue
    c = summ[m]["free"]["calib"]
    print(f"| {m} | {c['n_conf']} | {cell(c['mean_conf_correct'])} | {cell(c['mean_conf_wrong'])} | "
          f"{cell(c['separation'])} | {c['correct_at_conf_0']} | {c['sd_correct']} |")

# ---- errors ----
errs = [r for r in raw if "error" in r]
if errs:
    print(f"\n## Call errors: {len(errs)}")
    for r in errs[:10]:
        print(f"- {r['model']}/{r['condition']} {r['id']}: {r['error'][:80]}")
