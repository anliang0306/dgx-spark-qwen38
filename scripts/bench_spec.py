#!/usr/bin/env python3
"""
Fixed-instrument benchmark for the Flash-Next lane, used to compare speculative
draft depths on identical prompts. Greedy, thinking off, short prompts (decode
rate, not prefill).

Usage: python3 bench_spec.py <tag>
Writes ~/dsh-work/sweep/<tag>.json and prints a one-line summary plus details.
"""
import json
import os
import statistics
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

PORT = int(os.environ.get("PORT", "30000"))
BASE = f"http://127.0.0.1:{PORT}"
KEY = open(os.path.expanduser("~/.config/qwen38/api-key")).read().strip()
MODEL = "qwen3.8-flash-next"
OUTDIR = os.path.expanduser("~/dsh-work/sweep")

PROMPTS = [
    ("code", 512, "Write a Python function that merges two sorted lists in O(n) and explain the edge cases it handles. Keep it under 400 tokens."),
    ("math", 512, "A train leaves at 14:20 and travels 187 km at 82 km/h, then 94 km at 61 km/h. What time does it arrive? Show the arithmetic."),
    ("prose", 512, "Describe in three short paragraphs why memory bandwidth, not raw TFLOPs, decides single-stream inference speed on a unified-memory machine."),
    ("code2", 512, "Implement a thread-safe bounded blocking queue in Python with condition variables, and list the failure modes you avoided."),
    ("list", 512, "List eight differences between TCP and UDP, one line each, then give one protocol example for each."),
]


def call(prompt, max_tokens):
    payload = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0,
        "stream": True,
        "stream_options": {"include_usage": True},
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(
        BASE + "/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"})
    t0 = time.time()
    ttft = None
    usage = {}
    with urllib.request.urlopen(req, timeout=1200) as r:
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
                usage = chunk["usage"]
            for ch in chunk.get("choices") or []:
                d = ch.get("delta") or {}
                if (d.get("content") or d.get("reasoning_content")) and ttft is None:
                    ttft = time.time() - t0
    wall = time.time() - t0
    n = usage.get("completion_tokens", 0)
    dec = (n - 1) / (wall - ttft) if ttft and n > 1 and wall > ttft else 0.0
    return {"n": n, "pt": usage.get("prompt_tokens", 0), "ttft": ttft,
            "wall": wall, "decode": dec}


def main():
    tag = sys.argv[1] if len(sys.argv) > 1 else "unlabeled"
    os.makedirs(OUTDIR, exist_ok=True)

    # warm-up: the engine sleeps on idle, so the first request pays the wake-up
    call("Reply with the single word: READY", 16)

    single = {}
    for name, mt, prompt in PROMPTS:
        runs = [call(prompt, mt) for _ in range(2)]
        runs.sort(key=lambda r: r["decode"])
        med = runs[len(runs) // 2]
        single[name] = {"decode": med["decode"], "ttft_ms": (med["ttft"] or 0) * 1000,
                        "out": med["n"], "runs": [round(r["decode"], 1) for r in runs]}
        print(f"  {name:6s} decode={med['decode']:6.1f} tok/s  ttft={single[name]['ttft_ms']:6.0f} ms  out={med['n']}")

    t0 = time.time()
    with ThreadPoolExecutor(max_workers=4) as ex:
        conc = list(ex.map(lambda p: call(p[2], p[1]), PROMPTS[:4]))
    cwall = time.time() - t0
    ctotal = sum(c["n"] for c in conc)
    agg = ctotal / cwall

    decodes = [v["decode"] for v in single.values()]
    result = {
        "tag": tag,
        "single_mean": statistics.mean(decodes),
        "single_median": statistics.median(decodes),
        "single_min": min(decodes),
        "single_max": max(decodes),
        "conc4_aggregate": agg,
        "conc4_tokens": ctotal,
        "conc4_wall": cwall,
        "per_prompt": single,
        "ts": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    with open(os.path.join(OUTDIR, f"{tag}.json"), "w") as f:
        json.dump(result, f, indent=2)

    print(f"SUMMARY {tag}: single mean={result['single_mean']:.1f} "
          f"median={result['single_median']:.1f} range=[{result['single_min']:.1f},{result['single_max']:.1f}] "
          f"| conc4 aggregate={agg:.1f} tok/s ({ctotal} tok in {cwall:.1f}s)")


if __name__ == "__main__":
    main()
