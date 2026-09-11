#!/usr/bin/env bash
set -uo pipefail
REPO="RadixArk/Qwen3.8-Flash-Next-NVFP4"
REV="7b719225242aacd3dbd3f9407468c2ee9a9d2594"
BIG="model-bf16-00011.safetensors"

echo "=== docker access without sudo ==="
if docker info >/dev/null 2>&1; then
  echo "OK: docker usable as $(id -un); server=$(docker info --format '{{.ServerVersion}}') root=$(docker info --format '{{.DockerRootDir}}')"
else
  echo "FAIL: docker still needs sudo in this session"
fi

echo
echo "=== mirror reachability ==="
for h in huggingface.co hf-mirror.com www.modelscope.cn; do
  code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' "https://$h/" 2>/dev/null || echo ERR)
  echo "$h -> $code"
done

echo
echo "=== single-connection speed, direct vs mirror (100 MB each) ==="
for base in https://huggingface.co https://hf-mirror.com; do
  echo "-- $base"
  curl -L -sS -m 90 -r 0-104857600 -o /dev/null \
    -w '   speed=%{speed_download} B/s http=%{http_code}\n' \
    "$base/${REPO}/resolve/${REV}/${BIG}" || echo "   failed"
done

echo
echo "=== 4 parallel connections aggregate (direct, 100 MB each) ==="
start=$(date +%s.%N)
for i in 1 2 3 4; do
  off=$(( (i-1) * 104857600 ))
  curl -L -sS -m 120 -r ${off}-$(( off + 104857600 )) -o /dev/null &
done
wait
end=$(date +%s.%N)
echo "   wall=$(echo "$end - $start" | bc) s for 4x100MB"

echo
echo "=== modelscope search for this checkpoint ==="
curl -sS -m 30 "https://www.modelscope.cn/api/v1/dolphin/models?PageSize=5&PageNumber=1&Name=Qwen3.8-Flash-Next" 2>/dev/null | head -c 1200
echo
