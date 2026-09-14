#!/usr/bin/env bash
# Wait for the 512K boot and report the new runtime facts.
set -uo pipefail
KEY=$(cat "$HOME/.config/qwen38/api-key")

echo "waiting for /health (max 25 min)..."
for i in $(seq 1 150); do
  if curl -s -m 5 -o /dev/null http://127.0.0.1:30000/health 2>/dev/null; then
    echo "health OK after ~$((i*10))s"
    break
  fi
  sleep 10
done
sleep 10

echo
echo "=== 服务 ==="
systemctl is-active qwen38-sglang.service qwen38-keepalive.service | tr '\n' ' '; echo
systemctl is-enabled qwen38-sglang.service | tr -d '\n'; echo " (enabled)"

echo
echo "=== 生效参数 ==="
grep -oE '\-\-context-length [0-9]+|\-\-mem-fraction-static [0-9.]+|\-\-max-running-requests [0-9]+' \
  /etc/systemd/system/qwen38-sglang.service | sort -u | sed 's/^/  /'

echo
echo "=== 运行时容量 ==="
curl -s -m 25 http://127.0.0.1:30000/get_server_info -H "Authorization: Bearer $KEY" \
  | python3 -c '
import json,sys
d=json.load(sys.stdin)
for k in ("context_length","max_total_num_tokens","mem_fraction_static","max_running_requests"):
    print("  %-24s %s" % (k, d.get(k)))
' 2>&1 | head -8

echo
echo "=== YaRN 落地确认 ==="
for r in RadixArk--Qwen3.8-27B-NVFP4 z-lab--Qwen3.8-27B-DFlash2; do
  f=$(ls -d "$HOME/.cache/huggingface/hub/models--$r"/snapshots/*/config.json 2>/dev/null | head -1)
  [ -n "$f" ] && python3 -c "
import json
d=json.load(open('$f')); tc=d.get('text_config',d); rp=tc.get('rope_parameters',{})
print('  %-28s max_pos=%s factor=%s rope=%s' % ('$r', tc.get('max_position_embeddings'), rp.get('factor'), rp.get('rope_type')))
"
done
echo "  --- 原始 native 备份仍在？ ---"
ls -l "$HOME"/.cache/huggingface/hub/models--*/snapshots/*/config.json.pre-yarn 2>/dev/null | sed 's/^/  /'

echo
echo "=== 宿主内存 ==="
awk '/MemTotal|MemAvailable/{printf "  %-14s %.1f GiB\n", $1, $2/1048576}' /proc/meminfo
echo READY_512K
