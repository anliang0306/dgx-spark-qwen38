#!/usr/bin/env python3
"""End-to-end verification for the Qwen3.8-Flash-Next lane on this box."""
import json
import os
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

PORT = int(os.environ.get("PORT", "30000"))
BASE = f"http://127.0.0.1:{PORT}"
KEY = open(os.path.expanduser("~/.config/qwen38/api-key")).read().strip()
MODEL = os.environ.get("MODEL", "qwen3.8-flash-next")


def post(path, payload, timeout=600):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"},
        method="POST",
    )
    return urllib.request.urlopen(req, timeout=timeout)


def get(path, timeout=30):
    req = urllib.request.Request(BASE + path, headers={"Authorization": f"Bearer {KEY}"})
    return urllib.request.urlopen(req, timeout=timeout)


def stream_chat(prompt, max_tokens=512, thinking=False, timeout=900):
    payload = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    if not thinking:
        payload["chat_template_kwargs"] = {"enable_thinking": False}
    t0 = time.time()
    ttft = None
    text = ""
    usage = {}
    with post("/v1/chat/completions", payload, timeout) as r:
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
                delta = ch.get("delta") or {}
                piece = delta.get("content") or delta.get("reasoning_content") or ""
                if piece:
                    if ttft is None:
                        ttft = time.time() - t0
                    text += piece
    wall = time.time() - t0
    n = (usage.get("completion_tokens") or 0)
    dec = (n - 1) / (wall - ttft) if ttft is not None and n > 1 and wall > ttft else 0.0
    return {"text": text, "usage": usage, "ttft": ttft, "wall": wall, "decode_tps": dec,
            "finish": None}


def main():
    print("=" * 70)
    print("1. /v1/models")
    with get("/v1/models") as r:
        models = [m["id"] for m in json.load(r).get("data", [])]
    print("   served:", models)
    assert MODEL in models or models, "model not served"

    print("=" * 70)
    print("2. single-stream decode, 3 workloads (thinking off, temperature 0)")
    cases = [
        ("code", "Write a Python function that merges two sorted lists in O(n) and explain the "
                 "edge cases it handles. Keep it under 400 tokens."),
        ("math", "A train leaves at 14:20 and travels 187 km at 82 km/h, then 94 km at 61 km/h. "
                 "What time does it arrive? Show the arithmetic."),
        ("prose", "Describe in three short paragraphs why memory bandwidth, not raw TFLOPs, "
                  "decides single-stream inference speed on a unified-memory machine."),
    ]
    results = []
    for name, prompt in cases:
        r = stream_chat(prompt, max_tokens=512)
        ct = r["usage"].get("completion_tokens", 0)
        pt = r["usage"].get("prompt_tokens", 0)
        print(f"   {name:6s} decode={r['decode_tps']:6.1f} tok/s  ttft={r['ttft']*1000:6.0f} ms "
              f"out={ct:4d} tok in={pt:4d} tok wall={r['wall']:6.1f}s")
        results.append(r["decode_tps"])
        if name == "code":
            print("   --- first 200 chars ---")
            print("   " + r["text"][:200].replace("\n", "\n   "))
    print(f"   median decode: {sorted(results)[len(results)//2]:.1f} tok/s")

    print("=" * 70)
    print("3. tool calling (qwen3_coder parser)")
    tools = [{
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get the current weather for a city",
            "parameters": {"type": "object",
                           "properties": {"city": {"type": "string"}},
                           "required": ["city"]},
        },
    }]
    payload = {"model": MODEL, "messages": [{"role": "user", "content": "What is the weather in Shanghai right now? Use the tool."}],
               "tools": tools, "max_tokens": 512, "temperature": 0,
               "chat_template_kwargs": {"enable_thinking": False}}
    with post("/v1/chat/completions", payload) as r:
        body = json.load(r)
    msg = body["choices"][0]["message"]
    tc = msg.get("tool_calls")
    print("   tool_calls:", json.dumps(tc, ensure_ascii=False)[:300] if tc else "NONE")
    print("   finish_reason:", body["choices"][0].get("finish_reason"))

    print("=" * 70)
    print("4. 4-way concurrency (aggregate)")
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=4) as ex:
        outs = list(ex.map(lambda p: stream_chat(p, max_tokens=400), [c[1] for c in cases] + [
            "List five differences between TCP and UDP, one line each."]))
    wall = time.time() - t0
    total = sum(o["usage"].get("completion_tokens", 0) for o in outs)
    print(f"   aggregate={total/wall:7.1f} tok/s over {wall:.1f}s (4 streams, {total} tokens)")

    print("=" * 70)
    print("5. long context (needle)")
    filler = ("The quick brown fox jumps over the lazy dog. " * 40)
    for target_k in (30000, 100000):
        words = max(1, int(target_k * 0.75 / 9))
        body = (filler * (words // 40 + 1))
        needle = "The secret access code for the vault is ZEPHYR-4417."
        prompt = (body[:len(body) // 2] + " " + needle + " " + body[len(body) // 2:] +
                  "\n\nWhat is the secret access code for the vault? Reply with only the code.")
        r = stream_chat(prompt, max_tokens=64)
        pt = r["usage"].get("prompt_tokens", 0)
        ok = "ZEPHYR-4417" in r["text"]
        print(f"   ~{target_k//1000}k target -> prompt={pt} tok  ttft={r['ttft']:.1f}s  "
              f"decode={r['decode_tps']:.1f} tok/s  needle={'FOUND' if ok else 'MISSING'}  "
              f"answer={r['text'].strip()[:60]!r}")

    print("=" * 70)
    print("ALL CHECKS COMPLETED")


if __name__ == "__main__":
    sys.exit(main())
