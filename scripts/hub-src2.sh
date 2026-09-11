#!/usr/bin/env bash
set -uo pipefail
IMG="lmsysorg/sglang@sha256:9d2a843c706c74bc259c0d9abf360551eb2734e1e7d255ab012a6965f10480b6"
docker run --rm -i --entrypoint python3 "$IMG" - <<'PY'
import inspect
import huggingface_hub.file_download as fd
src = inspect.getsource(fd._hf_hub_download_to_cache_dir).splitlines()
print("=== lines 125-215 ===")
for i in range(124, min(215, len(src))):
    print(f"{i+1:4d}: {src[i]}")
print()
print("=== helper names containing 'metadata' or 'cache' ===")
for name in dir(fd):
    if "metadata" in name.lower() or "cache" in name.lower():
        print("  ", name)
PY
