#!/usr/bin/env bash
# Is the KV pool actually binding in real traffic, or is the 48 GB headroom unused
# by choice? Evidence: retractions/preemptions and the KV watermark history.
set -uo pipefail
J="journalctl -u qwen38-sglang --no-pager"

echo "############ 1. 是否发生过 KV 抢占 / 撤回（池子不够的硬证据）############"
eval "$J" 2>/dev/null | grep -icE 'retract|preempt|kv cache is full|out of memory|OutOfMemory' || echo 0
echo "  --- 具体行（最多 10） ---"
eval "$J" 2>/dev/null | grep -iE 'retract|preempt|kv cache is full|out of memory' | tail -10

echo
echo "############ 2. KV 水位历史：full token usage 的最大值 ############"
eval "$J" 2>/dev/null | grep -oE 'full token usage: [0-9.]+' | awk '{print $4}' | sort -rn | head -5 | sed 's/^/  max observed: /'
echo "  （1.00 = KV 池耗尽；池子总量 462272 tokens）"

echo
echo "############ 3. 历史峰值并发与排队情况 ############"
eval "$J" 2>/dev/null | grep -oE '#running-req: [0-9]+' | awk '{print $2}' | sort -rn | head -3 | sed 's/^/  max running: /'
eval "$J" 2>/dev/null | grep -oE '#queue-req: [0-9]+' | awk '{print $2}' | sort -rn | head -3 | sed 's/^/  max queued : /'

echo
echo "############ 4. mamba 池水位历史 ############"
eval "$J" 2>/dev/null | grep -oE 'mamba usage: [0-9.]+' | awk '{print $3}' | sort -rn | head -3 | sed 's/^/  max mamba usage: /'

echo
echo "############ 5. accept len 分布（投机效率）############"
eval "$J" 2>/dev/null | grep -oE 'accept len: [0-9.]+' | awk '{print $3}' | sort -n | awk '
{a[NR]=$1; s+=$1}
END{if(NR==0){print "  (no data)"; exit}
 printf "  n=%d  min=%.2f  p50=%.2f  p90=%.2f  max=%.2f  mean=%.2f\n", NR, a[1], a[int(NR*0.5)], a[int(NR*0.9)], a[NR], s/NR}'
echo "  （draft 宽度 = 8，理论上限约 9）"
