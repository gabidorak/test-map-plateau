#!/bin/sh
# A dedicated server's race records outlive its restarts (server/: Docker restarts it at each update, and its user://
# lives in the /data volume, the container user's home). A dedicated server with its home in a temporary folder takes
# the time a client races (tools/test_server_records.gd --race), is killed, starts again, and still sends that time to
# a client joining (--check). Port 7794; ~1 min (the shortest bus race time the server accepts is ~30 s). Exit 1 on
# failure.
cd "$(dirname "$0")/.." || exit 1
home=/tmp/test_server_records_home
records="$home/.local/share/godot/app_userdata/Plateau Map/race_records.json"
rm -rf "$home"
mkdir -p "$home"
ok=0

serve() {
    env -u XDG_DATA_HOME HOME="$home" godot --headless --path . -- --dedicated --port=7794 > "/tmp/test_server_records_$1.log" 2>&1 &
    server=$!
    sleep 4
}

serve 1
godot --headless --path . --script res://tools/test_server_records.gd -- --join=127.0.0.1:7794 --name=Racer --race \
    > /tmp/test_server_records_race.log 2>&1 || ok=1
kill -9 $server
wait $server 2>/dev/null
if [ -f "$records" ] && grep -q Racer "$records"; then
    echo "ok   the records file is in the server's home: $records"
else
    echo "FAIL no records file with the time at $records"
    ok=1
fi
serve 2
godot --headless --path . --script res://tools/test_server_records.gd -- --join=127.0.0.1:7794 --name=Viewer --check \
    > /tmp/test_server_records_check.log 2>&1 || ok=1
kill $server
wait $server 2>/dev/null
grep -hE "^(ok|FAIL)" /tmp/test_server_records_race.log /tmp/test_server_records_check.log
grep -hE "SCRIPT ERROR|ERROR:" /tmp/test_server_records_*.log | sort | uniq -c | head -20
grep -h "^Race:" /tmp/test_server_records_1.log
exit $ok
