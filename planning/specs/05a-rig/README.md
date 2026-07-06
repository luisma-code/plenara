# Spec 05a test rig

The measurement rig for **Spec 05a — Functional Examples** Phase 3 (real-model traces). It runs each example's model-invoking steps against the on-device NLU candidates and the full Claude matrix, capturing latency, token usage, and cost.

Analysis and archived results live in [`../../../research/spec-05a-phase3/`](../../../research/spec-05a-phase3/).

## Layout

```
setup.sh                 portable setup — run once / after a machine move
harness/
  lib.py                 local_chat() (llama-server) + claude_chat() (Anthropic SDK) + pricing/cost
  measure.py             run a task file across the matrix → results/<example>.json + Markdown tables
  validate_authoring.py  check authored type+skill JSON against the closed DSL vocabulary + schema
  verify.py              auth check + 7-model reachability ping (prints no key material)
  serve.sh               start|stop the two local llama-servers (Qwen:8081, Llama:8082)
  tasks/*.json           per-example measurement specs (system + prompt per step, surface = local|claude|both)
results/                 run outputs + server logs (committed; large binaries are not)
bin/  models/  venv/  .env    gitignored (llama.cpp binaries, GGUF weights, venv, API key)
```

## Setup (once, or after moving machines)

```bash
bash setup.sh
```

Downloads the latest llama.cpp Windows CPU binaries, the two GGUF models (Qwen2.5-1.5B-Instruct, Llama-3.2-3B-Instruct, Q4_K_M), creates a Python venv, and installs the `anthropic` SDK. All derived artifacts are gitignored; only `setup.sh`, the harness, and `results/` are committed.

## Running

```bash
bash harness/serve.sh start          # load both local models (idempotent)
printf 'ANTHROPIC_API_KEY=sk-ant-...\n' > .env   # BYOK; gitignored, never printed/committed
./venv/Scripts/python.exe harness/verify.py                    # auth + matrix ping (~$0.0005)
./venv/Scripts/python.exe harness/measure.py harness/tasks/P-01.json
./venv/Scripts/python.exe harness/validate_authoring.py P-01   # for authoring examples
bash harness/serve.sh stop
```

`measure.py` writes `results/<example>.json` (full raw records) and prints Markdown tables to stdout. A task step's `surface` is `local`, `claude`, or `both`; Claude steps are skipped with a note if no `.env` key is present, so the local half always runs.

## Model matrix

- **Local:** Qwen2.5-1.5B-Instruct, Llama-3.2-3B-Instruct — the Spec 05a §0.4 D-B checkpoint candidates.
- **Claude:** haiku-4.5, sonnet-4.5, sonnet-4.6, opus-4.5, opus-4.6, opus-4.7, opus-4.8 (Sonnet 5 / Fable / Mythos excluded per Luis). IDs + pricing are in `harness/lib.py::CLAUDE_MODELS`.

## Notes

- Local latency is CPU / Q4 / uncached — treat it as *relative* between the two models, not as a shipped device number.
- Claude requests are intentionally minimal (no temperature/thinking config) so one call shape is valid across all 7 models and the numbers are comparable.
