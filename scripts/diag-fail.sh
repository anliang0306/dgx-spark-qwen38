#!/usr/bin/env bash
set -uo pipefail
echo "=== service ==="
systemctl is-active qwen38-flash.service; systemctl status qwen38-flash.service --no-pager 2>/dev/null | head -12
echo
echo "=== container ==="
docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' | head -5
echo
echo "=== journal (last 50) ==="
journalctl -u qwen38-flash -n 50 --no-pager 2>/dev/null | tail -50
echo
echo "=== errors/tracebacks in journal ==="
journalctl -u qwen38-flash --since "-40 min" --no-pager 2>/dev/null | grep -iE 'error|traceback|assert|exception|killed|oom|invalid|fail' | tail -25
