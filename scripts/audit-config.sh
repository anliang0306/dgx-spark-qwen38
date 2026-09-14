#!/usr/bin/env bash
# Collect everything needed to judge whether the RUNNING parameters are optimal:
# the live flags, what the engine actually allocated, and any fallback warnings.
set -uo pipefail
echo "############ 1. 单元文件里声明的参数 ############"
grep -oE '\-\-[a-z0-9-]+( [^ \\]*)?' /etc/systemd/system/qwen38-sglang.service \
  | sed 's/ *$//' | grep -vE '^--(trust-remote-code|host|port)$' | sort -u

echo
echo "############ 2. 容器实际收到的参数 ############"
docker inspect qwen38-sglang --format '{{join .Args "\n"}}' 2>/dev/null | tr '\n' ' ' | sed 's/ --/\n  --/g' | sed 's/^ *//'

echo
echo "############ 3. docker 资源限制 ############"
docker inspect qwen38-sglang --format 'Memory={{.HostConfig.Memory}} MemorySwap={{.HostConfig.MemorySwap}} ShmSize={{.HostConfig.ShmSize}} NetworkMode={{.HostConfig.NetworkMode}} IpcMode={{.HostConfig.IpcMode}}'

echo
echo "############ 4. 启动日志：实际分配到的资源 ############"
journalctl -u qwen38-sglang --no-pager 2>/dev/null \
  | grep -iE 'KV Cache is allocated|max_total_num_tokens|max_running_requests|Capture (cuda graph|target)|cuda graph|Memory pool|mem_fraction|available_gpu_memory|Load weight end|Init torch distributed|torch.compile|torch compile|PLE table:' \
  | tail -30

echo
echo "############ 5. 日志中的降级/回退/警告 ############"
journalctl -u qwen38-sglang --no-pager 2>/dev/null \
  | grep -iE 'fall.?back|eager|not supported|disabled|warn|skip' \
  | grep -viE 'Ignore import error|torchcodec|helion|sarashina|mimo_v2' \
  | tail -20

echo
echo "############ 6. 当前运行时状态 ############"
curl -s -m 8 http://127.0.0.1:30000/get_server_info 2>/dev/null | python3 -m json.tool 2>/dev/null | head -40 || echo "  (/get_server_info 不可用)"
echo
awk '/MemTotal|MemAvailable|Cached/{printf "  %-14s %.1f GiB\n", $1, $2/1048576}' /proc/meminfo
echo "  --- container mem ---"
docker stats --no-stream --format '  {{.Name}} CPU={{.CPUPerc}} MEM={{.MemUsage}} ({{.MemPerc}})' 2>/dev/null
