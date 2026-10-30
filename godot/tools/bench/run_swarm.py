#!/usr/bin/env python3
"""Runs the swarm (swarm.gd) in several processes on this machine, ramping up the players, and prints per stage what it
saw, joined with the server's --stats lines if it has them (--server-log, a file or "ssh host docker logs..." copied
over afterwards). See README.md.

    run_swarm.py --server HOST:PORT --tokens tokens.json --routes routes.json --stages 8,16,32 --hold 60 --procs 12 --out DIR
"""
import argparse
import json
import pathlib
import subprocess
import sys
import time

here = pathlib.Path(__file__).resolve().parent
godot_dir = here.parent.parent


def percentile(hist, q):
    total = sum(hist.values())
    if not total:
        return None
    seen = 0
    for ms in sorted(hist):
        seen += hist[ms]
        if seen >= total * q:
            return ms
    return max(hist)


def summarise(out, stages, hold, start, server_log=None):
    swarm = []
    for f in sorted(out.glob("swarm_*.log")):
        for line in f.read_text(errors="replace").splitlines():
            if line.startswith("SWARM "):
                swarm.append(json.loads(line[6:]))
    server = []
    if server_log and pathlib.Path(server_log).exists():
        for line in pathlib.Path(server_log).read_text(errors="replace").splitlines():
            at = line.find("STATS ")
            if at >= 0:
                server.append(json.loads(line[at + 6:]))
    rows = []
    for k, n in enumerate(stages):
        t0, t1 = start + k * hold + hold * 0.55, start + (k + 1) * hold   # settled: after the joins
        rec = [r for r in swarm if t0 <= r["t"] < t1]
        srv = [r for r in server if t0 <= r["t"] < t1]
        row = {"players": n}
        if rec:
            hist = {}
            for r in rec:
                for ms, c in r["hist"].items():
                    hist[int(ms)] = hist.get(int(ms), 0) + c
            wall = sum(r["wall"] for r in rec) / len(rec) * len({round(r["t"] / 5) for r in rec}) or 1
            windows = len({round(r["t"] / 5) for r in rec}) or 1
            driving = sum(r["driving"] for r in rec) / windows
            row.update(driving=round(driving, 1), rtt_ms=round(sum(r["rtt_sum"] for r in rec) / max(sum(r["linked"] for r in rec), 1), 1),
                       relay_p50=percentile(hist, .5), relay_p95=percentile(hist, .95), relay_p99=percentile(hist, .99),
                       delivered=round(100 * sum(r["rx_player"] for r in rec) / max(windows * 5 * 60 * driving * (driving - 1), 1), 1),
                       rx_kb_s_per_bot=round(sum(r["rx_kb"] for r in rec) / max(windows * 5 * driving, 1), 1),
                       relay_kb_s=round(sum(r.get("relay_kb", 0) for r in rec) / max(windows * 5 * driving, 1), 1),
                       train_kb_s=round(sum(r.get("train_kb", 0) for r in rec) / max(windows * 5 * driving, 1), 1),
                       lost=sum(r["failed"] + r["kicked"] for r in rec),
                       swarm_slow=round(100 * sum(r["slow"] for r in rec) / max(sum(r["frames"] for r in rec), 1), 1))
        if srv:
            def mean(key):
                return round(sum(r[key] for r in srv) / len(srv), 2)
            row.update(srv_players=max(r["players"] for r in srv), tps=mean("tps"), late_ticks=sum(r["late_ticks"] for r in srv),
                       tick_avg=mean("tick_ms_avg"), tick_p99=mean("tick_ms_p99"), tick_max=max(r["tick_ms_max"] for r in srv),
                       cpu=mean("cpu"), cpu_main=mean("cpu_main"), rss_mb=round(max(r["rss_mb"] for r in srv)),
                       sent_mbit=round(mean("sent_kb_s") * 8 / 1024, 1), recv_mbit=round(mean("recv_kb_s") * 8 / 1024, 1),
                       traffic_level=max(r["traffic_level"] for r in srv))
        rows.append(row)
    return rows


def table(rows):
    keys = []
    for r in rows:
        keys += [k for k in r if k not in keys]
    lines = ["\t".join(keys)]
    for r in rows:
        lines.append("\t".join(str(r.get(k, "")) for k in keys))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", required=True)
    ap.add_argument("--tokens", required=True)
    ap.add_argument("--routes", required=True)
    ap.add_argument("--stages", required=True)
    ap.add_argument("--hold", type=float, default=60)
    ap.add_argument("--procs", type=int, default=8)
    ap.add_argument("--build", default="")
    ap.add_argument("--walk", default="0")
    ap.add_argument("--net", help="net.gd of the build the server runs, if not this tree's")
    ap.add_argument("--out", required=True)
    ap.add_argument("--server-log")
    ap.add_argument("--summarise-from", type=float, help="only summarise an earlier run that began at this unix time")
    a = ap.parse_args()
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    stages = [int(x) for x in a.stages.split(",")]
    if a.summarise_from:
        print(table(summarise(out, stages, a.hold, a.summarise_from, a.server_log)))
        return
    start = time.time() + 15
    (out / "start").write_text(str(start))
    total = stages[-1]
    per, extra = divmod(total, a.procs)
    first = 0
    procs = []
    for p in range(a.procs):
        n = per + (1 if p < extra else 0)
        if not n:
            continue
        log = open(out / f"swarm_{p}.log", "w")
        procs.append(subprocess.Popen(
            ["godot", "--headless", "--path", str(godot_dir), "--script", "res://tools/bench/swarm.gd", "--",
             f"--server={a.server}", f"--tokens={a.tokens}", f"--routes={a.routes}", f"--bots={first},{n}",
             f"--start={start}", f"--stages={a.stages}", f"--hold={a.hold}", f"--build={a.build}", f"--walk={a.walk}"]
            + ([f"--net={a.net}"] if a.net else []),
            stdout=log, stderr=subprocess.STDOUT))
        first += n
    # bots are dealt out in blocks; which process a bot is in doesn't matter, they all run on this clock
    end = start + a.hold * len(stages)
    try:
        while time.time() < end and all(p.poll() is None for p in procs):
            time.sleep(1)
    finally:
        for p in procs:
            p.terminate()
    print(f"start {start}")
    print(table(summarise(out, stages, a.hold, start, a.server_log)))
    sys.stdout.flush()


main()
