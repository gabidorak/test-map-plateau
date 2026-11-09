#!/bin/sh
# PTA Online's properties with two players (ONLINE_MILESTONES.md O9): a local accounts service (server/accounts,
# throwaway SQLite file, the repository's .venv), an official dedicated server on port 7799 whose PLATEAU_ONLINE_HOMES
# gives Owner_1 the studio of the Logements de l'X 19 with its garage, and two players (tools/test_properties_online.gd):
# Owner_1 goes in, the visitor outside no longer sees them; the visitor is refused the locked flat, visits it once
# opened (they see each other there), the owner leaves by the lift at the wheel of their sedan. ~3 min. Exit 1 on
# failure.
#   GODOT=path/to/godot tools/test_properties_online.sh
cd "$(dirname "$0")/.." || exit 1
godot="${GODOT:-godot}"
if [ -z "$PYTHON" ]; then
    PYTHON="$(pwd)/../.venv/bin/python"
    [ -x "$PYTHON" ] || PYTHON="$(pwd)/../.venv/Scripts/python.exe"
fi
tmp="${TMPDIR:-/tmp}/test_properties_online"
rm -rf "$tmp"
mkdir -p "$tmp/server_home" "$tmp/owner_home" "$tmp/visitor_home" "$tmp/sync"
secret=test-secret-$$
accounts_port=8799
ok=0

export PLATEAU_ACCOUNTS_URL="http://127.0.0.1:$accounts_port"
export PLATEAU_ONLINE_SERVER="127.0.0.1:7799"

(cd ../server/accounts && PLATEAU_ACCOUNTS_DB="$tmp/accounts.db" PLATEAU_SERVER_SECRET="$secret" PLATEAU_BACKUP_DIR="" \
    exec "$PYTHON" -m uvicorn plateau_accounts.app:app --host 127.0.0.1 --port $accounts_port) > "$tmp/accounts.log" 2>&1 &
accounts=$!
for i in $(seq 50); do
    curl -fs "$PLATEAU_ACCOUNTS_URL/v1/status" > /dev/null 2>&1 && break
    sleep 0.2
done

# api <name>: signs the account up, gives it the models after it, prints its token
api() {
    PLATEAU_SERVER_SECRET="$secret" "$PYTHON" - "$@" <<'EOF'
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
owner=$(api Owner_1 sedan | tr -d '\r')
visitor=$(api Visitor_1 | tr -d '\r')
if [ -z "$owner" ] || [ -z "$visitor" ]; then
    echo "FAIL could not make the accounts (see $tmp/accounts.log)"
    kill $accounts
    exit 1
fi

HOME="$tmp/server_home" PLATEAU_SERVER_SECRET="$secret" PLATEAU_ONLINE_HOMES="Owner_1=logx-19-studio+garage" \
    "$godot" --headless --path . -- --dedicated --official --port=7799 --no-bots > "$tmp/server.log" 2>&1 &
server=$!
for i in $(seq 120); do
    grep -q "Dedicated server" "$tmp/server.log" && break
    sleep 0.5
done

client() {   # client <home> <args...>
    home=$1
    shift
    HOME="$tmp/$home" "$godot" --headless --path . --script res://tools/test_properties_online.gd \
        -- "$@" --online --sync="$tmp/sync" > "$tmp/client_$home.log" 2>&1
}

client visitor_home --visitor="$visitor" &
visitor_pid=$!
client owner_home --owner="$owner" || ok=1
wait $visitor_pid || ok=1
for home in owner_home visitor_home; do
    grep -hE "^(ok|FAIL)" "$tmp/client_$home.log"
done
kill $server $accounts
wait $server $accounts 2>/dev/null
grep -hE "SCRIPT ERROR" "$tmp"/*.log | sort | uniq -c | head -20
exit $ok
