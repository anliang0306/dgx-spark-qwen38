#!/usr/bin/env bash
# Wait for the seeded cache and the docker image, then ask the image's own
# huggingface_hub whether it accepts our pre-seeded cache (i.e. whether
# snapshot_download returns instantly or tries to re-download 135 GB).
set -uo pipefail
IMG="lmsysorg/sglang@sha256:9d2a843c706c74bc259c0d9abf360551eb2734e1e7d255ab012a6965f10480b6"
REPO="RadixArk/Qwen3.8-Flash-Next-NVFP4"
REV="7b719225242aacd3dbd3f9407468c2ee9a9d2594"
HF_CACHE="$HOME/.cache/huggingface"

echo "== waiting for the checkpoint seed to finish =="
for i in $(seq 1 180); do
  if grep -q 'DONE' "$HOME/dsh-work/seed.log" 2>/dev/null; then
    tail -n 2 "$HOME/dsh-work/seed.log"
    break
  fi
  sleep 60
done
if ! grep -q 'DONE' "$HOME/dsh-work/seed.log" 2>/dev/null; then
  echo "SEED NOT FINISHED after 180 min"; tail -n 3 "$HOME/dsh-work/seed.log"; exit 1
fi

echo
echo "== waiting for the docker image pull =="
for i in $(seq 1 90); do
  if docker image inspect "$IMG" >/dev/null 2>&1; then echo "image present"; break; fi
  sleep 20
done
if ! docker image inspect "$IMG" >/dev/null 2>&1; then
  echo "IMAGE NOT AVAILABLE after 30 min"; tail -n 5 "$HOME/dsh-work/pull-image.log"; exit 1
fi

echo
echo "== snapshot integrity: files / symlinks / sizes =="
python3 - <<'PY'
import json, os, urllib.request
REV = "7b719225242aacd3dbd3f9407468c2ee9a9d2594"
REPO = "RadixArk/Qwen3.8-Flash-Next-NVFP4"
cache = os.path.expanduser("~/.cache/huggingface/hub/models--" + REPO.replace("/", "--"))
snap = os.path.join(cache, "snapshots", REV)
req = urllib.request.Request(f"https://huggingface.co/api/models/{REPO}/tree/{REV}?recursive=1",
                             headers={"User-Agent": "verify/1.0"})
tree = json.loads(urllib.request.urlopen(req, timeout=60).read().decode())
files = [x for x in tree if x.get("type") == "file"]
bad = []
total = 0
for f in files:
    p = os.path.join(snap, f["path"])
    if not os.path.exists(p):
        bad.append((f["path"], "missing"))
        continue
    sz = os.path.getsize(p)
    total += sz
    if sz != f["size"]:
        bad.append((f["path"], f"{sz} != {f['size']}"))
print(f"snapshot files present: {len(files) - len(bad)}/{len(files)}  bytes={total/1e9:.1f} GB")
print("refs/main:", open(os.path.join(cache, "refs", "main")).read().strip()[:12] if os.path.exists(os.path.join(cache, "refs", "main")) else "MISSING")
if bad:
    print("PROBLEMS:", bad[:10])
else:
    print("snapshot complete and size-consistent")
PY

echo
echo "== does the image's huggingface_hub accept this cache? (180 s cap) =="
start=$(date +%s)
timeout 180 docker run --rm -i --network host --user "$(id -u):$(id -g)" \
  --entrypoint python3 \
  -e HF_HOME=/hf -e HF_HUB_DOWNLOAD_TIMEOUT=30 -e HF_HUB_DISABLE_XET=1 \
  -e REPO="$REPO" -e REV="$REV" \
  -v "$HF_CACHE":/hf \
  "$IMG" - <<'PY'
import os, sys, time
from huggingface_hub import snapshot_download
print("hub version:", __import__("huggingface_hub").__version__)
t0 = time.time()
path = snapshot_download(os.environ["REPO"], revision=os.environ["REV"])
print("resolved in %.1fs -> %s" % (time.time() - t0, path))
PY
rc=$?
end=$(date +%s)
echo "exit=$rc wall=$((end - start))s"
if [ "$rc" -eq 0 ]; then
  echo "VERDICT: cache accepted (no re-download)"
else
  echo "VERDICT: cache NOT accepted (re-download started / error) -- inspect above"
fi
