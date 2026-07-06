
## Headline metrics (model x condition)

| model | cond | route acc | fmt-valid | numeric-idx | slot exP/exR | slot nmP/nmR | p50 ms | p95 ms | mean-conf ✓ | mean-conf ✗ | ✓@0.0 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| qwen2.5-1.5b | free | 49% | 100% | 0% | 50%/48% | 82%/79% | 2110.2 | 2679.3 | 0.929 | 0.914 | 1 |
| qwen2.5-1.5b | constrained | 49% | 100% | 0% | 50%/48% | 82%/79% | 2106.7 | 2712.6 | 0.929 | 0.914 | 1 |
| llama-3.2-3b | free | 49% | 100% | 0% | 38%/49% | 72%/85% | 4770.5 | 5690.4 | 0.836 | 0.792 | 0 |
| llama-3.2-3b | constrained | 49% | 100% | 0% | 38%/49% | 73%/86% | 6799.7 | 8618.1 | 0.836 | 0.793 | 0 |
| gemma-2-2b | free | 49% | 100% | 0% | 44%/40% | 72%/65% | 6241.2 | 7390.1 | 0.945 | 0.9 | 0 |
| gemma-2-2b | constrained | 49% | 100% | 0% | 44%/40% | 72%/65% | 5975.4 | 7810.9 | 0.945 | 0.9 | 0 |
| phi-3.5-mini | free | 46% | 100% | 0% | 48%/47% | 80%/83% | 27560.5 | 31900.4 | 0.94 | 0.956 | 1 |
| phi-3.5-mini | constrained | n/a — llama.cpp json_schema grammar rejected… | | | | | | | | | |
| haiku-4.5 | free | 86% | 100% | 0% | 78%/76% | 92%/91% | 762.4 | 1638.4 | 0.891 | 0.884 | 3 |

## Per-class routing accuracy (free condition)

| model | A (route) | B (slots) | C (meta) | D (OOD) | E (adversarial) |
|---|---|---|---|---|---|
| qwen2.5-1.5b | 65% (26) | 29% (7) | 0% (6) | 25% (8) | 70% (10) |
| llama-3.2-3b | 81% (26) | 29% (7) | 0% (6) | 0% (8) | 50% (10) |
| gemma-2-2b | 65% (26) | 57% (7) | 0% (6) | 38% (8) | 40% (10) |
| phi-3.5-mini | 65% (26) | 43% (7) | 0% (6) | 12% (8) | 50% (10) |
| haiku-4.5 | 96% (26) | 100% (7) | 33% (6) | 100% (8) | 70% (10) |

## Free vs constrained (route acc delta, local models)

| model | free | constrained | Δ |
|---|---|---|---|
| qwen2.5-1.5b | 49% | 49% | +0 pts |
| llama-3.2-3b | 49% | 49% | +0 pts |
| gemma-2-2b | 49% | 49% | +0 pts |
| phi-3.5-mini | 46% | n/a | — |

## G-19 privacy boundary — adversarial-personal cases (expect a records skill, must NOT go OOD/none)

cases: ['D-adv-1', 'D-adv-2', 'D-adv-3', 'D-adv-4']
| model/cond | correct skill | stayed-in-records (safe) | leaked to none/OOD (privacy fail) |
|---|---|---|---|
| qwen2.5-1.5b/free | 2/4 | 3/4 | 0/4 |
| qwen2.5-1.5b/constrained | 2/4 | 3/4 | 0/4 |
| llama-3.2-3b/free | 0/4 | 4/4 | 0/4 |
| llama-3.2-3b/constrained | 0/4 | 4/4 | 0/4 |
| gemma-2-2b/free | 3/4 | 4/4 | 0/4 |
| gemma-2-2b/constrained | 3/4 | 4/4 | 0/4 |
| phi-3.5-mini/free | 1/4 | 4/4 | 0/4 |
| haiku-4.5/free | 4/4 | 4/4 | 0/4 |

## Small-model overlap (free) — can an ensemble clear the bar?

- cases: 57
- qwen2.5-1.5b: 28 correct
- llama-3.2-3b: 28 correct
- gemma-2-2b: 28 correct
- phi-3.5-mini: 26 correct
- **all-4 agree & correct:** 17/57 = 30%
- **union (any one correct — oracle ceiling):** 40/57 = 70%
- **no model ever correct:** 17 cases: ['A-recur-1', 'B-fact-3', 'B-fact-4', 'C-meta-1', 'C-meta-2', 'C-meta-3', 'C-meta-4', 'C-meta-5', 'C-meta-6', 'D-adv-4', 'D-ood-1', 'D-ood-2', 'D-ood-3', 'D-ood-4', 'E-ana-1', 'E-coord-2', 'E-twin-1']

## Calibration detail (free)

| model | n w/ conf | mean ✓ | mean ✗ | separation | ✓ at conf 0.0 | sd(✓) |
|---|---|---|---|---|---|---|
| qwen2.5-1.5b | 57 | 0.929 | 0.914 | 0.015 | 1 | 0.185 |
| llama-3.2-3b | 54 | 0.836 | 0.792 | 0.043 | 0 | 0.048 |
| gemma-2-2b | 57 | 0.945 | 0.9 | 0.045 | 0 | 0.02 |
| phi-3.5-mini | 57 | 0.94 | 0.956 | -0.016 | 1 | 0.192 |
| haiku-4.5 | 57 | 0.891 | 0.884 | 0.008 | 3 | 0.229 |
