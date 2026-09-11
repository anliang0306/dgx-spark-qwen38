#!/usr/bin/env bash
# Wait for the image pull to settle, then inspect how the image's huggingface_hub
# decides that a cached file is still valid (this decides whether our pre-seeded
# cache is accepted or re-downloaded).
set -uo pipefail
IMG="lmsysorg/sglang@sha256:9d2a843c706c74bc259c0d9abf360551eb2734e1e7d255ab012a6965f10480b6"

for i in $(seq 1 90); do
  if ! pgrep -f "docker pull $IMG" >/dev/null 2>&1; then break; fi
  sleep 20
done
echo "=== pull settled after $((i*20))s ==="
tail -n 3 "$HOME/dsh-work/pull-image.log"
docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | head -5

echo
echo "=== huggingface_hub inside the image ==="
docker run --rm --entrypoint python3 "$IMG" - <<'PY'
import inspect
import huggingface_hub as h
print("version:", h.__version__)
import huggingface_hub.file_download as fd
for name in ("_metadata_path", "_get_metadata_or_catch_error", "_huggingface_dir"):
    fn = getattr(fd, name, None)
    if fn is not None:
        try:
            print(f"\n--- {name} ---\n{inspect.getsource(fn)}")
        except Exception as e:
            print(f"\n--- {name} (no source: {e}) ---")
PY
