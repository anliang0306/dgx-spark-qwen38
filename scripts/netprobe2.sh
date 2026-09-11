#!/usr/bin/env bash
set -uo pipefail
REPO="RadixArk/Qwen3.8-Flash-Next-NVFP4"
REV="7b719225242aacd3dbd3f9407468c2ee9a9d2594"
BIG="model-bf16-00011.safetensors"
URL="https://huggingface.co/${REPO}/resolve/${REV}/${BIG}"
TMP=$(mktemp -d)

echo "=== 8 parallel connections x 50 MB (aggregate) ==="
start=$(date +%s.%N)
pids=()
for i in $(seq 0 7); do
  off=$(( i * 52428800 ))
  end=$(( off + 52428800 - 1 ))
  curl -L -sS -m 180 -r "${off}-${end}" -o "$TMP/part.$i" "$URL" &
  pids+=($!)
done
ok=0
for p in "${pids[@]}"; do wait "$p" && ok=$((ok+1)); done
finish=$(date +%s.%N)
bytes=$(du -sb "$TMP" | cut -f1)
wall=$(awk -v a="$start" -v b="$finish" 'BEGIN{printf "%.1f", b-a}')
agg=$(awk -v b="$bytes" -v w="$wall" 'BEGIN{printf "%.2f", b/1048576/w}')
echo "   connections_ok=$ok  bytes=$bytes  wall=${wall}s  aggregate=${agg} MB/s"
rm -rf "$TMP"

echo
echo "=== host pip reachability + huggingface_hub install ==="
timeout 300 pip3 install --user --quiet --disable-pip-version-check huggingface_hub 2>&1 | tail -3
python3 -c "import huggingface_hub, sys; print('huggingface_hub', huggingface_hub.__version__)" 2>&1

echo
echo "=== docker pull progress ==="
tail -n 3 "$HOME/dsh-work/pull-image.log" 2>/dev/null
docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | head -5
