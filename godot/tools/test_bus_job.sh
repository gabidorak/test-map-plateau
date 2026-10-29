#!/bin/sh
# PTA Online's bus job (ONLINE_MILESTONES.md O5): the solo checks (tools/test_bus_job.gd --check), then a local accounts
# service (server/accounts, throwaway SQLite file, the repository's .venv), an official dedicated server on port 7799
# with its bot traffic, and two players: Driver_1 goes on duty on the 4606 in the depot's lent bus (a bot bus of the
# line leaves the map on both screens), serves the first stop (paid by the accounts service) and leaves; Watcher_1 sees
# the bot bus come back. ~6 min. Exit 1 on failure.
cd "$(dirname "$0")/.." || exit 1
python="${PYTHON:-$(pwd)/../.venv/bin/python}"
tmp=/tmp/test_bus_job
rm -rf "$tmp"
mkdir -p "$tmp/server_home" "$tmp/driver_home" "$tmp/watcher_home" "$tmp/sync"
secret=test-secret-$$
accounts_port=8799
ok=0

export PLATEAU_ACCOUNTS_URL="http://127.0.0.1:$accounts_port"
export PLATEAU_ONLINE_SERVER="127.0.0.1:7799"

if [ "$1" != "--lan-only" ]; then
    godot --headless --fixed-fps 60 --path . --script res://tools/test_bus_job.gd -- --check > "$tmp/check.log" 2>&1 || ok=1
    grep -hE "^(ok|FAIL|     )" "$tmp/check.log"
fi

(cd ../server/accounts && PLATEAU_ACCOUNTS_DB="$tmp/accounts.db" PLATEAU_SERVER_SECRET="$secret" PLATEAU_BACKUP_DIR="" \
    exec "$python" -m uvicorn plateau_accounts.app:app --host 127.0.0.1 --port $accounts_port) > "$tmp/accounts.log" 2>&1 &
accounts=$!
for i in $(seq 50); do
    curl -fs "$PLATEAU_ACCOUNTS_URL/v1/status" > /dev/null 2>&1 && break
    sleep 0.2
done

# signup <name>: signs the account up, prints its token
signup() {
    "$python" - "$@" <<'EOF'
import json, os, sys, urllib.request
req = urllib.request.Request(os.environ["PLATEAU_ACCOUNTS_URL"] + "/v1/signup",
                             json.dumps({"username": sys.argv[1], "password": "a long test password"}).encode(),
                             {"Content-Type": "application/json", "Plateau-Api": "1"})
print(json.load(urllib.request.urlopen(req))["token"])
EOF
}
driver=$(signup Driver_1)
watcher=$(signup Watcher_1)
if [ -z "$driver" ] || [ -z "$watcher" ]; then
    echo "FAIL could not make the accounts (see $tmp/accounts.log)"
    kill $accounts
    exit 1
fi

env -u XDG_DATA_HOME HOME="$tmp/server_home" PLATEAU_SERVER_SECRET="$secret" godot --headless \
    --path . -- --dedicated --official --port=7799 > "$tmp/server.log" 2>&1 &
server=$!
for i in $(seq 180); do
    grep -q "Dedicated server" "$tmp/server.log" && break
    sleep 0.5
done

client() {   # client <home> <log name> <args...>
    home=$1
    name=$2
    shift 2
    env -u XDG_DATA_HOME HOME="$tmp/$home" godot --headless --path . \
        --script res://tools/test_bus_job.gd -- "$@" --online --sync="$tmp/sync" > "$tmp/client_$name.log" 2>&1
}

client watcher_home watcher --watcher="$watcher" &
watcher_pid=$!
client driver_home driver --driver="$driver" || ok=1
wait $watcher_pid || ok=1
for name in driver watcher; do
    grep -hE "^(ok|FAIL|     )" "$tmp/client_$name.log"
done

kill $server $accounts
wait $server $accounts 2>/dev/null
for line in "Driver_1 is on duty on line 4606 (a lent bus-idfm-artic), bot bus" \
        "Driver_1 served Gare de Massy - Palaiseau (line 4606): 90 €" "Driver_1 is off duty (left the game)"; do
    if grep -qF "$line" "$tmp/server.log"; then
        echo "ok   the server log has: $line"
    else
        echo "FAIL not in the server log: $line"
        ok=1
    fi
done
# the bot bus comes back where its timetable has it (the watcher sees it), or at its next departure (nobody sees it)
seen=$(cat "$tmp/sync/watcher_back" 2>/dev/null)
if grep -q "off duty (left the game).*back on the map" "$tmp/server.log"; then
    if [ "$seen" = "yes" ]; then
        echo "ok   the held bot bus is back on the map, on the watcher's screen too"
    else
        echo "FAIL the server put the held bot bus back on the map, the watcher didn't see it"
        ok=1
    fi
elif grep -q "off duty (left the game).*back at its next departure" "$tmp/server.log"; then
    echo "ok   the held bot bus comes back at its line's next departure (its timetable's place was in sight)"
else
    echo "FAIL the server didn't say where the held bot bus went"
    ok=1
fi
grep -hE "SCRIPT ERROR" "$tmp"/*.log | sort | uniq -c | head -20
exit $ok
