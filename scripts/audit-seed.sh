#!/usr/bin/env bash
set -uo pipefail
echo "=== runner log (full) ==="
cat "$HOME/dsh-work/seed-27b-runner.log"

echo
echo "=== target log tail ==="
tail -6 "$HOME/dsh-work/seed-27b-target.log"
echo
echo "=== draft log tail ==="
tail -4 "$HOME/dsh-work/seed-27b-draft.log"

echo
echo "=== exact per-file audit against the pinned HF trees ==="
python3 - <<'PY'
import json, os, urllib.request

JOBS = [
    ("target", "RadixArk/Qwen3.8-27B-NVFP4", "52d1adc5f38aa5ebf099c29ed7025ba34cfbb854"),
    ("draft ", "z-lab/Qwen3.8-27B-DFlash2",   "50307d4c4cde6860d4eee73e2547cd786fe8e8a4"),
]
HF = os.path.expanduser("~/.cache/huggingface/hub")

def get(u):
    return urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": "audit/1.0"}), timeout=60).read().decode()

for label, repo, rev in JOBS:
    tree = [x for x in json.loads(get(f"https://huggingface.co/api/models/{repo}/tree/{rev}?recursive=1"))
            if x.get("type") == "file"]
    snap = os.path.join(HF, "models--" + repo.replace("/", "--"), "snapshots", rev)
    ok = missing = broken = wrongsize = 0
    problems = []
    for f in tree:
        p = os.path.join(snap, f["path"])
        if not os.path.lexists(p):
            missing += 1; problems.append(("MISSING", f["path"], f["size"]))
        elif not os.path.exists(p):
            broken += 1; problems.append(("BROKEN-LINK", f["path"], f["size"]))
        else:
            sz = os.path.getsize(p)
            if sz != f["size"]:
                wrongsize += 1; problems.append((f"WRONG-SIZE {sz}", f["path"], f["size"]))
            else:
                ok += 1
    print(f"{label} {repo}")
    print(f"        expected={len(tree)}  ok={ok}  missing={missing}  broken={broken}  wrongsize={wrongsize}")
    for kind, path, size in problems:
        print(f"        {kind:14s} {path}  (expected {size} bytes)")
PY

echo
echo "=== blobs present ==="
du -sh "$HOME"/.cache/huggingface/hub/models--*/blobs 2>/dev/null
ls "$HOME"/.cache/huggingface/hub/models--RadixArk--Qwen3.8-27B-NVFP4/blobs | wc -l
ls "$HOME"/.cache/huggingface/hub/models--z-lab--Qwen3.8-27B-DFlash2/blobs | wc -l
echo "stray .part files: $(find "$HOME"/.cache/huggingface -name '*.part-*' 2>/dev/null | wc -l)"
find "$HOME"/.cache/huggingface -name '*.part-*' 2>/dev/null | head -5
