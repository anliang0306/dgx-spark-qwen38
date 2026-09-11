#!/usr/bin/env python3
"""
Concurrency probe: N parallel streaming requests against the running server.

Env:
  MODEL    served model name (default: qwen3.8-27b)
  STREAMS  concurrency level (default: 8)
  MAXTOK   max_tokens per request (default: 400)
  ROUNDS   repeat the batch this many times (default: 1) -- use >1 for a soak
"""
import json
import os
import statistics
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

PORT = int(os.environ.get("PORT", "30000"))
KEY = open(os.path.expanduser("~/.config/qwen38/api-key")).read().strip()
MODEL = os.environ.get("MODEL", "qwen3.8-27b")
STREAMS = int(os.environ.get("STREAMS", "8"))
MAXTOK = int(os.environ.get("MAXTOK", "400"))
ROUNDS = int(os.environ.get("ROUNDS", "1"))

PROMPTS = [
    "Write a Python class implementing an LRU cache with O(1) get and put.",
    "Explain the difference between a process and a thread, with a concrete example.",
    "Compute the sum of the first 200 Fibonacci numbers and show your method.",
    "Write a SQL query and index plan for finding the top 10 customers by revenue.",
    "Summarize how TCP congestion control works in about 300 words.",
    "Write a bash script that rotates log files older than 7 days.",
    "Explain CRISPR-Cas9 to a curious high-school student.",
    "List 8 refactoring techniques with a one-line example each.",
    "What are the trade-offs between optimistic and pessimistic locking?",
    "Describe how a B+ tree index speeds up range queries.",
    "Write a regular expression that validates IPv4 addresses and explain it.",
    "Explain the CAP theorem with a concrete distributed-system example.",
    "How does gradient accumulation let you train with a larger effective batch?",
    "Write a Python context manager that retries a flaky operation with backoff.",
    "Explain what a memory barrier is and when one is needed.",
    "Summarize the difference between RAID 5 and RAID 6.",
]


def run(prompt):
    payload = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": MAXTOK, "temperature": 0,
        "stream": True, "stream_options": {"include_usage": True},
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(
        f"http://127.0.0.1:{PORT}/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"})
    t0 = time.time()
    ttft = None
    n = 0
    err = None
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            for raw in r:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                body = line[5:].strip()
                if body == "[DONE]":
                    break
                try:
                    chunk = json.loads(body)
                except json.JSONDecodeError:
                    continue
                if chunk.get("usage"):
                    n = chunk["usage"].get("completion_tokens", n)
                for ch in chunk.get("choices") or []:
                    d = ch.get("delta") or {}
                    if (d.get("content") or d.get("reasoning_content")) and ttft is None:
                        ttft = time.time() - t0
    except Exception as e:  # noqa: BLE001
        err = f"{type(e).__name__}: {e}"
    return {"n": n, "ttft": ttft, "wall": time.time() - t0, "err": err}


def main():
    times, agg = [], []
    for rnd in range(1, ROUNDS + 1):
        batch = [PROMPTS[(rnd * STREAMS + i) % len(PROMPTS)] for i in range(STREAMS)]
        t0 = time.time()
        with ThreadPoolExecutor(max_workers=STREAMS) as ex:
            out = list(ex.map(run, batch))
        wall = time.time() - t0
        total = sum(o["n"] for o in out)
        errs = [o["err"] for o in out if o["err"]]
        a = total / wall if wall else 0
        ttfts = sorted(o["ttft"] for o in out if o["ttft"])
        agg.append(a)
        times.append(wall)
        print(f"round {rnd}/{ROUNDS}: streams={STREAMS} tokens={total} wall={wall:.1f}s "
              f"aggregate={a:.1f} tok/s per-stream={a/STREAMS:.1f} "
              f"ttft_med={(statistics.median(ttfts)*1000 if ttfts else 0):.0f}ms errors={len(errs)}")
        for e in errs[:3]:
            print(f"   ERROR {e}")

    print()
    print(f"SUMMARY streams={STREAMS} rounds={ROUNDS} "
          f"aggregate mean={statistics.mean(agg):.1f} min={min(agg):.1f} max={max(agg):.1f} tok/s "
          f"| wall mean={statistics.mean(times):.1f}s")


if __name__ == "__main__":
    main()
