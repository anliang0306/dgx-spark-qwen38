#!/usr/bin/env bash
# Does the deployed SGLang endpoint accept the OpenAI `developer` role, and which
# compat-relevant request fields does it tolerate? Evidence for models.json compat.
set -uo pipefail
KEY=$(cat "$HOME/.config/qwen38/api-key")
API=http://127.0.0.1:30000/v1/chat/completions

try() {
  local label="$1" body="$2"
  local out
  out=$(curl -s -m 45 "$API" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d "$body" 2>&1)
  printf '  %-34s -> %s\n' "$label" "$(printf '%s' "$out" | python3 -c '
import json,sys
raw=sys.stdin.read()
try:
    d=json.loads(raw)
    if "error" in d:
        e=d["error"]; m=e.get("message") if isinstance(e,dict) else str(e)
        print("ERROR:", str(m).replace("\n"," ")[:120])
    else:
        print("ok")
except Exception:
    print("unparseable:", raw[:100])
')"
}

M='"model":"qwen3.8-27b","messages":'
try "system role"        "{$M[{\"role\":\"system\",\"content\":\"be brief\"},{\"role\":\"user\",\"content\":\"say ok\"}],\"max_tokens\":16}"
try "developer role"     "{$M[{\"role\":\"developer\",\"content\":\"be brief\"},{\"role\":\"user\",\"content\":\"say ok\"}],\"max_tokens\":16}"
try "store=false"        "{$M[{\"role\":\"user\",\"content\":\"say ok\"}],\"max_tokens\":16,\"store\":false}"
try "stream_options"     "{$M[{\"role\":\"user\",\"content\":\"say ok\"}],\"max_tokens\":16,\"stream\":true,\"stream_options\":{\"include_usage\":true}}"
try "chat_template_kwargs off" "{$M[{\"role\":\"user\",\"content\":\"say ok\"}],\"max_tokens\":16,\"chat_template_kwargs\":{\"enable_thinking\":false}}"
try "tool call shape"    "{$M[{\"role\":\"user\",\"content\":\"weather in Shanghai?\"}],\"max_tokens\":64,\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"description\":\"get weather\",\"parameters\":{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"}},\"required\":[\"city\"]}}}]}"
