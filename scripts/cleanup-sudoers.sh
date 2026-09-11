#!/usr/bin/env bash
# Remove the temporary NOPASSWD sudoers drop-in created for this deployment.
set -uo pipefail
if [ -f /etc/sudoers.d/99-dsh-temp ]; then
  rm -f /etc/sudoers.d/99-dsh-temp
  echo "removed /etc/sudoers.d/99-dsh-temp"
else
  echo "nothing to remove"
fi
visudo -c >/dev/null && echo "sudoers still parses cleanly"
ls -l /etc/sudoers.d/ 2>/dev/null
