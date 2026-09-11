#!/usr/bin/env bash
# Wait for the engine to come back after a restart, then run the fixed benchmark
# and snapshot the speculation metrics the engine logs.
set -uo pipefail
TAG="$1"
PORT=30000
echo "waiting for /health after restart (max 25 min)..."
for i in $(seq 1 150); do
  if curl -s -m 3 -o /dev/null "http://127.0.0.1:$PORT/health" 2>/dev/null; then
    echo "health OK after ~$((i*10))s"
    break
  fi
  sleep 10
done
curl -s -m 5 -o /dev/null "http://127.0.0.1:$PORT/health" || { echo "engine never came up"; exit 1; }
sleep 10

echo
echo "=== flags in effect ==="
grep -E '^TIER=' "$HOME/.config/qwen38/launch-flash.sh"

echo
echo "=== benchmark ($TAG) ==="
python3 "$HOME/dsh-work/bench_spec.py" "$TAG"

echo
echo "=== engine-reported speculation metrics during the run ==="
journalctl -u qwen38-flash -n 400 --no-pager 2>/dev/null | grep -oE 'accept len: [0-9.]+|accept rate: [0-9.]+|gen throughput \(token/s\): [0-9.]+|#running-req: [0-9]+' | paste - - - - | tail -12
