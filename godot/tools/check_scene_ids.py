#!/usr/bin/env python3
"""tools/check_scene_ids.py: CI guard for the delta updates (scripts/delta.gd, .github/workflows/build.yml).

    check_scene_ids.py [--export] <godot dir>          every .tscn node has a unique_id; --export also exports the
                                                       project twice and checks each scene exports the same bytes
    check_scene_ids.py --patch <game.pck> <patch.pck>  this build's pack and the patch carry the same scenes

Godot's text-to-binary export gives every node a unique_id: the one its .tscn gives, or a random one the packer draws
at each export (SceneState::_parse_node -> ResourceUID::create_id) when the node has none -- and editor-saved scenes
carry ids, hand-written ones often do not. That is what broke build 46: scenes/loading.tscn's node had no id, so the
second export (the one --export-patch makes, "Data patch" in the workflow) converted it to different bytes than the
shipped game.pck. verify_patch.gd rightly refused to publish that patch, and every player had to download the whole
428 MB file. A unique_id also keeps the export small: the id is written once per node path and the packer draws a new
one for each export when the scene has none.

--export runs two exports of the project (the "Linux" preset) and compares each scene's converted file (.scn, or the
.res of a non-scene resource) with the first export's, then with the pack the first one wrote: exactly what the job's
"Data patch" does further down (--export-patch is a second export). The cache of conversions is cleared before each
export, since it hides the problem. It is for a job of its own, where exporting the project twice costs nothing but
the Linux data; run in an export job, it would break the other presets' cache of the project's imports. --patch
compares the generated files the game pack and the patch carry (path and md5): what a player's data + patch merge
into. A .tscn saved with properties=true is not converted (it exports its own text): it has nothing to check.
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # works under python3 -I too (-I leaves it out)
import pck_tool                                                   # noqa: E402

ANSI = re.compile(r"\x1b\[[0-9;]*m")
CONVERTED = re.compile(r"^export-[0-9a-f]+-(.+)\.(scn|res)$")     # .godot/exported/<hash>/export-<hash>-<name>.<ext>
NODE = re.compile(r"^\[node (?=[^\]]*name=)[^\]]*\]$", re.M)       # a node's line
UID = re.compile(r'^\[node (?=[^\]]*name=)[^\]]* unique_id=(\d+)', re.M)
TEXT = re.compile(r'^\[gd_scene [^\]]*\bproperties=true(?=[ \]])')  # saved without conversion
REMOVED = 2
MAX_ID = 0x7FFFFFFF                                               # 31 bits; -1 (all ones) is "unassigned"


def run(cmd) -> tuple:
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, ANSI.sub("", p.stdout + p.stderr)


def scenes_of(root: str) -> dict:
    """{name without .tscn: path} of the project's scenes."""
    out = {}
    for dirpath, dirnames, files in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".godot", ".git")]
        for f in files:
            if f.endswith(".tscn"):
                out[f[:-len(".tscn")]] = os.path.join(dirpath, f)
    return out


def conversions(root: str) -> dict:
    """{name without .scn/.res: (extension, path)} of the scene conversions cached in .godot/exported."""
    out = {}
    for dirpath, _, files in os.walk(os.path.join(root, ".godot", "exported")):
        for f in files:
            m = CONVERTED.match(f)
            if m:
                out[m.group(1)] = (m.group(2), os.path.join(dirpath, f))
    return out


def md5_file(path: str) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def pack_md5s(path: str):
    """{path in the pack: md5}; None when it is not a Godot pack."""
    try:
        data = pck_tool.read(path)
        return {p: md5 for _, _, p, md5, flags in pck_tool.pack_files(data) if not flags & REMOVED}
    except (OSError, ValueError):
        return None


def check_sources(root: str) -> list:
    """Problems in the scenes themselves: nodes without id, ids used twice, ids outside the 31 bits."""
    errors = []
    by_name = {}
    for name, path in sorted(scenes_of(root).items()):
        rel = os.path.relpath(path, root)
        by_name.setdefault(name, []).append(rel)
        text = open(path, encoding="utf-8").read()
        if TEXT.search(text):
            continue                         # the export keeps its text (properties=true): no conversion to differ
        nodes = len(NODE.findall(text))
        ids = [int(i) for i in UID.findall(text)]
        if len(ids) < nodes:
            errors.append("%s: %d of %d nodes have no unique_id: the export draws a random one for each, so this "
                          "scene never exports the same bytes twice" % (rel, nodes - len(ids), nodes))
        seen = set()
        for i in ids:
            if not 0 <= i <= MAX_ID:
                errors.append("%s: unique_id=%d does not fit a node id's 31 bits" % (rel, i))
            if i in seen:
                errors.append("%s: unique_id=%d is used twice" % (rel, i))
            seen.add(i)
    for name, rels in sorted(by_name.items()):
        if len(rels) > 1:
            errors.append("%s: same scene name: the exporter converts both to the same generated file"
                          % " and ".join(rels))
    return errors


def export(project: str, out: str) -> str:
    """godot --export-pack Linux <out>; "" when it worked, else what it said. A project with no user data folder
    (user://) exits 1 after writing the pack: the pack is what counts."""
    out = os.path.abspath(out)
    code, text = run(["godot", "--headless", "--path", os.path.abspath(project), "--export-pack", "Linux", out])
    if os.path.isfile(out):
        return ""
    return "godot --export-pack Linux failed (exit %d):\n%s" % (code, text.strip()[-3000:])


def check_exports(project: str) -> list:
    """Two exports of this project give every scene the same bytes, and the first export's pack carries them."""
    project = os.path.abspath(project)
    exported = os.path.join(project, ".godot", "exported")
    work = tempfile.mkdtemp(prefix="check_scene_ids-")
    try:
        scenes = scenes_of(project)
        shutil.rmtree(exported, ignore_errors=True)       # an older export's conversions would be reused as they are
        first = os.path.join(work, "first.pck")
        err = export(project, first)
        if err != "":
            return [err]
        before = conversions(project)
        # the same export again with the conversions gone: what the job's --export-patch does further down
        shutil.rmtree(exported, ignore_errors=True)
        err = export(project, os.path.join(work, "second.pck"))
        if err != "":
            return [err]
        after = conversions(project)
        got = pack_md5s(first)
        if got is None:
            return ["the export wrote no pack, so nothing can be checked"]
        errors = []
        for name in sorted(scenes):
            if name not in before:
                continue                                  # not converted, or a text one: nothing to differ
            rel = os.path.relpath(before[name][1], project)
            if md5_file(before[name][1]) != got.get(rel):
                errors.append("%s (%s): the pack of the export does not carry this conversion"
                              % (rel, os.path.relpath(scenes[name], project)))
            if name not in after:
                errors.append("%s (%s): the second export did not convert it" % (rel,
                                                                                os.path.relpath(scenes[name], project)))
            elif md5_file(after[name][1]) != md5_file(before[name][1]):
                errors.append("%s (%s): not the same at each export, some node has no unique_id, so the export "
                              "draws a random one" % (rel, os.path.relpath(scenes[name], project)))
        return errors
    finally:
        shutil.rmtree(work, ignore_errors=True)
        shutil.rmtree(exported, ignore_errors=True)       # the pack a later step here makes must be a fresh export


def check_patch(game: str, patch: str) -> list:
    """The generated scenes and resources this build's pack and the patch carry are the same."""
    a = pack_md5s(game)
    b = pack_md5s(patch)
    if a is None:
        return ["%s is not a Godot pack" % game]
    if b is None:
        return ["%s is not a Godot pack" % patch]
    errors = []
    for path, md5 in sorted(b.items()):
        if not path.startswith(".godot/exported/"):
            continue
        if path not in a:
            errors.append("extra in the patch: " + path)
        elif a[path] != md5:
            errors.append("differs: " + path)
    return errors


def main(argv: list) -> int:
    if "--help" in argv or "-h" in argv:
        print(USAGE)
        return 0
    opts = {a for a in argv if a.startswith("-")}
    paths = [a for a in argv if not a.startswith("-")]
    if opts - {"--export", "--patch"} or ({"--export", "--patch"} <= opts) \
            or len(paths) != (2 if "--patch" in opts else 1):
        print(USAGE, file=sys.stderr)
        return 2
    if "--patch" in opts:
        errors = check_patch(paths[0], paths[1])
    else:
        errors = check_sources(paths[0])
        if "--export" in opts:
            errors += check_exports(paths[0])
    if errors:
        print("%d problem(s):" % len(errors), file=sys.stderr)
        for e in errors:
            print("  " + e.replace("\n", "\n  "), file=sys.stderr)
        return 1
    print("Scenes: every node has its unique_id%s." % (" and every export gives the same bytes"
                                                      if "--export" in opts else ""))
    return 0


USAGE = """usage: check_scene_ids.py [--export] <godot dir>
       check_scene_ids.py --patch <game.pck> <patch.pck>"""


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
