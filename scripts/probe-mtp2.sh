#!/usr/bin/env bash
# Is there a measured MTP-vs-DFlash2 comparison on THIS hardware in the lane's docs?
set -uo pipefail
R="$HOME/dsh-work/repo"

echo "############ BENCHMARKS.md 中 MTP / NEXTN 的上下文 ############"
grep -inE -B3 -A6 'mtp|nextn' "$R/BENCHMARKS.md" | head -120

echo
echo "############ README.md 中 MTP 的上下文 ############"
grep -inE -B2 -A5 'mtp|nextn' "$R/README.md" | head -60
