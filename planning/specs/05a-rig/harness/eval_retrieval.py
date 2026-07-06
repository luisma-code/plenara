"""G-38: measure the post-NO-GO router as a STACK — retrieval alone.

The G-20 eval pre-supplied each case a correct candidate set; this scores the
thing that is now the actual router: a MiniLM embedding ranking the utterance
against the WHOLE skill set, top-1-with-margin. No model classify step.

Surface per skill = humanized id + desc (NO example phrases — the real system
adds authored examplePhrases as anchors, so these numbers are a conservative
FLOOR). Embedding server: llama-server --embedding (all-MiniLM-L6-v2) on :8090.
"""
import json, os, sys, math, urllib.request
from collections import defaultdict
sys.stdout.reconfigure(encoding="utf-8")

RIG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_PORT = sys.argv[1] if len(sys.argv) > 1 else "8090"
EMBED_URL = f"http://127.0.0.1:{_PORT}/v1/embeddings"


def embed(text):
    body = json.dumps({"input": text}).encode("utf-8")
    req = urllib.request.Request(EMBED_URL, data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)["data"][0]["embedding"]


def cos(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    return dot / (na * nb) if na and nb else 0.0


# Canonical example phrases per skill (hand-written; generic, NOT copied from the
# 57 test utterances). This mirrors the real retrieval surface, which the spec
# says embeds name + description + examplePhrases. Anchors are the design's lever.
PHRASES = {
    "create-task": ["add something to my to-do list", "put this on my list", "i need to remember to do a task"],
    "create-recurring-reminder": ["remind me every week", "set a repeating reminder", "every morning remind me to"],
    "create-reminder": ["remind me later about this", "set a reminder for a time", "ping me about it tomorrow"],
    "log-interaction": ["note that i talked to someone", "record a conversation with a person", "jot down what we discussed"],
    "log-run": ["log a run", "i went running today", "record my run distance"],
    "log-walk": ["log a walk", "i went for a walk", "record my walk"],
    "log-mood": ["log my mood", "record how i feel today", "track my mood"],
    "log-medication": ["log my medication", "i took my meds", "record a dose"],
    "log-meal": ["log a meal", "record what i ate", "track my food today"],
    "log-water": ["log water", "i drank a glass of water", "track my hydration"],
    "log-sleep": ["log my sleep", "record how long i slept", "track last night's sleep"],
    "add-contact-fact": ["remember a fact about someone", "note that a person likes something", "save a detail about a friend"],
    "recall-contact-fact": ["what do i know about someone", "remind me about a person", "tell me a fact about my friend"],
    "query-last-interaction": ["when did i last talk to someone", "how long since i saw a person", "last time i contacted them"],
    "query-aggregate": ["how many times did i do something", "total up my logs", "summarize my tracker over a period"],
    "search-records": ["find a note i wrote", "search my own journal and records", "what did i say about something"],
    "undo": ["undo that", "no take that back", "revert the last thing"],
    "instantiate-template": ["start tracking something new", "make me a tracker for this", "set up a new habit to track"],
}

ds = json.load(open(os.path.join(RIG, "dataset.json"), encoding="utf-8"))
cases = ds["cases"]

# skill universe from the candidate pool: skillId -> desc
skills = {}
for c in cases:
    for cand in c.get("candidates", []):
        skills.setdefault(cand["skillId"], cand.get("desc", ""))

# two surfaces: FLOOR (name+desc) and ANCHORED (name+desc+examplePhrases)
vecs_floor = {sid: embed(f"{sid.replace('-', ' ')}. {desc}") for sid, desc in skills.items()}
vecs_anchor = {sid: embed(f"{sid.replace('-', ' ')}. {desc} " + " ".join(PHRASES.get(sid, [])))
               for sid, desc in skills.items()}
missing = [s for s in skills if s not in PHRASES]
print(f"indexed {len(skills)} skills over {len(cases)} cases; "
      f"phrases missing for: {missing or 'none'}\n")


def ranklist(uv, vecs):
    return sorted(((cos(uv, v), sid) for sid, v in vecs.items()), reverse=True)


rows = []
for c in cases:
    exp = c["expected"]["skillId"]
    uv = embed(c["utterance"])
    sf = ranklist(uv, vecs_floor)
    sa = ranklist(uv, vecs_anchor)
    order = [sid for _, sid in sa]
    rank_of_exp = order.index(exp) + 1 if exp in order else 99
    rows.append({"id": c["id"], "class": c["class"], "exp": exp,
                 "top1": sa[0][1], "s1": round(sa[0][0], 4), "s2": round(sa[1][0], 4),
                 "margin": round(sa[0][0] - sa[1][0], 4), "correct": sa[0][1] == exp,
                 "floor_correct": sf[0][1] == exp, "rank_exp": rank_of_exp,
                 "is_none": exp == "none"})

fl = [r for r in rows if not r["is_none"]]
print(f"== FLOOR (name+desc) top-1: "
      f"{sum(r['floor_correct'] for r in fl) / len(fl):.1%} "
      f"| ANCHORED (+examplePhrases) top-1: {sum(r['correct'] for r in fl) / len(fl):.1%} "
      f"(real-skill n={len(fl)}) ==")
for k in (1, 3, 5, 8):
    rk = sum(1 for r in fl if r["rank_exp"] <= k) / len(fl)
    print(f"   recall@{k} (correct skill in top-{k}): {rk:.1%}")
print("   -> recall@K is what matters if retrieval feeds a top-K set to corpus/Haiku\n")

real = [r for r in rows if not r["is_none"]]
none = [r for r in rows if r["is_none"]]
acc = sum(r["correct"] for r in real) / len(real)
print(f"== Retrieval-only top-1 accuracy (real-skill cases, n={len(real)}): {acc:.1%} ==")
byc = defaultdict(list)
for r in real:
    byc[r["class"]].append(r)
for cls in sorted(byc):
    rs = byc[cls]
    print(f"   class {cls}: {sum(x['correct'] for x in rs)}/{len(rs)} = "
          f"{sum(x['correct'] for x in rs) / len(rs):.0%}")

print("\n== Margin sweep (real-skill cases): dispatch iff margin >= tau ==")
print(f"{'tau':>5} {'dispatch%':>10} {'acc@dispatch':>13} {'clarify%':>9}")
sweep = []
for tau in [0.0, 0.01, 0.02, 0.03, 0.05, 0.08, 0.10, 0.15]:
    disp = [r for r in real if r["margin"] >= tau]
    accd = sum(r["correct"] for r in disp) / len(disp) if disp else 0
    clar = (len(real) - len(disp)) / len(real)
    sweep.append({"tau": tau, "dispatch": len(disp) / len(real),
                  "acc_dispatch": accd, "clarify": clar})
    print(f"{tau:>5.2f} {len(disp) / len(real):>10.0%} {accd:>13.0%} {clar:>9.0%}")

if none:
    print(f"\n== OOD/none cases (n={len(none)}): low margin = correctly ambiguous ==")
    for r in sorted(none, key=lambda x: x["margin"]):
        print(f"   {r['id']:<15} top1={r['top1']:<24} margin={r['margin']:.3f}")

print("\n== Misroutes (real-skill, top1 != expected) ==")
for r in real:
    if not r["correct"]:
        print(f"   {r['id']:<15} exp={r['exp']:<24} got={r['top1']:<24} margin={r['margin']:.3f}")

json.dump({"rows": rows, "sweep": sweep, "acc": acc},
          open(os.path.join(RIG, "results", "eval-retrieval.json"), "w"), indent=1)
print("\n-> results/eval-retrieval.json")
