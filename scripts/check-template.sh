#!/usr/bin/env bash
set -uo pipefail
T="$HOME/.config/qwen38/chat-template-sglang.jinja"
echo "=== 模板文件 ==="
ls -l "$T"
echo
echo "=== reasoning_effort / thinking 相关片段 ==="
grep -n -i -E 'reasoning_effort|thinking|enable_thinking|effort' "$T" | head -40
echo
echo "=== 模板里出现的取值字符串 ==="
grep -o -E "'(xhigh|high|medium|low|minimal|none|off)'|\"(xhigh|high|medium|low|minimal|none|off)\"" "$T" | sort | uniq -c | sort -rn | head -20
echo
echo "=== 用各档位实测一次请求 ==="
KEY=$(cat "$HOME/.config/qwen38/api-key")
for lvl in low medium xhigh none; do
  out=$(curl -s -m 60 http://127.0.0.1:30000/v1/chat/completions \
    -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d "{\"model\":\"qwen3.8-27b\",\"messages\":[{\"role\":\"user\",\"content\":\"say ok\"}],\"max_tokens\":16,\"reasoning_effort\":\"$lvl\"}")
  code=$(echo "$out" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    if "error" in d: print("ERROR:", str(d["error"])[:90])
    else:
        m=d["choices"][0]["message"]
        print("ok content=%r reasoning=%r" % ((m.get("content") or "")[:20], (m.get("reasoning_content") or "")[:20]))
except Exception as e: print("parse-fail", e)' 2>&1)
  printf '  reasoning_effort=%-8s -> %s\n' "$lvl" "$code"
done
