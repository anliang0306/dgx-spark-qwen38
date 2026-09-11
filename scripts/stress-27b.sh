#!/usr/bin/env bash
# Three-phase stress test: repo fixed battery, 8-way concurrency, then a soak
# with host-memory sampling to catch drift or leaks.
set -uo pipefail
cd "$HOME/dsh-work"
MEMLOG="$HOME/dsh-work/soak-mem.log"

echo "########## Phase A: repo fixed battery (bench-matrix.sh, 8 probes x 2 calls) ##########"
if timeout 2400 bash "$HOME/dsh-work/repo/bench-matrix.sh" 2>&1 | tail -35; then
  echo "phase A rc=$?"
else
  echo "phase A rc=$?"
fi

echo
echo "########## Phase B: 8-way concurrency (one batch) ##########"
MODEL=qwen3.8-27b STREAMS=8 MAXTOK=400 ROUNDS=1 python3 "$HOME/dsh-work/conc8.py"

echo
echo "########## Phase C: soak, 8 streams x 10 rounds (with memory sampling) ##########"
: > "$MEMLOG"
(
  for i in $(seq 1 90); do
    printf '%s %s\n' "$(date +%H:%M:%S)" "$(awk '/MemAvailable/{printf "%.1f", $2/1048576}' /proc/meminfo)" >> "$MEMLOG"
    sleep 10
  done
) &
SAMPLER=$!

MODEL=qwen3.8-27b STREAMS=8 MAXTOK=400 ROUNDS=10 python3 "$HOME/dsh-work/conc8.py"
kill "$SAMPLER" 2>/dev/null || true
wait "$SAMPLER" 2>/dev/null || true

echo
echo "--- host MemAvailable during the soak (first/last 5 samples) ---"
head -5 "$MEMLOG"; echo "   ..."; tail -5 "$MEMLOG"

echo
echo "########## post-stress state ##########"
systemctl is-active qwen38-sglang.service qwen38-keepalive.service | tr '\n' ' '; echo
curl -s -m 5 -o /dev/null -w 'app health=%{http_code}\n' http://127.0.0.1:30000/health
curl -s -m 5 -o /dev/null -w 'proxy health=%{http_code}\n' http://127.0.0.1:30001/health
awk '/MemTotal|MemAvailable/{printf "%s %.1f GiB\n", $1, $2/1048576}' /proc/meminfo
docker stats --no-stream --format '{{.Name}}: CPU={{.CPUPerc}} MEM={{.MemUsage}}' 2>/dev/null | head -3
echo "--- engine log: error/traceback lines in the last 45 min ---"
journalctl -u qwen38-sglang --since '-45 min' --no-pager 2>/dev/null | grep -icE 'traceback|exception|error' || echo 0
echo "--- last 6 engine log lines ---"
journalctl -u qwen38-sglang -n 6 --no-pager 2>/dev/null | tail -6
echo STRESS_DONE
