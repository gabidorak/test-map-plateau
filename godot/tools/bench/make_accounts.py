#!/usr/bin/env python3
"""Throwaway accounts for the player capacity benchmark (swarm.gd), straight in the accounts service's SQLite database.

    PLATEAU_ACCOUNTS_DB=/data/bench.db python make_accounts.py COUNT MODEL > tokens.json

NEVER on the live database: it refuses a database that already has accounts not made by this script.
"""
import json
import os
import sys

from plateau_accounts import db

count, model = int(sys.argv[1]), sys.argv[2]
c = db.connect()
db.init(c)
others = c.execute("SELECT COUNT(*) FROM accounts WHERE username NOT LIKE 'Bench_%'").fetchone()[0]
if others:
    sys.exit(f"{os.environ.get('PLATEAU_ACCOUNTS_DB')} holds {others} real accounts: use a throwaway database")
out = []
for i in range(count):
    name = f"Bench_{i}"
    row = db.find(c, name)
    if row is not None:
        sys.exit(f"{name} exists already: start from an empty database")
    account, token = db.signup(c, name, f"bench-{i}-password-x", f"10.{i // 256}.{i % 256}.1")
    db.vehicle_change(c, account, "add", 0, model=model, colour="")
    out.append({"name": name, "token": token})
json.dump(out, sys.stdout)
