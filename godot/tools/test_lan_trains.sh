#!/bin/sh
# Runs tools/test_lan_trains.gd as a host (running the RER B trains) and a client on this machine at once; exits 1 when
# either fails. On port 7793, away from games running here (7777 up) and from the other LAN tests (7790, 7791, 7792).
cd "$(dirname "$0")/.." || exit 1
GODOT=${GODOT:-godot}
LOGS=${TMPDIR:-/tmp}
$GODOT --headless --path . --script res://tools/test_lan_trains.gd -- --host --port=7793 --name=Host > "$LOGS/test_lan_trains_host.log" 2>&1 &
host=$!
sleep 2
$GODOT --headless --path . --script res://tools/test_lan_trains.gd -- --join=127.0.0.1:7793 --name=Guest > "$LOGS/test_lan_trains_client.log" 2>&1
client=$?
wait $host
host=$?
grep -hE "^(ok|FAIL)" "$LOGS/test_lan_trains_host.log" "$LOGS/test_lan_trains_client.log"
grep -hE "SCRIPT ERROR|ERROR:" "$LOGS/test_lan_trains_host.log" "$LOGS/test_lan_trains_client.log" | sort | uniq -c | head -20
[ $host -eq 0 ] && [ $client -eq 0 ]
