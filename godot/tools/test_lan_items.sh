#!/bin/sh
# Runs tools/test_lan_items.gd as a host and a client on this machine at once; exits 1 when either fails. On port 7791,
# away from games running here (7777 up) and from test_lan.sh (7790). GODOT: the Godot binary (default: godot on the
# PATH).
cd "$(dirname "$0")/.." || exit 1
GODOT=${GODOT:-godot}
logs=${TMPDIR:-/tmp}
"$GODOT" --headless --path . --script res://tools/test_lan_items.gd -- --host --port=7791 --name=Host > "$logs/test_lan_items_host.log" 2>&1 &
host=$!
sleep 2
"$GODOT" --headless --path . --script res://tools/test_lan_items.gd -- --join=127.0.0.1:7791 --name=Guest > "$logs/test_lan_items_client.log" 2>&1
client=$?
wait $host
host=$?
grep -hE "^(ok|FAIL)" "$logs/test_lan_items_host.log" "$logs/test_lan_items_client.log"
grep -hE "SCRIPT ERROR|ERROR:" "$logs/test_lan_items_host.log" "$logs/test_lan_items_client.log" | sort | uniq -c | head -20
[ $host -eq 0 ] && [ $client -eq 0 ]
