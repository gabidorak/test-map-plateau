#!/bin/sh
# Runs tools/test_lan_buses.gd as a host (with the bot buses) and a client on this machine at once; exits 1 when either
# fails. On port 7791, away from games running here (7777 up) and from test_lan.sh (7790).
cd "$(dirname "$0")/.." || exit 1
godot --headless --path . --script res://tools/test_lan_buses.gd -- --host --port=7791 --name=Host > /tmp/test_lan_buses_host.log 2>&1 &
host=$!
sleep 2
godot --headless --path . --script res://tools/test_lan_buses.gd -- --join=127.0.0.1:7791 --name=Guest > /tmp/test_lan_buses_client.log 2>&1
client=$?
wait $host
host=$?
grep -hE "^(ok|FAIL)" /tmp/test_lan_buses_host.log /tmp/test_lan_buses_client.log
grep -hE "SCRIPT ERROR|ERROR:" /tmp/test_lan_buses_host.log /tmp/test_lan_buses_client.log | sort | uniq -c | head -20
[ $host -eq 0 ] && [ $client -eq 0 ]
