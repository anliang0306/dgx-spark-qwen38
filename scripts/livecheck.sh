#!/usr/bin/env bash
set -uo pipefail
echo "=== 服务 ==="
systemctl is-active qwen38-sglang.service qwen38-keepalive.service | tr '\n' ' '; echo
systemctl is-enabled qwen38-sglang.service qwen38-keepalive.service | tr '\n' ' '; echo
echo "启动于: $(systemctl show -p ActiveEnterTimestamp --value qwen38-sglang.service)"
echo "运行时长: $(systemctl show -p ActiveEnterTimestampMonotonic --value qwen38-sglang.service >/dev/null; ps -o etime= -p "$(systemctl show -p MainPID --value qwen38-sglang.service)" 2>/dev/null | tr -d ' ')"
echo
echo "=== 容器 ==="
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'
echo
echo "=== 端口 ==="
ss -tln | grep -E ':(30000|30001)' || echo "(未监听!)"
echo
echo "=== 健康检查 ==="
curl -s -m 5 -o /dev/null -w 'app   :30000 health=%{http_code}  (%{time_total}s)\n' http://127.0.0.1:30000/health
curl -s -m 5 -o /dev/null -w 'proxy :30001 health=%{http_code}  (%{time_total}s)\n' http://127.0.0.1:30001/health
echo
echo "=== 真实生成测试 ==="
KEY=$(cat "$HOME/.config/qwen38/api-key")
START=$(date +%s.%N)
RESP=$(curl -s -m 120 http://127.0.0.1:30000/v1/chat/completions \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"用一句中文说明你现在运行在哪台机器上。"}],"max_tokens":80,"temperature":0,"chat_template_kwargs":{"enable_thinking":false}}')
END=$(date +%s.%N)
echo "$RESP" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    m=d["choices"][0]["message"]
    print("回答   :", (m.get("content") or m.get("reasoning_content") or "").strip()[:200])
    print("finish :", d["choices"][0].get("finish_reason"))
    print("tokens : 输入 %d / 输出 %d" % (d["usage"]["prompt_tokens"], d["usage"]["completion_tokens"]))
except Exception as e:
    print("解析失败:", e); print(sys.stdin.read()[:300] if False else "")
'
awk -v a="$START" -v b="$END" 'BEGIN{printf "端到端耗时: %.2f s\n", b-a}'
echo
echo "=== 资源 ==="
awk '/MemTotal|MemAvailable/{printf "%s %.1f GiB\n", $1, $2/1048576}' /proc/meminfo
df -h / | tail -1
