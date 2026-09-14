#!/usr/bin/env bash
# Move the 27B lane from YaRN-1M (1010000 / factor 4.0 / mem-fraction 0.70)
# to a conservative YaRN-512K (524288 / factor 2.0 / mem-fraction 0.60).
#
# Runs as root (helper --sudo). The .pre-yarn backups hold the ORIGINAL native
# config and are deliberately left untouched.
set -uo pipefail

UNIT=/etc/systemd/system/qwen38-sglang.service
HF="${DGX_TARGET_HOME:?set DGX_TARGET_HOME to the deployment user's home}/.cache/huggingface/hub"
TARGET_REV=52d1adc5f38aa5ebf099c29ed7025ba34cfbb854
DRAFT_REV=50307d4c4cde6860d4eee73e2547cd786fe8e8a4

echo "############ 1. 备份 unit ############"
cp -p "$UNIT" "$UNIT.bak-pre512k"
ls -l "$UNIT.bak-pre512k"

echo
echo "############ 2. 改写 YaRN 参数：1010000/factor 4.0 -> 524288/factor 2.0 ############"
python3 - "$HF" "$TARGET_REV" "$DRAFT_REV" <<'PY'
import json, os, sys
hf, trev, drev = sys.argv[1:4]
jobs = [
    (f"{hf}/models--RadixArk--Qwen3.8-27B-NVFP4/snapshots/{trev}/config.json", "target"),
    (f"{hf}/models--z-lab--Qwen3.8-27B-DFlash2/snapshots/{drev}/config.json", "draft "),
]
for path, label in jobs:
    if not os.path.isfile(path):
        sys.exit(f"missing: {path}")
    with open(path, encoding="utf-8") as f:
        cfg = json.load(f)
    tc = cfg.get("text_config", cfg)
    before = (tc.get("max_position_embeddings"), tc.get("rope_parameters", {}).get("factor"))
    tc["max_position_embeddings"] = 524288
    rp = tc.setdefault("rope_parameters", {})
    rp["rope_type"] = "yarn"
    rp["factor"] = 2.0
    rp["original_max_position_embeddings"] = 262144
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
    print(f"  {label}: max_position_embeddings {before[0]} -> 524288, factor {before[1]} -> 2.0")
PY

echo
echo "############ 3. 改写 unit 参数 ############"
sed -i -e 's/--context-length 1010000/--context-length 524288/' \
       -e 's/--mem-fraction-static 0\.70/--mem-fraction-static 0.60/' "$UNIT"
grep -oE '\-\-context-length [0-9]+|\-\-mem-fraction-static [0-9.]+' "$UNIT" | sort -u | sed 's/^/  /'
bash -n <(sed -n "12,37p" "$UNIT" | sed 's/^ExecStart=\/bin\/bash -c //') 2>/dev/null \
  && echo "  (unit 内嵌命令语法检查通过)" || echo "  (语法检查跳过)"

echo
echo "############ 4. 重载并重启 ############"
systemctl daemon-reload
systemctl restart qwen38-sglang
echo "  restart issued; service state = $(systemctl is-active qwen38-sglang)"
echo "  (首次启动约 6-9 分钟)"
echo EDITS_DONE
