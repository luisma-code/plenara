"""E4 — Haiku full-inventory cold-start routing (05d candidate R8).

Instead of retrieval truncating to top-K (recall ceiling), hand Haiku the FULL
skill inventory + the utterance and let it pick. Tests the online cold-start
ceiling with no recall bottleneck, on the same held-out set as E2.
Usage: eval_haiku_fullinv.py
"""
import json, os, re, sys
sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402

RIG = lib.RIG
SYS = (
    "You are the intent router for a voice, personal-assistant app. Given the user's "
    "spoken utterance and the FULL list of the app's capabilities, output ONLY the id of "
    "the single best-matching capability. Output exactly 'none' if the utterance is a "
    "general-knowledge or world question the app cannot answer from the user's OWN notes, "
    "logs, trackers, or contacts. Output only the id token, nothing else."
)


def main():
    ds = json.load(open(os.path.join(RIG, "dataset.json"), encoding="utf-8"))
    skills = {}
    for c in ds["cases"]:
        for cand in c.get("candidates", []):
            skills.setdefault(cand["skillId"], cand.get("desc", ""))
    inv = "\n".join(f"- {sid}: {desc}" for sid, desc in sorted(skills.items()))
    valid = set(skills) | {"none"}

    cases = json.load(open(os.path.join(RIG, "heldout.json"), encoding="utf-8"))["cases"]
    rows, cost = [], 0.0
    for c in cases:
        user = f"Capabilities:\n{inv}\n\nUtterance: \"{c['utterance']}\"\n\nBest capability id:"
        r = lib.claude_chat("claude-haiku-4-5", SYS, user, max_tokens=20)
        cost += r["cost_usd"]
        pick = re.sub(r"[^a-z0-9-]", "", r["text"].strip().lower().split()[0]) if r["text"].strip() else ""
        if pick not in valid:  # snap to nearest valid token if it decorated the answer
            pick = next((v for v in valid if v in r["text"].lower()), pick)
        exp = c["expected"]["skillId"]
        rows.append({"id": c["id"], "exp": exp, "pick": pick, "correct": pick == exp,
                     "is_none": exp == "none"})

    real = [r for r in rows if not r["is_none"]]
    none = [r for r in rows if r["is_none"]]
    acc = sum(r["correct"] for r in real) / len(real)
    ood = sum(r["correct"] for r in none) / len(none) if none else 0
    print(f"== E4 Haiku full-inventory (held-out, {len(skills)} skills) ==")
    print(f"real-skill routing: {acc:.1%} (n={len(real)})   OOD-'none' correct: {ood:.0%} (n={len(none)})")
    print(f"total Haiku cost: ${cost:.4f}  (~${cost/len(cases):.5f}/utterance)")
    print("\nmisroutes:")
    for r in real:
        if not r["correct"]:
            print(f"  {r['id']:<20} exp={r['exp']:<22} got={r['pick']}")
    json.dump({"acc": acc, "ood_acc": ood, "cost": round(cost, 4), "rows": rows},
              open(os.path.join(RIG, "results", "eval-haiku-fullinv.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
