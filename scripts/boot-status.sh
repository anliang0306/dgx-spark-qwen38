#!/usr/bin/env bash
set -uo pipefail
echo "=== services ==="
systemctl is-active qwen38-flash.service qwen38-keepalive.service 2>&1
echo "=== PLE table ==="
ls -l --block-size=M "$HOME/flashnext-ple/" 2>/dev/null | head -4
du -sh --apparent-size "$HOME/flashnext-ple" 2>/dev/null
echo "=== memory ==="
awk '/MemTotal|MemAvailable/{printf "%s %.1f GiB\n", $1, $2/1048576}' /proc/meminfo
echo "=== container ==="
docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null
echo "=== journal (last 15) ==="
sudo -n journalctl -u qwen38-flash -n 15 --no-pager 2>/dev/null | tail -15 || journalctl -u qwen38-flash -n 15 --no-pager 2>/dev/null | tail -15
echo "=== health ==="
curl -s -m 5 -o /dev/null -w 'app=%{http_code} ' "http://127.0.0.1:30000/health" 2>/dev/null || echo -n "app=down "
curl -s -m 5 -o /dev/null -w 'proxy=%{http_code}\n' "http://127.0.0.1:30001/health" 2>/dev/null || echo "proxy=down"
