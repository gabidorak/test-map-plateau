#!/usr/bin/env python3
"""tools/pck_tool.py: Godot pack helpers for the delta updates (.github/workflows/build.yml, scripts/delta.gd).

    pck_tool.py list <pck or exe>                       files of a pack (or of the pack embedded in an executable)
    pck_tool.py content-id <pck>                        the data id: what the game's files are, not how they are laid out
    pck_tool.py launcher-id <godot dir> <godot version> the launcher id: what goes into the packed executables' boot pack
    pck_tool.py unpack-exe <exe> <out.pck>              the game pack carried by a packed executable (pack/*.zst chunks)
    pck_tool.py launcher <full exe> <thin exe> <out>    the launcher delta of a thin executable (format in scripts/delta.gd)
    pck_tool.py chain-add <chain.json> <patch.pck> <out dir> <from id> <to id> <run> <tag> [keep]
                                                            compresses a patch into <out dir> and adds it to the store's
                                                            chain, prints the patch files it drops

Pack format v4 (Godot 4.7): 112-byte header (flags bit 2: offsets relative to file_base), files aligned to 16 bytes,
directory at the end: per file path length, path, offset, size, md5, flags (2: removed by a patch, 4: delta-encoded).
An executable with an embedded pack ends with its size and "GDPC". Needs zstd (the command) for unpack-exe and chain-add.
"""
import hashlib
import json
import os
import re
import struct
import subprocess
import sys

BLOCK = 1 << 16                                 # launcher delta: the template part goes by 64 KB blocks
REMOVED = 2


def read(path):
    with open(path, "rb") as f:
        return f.read()


def embedded_pack(data):
    """(start, end) of the pack inside `data`: the whole file for a .pck, the embedded part of an executable."""
    if data[:4] == b"GDPC":
        return 0, len(data)
    if data[-4:] == b"GDPC":
        size, = struct.unpack_from("<Q", data, len(data) - 12)
        start = len(data) - 12 - size
        if start >= 0 and data[start:start + 4] == b"GDPC":
            return start, len(data) - 12
    raise ValueError("no Godot pack found")


def pack_files(data, start=0):
    """[(absolute offset, size, path, md5 hex, flags)] of the pack at `start`, in directory order."""
    magic, version, major, minor, patch, flags = struct.unpack_from("<4sIIIII", data, start)
    if magic != b"GDPC" or version != 4:
        raise ValueError("not a pack of format 4")
    file_base, dir_offset = struct.unpack_from("<QQ", data, start + 24)
    base = start + file_base if flags & 2 else file_base
    pos = start + dir_offset
    count, = struct.unpack_from("<I", data, pos)
    pos += 4
    files = []
    for _ in range(count):
        n, = struct.unpack_from("<I", data, pos)
        path = data[pos + 4:pos + 4 + n].rstrip(b"\0").decode()
        pos += 4 + n
        offset, size = struct.unpack_from("<QQ", data, pos)
        md5 = data[pos + 16:pos + 32].hex()
        fflags, = struct.unpack_from("<I", data, pos + 32)
        pos += 36
        files.append((base + offset, size, path, md5, fflags))
    return files


def content_id(data):
    """sha256 (16 hex digits) of the sorted "path md5" lines of a full pack; scripts/delta.gd computes the same."""
    lines = sorted("%s %s\n" % (path, md5) for _, _, path, md5, flags in pack_files(data) if not flags & REMOVED)
    return hashlib.sha256("".join(lines).encode()).hexdigest()[:16]


def launcher_id(godot_dir, version):
    """Hash of the Godot version and of the sources of the packed executables' boot pack: the "Packed" presets'
    export_files, project.godot and export_presets.cfg. Same id = same boot pack, so a data update fits the executable."""
    presets = open(os.path.join(godot_dir, "export_presets.cfg"), encoding="utf-8").read()
    files = set()
    for line in re.findall(r'^export_files=PackedStringArray\((.*)\)$', presets, re.M):
        files.update(p[len("res://"):] for p in re.findall(r'"([^"]+)"', line))
    h = hashlib.sha256(version.encode() + b"\n")
    for rel in sorted(files | {"project.godot", "export_presets.cfg"}):
        h.update(rel.encode() + b"\n" + read(os.path.join(godot_dir, rel)) + b"\n")
    return h.hexdigest()[:16]


def unpack_exe(exe, out):
    """Writes the game pack of a packed executable: its pack/manifest.json chunks, decompressed one after the other."""
    data = read(exe)
    start, _ = embedded_pack(data)
    files = {path: (offset, size) for offset, size, path, _, _ in pack_files(data, start)}
    o, n = files["pack/manifest.json"]
    manifest = json.loads(data[o:o + n])
    with open(out + ".part", "wb") as f:
        for chunk in manifest["chunks"]:
            o, n = files["pack/" + chunk["file"]]
            plain = subprocess.run(["zstd", "-d", "-q", "--long=27", "-c"], input=data[o:o + n], capture_output=True,
                    check=True).stdout
            if len(plain) != chunk["size"]:
                raise ValueError("damaged chunk " + chunk["file"])
            f.write(plain)
    if os.path.getsize(out + ".part") != manifest["size"]:
        raise ValueError("unpacked size mismatch")
    os.replace(out + ".part", out)
    return manifest


def launcher_delta(full, thin, out):
    """The thin executable as: the hashes of its template blocks (the bytes before its pack), the blocks that differ
    from the full executable of the same build (headers that hold the pack's size: they differ in any other build too),
    and everything from the pack on. A client keeps its own blocks where the hashes match (scripts/delta.gd)."""
    a, b = read(full), read(thin)
    template, _ = embedded_pack(b)
    count = (template + BLOCK - 1) // BLOCK
    ship = [i for i in range(count) if i in (0, count - 1) or a[i * BLOCK:(i + 1) * BLOCK] != b[i * BLOCK:(i + 1) * BLOCK]]
    header = {
        "size": len(b), "sha256": hashlib.sha256(b).hexdigest(), "block": BLOCK, "template": template,
        "hashes": [hashlib.sha256(b[i * BLOCK:min((i + 1) * BLOCK, template)]).hexdigest()[:32] for i in range(count)],
        "ship": ship,
    }
    head = json.dumps(header, separators=(",", ":")).encode()
    with open(out, "wb") as f:
        f.write(struct.pack("<I", len(head)) + head)
        for i in ship:
            f.write(b[i * BLOCK:min((i + 1) * BLOCK, template)])
        f.write(b[template:])
    return len(ship), os.path.getsize(out)


def chain_add(chain_path, patch, out_dir, from_id, to_id, run, tag, keep=60):
    """Compresses a patch pack (from_id -> to_id) to <out_dir>/patch-<run>.pck.zst and adds it to the chain; keeps the
    `keep` newest patches, returns the files of the dropped ones (to delete from the store)."""
    chain = json.loads(read(chain_path)) if os.path.exists(chain_path) else {"patches": []}
    raw = read(patch)
    name = "patch-%d.pck.zst" % run
    blob = subprocess.run(["zstd", "-q", "-19", "-c"], input=raw, capture_output=True, check=True).stdout
    with open(os.path.join(out_dir, name), "wb") as f:
        f.write(blob)
    chain["patches"] = [p for p in chain["patches"] if p["run"] != run] + [{
        "from": from_id, "to": to_id, "run": run, "tag": tag, "file": name, "size": len(blob), "raw": len(raw),
        "sha256": hashlib.sha256(blob).hexdigest()}]
    chain["patches"].sort(key=lambda p: p["run"])
    dropped = [p["file"] for p in chain["patches"][:-keep]]
    chain["patches"] = chain["patches"][-keep:]
    with open(chain_path, "w") as f:
        json.dump(chain, f, indent=1)
    return dropped


def main(argv):
    if len(argv) == 2 and argv[0] == "list":
        data = read(argv[1])
        for offset, size, path, md5, flags in sorted(pack_files(data, embedded_pack(data)[0])):
            print("%12d %10d %s %d %s" % (offset, size, md5, flags, path))
    elif len(argv) == 2 and argv[0] == "content-id":
        print(content_id(read(argv[1])))
    elif len(argv) == 3 and argv[0] == "launcher-id":
        print(launcher_id(argv[1], argv[2]))
    elif len(argv) == 3 and argv[0] == "unpack-exe":
        manifest = unpack_exe(argv[1], argv[2])
        print("unpacked %s (%s, %d bytes)" % (argv[2], manifest.get("tag", "?"), manifest["size"]))
    elif len(argv) == 4 and argv[0] == "launcher":
        shipped, size = launcher_delta(argv[1], argv[2], argv[3])
        print("launcher delta: %d template blocks shipped, %d bytes" % (shipped, size))
    elif len(argv) in (8, 9) and argv[0] == "chain-add":
        for name in chain_add(argv[1], argv[2], argv[3], argv[4], argv[5], int(argv[6]), argv[7],
                int(argv[8]) if len(argv) == 9 else 60):
            print(name)
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
