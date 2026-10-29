#!/bin/sh
# PTA Online rules and garages (ONLINE_MILESTONES.md O3): the solo checks (tools/test_online_rules.gd --check), then a
# local accounts service (server/accounts, throwaway SQLite file, the repository's .venv), an official dedicated server
# on port 7797 and two players: Owner_1 (a sedan, a taxi, a GAZ Tiger and a bus in their garage) and Other_1 (nothing).
# Owner_1 forges parks of armed vehicles and gets two vehicles out; Other_1 is refused the locked taxi, drives it once
# unlocked; Owner_1 leaves, comes back within 30 s (the taxi is theirs again), leaves for good: the taxi goes 30 s on.
# ~4 min. Exit 1 on failure.
cd "$(dirname "$0")/.." || exit 1
python="${PYTHON:-$(pwd)/../.venv/bin/python}"
tmp=/tmp/test_online_rules
rm -rf "$tmp"
mkdir -p "$tmp/server_home" "$tmp/owner_home" "$tmp/other_home" "$tmp/sync"
secret=test-secret-$$
accounts_port=8797
ok=0

export PLATEAU_ACCOUNTS_URL="http://127.0.0.1:$accounts_port"
export PLATEAU_ONLINE_SERVER="127.0.0.1:7797"

godot --headless --fixed-fps 60 --path . --script res://tools/test_online_rules.gd -- --check > "$tmp/check.log" 2>&1 || ok=1
grep -hE "^(ok|FAIL)" "$tmp/check.log"

(cd ../server/accounts && PLATEAU_ACCOUNTS_DB="$tmp/accounts.db" PLATEAU_SERVER_SECRET="$secret" PLATEAU_BACKUP_DIR="" \
    exec "$python" -m uvicorn plateau_accounts.app:app --host 127.0.0.1 --port $accounts_port) > "$tmp/accounts.log" 2>&1 &
accounts=$!
for i in $(seq 50); do
    curl -fs "$PLATEAU_ACCOUNTS_URL/v1/status" > /dev/null 2>&1 && break
    sleep 0.2
done

# api <name>: signs the account up, gives it the models after it, prints its token
api() {
    PLATEAU_SERVER_SECRET="$secret" "$python" - "$@" <<'EOF'
import json, os, sys, urllib.request
url, secret = os.environ["PLATEAU_ACCOUNTS_URL"], os.environ["PLATEAU_SERVER_SECRET"]
def call(path, body=None, server=False):
    h = {"Content-Type": "application/json", "Plateau-Api": "1"}
    if server:
        h["X-Server-Secret"] = secret
    req = urllib.request.Request(url + path, json.dumps(body).encode() if body is not None else None, h)
    return json.load(urllib.request.urlopen(req))
token = call("/v1/signup", {"username": sys.argv[1], "password": "a long test password"})["token"]
account = call("/v1/server/who?token=" + token, server=True)["account"]
for model in sys.argv[2:]:
    call("/v1/server/vehicle", {"account": account, "action": "add", "model": model}, server=True)
print(token)
EOF
}
owner=$(api Owner_1 sedan taxi gaz-tiger bus-idfm)
other=$(api Other_1)
if [ -z "$owner" ] || [ -z "$other" ]; then
    echo "FAIL could not make the accounts (see $tmp/accounts.log)"
    kill $accounts
    exit 1
fi

env -u XDG_DATA_HOME HOME="$tmp/server_home" PLATEAU_SERVER_SECRET="$secret" godot --headless --path . -- \
    --dedicated --official --port=7797 --no-bots > "$tmp/server.log" 2>&1 &
server=$!
for i in $(seq 120); do
    grep -q "Dedicated server" "$tmp/server.log" && break
    sleep 0.5
done
if grep -q "PTA Online, official PTA Online server" "$tmp/server.log"; then
    echo "ok   the official server plays PTA Online"
else
    echo "FAIL the server isn't the official PTA Online one: $(grep 'Dedicated server' "$tmp/server.log")"
    ok=1
fi

client() {   # client <home> <log name> <args...>
    home=$1
    name=$2
    shift 2
    env -u XDG_DATA_HOME HOME="$tmp/$home" godot --headless --path . --script res://tools/test_online_rules.gd \
        -- "$@" --online --sync="$tmp/sync" > "$tmp/client_$name.log" 2>&1
}

client other_home other --other="$other" &
other_pid=$!
client owner_home owner --owner="$owner" || ok=1
client owner_home back --back="$owner" || ok=1
wait $other_pid || ok=1
for name in owner other back; do
    grep -hE "^(ok|FAIL)" "$tmp/client_$name.log"
done

kill $server $accounts
wait $server $accounts 2>/dev/null
for line in "got their sedan out at telecom" "got their taxi out at telecom" "no gaz-tiger at telecom (Armed" \
        "no biplane-armed at telecom (Armed" "taxi left the map (owner gone 30 s)"; do
    if grep -q "$line" "$tmp/server.log"; then
        echo "ok   the server log has: $line"
    else
        echo "FAIL not in the server log: $line"
        ok=1
    fi
done
grep -hE "SCRIPT ERROR" "$tmp"/*.log | sort | uniq -c | head -20
exit $ok
