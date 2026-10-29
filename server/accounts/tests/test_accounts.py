"""The accounts service: every route, the rules, look-alikes, lockouts, the sign-up limit, renames, the internal API's
secret and its money rules, the admin CLI and the backups. Run from server/accounts: `python -m pytest -q`."""

import json
import sqlite3
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from plateau_accounts import admin, app as app_module, backup, db, rules

HERE = Path(__file__).resolve().parent.parent
SECRET = "test-secret"
VECTORS = json.loads((HERE / "rule_vectors.json").read_text(encoding="utf-8"))


class Clock:
    def __init__(self):
        self.t = 1_800_000_000.0

    def __call__(self):
        return self.t


@pytest.fixture
def clock(monkeypatch):
    c = Clock()
    monkeypatch.setattr(db, "clock", c)
    return c


@pytest.fixture
def client(tmp_path, monkeypatch, clock):
    monkeypatch.setenv("PLATEAU_ACCOUNTS_DB", str(tmp_path / "accounts.db"))
    monkeypatch.setenv("PLATEAU_SERVER_SECRET", SECRET)
    monkeypatch.setenv("PLATEAU_BACKUP_DIR", "")
    with TestClient(app_module.app) as c:
        yield c


def signup(client, name="Gabriel", password="correct horse", ip=None):
    headers = {"x-forwarded-for": ip} if ip else {}
    return client.post("/v1/signup", json={"username": name, "password": password}, headers=headers)


def auth(token):
    return {"Authorization": f"Bearer {token}"}


def internal(secret=SECRET):
    return {"X-Server-Secret": secret}


# ---------------------------------------------------------------- rules

@pytest.mark.parametrize("name", VECTORS["usernames_ok"])
def test_username_accepted(name):
    assert rules.username_problem(name) == ""


@pytest.mark.parametrize("name,start", VECTORS["usernames_refused"])
def test_username_refused(name, start):
    assert rules.username_problem(name).startswith(start)


@pytest.mark.parametrize("password,user", VECTORS["passwords_ok"])
def test_password_accepted(password, user):
    assert rules.password_problem(password, user) == ""


@pytest.mark.parametrize("password,user,start", VECTORS["passwords_refused"])
def test_password_refused(password, user, start):
    assert rules.password_problem(password, user).startswith(start)


def test_skeleton():
    assert rules.skeleton("Gabr1el") == rules.skeleton("ga-briel") == rules.skeleton("GABRIEL") == "gabriei"
    assert rules.skeleton("B0b_5.7") == "bobst"


def test_short_banned_words_only_match_whole_names():
    assert rules.username_problem("con") != ""
    assert rules.username_problem("Constance") == ""
    assert rules.username_problem("Bacon") == ""


def test_client_rules_file_matches():
    """godot/data/account_rules.json is the game's copy of the lists (sync_client_rules.py writes it)."""
    copy = json.loads((HERE.parent.parent / "godot/data/account_rules.json").read_text(encoding="utf-8"))
    assert copy["reserved"] == rules.RESERVED
    assert copy["banned"] == rules._list("banned_words.txt")
    assert set(copy["common_passwords"]) == rules.COMMON_PASSWORDS
    assert copy["name_min"] == rules.NAME_MIN and copy["name_max"] == rules.NAME_MAX
    assert copy["password_min"] == rules.PASSWORD_MIN and copy["password_max"] == rules.PASSWORD_MAX


def test_start_money_matches_prices():
    """godot/data/prices.json's starting money (the cheapest car's price) is what a new account gets."""
    prices = json.loads((HERE.parent.parent / "godot/data/prices.json").read_text(encoding="utf-8"))
    assert prices["start"] == db.START_BALANCE
    cheapest = min(p for t in prices["tiers"] if t["at"] == "prestige" for p in t["models"].values())
    assert cheapest == db.START_BALANCE


# ---------------------------------------------------------------- public API

def test_signup_login_me_logout(client):
    r = signup(client)
    assert r.status_code == 200, r.text
    first = r.json()
    assert first["username"] == "Gabriel" and first["balance"] == 5000 and first["vehicles"] == []
    r = client.get("/v1/me", headers=auth(first["token"]))
    assert r.status_code == 200 and r.json()["balance"] == 5000
    r = client.post("/v1/login", json={"username": "gABRIEL", "password": "correct horse"})
    assert r.status_code == 200 and r.json()["username"] == "Gabriel"
    second = r.json()["token"]
    assert second != first["token"]
    assert client.post("/v1/logout", headers=auth(first["token"])).status_code == 200
    assert client.get("/v1/me", headers=auth(first["token"])).status_code == 401
    assert client.get("/v1/me", headers=auth(second)).status_code == 200


def test_logout_all(client):
    a = signup(client).json()["token"]
    b = client.post("/v1/login", json={"username": "Gabriel", "password": "correct horse"}).json()["token"]
    assert client.post("/v1/logout-all", headers=auth(a)).status_code == 200
    assert client.get("/v1/me", headers=auth(a)).status_code == 401
    assert client.get("/v1/me", headers=auth(b)).status_code == 401


def test_me_without_token(client):
    r = client.get("/v1/me")
    assert r.status_code == 401 and r.json()["error"] == "token"
    assert client.get("/v1/me", headers=auth("made-up")).status_code == 401


def test_tokens_stored_hashed(client, tmp_path):
    token = signup(client).json()["token"]
    raw = (tmp_path / "accounts.db").read_bytes()
    for f in tmp_path.glob("accounts.db*"):
        raw += f.read_bytes()
    assert token.encode() not in raw
    assert b"correct horse" not in raw


def test_signup_refusals(client):
    r = signup(client, name="a__b")
    assert r.status_code == 400 and r.json()["error"] == "username"
    r = signup(client, password="password")
    assert r.status_code == 400 and r.json()["error"] == "password"
    r = signup(client, name="Gabriel1", password="gabriel1")
    assert r.status_code == 400 and "username" in r.json()["message"]


def test_names_unique_without_case_and_lookalikes(client):
    assert signup(client, "Gabriel", ip="1.1.1.1").status_code == 200
    for k, name in enumerate(("gabriel", "GABRIEL", "Gabr1el", "ga-briel", "Gabr.1.el", "GabrieL")):
        assert signup(client, name, ip=f"2.2.2.{k}").status_code == 409, name
    assert signup(client, "Gabrielle", ip="2.2.3.1").status_code == 200
    r = signup(client, "gabriel", ip="3.3.3.3")
    assert r.json()["message"] == "This username is taken."
    r = signup(client, "Gabr1el", ip="3.3.3.4")
    assert r.json()["message"] == "Too close to an existing username."


def test_wrong_password_and_unknown_user_look_the_same(client):
    signup(client)
    a = client.post("/v1/login", json={"username": "Gabriel", "password": "wrong password"})
    b = client.post("/v1/login", json={"username": "Nobody", "password": "wrong password"})
    assert a.status_code == b.status_code == 401
    assert a.json() == b.json()


def test_lockout_timing(client, clock):
    signup(client)

    def login(pw="wrong password"):
        return client.post("/v1/login", json={"username": "Gabriel", "password": pw})

    for _ in range(4):
        assert login().status_code == 401
    assert login().status_code == 401           # the 5th wrong one locks
    r = login("correct horse")
    assert r.status_code == 429 and r.json()["error"] == "locked" and r.json()["retry_after"] == 60
    clock.t += 59
    assert login("correct horse").status_code == 429
    clock.t += 1.5
    for _ in range(5):
        assert login().status_code == 401
    r = login("correct horse")
    assert r.status_code == 429 and r.json()["retry_after"] == 120     # doubled
    clock.t += 121
    assert login("correct horse").status_code == 200   # a good login resets the doubling
    for _ in range(5):
        login()
    assert login("correct horse").json()["retry_after"] == 60


def test_signup_limit_per_ip(client, clock):
    for k in range(3):
        assert signup(client, f"Player{k}", ip="9.9.9.9").status_code == 200
    r = signup(client, "Player3", ip="9.9.9.9")
    assert r.status_code == 429 and r.json()["error"] == "signup_limit"
    assert signup(client, "Player4", ip="9.9.9.8").status_code == 200   # another address
    clock.t += 86401
    assert signup(client, "Player5", ip="9.9.9.9").status_code == 200   # a day later


def test_rename_and_reservation(client, clock):
    token = signup(client, "Gabriel", ip="1.1.1.1").json()["token"]
    r = client.post("/v1/rename", json={"username": "Gaby"}, headers=auth(token))
    assert r.status_code == 429 and r.json()["error"] == "rename_wait"      # 30 days after sign-up
    clock.t += 30 * 86400 + 1
    r = client.post("/v1/rename", json={"username": "Gaby"}, headers=auth(token))
    assert r.status_code == 200 and r.json()["username"] == "Gaby"
    assert client.post("/v1/login", json={"username": "Gaby", "password": "correct horse"}).status_code == 200
    assert client.post("/v1/login", json={"username": "Gabriel", "password": "correct horse"}).status_code == 401
    # the old name stays reserved for 30 days, look-alikes too
    assert signup(client, "Gabriel", ip="2.2.2.2").status_code == 409
    assert signup(client, "gabr1el", ip="2.2.2.3").status_code == 409
    r = client.post("/v1/rename", json={"username": "Gabriel"}, headers=auth(token))
    assert r.status_code == 429                 # and the owner waits like anyone
    clock.t += 30 * 86400 + 1
    assert signup(client, "Gabriel", ip="2.2.2.4").status_code == 200
    r = client.post("/v1/rename", json={"username": "a__b"}, headers=auth(token))
    assert r.status_code == 400


def test_own_old_name_stays_free_for_its_account(client, clock):
    token = signup(client, "Gabriel").json()["token"]
    clock.t += 30 * 86400 + 1
    client.post("/v1/rename", json={"username": "Gaby"}, headers=auth(token))
    clock.t += 86400                            # reserved, but for this account only (an admin rename back)
    c = db.connect()
    db.rename(c, db.find(c, "Gaby")["id"], "gabriel", admin=True)
    assert client.get("/v1/me", headers=auth(token)).json()["username"] == "gabriel"


def test_banned_account(client):
    token = signup(client).json()["token"]
    c = db.connect()
    db.set_banned(c, db.find(c, "Gabriel")["id"], True)
    assert client.get("/v1/me", headers=auth(token)).status_code == 401     # logged out everywhere
    r = client.post("/v1/login", json={"username": "Gabriel", "password": "correct horse"})
    assert r.status_code == 403 and r.json()["error"] == "banned"
    r = client.post("/v1/login", json={"username": "Gabriel", "password": "wrong password"})
    assert r.status_code == 401                 # a wrong password doesn't learn it is banned
    db.set_banned(c, db.find(c, "Gabriel")["id"], False)
    assert client.post("/v1/login", json={"username": "Gabriel", "password": "correct horse"}).status_code == 200


def test_old_game_asked_to_update(client):
    r = client.get("/v1/status", headers={"Plateau-Api": "0"})
    assert r.status_code == 426 and r.json()["error"] == "update"
    assert client.get("/v1/status", headers={"Plateau-Api": "1"}).json()["api"] == 1


# ---------------------------------------------------------------- internal API

def test_internal_api_refused_without_secret(client, monkeypatch):
    token = signup(client).json()["token"]
    for headers in ({}, internal("wrong")):
        assert client.get(f"/v1/server/who?token={token}", headers=headers).status_code == 403
        assert client.post("/v1/server/pay", json={"account": 1, "amount": 1, "reason": "x"},
                           headers=headers).status_code == 403
        assert client.post("/v1/server/charge", json={"account": 1, "amount": 1, "reason": "x"},
                           headers=headers).status_code == 403
        assert client.post("/v1/server/vehicle", json={"account": 1, "action": "add", "model": "r8"},
                           headers=headers).status_code == 403
    monkeypatch.setenv("PLATEAU_SERVER_SECRET", "")
    assert client.get(f"/v1/server/who?token={token}", headers=internal("")).status_code == 403


def test_who(client):
    token = signup(client).json()["token"]
    r = client.get(f"/v1/server/who?token={token}", headers=internal())
    assert r.status_code == 200 and r.json()["username"] == "Gabriel" and r.json()["balance"] == 5000
    assert client.get("/v1/server/who?token=nope", headers=internal()).status_code == 404
    c = db.connect()
    db.set_banned(c, r.json()["account"], True)
    assert client.get(f"/v1/server/who?token={token}", headers=internal()).status_code == 404   # revoked


def test_pay_and_charge(client):
    token = signup(client).json()["token"]
    account = client.get(f"/v1/server/who?token={token}", headers=internal()).json()["account"]
    r = client.post("/v1/server/pay", json={"account": account, "amount": 120, "reason": "stop", "job": "bus"},
                    headers=internal())
    assert r.json()["balance"] == 5120
    r = client.post("/v1/server/charge", json={"account": account, "amount": 5000, "reason": "hatchback"},
                    headers=internal())
    assert r.json()["balance"] == 120
    r = client.post("/v1/server/charge", json={"account": account, "amount": 121, "reason": "too much"},
                    headers=internal())
    assert r.status_code == 402 and r.json()["error"] == "too_poor" and r.json()["balance"] == 120
    r = client.post("/v1/server/charge", json={"account": account, "amount": 120, "reason": "all of it"},
                    headers=internal())
    assert r.json()["balance"] == 0
    for path in ("/v1/server/pay", "/v1/server/charge"):
        r = client.post(path, json={"account": account, "amount": -5, "reason": "negative"}, headers=internal())
        assert r.status_code == 400
    assert client.post("/v1/server/pay", json={"account": 999, "amount": 1, "reason": "x"},
                       headers=internal()).status_code == 404
    c = db.connect()
    rows = db.payments(c, account)
    assert [p["amount"] for p in rows] == [-120, -5000, 120, 5000]
    assert rows[2]["job"] == "bus" and rows[0]["balance"] == 0


def test_pay_cap_per_hour(client, clock):
    token = signup(client).json()["token"]
    account = client.get(f"/v1/server/who?token={token}", headers=internal()).json()["account"]

    def pay(amount, job="bus:4606", cap=1000):
        return client.post("/v1/server/pay", json={"account": account, "amount": amount, "reason": "stop", "job": job,
                                                   "cap": cap}, headers=internal()).json()

    assert pay(600) == {"balance": 5600, "paid": 600, "hour": 600}
    client.post("/v1/server/pay", json={"account": account, "amount": 900, "reason": "gift", "job": "admin"},
                headers=internal())                         # the admin's money doesn't count
    assert pay(600) == {"balance": 6900, "paid": 400, "hour": 1000}
    assert pay(300)["paid"] == 0
    clock.t += 1800
    assert pay(300, job="stunts")["paid"] == 0             # every job counts
    clock.t += 1801                                         # the first two are over an hour old
    assert pay(300) == {"balance": 7200, "paid": 300, "hour": 300}
    rows = db.payments(db.connect(), account)
    assert [r["reason"] for r in rows[:4]] == ["stop", "stop (cap)", "stop (cap)", "stop (cap)"]


def test_vehicles(client):
    token = signup(client).json()["token"]
    account = client.get(f"/v1/server/who?token={token}", headers=internal()).json()["account"]

    def change(**kw):
        return client.post("/v1/server/vehicle", json={"account": account, **kw}, headers=internal())

    r = change(action="add", model="hatchback", colour="red", price=5000)
    assert r.status_code == 200 and r.json()["balance"] == 0
    vid = r.json()["vehicle"]
    r = change(action="add", model="sedan", price=6000)
    assert r.status_code == 402
    assert len(client.get("/v1/me", headers=auth(token)).json()["vehicles"]) == 1   # not added
    assert change(action="wreck", vehicle=vid).json()["vehicles"][0]["wrecked"] is True
    assert change(action="repair", vehicle=vid, price=150).status_code == 402
    client.post("/v1/server/pay", json={"account": account, "amount": 1000, "reason": "x"}, headers=internal())
    r = change(action="repair", vehicle=vid, price=150)
    assert r.json()["vehicles"][0]["wrecked"] is False and r.json()["balance"] == 850
    r = change(action="colour", vehicle=vid, colour="blue", price=50)
    assert r.json()["vehicles"][0]["colour"] == "blue"
    assert change(action="colour", vehicle=999, colour="x").status_code == 404
    assert change(action="explode", vehicle=vid).status_code == 400
    me = client.get("/v1/me", headers=auth(token)).json()
    assert me["vehicles"] == [{"id": vid, "model": "hatchback", "colour": "blue", "wrecked": False, "upgrades": {}}]
    c = db.connect()
    assert len(db.payments(c, account)) == 6    # start, buy, wreck, pay, repair, colour; the refused ones none


# ---------------------------------------------------------------- admin CLI and backups

def test_admin(client, capsys):
    token = signup(client).json()["token"]
    admin.main(["give", "gabriel", "1000", "beta tester"])
    admin.main(["take", "Gabriel", "500"])
    with pytest.raises(SystemExit):
        admin.main(["take", "Gabriel", "99999"])
    admin.main(["show", "Gabriel"])
    out = capsys.readouterr().out
    assert "Balance: 5500 €" in out and "beta tester" in out
    admin.main(["reset-password", "Gabriel", "--password", "a new password"])
    assert client.get("/v1/me", headers=auth(token)).status_code == 401
    assert client.post("/v1/login", json={"username": "Gabriel", "password": "a new password"}).status_code == 200
    admin.main(["rename", "Gabriel", "Gaby"])   # no 30-day wait for the admin
    assert client.post("/v1/login", json={"username": "Gaby", "password": "a new password"}).status_code == 200
    admin.main(["ban", "Gaby"])
    assert client.post("/v1/login", json={"username": "Gaby", "password": "a new password"}).status_code == 403
    admin.main(["unban", "Gaby"])
    assert client.post("/v1/login", json={"username": "Gaby", "password": "a new password"}).status_code == 200
    admin.main(["add-vehicle", "gaby", "audi-r8"])
    c = db.connect()
    row = db.find(c, "Gaby")
    assert [v["model"] for v in db.vehicles(c, row["id"])] == ["audi-r8"]
    assert db.balance(c, row["id"]) == 5500     # free
    with pytest.raises(SystemExit):
        admin.main(["show", "nobody"])


def test_backup(client, tmp_path):
    signup(client)
    out = tmp_path / "backups"
    for day in range(1, 17):
        assert backup.backup_now(db.path(), str(out), day=f"2026-11-{day:02d}") is not None
    assert backup.backup_now(db.path(), str(out), day="2026-11-16") is None    # one a day
    files = sorted(p.name for p in out.glob("accounts-*.db"))
    assert len(files) == 14 and files[0] == "accounts-2026-11-03.db"
    copy = sqlite3.connect(out / files[-1])
    assert copy.execute("SELECT username FROM accounts").fetchone()[0] == "Gabriel"
