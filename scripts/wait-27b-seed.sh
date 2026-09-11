#!/usr/bin/env bash
# Wait for both the checkpoint seed and the base-image pull, then report.
set -uo pipefail
IMG="lmsysorg/sglang@sha256:febfb971c7352570fc445c466ebd6ffc9d896024958e544a60f2137fd85856b1"

echo "== waiting for the seeder (max 60 min) =="
for i in $(seq 1 180); do
  grep -q SEED_ALL_DONE "$HOME/dsh-work/seed-27b-runner.log" 2>/dev/null && break
  sleep 20
done
echo "--- runner log ---"
tail -8 "$HOME/dsh-work/seed-27b-runner.log"

echo
echo "--- per-checkpoint result ---"
python3 - <<'PY'
import json, os
for tag in ("27b-target", "27b-draft"):
    p = os.path.expanduser(f"~/dsh-work/seed-status-{tag}.json")
    try:
        d = json.load(open(p))
        print(f"{tag:11s} done={d['done']}/{d['total']}  {d['bytes_done']/1e9:.2f}/{d['bytes_total']/1e9:.2f} GB  failed={len(d['failed'])}")
        for f in d['failed'][:3]:
            print(f"            FAILED {f['path']}: {f['error'][:120]}")
    except FileNotFoundError:
        print(f"{tag:11s} (no status file yet)")
PY

echo
echo "--- snapshots on disk ---"
for d in "$HOME"/.cache/huggingface/hub/models--*/snapshots/*/; do
  [ -d "$d" ] && echo "$(ls "$d" | wc -l) files  $d"
done
du -sh "$HOME"/.cache/huggingface/hub/models--* 2>/dev/null
echo "broken symlinks (should be 0): $(find "$HOME"/.cache/huggingface -xtype l 2>/dev/null | wc -l)"

echo
echo "== waiting for the docker pull (max 60 min) =="
for i in $(seq 1 180); do
  docker image inspect "$IMG" >/dev/null 2>&1 && break
  sleep 20
done
if docker image inspect "$IMG" >/dev/null 2>&1; then
  echo "image present"
else
  echo "IMAGE STILL MISSING"; tail -6 "$HOME/dsh-work/pull-27b.log"
fi
docker images --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}' 2>/dev/null | head -5
echo
df -h / | tail -1
echo "READY_FOR_INSTALL"
