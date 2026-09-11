#!/usr/bin/env bash
# Fill the two unverified aggregate points: 16 and 32 concurrent streams against
# the CURRENT config (--max-running-requests 8, so extra streams queue).
set -uo pipefail
cd "$HOME/dsh-work"
echo "=== config in effect ==="
docker inspect qwen38-sglang --format '{{join .Args " "}}' 2>/dev/null | tr ' ' '\n' | grep -A1 -E '^--max-running-requests$|^--max-mamba-cache-size$|^--speculative-num-draft-tokens$' | paste - - 2>/dev/null || true
grep -oE '\-\-max-running-requests [0-9]+|\-\-max-mamba-cache-size [0-9]+|\-\-speculative-num-draft-tokens [0-9]+' /etc/systemd/system/qwen38-sglang.service | sort -u

echo
echo "=== 16 streams ==="
MODEL=qwen3.8-27b STREAMS=16 MAXTOK=400 ROUNDS=1 python3 "$HOME/dsh-work/conc8.py"

echo
echo "=== 32 streams ==="
MODEL=qwen3.8-27b STREAMS=32 MAXTOK=400 ROUNDS=1 python3 "$HOME/dsh-work/conc8.py"

echo
echo "=== engine view during high concurrency ==="
journalctl -u qwen38-sglang --since '-8 min' --no-pager 2>/dev/null | grep -oE '#running-req: [0-9]+|#queue-req: [0-9]+|gen throughput \(token/s\): [0-9.]+' | paste - - - | tail -10

echo
echo "=== health after ==="
curl -s -m 5 -o /dev/null -w 'health=%{http_code}\n' http://127.0.0.1:30000/health
