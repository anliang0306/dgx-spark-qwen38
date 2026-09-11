#!/usr/bin/env bash
# Runs as root (invoked via: sudo -S bash -c '<this file>').
set -euo pipefail

echo "=== 1. temp NOPASSWD sudoers ==="
umask 077
printf 'anliang ALL=(ALL) NOPASSWD:ALL\n' > /tmp/99-dsh-temp
visudo -c -f /tmp/99-dsh-temp
install -m 440 -o root -g root /tmp/99-dsh-temp /etc/sudoers.d/99-dsh-temp
rm -f /tmp/99-dsh-temp
ls -l /etc/sudoers.d/99-dsh-temp

echo "=== 2. docker group ==="
if id -nG anliang | tr ' ' '\n' | grep -qx docker; then
  echo "anliang already in docker group"
else
  usermod -aG docker anliang
  echo "added anliang to docker group"
fi
getent group docker

echo "=== 3. sanity ==="
sudo -n -u anliang true && echo "sudo -n works"
echo "done"
