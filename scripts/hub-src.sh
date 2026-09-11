#!/usr/bin/env bash
set -uo pipefail
IMG="lmsysorg/sglang@sha256:9d2a843c706c74bc259c0d9abf360551eb2734e1e7d255ab012a6965f10480b6"
docker run --rm -i --entrypoint python3 "$IMG" - <<'PY'
import inspect
import huggingface_hub as h
print("huggingface_hub:", h.__version__)
import huggingface_hub.file_download as fd
print("\n=== _metadata_path ===")
print(inspect.getsource(fd._metadata_path))
print("\n=== _get_metadata_or_catch_error ===")
print(inspect.getsource(fd._get_metadata_or_catch_error))
PY
echo
echo "=== how a cached file is validated (_hf_hub_download_to_cache_dir head) ==="
docker run --rm -i --entrypoint python3 "$IMG" - <<'PY'
import inspect
import huggingface_hub.file_download as fd
src = inspect.getsource(fd._hf_hub_download_to_cache_dir)
lines = src.splitlines()
for i, l in enumerate(lines):
    if "metadata" in l or "etag" in l.lower() or "local_files_only" in l or "force_download" in l:
        print(f"{i:4d}: {l}")
PY
