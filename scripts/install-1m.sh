#!/usr/bin/env bash
# Switch the 27B lane to CONTEXT_MODE=1m (YaRN -> 1,010,000 tokens, mem-fraction 0.70).
# Runs as root (helper --sudo): writes the temporary NOPASSWD drop-in, then launches
# install.sh AS the deployment user so the rendered unit keeps User=<deployment user>.
set -uo pipefail

USER_NAME="${DGX_TARGET_USER:?set DGX_TARGET_USER to the deployment user}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
[ -n "$USER_HOME" ] || { echo "no such user: $USER_NAME" >&2; exit 1; }
LOG="$USER_HOME/dsh-work/install-1m.log"
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
sudo -u "$USER_NAME" -H sudo -n true && echo "passwordless sudo confirmed"

echo
echo "=== 2. current context mode ==="
grep -oE '\-\-context-length [0-9]+|\-\-mem-fraction-static [0-9.]+' /etc/systemd/system/qwen38-sglang.service | sort -u

echo
echo "=== 3. launching CONTEXT_MODE=1m installer as $USER_NAME ==="
: > "$LOG"
chown "$USER_NAME:$USER_NAME" "$LOG"
nohup sudo -u "$USER_NAME" -H bash -c \
  "cd '$REPO' && MODEL_CHOICE=stock CONTEXT_MODE=1m ./install.sh" \
  >>"$LOG" 2>&1 &
echo "installer started pid=$! log=$LOG"

sleep 90
echo
echo "--- log so far ---"
tail -30 "$LOG"
