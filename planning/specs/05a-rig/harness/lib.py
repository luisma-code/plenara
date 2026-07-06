"""Spec 05a measurement harness — shared library.

Two measurement surfaces:
  * local_chat()  — hits a running llama-server (/v1/chat/completions) for the
    on-device NLU models (Qwen2.5-1.5B, Llama-3.2-3B). Model is preloaded, so
    reported latency excludes one-time load; server-side `timings` give
    prompt/predicted ms and per-token rates.
  * claude_chat() — Anthropic SDK, across the full non-excluded model matrix,
    capturing wall-clock latency + billed token usage + computed USD cost.

Requests to Claude are kept minimal (model, max_tokens, system, messages) so a
single call shape is valid across every model in the matrix — no temperature or
thinking config, which 4.7/4.8 reject.
"""
import json
import os
import time
import urllib.request
import urllib.error

# ---- model matrix -----------------------------------------------------------

# (key, base_url) — llama-server instances started by serve.sh
LOCAL_MODELS = [
    ("qwen2.5-1.5b", "http://127.0.0.1:8081"),
    ("llama-3.2-3b", "http://127.0.0.1:8082"),
]

# (key, model_id, input $/1M, output $/1M) — excludes Sonnet 5 / Fable / Mythos
CLAUDE_MODELS = [
    ("haiku-4.5",  "claude-haiku-4-5",  1.00,  5.00),
    ("sonnet-4.5", "claude-sonnet-4-5", 3.00, 15.00),
    ("sonnet-4.6", "claude-sonnet-4-6", 3.00, 15.00),
    ("opus-4.5",   "claude-opus-4-5",   5.00, 25.00),
    ("opus-4.6",   "claude-opus-4-6",   5.00, 25.00),
    ("opus-4.7",   "claude-opus-4-7",   5.00, 25.00),
    ("opus-4.8",   "claude-opus-4-8",   5.00, 25.00),
]
CLAUDE_PRICE = {mid: (pin, pout) for _, mid, pin, pout in CLAUDE_MODELS}

RIG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_api_key():
    """ANTHROPIC_API_KEY from env, else from the gitignored .env file."""
    key = os.environ.get("ANTHROPIC_API_KEY")
    if key:
        return key.strip()
    envpath = os.path.join(RIG, ".env")
    if os.path.exists(envpath):
        for line in open(envpath, encoding="utf-8"):
            line = line.strip()
            if line.startswith("ANTHROPIC_API_KEY"):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None


# ---- local (llama-server) ---------------------------------------------------

def local_chat(base_url, system, user, max_tokens=256, temperature=0.0,
               json_schema=None, grammar=None):
    """One chat completion against a preloaded llama-server.

    Optional constrained decoding: pass `json_schema` (a JSON-schema dict) or
    `grammar` (a GBNF string) to force the output shape (e.g. skillId enum).
    llama-server accepts both as top-level fields on /v1/chat/completions.

    Returns dict: text, latency_ms (wall clock), prompt_tok, completion_tok,
    server_prompt_ms, server_predicted_ms, predicted_per_second.
    """
    payload = {
        "messages": (
            ([{"role": "system", "content": system}] if system else [])
            + [{"role": "user", "content": user}]
        ),
        "temperature": temperature,
        "max_tokens": max_tokens,
        "cache_prompt": False,
    }
    if json_schema is not None:
        payload["json_schema"] = json_schema
    if grammar is not None:
        payload["grammar"] = grammar
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        base_url + "/v1/chat/completions", data=body,
        headers={"Content-Type": "application/json"},
    )
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=300) as resp:
        d = json.load(resp)
    latency_ms = (time.perf_counter() - t0) * 1000
    tim = d.get("timings", {}) or {}
    usage = d.get("usage", {}) or {}
    return {
        "text": d["choices"][0]["message"]["content"],
        "latency_ms": round(latency_ms, 1),
        "prompt_tok": usage.get("prompt_tokens"),
        "completion_tok": usage.get("completion_tokens"),
        "server_prompt_ms": round(tim.get("prompt_ms", 0), 1),
        "server_predicted_ms": round(tim.get("predicted_ms", 0), 1),
        "predicted_per_second": round(tim.get("predicted_per_second", 0), 1),
    }


# ---- claude (Anthropic SDK) -------------------------------------------------

_client = None


def _claude_client():
    global _client
    if _client is None:
        import anthropic
        key = load_api_key()
        if not key:
            raise RuntimeError(
                "No ANTHROPIC_API_KEY in env or planning/specs/05a-rig/.env — "
                "set it this session (e.g. `! export ANTHROPIC_API_KEY=sk-ant-...`)."
            )
        _client = anthropic.Anthropic(api_key=key)
    return _client


def claude_chat(model_id, system, user, max_tokens=1024):
    """One Messages call. Returns text, latency_ms, in_tok, out_tok, cost_usd."""
    client = _claude_client()
    t0 = time.perf_counter()
    msg = client.messages.create(
        model=model_id,
        max_tokens=max_tokens,
        system=system or "",
        messages=[{"role": "user", "content": user}],
    )
    latency_ms = (time.perf_counter() - t0) * 1000
    text = "".join(b.text for b in msg.content if getattr(b, "type", "") == "text")
    in_tok = msg.usage.input_tokens
    out_tok = msg.usage.output_tokens
    pin, pout = CLAUDE_PRICE.get(model_id, (0, 0))
    cost = in_tok / 1e6 * pin + out_tok / 1e6 * pout
    return {
        "text": text,
        "latency_ms": round(latency_ms, 1),
        "in_tok": in_tok,
        "out_tok": out_tok,
        "cost_usd": round(cost, 6),
        "stop_reason": msg.stop_reason,
    }
