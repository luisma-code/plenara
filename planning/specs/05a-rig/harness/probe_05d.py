"""05d routing-design feasibility probes (THROWAWAY — sanity checks, not the eval).

Probes the premises behind the 05d candidate slate, against dataset.json:
  P0  base_single   : replicate eval_retrieval.py anchored single-vector (sanity ~47%)
  P1  multi         : multi-vector max-sim (name+desc vec + one vec PER example phrase)
  P2  multi+gate    : P1 + deterministic act-type partition (query/prospective/
                      instantiate/capture) restricting the candidate skill set
  P3  multi+bm25    : P1 fused with BM25 lexical scores via reciprocal-rank fusion
  P4  syn           : max-sim over ~20 Haiku-GENERATED anchor phrases per skill
  P5  syn+gate      : P4 + act-type gate
  P6  syn+gate+bm25 : the full factored hybrid

CAVEAT (recorded in 05d): the act-type rules were written while looking at this
dataset — treat gate numbers as an upper-ish bound pending a held-out set.
Usage: venv/Scripts/python.exe harness/probe_05d.py [port]  (embed server on :8090)
"""
import json, math, os, re, sys, urllib.request
from collections import defaultdict

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402

RIG = lib.RIG
PORT = sys.argv[1] if len(sys.argv) > 1 else "8090"
EMBED_URL = f"http://127.0.0.1:{PORT}/v1/embeddings"
ANCHOR_CACHE = os.path.join(RIG, "results", "probe-synthetic-anchors.json")

_embed_cache = {}


def embed(text):
    if text in _embed_cache:
        return _embed_cache[text]
    body = json.dumps({"input": text}).encode("utf-8")
    req = urllib.request.Request(EMBED_URL, data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        v = json.load(r)["data"][0]["embedding"]
    _embed_cache[text] = v
    return v


def cos(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    return dot / (na * nb) if na and nb else 0.0


# ---- hand-written canonical phrases (same as eval_retrieval.py + show-streak,
# which that script reported missing; style-matched, not copied from test set) --
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
    "show-streak": ["what's my current streak", "how many days in a row have i done it", "show my habit streak"],
}

# ---- act-type partition ------------------------------------------------------
QUERY_SKILLS = {"recall-contact-fact", "query-last-interaction", "query-aggregate",
                "search-records", "show-streak"}
PROSPECTIVE_SKILLS = {"create-task", "create-reminder", "create-recurring-reminder"}
INSTANTIATE_SKILLS = {"instantiate-template"}
# capture = everything else (log-*, add-contact-fact, log-interaction); undo is
# a rule-prefilter system command in the real design, kept in capture here.

TWIN_GROUP = {"create-task", "create-reminder", "create-recurring-reminder"}


def act_type(utt):
    u = utt.lower().strip()
    if re.search(r"^(what|when|how|who|where|which|do i|did i|have i)\b"
                 r"|what'?s\b|\bfind\b|pull up|search|look up|remind me what"
                 r"|what do i know", u):
        return "query"
    if re.search(r"remind me (to|about|every)|\badd .* to my\b|\bput .* on my\b"
                 r"|^i need to\b|set (up )?a .*reminder|^every\b", u):
        return "prospective"
    if re.search(r"start(ed)? track|begin track|want to start|start a .*tracker"
                 r"|make me a tracker|^track (my|the|which)|set up a new", u):
        return "instantiate"
    return "capture"


def partition_for(at, all_ids):
    if at == "query":
        return QUERY_SKILLS & all_ids
    if at == "prospective":
        return PROSPECTIVE_SKILLS & all_ids
    if at == "instantiate":
        return INSTANTIATE_SKILLS & all_ids
    return all_ids - QUERY_SKILLS - PROSPECTIVE_SKILLS - INSTANTIATE_SKILLS


# ---- BM25 --------------------------------------------------------------------
def toks(s):
    return re.findall(r"[a-z0-9']+", s.lower())


class BM25:
    def __init__(self, docs):  # docs: {id: text}
        self.k1, self.b = 1.5, 0.75
        self.docs = {i: toks(t) for i, t in docs.items()}
        self.avgdl = sum(len(d) for d in self.docs.values()) / len(self.docs)
        self.df = defaultdict(int)
        for d in self.docs.values():
            for w in set(d):
                self.df[w] += 1
        self.N = len(self.docs)

    def score(self, query, did):
        d = self.docs[did]
        dl = len(d)
        tf = defaultdict(int)
        for w in d:
            tf[w] += 1
        s = 0.0
        for w in set(toks(query)):
            if w not in self.df:
                continue
            idf = math.log(1 + (self.N - self.df[w] + 0.5) / (self.df[w] + 0.5))
            f = tf[w]
            s += idf * f * (self.k1 + 1) / (f + self.k1 * (1 - self.b + self.b * dl / self.avgdl))
        return s


def rrf(rank_lists, k=60):
    """rank_lists: list of [skillId ordered best-first]. Returns {id: fused}."""
    fused = defaultdict(float)
    for rl in rank_lists:
        for r, sid in enumerate(rl):
            fused[sid] += 1.0 / (k + r + 1)
    return fused


# ---- synthetic anchors ---------------------------------------------------------
GEN_SYS = (
    "You generate training utterances for a voice assistant's intent router. "
    "Given one capability (id, description, slots), write EXACTLY 20 short, diverse "
    "utterances a user might SAY OUT LOUD to invoke it. Vary style: terse fragments, "
    "casual full sentences, a couple with disfluencies (um, uh), concrete example "
    "values for slots (names, numbers, dates). Do NOT mention the capability id. "
    "One utterance per line, no numbering, no quotes, no commentary."
)


def gen_anchors(skills_meta):
    if os.path.exists(ANCHOR_CACHE):
        return json.load(open(ANCHOR_CACHE, encoding="utf-8"))
    out = {}
    total_cost = 0.0
    for sid, meta in skills_meta.items():
        user = (f"Capability id: {sid}\nDescription: {meta['desc']}\n"
                f"Slots: {', '.join(meta['slots']) or '(none)'}")
        r = lib.claude_chat("claude-haiku-4-5", GEN_SYS, user, max_tokens=500)
        total_cost += r["cost_usd"]
        lines = [ln.strip(" -\"'") for ln in r["text"].splitlines() if ln.strip()]
        out[sid] = [ln for ln in lines if 2 <= len(ln) <= 120][:20]
        print(f"  gen {sid}: {len(out[sid])} phrases (${r['cost_usd']:.4f})")
    json.dump(out, open(ANCHOR_CACHE, "w", encoding="utf-8"), indent=1)
    print(f"  -> cached {ANCHOR_CACHE}  total ${total_cost:.4f}")
    return out


# ---- scoring ----------------------------------------------------------------
def score_config(cases, skill_vecs, all_ids, bm25=None, gate=False):
    """skill_vecs: {sid: [vec, ...]} (max-sim). Returns rows."""
    rows = []
    for c in cases:
        exp = c["expected"]["skillId"]
        uv = embed(c["utterance"])
        cand = partition_for(act_type(c["utterance"]), all_ids) if gate else all_ids
        if not cand:
            cand = all_ids
        dense = {sid: max(cos(uv, v) for v in skill_vecs[sid]) for sid in cand}
        if bm25 is not None:
            drank = [s for s, _ in sorted(dense.items(), key=lambda x: -x[1])]
            brank = sorted(cand, key=lambda s: -bm25.score(c["utterance"], s))
            fused = rrf([drank, brank])
            order = sorted(cand, key=lambda s: -fused[s])
        else:
            order = sorted(cand, key=lambda s: -dense[s])
        srt = sorted(dense.values(), reverse=True)
        s1 = srt[0]
        s2 = srt[1] if len(srt) > 1 else 0.0
        rank_exp = order.index(exp) + 1 if exp in order else 99
        rows.append({"id": c["id"], "class": c["class"], "exp": exp,
                     "top1": order[0], "s1": round(s1, 4),
                     "margin": round(s1 - s2, 4),
                     "correct": order[0] == exp, "rank_exp": rank_exp,
                     "gate_excluded": exp != "none" and exp not in cand,
                     "is_none": exp == "none"})
    return rows


def report(name, rows):
    real = [r for r in rows if not r["is_none"]]
    nones = [r for r in rows if r["is_none"]]
    acc = sum(r["correct"] for r in real) / len(real)
    # group accuracy: within the task/reminder twin group, any member counts
    gacc = sum(1 for r in real
               if r["correct"] or (r["exp"] in TWIN_GROUP and r["top1"] in TWIN_GROUP)
               ) / len(real)
    r5 = sum(1 for r in real if r["rank_exp"] <= 5) / len(real)
    r8 = sum(1 for r in real if r["rank_exp"] <= 8) / len(real)
    gx = sum(r["gate_excluded"] for r in real)
    byc = defaultdict(list)
    for r in real:
        byc[r["class"]].append(r)
    cls = " ".join(f"{c}:{sum(x['correct'] for x in byc[c])}/{len(byc[c])}"
                   for c in sorted(byc))
    # OOD signal: mean top-1 sim, real vs none
    m_real = sum(r["s1"] for r in real) / len(real)
    m_none = sum(r["s1"] for r in nones) / len(nones) if nones else 0
    print(f"{name:<16} top1={acc:5.1%}  group={gacc:5.1%}  r@5={r5:5.1%}  "
          f"r@8={r8:5.1%}  gate-excl={gx}  [{cls}]  s1 real/none={m_real:.3f}/{m_none:.3f}")
    return {"name": name, "acc": acc, "group_acc": gacc, "r5": r5, "r8": r8,
            "gate_excluded": gx, "s1_real": m_real, "s1_none": m_none,
            "rows": rows}


def main():
    ds = json.load(open(os.path.join(RIG, "dataset.json"), encoding="utf-8"))
    cases = ds["cases"]
    skills_meta = {}
    for c in cases:
        for cand in c.get("candidates", []):
            skills_meta.setdefault(cand["skillId"], {"desc": cand.get("desc", ""),
                                                     "slots": cand.get("slots", [])})
    all_ids = set(skills_meta)
    print(f"{len(all_ids)} skills, {len(cases)} cases "
          f"({sum(1 for c in cases if c['expected']['skillId'] != 'none')} real-skill)\n")

    name_desc = {sid: f"{sid.replace('-', ' ')}. {m['desc']}" for sid, m in skills_meta.items()}

    # P0: single concatenated vector (replication)
    vec_single = {sid: [embed(f"{name_desc[sid]} " + " ".join(PHRASES.get(sid, [])))]
                  for sid in all_ids}
    # P1: multi-vector = name+desc vec + one vec per phrase
    vec_multi = {sid: [embed(name_desc[sid])] + [embed(p) for p in PHRASES.get(sid, [])]
                 for sid in all_ids}

    bm25 = BM25({sid: name_desc[sid] + " " + " ".join(PHRASES.get(sid, []))
                 for sid in all_ids})

    results = []
    results.append(report("P0 base_single", score_config(cases, vec_single, all_ids)))
    results.append(report("P1 multi", score_config(cases, vec_multi, all_ids)))
    results.append(report("P2 multi+gate", score_config(cases, vec_multi, all_ids, gate=True)))
    results.append(report("P3 multi+bm25", score_config(cases, vec_multi, all_ids, bm25=bm25)))
    results.append(report("P3b multi+g+b", score_config(cases, vec_multi, all_ids, bm25=bm25, gate=True)))

    if lib.load_api_key():
        anchors = gen_anchors(skills_meta)
        vec_syn = {sid: [embed(name_desc[sid])]
                        + [embed(p) for p in PHRASES.get(sid, [])]
                        + [embed(p) for p in anchors.get(sid, [])]
                   for sid in all_ids}
        bm25s = BM25({sid: name_desc[sid] + " " + " ".join(PHRASES.get(sid, []))
                      + " " + " ".join(anchors.get(sid, [])) for sid in all_ids})
        results.append(report("P4 syn", score_config(cases, vec_syn, all_ids)))
        results.append(report("P5 syn+gate", score_config(cases, vec_syn, all_ids, gate=True)))
        results.append(report("P6 syn+g+bm25", score_config(cases, vec_syn, all_ids, bm25=bm25s, gate=True)))
    else:
        print("no API key — skipping synthetic-anchor probes P4-P6")

    # misroutes for the best config
    best = max(results, key=lambda r: r["acc"])
    print(f"\nmisroutes for {best['name']}:")
    for r in best["rows"]:
        if not r["is_none"] and not r["correct"]:
            print(f"  {r['id']:<15} exp={r['exp']:<24} got={r['top1']:<24} "
                  f"rank_exp={r['rank_exp']} {'GATE-EXCL' if r['gate_excluded'] else ''}")

    json.dump([{k: v for k, v in r.items() if k != 'rows'} for r in results],
              open(os.path.join(RIG, "results", "probe-05d.json"), "w"), indent=1)
    print("\n-> results/probe-05d.json")


if __name__ == "__main__":
    main()
