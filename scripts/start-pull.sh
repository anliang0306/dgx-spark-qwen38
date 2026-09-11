#!/usr/bin/env bash
# Start the ~30 GB image pull in the background so it overlaps with the checkpoint work.
set -uo pipefail
IMG="lmsysorg/sglang@sha256:9d2a843c706c74bc259c0d9abf360551eb2734e1e7d255ab012a6965f10480b6"
LOG="$HOME/dsh-work/pull-image.log"
mkdir -p "$HOME/dsh-work"
if docker image inspect "$IMG" >/dev/null 2>&1; then
  echo "image already present"
  exit 0
fi
nohup docker pull "$IMG" >"$LOG" 2>&1 &
echo "pull started pid=$! log=$LOG"
sleep 20
echo "--- log so far ---"
tail -n 8 "$LOG"
