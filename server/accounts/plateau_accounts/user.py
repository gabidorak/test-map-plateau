"""Runs the service and the admin CLI as an unprivileged user. The image is built without running anything inside
it (the arm64 one is cross-built: no emulation), so it can't create its user or set the volumes' owner at build time:
started as root, this gives /data and /backups to UID and becomes it."""

import os

UID = 1000


def drop_root() -> None:
    if os.getuid() != 0:
        return
    for d in ("/data", "/backups"):
        if os.path.isdir(d):
            for root, dirs, files in os.walk(d):
                for name in [root] + [os.path.join(root, f) for f in files]:
                    os.chown(name, UID, UID)
    os.setgroups([])
    os.setgid(UID)
    os.setuid(UID)
    os.environ["HOME"] = "/data"
