#!/usr/bin/env python3
"""Measure how large this conversation really is, from the DSH session log.
Python 3.14 ships compression.zstd (PEP 784), so no extra dependency is needed."""
import glob
import json
import os
import sys

try:
    from compression import zstd
except ImportError:
    print("no compression.zstd in this Python; falling back to size-only estimate")
    zstd = None

SESS = os.path.expanduser("~/.dsh/sessions")
files = sorted(glob.glob(os.path.join(SESS, "**", "*.jsonl.zstd"), recursive=True),
               key=os.path.getmtime, reverse=True)
print(f"found {len(files)} session logs\n")

MARKERS = ["qwen38-flashnext", "DGX-Spark-Qwen3.8", "qwen3.8-27b"]

for path in files[:3]:
    size = os.path.getsize(path)
    mtime = __import__("time").strftime("%m-%d %H:%M", __import__("time").localtime(os.path.getmtime(path)))
    print("=" * 70)
    print(f"{os.path.basename(path)}  compressed={size:,} B  mtime={mtime}")
    if zstd is None:
        continue
    try:
        raw = zstd.decompress(open(path, "rb").read())
    except Exception as e:
        print(f"  decompress failed: {e}")
        continue
    text = raw.decode("utf-8", "replace")
    print(f"  decompressed   = {len(raw):,} B  ({len(text):,} chars)")

    # which conversation is this?
    hits = [m for m in MARKERS if m in text]
    print(f"  markers found  : {hits if hits else '(none of ours)'}")

    # sum the text carried in each JSONL record
    chars = 0
    kinds = {}
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        t = rec.get("type") or rec.get("kind") or "?"
        kinds[t] = kinds.get(t, 0) + 1
        chars += len(line)
    print(f"  records        : {sum(kinds.values()):,}  ({dict(list(kinds.items())[:6])})")
    print(f"  total chars    : {chars:,}")
    print(f"  est. tokens    : {chars/1.88:,.0f} (Chinese ratio 1.88) .. {chars/4:,.0f} (English ratio 4)")
    print(f"  local model window = 262,144  ->  {'EXCEEDS' if chars/4 > 262144 else 'may fit'}")
