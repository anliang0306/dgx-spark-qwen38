#!/usr/bin/env bash
set -uo pipefail
KEY=$(cat "$HOME/.config/qwen38/api-key")

echo "############ /get_server_info（权威运行时状态）############"
curl -s -m 10 http://127.0.0.1:30000/get_server_info -H "Authorization: Bearer $KEY" \
  | python3 -c '
import json,sys
d=json.load(sys.stdin)
keys=["model_path","served_model_name","context_length","max_total_num_tokens","max_running_requests",
      "max_prefill_tokens","mem_fraction_static","chunked_prefill_size","page_size","tp_size",
      "speculative_algorithm","speculative_num_draft_tokens","cuda_graph_max_bs",
      "max_mamba_cache_size","mamba_radix_cache_strategy","enable_torch_compile",
      "torch_compile_max_bs","num_continuous_decode_steps","disable_prefill_cuda_graph",
      "attention_backend","quantization","dtype","sleep_on_idle"]
for k in keys:
    if k in d: print("  %-30s %s" % (k, d[k]))
print("  --- 其它顶层键 ---")
print("  " + ", ".join(sorted(set(d)-set(keys))))
' 2>&1 | head -40

echo
echo "############ 启动时的 KV 池分配（全量日志搜索）############"
journalctl -u qwen38-sglang --no-pager 2>/dev/null \
  | grep -iE 'KV Cache is allocated|max_total_num_tokens|#tokens:|Memory pool end|available_gpu_memory|Load weight end' \
  | tail -12

echo
echo "############ 启动各阶段耗时（判断是否有可优化项）############"
journalctl -u qwen38-sglang --no-pager 2>/dev/null | grep -iE 'Load weight (begin|end)|Capture .*cuda graph|torch.compile|Warmup|The server is fired up' | tail -12

echo
echo "############ mamba 池实际占用 vs 上限 ############"
journalctl -u qwen38-sglang --no-pager 2>/dev/null | grep -oE 'mamba num: [0-9]+, mamba usage: [0-9.]+' | tail -3
echo "  （mamba usage = 已用槽位 / --max-mamba-cache-size 96）"
