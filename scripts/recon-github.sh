#!/usr/bin/env bash
set -uo pipefail
echo "=== git / gh ==="
for c in git gh; do
  if command -v $c >/dev/null 2>&1; then echo "$c -> $(command -v $c) ($($c --version 2>&1 | head -1))"; else echo "$c -> (missing)"; fi
done
echo
echo "=== git identity / remote helpers ==="
git config --global --list 2>/dev/null | grep -E 'user\.|credential|url\.' || echo "(no global user/credential config)"
echo
echo "=== stored credentials ==="
for p in "$HOME/.git-credentials" "$HOME/.netrc" "$HOME/.config/gh/hosts.yml"; do
  if [ -e "$p" ]; then echo "FOUND: $p"; else echo "absent: $p"; fi
done
echo
echo "=== ssh keys ==="
ls -la "$HOME/.ssh" 2>/dev/null | head -10 || echo "(no ~/.ssh)"
echo
echo "=== token env ==="
for v in GH_TOKEN GITHUB_TOKEN; do
  eval "val=\${$v:-}"; [ -n "$val" ] && echo "$v = SET" || echo "$v = unset"
done
echo
echo "=== outbound github reachability ==="
curl -sS -m 15 -o /dev/null -w 'github.com=%{http_code}\n' https://github.com/ 2>&1
curl -sS -m 15 -o /dev/null -w 'api.github.com=%{http_code}\n' https://api.github.com/ 2>&1
