#!/bin/sh
# PTA Online's stunts (ONLINE_MILESTONES.md O6): the solo checks (tools/test_stunts.gd --check), then a local accounts
# service (server/accounts, throwaway SQLite file, the repository's .venv), an official dedicated server on port 7800,
# and Stunter_1 with a sedan in their garage: they jump the best stunt spot twice (judged on the server,
# paid by the accounts service: the first-time reward, then a small one). ~3 min. Exit 1 on failure.
cd "$(dirname "$0")/.." || exit 1
python="${PYTHON:-$(pwd)/../.venv/bin/python}"
tmp=/tmp/test_stunts
rm -rf "$tmp"
mkdir -p "$tmp/server_home" "$tmp/client_home"
secret=test-secret-$$
accounts_port=8800
ok=0

export PLATEAU_ACCOUNTS_URL="http://127.0.0.1:$accounts_port"
export PLATEAU_ONLINE_SERVER="127.0.0.1:7800"

if [ "$1" != "--lan-only" ]; then
    godot --headless --fixed-fps 60 --path . --script res://tools/test_stunts.gd -- --check > "$tmp/check.log" 2>&1 || ok=1
    grep -hE "^(ok|FAIL|     )" "$tmp/check.log"
fi

(cd ../server/accounts && PLATEAU_ACCOUNTS_DB="$tmp/accounts.db" PLATEAU_SERVER_SECRET="$secret" PLATEAU_BACKUP_DIR="" \
    exec "$python" -m uvicorn plateau_accounts.app:app --host 127.0.0.1 --port $accounts_port) > "$tmp/accounts.log" 2>&1 &
accounts=$!
for i in $(seq 50); do
    curl -fs "$PLATEAU_ACCOUNTS_URL/v1/status" > /dev/null 2>&1 && break
    sleep 0.2
done

token=$(PLATEAU_SERVER_SECRET="$secret" "$python" - <<'PY'
import json, os, urllib.request
url, secret = os.environ["PLATEAU_ACCOUNTS_URL"], os.environ["PLATEAU_SERVER_SECRET"]
def call(path, body=None, server=False):
    h = {"Content-Type": "application/json", "Plateau-Api": "1"}
    if server:
        h["X-Server-Secret"] = secret
    req = urllib.request.Request(url + path, json.dumps(body).encode() if body is not None else None, h)
    return json.load(urllib.request.urlopen(req))
token = call("/v1/signup", {"username": "Stunter_1", "password": "a long test password"})["token"]
account = call("/v1/server/who?token=" + token, server=True)["account"]
call("/v1/server/vehicle", {"account": account, "action": "add", "model": "sedan"}, server=True)
print(token)
PY
)
if [ -z "$token" ]; then
    echo "FAIL could not make the account (see $tmp/accounts.log)"
    kill $accounts
    exit 1
fi

env -u XDG_DATA_HOME HOME="$tmp/server_home" PLATEAU_SERVER_SECRET="$secret" godot --headless --path . -- \
    --dedicated --official --port=7800 --no-bots > "$tmp/server.log" 2>&1 &
server=$!
for i in $(seq 180); do
    grep -q "Dedicated server" "$tmp/server.log" && break
    sleep 0.5
done

env -u XDG_DATA_HOME HOME="$tmp/client_home" godot --headless --path . \
    --script res://tools/test_stunts.gd -- --client="$token" --online > "$tmp/client.log" 2>&1 || ok=1
grep -hE "^(ok|FAIL|     )" "$tmp/client.log"

kill $server $accounts
wait $server $accounts 2>/dev/null
for line in "Stunter_1 got their sedan out at telecom" "(first time!)"; do
    if grep -qF "$line" "$tmp/server.log"; then
        echo "ok   the server log has: $line"
    else
        echo "FAIL not in the server log: $line"
        ok=1
    fi
done
if "$python" - "$tmp/accounts.db" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
rows = c.execute("SELECT amount, reason, job FROM payments WHERE job = 'stunts' ORDER BY id").fetchall()
firsts = c.execute("SELECT key FROM firsts").fetchall()
print("     stunt payments:", rows, "firsts:", firsts)
sys.exit(0 if len(rows) >= 2 and rows[0][1].endswith("(first)") and len(firsts) == 1 else 1)
PY
then
    echo "ok   the accounts service logged the first-time reward and a second payment, one spot done"
else
    echo "FAIL the accounts service's payments aren't right"
    ok=1
fi
grep -hE "SCRIPT ERROR" "$tmp"/*.log | sort | uniq -c | head -20
exit $ok
