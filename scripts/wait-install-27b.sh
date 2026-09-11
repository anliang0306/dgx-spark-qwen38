#!/usr/bin/env bash
# Wait for the 27B installer (including its own smoke test) to finish.
set -uo pipefail
echo "waiting for the installer (max 40 min)..."
for i in $(seq 1 120); do
  pgrep -f "[i]nstall.sh" >/dev/null 2>&1 || break
  sleep 20
done
echo "=== installer finished after ~$((i*20))s ==="
tail -20 "$HOME/dsh-work/install-27b.log"
echo
echo "=== services ==="
systemctl is-active qwen38-sglang.service qwen38-keepalive.service
systemctl is-enabled qwen38-sglang.service qwen38-keepalive.service
echo
echo "=== health ==="
curl -s -m 5 -o /dev/null -w 'app=%{http_code}\n' http://127.0.0.1:30000/health
curl -s -m 5 -o /dev/null -w 'proxy=%{http_code}\n' http://127.0.0.1:30001/health
echo
echo "=== container ==="
docker ps --format '{{.Names}} {{.Status}}'
df -h / | tail -1
