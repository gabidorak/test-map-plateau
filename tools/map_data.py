#!/usr/bin/env python3
"""tools/map_data.py: the generated map data lives on a GitHub release, not in git.

The map files (godot/world/ heightmaps, ground meshes and world.json, godot/world/base/, the generated scene and its
meshes: DATA below, ignored by git) weigh ~1.9 GB and change at every map rebuild, which made the git history grow by
gigabytes. They are cut into shards (one per world file, the 21 000 meshes in 32 buckets), each published once per
content as an asset of the "map-data" prerelease (downloads are free and unmetered, unlike Git LFS). map_data.lock,
in git, names the shards' contents a commit uses, so every commit still pins its map exactly.

    python3 tools/map_data.py fetch      after a clone or a pull: download the shards that differ from map_data.lock
                                         (--cache DIR: keep the downloaded shard archives there and take them from
                                         there next time, as CI does with its actions/cache)
    python3 tools/map_data.py status     which shards differ from map_data.lock (exit 1 if any)
    python3 tools/map_data.py publish    after rebuilding the map: upload the changed shards, rewrite map_data.lock
                                         (needs gh, logged in with write access); then commit map_data.lock
    python3 tools/map_data.py prune      delete the assets no map_data.lock in the history uses (--yes to do it)
    python3 tools/map_data.py install-hook   a pre-push hook that refuses to push map edits not published

fetch never overwrites local map edits that were not published (it says so; --force does). Python 3.8+, stdlib only.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import fnmatch
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCK = os.path.join(ROOT, "map_data.lock")
# What was last fetched or published here, per shard: tells a local edit from an old version (ignored by git).
STATE = os.path.join(ROOT, ".map_data_state.json")
REPO = "gabidorak/test-map-plateau"
RELEASE = "map-data"
FORMAT = 1

# The data, as (directory, file patterns, excluded names). Keep in step with .gitignore.
WORLD = "godot/world"
BASE = "godot/world/base"
GENERATED = "godot/scenes/generated"
MESHES = "godot/scenes/generated/meshes"
DATA = [
    (WORLD, ["world.json", "ground*", "heightmap*"], []),
    (BASE, ["*"], [".gdignore"]),
    (GENERATED, ["neighborhood.tscn"], []),
    (MESHES, ["*"], []),
]
MESH_BUCKETS = 32


def shard_of(rel: str) -> str:
    """The shard a data file belongs to: its own for the world files, a bucket of its name for the meshes."""
    d, name = rel.rsplit("/", 1)
    if d == MESHES:
        return "meshes-%02d" % (zlib.crc32(name.encode()) % MESH_BUCKETS)
    if d == WORLD:
        return "world-" + name
    if d == BASE:
        return "base-" + name
    return name


def local_files() -> dict[str, list[str]]:
    """shard -> sorted data files present here (paths relative to ROOT, with /)."""
    shards: dict[str, list[str]] = {}
    for d, patterns, excluded in DATA:
        full = os.path.join(ROOT, d)
        if not os.path.isdir(full):
            continue
        for name in os.listdir(full):
            # dot files are never data (.gdignore, fetch's .part files)
            if name.startswith(".") or name in excluded or not os.path.isfile(os.path.join(full, name)):
                continue
            if any(fnmatch.fnmatchcase(name, p) for p in patterns):
                rel = d + "/" + name
                shards.setdefault(shard_of(rel), []).append(rel)
    for files in shards.values():
        files.sort()
    return shards


def file_sha(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def shard_hash(entries: list[tuple[str, str]]) -> str:
    """A shard's content id: its files' paths and content hashes, sorted (not the archive's bytes)."""
    h = hashlib.sha256()
    for rel, sha in sorted(entries):
        h.update(("%s\0%s\n" % (rel, sha)).encode())
    return h.hexdigest()


def local_hashes(only: set[str] | None = None) -> dict[str, dict]:
    out = {}
    for shard, files in local_files().items():
        if only is not None and shard not in only:
            continue
        entries = [(rel, file_sha(os.path.join(ROOT, rel))) for rel in files]
        out[shard] = {
            "hash": shard_hash(entries),
            "files": len(files),
            "bytes": sum(os.path.getsize(os.path.join(ROOT, rel)) for rel in files),
        }
    return out


def asset_name(shard: str, h: str) -> str:
    return "%s.%s.tar.xz" % (shard, h[:20])


def read_json(path: str, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return default


def write_json(path: str, data) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=1, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


def read_lock() -> dict:
    lock = read_json(LOCK, None)
    if lock is None:
        sys.exit("No map_data.lock: nothing published yet (tools/map_data.py publish)")
    if lock.get("format") != FORMAT:
        sys.exit("map_data.lock has format %r, this script reads %d: pull the newer tools/map_data.py"
                 % (lock.get("format"), FORMAT))
    return lock


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return "%.1f %s" % (n, unit) if unit != "B" else "%d B" % n
        n /= 1024
    return str(n)


def diff(lock: dict, local: dict) -> tuple[list[str], list[str], list[str]]:
    """(shards to download: missing or different here, shards here the lock does not have, shards up to date)."""
    want = lock["shards"]
    differ = sorted(s for s in want if local.get(s, {}).get("hash") != want[s]["hash"])
    extra = sorted(s for s in local if s not in want)
    same = sorted(s for s in want if s not in differ)
    return differ, extra, same


# --- status ------------------------------------------------------------------------------------------------------

def cmd_status(args) -> int:
    lock = read_lock()
    local = local_hashes()
    differ, extra, _ = diff(lock, local)
    state = read_json(STATE, {})
    for s in differ:
        if s not in local:
            print("missing   %s" % s)
        elif state.get(s) == local[s]["hash"]:
            print("outdated  %s (an older version: fetch)" % s)
        else:
            print("modified  %s (not published)" % s)
    for s in extra:
        print("extra     %s (not in map_data.lock)" % s)
    if not differ and not extra:
        if not args.quiet:
            print("Map data matches map_data.lock (%d shards, %s)"
                  % (len(local), human(sum(v["bytes"] for v in local.values()))))
        return 0
    return 1


# --- fetch -------------------------------------------------------------------------------------------------------

ATTEMPTS = 7                    # with the waits below: ~4 min of a stalled download server before giving up (CI build
                                # 66: the release host stalled one runner's downloads for minutes, 4 quick tries failed)


def download(url: str, dest: str) -> None:
    """Downloads url to dest, resuming a cut transfer where it stopped (HTTP Range; a server that ignores it sends the
    whole file again). The content is checked afterwards (unpack), so a bad resume cannot slip through."""
    err = None
    for attempt in range(ATTEMPTS):
        have = os.path.getsize(dest) if os.path.exists(dest) else 0
        headers = {"User-Agent": "plateau-map-data"}
        if have:
            headers["Range"] = "bytes=%d-" % have
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=30) as r:
                with open(dest, "ab" if have and r.status == 206 else "wb") as f:
                    shutil.copyfileobj(r, f, 1 << 20)
            return
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise SystemExit("%s: not found. Was this map version published? (tools/map_data.py publish)" % url)
            if e.code == 416 and os.path.exists(dest):     # the range is past the end: start again from nothing
                os.remove(dest)
            err = e
        except (urllib.error.URLError, OSError) as e:
            err = e
        if attempt + 1 < ATTEMPTS:
            wait = min(5 * 2 ** attempt, 60)
            print("  %s: %s, try %d/%d in %d s" % (os.path.basename(dest), err, attempt + 2, ATTEMPTS, wait),
                  file=sys.stderr, flush=True)
            time.sleep(wait)
    raise SystemExit("%s: %s" % (url, err))


def unpack(archive: str, shard: str, expect: str) -> dict[str, bytes]:
    """The shard's files (rel path -> bytes), checked against its content id."""
    files: dict[str, bytes] = {}
    with tarfile.open(archive, "r:xz") as tar:
        for m in tar:
            if not m.isfile():
                continue
            rel = m.name
            if rel.startswith("/") or ".." in rel.split("/") or shard_of(rel) != shard:
                raise SystemExit("%s: unexpected member %r" % (archive, rel))
            files[rel] = tar.extractfile(m).read()
    got = shard_hash([(rel, hashlib.sha256(b).hexdigest()) for rel, b in files.items()])
    if got != expect:
        raise SystemExit("%s: content %s, map_data.lock says %s" % (archive, got[:12], expect[:12]))
    return files


def cmd_fetch(args) -> int:
    lock = read_lock()
    only = set(args.only) if args.only else None
    if only:
        unknown = only - set(lock["shards"])
        if unknown:
            sys.exit("Not in map_data.lock: %s" % ", ".join(sorted(unknown)))
    local = local_hashes(only)
    differ, extra, _ = diff({"shards": {s: v for s, v in lock["shards"].items() if only is None or s in only}}, local)
    state = read_json(STATE, {})
    # A shard that is neither the lock's version nor the one last synced here was edited here: never thrown away.
    edited = [s for s in differ + extra if s in local and state.get(s) != local[s]["hash"]]
    if edited and not args.force:
        print("Local map edits, not published (publish them, or fetch --force to throw them away):")
        for s in edited:
            print("  " + s)
        return 1
    total = sum(lock["shards"][s]["bytes"] for s in differ)
    if differ:
        print("Downloading %d shard(s), %s of map data" % (len(differ), human(total)))
    cache = args.cache
    if cache:
        os.makedirs(cache, exist_ok=True)
    def get(s: str) -> tuple[dict[str, bytes], float, bool]:
        t = time.time()
        info = lock["shards"][s]
        if cache:
            # an asset's name holds its content id, so a cached archive is that content or unreadable (then fetched)
            path = os.path.join(cache, info["asset"])
            if os.path.exists(path):
                try:
                    return unpack(path, s, info["hash"]), time.time() - t, True
                except (SystemExit, Exception) as e:       # wrong content, or a cut or corrupt archive
                    print("  %s: cached archive unusable (%s), downloading it" % (info["asset"], e), file=sys.stderr)
                    os.remove(path)
            part = os.path.join(cache, "." + info["asset"] + ".part")
        else:
            part = path = os.path.join(tmp, info["asset"])
        url = "https://github.com/%s/releases/download/%s/%s" % (
            lock.get("repo", REPO), lock.get("release", RELEASE), info["asset"])
        download(url, part)
        files = unpack(part, s, info["hash"])
        if cache:
            os.replace(part, path)
        else:
            os.remove(part)
        return files, time.time() - t, False

    # a few downloads at once (one stream rarely fills the line); the files are written here, one shard at a time
    with tempfile.TemporaryDirectory(prefix="map_data_") as tmp, \
            concurrent.futures.ThreadPoolExecutor(4) as pool:
        jobs = {pool.submit(get, s): s for s in sorted(differ, key=lambda s: -lock["shards"][s]["bytes"])}
        for i, job in enumerate(concurrent.futures.as_completed(jobs), 1):
            s = jobs[job]
            info = lock["shards"][s]
            files, secs, cached = job.result()
            for rel in local_files().get(s, []):
                if rel not in files:
                    os.remove(os.path.join(ROOT, rel))
            for rel, data in files.items():
                dest = os.path.join(ROOT, rel)
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                part = os.path.join(os.path.dirname(dest), "." + os.path.basename(dest) + ".part")  # not data
                with open(part, "wb") as f:
                    f.write(data)
                os.replace(part, dest)
            state[s] = info["hash"]
            write_json(STATE, state)
            print("  [%d/%d] %-28s %9s  %.1fs%s" % (i, len(differ), s, human(info["bytes"]), secs,
                                                    "  (cache)" if cached else ""))
    for s in extra:
        for rel in local_files().get(s, []):
            os.remove(os.path.join(ROOT, rel))
        state.pop(s, None)
        print("  removed %s (not in map_data.lock)" % s)
    write_json(STATE, state)
    if cache and only is None:
        # the archives of other map versions go (a cache restored from an older lock would otherwise grow forever)
        keep = {v["asset"] for v in lock["shards"].values()}
        for name in os.listdir(cache):
            if name not in keep:
                os.remove(os.path.join(cache, name))
    if not differ and not extra:
        print("Map data already matches map_data.lock")
    return 0


# --- publish -----------------------------------------------------------------------------------------------------

def gh(*argv: str, capture: bool = True) -> str:
    try:
        r = subprocess.run(["gh", *argv], cwd=ROOT, check=True, text=True,
                           stdout=subprocess.PIPE if capture else None)
    except FileNotFoundError:
        sys.exit("publish needs the GitHub CLI (gh), logged in with write access to %s" % REPO)
    except subprocess.CalledProcessError as e:
        sys.exit("gh %s failed (%d)" % (" ".join(argv[:3]), e.returncode))
    return r.stdout if capture else ""


def release_assets() -> set[str] | None:
    """The release's asset names, None if there is no such release yet."""
    try:
        r = subprocess.run(["gh", "release", "view", RELEASE, "-R", REPO, "--json", "assets",
                            "--jq", ".assets[].name"], cwd=ROOT, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError:
        sys.exit("This needs the GitHub CLI (gh), logged in with write access to %s" % REPO)
    if r.returncode != 0:
        if "not found" in r.stderr.lower():
            return None
        sys.exit("gh release view %s: %s" % (RELEASE, r.stderr.strip()))
    return set(r.stdout.split())


def pack(shard: str, files: list[str], dest: str) -> float:
    t = time.time()
    with tarfile.open(dest, "w:xz", preset=6) as tar:
        for rel in files:
            with open(os.path.join(ROOT, rel), "rb") as f:
                data = f.read()
            info = tarfile.TarInfo(rel)
            info.size = len(data)
            info.mode = 0o644
            info.mtime = 0
            tar.addfile(info, io.BytesIO(data))
    return time.time() - t


def cmd_publish(args) -> int:
    local = local_hashes()
    if not local:
        sys.exit("No map data here to publish")
    files = local_files()
    have = release_assets()
    if have is None:
        # a prerelease: the updater's "latest release" never sees it
        gh("release", "create", RELEASE, "-R", REPO, "--prerelease", "--title", "Map data",
           "--notes", "The generated map files, in shards named by content (tools/map_data.py, map_data.lock). "
                      "Not a build.")
        have = set()
    shards = {}
    todo = []
    for s, v in sorted(local.items()):
        name = asset_name(s, v["hash"])
        shards[s] = dict(v, asset=name)
        if name not in have:
            todo.append(s)
    if todo:
        print("Uploading %d shard(s), %s of map data" % (len(todo), human(sum(local[s]["bytes"] for s in todo))))
    with tempfile.TemporaryDirectory(prefix="map_data_") as tmp:
        # xz is slow to write (~3 MB/s on the heightmaps) but small and in every Python: the shards pack in parallel,
        # biggest first, and go up in batches as they are ready
        todo.sort(key=lambda s: -local[s]["bytes"])
        workers = max(1, min(len(todo), (os.cpu_count() or 2) - 1, 8))
        with concurrent.futures.ProcessPoolExecutor(workers) as pool:
            jobs = {pool.submit(pack, s, files[s], os.path.join(tmp, shards[s]["asset"])): s for s in todo}
            batch: list[str] = []
            for i, job in enumerate(concurrent.futures.as_completed(jobs), 1):
                s = jobs[job]
                path = os.path.join(tmp, shards[s]["asset"])
                secs = job.result()
                print("  [%d/%d] %-28s %9s -> %9s  %.1fs" % (i, len(todo), s, human(local[s]["bytes"]),
                                                           human(os.path.getsize(path)), secs))
                batch.append(path)
                if len(batch) == 8 or i == len(todo):
                    gh("release", "upload", RELEASE, "-R", REPO, "--clobber", *batch, capture=False)
                    for p in batch:
                        os.remove(p)
                    batch = []
    lock = {"format": FORMAT, "repo": REPO, "release": RELEASE, "shards": shards}
    old = read_json(LOCK, None)
    write_json(LOCK, lock)
    write_json(STATE, {s: v["hash"] for s, v in local.items()})
    if old == lock:
        print("Nothing new: map_data.lock unchanged")
    else:
        print("map_data.lock updated: commit it with the code that goes with this map")
    return 0


# --- prune -------------------------------------------------------------------------------------------------------

def cmd_prune(args) -> int:
    used: set[str] = set()
    lock = read_json(LOCK, None)
    if lock:
        used |= {v["asset"] for v in lock["shards"].values()}
    revs = subprocess.run(["git", "log", "--all", "--format=%H", "--", "map_data.lock"], cwd=ROOT, check=True,
                          text=True, stdout=subprocess.PIPE).stdout.split()
    for rev in revs:
        r = subprocess.run(["git", "show", "%s:map_data.lock" % rev], cwd=ROOT, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if r.returncode == 0:
            used |= {v["asset"] for v in json.loads(r.stdout)["shards"].values()}
    unused = sorted((release_assets() or set()) - used)
    if not unused:
        print("Every asset is used by a map_data.lock in the history")
        return 0
    for name in unused:
        print(("deleting " if args.yes else "unused   ") + name)
        if args.yes:
            gh("release", "delete-asset", RELEASE, name, "-R", REPO, "--yes")
    if not args.yes:
        print("%d unused asset(s): --yes deletes them (commits whose map_data.lock uses none of them are not "
              "affected; local branches not pushed are counted too)" % len(unused))
    return 0


# --- install-hook ------------------------------------------------------------------------------------------------

HOOK = """#!/bin/sh
# tools/map_data.py install-hook: no push of map edits that were not published (git push --no-verify skips it).
python3 tools/map_data.py check-push || exit 1
"""


def cmd_check_push(args) -> int:
    if not os.path.exists(LOCK):
        return 0
    lock = read_lock()
    local = local_hashes()
    differ, extra, _ = diff(lock, local)
    state = read_json(STATE, {})
    # missing shards or ones last fetched (an older version) are not edits: only shards changed here block the push
    edited = [s for s in differ + extra if s in local and state.get(s) != local[s]["hash"]]
    if not edited:
        return 0
    print("Map data edited here but not published: %s" % ", ".join(edited))
    print("Run python3 tools/map_data.py publish and commit map_data.lock (git push --no-verify skips this check)")
    return 1


def cmd_install_hook(args) -> int:
    hooks = subprocess.run(["git", "rev-parse", "--git-path", "hooks"], cwd=ROOT, check=True, text=True,
                           stdout=subprocess.PIPE).stdout.strip()
    path = os.path.join(ROOT, hooks, "pre-push")
    if os.path.exists(path) and "map_data.py" not in open(path, encoding="utf-8").read():
        sys.exit("%s exists: add the line 'python3 tools/map_data.py check-push || exit 1' to it" % path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(HOOK)
    os.chmod(path, 0o755)
    print("Installed %s" % path)
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("status")
    s.add_argument("-q", "--quiet", action="store_true")
    s = sub.add_parser("fetch")
    s.add_argument("--force", action="store_true", help="overwrite local map edits that were not published")
    s.add_argument("--only", nargs="+", metavar="SHARD", help="only these shards (names as in map_data.lock)")
    s.add_argument("--cache", metavar="DIR", help="keep the shard archives in DIR, and take them from there")
    sub.add_parser("publish")
    s = sub.add_parser("prune")
    s.add_argument("--yes", action="store_true")
    sub.add_parser("install-hook")
    sub.add_parser("check-push")
    args = p.parse_args()
    return {"status": cmd_status, "fetch": cmd_fetch, "publish": cmd_publish, "prune": cmd_prune,
            "install-hook": cmd_install_hook, "check-push": cmd_check_push}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
