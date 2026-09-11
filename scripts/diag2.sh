#!/usr/bin/env bash
set -uo pipefail
B=~/.cache/huggingface/hub/models--RadixArk--Qwen3.8-Flash-Next-NVFP4/blobs
sum_parts() { ls -l "$B"/*.part-* 2>/dev/null | awk '{s+=$5} END{print s+0}'; }
all_bytes() { du -sb "$B" | cut -f1; }

P1=$(sum_parts); A1=$(all_bytes); T1=$(date +%s)
sleep 120
P2=$(sum_parts); A2=$(all_bytes); T2=$(date +%s)
awk -v p1="$P1" -v p2="$P2" -v a1="$A1" -v a2="$A2" -v t1="$T1" -v t2="$T2" 'BEGIN{
  t=t2-t1;
  printf "parts(in-flight) %.1f -> %.1f MB  delta=%.1f MB  =>  %.2f MB/s\n", p1/1048576, p2/1048576, (p2-p1)/1048576, (p2-p1)/1048576/t;
  printf "blobs(total)     %.1f -> %.1f MB  delta=%.1f MB  =>  %.2f MB/s\n", a1/1048576, a2/1048576, (a2-a1)/1048576, (a2-a1)/1048576/t;
}'
echo "--- per-file delta ---"
for f in "$B"/*.part-*; do
  [ -e "$f" ] || continue
  echo "$(stat -c %s "$f") $(basename "$f" | cut -c1-12)"
done | sort -rn | head -14
echo "--- seeder cpu/mem ---"
ps -o pid,etime,time,%cpu,rss,cmd -p "$(pgrep -f seed_hf_cache.py | head -1)" 2>/dev/null
echo "--- tcp info (5 busiest sockets) ---"
ss -tin state established 2>/dev/null | grep -A1 '443' | grep -E 'bytes_acked|rtt' | head -10
