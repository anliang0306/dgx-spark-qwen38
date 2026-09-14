#!/usr/bin/env bash
set -uo pipefail
KEY=$(cat "$HOME/.config/qwen38/api-key")
echo "key      : $KEY"
echo "key file : $(ls -l "$HOME/.config/qwen38/api-key")"
echo -n "auth test: "
curl -s -m 8 -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1:30000/v1/models -H "Authorization: Bearer $KEY"
echo -n "no-auth  : "
curl -s -m 8 -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1:30000/v1/models
echo -n "served   : "
curl -s -m 8 http://127.0.0.1:30000/v1/models -H "Authorization: Bearer $KEY" | python3 -c 'import json,sys; print([m["id"] for m in json.load(sys.stdin)["data"]])'
