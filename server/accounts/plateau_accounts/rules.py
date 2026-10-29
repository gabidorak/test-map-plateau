"""Username and password rules (ONLINE_MODE.md 3.4). The game checks the same rules while the player types
(godot/scripts/account_rules.gd, from godot/data/account_rules.json); rule_vectors.json holds examples both must agree
on. Uniqueness, reserved old names, lockouts and the sign-up limit need the database: db.py."""

import re
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
NAME_MIN, NAME_MAX = 3, 16
PASSWORD_MIN, PASSWORD_MAX = 8, 128
SEPARATORS = "_-."
LOOKALIKES = str.maketrans({"0": "o", "1": "i", "l": "i", "3": "e", "4": "a", "5": "s", "7": "t"})
RESERVED = ["admin", "administrator", "mod", "moderator", "server", "system", "host", "official", "pta", "ptaonline",
            "plateau", "support", "staff", "jeanclaude", "dragon91", "bot", "null", "undefined"]
SHORT_WORD = 3                          # banned words this long or shorter only refuse the whole name

_NAME_CHARS = re.compile(r"^[A-Za-z0-9_.-]+$")


def _list(name: str) -> list[str]:
    lines = (HERE / name).read_text(encoding="utf-8").splitlines()
    return [s.strip() for s in lines if s.strip() and not s.startswith("#")]


def skeleton(name: str) -> str:
    """The form two names are compared in: lowercase, look-alike digits mapped to letters, separators dropped."""
    return name.lower().translate(LOOKALIKES).translate({ord(c): None for c in SEPARATORS})


BANNED = [skeleton(w) for w in _list("banned_words.txt")]
COMMON_PASSWORDS = {p.lower() for p in _list("common_passwords.txt")}
RESERVED_SKELETONS = {skeleton(r) for r in RESERVED}


def username_problem(name: str) -> str:
    """Why `name` can't be a username, or "" (rules 1, 2, 3, 6 and 7; uniqueness is the database's)."""
    if len(name) < NAME_MIN or len(name) > NAME_MAX:
        return f"A username has {NAME_MIN} to {NAME_MAX} characters."
    if not _NAME_CHARS.match(name):
        return "Only letters without accents, digits, _ - and . (no spaces)."
    if name[0] in SEPARATORS:
        return "A username starts with a letter or a digit."
    if name[-1] in SEPARATORS:
        return "A username doesn't end with _ - or ."
    if any(a in SEPARATORS and b in SEPARATORS for a, b in zip(name, name[1:])):
        return "No two of _ - . in a row."
    sk = skeleton(name)
    if sk in RESERVED_SKELETONS:
        return "This name is reserved."
    for w in BANNED:
        if sk == w if len(w) <= SHORT_WORD else w in sk:
            return "This name isn't allowed."
    return ""


def password_problem(password: str, username: str = "") -> str:
    """Why `password` can't be used (for `username`), or ""."""
    if len(password) < PASSWORD_MIN:
        return f"A password has at least {PASSWORD_MIN} characters."
    if len(password) > PASSWORD_MAX:
        return f"A password has at most {PASSWORD_MAX} characters."
    if username and password.lower() == username.lower():
        return "The password can't be the username."
    if password.lower() in COMMON_PASSWORDS:
        return "This password is one of the most common ones: pick another."
    return ""
