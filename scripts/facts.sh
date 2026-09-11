#!/usr/bin/env bash
set -uo pipefail
echo "=== units ==="
systemctl is-enabled qwen38-flash.service qwen38-keepalive.service 2>&1
systemctl show -p ActiveEnterTimestamp --value qwen38-flash.service
echo "=== container ==="
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'
echo "=== listening ports ==="
ss -tlnp 2>/dev/null | grep -E ':(30000|30001)\b' || ss -tln | grep -E ':(30000|30001)'
echo "=== api key ==="
cat "$HOME/.config/qwen38/api-key"; echo
echo "=== launch script ==="
cat "$HOME/.config/qwen38/launch-flash.sh"
echo "=== disk / mem ==="
df -h / | tail -1
awk '/MemTotal|MemAvailable/{printf "%s %.1f GiB\n", $1, $2/1048576}' /proc/meminfo
echo "=== model disk usage ==="
du -sh "$HOME/.cache/huggingface" "$HOME/flashnext-ple" 2>/dev/null
docker system df 2>/dev/null | head -4
