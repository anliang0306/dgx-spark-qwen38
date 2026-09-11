#!/usr/bin/env bash
set -uo pipefail
# kill the stray self-matching waiter loop from the previous check (if any)
for p in $(pgrep -f "while pgrep -f seed_hf_cache" 2>/dev/null || true); do
  [ "$p" != "$$" ] && kill "$p" 2>/dev/null || true
done
cd "$HOME/dsh-work"
if pgrep -f "[s]eed_hf_cache.py" >/dev/null; then
  echo "seeder still running:"; pgrep -af "[s]eed_hf_cache.py"; exit 0
fi
mv -f seed.log seed-run1.log 2>/dev/null || true
nohup env SEED_WORKERS=3 python3 -u "$HOME/dsh-work/seed_hf_cache.py" >> seed.log 2>&1 &
echo "retry started pid=$!"
sleep 40
tail -n 12 seed.log
