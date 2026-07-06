"""Local-model routing/slot eval (Spec 05b §3 / G-20).

Runs dataset.json across {Qwen-1.5B, Llama-3.2-3B, Gemma-2-2B, Phi-3.5-mini} +
Haiku-4.5 (cloud reference), under free-form and json-schema-constrained
conditions, and scores every case:
  * routing accuracy (canonicalised: numeric-index skillId mapped to candidate)
  * slot precision/recall  (exact + normalized)
  * format-valid rate      (parseable JSON AND skillId is a valid id/none string)
  * latency p50/p95        (wall-clock ms)
  * calibration            (does self-reported confidence separate right/wrong?)
plus a per-class (A-E) routing breakdown.

Writes results/eval-routing-raw.json (every call) and results/eval-routing-summary.json
(aggregated metrics). Usage:
  venv/Scripts/python.exe harness/eval_routing.py [--models qwen,llama,...] [--limit N]
"""
import json
import os
import re
import sys
import statistics as stats

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402

RIG = lib.RIG

LOCAL = [
    ("qwen2.5-1.5b", "http://127.0.0.1:8081"),
    ("llama-3.2-3b", "http://127.0.0.1:8082"),
    ("gemma-2-2b",   "http://127.0.0.1:8083"),
    ("phi-3.5-mini", "http://127.0.0.1:8084"),
]
# phi rejects json_schema-derived grammars in this llama.cpp build
CONSTRAINED_UNSUPPORTED = {"phi-3.5-mini"}
HAIKU = ("haiku-4.5", "claude-haiku-4-5")

SYSTEM = (
    "You are Plenara's on-device intent classifier. A retrieval step has already "
    "narrowed the user's request to a SMALL candidate set of capabilities. Your job: "
    "choose EXACTLY ONE candidate skillId that fulfils the request, OR \"none\" if none "
    "of the candidates fits (the request needs a capability that is not in the list, is "
    "out-of-domain world knowledge, or is ambiguous/anaphoric with no referent here). "
    "Then extract the declared slots for the chosen capability; a single sentence may "
    "carry multiple entities/facts — capture them all. For dates, extract the phrase as "
    "spoken (e.g. \"Thursday\", \"the day before Sarah's birthday\") — do NOT resolve it "
    "to a calendar date. Reply with ONLY a JSON object and nothing else: "
    "{\"skillId\": <a candidate id or \"none\">, \"slots\": {..}, \"confidence\": 0.0-1.0}. "
    "Never invent a skillId that is not in the candidate list. No commentary, no markdown."
)


def build_user(case):
    lines = [f'Utterance: "{case["utterance"]}"', "", "Candidates:"]
    for c in case["candidates"]:
        slotstr = ", ".join(c["slots"]) if c["slots"] else "(none)"
        lines.append(f'- {c["skillId"]}: {c["desc"]} [slots: {slotstr}]')
    return "\n".join(lines)


def schema_for(case):
    ids = [c["skillId"] for c in case["candidates"]] + ["none"]
    return {
        "type": "object",
        "properties": {
            "skillId": {"type": "string", "enum": ids},
            "slots": {"type": "object"},
            "confidence": {"type": "number"},
        },
        "required": ["skillId", "slots", "confidence"],
    }


# ---- parsing ---------------------------------------------------------------

def extract_json(text):
    """First balanced {...} object in text (handles fences + trailing prose)."""
    t = text.strip()
    m = re.search(r"```(?:json)?\s*(.*?)```", t, re.DOTALL)
    if m:
        t = m.group(1).strip()
    start = t.find("{")
    if start < 0:
        return None
    depth = 0
    instr = False
    esc = False
    for i in range(start, len(t)):
        ch = t[i]
        if instr:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                instr = False
        else:
            if ch == '"':
                instr = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(t[start:i + 1])
                    except Exception:
                        return None
    return None


def canon_skill(raw_skill, cand_ids):
    """Return (canonical_id, was_numeric_index, is_valid_id_string).

    Maps a numeric/positional skillId to the candidate at that 1-based index
    (findings §5). Normalises null/''/'none' -> 'none'.
    """
    if raw_skill is None:
        return "none", False, True
    if isinstance(raw_skill, bool):
        return "none", False, False
    if isinstance(raw_skill, (int, float)):
        idx = int(raw_skill)
        if 1 <= idx <= len(cand_ids):
            return cand_ids[idx - 1], True, False
        return "none", True, False
    s = str(raw_skill).strip()
    if s == "" or s.lower() in ("none", "null"):
        return "none", False, True
    # pure number as string
    if re.fullmatch(r"\d+", s):
        idx = int(s)
        if 1 <= idx <= len(cand_ids):
            return cand_ids[idx - 1], True, False
        return "none", True, False
    if s in cand_ids:
        return s, False, True
    # case-insensitive id match
    for cid in cand_ids:
        if cid.lower() == s.lower():
            return cid, False, True
    return "none", False, False  # hallucinated id


# ---- slot scoring ----------------------------------------------------------

FILLER = {"the", "a", "an", "my", "to", "is", "was", "i", "on", "at", "in",
          "for", "of", "her", "his", "their", "with", "and", "that"}


def norm_tokens(v):
    if v is None:
        return set()
    s = str(v).lower()
    s = re.sub(r"[^a-z0-9\s]", " ", s)
    toks = [t for t in s.split() if t and t not in FILLER]
    return set(toks)


def value_match(exp_v, pred_v):
    """Normalized value match: containment or jaccard>=0.5."""
    e, p = norm_tokens(exp_v), norm_tokens(pred_v)
    if not e and not p:
        return True
    if not e or not p:
        return False
    if e <= p or p <= e:
        return True
    inter = len(e & p)
    union = len(e | p)
    return union and (inter / union) >= 0.5


def score_slots(expected, predicted):
    """Return dict of exact/normalized TP counts + denominators."""
    if not isinstance(predicted, dict):
        predicted = {}
    exp_items = [(k, v) for k, v in expected.items()]
    pred_items = [(k, v) for k, v in predicted.items() if v not in (None, "", [], {})]
    # exact: same key, equal normalized token sets
    tp_exact = 0
    for k, v in pred_items:
        if k in expected and norm_tokens(v) == norm_tokens(expected[k]):
            tp_exact += 1
    # normalized precision: predicted value matches SOME expected value (key-agnostic)
    tp_norm_p = 0
    for k, v in pred_items:
        if any(value_match(ev, v) for _, ev in exp_items):
            tp_norm_p += 1
    # normalized recall: expected value matched by SOME predicted value
    tp_norm_r = 0
    for k, ev in exp_items:
        if any(value_match(ev, pv) for _, pv in pred_items):
            tp_norm_r += 1
    return {
        "n_exp": len(exp_items), "n_pred": len(pred_items),
        "tp_exact": tp_exact, "tp_norm_p": tp_norm_p, "tp_norm_r": tp_norm_r,
    }


# ---- run one case ----------------------------------------------------------

def run_case(model_key, case, condition, base_url=None):
    sysp, user = SYSTEM, build_user(case)
    schema = schema_for(case) if condition == "constrained" else None
    rec = {"id": case["id"], "class": case["class"], "condition": condition,
           "model": model_key}
    try:
        if base_url:  # local
            r = lib.local_chat(base_url, sysp, user, max_tokens=200,
                               json_schema=schema)
            rec["latency_ms"] = r["latency_ms"]
            rec["server_ms"] = round((r.get("server_prompt_ms") or 0)
                                     + (r.get("server_predicted_ms") or 0), 1)
            text = r["text"]
        else:  # claude (free only)
            r = lib.claude_chat(HAIKU[1], sysp, user, max_tokens=200)
            rec["latency_ms"] = r["latency_ms"]
            rec["cost_usd"] = r["cost_usd"]
            text = r["text"]
    except Exception as e:  # noqa: BLE001
        rec["error"] = str(e)[:160]
        return rec
    rec["text"] = text
    parsed = extract_json(text)
    cand_ids = [c["skillId"] for c in case["candidates"]]
    exp_skill = case["expected"]["skillId"]
    if parsed is None:
        rec.update(parseable=False, format_valid=False, canon_skill="none",
                   routing_correct=(exp_skill == "none"), confidence=None,
                   slots=None)
        return rec
    rec["parseable"] = True
    raw_skill = parsed.get("skillId", None)
    canon, was_num, valid_str = canon_skill(raw_skill, cand_ids)
    rec["raw_skillId"] = raw_skill
    rec["canon_skill"] = canon
    rec["numeric_index"] = was_num
    rec["format_valid"] = bool(valid_str)
    rec["routing_correct"] = (canon == exp_skill)
    conf = parsed.get("confidence", None)
    rec["confidence"] = conf if isinstance(conf, (int, float)) else None
    # slots only scored for real-skill expectations that carry slots
    if exp_skill != "none" and case["expected"]["slots"]:
        rec["slots"] = score_slots(case["expected"]["slots"], parsed.get("slots", {}))
    else:
        rec["slots"] = None
    return rec


# ---- aggregation -----------------------------------------------------------

def pctl(xs, q):
    if not xs:
        return None
    xs = sorted(xs)
    k = (len(xs) - 1) * q
    lo = int(k)
    hi = min(lo + 1, len(xs) - 1)
    return round(xs[lo] + (xs[hi] - xs[lo]) * (k - lo), 1)


def aggregate(records):
    """records: list for one model×condition."""
    n = len(records)
    ok = [r for r in records if "error" not in r]
    routing = [r for r in ok if r.get("routing_correct")]
    fmt = [r for r in ok if r.get("format_valid")]
    lat = [r["latency_ms"] for r in ok if "latency_ms" in r]
    numidx = [r for r in ok if r.get("numeric_index")]
    # slots (micro-avg)
    se = sum(r["slots"]["tp_exact"] for r in ok if r.get("slots"))
    snp = sum(r["slots"]["tp_norm_p"] for r in ok if r.get("slots"))
    snr = sum(r["slots"]["tp_norm_r"] for r in ok if r.get("slots"))
    npred = sum(r["slots"]["n_pred"] for r in ok if r.get("slots"))
    nexp = sum(r["slots"]["n_exp"] for r in ok if r.get("slots"))
    # calibration
    cc = [(r["confidence"], r["routing_correct"]) for r in ok
          if r.get("confidence") is not None]
    conf_correct = [c for c, ok_ in cc if ok_]
    conf_wrong = [c for c, ok_ in cc if not ok_]
    correct_at_zero = sum(1 for c, ok_ in cc if ok_ and c == 0.0)
    # per-class routing
    by_class = {}
    for cls in "ABCDE":
        cr = [r for r in ok if r["class"] == cls]
        if cr:
            by_class[cls] = {
                "n": len(cr),
                "acc": round(sum(r.get("routing_correct", False) for r in cr) / len(cr), 3),
            }

    def sd(x):
        return round(stats.pstdev(x), 3) if len(x) > 1 else 0.0

    return {
        "n": n, "n_ok": len(ok),
        "routing_acc": round(len(routing) / len(ok), 3) if ok else None,
        "format_valid_rate": round(len(fmt) / len(ok), 3) if ok else None,
        "numeric_index_rate": round(len(numidx) / len(ok), 3) if ok else None,
        "slot_exact_P": round(se / npred, 3) if npred else None,
        "slot_exact_R": round(se / nexp, 3) if nexp else None,
        "slot_norm_P": round(snp / npred, 3) if npred else None,
        "slot_norm_R": round(snr / nexp, 3) if nexp else None,
        "slot_pairs": {"n_pred": npred, "n_exp": nexp},
        "lat_p50": pctl(lat, 0.5), "lat_p95": pctl(lat, 0.95),
        "lat_mean": round(sum(lat) / len(lat), 1) if lat else None,
        "calib": {
            "n_conf": len(cc),
            "mean_conf_correct": round(sum(conf_correct) / len(conf_correct), 3) if conf_correct else None,
            "mean_conf_wrong": round(sum(conf_wrong) / len(conf_wrong), 3) if conf_wrong else None,
            "separation": (round(sum(conf_correct) / len(conf_correct)
                                 - sum(conf_wrong) / len(conf_wrong), 3)
                           if conf_correct and conf_wrong else None),
            "correct_at_conf_0": correct_at_zero,
            "sd_correct": sd(conf_correct),
        },
        "by_class": by_class,
    }


def main():
    args = sys.argv[1:]
    model_filter = None
    limit = None
    if "--models" in args:
        model_filter = set(args[args.index("--models") + 1].split(","))
    if "--limit" in args:
        limit = int(args[args.index("--limit") + 1])

    ds = json.load(open(os.path.join(RIG, "dataset.json"), encoding="utf-8"))
    cases = ds["cases"][:limit] if limit else ds["cases"]
    have_key = lib.load_api_key() is not None

    raw = []
    summary = {}

    # local models
    for key, url in LOCAL:
        if model_filter and key not in model_filter:
            continue
        conds = ["free"]
        if key not in CONSTRAINED_UNSUPPORTED:
            conds.append("constrained")
        else:
            summary.setdefault(key, {})["constrained"] = {
                "unavailable": "llama.cpp json_schema grammar rejected by this model's tokenizer "
                               "(400: 'Unexpected empty grammar stack')"}
        for cond in conds:
            recs = []
            for i, case in enumerate(cases):
                r = run_case(key, case, cond, base_url=url)
                recs.append(r)
                raw.append(r)
                tag = "OK" if r.get("routing_correct") else "x "
                print(f"  [{key}/{cond}] {i+1}/{len(cases)} {case['id']:<12} "
                      f"exp={case['expected']['skillId']:<22} got={r.get('canon_skill','ERR'):<22} {tag}",
                      flush=True)
            summary.setdefault(key, {})[cond] = aggregate(recs)
            print(f"== {key}/{cond}: routing_acc={summary[key][cond]['routing_acc']} "
                  f"fmt={summary[key][cond]['format_valid_rate']} "
                  f"p95={summary[key][cond]['lat_p95']}ms ==\n", flush=True)
            _dump(raw, summary)

    # cloud reference (free only)
    if (not model_filter or HAIKU[0] in model_filter) and have_key:
        recs = []
        for i, case in enumerate(cases):
            r = run_case(HAIKU[0], case, "free", base_url=None)
            recs.append(r)
            raw.append(r)
            tag = "OK" if r.get("routing_correct") else "x "
            print(f"  [{HAIKU[0]}/free] {i+1}/{len(cases)} {case['id']:<12} "
                  f"got={r.get('canon_skill','ERR'):<22} {tag}", flush=True)
        summary[HAIKU[0]] = {"free": aggregate(recs)}
        print(f"== {HAIKU[0]}/free: routing_acc={summary[HAIKU[0]]['free']['routing_acc']} ==\n", flush=True)
        _dump(raw, summary)
    elif not have_key:
        print("_Haiku SKIPPED — no ANTHROPIC_API_KEY_")

    _dump(raw, summary)
    print("done -> results/eval-routing-raw.json + results/eval-routing-summary.json")


def _dump(raw, summary):
    outdir = os.path.join(RIG, "results")
    with open(os.path.join(outdir, "eval-routing-raw.json"), "w", encoding="utf-8") as f:
        json.dump(raw, f, indent=2)
    with open(os.path.join(outdir, "eval-routing-summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)


if __name__ == "__main__":
    main()
