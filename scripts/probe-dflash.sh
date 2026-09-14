#!/usr/bin/env bash
# Is speculative_num_draft_tokens=8 a ceiling or just a default for DFLASH on this
# model? Check the drafter's own config and SGLang's constraints.
set -uo pipefail

echo "############ 1. DFlash2 draft 模型 config.json ############"
D="$HOME/.cache/huggingface/hub/models--z-lab--Qwen3.8-27B-DFlash2/snapshots/50307d4c4cde6860d4eee73e2547cd786fe8e8a4"
cat "$D/config.json"

echo
echo "############ 2. 目标模型 config 里与投机/块大小相关的字段 ############"
T="$HOME/.cache/huggingface/hub/models--RadixArk--Qwen3.8-27B-NVFP4/snapshots/52d1adc5f38aa5ebf099c29ed7025ba34cfbb8854"
T="$HOME/.cache/huggingface/hub/models--RadixArk--Qwen3.8-27B-NVFP4/snapshots/52d1adc5f38aa5ebf099c29ed7025ba34cfbb854"
python3 - "$T/config.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
for k,v in d.items():
    if any(s in k.lower() for s in ('spec','draft','block','mtp','quant','num_hidden','layer','max_position')):
        print("  %-32s %s" % (k, str(v)[:110]))
PY

echo
echo "############ 3. SGLang 源码里 DFLASH 的块大小约束 ############"
docker exec qwen38-sglang bash -lc "grep -rn 'dflash_block_size\|DFLASH' /sgl-workspace/sglang/python/sglang/srt/server_args.py 2>/dev/null | head -20"

echo
echo "############ 4. 是否存在显式的上限/断言 ############"
docker exec qwen38-sglang bash -lc "grep -rn -A4 'dflash_block_size' /sgl-workspace/sglang/python/sglang/srt/speculative/*.py 2>/dev/null | grep -iE 'assert|raise|block_size|64|16|32' | head -20"
