#!/bin/sh
# PTA Online's police between an official server and a player: a local accounts service (server/accounts, throwaway
# SQLite file, the repository's .venv), an official dedicated server on port 7803 (its bot traffic on: cars to steal),
# and Thief_1 (tools/test_police_online.gd): steals a bot car, stays in it, is pulled out, tased, carried and arrested by
# the police; the accounts service logs the fine. ~4 min. Exit 1 on failure.
# GODOT: the Godot binary (default: godot on the PATH); PYTHON: the .venv's python (default: bin/ or Scripts/).
cd "$(dirname "$0")/.." || exit 1
godot="${GODOT:-godot}"
python="${PYTHON:-$(pwd)/../.venv/bin/python}"
[ -x "$python" ] || python="$(pwd)/../.venv/Scripts/python.exe"
tmp="${TMPDIR:-/tmp}/test_police_online"
rm -rf "$tmp"
mkdir -p "$tmp/server_home" "$tmp/client_home"
secret=test-secret-$$
accounts_port=8803
ok=0

export PLATEAU_ACCOUNTS_URL="http://127.0.0.1:$accounts_port"
export PLATEAU_ONLINE_SERVER="127.0.0.1:7803"

(cd ../server/accounts && PLATEAU_ACCOUNTS_DB="$tmp/accounts.db" PLATEAU_SERVER_SECRET="$secret" PLATEAU_BACKUP_DIR="" \
    exec "$python" -m uvicorn plateau_accounts.app:app --host 127.0.0.1 --port $accounts_port) > "$tmp/accounts.log" 2>&1 &
accounts=$!
for i in $(seq 50); do
    curl -fs "$PLATEAU_ACCOUNTS_URL/v1/status" > /dev/null 2>&1 && break
    sleep 0.2
done

token=$("$python" - <<'PY'
import json, os, urllib.request
url = os.environ["PLATEAU_ACCOUNTS_URL"]
req = urllib.request.Request(url + "/v1/signup", json.dumps({"username": "Thief_1",
                             "password": "a long test password"}).encode(),
                             {"Content-Type": "application/json", "Plateau-Api": "1"})
print(json.load(urllib.request.urlopen(req))["token"])
PY
)
if [ -z "$token" ]; then
    echo "FAIL could not make the account (see $tmp/accounts.log)"
    kill $accounts
    exit 1
fi

env -u XDG_DATA_HOME HOME="$tmp/server_home" PLATEAU_SERVER_SECRET="$secret" \
    "$godot" --headless --path . -- --dedicated --official --port=7803 > "$tmp/server.log" 2>&1 &
server=$!
for i in $(seq 180); do
    grep -q "Dedicated server" "$tmp/server.log" && break
    sleep 0.5
done

env -u XDG_DATA_HOME HOME="$tmp/client_home" "$godot" --headless --path . \
    --script res://tools/test_police_online.gd -- --client="$token" --online > "$tmp/client.log" 2>&1 || ok=1
grep -hE "^(ok|FAIL|     )" "$tmp/client.log"

kill $server $accounts
wait $server $accounts 2>/dev/null
if "$python" - "$tmp/accounts.db" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
rows = c.execute("SELECT amount, reason, job FROM payments WHERE job = 'fine' ORDER BY id").fetchall()
print("     fines:", rows)
sys.exit(0 if len(rows) == 1 and rows[0][0] == -1000 else 1)
PY
then
    echo "ok   the accounts service logged the fine"
else
    echo "FAIL the accounts service's fines aren't right"
    ok=1
fi
grep -hE "SCRIPT ERROR" "$tmp/server.log" "$tmp/client.log" | sort | uniq -c | head -10
exit $ok
