#!/usr/bin/env bash
set -uo pipefail
echo "=== service ==="
systemctl is-active qwen38-flash.service
echo
echo "=== prometheus: speculation / throughput / cache ==="
curl -s -m 10 http://127.0.0.1:30000/metrics 2>/dev/null \
  | grep -Ei 'accept|spec_|decode|gen_throughput|num_running|prefix_cache|token_usage' \
  | grep -v '^#' | head -40
echo
echo "=== engine flags actually running ==="
tr '\0' ' ' < /proc/$(pgrep -f 'sglang.launch_server' | head -1)/cmdline 2>/dev/null | tr ' ' '\n' \
  | grep -E 'speculative|max-running|mamba|mem-fraction|page-size|token-map|ple-|chunked' || echo "(in container, reading launcher instead)"
grep -E 'TIER=|SPEC_TOKEN_MAP|max-running' "$HOME/.config/qwen38/launch-flash.sh" | head -5
echo
echo "=== recent accept-length lines from the engine log ==="
journalctl -u qwen38-flash -n 2000 --no-pager 2>/dev/null | grep -iE 'accept' | tail -12
echo
echo "=== current memory ==="
awk '/MemTotal|MemAvailable/{printf "%s %.1f GiB\n", $1, $2/1048576}' /proc/meminfo
