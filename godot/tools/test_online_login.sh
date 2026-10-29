#!/bin/sh
# PTA Online logins (ONLINE_MILESTONES.md O2): a local accounts service (server/accounts, throwaway SQLite file, the
# repository's .venv: `pip install -r server/accounts/requirements.txt`), an official dedicated server on port 7796,
# and clients (tools/test_online_login.gd) that sign up and join as their username, join again with the kept login
# without typing, get kicked with a bad token or no login, and see clear messages with the accounts service or the game
# server down. The clients share a temporary home (their user://account.cfg). ~2 min. Exit 1 on failure.
cd "$(dirname "$0")/.." || exit 1
python="${PYTHON:-$(pwd)/../.venv/bin/python}"
tmp=/tmp/test_online_login
rm -rf "$tmp"
mkdir -p "$tmp/server_home" "$tmp/client_home"
secret=test-secret-$$
accounts_port=8796
ok=0

export PLATEAU_ACCOUNTS_URL="http://127.0.0.1:$accounts_port"
export PLATEAU_ONLINE_SERVER="127.0.0.1:7796"

start_accounts() {
    (cd ../server/accounts && PLATEAU_ACCOUNTS_DB="$tmp/accounts.db" PLATEAU_SERVER_SECRET="$secret" PLATEAU_BACKUP_DIR="" \
        exec "$python" -m uvicorn plateau_accounts.app:app --host 127.0.0.1 --port $accounts_port) \
        > "$tmp/accounts.log" 2>&1 &
    accounts=$!
    for i in $(seq 50); do
        curl -fs "$PLATEAU_ACCOUNTS_URL/v1/status" > /dev/null 2>&1 && return
        sleep 0.2
    done
    echo "FAIL the accounts service did not start (see $tmp/accounts.log)"
    exit 1
}

client() {   # client <log name> <args...>
    name=$1
    shift
    env -u XDG_DATA_HOME HOME="$tmp/client_home" godot --headless --path . --script res://tools/test_online_login.gd \
        -- "$@" > "$tmp/client_$name.log" 2>&1 || ok=1
    grep -hE "^(ok|FAIL)" "$tmp/client_$name.log"
}

client rules --rules
start_accounts
env -u XDG_DATA_HOME HOME="$tmp/server_home" PLATEAU_SERVER_SECRET="$secret" godot --headless --path . -- \
    --dedicated --official --port=7796 --no-bots > "$tmp/server.log" 2>&1 &
server=$!
for i in $(seq 120); do
    grep -q "Dedicated server" "$tmp/server.log" && break
    sleep 0.5
done
if grep -q "official PTA Online server" "$tmp/server.log"; then
    echo "ok   the server says it is the official one"
else
    echo "FAIL the server did not start as the official one"
    ok=1
fi

client signup --signup=Tester_1 --online
client remembered --remembered=Tester_1 --online
token=$(sed -n 's/^token="\(.*\)"$/\1/p' "$tmp/client_home/.local/share/godot/app_userdata/Plateau Map/account.cfg")
client bad_token --bad-token --online
client no_login --no-login --join=127.0.0.1:7796
kill $accounts
wait $accounts 2>/dev/null
client service_down --service-down="$token" --online
kill $server
wait $server 2>/dev/null
PLATEAU_ONLINE_SERVER="127.0.0.1:7797" client server_down --server-down --online

if grep -q "logged in as Tester_1" "$tmp/server.log"; then
    echo "ok   the server log has the login"
else
    echo "FAIL no login in the server log"
    ok=1
fi
grep -h "^Kicked" "$tmp/server.log"
grep -hE "SCRIPT ERROR" "$tmp"/*.log | sort | uniq -c | head -20
exit $ok
