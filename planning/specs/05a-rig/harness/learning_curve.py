"""E5 — the corpus learning-curve simulator (the make-or-break metric).

Offline/free users get on-device retrieval only (~80% top-1, E2), so novel
phrasings misroute until the corpus fast-path learns them. This simulates one
persona's usage stream and measures how fast the correction rate falls — and
whether SOFT corpus generalization (05d R9b: a learned utterance embedding
matches SIMILAR future phrasings) beats EXACT match.

Model (stated caveats in findings): base router = multi-vector + synthetic
anchors (the E2 winner, no gate). Learn-on-every-use: after each turn the
utterance embedding is added to the corpus for its TRUE skill (act-then-describe
boost, or the user's correction). Corpus-first routing: a turn whose utterance
cos-sim to a learned entry >= theta routes to that entry's skill (silent
fast-path); else retrieval. A wrong route = a friction turn (user corrects).
Usage: learning_curve.py [embed_port=8091]
"""
import json, os, sys, random
sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib          # noqa: E402
import probe_05d as p  # noqa: E402

PORT = sys.argv[1] if len(sys.argv) > 1 else "8091"
p.EMBED_URL = f"http://127.0.0.1:{PORT}/v1/embeddings"
p._embed_cache = {}
RIG = lib.RIG
CACHE = os.path.join(RIG, "results", "learning-streams.json")
STREAM_SKILLS = ["log-run", "log-mood", "create-task", "create-reminder",
                 "query-aggregate", "recall-contact-fact"]
GEN_SYS = (
    "Generate diverse ways a SINGLE real user would phrase invoking one capability across "
    "many days — natural spoken utterances, varied wording, length, and register, a few with "
    "disfluencies, concrete slot values (real names/numbers/dates). They simulate one person's "
    "genuine usage variation over weeks. One per line; no numbering, quotes, or commentary."
)


def gen_streams(skills_meta):
    if os.path.exists(CACHE):
        return json.load(open(CACHE, encoding="utf-8"))["streams"]
    out, cost = {}, 0.0
    for sid in STREAM_SKILLS:
        m = skills_meta[sid]
        user = (f"Capability: {m['desc']}\nSlots: {', '.join(m['slots']) or '(none)'}\n"
                f"Write 18 utterances.")
        r = lib.claude_chat("claude-sonnet-4-5", GEN_SYS, user, max_tokens=520)
        cost += r["cost_usd"]
        out[sid] = [ln.strip(" -\"'\t") for ln in r["text"].splitlines() if ln.strip()][:18]
    json.dump({"streams": out, "cost": round(cost, 4)}, open(CACHE, "w", encoding="utf-8"), indent=1)
    print(f"generated usage streams via sonnet (${cost:.3f})")
    return out


def simulate(stream, skill_vecs, all_ids, theta_corpus, learn=True):
    corpus = []   # list of (vec, skillId)
    res = []
    for utt, true in stream:
        uv = p.embed(utt)
        if corpus:
            best_sim, best_skill = max((p.cos(uv, cv), cs) for cv, cs in corpus)
        else:
            best_sim, best_skill = -1.0, None
        if best_sim >= theta_corpus:
            routed, source = best_skill, "corpus"
        else:
            dense = {sid: max(p.cos(uv, v) for v in skill_vecs[sid]) for sid in all_ids}
            routed, source = max(dense, key=dense.get), "retrieval"
        res.append({"correct": routed == true, "source": source})
        if learn:
            corpus.append((uv, true))
    return res


def rate(res, lo, hi):
    w = res[lo:hi]
    return sum(1 for r in w if not r["correct"]) / len(w)


def main():
    ds = json.load(open(os.path.join(RIG, "dataset.json"), encoding="utf-8"))
    skills_meta = {}
    for c in ds["cases"]:
        for cand in c.get("candidates", []):
            skills_meta.setdefault(cand["skillId"],
                                   {"desc": cand.get("desc", ""), "slots": cand.get("slots", [])})
    all_ids = set(skills_meta)
    name_desc = {sid: f"{sid.replace('-', ' ')}. {m['desc']}" for sid, m in skills_meta.items()}
    anchors = json.load(open(os.path.join(RIG, "results", "probe-synthetic-anchors.json"), encoding="utf-8"))
    skill_vecs = {sid: [p.embed(name_desc[sid])] + [p.embed(x) for x in p.PHRASES.get(sid, [])]
                       + [p.embed(x) for x in anchors.get(sid, [])] for sid in all_ids}

    streams = gen_streams(skills_meta)
    # Realistic usage: a user REUSES a few habitual phrasings per skill (Zipfian),
    # with a long tail of rarer variants — sampled WITH replacement over a longer
    # stream, so the corpus can actually catch repeated phrasings (the real mechanism).
    random.seed(42)
    STREAM_LEN = 300
    skill_list = list(streams.keys())
    weighted = {sid: (utts, [1.0 / (i + 1) for i in range(len(utts))])
                for sid, utts in streams.items()}
    pairs = []
    for _ in range(STREAM_LEN):
        sid = random.choice(skill_list)
        utts, w = weighted[sid]
        pairs.append((random.choices(utts, weights=w)[0], sid))
    n = len(pairs)
    third = n // 3
    print(f"stream: {n} turns over {len(streams)} skills, Zipfian phrasing reuse; "
          f"base retrieval = multi+anchors (E2 winner)\n")

    configs = [("no corpus (retrieval only)", None, False),
               ("EXACT corpus (θ=0.995)", 0.995, True),
               ("SOFT corpus (θ=0.86, R9b)", 0.86, True),
               ("SOFT corpus (θ=0.82, R9b)", 0.82, True)]
    summary = {}
    for label, theta, learn in configs:
        res = simulate(pairs, skill_vecs, all_ids, theta if theta else 2.0, learn=learn)
        overall_corr = sum(1 for r in res if not r["correct"])
        early = rate(res, 0, third)
        late = rate(res, 2 * third, n)
        corpus_share = sum(1 for r in res if r["source"] == "corpus") / n
        corpus_err = sum(1 for r in res if r["source"] == "corpus" and not r["correct"])
        summary[label] = {"corrections": overall_corr, "early_rate": early, "late_rate": late,
                          "corpus_share": corpus_share, "corpus_errors": corpus_err}
        print(f"{label:<30} corrections={overall_corr:>3}/{n}  "
              f"early-third={early:.0%}  late-third={late:.0%}  "
              f"corpus-hits={corpus_share:.0%}  corpus-errs={corpus_err}")

    print("\nRead: 'early/late-third' = correction (friction) rate at start vs end of the stream.")
    print("A steep early→late drop = the app goes silent fast (the vision holds).")
    json.dump(summary, open(os.path.join(RIG, "results", "learning-curve.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
