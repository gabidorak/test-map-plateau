#!/bin/sh
# Runs tools/test_lan_races.gd as a host and a client on this machine at once (the client once the host has raced a lap
# alone); exits 1 when either fails. On port 7792, away from games running here (7777 up).
cd "$(dirname "$0")/.." || exit 1
rm -f /tmp/test_lan_races_ready
godot --headless --path . --script res://tools/test_lan_races.gd -- --host --port=7792 --name=Host \
    > /tmp/test_lan_races_host.log 2>&1 &
host=$!
for i in $(seq 1 120); do
    [ -f /tmp/test_lan_races_ready ] && break
    kill -0 $host 2>/dev/null || break
    sleep 0.5
done
godot --headless --path . --script res://tools/test_lan_races.gd -- --join=127.0.0.1:7792 --name=Guest \
    > /tmp/test_lan_races_client.log 2>&1
client=$?
wait $host
host=$?
grep -hE "^(ok|FAIL)" /tmp/test_lan_races_host.log /tmp/test_lan_races_client.log
grep -hE "SCRIPT ERROR|ERROR:" /tmp/test_lan_races_host.log /tmp/test_lan_races_client.log | sort | uniq -c | head -20
[ $host -eq 0 ] && [ $client -eq 0 ]
