#!/bin/sh
# The player capacity benchmark's server side (README.md), on the VPS, in a folder holding this script, make_accounts.py,
# plateau-bench (the ARM64 export template) and bench.pck. Takes the official server's place on UDP 7777 for the time of
# the test (no firewall change) with a throwaway accounts database: the live accounts are not touched.
#   vps_bench.sh prepare COUNT    throwaway accounts: writes tokens.json
#   vps_bench.sh up MAX [FLAGS]   stops plateau-server, starts the bench server for MAX players; logs in server.log
#   vps_bench.sh down             stops the bench server and starts plateau-server again
#   vps_bench.sh status           quick look: players on the official server, CPU and memory
set -u
here=$(cd "$(dirname "$0")" && pwd)
secret=bench-secret
accounts_image=$(docker inspect --format '{{.Image}}' plateau-accounts)
server_image=$(docker inspect --format '{{.Image}}' plateau-server)

case "${1:-}" in
prepare)
    rm -f "$here"/bench.db*
    docker run --rm -v "$here:/bench" -e PLATEAU_ACCOUNTS_DB=/bench/bench.db --entrypoint python "$accounts_image" \
        /bench/make_accounts.py "$2" sedan > "$here/tokens.json"
    wc -c "$here/tokens.json"
    ;;
up)
    max=$2
    shift 2
    docker stop plateau-server
    docker rm -f bench-accounts bench-server 2>/dev/null
    docker run -d --name bench-accounts --network host -v "$here:/bench" -e PLATEAU_ACCOUNTS_DB=/bench/bench.db \
        -e PLATEAU_SERVER_SECRET=$secret -e PLATEAU_BACKUP_DIR= --entrypoint python "$accounts_image" \
        -m uvicorn plateau_accounts.app:app --host 127.0.0.1 --port 8791
    docker run -d --name bench-server --network host -v "$here:/bench" -e HOME=/tmp \
        -e PLATEAU_ACCOUNTS_URL=http://127.0.0.1:8791 -e PLATEAU_SERVER_SECRET=$secret \
        --entrypoint /bench/plateau-bench "$server_image" \
        --main-pack /bench/bench.pck --headless -- --dedicated --official --port=7777 --max-players="$max" --stats "$@"
    : > "$here/server.log"
    (docker logs -f bench-server > "$here/server.log" 2>&1 &)
    echo "started: tail -f $here/server.log"
    ;;
down)
    docker rm -f bench-server bench-accounts
    docker start plateau-server
    ;;
status)
    docker logs --tail 3 plateau-server 2>&1 | cut -c1-150
    docker stats --no-stream --format '{{.Name}} cpu {{.CPUPerc}} mem {{.MemUsage}}'
    uptime
    ;;
*)
    sed -n 2,8p "$0"
    ;;
esac
