#!/usr/bin/env python3
"""Pull the subagent model-selection policy record out of the session that
recorded one, to settle whether the delegation allowlist actually took effect."""
import glob
import json
import os
import time

from compression import zstd

SESS = os.path.expanduser("~/.dsh/sessions")
files = sorted(glob.glob(os.path.join(SESS, "**", "*.jsonl.zstd"), recursive=True),
               key=os.path.getmtime, reverse=True)

for path in files[:4]:
    raw = zstd.decompress(open(path, "rb").read()).decode("utf-8", "replace")
    hits = []
    for line in raw.splitlines():
        if "model-selection-policy" in line or '"model/selection"' in line:
            try:
                hits.append(json.loads(line))
            except Exception:
                pass
    if not hits:
        continue
    mt = time.strftime("%m-%d %H:%M", time.localtime(os.path.getmtime(path)))
    print("=" * 70)
    print(f"session log mtime={mt}  ({os.path.getsize(path):,} B compressed)")
    for h in hits[:6]:
        t = h.get("type") or h.get("kind")
        print(f"  --- {t} ---")
        body = {k: v for k, v in h.items() if k not in ("type", "kind")}
        s = json.dumps(body, ensure_ascii=False)
        print("  " + (s[:900] + ("…" if len(s) > 900 else "")))
    break
