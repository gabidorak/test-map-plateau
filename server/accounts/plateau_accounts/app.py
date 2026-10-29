"""PTA Online accounts service (ONLINE_MODE.md 3, ONLINE_MILESTONES.md O1).

Public API, for the game (HTTPS through Caddy): sign up, log in, log out (this token or all), me, rename. The game
sends `Authorization: Bearer <token>` and `Plateau-Api: <n>`; a game older than MIN_CLIENT_API gets 426 and a message
asking to update.
Internal API, for the official game server only (Docker network; Caddy refuses /v1/server/*): who is this token, pay,
charge, change a vehicle. Each call carries `X-Server-Secret`, compared with PLATEAU_SERVER_SECRET (no secret set: the
internal API is off). Money only moves here, and every change writes a `payments` row.
Errors are {"error": code, "message": text to show, ...} with the HTTP status (db.Refused)."""

import hmac
import os
import sqlite3
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

from . import backup, db

API = 1                                 # this service's API version
MIN_CLIENT_API = 1                      # games sending an older Plateau-Api are asked to update


@asynccontextmanager
async def lifespan(_app: FastAPI):
    conn = db.connect()
    db.init(conn)
    conn.close()
    backup.start(db.path())
    yield


app = FastAPI(title="PTA Online accounts", lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)
# The client's address (the sign-up limit) from X-Forwarded-For: only Caddy and the game server reach the service (its
# port is published on 127.0.0.1 only), and Caddy replaces the header a player sends with their real address.
app.add_middleware(ProxyHeadersMiddleware, trusted_hosts="*")


@app.exception_handler(db.Refused)
async def _refused(_request: Request, e: db.Refused) -> JSONResponse:
    return JSONResponse({"error": e.code, "message": e.message, **e.extra}, status_code=e.status)


@app.middleware("http")
async def _client_api(request: Request, call_next):
    api = request.headers.get("plateau-api", "")
    if api.isdigit() and int(api) < MIN_CLIENT_API:
        return JSONResponse({"error": "update", "message": "This version of the game is too old for PTA Online: "
                             "restart it to update."}, status_code=426)
    return await call_next(request)


def conn():
    c = db.connect()
    try:
        yield c
    finally:
        c.close()


def _account(c: sqlite3.Connection, authorization: str) -> sqlite3.Row:
    token = authorization.removeprefix("Bearer ").strip()
    row = db.account_of(c, token)
    if row is None:
        raise db.Refused(401, "token", "Logged out: log in again.")
    if row["banned"]:
        raise db.Refused(403, "banned", "This account is banned.")
    return row


def _me(c: sqlite3.Connection, row: sqlite3.Row) -> dict:
    return {"username": row["username"], "balance": db.balance(c, row["id"]), "vehicles": db.vehicles(c, row["id"]),
            "created": row["created"], "next_rename": db.next_rename(row)}


class Credentials(BaseModel):
    username: str
    password: str


class NewName(BaseModel):
    username: str


@app.get("/v1/status")
def status() -> dict:
    return {"api": API, "min_client_api": MIN_CLIENT_API}


@app.post("/v1/signup")
def signup(body: Credentials, request: Request, c=Depends(conn)) -> dict:
    ip = request.client.host if request.client else ""
    account, token = db.signup(c, body.username, body.password, ip)
    row = c.execute("SELECT * FROM accounts WHERE id = ?", (account,)).fetchone()
    return {"token": token, **_me(c, row)}


@app.post("/v1/login")
def login(body: Credentials, c=Depends(conn)) -> dict:
    account, token = db.login(c, body.username, body.password)
    row = c.execute("SELECT * FROM accounts WHERE id = ?", (account,)).fetchone()
    return {"token": token, **_me(c, row)}


@app.post("/v1/logout")
def logout(authorization: str = Header(""), c=Depends(conn)) -> dict:
    db.logout(c, authorization.removeprefix("Bearer ").strip())
    return {}


@app.post("/v1/logout-all")
def logout_all(authorization: str = Header(""), c=Depends(conn)) -> dict:
    db.logout_all(c, _account(c, authorization)["id"])
    return {}


@app.get("/v1/me")
def me(authorization: str = Header(""), c=Depends(conn)) -> dict:
    return _me(c, _account(c, authorization))


@app.post("/v1/rename")
def rename(body: NewName, authorization: str = Header(""), c=Depends(conn)) -> dict:
    row = _account(c, authorization)
    db.rename(c, row["id"], body.username)
    return _me(c, c.execute("SELECT * FROM accounts WHERE id = ?", (row["id"],)).fetchone())


# ---------------------------------------------------------------- internal (official game server)

def server(x_server_secret: str = Header("")) -> None:
    secret = os.environ.get("PLATEAU_SERVER_SECRET", "")
    if not secret or not hmac.compare_digest(x_server_secret.encode(), secret.encode()):
        raise db.Refused(403, "secret", "Not the official server.")


def _owner(c: sqlite3.Connection, account: int) -> sqlite3.Row:
    row = c.execute("SELECT * FROM accounts WHERE id = ?", (account,)).fetchone()
    if row is None:
        raise db.Refused(404, "no_account", "No such account.")
    return row


class Money(BaseModel):
    account: int
    amount: int
    reason: str
    job: str = ""
    cap: int = 0                        # pay: job earnings per hour at most (db.earn), 0 none


class VehicleChange(BaseModel):
    account: int
    action: str                         # add, repair, wreck, colour
    vehicle: int = 0                    # all but add
    model: str = ""                     # add
    colour: str = ""                    # add, colour
    price: int = 0                      # charged in the same transaction


@app.get("/v1/server/who", dependencies=[Depends(server)])
def who(token: str = "", c=Depends(conn)) -> dict:
    row = db.account_of(c, token)
    if row is None:
        raise db.Refused(404, "token", "Not logged in: log in again from PTA Online.")
    if row["banned"]:
        raise db.Refused(403, "banned", "This account is banned.")
    return {"account": row["id"], **_me(c, row)}


@app.post("/v1/server/pay", dependencies=[Depends(server)])
def pay(body: Money, c=Depends(conn)) -> dict:
    _owner(c, body.account)
    if body.cap > 0:
        return db.earn(c, body.account, body.amount, body.reason, body.job, body.cap)
    return {"balance": db.pay(c, body.account, body.amount, body.reason, body.job)}


@app.post("/v1/server/charge", dependencies=[Depends(server)])
def charge(body: Money, c=Depends(conn)) -> dict:
    _owner(c, body.account)
    return {"balance": db.charge(c, body.account, body.amount, body.reason, body.job)}


@app.post("/v1/server/vehicle", dependencies=[Depends(server)])
def vehicle(body: VehicleChange, c=Depends(conn)) -> dict:
    _owner(c, body.account)
    done = db.vehicle_change(c, body.account, body.action, body.price, body.vehicle, body.model, body.colour)
    return {**done, "vehicles": db.vehicles(c, body.account)}
