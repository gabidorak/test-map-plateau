#!/bin/sh
# PTA Online's shop, repairs and colours (ONLINE_MILESTONES.md O4): the solo checks (tools/test_online_shop.gd --check),
# then a local accounts service (server/accounts, throwaway SQLite file, the repository's .venv), an official
# dedicated server on port 7798 and three players: Buyer_1 (a new account: 5 000 €) buys the cheapest car, is refused
# the next one and purchases forged from afar, wrecks the car, is paid 10 000 € (the internal API), pays its repair
# and paints it red; Watcher_1 sees it red; a client with a made-up login asks to buy, repair and paint before it is
# kicked. ~4 min. Exit 1 on failure.
cd "$(dirname "$0")/.." || exit 1
python="${PYTHON:-$(pwd)/../.venv/bin/python}"
tmp=/tmp/test_online_shop
rm -rf "$tmp"
mkdir -p "$tmp/server_home" "$tmp/buyer_home" "$tmp/watcher_home" "$tmp/forger_home" "$tmp/sync"
secret=test-secret-$$
accounts_port=8798
ok=0

export PLATEAU_ACCOUNTS_URL="http://127.0.0.1:$accounts_port"
export PLATEAU_ONLINE_SERVER="127.0.0.1:7798"

godot --headless --fixed-fps 60 --path . --script res://tools/test_online_shop.gd -- --check > "$tmp/check.log" 2>&1 || ok=1
grep -hE "^(ok|FAIL)" "$tmp/check.log"

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
buyer=$(signup Buyer_1)
watcher=$(signup Watcher_1)
if [ -z "$buyer" ] || [ -z "$watcher" ]; then
    echo "FAIL could not make the accounts (see $tmp/accounts.log)"
    kill $accounts
    exit 1
fi

env -u XDG_DATA_HOME HOME="$tmp/server_home" PLATEAU_SERVER_SECRET="$secret" PLATEAU_ONLINE_TOW=3 godot --headless \
    --path . -- --dedicated --official --port=7798 --no-bots > "$tmp/server.log" 2>&1 &
server=$!
for i in $(seq 120); do
    grep -q "Dedicated server" "$tmp/server.log" && break
    sleep 0.5
done

client() {   # client <home> <log name> <args...>
    home=$1
    name=$2
    shift 2
    env -u XDG_DATA_HOME HOME="$tmp/$home" PLATEAU_TEST_SECRET="$secret" godot --headless --path . \
        --script res://tools/test_online_shop.gd -- "$@" --online --sync="$tmp/sync" > "$tmp/client_$name.log" 2>&1
}

client forger_home forger --forger || ok=1
client watcher_home watcher --watcher="$watcher" &
watcher_pid=$!
client buyer_home buyer --buyer="$buyer" || ok=1
wait $watcher_pid || ok=1
for name in forger buyer watcher; do
    grep -hE "^(ok|FAIL)" "$tmp/client_$name.log"
done

kill $server $accounts
wait $server $accounts 2>/dev/null
for line in "no kaykit-hatchback bought at prestige (Not logged in.)" "Buyer_1 bought a kaykit-hatchback for 5000 €" \
        "no horse bought at prestige (Not enough money" "no kaykit-hatchback bought at prestige (Walk into" \
        "Buyer_1's kaykit-hatchback is wrecked" "Buyer_1 repaired their kaykit-hatchback for 150 €" \
        "Buyer_1 painted their kaykit-hatchback red for 200 €"; do
    if grep -qF "$line" "$tmp/server.log"; then
        echo "ok   the server log has: $line"
    else
        echo "FAIL not in the server log: $line"
        ok=1
    fi
done
if grep -q "bought" "$tmp/server.log" && [ "$(grep -c " bought a " "$tmp/server.log")" -ne 1 ]; then
    echo "FAIL the server sold more than one vehicle: $(grep " bought a " "$tmp/server.log")"
    ok=1
fi
grep -hE "SCRIPT ERROR" "$tmp"/*.log | sort | uniq -c | head -20
exit $ok
