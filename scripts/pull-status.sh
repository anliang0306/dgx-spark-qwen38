#!/usr/bin/env bash
set -uo pipefail
L="$HOME/dsh-work/pull-image.log"
echo "unique layers touched: $(grep -oE '^[0-9a-f]{12}' "$L" | sort -u | wc -l)"
echo "final state per layer:"
grep -oE '^[0-9a-f]{12}: [A-Za-z ]+' "$L" | awk -F': ' '{s[$1]=$2} END {for (k in s) print s[k]}' | sort | uniq -c | sort -rn
echo "retries total: $(grep -c Retrying "$L")"
echo "--- tail ---"
tail -n 4 "$L"
echo "--- seed ---"
tail -n 1 "$HOME/dsh-work/seed.log"
du -sh "$HOME/.cache/huggingface/hub/models--RadixArk--Qwen3.8-Flash-Next-NVFP4/blobs"
