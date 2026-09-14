#!/usr/bin/env python3
"""Print the subagent/model-selection-policy record from every session that has one."""
import glob
import json
import os
import time

from compression import zstd

SESS = os.path.expanduser("~/.dsh/sessions")
files = sorted(glob.glob(os.path.join(SESS, "**", "*.jsonl.zstd"), recursive=True),
               key=os.path.getmtime, reverse=True)

found = 0
for path in files:
    raw = zstd.decompress(open(path, "rb").read()).decode("utf-8", "replace")
    if "model-selection-policy" not in raw:
        continue
    found += 1
    mt = time.strftime("%m-%d %H:%M", time.localtime(os.path.getmtime(path)))
    print("=" * 70)
    print(f"session mtime={mt}   ({os.path.getsize(path):,} B compressed)")
    for line in raw.splitlines():
        if "model-selection-policy" not in line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        print("  type:", r.get("type") or r.get("kind"))
        body = {k: v for k, v in r.items() if k not in ("type", "kind")}
        print("  " + json.dumps(body, ensure_ascii=False)[:1200])
    if found >= 2:
        break

if not found:
    print("no session recorded a subagent model-selection policy")
