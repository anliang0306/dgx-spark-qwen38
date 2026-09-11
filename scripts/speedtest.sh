#!/usr/bin/env bash
set -uo pipefail
REPO="RadixArk/Qwen3.8-Flash-Next-NVFP4"
REV="7b719225242aacd3dbd3f9407468c2ee9a9d2594"
echo "=== checkpoint file list / total size (pinned rev) ==="
curl -sS -m 60 "https://huggingface.co/api/models/${REPO}/tree/${REV}?recursive=1" -o /tmp/tree.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/tree.json'))
files = [x for x in d if x.get('type') == 'file']
tot = sum(x.get('size', 0) for x in files)
print(f"files={len(files)} total={tot/1e9:.1f} GB")
for x in sorted(files, key=lambda y: -y.get('size', 0))[:6]:
    print(f"  {x.get('size',0)/1e9:8.2f} GB  {x['path']}")
PY
echo
echo "=== download speed test: 200 MB range from the largest shard ==="
BIG=$(python3 -c "
import json
d=json.load(open('/tmp/tree.json'))
f=[x for x in d if x.get('type')=='file']
f.sort(key=lambda y:-y.get('size',0))
print(f[0]['path'])
")
echo "file: $BIG"
URL="https://huggingface.co/${REPO}/resolve/${REV}/${BIG}"
curl -L -sS -m 120 -r 0-209715200 -o /dev/null -w 'speed=%{speed_download} B/s  downloaded=%{size_download} B  http=%{http_code}\n' "$URL" || echo "range download failed"
echo
echo "=== end-to-end small-file test via huggingface_hub (container path) ==="
python3 -c "import huggingface_hub" 2>/dev/null && echo "hub present on host" || echo "hub not on host (installer downloads inside the container)"
