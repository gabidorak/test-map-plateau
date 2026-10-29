"""The accounts database: one SQLite file in WAL mode (PLATEAU_ACCOUNTS_DB, /data/accounts.db in the container).
Every function takes an open connection; writes run in `with write(conn):` (BEGIN IMMEDIATE), so a charge can't race
another one. Money is whole euros."""

import hashlib
import json
import os
import secrets
import sqlite3
import time
from contextlib import contextmanager

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

from . import rules

START_BALANCE = 5000                    # € on a new account
RENAME_EVERY = 30 * 86400               # s between two renames
NAME_KEPT = 30 * 86400                  # s an old name stays reserved for its account
LOCK_TRIES = 5                          # wrong passwords in a row before a lockout...
LOCK_FIRST = 60                         # ...of this many seconds, doubling at each lockout until a good login
SIGNUPS_PER_IP = 3                      # accounts made from one IP address...
SIGNUP_WINDOW = 86400                   # ...per this many seconds

SCHEMA = """
CREATE TABLE IF NOT EXISTS accounts (
    id INTEGER PRIMARY KEY,
    username TEXT NOT NULL,             -- as typed at sign-up (or at the last rename)
    lower TEXT NOT NULL UNIQUE,         -- login lookup
    skeleton TEXT NOT NULL UNIQUE,      -- look-alike uniqueness (rules.skeleton)
    password TEXT NOT NULL,             -- argon2id hash
    created REAL NOT NULL,
    renamed_at REAL,
    banned INTEGER NOT NULL DEFAULT 0,
    fails INTEGER NOT NULL DEFAULT 0,   -- wrong passwords since the last lockout or good login
    lock_level INTEGER NOT NULL DEFAULT 0,
    locked_until REAL NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS tokens (
    hash TEXT PRIMARY KEY,              -- sha256 of the token: the token itself is never stored
    account INTEGER NOT NULL REFERENCES accounts(id),
    created REAL NOT NULL,
    last_used REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS tokens_account ON tokens(account);
CREATE TABLE IF NOT EXISTS wallet (
    account INTEGER PRIMARY KEY REFERENCES accounts(id),
    balance INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS vehicles (
    id INTEGER PRIMARY KEY,
    account INTEGER NOT NULL REFERENCES accounts(id),
    model TEXT NOT NULL,
    colour TEXT NOT NULL DEFAULT '',
    wrecked INTEGER NOT NULL DEFAULT 0,
    upgrades TEXT NOT NULL DEFAULT '{}',
    added REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS vehicles_account ON vehicles(account);
CREATE TABLE IF NOT EXISTS payments (
    id INTEGER PRIMARY KEY,
    account INTEGER NOT NULL REFERENCES accounts(id),
    amount INTEGER NOT NULL,            -- + earned, - spent, 0 for a change that cost nothing
    reason TEXT NOT NULL,
    job TEXT NOT NULL DEFAULT '',
    time REAL NOT NULL,
    balance INTEGER NOT NULL            -- after it
);
CREATE INDEX IF NOT EXISTS payments_account ON payments(account, time);
CREATE TABLE IF NOT EXISTS reserved_names (
    skeleton TEXT NOT NULL,
    account INTEGER NOT NULL REFERENCES accounts(id),
    until REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS reserved_skeleton ON reserved_names(skeleton);
CREATE TABLE IF NOT EXISTS signups (
    ip TEXT NOT NULL,
    time REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS signups_ip ON signups(ip, time);
"""

_hasher = PasswordHasher()              # argon2id
_DUMMY = _hasher.hash("not a password, only spends the same time")
clock = time.time                       # tests move it


class Refused(Exception):
    """A request the rules refuse: HTTP `status`, a short `code` for the game, a `message` to show."""

    def __init__(self, status: int, code: str, message: str, **extra):
        super().__init__(message)
        self.status, self.code, self.message, self.extra = status, code, message, extra


def path() -> str:
    return os.environ.get("PLATEAU_ACCOUNTS_DB", "/data/accounts.db")


def connect(db_path: str | None = None) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path or path(), isolation_level=None, timeout=10, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA busy_timeout=10000")
    return conn


def init(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA)


@contextmanager
def write(conn: sqlite3.Connection):
    conn.execute("BEGIN IMMEDIATE")
    try:
        yield
    except BaseException:
        conn.execute("ROLLBACK")
        raise
    conn.execute("COMMIT")


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


# ---------------------------------------------------------------- accounts

def find(conn: sqlite3.Connection, username: str) -> sqlite3.Row | None:
    return conn.execute("SELECT * FROM accounts WHERE lower = ?", (username.lower(),)).fetchone()


def _name_free(conn: sqlite3.Connection, name: str, account: int = 0) -> None:
    """Refuses `name` if another account has it or a look-alike of it, or keeps it as an old name."""
    sk = rules.skeleton(name)
    row = conn.execute("SELECT id, lower FROM accounts WHERE skeleton = ? AND id != ?", (sk, account)).fetchone()
    if row:
        same = row["lower"] == name.lower()
        raise Refused(409, "taken", "This username is taken." if same else "Too close to an existing username.")
    if conn.execute("SELECT 1 FROM reserved_names WHERE skeleton = ? AND account != ? AND until > ?",
                    (sk, account, clock())).fetchone():
        raise Refused(409, "taken", "This username was in use recently: pick another.")


def new_token(conn: sqlite3.Connection, account: int) -> str:
    token = secrets.token_urlsafe(32)
    now = clock()
    conn.execute("INSERT INTO tokens (hash, account, created, last_used) VALUES (?, ?, ?, ?)",
                 (_token_hash(token), account, now, now))
    return token


def signup(conn: sqlite3.Connection, username: str, password: str, ip: str) -> tuple[int, str]:
    """A new account with START_BALANCE € and a token for it: (account id, token)."""
    problem = rules.username_problem(username)
    if problem:
        raise Refused(400, "username", problem)
    problem = rules.password_problem(password, username)
    if problem:
        raise Refused(400, "password", problem)
    pw_hash = _hasher.hash(password)    # outside the write lock: it takes a while on purpose
    with write(conn):
        now = clock()
        n = conn.execute("SELECT COUNT(*) FROM signups WHERE ip = ? AND time > ?",
                         (ip, now - SIGNUP_WINDOW)).fetchone()[0]
        if n >= SIGNUPS_PER_IP:
            raise Refused(429, "signup_limit", f"Only {SIGNUPS_PER_IP} new accounts a day from one connection.")
        _name_free(conn, username)
        cur = conn.execute("INSERT INTO accounts (username, lower, skeleton, password, created) VALUES (?, ?, ?, ?, ?)",
                           (username, username.lower(), rules.skeleton(username), pw_hash, now))
        account = cur.lastrowid
        conn.execute("INSERT INTO wallet (account, balance) VALUES (?, ?)", (account, START_BALANCE))
        _log(conn, account, START_BALANCE, "starting money", "", START_BALANCE)
        conn.execute("INSERT INTO signups (ip, time) VALUES (?, ?)", (ip, now))
        return account, new_token(conn, account)


def login(conn: sqlite3.Connection, username: str, password: str) -> tuple[int, str]:
    """(account id, new token), or Refused: wrong name or password, locked out, banned."""
    row = find(conn, username)
    if row is None:
        try:
            _hasher.verify(_DUMMY, password)    # the same time as a real check: names can't be probed
        except VerificationError:
            pass
        raise Refused(401, "wrong", "Wrong username or password.")
    now = clock()
    if row["locked_until"] > now:
        wait = int(row["locked_until"] - now + 0.999)
        raise Refused(429, "locked", f"Too many wrong passwords: try again in {_duration(wait)}.", retry_after=wait)
    try:
        ok = _hasher.verify(row["password"], password)
    except (VerificationError, InvalidHashError):
        ok = False
    with write(conn):
        if not ok:
            fails = row["fails"] + 1
            if fails >= LOCK_TRIES:
                wait = LOCK_FIRST * 2 ** row["lock_level"]
                conn.execute("UPDATE accounts SET fails = 0, lock_level = lock_level + 1, locked_until = ? "
                             "WHERE id = ?", (now + wait, row["id"]))
            else:
                conn.execute("UPDATE accounts SET fails = ? WHERE id = ?", (fails, row["id"]))
        else:
            conn.execute("UPDATE accounts SET fails = 0, lock_level = 0, locked_until = 0 WHERE id = ?", (row["id"],))
            if row["banned"]:
                raise Refused(403, "banned", "This account is banned.")
            if _hasher.check_needs_rehash(row["password"]):
                conn.execute("UPDATE accounts SET password = ? WHERE id = ?", (_hasher.hash(password), row["id"]))
            return row["id"], new_token(conn, row["id"])
    raise Refused(401, "wrong", "Wrong username or password.")


def _duration(s: int) -> str:
    return f"{s} s" if s < 120 else f"{(s + 59) // 60} min"


def account_of(conn: sqlite3.Connection, token: str) -> sqlite3.Row | None:
    """The account a token logs into (its last use noted), or None."""
    if not token:
        return None
    h = _token_hash(token)
    row = conn.execute("SELECT accounts.* FROM tokens JOIN accounts ON accounts.id = tokens.account WHERE hash = ?",
                       (h,)).fetchone()
    if row:
        conn.execute("UPDATE tokens SET last_used = ? WHERE hash = ?", (clock(), h))
    return row


def logout(conn: sqlite3.Connection, token: str) -> None:
    conn.execute("DELETE FROM tokens WHERE hash = ?", (_token_hash(token),))


def logout_all(conn: sqlite3.Connection, account: int) -> None:
    conn.execute("DELETE FROM tokens WHERE account = ?", (account,))


def rename(conn: sqlite3.Connection, account: int, new_name: str, admin: bool = False) -> None:
    """Renames an account (once every RENAME_EVERY, unless `admin`); its old name stays reserved for it NAME_KEPT s."""
    problem = rules.username_problem(new_name)
    if problem:
        raise Refused(400, "username", problem)
    with write(conn):
        row = conn.execute("SELECT * FROM accounts WHERE id = ?", (account,)).fetchone()
        now = clock()
        last = row["renamed_at"] or row["created"]
        if not admin and now - last < RENAME_EVERY:
            days = int((last + RENAME_EVERY - now) / 86400) + 1
            raise Refused(429, "rename_wait", f"One rename every 30 days: the next one in {days} days.")
        _name_free(conn, new_name, account)
        if rules.skeleton(new_name) != row["skeleton"]:
            conn.execute("INSERT INTO reserved_names (skeleton, account, until) VALUES (?, ?, ?)",
                         (row["skeleton"], account, now + NAME_KEPT))
        conn.execute("DELETE FROM reserved_names WHERE account = ? AND skeleton = ?", (account, rules.skeleton(new_name)))
        conn.execute("UPDATE accounts SET username = ?, lower = ?, skeleton = ?, renamed_at = ? WHERE id = ?",
                     (new_name, new_name.lower(), rules.skeleton(new_name), now, account))
        _log(conn, account, 0, f"renamed {row['username']} -> {new_name}", "", balance(conn, account))


def next_rename(row: sqlite3.Row) -> float:
    return (row["renamed_at"] or row["created"]) + RENAME_EVERY


def set_password(conn: sqlite3.Connection, account: int, password: str) -> None:
    """Admin reset: new hash, lockout cleared, every token revoked (the game logs in again)."""
    pw_hash = _hasher.hash(password)
    with write(conn):
        conn.execute("UPDATE accounts SET password = ?, fails = 0, lock_level = 0, locked_until = 0 WHERE id = ?",
                     (pw_hash, account))
        logout_all(conn, account)


def set_banned(conn: sqlite3.Connection, account: int, banned: bool) -> None:
    with write(conn):
        conn.execute("UPDATE accounts SET banned = ? WHERE id = ?", (int(banned), account))
        if banned:
            logout_all(conn, account)


# ---------------------------------------------------------------- money and vehicles

def balance(conn: sqlite3.Connection, account: int) -> int:
    row = conn.execute("SELECT balance FROM wallet WHERE account = ?", (account,)).fetchone()
    return row[0] if row else 0


def _log(conn, account: int, amount: int, reason: str, job: str, after: int) -> None:
    conn.execute("INSERT INTO payments (account, amount, reason, job, time, balance) VALUES (?, ?, ?, ?, ?, ?)",
                 (account, amount, reason, job, clock(), after))


def _move(conn, account: int, amount: int, reason: str, job: str) -> int:
    """Adds `amount` (negative: takes) inside a write; refuses to go below 0. Returns the new balance."""
    now_balance = balance(conn, account)
    if now_balance + amount < 0:
        raise Refused(402, "too_poor", "Not enough money.", balance=now_balance)
    conn.execute("UPDATE wallet SET balance = ? WHERE account = ?", (now_balance + amount, account))
    _log(conn, account, amount, reason, job, now_balance + amount)
    return now_balance + amount


def pay(conn: sqlite3.Connection, account: int, amount: int, reason: str, job: str = "") -> int:
    if amount < 0:
        raise Refused(400, "amount", "A payment is 0 or more.")
    with write(conn):
        return _move(conn, account, amount, reason, job)


HOUR = 3600.0


def earned_in_hour(conn: sqlite3.Connection, account: int) -> int:
    """What the account earned from jobs (any job but the admin's) in the last HOUR s."""
    row = conn.execute("SELECT COALESCE(SUM(amount), 0) FROM payments WHERE account = ? AND time > ? AND amount > 0 "
                       "AND job NOT IN ('', 'admin')", (account, clock() - HOUR)).fetchone()
    return row[0]


def earn(conn: sqlite3.Connection, account: int, amount: int, reason: str, job: str, cap: int = 0) -> dict:
    """Pays `amount` for job `job`, cut so that the account's job earnings over the last HOUR s stay within `cap`
    (0: no cap; a cut payment's reason says "(cap)"). Returns the balance, what was paid, and the hour's earnings."""
    if amount < 0:
        raise Refused(400, "amount", "A payment is 0 or more.")
    with write(conn):
        hour = earned_in_hour(conn, account)
        paid = min(amount, max(cap - hour, 0)) if cap > 0 else amount
        after = _move(conn, account, paid, reason + (" (cap)" if paid < amount else ""), job)
        return {"balance": after, "paid": paid, "hour": hour + paid}


def charge(conn: sqlite3.Connection, account: int, amount: int, reason: str, job: str = "") -> int:
    if amount < 0:
        raise Refused(400, "amount", "A charge is 0 or more.")
    with write(conn):
        return _move(conn, account, -amount, reason, job)


def vehicles(conn: sqlite3.Connection, account: int) -> list[dict]:
    rows = conn.execute("SELECT * FROM vehicles WHERE account = ? ORDER BY id", (account,)).fetchall()
    return [{"id": r["id"], "model": r["model"], "colour": r["colour"], "wrecked": bool(r["wrecked"]),
             "upgrades": json.loads(r["upgrades"])} for r in rows]


def vehicle_change(conn: sqlite3.Connection, account: int, action: str, price: int = 0, vehicle: int = 0,
                   model: str = "", colour: str = "") -> dict:
    """add (model, colour), repair, wreck, colour (colour) a vehicle, charging `price` in the same transaction.
    Returns {"vehicle": id, "balance": €}."""
    if price < 0:
        raise Refused(400, "amount", "A price is 0 or more.")
    with write(conn):
        if action == "add":
            if not model:
                raise Refused(400, "model", "No model given.")
            vehicle = conn.execute("INSERT INTO vehicles (account, model, colour, added) VALUES (?, ?, ?, ?)",
                                   (account, model, colour, clock())).lastrowid
            what = f"bought {model}"
        else:
            row = conn.execute("SELECT * FROM vehicles WHERE id = ? AND account = ?", (vehicle, account)).fetchone()
            if row is None:
                raise Refused(404, "no_vehicle", "No such vehicle in this garage.")
            if action == "repair":
                conn.execute("UPDATE vehicles SET wrecked = 0 WHERE id = ?", (vehicle,))
            elif action == "wreck":
                conn.execute("UPDATE vehicles SET wrecked = 1 WHERE id = ?", (vehicle,))
            elif action == "colour":
                conn.execute("UPDATE vehicles SET colour = ? WHERE id = ?", (colour, vehicle))
            else:
                raise Refused(400, "action", f"Unknown vehicle action {action!r}.")
            what = f"{action} {row['model']} #{vehicle}" + (f" {colour}" if action == "colour" else "")
        return {"vehicle": vehicle, "balance": _move(conn, account, -price, what, "")}


def payments(conn: sqlite3.Connection, account: int, n: int = 50) -> list[sqlite3.Row]:
    return conn.execute("SELECT * FROM payments WHERE account = ? ORDER BY id DESC LIMIT ?", (account, n)).fetchall()
