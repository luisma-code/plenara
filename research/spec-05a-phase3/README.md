# research/spec-05a-phase3

Archived working record for **Spec 05a — Phase 3** (full end-to-end example traces + real-model measurements). This folder exists so the work is reconstructable later: what was run, against which models, what it produced, and what we concluded.

## Contents

| Path | What it is |
|---|---|
| [`findings.md`](findings.md) | The synthesized conclusions from the Phase-3 **vertical slice** (5 of 60 examples). Start here. |
| [`raw/*.json`](raw/) | Complete per-model measurement records (F-01, F-07, F-19, P-01, DP-02) — every call's output text, latency, token usage, and cost. The real debug-level data. |
| [`raw/*.console.txt`](raw/) | Human-readable console transcripts of the measurement runs (the tables + truncated outputs as they were produced). |
| [`raw/setup.log`](raw/), `raw/*-server.log` | Rig setup log and the two `llama-server` logs (model load, request timings). |

## The rig (live, reproducible tooling)

The archive above is a snapshot; the **live** rig that produced it is in [`../../planning/specs/05a-rig/`](../../planning/specs/05a-rig/):

- `setup.sh` — portable one-command setup (downloads llama.cpp binaries + the two GGUF models, creates the venv, installs the Anthropic SDK). Re-run after a machine move.
- `harness/` — `lib.py` (local + Claude call wrappers), `measure.py` (runs a task file across the matrix), `validate_authoring.py` (checks authored DSL against the closed vocabulary), `verify.py` (auth + matrix reachability), `serve.sh` (start/stop the local model servers), and `tasks/*.json` (the per-example measurement specs).
- `results/` — where fresh runs land. Weights, binaries, venv, and `.env` (the API key) are gitignored.

## To reproduce a measurement

```bash
cd planning/specs/05a-rig
bash setup.sh                       # once, or after a machine move
bash harness/serve.sh start         # loads Qwen:8081 + Llama:8082
printf 'ANTHROPIC_API_KEY=sk-ant-...\n' > .env   # BYOK; gitignored
./venv/Scripts/python.exe harness/verify.py               # auth + 7-model ping
./venv/Scripts/python.exe harness/measure.py harness/tasks/P-01.json
./venv/Scripts/python.exe harness/validate_authoring.py P-01
```

## Model matrix

- **Local (D-B candidates):** Qwen2.5-1.5B-Instruct, Llama-3.2-3B-Instruct (Q4_K_M, via llama.cpp).
- **Cloud (full non-excluded set):** haiku-4.5, sonnet-4.5, sonnet-4.6, opus-4.5, opus-4.6, opus-4.7, opus-4.8. Sonnet 5 / Fable / Mythos excluded per Luis.

## Status

Vertical slice complete (5 examples). Remaining 55 examples pending sign-off on the trace-doc format. Total Claude spend so far: ~$0.35.
