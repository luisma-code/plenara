#!/usr/bin/env bash
# Spec 05a test rig — reproducible setup (Phase 2).
# Downloads the local NLU models (Qwen2.5-1.5B-Instruct, Llama-3.2-3B-Instruct),
# the llama.cpp Windows CPU binaries, and a Python venv with the Anthropic SDK.
#
# Portable: derives all paths from this script's own location, so it works after
# a machine move / re-clone. Run from Git Bash (Windows) or bash (POSIX):
#   bash planning/specs/05a-rig/setup.sh
#
# Downloaded weights/binaries/venv are gitignored (see .gitignore); only this
# script, the harness, and the results tables are committed.
set -uo pipefail
RIG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$RIG/bin"; MODELS="$RIG/models"; LOG="$RIG/results/setup.log"
mkdir -p "$BIN" "$MODELS" "$RIG/results"
# Windows path helper for PowerShell calls (no-op on POSIX).
winpath() { command -v cygpath >/dev/null 2>&1 && cygpath -w "$1" || printf '%s' "$1"; }
echo "=== rig setup started $(date -u) ===" | tee "$LOG"

# 1) llama.cpp Windows CPU binaries (latest release).
echo "[1/4] resolving latest llama.cpp release asset..." | tee -a "$LOG"
API=$(curl -sS --max-time 60 https://api.github.com/repos/ggml-org/llama.cpp/releases/latest)
URL=$(printf '%s' "$API" | grep -oE 'https://[^"]+' | grep -iE 'bin-win-cpu-x64\.zip' | head -1)
[ -z "$URL" ] && URL=$(printf '%s' "$API" | grep -oE 'https://[^"]+' | grep -iE 'win.*(avx2|cpu).*x64\.zip' | head -1)
[ -z "$URL" ] && URL=$(printf '%s' "$API" | grep -oE 'https://[^"]+' | grep -iE 'win.*x64\.zip' | head -1)
echo "  asset: ${URL:-<none found>}" | tee -a "$LOG"
if [ -n "$URL" ]; then
  curl -sSL --max-time 600 -o "$BIN/llama.zip" "$URL" 2>>"$LOG"
  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "Expand-Archive -Path '$(winpath "$BIN/llama.zip")' -DestinationPath '$(winpath "$BIN")' -Force" 2>>"$LOG"
  else
    unzip -o "$BIN/llama.zip" -d "$BIN" >>"$LOG" 2>&1
  fi
  echo "  llama.cpp extracted" | tee -a "$LOG"
fi

# 2) Qwen2.5-1.5B-Instruct Q4_K_M (open, ungated) — Spec 05a D-B checkpoint A.
echo "[2/4] downloading Qwen2.5-1.5B-Instruct Q4_K_M..." | tee -a "$LOG"
curl -sSL --max-time 1200 -o "$MODELS/qwen2.5-1.5b-instruct-q4_k_m.gguf" \
  "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf" 2>>"$LOG"
echo "  qwen size: $(du -h "$MODELS/qwen2.5-1.5b-instruct-q4_k_m.gguf" 2>/dev/null | cut -f1)" | tee -a "$LOG"

# 3) Llama-3.2-3B-Instruct Q4_K_M (bartowski re-quant, ungated) — checkpoint B.
echo "[3/4] downloading Llama-3.2-3B-Instruct Q4_K_M..." | tee -a "$LOG"
curl -sSL --max-time 1800 -o "$MODELS/llama-3.2-3b-instruct-q4_k_m.gguf" \
  "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf" 2>>"$LOG"
echo "  llama size: $(du -h "$MODELS/llama-3.2-3b-instruct-q4_k_m.gguf" 2>/dev/null | cut -f1)" | tee -a "$LOG"

# 4) Python venv + Anthropic SDK (for the Claude measurement half).
echo "[4/4] creating venv + installing anthropic..." | tee -a "$LOG"
python -m venv "$RIG/venv" 2>>"$LOG"
PY="$RIG/venv/Scripts/python.exe"; [ -x "$PY" ] || PY="$RIG/venv/bin/python"
"$PY" -m pip install --quiet --upgrade pip 2>>"$LOG"
"$PY" -m pip install --quiet anthropic 2>>"$LOG"
echo "  anthropic: $("$PY" -m pip show anthropic 2>/dev/null | grep -i version)" | tee -a "$LOG"

echo "=== rig setup finished $(date -u) ===" | tee -a "$LOG"
find "$BIN" -maxdepth 2 -iname 'llama-cli*' -o -iname 'llama-server*' 2>/dev/null | tee -a "$LOG"
ls -lh "$MODELS" | tee -a "$LOG"
