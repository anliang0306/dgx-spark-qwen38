#!/usr/bin/env bash
# Launch the flash-lane installer detached, with a log we can poll.
set -uo pipefail
cd "$HOME/dsh-work/repo"
LOG="$HOME/dsh-work/install.log"
if pgrep -f "$HOME/dsh-work/repo/install.sh" >/dev/null 2>&1; then
  echo "installer already running:"; pgrep -af "$HOME/dsh-work/repo/install.sh"
  exit 0
fi
: > "$LOG"
nohup env MODEL_CHOICE=flash FLASH_TIER=context ./install.sh >>"$LOG" 2>&1 &
echo "installer started pid=$! log=$LOG"
sleep 45
echo "--- log so far ---"
tail -n 30 "$LOG"
