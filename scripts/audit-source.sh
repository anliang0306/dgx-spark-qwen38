#!/usr/bin/env bash
# Confirm from SGLang's own source what torch_compile_max_bs does above its limit,
# and how the mamba cache size maps to per-request slots.
set -uo pipefail
C=qwen38-sglang
echo "############ torch_compile_max_bs 在源码里的用法 ############"
docker exec "$C" bash -lc "grep -rn 'torch_compile_max_bs' /sgl-workspace/sglang/python/sglang/srt/ 2>/dev/null | head -20"
echo
echo "############ 超过上限时的分支 ############"
docker exec "$C" bash -lc "grep -rn -B3 -A8 'torch_compile_max_bs' /sgl-workspace/sglang/python/sglang/srt/model_executor/model_runner.py 2>/dev/null | head -40"
echo
echo "############ mamba 每请求槽位 ############"
docker exec "$C" bash -lc "grep -rn 'mamba_max_states_per_path\|extra_buffer\|states_per_req\|5 \* ' /sgl-workspace/sglang/python/sglang/srt/mem_cache/*.py 2>/dev/null | head -15"
echo
echo "############ 当前 mamba 池实际分配 ############"
journalctl -u qwen38-sglang --no-pager 2>/dev/null | grep -iE 'mamba.*(cache|pool|alloc)' | tail -8
