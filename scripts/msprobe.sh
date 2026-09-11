#!/usr/bin/env bash
set -uo pipefail
REPO="RadixArk/Qwen3.8-Flash-Next-NVFP4"
F="model-plefp8-00001.safetensors"   # 5.2 GB
BASE="https://www.modelscope.cn/api/v1/models/${REPO}/repo?Revision=master&FilePath=${F}"

echo "=== modelscope headers ==="
curl -sSL -m 30 -o /dev/null -D - -r 0-1023 "$BASE" 2>&1 | head -20

echo
echo "=== modelscope single-stream speed (first 200 MB, 60 s cap) ==="
curl -sSL -m 60 -r 0-209715199 -o /dev/null -w 'speed=%{speed_download} B/s bytes=%{size_download} http=%{http_code}\n' "$BASE"

echo
echo "=== modelscope 4-parallel aggregate (200 MB each) ==="
TMP=$(mktemp -d); start=$(date +%s.%N); pids=()
for i in 0 1 2 3; do
  off=$(( i * 209715200 )); end=$(( off + 209715199 ))
  curl -sSL -m 120 -r "${off}-${end}" -o "$TMP/p.$i" "$BASE" & pids+=($!)
done
ok=0; for p in "${pids[@]}"; do wait "$p" && ok=$((ok+1)); done
finish=$(date +%s.%N); bytes=$(du -sb "$TMP" | cut -f1)
awk -v b="$bytes" -v a="$start" -v c="$finish" -v k="$ok" 'BEGIN{printf "ok=%s bytes=%d wall=%.1fs aggregate=%.2f MB/s\n", k, b, c-a, b/1048576/(c-a)}'
rm -rf "$TMP"

echo
echo "=== docker pull status ==="
tail -n 3 "$HOME/dsh-work/pull-image.log"
docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | head -3
