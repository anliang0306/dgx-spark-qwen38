#!/usr/bin/env bash
# Map which reasoning_effort values the deployed SGLang template actually accepts,
# so the client's compat switches can be set from evidence rather than assumption.
set -uo pipefail
KEY=$(cat "$HOME/.config/qwen38/api-key")
for lvl in off none minimal low medium high xhigh max; do
  out=$(curl -s -m 60 http://127.0.0.1:30000/v1/chat/completions \
    -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d "{\"model\":\"qwen3.8-27b\",\"messages\":[{\"role\":\"user\",\"content\":\"say ok\"}],\"max_tokens\":24,\"reasoning_effort\":\"$lvl\"}" 2>&1)
  printf '  reasoning_effort=%-8s -> %s\n' "$lvl" "$(printf '%s' "$out" | python3 -c '
import json,sys
raw=sys.stdin.read()
try:
    d=json.loads(raw)
    if "error" in d:
        e=d["error"]
        msg=e.get("message") if isinstance(e,dict) else str(e)
        print("ERROR:", str(msg)[:110])
    else:
        m=d["choices"][0]["message"]
        r=(m.get("reasoning_content") or "")
        c=(m.get("content") or "")
        print("ok  reasoning=%s content=%r" % ("yes" if r.strip() else "no ", c.strip()[:24]))
except Exception as ex:
    print("unparseable:", raw[:110])
')"
done
