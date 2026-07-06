"""Auth + matrix reachability check. Pings each Claude model with max_tokens=1.
Prints only pass/fail + latency + a masked key fingerprint — never the key."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402

key = lib.load_api_key()
if not key:
    print("NO KEY"); sys.exit(1)
print(f"key loaded: {key[:10]}…{key[-4:]}  ({len(key)} chars)")
print("pinging matrix (max_tokens=1)…\n")
total = 0.0
for name, mid, _pin, _pout in lib.CLAUDE_MODELS:
    try:
        r = lib.claude_chat(mid, "", "Reply with the single character: K", max_tokens=1)
        total += r["cost_usd"]
        print(f"  OK   {name:<11} {mid:<20} {r['latency_ms']:>7.0f} ms  in/out {r['in_tok']}/{r['out_tok']}  ${r['cost_usd']:.6f}")
    except Exception as e:  # noqa: BLE001
        print(f"  FAIL {name:<11} {mid:<20} {type(e).__name__}: {str(e)[:80]}")
print(f"\ntotal spend this check: ${total:.6f}")
