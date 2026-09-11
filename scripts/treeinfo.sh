#!/usr/bin/env bash
set -uo pipefail
REPO="RadixArk/Qwen3.8-Flash-Next-NVFP4"
REV="7b719225242aacd3dbd3f9407468c2ee9a9d2594"
curl -sS -m 90 "https://huggingface.co/api/models/${REPO}/tree/${REV}?recursive=1" -o /tmp/tree.json
python3 - <<'PY'
import json, collections
d = json.load(open('/tmp/tree.json'))
files = [x for x in d if x.get('type') == 'file']
lfs = [x for x in files if 'lfs' in x]
nonlfs = [x for x in files if 'lfs' not in x]
print(f"files={len(files)} lfs={len(lfs)} non-lfs={len(nonlfs)}")
print("total = %.1f GB" % (sum(x.get('size',0) for x in files)/1e9))
print("\nsample lfs entry:")
print(json.dumps(lfs[0], ensure_ascii=False)[:400] if lfs else "none")
print("\nsample non-lfs entry:")
print(json.dumps(nonlfs[0], ensure_ascii=False)[:300] if nonlfs else "none")
print("\nsize classes:")
c = collections.Counter()
for x in files:
    c[round(x.get('size',0)/1e9, 2)] += 1
for k, v in sorted(c.items(), reverse=True)[:12]:
    print(f"  {k:6.2f} GB x {v}")
print("\nnon-lfs files (small ones, need git-sha1 verification):")
for x in nonlfs[:15]:
    print(f"  {x.get('size',0):>10} {x['path']} oid={x.get('oid','')[:12]}")
PY
echo
echo "=== docker pull ==="
tail -n 2 "$HOME/dsh-work/pull-image.log"
docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | head -3
