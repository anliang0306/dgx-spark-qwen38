#!/usr/bin/env bash
set -uo pipefail
REPO="RadixArk/Qwen3.8-Flash-Next-NVFP4"
REV="7b719225242aacd3dbd3f9407468c2ee9a9d2594"
BIG="model-bf16-00011.safetensors"
TMP=$(mktemp -d)

test_agg() {
  local base="$1" label="$2"
  local start finish bytes wall agg
  start=$(date +%s.%N)
  local pids=()
  for i in $(seq 0 7); do
    local off=$(( i * 52428800 )) end=$(( i * 52428800 + 52428799 ))
    curl -L -sS -m 180 -r "${off}-${end}" -o "$TMP/$label.$i" "$base/${REPO}/resolve/${REV}/${BIG}" &
    pids+=($!)
  done
  local ok=0
  for p in "${pids[@]}"; do wait "$p" && ok=$((ok+1)); done
  finish=$(date +%s.%N)
  bytes=$(du -sb "$TMP" 2>/dev/null | cut -f1)
  wall=$(awk -v a="$start" -v b="$finish" 'BEGIN{printf "%.1f", b-a}')
  agg=$(awk -v b="$bytes" -v w="$wall" 'BEGIN{printf "%.2f", b/1048576/w}')
  echo "   $label: ok=$ok bytes=$bytes wall=${wall}s aggregate=${agg} MB/s"
  rm -f "$TMP"/$label.*
}

echo "=== aggregate: hf-mirror.com ==="
test_agg "https://hf-mirror.com" mirror

echo
echo "=== modelscope: does it host this checkpoint? ==="
for m in "RadixArk/Qwen3.8-Flash-Next-NVFP4" "Qwen/Qwen3.8-Flash-Next"; do
  code=$(curl -sS -m 20 -o /tmp/ms.json -w '%{http_code}' "https://www.modelscope.cn/api/v1/models/$m")
  echo "   $m -> http=$code $(head -c 200 /tmp/ms.json 2>/dev/null | tr -d '\n')"
done

echo
echo "=== docker pull status ==="
tail -n 5 "$HOME/dsh-work/pull-image.log" 2>/dev/null
docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' 2>/dev/null | head -5
pgrep -af "docker pull" | head -3
rm -rf "$TMP"
