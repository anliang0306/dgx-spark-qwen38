#!/usr/bin/env bash
# Before switching the 27B lane to CONTEXT_MODE=1m: see exactly what the YaRN
# patch touches, and confirm the repo clone is clean enough for install.sh.
set -uo pipefail
R="$HOME/dsh-work/repo"

echo "############ 1. patch-yarn.py 全文 ############"
cat "$R/patch-yarn.py"

echo
echo "############ 2. install.sh 里调用它的位置与上下文 ############"
grep -n -B6 -A6 'patch-yarn' "$R/install.sh" | head -40

echo
echo "############ 3. CONTEXT_MODE=1m 相关的其它改动 ############"
grep -n -B3 -A8 'CONTEXT_MODE' "$R/install.sh" | grep -iE 'yarn|1m|mem-fraction|0\.70|patch|keepalive|context-length' | head -25

echo
echo "############ 4. 仓库是否干净（install.sh 可能要求）############"
git -C "$R" status --short --untracked-files=no | head -5
git -C "$R" log --oneline -1
