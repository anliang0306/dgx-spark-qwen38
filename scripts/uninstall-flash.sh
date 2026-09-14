#!/usr/bin/env bash
# Phase 1: remove the Flash-Next lane (services + config) and reclaim its data.
# Run as root with HOME pinned to the deployment user, otherwise uninstall.sh
# resolves ~/.config/qwen38 against /root.
set -uo pipefail
export HOME="${DGX_TARGET_HOME:?set DGX_TARGET_HOME to the deployment user's home directory}"
cd "$HOME/dsh-work/repo"

echo "############ before ############"
df -h / | tail -1
du -sh "$HOME/.cache/huggingface/hub/models--RadixArk--Qwen3.8-Flash-Next-NVFP4" "$HOME/flashnext-ple" 2>/dev/null
docker images -a 2>/dev/null | head -5

echo
echo "############ uninstall (services + config) ############"
./uninstall.sh --yes 2>&1 | tail -25

echo
echo "############ reclaim data ############"
rm -rf "$HOME/.cache/huggingface/hub/models--RadixArk--Qwen3.8-Flash-Next-NVFP4"
echo "removed flash weights"
rm -rf "$HOME/flashnext-ple"
echo "removed PLE table"
IMG_ID="$(docker images -aq --filter 'dangling=true' | head -1)"
if [ -n "$IMG_ID" ]; then
  docker rmi -f "$IMG_ID" 2>&1 | tail -2
  echo "removed dangling serving image ($IMG_ID)"
else
  echo "no dangling image found"
fi

echo
echo "############ after ############"
df -h / | tail -1
echo "--- units ---"
ls /etc/systemd/system/ | grep -i qwen38 || echo "(no qwen38 units left)"
echo "--- config ---"
ls -d "$HOME/.config/qwen38" 2>/dev/null || echo "(config dir removed)"
echo "--- oc launcher ---"
ls -l "$HOME/.local/bin/oc" 2>/dev/null || echo "(oc launcher removed)"
echo "--- remaining images ---"
docker images -a 2>/dev/null | head -5
echo "--- hf cache ---"
ls -la "$HOME/.cache/huggingface/hub/" 2>/dev/null | tail -5
