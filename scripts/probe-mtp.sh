#!/usr/bin/env bash
# Did the lane's authors compare the target's built-in MTP (NEXTN) against the
# external DFlash2 drafter on the 27B? Search their own docs.
set -uo pipefail
R="$HOME/dsh-work/repo"

echo "############ 1. 各文档里 MTP / NEXTN 的出现次数 ############"
for f in README.md BENCHMARKS.md CHANGELOG.md dflash2/ATTRIBUTION.md flash-sglang/ATTRIBUTION.md; do
  [ -f "$R/$f" ] && printf '  %-32s MTP=%-4s NEXTN=%-4s DFlash2=%-4s\n' "$f" \
    "$(grep -ic 'MTP' "$R/$f")" "$(grep -ic 'NEXTN' "$R/$f")" "$(grep -ic 'DFlash2\|DFLASH' "$R/$f")"
done

echo
echo "############ 2. CHANGELOG 里 MTP / NEXTN 相关的决策记录 ############"
grep -inE 'mtp|nextn' "$R/CHANGELOG.md" | head -40

echo
echo "############ 3. dflash2/ATTRIBUTION.md 结论段 ############"
[ -f "$R/dflash2/ATTRIBUTION.md" ] && grep -inE -B2 -A6 'mtp|nextn|replaced|dspark' "$R/dflash2/ATTRIBUTION.md" | head -60
