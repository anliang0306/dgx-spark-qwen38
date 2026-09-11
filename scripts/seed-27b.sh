#!/usr/bin/env bash
# Seed the 27B lane's two checkpoints (target + DFlash2 draft) via ModelScope,
# hash-verified against the pinned HuggingFace revisions.
set -uo pipefail
cd "$HOME/dsh-work"

cat > "$HOME/dsh-work/seed-27b-runner.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
cd "$HOME/dsh-work"
echo "=== target: RadixArk/Qwen3.8-27B-NVFP4 ==="
SEED_REPO="RadixArk/Qwen3.8-27B-NVFP4" \
SEED_REV="52d1adc5f38aa5ebf099c29ed7025ba34cfbb854" \
SEED_TAG=27b-target SEED_WORKERS=8 \
  python3 -u seed_hf_cache.py
echo "target rc=$?"
echo "=== draft: z-lab/Qwen3.8-27B-DFlash2 ==="
SEED_REPO="z-lab/Qwen3.8-27B-DFlash2" \
SEED_REV="50307d4c4cde6860d4eee73e2547cd786fe8e8a4" \
SEED_TAG=27b-draft SEED_WORKERS=4 \
  python3 -u seed_hf_cache.py
echo "draft rc=$?"
echo SEED_ALL_DONE
EOS

if pgrep -f "[s]eed-27b-runner.sh" >/dev/null; then
  echo "runner already active"; exit 0
fi
nohup bash "$HOME/dsh-work/seed-27b-runner.sh" > "$HOME/dsh-work/seed-27b-runner.log" 2>&1 &
echo "seeder runner started pid=$!"
sleep 40
echo "--- runner log ---"
tail -20 "$HOME/dsh-work/seed-27b-runner.log"
echo "--- per-repo logs ---"
for f in "$HOME"/dsh-work/seed-27b-target.log "$HOME"/dsh-work/seed-27b-draft.log; do
  [ -f "$f" ] && { echo "[$(basename "$f")]"; tail -3 "$f"; }
done
