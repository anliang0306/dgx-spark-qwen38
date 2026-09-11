#!/usr/bin/env bash
set -uo pipefail
echo "=== container / service ==="
systemctl is-active qwen38-flash.service
docker ps -a --format '{{.Names}}\t{{.Status}}' | head -3
echo
echo "=== exceptions / tracebacks in the last 30 min ==="
journalctl -u qwen38-flash --since "-30 min" --no-pager 2>/dev/null \
  | grep -iE 'traceback|NotImplementedError|AssertionError|ValueError|RuntimeError|Scheduler hit|CUDA error|out of memory' \
  | tail -20
echo
echo "=== last 12 log lines ==="
journalctl -u qwen38-flash -n 12 --no-pager 2>/dev/null | tail -12
