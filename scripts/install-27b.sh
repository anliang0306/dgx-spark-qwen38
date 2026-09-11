#!/usr/bin/env bash
# Phase 2: run the 27B lane installer detached.
#
# Invoked via the helper's --sudo mode, i.e. this script runs as root. That is on
# purpose: it writes the temporary NOPASSWD drop-in directly, then launches
# install.sh AS the deployment user (sudo -u anliang -H) so the rendered systemd
# unit keeps User=anliang instead of becoming root.
set -uo pipefail

USER_NAME=anliang
USER_HOME=/home/anliang
LOG="$USER_HOME/dsh-work/install-27b.log"
REPO="$USER_HOME/dsh-work/repo"

if pgrep -f "[i]nstall.sh" >/dev/null 2>&1; then
  echo "an installer is already running:"; pgrep -af "[i]nstall.sh"; exit 0
fi

echo "=== 1. temporary NOPASSWD drop-in ==="
umask 077
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USER_NAME" > /tmp/99-dsh-temp
visudo -c -f /tmp/99-dsh-temp
install -m 440 -o root -g root /tmp/99-dsh-temp /etc/sudoers.d/99-dsh-temp
rm -f /tmp/99-dsh-temp
ls -l /etc/sudoers.d/99-dsh-temp
sudo -u "$USER_NAME" -H sudo -n true && echo "passwordless sudo confirmed for $USER_NAME"

echo
echo "=== 2. launching the installer as $USER_NAME ==="
: > "$LOG"
chown "$USER_NAME:$USER_NAME" "$LOG"
nohup sudo -u "$USER_NAME" -H bash -c \
  "cd '$REPO' && MODEL_CHOICE=stock CONTEXT_MODE=native ./install.sh" \
  >>"$LOG" 2>&1 &
echo "installer started pid=$! log=$LOG"

sleep 75
echo
echo "--- log so far ---"
tail -35 "$LOG"
