#!/usr/bin/env bash
# Start/stop the local llama-server instances used by the harness.
#   bash harness/serve.sh start   # loads both models, waits until ready
#   bash harness/serve.sh stop
# Qwen2.5-1.5B  -> :8081   |   Llama-3.2-3B -> :8082
set -uo pipefail
RIG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RIG"
THREADS="${LLAMA_THREADS:-8}"

start_one() {
  local gguf="$1" port="$2" log="$3"
  if grep -q "listening on" "$log" 2>/dev/null && curl -sf "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
    echo "  :$port already up"; return
  fi
  nohup ./bin/llama-server.exe -m "$gguf" --port "$port" -c 4096 -t "$THREADS" --no-webui > "$log" 2>&1 &
  echo "  :$port pid $!"
  for _ in $(seq 1 90); do
    grep -q "server is listening" "$log" 2>/dev/null && { echo "  :$port ready"; return; }
    sleep 1
  done
  echo "  :$port TIMEOUT — see $log"
}

case "${1:-start}" in
  start)
    echo "starting llama-servers ($THREADS threads)..."
    start_one ./models/qwen2.5-1.5b-instruct-q4_k_m.gguf 8081 results/qwen-server.log
    start_one ./models/llama-3.2-3b-instruct-q4_k_m.gguf 8082 results/llama-server.log
    ;;
  stop)
    # kill by listening port (Windows netstat + taskkill via powershell)
    for port in 8081 8082; do
      powershell.exe -NoProfile -Command "Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force }" 2>/dev/null
    done
    echo "stopped :8081 :8082"
    ;;
  *) echo "usage: serve.sh {start|stop}"; exit 1;;
esac
