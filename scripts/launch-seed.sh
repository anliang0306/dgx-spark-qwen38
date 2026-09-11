#!/usr/bin/env bash
set -uo pipefail
cd "$HOME/dsh-work"
if pgrep -f seed_hf_cache.py >/dev/null; then
  echo "seeder already running:"; pgrep -af seed_hf_cache.py
  exit 0
fi
: > seed.log
nohup python3 -u "$HOME/dsh-work/seed_hf_cache.py" >> seed.log 2>&1 &
echo "seeder started pid=$!"
sleep 30
echo "--- first 25s of log ---"
tail -n 25 seed.log
