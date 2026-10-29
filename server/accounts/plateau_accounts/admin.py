"""plateau-admin: the accounts admin's commands, on the live database (safe while the service runs: SQLite locks).

    docker compose exec accounts plateau-admin show <user>
    docker compose exec accounts plateau-admin reset-password <user> [--password P]   (prints a new one otherwise)
    docker compose exec accounts plateau-admin rename <user> <new name>               (any time, no 30-day wait)
    docker compose exec accounts plateau-admin ban <user> | unban <user>              (ban logs them out everywhere)
    docker compose exec accounts plateau-admin give <user> <€> [reason] | take <user> <€> [reason]
    docker compose exec accounts plateau-admin add-vehicle <user> <model> [colour]    (free; models: godot/scripts/car.gd)
"""

import argparse
import datetime
import secrets
import sys

from . import db, rules


def _row(c, username: str):
    row = db.find(c, username)
    if row is None:
        sys.exit(f"No account named {username!r}.")
    return row


def _when(t: float | None) -> str:
    return datetime.datetime.fromtimestamp(t, datetime.UTC).strftime("%Y-%m-%d %H:%M UTC") if t else "-"


def show(c, a) -> None:
    row = _row(c, a.user)
    print(f"{row['username']} (#{row['id']}), created {_when(row['created'])}, renamed {_when(row['renamed_at'])}"
          f"{', BANNED' if row['banned'] else ''}")
    if row["locked_until"] > db.clock():
        print(f"Locked out until {_when(row['locked_until'])}")
    tokens = c.execute("SELECT COUNT(*), MAX(last_used) FROM tokens WHERE account = ?", (row["id"],)).fetchone()
    print(f"Logged in on {tokens[0]} device(s), last seen {_when(tokens[1])}")
    print(f"Balance: {db.balance(c, row['id'])} €")
    vs = db.vehicles(c, row["id"])
    print(f"Vehicles ({len(vs)}):")
    for v in vs:
        print(f"  #{v['id']} {v['model']}  colour {v['colour'] or '-'}{'  WRECKED' if v['wrecked'] else ''}")
    print("Last payments:")
    for p in db.payments(c, row["id"], 50):
        job = f" [{p['job']}]" if p["job"] else ""
        print(f"  {_when(p['time'])}  {p['amount']:+8d} €  -> {p['balance']:8d} €  {p['reason']}{job}")


def reset_password(c, a) -> None:
    row = _row(c, a.user)
    password = a.password or secrets.token_urlsafe(9)
    problem = rules.password_problem(password, row["username"])
    if problem:
        sys.exit(problem)
    db.set_password(c, row["id"], password)
    print(f"New password for {row['username']}: {password}  (logged out everywhere)")


def rename(c, a) -> None:
    row = _row(c, a.user)
    try:
        db.rename(c, row["id"], a.new, admin=True)
    except db.Refused as e:
        sys.exit(e.message)
    print(f"{row['username']} is now {a.new}")


def ban(c, a) -> None:
    row = _row(c, a.user)
    db.set_banned(c, row["id"], a.cmd == "ban")
    print(f"{row['username']} {'banned' if a.cmd == 'ban' else 'unbanned'}")


def give(c, a) -> None:
    row = _row(c, a.user)
    if a.amount < 0:
        sys.exit("The amount is positive (take for the other way).")
    try:
        if a.cmd == "give":
            after = db.pay(c, row["id"], a.amount, a.reason, "admin")
        else:
            after = db.charge(c, row["id"], a.amount, a.reason, "admin")
    except db.Refused as e:
        sys.exit(f"{e.message} ({row['username']} has {db.balance(c, row['id'])} €)")
    print(f"{row['username']}: {after} €")


def add_vehicle(c, a) -> None:
    row = _row(c, a.user)
    done = db.vehicle_change(c, row["id"], "add", 0, model=a.model, colour=a.colour)
    print(f"{row['username']}: {a.model} #{done['vehicle']} added")


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(prog="plateau-admin", description="PTA Online accounts admin")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("show", help="balance, vehicles, last 50 payments")
    s.add_argument("user")
    s.set_defaults(fn=show)
    s = sub.add_parser("reset-password", help="new password (random unless given), logged out everywhere")
    s.add_argument("user")
    s.add_argument("--password", default="")
    s.set_defaults(fn=reset_password)
    s = sub.add_parser("rename", help="rename now (no 30-day wait)")
    s.add_argument("user")
    s.add_argument("new")
    s.set_defaults(fn=rename)
    for name in ("ban", "unban"):
        s = sub.add_parser(name)
        s.add_argument("user")
        s.set_defaults(fn=ban)
    for name in ("give", "take"):
        s = sub.add_parser(name, help=f"{name} money (whole euros)")
        s.add_argument("user")
        s.add_argument("amount", type=int)
        s.add_argument("reason", nargs="?", default=f"admin {name}")
        s.set_defaults(fn=give)
    s = sub.add_parser("add-vehicle", help="a vehicle in their garage, free (PTA Online's game models)")
    s.add_argument("user")
    s.add_argument("model")
    s.add_argument("colour", nargs="?", default="")
    s.set_defaults(fn=add_vehicle)
    a = p.parse_args(argv)
    c = db.connect()
    db.init(c)
    try:
        a.fn(c, a)
    finally:
        c.close()


if __name__ == "__main__":
    main()
