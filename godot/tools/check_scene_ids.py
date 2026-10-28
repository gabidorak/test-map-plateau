#!/usr/bin/env python3
"""tools/check_scene_ids.py <godot dir>: every .tscn node has a unique_id (CI, "Scene ids" in .github/workflows/build.yml).

Godot's text-to-binary export gives every node a unique_id: the one its .tscn gives, or a random one drawn at each
export (SceneState::_parse_node -> ResourceUID::create_id) when it has none. Editor-saved scenes carry ids, hand-written
ones often do not. The data patch (--export-patch, a second export) then converts such a scene to other bytes than this
build's game.pck, tools/verify_patch.gd refuses the patch, and every player downloads the whole game (build 46:
scenes/loading.tscn). A .tscn saved with properties=true is exported as text: nothing to check.
"""
import os
import re
import sys

NODE = re.compile(r"^\[node (?=[^\]]*name=)[^\]]*\]$", re.M)       # a node's line
UID = re.compile(r'^\[node (?=[^\]]*name=)[^\]]* unique_id=(\d+)', re.M)
TEXT = re.compile(r'^\[gd_scene [^\]]*\bproperties=true(?=[ \]])')  # saved without conversion
MAX_ID = 0x7FFFFFFF                                               # 31 bits; -1 (all ones) is "unassigned"


def scenes_of(root: str) -> list:
    out = []
    for dirpath, dirnames, files in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".godot", ".git")]
        out += [os.path.join(dirpath, f) for f in files if f.endswith(".tscn")]
    return sorted(out)


def check(root: str) -> list:
    """Nodes without id, ids used twice in a scene, ids outside the 31 bits."""
    errors = []
    for path in scenes_of(root):
        rel = os.path.relpath(path, root)
        text = open(path, encoding="utf-8").read()
        if TEXT.search(text):
            continue
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
    return errors


def main(argv: list) -> int:
    if len(argv) != 1 or argv[0].startswith("-"):
        print("usage: check_scene_ids.py <godot dir>", file=sys.stderr)
        return 2
    errors = check(argv[0])
    if errors:
        print("%d problem(s):" % len(errors), file=sys.stderr)
        for e in errors:
            print("  " + e, file=sys.stderr)
        return 1
    print("Scenes: every node has its unique_id.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
