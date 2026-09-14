#!/usr/bin/env python3
"""Reproduce CONTEXT_WINDOW_EXCEEDED against the DGX endpoint and measure the
Chinese token ratio, so the diagnosis rests on data instead of a guess."""
import json
import os
import sys
import time
import urllib.error
import urllib.request

# Point these at your own deployment; no credentials live in this file.
BASE = os.environ.get("DGX_BASE", "http://<DGX_HOST>:30000/v1")
KEY = os.environ.get("DGX_API_KEY") or sys.exit("set DGX_API_KEY")


def post(payload, timeout=900):
    req = urllib.request.Request(
        BASE + "/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"},
        method="POST")
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode()), time.time() - t0
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        return e.code, raw, time.time() - t0
    except Exception as e:
        return None, f"{type(e).__name__}: {e}", time.time() - t0


def chat(content, max_tokens=8):
    return post({"model": "qwen3.8-27b",
                 "messages": [{"role": "user", "content": content}],
                 "max_tokens": max_tokens, "temperature": 0,
                 "chat_template_kwargs": {"enable_thinking": False}})


print("=" * 72)
print("测试 1：中文的 token/字符 比率（检验 DSH 是否可能低估）")
sample_cn = "这是一个用于测量分词比例的中文样本，包含标点、数字 12345 和英文 mixed words。" * 20
st, body, el = chat(sample_cn)
if st == 200:
    pt = body["usage"]["prompt_tokens"]
    print(f"  字符数={len(sample_cn)}  prompt_tokens={pt}  ->  {len(sample_cn)/pt:.2f} 字符/token")
    print(f"  （若按 chars/4 估算会得到 {len(sample_cn)//4} tokens，实际 {pt}，"
          f"低估倍数 {pt/max(1,len(sample_cn)//4):.1f}x）")
else:
    print(f"  status={st} body={str(body)[:200]}")

print()
print("测试 2：超过 262144 上下文的长 prompt（复现 CONTEXT_WINDOW_EXCEEDED）")
# ~300k tokens of English filler, sent as one user message
filler = "the quick brown fox jumps over the lazy dog. " * 20000   # ~900k chars
st, body, el = chat(filler, max_tokens=8)
print(f"  status={st}  耗时={el:.1f}s")
if st == 200:
    print(f"  ✅ 竟然成功 prompt_tokens={body['usage']['prompt_tokens']}")
else:
    print(f"  ❌ 失败: {str(body)[:600]}")

print()
print("测试 3：刚好在边界内的长 prompt（约 200k tokens），确认不是普遍故障")
filler2 = "the quick brown fox jumps over the lazy dog. " * 13000   # ~585k chars
st, body, el = chat(filler2, max_tokens=8)
print(f"  status={st}  耗时={el:.1f}s")
if st == 200:
    print(f"  ✅ 成功 prompt_tokens={body['usage']['prompt_tokens']}")
else:
    print(f"  ❌ 失败: {str(body)[:400]}")
