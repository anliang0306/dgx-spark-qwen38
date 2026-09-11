#!/usr/bin/env bash
# Re-run the seeder for the draft checkpoint: the blob is already verified, so
# this only rewrites the snapshot symlinks with the corrected relative depth.
set -uo pipefail
cd "$HOME/dsh-work"
SEED_REPO='z-lab/Qwen3.8-27B-DFlash2' \
SEED_REV='50307d4c4cde6860d4eee73e2547cd786fe8e8a4' \
SEED_TAG=27b-draft SEED_WORKERS=4 \
  python3 -u seed_hf_cache.py 2>&1 | tail -5

echo
echo "=== broken symlinks per snapshot ==="
for d in "$HOME"/.cache/huggingface/hub/models--*/snapshots/*/; do
  n=$(find "$d" -xtype l 2>/dev/null | wc -l)
  echo "$n broken  $d"
done

echo
echo "=== the previously broken file ==="
D="$HOME/.cache/huggingface/hub/models--z-lab--Qwen3.8-27B-DFlash2/snapshots/50307d4c4cde6860d4eee73e2547cd786fe8e8a4"
ls -l "$D/assets/dflash2-figure.png" 2>&1
readlink -f "$D/assets/dflash2-figure.png" 2>&1
stat -c '%s bytes, readable=%A' "$D/assets/dflash2-figure.png" 2>&1

echo
echo "=== full file counts ==="
for d in "$HOME"/.cache/huggingface/hub/models--*/snapshots/*/; do
  echo "$(find "$d" -type f -o -type l | wc -l) entries  $d"
done
