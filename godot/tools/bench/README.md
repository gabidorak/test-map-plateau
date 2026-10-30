# Player capacity benchmark

How many players a dedicated server takes: a swarm of bots playing PTA Online over the real protocol (real login, garage,
real ENet RPCs) against a real server, ramped up while the server reports how it copes.

- `swarm.gd`: one process, many bots (no game loaded: about 150 MB per process). Their RPC stubs are generated from the real
  scripts' `@rpc` lines, so the swarm follows protocol changes by itself.
- `run_swarm.py`: runs several swarm processes, one stage of players after another, and prints a table per stage.
- `make_routes.gd`: the routes they drive. `make_accounts.py`: throwaway accounts, in a throwaway database.
- `scripts/server_stats.gd` (`--stats`, with `--max-players=N`; both dedicated server options): one JSON line every 5 s.
- `vps_bench.sh`: the server side on a VPS, with an exported pack, replacing the official server for the time of the test.

## Reading the table

| column | meaning | healthy |
|---|---|---|
| `tps` | physics ticks per second | 60 |
| `cpu_main` | the server's main thread, in cores | under ~0.8: everything game and network runs on it |
| `tick_avg/p99` | ms of scripts per tick | under 16.7 |
| `delivered` | share of the other bots' player states received, % | ~100 |
| `relay_p50/p99` | ms from a bot through the server to another bot | stays near the idle value |
| `lost` | bots dropped or kicked | 0 |
| `traffic_level` | how far the adaptive bot traffic thinned out (0 to 3) | |
| `sent_mbit` | the server's upload | under the link |
| `swarm_slow` | % of slow swarm frames: over a few %, the swarm itself was too slow and the run says nothing | ~0 |

Watch `/proc/net/udp6`'s `drops` column on the server's port too: reliable messages lost there time clients out in batches.

## Running it

```sh
S=some/folder
godot --headless --path godot --script res://tools/bench/make_routes.gd -- $S/routes.json
godot --headless --path godot --export-pack Linux $S/bench.pck
# on the VPS: bench.pck, the linux_release.arm64 export template as plateau-bench, vps_bench.sh, make_accounts.py
./vps_bench.sh prepare 100 && ./vps_bench.sh up 100
# here, with tokens.json copied from the VPS and server.log copied back afterwards for the server's columns
python3 godot/tools/bench/run_swarm.py --server HOST:7777 --tokens tokens.json --routes $S/routes.json \
    --stages 1,8,16,24,32,48,64 --hold 60 --procs 10 --out $S/run1
./vps_bench.sh down
```

## Results: what a player costs in bandwidth (laptop, server on 2 pinned cores, 2026-10-30)

Old relay and new one, one after the other in the same state of the machine (its speed varies by 2x between sessions: only
compare runs made together). Before: every state to every player, as Variant arrays. Now: `net_codec.gd` bytes, by distance
(`net.gd` `_relay_out`), and the trains likewise. First three rows: the relay at 30 Hz, before it went to 60 (about the same
bandwidth with everyone apart).

| Players, all driving | Server sends before | Now | Per client before | Now |
|---|---|---|---|---|
| 1 | 2.6 Mbit/s | 0.1 | 2.7 Mbit/s | 67 kbit/s |
| 8 | 34.2 | 0.8 | 4.3 | 96 kbit/s |
| 16 | 81.9 | 1.6 | 5.3 | 102 kbit/s |

The relay every tick, on foot at 60 Hz, as it is now:

| Players | Server sends | Per client | Relay p50 / p99 | Ticks/s | Main thread |
|---|---|---|---|---|---|
| 80 driving, spread over the map | 13.4 Mbit/s | 170 kbit/s | 20 / 32 ms | 60 | 93% |
| 64 driving, within 300 m (the worst case) | 37.6 | 600 kbit/s | 19 / 29 ms | 60 | 71% |
| 64 bunched, half on foot (see below) | 14.6 | 515 kbit/s | 18 / 29 ms | 60 | 66% |

The same 64 bunched, half on foot, with the relay at 30 Hz and on foot at 30 Hz: 10.1 Mbit/s, relay 30 / 45 ms. Relay at 60 Hz,
on foot at 30 Hz: 11.1 Mbit/s, 18 / 28 ms.

No player lost in any of these. Still to measure: the real Ampere server, a real client's frame rate and how the far tiers
look. `--walk`: walkers leave their car parked at the garage, which fills up: from about 30 active bots the others stay at
the terminal, on foot (the third row: 29 active). `delivered` counts every pair of players at 60 states a second, so it means
little since the tiers.
