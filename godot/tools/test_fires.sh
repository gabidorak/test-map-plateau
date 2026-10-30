#!/bin/sh
# PTA Online's fires and firefighter job (ONLINE_MILESTONES.md O7): the solo checks (tools/test_fires.gd --check), then a
# local accounts service (server/accounts, throwaway SQLite file, the repository's .venv), an official dedicated server on
# port 7801 lighting its alarms at the building spot nearest the fire station (PLATEAU_FIRE_SPOT=building), and
# Firefighter_1: on duty at the fire station, they see the fire, hose it out with the lent truck's jet (flown again on the
# server from the truck's state) and are paid by the accounts service. ~3 min. Exit 1 on failure.
cd "$(dirname "$0")/.." || exit 1
python="${PYTHON:-$(pwd)/../.venv/bin/python}"
tmp=/tmp/test_fires
rm -rf "$tmp"
mkdir -p "$tmp/server_home" "$tmp/client_home"
secret=test-secret-$$
accounts_port=8801
ok=0

export PLATEAU_ACCOUNTS_URL="http://127.0.0.1:$accounts_port"
export PLATEAU_ONLINE_SERVER="127.0.0.1:7801"

if [ "$1" != "--lan-only" ]; then
    godot --headless --fixed-fps 60 --path . --script res://tools/test_fires.gd -- --check > "$tmp/check.log" 2>&1 || ok=1
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
url = os.environ["PLATEAU_ACCOUNTS_URL"]
req = urllib.request.Request(url + "/v1/signup", json.dumps({"username": "Firefighter_1",
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

env -u XDG_DATA_HOME HOME="$tmp/server_home" PLATEAU_SERVER_SECRET="$secret" PLATEAU_FIRE_SPOT=building \
    PLATEAU_FIRE_FIRST=2 godot --headless --path . -- --dedicated --official --port=7801 --no-bots \
    > "$tmp/server.log" 2>&1 &
server=$!
for i in $(seq 180); do
    grep -q "Dedicated server" "$tmp/server.log" && break
    sleep 0.5
done

env -u XDG_DATA_HOME HOME="$tmp/client_home" godot --headless --path . \
    --script res://tools/test_fires.gd -- --client="$token" --online > "$tmp/client.log" 2>&1 || ok=1
grep -hE "^(ok|FAIL|     )" "$tmp/client.log"

kill $server $accounts
wait $server $accounts 2>/dev/null
for line in "Firefighter_1 is on duty as a firefighter" "Fire 1 (Building fire" "put out after"; do
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
rows = c.execute("SELECT amount, reason, job FROM payments WHERE job = 'fire' ORDER BY id").fetchall()
print("     fire payments:", rows)
sys.exit(0 if len(rows) >= 1 and rows[0][0] > 0 and "Building fire" in rows[0][1] else 1)
PY
then
    echo "ok   the accounts service logged the fire's pay"
else
    echo "FAIL the accounts service's payments aren't right"
    ok=1
fi
grep -hE "SCRIPT ERROR" "$tmp"/*.log | sort | uniq -c | head -20
exit $ok
