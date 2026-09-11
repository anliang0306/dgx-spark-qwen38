#!/usr/bin/env python3
"""
Seed the HuggingFace cache for a pinned repo revision using ModelScope as the
transport, verifying every byte against the HuggingFace LFS sha256 / git blob sha1.

Why: HF direct and hf-mirror both measured ~12.5 MB/s from this host (135 GB -> ~3 h),
ModelScope measured 44 MB/s+ on the same box for the same checkpoint. Every file is
hash-verified before it is admitted, so the transport cannot change what we serve.

Re-runnable: completed blobs are skipped.
"""
import hashlib
import json
import os
import queue
import sys
import threading
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

REPO = "RadixArk/Qwen3.8-Flash-Next-NVFP4"
REV = "7b719225242aacd3dbd3f9407468c2ee9a9d2594"
HF_CACHE = os.path.expanduser(os.environ.get("HF_CACHE", "~/.cache/huggingface"))
CACHE = os.path.join(HF_CACHE, "hub", "models--" + REPO.replace("/", "--"))
BLOBS = os.path.join(CACHE, "blobs")
SNAP = os.path.join(CACHE, "snapshots", REV)
WORK = os.path.expanduser("~/dsh-work")
STATUS = os.path.join(WORK, "seed-status.json")
LOG = os.path.join(WORK, "seed.log")
WORKERS = int(os.environ.get("SEED_WORKERS", "12"))
UA = "Mozilla/5.0 (X11; Linux aarch64) hf-seeder/1.0"

_ms = "https://www.modelscope.cn/api/v1/models/{repo}/repo?Revision=master&FilePath={path}"
_hf = "https://huggingface.co/{repo}/resolve/{rev}/{path}"

_lock = threading.Lock()
_log_lock = threading.Lock()
state = {"done": 0, "total": 0, "bytes_done": 0, "bytes_total": 0,
         "failed": [], "active": {}, "started": time.time(), "recent": []}


def log(msg):
    line = time.strftime("[%H:%M:%S] ") + msg
    with _log_lock:
        print(line, flush=True)
        with open(LOG, "a") as f:
            f.write(line + "\n")


def http_get(url, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    return urllib.request.urlopen(req, timeout=timeout)


def fetch_tree():
    url = f"https://huggingface.co/api/models/{REPO}/tree/{REV}?recursive=1"
    with http_get(url, 90) as r:
        return json.loads(r.read().decode())


def verify(path, kind, etag):
    h256 = hashlib.sha256()
    hgit = hashlib.sha1()
    size = 0
    if kind == "git":
        hgit.update(b"blob %d\0" % os.path.getsize(path))
    with open(path, "rb") as f:
        while True:
            chunk = f.read(8 << 20)
            if not chunk:
                break
            size += len(chunk)
            h256.update(chunk)
            if kind == "git":
                hgit.update(chunk)
    got = h256.hexdigest() if kind == "lfs" else hgit.hexdigest()
    return got == etag, size


def download_one(entry):
    path = entry["path"]
    size = entry["size"]
    if "lfs" in entry:
        etag, kind = entry["lfs"]["oid"], "lfs"
    else:
        etag, kind = entry["oid"], "git"
    blob = os.path.join(BLOBS, etag)
    meta = blob + ".metadata"

    if os.path.exists(blob) and os.path.getsize(blob) == size:
        ok, _ = verify(blob, kind, etag)
        if ok:
            if not os.path.exists(meta):
                write_metadata(meta, etag, path, size)
            return path, size, "cached"

    part = blob + f".part-{os.getpid()}-{threading.get_ident()}"
    sources = [("modelscope", _ms.format(repo=REPO, path=urllib.parse.quote(path))),
               ("huggingface", _hf.format(repo=REPO, rev=REV, path=path))]
    errors = []
    for name, src in sources:
        try:
            with http_get(src, 60) as r, open(part, "wb") as f:
                while True:
                    chunk = r.read(4 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
        except Exception as e:  # noqa: BLE001
            errors.append(f"{name}: {e}")
            if os.path.exists(part):
                os.unlink(part)
            continue
        ok, got_size = verify(part, kind, etag)
        if ok and got_size == size:
            os.replace(part, blob)
            write_metadata(meta, etag, path, size)
            return path, size, ("new" if name == "modelscope" else "new-hf")
        errors.append(f"{name}: hash/size mismatch (size {got_size} vs {size})")
        if os.path.exists(part):
            os.unlink(part)
    raise RuntimeError(f"{path}: " + " | ".join(errors))


def write_metadata(meta_path, etag, relpath, size):
    tmp = meta_path + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"commit_hash": REV, "etag": etag, "location": relpath, "size": size}, f)
    os.replace(tmp, meta_path)


def worker(entry, q):
    t0 = time.time()
    try:
        path, size, how = download_one(entry)
        with _lock:
            state["done"] += 1
            state["bytes_done"] += size
            state["active"].pop(entry["path"], None)
            state["recent"].append({"path": path, "mb": round(size / 1e6, 1),
                                    "s": round(time.time() - t0, 1), "how": how})
            state["recent"] = state["recent"][-8:]
        if how == "new":
            log(f"OK  {size/1e9:7.2f} GB {time.time()-t0:7.1f}s  {path}")
    except Exception as e:  # noqa: BLE001
        with _lock:
            state["failed"].append({"path": entry["path"], "error": str(e)})
            state["active"].pop(entry["path"], None)
        log(f"FAIL {entry['path']}: {e}")
    finally:
        q.get()
        q.task_done()


def reporter():
    while True:
        time.sleep(20)
        with _lock:
            done, total = state["done"], state["total"]
            bd, bt = state["bytes_done"], state["bytes_total"]
            failed = len(state["failed"])
            el = time.time() - state["started"]
            rate = bd / el / 1e6 if el > 0 else 0
            eta = (bt - bd) / (bd / el) if bd and el else 0
            snap = dict(state)
        snap.update({"elapsed_s": int(el), "mbps": round(rate, 1), "eta_s": int(eta)})
        tmp = STATUS + ".tmp"
        with open(tmp, "w") as f:
            json.dump(snap, f)
        os.replace(tmp, STATUS)
        log(f"progress {done}/{total} files  {bd/1e9:.1f}/{bt/1e9:.1f} GB  "
            f"{rate:.1f} MB/s  eta {eta/60:.0f} min  failed={failed}")


def main():
    os.makedirs(BLOBS, exist_ok=True)
    os.makedirs(SNAP, exist_ok=True)
    entries = [x for x in fetch_tree() if x.get("type") == "file"]
    entries.sort(key=lambda x: -x.get("size", 0))
    with _lock:
        state["total"] = len(entries)
        state["bytes_total"] = sum(e.get("size", 0) for e in entries)
    log(f"seeding {REPO} @ {REV}: {len(entries)} files, "
        f"{state['bytes_total']/1e9:.1f} GB, {WORKERS} workers")

    threading.Thread(target=reporter, daemon=True).start()

    q = queue.Queue(WORKERS * 2)
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for e in entries:
            with _lock:
                state["active"][e["path"]] = True
            q.put(1)
            ex.submit(worker, e, q)
        ex.shutdown(wait=True)

    # snapshot symlinks + ref
    missing = []
    for e in entries:
        etag = e["lfs"]["oid"] if "lfs" in e else e["oid"]
        blob = os.path.join(BLOBS, etag)
        if not os.path.exists(blob) or os.path.getsize(blob) != e["size"]:
            missing.append(e["path"])
            continue
        target = os.path.join(SNAP, e["path"])
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if os.path.islink(target) or os.path.exists(target):
            os.unlink(target)
        os.symlink(os.path.join("..", "..", "blobs", etag), target)
    os.makedirs(os.path.join(CACHE, "refs"), exist_ok=True)
    with open(os.path.join(CACHE, "refs", "main"), "w") as f:
        f.write(REV)
    with _lock:
        failed = list(state["failed"])
    log(f"snapshot written: {SNAP}")
    if missing:
        log(f"NOT LINKED (missing/incomplete blobs): {len(missing)} -> {missing[:5]}")
    if failed or missing:
        log(f"DONE WITH FAILURES: {len(failed)} download errors, {len(missing)} missing files")
        sys.exit(1)
    log("DONE: all files verified")


if __name__ == "__main__":
    main()
