"""Run a task file's model-invoking steps across the matrix and emit tables.

Task file (JSON):
{
  "example": "P-01",
  "steps": [
    {"id": "raise-meta", "surface": "local",  "system": "...", "prompt": "...", "max_tokens": 128},
    {"id": "author",     "surface": "claude", "system": "...", "prompt": "...", "max_tokens": 1500}
  ]
}

surface ∈ {local, claude, both}. Writes results/<example>.json (raw) and prints
a Markdown table per step. Claude steps are skipped with a note if no key is set,
so the local half always runs.

Usage:  venv/Scripts/python.exe harness/measure.py harness/tasks/<file>.json
"""
import json
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:  # noqa: BLE001
    pass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402


def run_step(step):
    surface = step.get("surface", "both")
    sysp = step.get("system", "")
    prompt = step["prompt"]
    out = {"id": step["id"], "surface": surface, "local": [], "claude": []}

    if surface in ("local", "both"):
        for key, url in lib.LOCAL_MODELS:
            try:
                r = lib.local_chat(url, sysp, prompt, step.get("max_tokens", 256))
                r["model"] = key
                out["local"].append(r)
            except Exception as e:  # noqa: BLE001
                out["local"].append({"model": key, "error": str(e)})

    if surface in ("claude", "both"):
        if lib.load_api_key() is None:
            out["claude_note"] = "SKIPPED — no ANTHROPIC_API_KEY set"
        else:
            for key, mid, _pin, _pout in lib.CLAUDE_MODELS:
                try:
                    r = lib.claude_chat(mid, sysp, prompt, step.get("max_tokens_claude", step.get("max_tokens", 1024)))
                    r["model"] = key
                    out["claude"].append(r)
                except Exception as e:  # noqa: BLE001
                    out["claude"].append({"model": key, "error": str(e)})
    return out


def md_local(rows):
    if not rows:
        return ""
    lines = ["| model | latency ms | prompt→gen ms (server) | tok in/out | gen tok/s |",
             "|---|---|---|---|---|"]
    for r in rows:
        if "error" in r:
            lines.append(f"| {r['model']} | ERROR: {r['error'][:40]} | | | |")
            continue
        lines.append(
            f"| {r['model']} | {r['latency_ms']} | "
            f"{r['server_prompt_ms']}→{r['server_predicted_ms']} | "
            f"{r['prompt_tok']}/{r['completion_tok']} | {r['predicted_per_second']} |"
        )
    return "\n".join(lines)


def md_claude(rows):
    if not rows:
        return ""
    lines = ["| model | latency ms | tok in/out | cost $ | stop |",
             "|---|---|---|---|---|"]
    for r in rows:
        if "error" in r:
            lines.append(f"| {r['model']} | ERROR: {r['error'][:50]} | | | |")
            continue
        lines.append(
            f"| {r['model']} | {r['latency_ms']} | {r['in_tok']}/{r['out_tok']} | "
            f"{r['cost_usd']:.6f} | {r['stop_reason']} |"
        )
    return "\n".join(lines)


def main():
    task = json.load(open(sys.argv[1], encoding="utf-8"))
    example = task["example"]
    results = {"example": example, "steps": []}
    for step in task["steps"]:
        print(f"\n### {example} — step `{step['id']}`  ({step.get('surface','both')})\n")
        r = run_step(step)
        results["steps"].append(r)
        if r["local"]:
            print("**Local:**\n")
            print(md_local(r["local"]))
            print("\n_outputs:_")
            for x in r["local"]:
                if "text" in x:
                    print(f"- `{x['model']}`: {x['text'].strip()[:300]}")
        if r.get("claude_note"):
            print(f"\n_Claude: {r['claude_note']}_")
        if r["claude"]:
            print("\n**Claude:**\n")
            print(md_claude(r["claude"]))
            print("\n_outputs:_")
            for x in r["claude"]:
                if "text" in x:
                    print(f"- `{x['model']}`: {x['text'].strip()[:400]}")

    outdir = os.path.join(lib.RIG, "results")
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, f"{example}.json"), "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    print(f"\n_raw results → results/{example}.json_")


if __name__ == "__main__":
    main()
