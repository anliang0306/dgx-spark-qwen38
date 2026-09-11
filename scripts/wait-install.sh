#!/usr/bin/env bash
set -uo pipefail
echo "waiting for the installer to finish (max 40 min)..."
for i in $(seq 1 120); do
  if ! pgrep -f "[i]nstall.sh" >/dev/null 2>&1; then break; fi
  sleep 20
done
echo "=== installer finished after ~$((i*20))s ==="
tail -n 25 "$HOME/dsh-work/install.log"
echo
echo "=== service state ==="
systemctl is-active qwen38-flash.service qwen38-keepalive.service
echo "=== health ==="
curl -s -m 5 -o /dev/null -w 'app health=%{http_code}\n' "http://127.0.0.1:30000/health" || true
curl -s -m 5 -o /dev/null -w 'proxy health=%{http_code}\n' "http://127.0.0.1:30001/health" || true
