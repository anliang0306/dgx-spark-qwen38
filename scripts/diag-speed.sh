#!/usr/bin/env bash
set -uo pipefail
B=~/.cache/huggingface/hub/models--RadixArk--Qwen3.8-Flash-Next-NVFP4/blobs
S1=$(du -sb "$B" | cut -f1); T1=$(date +%s)
sleep 60
S2=$(du -sb "$B" | cut -f1); T2=$(date +%s)
awk -v a="$S1" -v b="$S2" -v t1="$T1" -v t2="$T2" 'BEGIN{d=b-a; t=t2-t1; printf "seeder throughput: %.1f MB/s (%d bytes in %ds)\n", d/1048576/t, d, t}'

echo "--- in-flight part files (top 15 by current size) ---"
ls -l --block-size=M "$B"/*.part-* 2>/dev/null | awk '{print $5, $9}' | sort -rh | head -15
echo "count: $(ls "$B"/*.part-* 2>/dev/null | wc -l)"

echo
echo "--- independent 4-way range test right now (200 MB each, ModelScope) ---"
REPO="RadixArk/Qwen3.8-Flash-Next-NVFP4"
F="model-plefp8-00001.safetensors"
URL="https://www.modelscope.cn/api/v1/models/${REPO}/repo?Revision=master&FilePath=${F}"
TMP=$(mktemp -d); start=$(date +%s.%N); pids=()
for i in 0 1 2 3; do
  off=$(( i * 209715200 )); end=$(( off + 209715199 ))
  curl -sSL -m 90 -r "${off}-${end}" -o "$TMP/p.$i" "$URL" & pids+=($!)
done
ok=0; for p in "${pids[@]}"; do wait "$p" && ok=$((ok+1)); done
finish=$(date +%s.%N); bytes=$(du -sb "$TMP" | cut -f1)
awk -v b="$bytes" -v a="$start" -v c="$finish" -v k="$ok" 'BEGIN{printf "ok=%s bytes=%d wall=%.1fs aggregate=%.2f MB/s\n", k, b, c-a, b/1048576/(c-a)}'
rm -rf "$TMP"

echo
echo "--- concurrent connections to modelscope cdn ---"
ss -tn state established '( dport = :443 )' 2>/dev/null | grep -c 'modelscope\|:' || true
