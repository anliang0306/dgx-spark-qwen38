#!/usr/bin/env python3
"""8-stream aggregate throughput probe against the running server."""
import json
import os
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

PORT = int(os.environ.get("PORT", "30000"))
KEY = open(os.path.expanduser("~/.config/qwen38/api-key")).read().strip()
PROMPTS = [
    "Write a Python class implementing an LRU cache with O(1) get and put.",
    "Explain the difference between a process and a thread, with a concrete example.",
    "Compute the sum of the first 200 Fibonacci numbers and show your method.",
    "Write a SQL query and index plan for finding the top 10 customers by revenue.",
    "Summarize how TCP congestion control works in about 300 words.",
    "Write a bash script that rotates log files older than 7 days.",
    "Explain CRISPR-Cas9 to a curious high-school student.",
    "List 8 refactoring techniques with a one-line example each.",
]


def run(prompt):
    payload = {
        "model": "qwen3.8-flash-next",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 400, "temperature": 0,
        "stream": True, "stream_options": {"include_usage": True},
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(
        f"http://127.0.0.1:{PORT}/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"})
    n = 0
    with urllib.request.urlopen(req, timeout=600) as r:
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
    return n


for streams in (8,):
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=streams) as ex:
        counts = list(ex.map(run, PROMPTS[:streams]))
    wall = time.time() - t0
    total = sum(counts)
    print(f"{streams} streams: {total} tokens in {wall:.1f}s -> aggregate {total/wall:.1f} tok/s "
          f"(per stream {total/wall/streams:.1f} tok/s)")
