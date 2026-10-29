"""Daily backups of the live database with SQLite's online backup (safe while the service writes), into a folder
outside the Docker volume (PLATEAU_BACKUP_DIR, /backups in the container: a host folder). KEEP are kept."""

import os
import sqlite3
import threading
import time
from pathlib import Path

KEEP = 14
CHECK_EVERY = 3600                      # s between two looks at whether today's backup is done


def folder() -> str:
    return os.environ.get("PLATEAU_BACKUP_DIR", "/backups")


def backup_now(db_path: str, out_dir: str, keep: int = KEEP, day: str | None = None) -> Path | None:
    """Writes accounts-<day>.db unless it exists; drops the oldest beyond `keep`. Returns the new file, or None."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    day = day or time.strftime("%Y-%m-%d", time.gmtime())
    target = out / f"accounts-{day}.db"
    if target.exists():
        return None
    part = target.with_suffix(".part")
    src = sqlite3.connect(db_path)
    dst = sqlite3.connect(part)
    try:
        src.backup(dst)
    finally:
        dst.close()
        src.close()
    part.rename(target)
    for old in sorted(out.glob("accounts-*.db"))[:-keep]:
        old.unlink()
    return target


def start(db_path: str) -> threading.Thread | None:
    """Backs up now and then once a day, in a daemon thread (none without a backup folder)."""
    out_dir = folder()
    if not out_dir:
        return None

    def loop() -> None:
        while True:
            try:
                made = backup_now(db_path, out_dir)
                if made:
                    print(f"Backup: {made}", flush=True)
            except Exception as e:      # a full disk must not take the service down
                print(f"Backup failed: {e}", flush=True)
            time.sleep(CHECK_EVERY)

    t = threading.Thread(target=loop, name="backup", daemon=True)
    t.start()
    return t
