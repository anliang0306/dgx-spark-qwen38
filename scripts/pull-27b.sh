#!/usr/bin/env bash
# Pull the 27B lane's pinned base image ahead of install.sh (step 2 becomes a no-op).
set -uo pipefail
IMG="lmsysorg/sglang@sha256:febfb971c7352570fc445c466ebd6ffc9d896024958e544a60f2137fd85856b1"
LOG="$HOME/dsh-work/pull-27b.log"
if docker image inspect "$IMG" >/dev/null 2>&1; then
  echo "image already present"; exit 0
fi
if pgrep -f "[d]ocker pull" >/dev/null; then
  echo "a docker pull is already running:"; pgrep -af "[d]ocker pull"; exit 0
fi
nohup docker pull "$IMG" >"$LOG" 2>&1 &
echo "pull started pid=$! log=$LOG"
sleep 25
tail -5 "$LOG"
