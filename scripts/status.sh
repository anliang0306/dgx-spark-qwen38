#!/usr/bin/env bash
set -uo pipefail
echo "=== seed ==="
python3 - <<'PY'
import json, os
p = os.path.expanduser('~/dsh-work/seed-status.json')
try:
    d = json.load(open(p))
    print("done %d/%d files  %.1f/%.1f GB  %.1f MB/s  eta %.0f min  failed=%d  in-flight=%d"
          % (d['done'], d['total'], d['bytes_done']/1e9, d['bytes_total']/1e9,
             d.get('mbps', 0), d.get('eta_s', 0)/60, len(d['failed']), len(d['active'])))
    if d['failed']:
        print("failures:", d['failed'][:3])
    for r in d.get('recent', [])[-4:]:
        print("   recent: %-55s %6.2f GB %6.1fs %s" % (r['path'], r['mb'], r['s'], r['how']))
except FileNotFoundError:
    print("no status file yet")
PY
du -sh ~/.cache/huggingface/hub/*/blobs 2>/dev/null
echo
echo "=== docker image ==="
tail -n 2 ~/dsh-work/pull-image.log 2>/dev/null
pgrep -af "docker pull" | head -2 || echo "no pull running"
docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' 2>/dev/null | head -3
echo
echo "=== disk / mem ==="
df -h / | tail -1
awk '/MemAvailable|MemTotal/{printf "%s %.0f GiB\n", $1, $2/1048576}' /proc/meminfo
