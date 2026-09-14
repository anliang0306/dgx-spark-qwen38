#!/usr/bin/env bash
# Quantify exactly what a switch to multi-user.target (no GUI) would free.
set -uo pipefail

echo "############ 1. 当前默认 target ############"
systemctl get-default
echo "  活动图形目标: $(systemctl is-active graphical.target 2>/dev/null)"

echo
echo "############ 2. 精确口径：cgroup 内存记账（无重复计算）############"
for cg in user@1000.service user.slice system.slice; do
  p="/sys/fs/cgroup/$cg/memory.current"
  [ -f "$p" ] && printf '  %-24s %8.1f MiB\n' "$cg" "$(awk '{print $1/1048576}' "$p")"
done
echo "  --- 图形会话相关 scope ---"
for d in /sys/fs/cgroup/user.slice/user-1000.slice/*/; do
  n=$(basename "$d")
  f="$d/memory.current"
  [ -f "$f" ] && printf '  %-52s %8.1f MiB\n' "$n" "$(awk '{print $1/1048576}' "$f")"
done 2>/dev/null | head -12

echo
echo "############ 3. 进程 RSS 明细（有重复计算，仅作参考）############"
ps -eo rss,comm --sort=-rss 2>/dev/null | awk 'NR==1{next} {a[$2]+=$1} END{for(k in a) printf "%8.1f MiB  %s\n", a[k]/1024, k}' | head -18

echo
echo "############ 4. GPU 侧（统一内存，图形栈也吃）############"
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv 2>/dev/null | head -8
echo "  --- 所有占用 GPU 内存的进程 ---"
nvidia-smi 2>/dev/null | sed -n '/Processes/,$p' | head -12

echo
echo "############ 5. 内存总览 ############"
awk '/MemTotal|MemFree|MemAvailable|Cached|Buffers|Shmem|Slab/{printf "  %-14s %8.1f GiB\n", $1, $2/1048576}' /proc/meminfo

echo
echo "############ 6. CPU 占用前 8 ############"
ps -eo pcpu,comm --sort=-pcpu 2>/dev/null | head -9 | sed 's/^/  /'
