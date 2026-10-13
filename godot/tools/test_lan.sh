#!/bin/sh
# Runs tools/test_lan.gd as a host and a client on this machine at once; exits 1 when either fails. On port 7790,
# away from games running here (7777 up).
cd "$(dirname "$0")/.." || exit 1
godot --headless --path . --script res://tools/test_lan.gd -- --host --port=7790 --name=Host > /tmp/test_lan_host.log 2>&1 &
host=$!
sleep 2
godot --headless --path . --script res://tools/test_lan.gd -- --join=127.0.0.1:7790 --name=Guest > /tmp/test_lan_client.log 2>&1
client=$?
wait $host
host=$?
grep -hE "^(ok|FAIL)" /tmp/test_lan_host.log /tmp/test_lan_client.log
grep -hE "SCRIPT ERROR|ERROR:" /tmp/test_lan_host.log /tmp/test_lan_client.log | sort | uniq -c | head -20
[ $host -eq 0 ] && [ $client -eq 0 ]
