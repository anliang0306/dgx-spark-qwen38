#!/usr/bin/env python3
"""Prove the 1M window end-to-end: send a prompt that exceeds the OLD 262,144 limit.
ASCII-only output so the Windows console codepage cannot break it."""
import json
import os
import sys
import time
import urllib.error
import urllib.request

# Point these at your own deployment; no credentials live in this file.
BASE = os.environ.get("DGX_BASE", "http://<DGX_HOST>:30000/v1")
KEY = os.environ.get("DGX_API_KEY") or sys.exit("set DGX_API_KEY")
UNIT = "the quick brown fox jumps over the lazy dog. "


def chat(content, max_tokens=8, timeout=2400):
    payload = {"model": "qwen3.8-27b",
               "messages": [{"role": "user", "content": content}],
               "max_tokens": max_tokens, "temperature": 0,
               "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(
        BASE + "/chat/completions", data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"},
        method="POST")
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode()), time.time() - t0
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), time.time() - t0
    except Exception as e:
        return None, f"{type(e).__name__}: {e}", time.time() - t0


n = int(sys.argv[1]) if len(sys.argv) > 1 else 34000
text = UNIT * n
print(f"filler: {len(text):,} chars (~{len(text)//4:,} tokens by chars/4)", flush=True)

st, body, el = chat(text)
print(f"\nstatus={st}  elapsed={el:.1f}s", flush=True)
if st == 200:
    pt = body["usage"]["prompt_tokens"]
    print(f"RESULT: PASS -- prompt_tokens={pt:,} (> 262,144, so the old window would have rejected it)", flush=True)
    print(f"        completion={body['usage']['completion_tokens']} tokens", flush=True)
else:
    print(f"RESULT: FAIL -- {str(body)[:500]}", flush=True)
