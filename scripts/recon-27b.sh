#!/usr/bin/env bash
set -uo pipefail
echo "############ 1. uninstall inventory (read-only) ############"
cd "$HOME/dsh-work/repo" && ./uninstall.sh --list 2>&1 | head -40

echo
echo "############ 2. disk / services ############"
df -h / | tail -1
systemctl is-active qwen38-flash qwen38-keepalive 2>&1 | tr '\n' ' '; echo
docker ps --format '{{.Names}} {{.Status}}' 2>/dev/null
docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' 2>/dev/null

echo
echo "############ 3. checkpoint availability + size ############"
python3 - <<'PY'
import json, urllib.request, urllib.parse

REPOS = [
    ("target   ", "RadixArk/Qwen3.8-27B-NVFP4", "52d1adc5f38aa5ebf099c29ed7025ba34cfbb854"),
    ("target-bf16", "RadixArk/Qwen3.8-27B-NVFP4-BF16-LMHead", None),
    ("draft    ", "z-lab/Qwen3.8-27B-DFlash2", None),
]

def get(url, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": "recon/1.0"})
    return urllib.request.urlopen(req, timeout=timeout).read().decode()

for label, repo, rev in REPOS:
    print(f"--- {label} {repo}")
    # HuggingFace
    try:
        info = json.loads(get(f"https://huggingface.co/api/models/{repo}"))
        sha = info.get("sha", "")
        tree = json.loads(get(f"https://huggingface.co/api/models/{repo}/tree/{sha}?recursive=1"))
        files = [x for x in tree if x.get("type") == "file"]
        tot = sum(x.get("size", 0) for x in files)
        print(f"    HF     : {len(files)} files, {tot/1e9:.2f} GB, sha={sha[:12]}, modified={info.get('lastModified','?')}")
        if rev:
            hit = (sha == rev)
            print(f"    HF pin : requested {rev[:12]} -> {'MATCH' if hit else 'MISMATCH! default sha differs'}")
    except Exception as e:
        print(f"    HF     : ERROR {e}")
    # ModelScope
    for ms in (repo,):
        try:
            d = json.loads(get(f"https://www.modelscope.cn/api/v1/models/{ms}"))
            code = d.get("Code")
            rev_ms = (d.get("Data") or {}).get("Revision", "?")
            print(f"    MS     : Code={code} revision={rev_ms}")
        except Exception as e:
            print(f"    MS     : ERROR {e}")
PY
