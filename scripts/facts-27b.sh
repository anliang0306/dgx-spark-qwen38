#!/usr/bin/env bash
set -uo pipefail
echo "=== units ==="
systemctl is-active qwen38-sglang.service qwen38-keepalive.service | tr '\n' ' '; echo
systemctl is-enabled qwen38-sglang.service qwen38-keepalive.service | tr '\n' ' '; echo
systemctl show -p ActiveEnterTimestamp --value qwen38-sglang.service

echo
echo "=== qwen38-sglang.service ==="
cat /etc/systemd/system/qwen38-sglang.service

echo
echo "=== running engine flags ==="
docker inspect qwen38-sglang --format '{{join .Args "\n"}}' 2>/dev/null | grep -E 'speculative|mem-fraction|context-length|model-path|revision|tp-size|page-size|chunked|max-running|served-model' || true

echo
echo "=== api key ==="
cat "$HOME/.config/qwen38/api-key"; echo

echo
echo "=== container / ports ==="
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'
ss -tln | grep -E ':(30000|30001)'

echo
echo "=== disk ==="
df -h / | tail -1
du -sh "$HOME"/.cache/huggingface/hub/models--* 2>/dev/null
docker system df | head -4

echo
echo "=== speculation metrics from the benchmark run ==="
journalctl -u qwen38-sglang -n 600 --no-pager 2>/dev/null | grep -oE 'accept len: [0-9.]+|accept rate: [0-9.]+|gen throughput \(token/s\): [0-9.]+|#running-req: [0-9]+' | paste - - - - | tail -8

echo
echo "=== memory ==="
awk '/MemTotal|MemAvailable/{printf "%s %.1f GiB\n", $1, $2/1048576}' /proc/meminfo
