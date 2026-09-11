#!/usr/bin/env bash
# Patch the rendered flash launcher's speculative draft depth. Unprivileged:
# the launcher lives in the user's config dir. A backup is kept on first change.
set -euo pipefail
STEPS="$1"; DRAFT="$2"; TOPK="${3:-1}"
L="$HOME/.config/qwen38/launch-flash.sh"
[ -f "$L" ] || { echo "no launcher at $L" >&2; exit 1; }
[ -f "$L.orig" ] || cp -p "$L" "$L.orig"

sed -i -E \
  -e "s/--speculative-num-steps [0-9]+/--speculative-num-steps ${STEPS}/" \
  -e "s/--speculative-num-draft-tokens [0-9]+/--speculative-num-draft-tokens ${DRAFT}/" \
  -e "s/--speculative-eagle-topk [0-9]+/--speculative-eagle-topk ${TOPK}/" \
  "$L"
bash -n "$L" || { echo "launcher no longer parses, restoring"; cp -p "$L.orig" "$L"; exit 1; }
echo "launcher now:"; grep -E '^TIER=' "$L"
