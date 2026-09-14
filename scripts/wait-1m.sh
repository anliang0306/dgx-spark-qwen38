#!/usr/bin/env bash
# Wait for the CONTEXT_MODE=1m install to settle, then report the new runtime facts.
set -uo pipefail
KEY=$(cat "$HOME/.config/qwen38/api-key")

echo "waiting for the installer (max 40 min)..."
for i in $(seq 1 120); do
  pgrep -f "[i]nstall.sh" >/dev/null 2>&1 || break
  sleep 20
done
echo "=== installer finished after ~$((i*20))s ==="
tail -18 "$HOME/dsh-work/install-1m.log"

echo
echo "=== 新的单元参数 ==="
grep -oE '\-\-context-length [0-9]+|\-\-mem-fraction-static [0-9.]+|\-\-chunked-prefill-size [0-9]+' \
  /etc/systemd/system/qwen38-sglang.service | sort -u

echo
echo "=== 服务 / 健康 ==="
systemctl is-active qwen38-sglang.service qwen38-keepalive.service | tr '\n' ' '; echo
sleep 5
curl -s -m 15 -o /dev/null -w '  app health=%{http_code}\n' http://127.0.0.1:30000/health || true
curl -s -m 15 -o /dev/null -w '  proxy health=%{http_code}\n' http://127.0.0.1:30001/health || true

echo
echo "=== 运行时上下文容量（关键数字）==="
curl -s -m 20 http://127.0.0.1:30000/get_server_info -H "Authorization: Bearer $KEY" \
  | python3 -c '
import json,sys
d=json.load(sys.stdin)
for k in ("context_length","max_total_num_tokens","mem_fraction_static","max_prefill_tokens","chunked_prefill_size","max_running_requests","max_mamba_cache_size"):
    print("  %-26s %s" % (k, d.get(k)))
' 2>&1 | head -12

echo
echo "=== YaRN 补丁落地确认 ==="
for r in RadixArk--Qwen3.8-27B-NVFP4 z-lab--Qwen3.8-27B-DFlash2; do
  f=$(ls -d "$HOME/.cache/huggingface/hub/models--$r"/snapshots/*/config.json 2>/dev/null | head -1)
  [ -n "$f" ] && python3 -c "
import json,sys
d=json.load(open('$f'))
tc=d.get('text_config',d)
print('  %-28s max_position_embeddings=%s rope_type=%s factor=%s' % ('$r', tc.get('max_position_embeddings'), tc.get('rope_parameters',{}).get('rope_type'), tc.get('rope_parameters',{}).get('factor')))
" || echo "  $r: config.json 未找到"
done

echo
echo "=== 宿主内存 ==="
awk '/MemTotal|MemAvailable/{printf "  %-14s %.1f GiB\n", $1, $2/1048576}' /proc/meminfo
echo "READY_1M"
