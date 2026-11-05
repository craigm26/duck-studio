#!/usr/bin/env python3
"""M1, closed loop on the simulated duck: physics here (duckbench), pictures and the driver on the Mac.

THE SPLIT, AS FOR THE RECORDING. duckbench steps the world in lockstep: each /intent advances it
exactly `hold` seconds. The Mac runs the app headless (`DuckStudio -driver-trial FOLDER`), where
StudioKit's DriverTrial runs the shipped DreamPilot with the driver loaded as the phone loads one, and
the app's own head camera draws each picture. It asks this end, one JSON line at a time over the ssh
channel's stdin and stdout: `begin` (set up the next start), `step` (one /intent), and `ask`, `stop`,
`end`, `ended`, which are only logged. Nothing listens on a port on the shared Mac.

THE STARTS are record_ball_takes.py's rule (bearing and range from SplitMix64(seed * 7919 + 1)) on
holdout seeds the recording never used (it used 1-75 and 1001-1134).

THREE DRIVERS ON THE SAME SEEDS:
- `driver`: the trained driver, through DreamPilot on the Mac;
- `zero`: every row still, through the same pilot and camera (`-driver-trial zero`);
- `expert`: BallExpert (this repo's parity-tested port) every 0.1 s on this machine, as it was
  recorded, and stopped at the ball: the ceiling.

REACHED means the duck's root came within BallExpert.reach (0.35 m since round 3: the top half of
the ball is still in the head picture there) of the ball's centre at any tick of the run. Round 1's two
successes walked through the ball, so reaching is not enough on its own: STOPPED AT THE BALL means the
run ended within STOPPED_M (reach + 0.05 m, 0.40 m) and standing, every command of the last STANDING_S (1 s) inside the walker's dead zone. Each run also
reports the time to reach and to first see the ball (the root's heading within the head camera's
half-width, from the first ask), how far the ball was pushed, and how far the root moved in the last
second. PARKED AT THE BALL is the physical twin of stopped: the same 0.40 m, but the root still
(moved at most STILL_M in the last second) whatever the commands were, because alpha_walking does
not step for every command above the dead zone (measured 2026-11-04: the v3 driver's 0.1 to 0.2 m/s
moved the duck 0.02 to 0.03 m/s). Each run's every tick, every chunk the driver answered and the stop/end order is saved as
JSON lines in OUT/WHO/seed-N.jsonl. Every tick (and the start) also carries the bench's FULL state
under "bench" (root, quaternion, 14 joints, ball, sim time: what record_ball_takes.py keeps per row),
so a later DAgger round can draw the pictures the driver itself visited and have the expert label
them. OUT/WHO/summary.json sits beside the logs; every number is scored
from that log (`score`), so `--rescore` rebuilds a summary from old logs without the bench.

    python3 scripts/m1_trial.py --who expert --out ~/scratch/ball-takes/m1-v1
    python3 scripts/m1_trial.py --who driver --mac-driver '~/m1-driver' --out ~/scratch/ball-takes/m1-v1
    python3 scripts/m1_trial.py --who driver --raw --out ~/scratch/ball-takes/m1-v1   # no DriverSnap
    python3 scripts/m1_trial.py --who driver --rescore --out ~/scratch/ball-takes/m1-v1
"""

import argparse
import json
import math
import pathlib
import select
import statistics
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from record_ball_takes import (DEAD_ZONE, REACH, STANDING_ROWS, WALKER, SplitMix64,  # noqa: E402
                               call, command, style, yaw_of)

PREFIX = "TRIAL>"
MAC_APP = "~/m1-app/DuckStudio.app/Contents/MacOS/DuckStudio"
STOPPED_M = round(REACH + 0.05, 3)   # stopped at the ball: ended this close (0.40 m), a stop's few mm of drift spared
STANDING_S = 1.0           # and every command of the last second inside the dead zone
STILL_M = 0.02             # parked: the root moved at most this far in that last second, whatever was asked
HALF_HFOV = math.atan(math.tan(math.radians(45 / 2)) * 320 / 176)   # the head camera's half-width, 36.98 deg


def start_of(seed):
    rng = SplitMix64(seed * 7919 + 1)
    return -180 + 360 * rng.next(), 0.5 + 0.9 * rng.next()


def setup(bench, seed):
    bearing, rng_range = start_of(seed)
    call(bench, "/reset", {})
    call(bench, "/policy", {"policy": WALKER})
    return bearing, rng_range, call(bench, "/ball", {"bearing": bearing, "range": rng_range})


def geometry(state):
    x, y = state["position"][0], state["position"][1]
    bx, by = state["ball"][0], state["ball"][1]
    yaw = yaw_of(state["quaternion"])
    off = math.remainder(math.atan2(by - y, bx - x) - yaw, 2 * math.pi)
    return {"t": state["t"], "x": x, "y": y, "yaw": yaw, "bx": bx, "by": by,
            "dist": math.hypot(bx - x, by - y), "off": off, "upright": state.get("upright", True)}


class Run:
    def __init__(self, out_dir, who, seed, bearing, rng_range, state):
        self.path = out_dir / f"seed-{seed}.jsonl"
        self.f = open(self.path, "w")
        self.seed, self.who = seed, who
        self.fell = False
        self.asks, self.ask_ms, self.refusals, self.tail = 0, [], [], []
        self.last = None
        self.write({"type": "start", "seed": seed, "who": who, "bearing": bearing, "range": rng_range,
                    **geometry(state), "bench": state})
        self.see(state, None)

    def write(self, obj):
        self.f.write(json.dumps(obj) + "\n")

    def see(self, state, cmd):
        g = geometry(state)
        self.last = g
        if not g["upright"]:
            self.fell = True
        if cmd is not None:
            self.write({"type": "step", "cmd": cmd, **g, "bench": state})

    def event(self, kind, req):
        self.tail.append(kind)
        if kind == "ask":
            if "refused" in req:
                self.refusals.append(req["refused"])
            else:
                self.asks += 1
                self.ask_ms.append(req.get("ms", 0))
        self.write({"type": kind, **req})

    def close(self):
        self.f.close()
        return {**score(self.path), "fell": self.fell, "asks": self.asks, "refusals": self.refusals,
                "ask_ms_p50": round(statistics.median(self.ask_ms), 1) if self.ask_ms else None,
                "log": str(self.path)}


def score(path):
    """One run's numbers, from its log alone. The clock starts at the first ask (the driver's first
    look; the expert has none, so its start). Seeing is judged from the root's heading, so a ball
    under the camera (closer than about 0.30 m) still counts as seen."""
    with open(path) as f:
        lines = [json.loads(l) for l in f]
    start = lines[0]
    steps = [l for l in lines if l["type"] == "step"]
    first_ask = next((l["t"] for l in lines if l["type"] == "ask" and "rows" in l), None)
    t0 = first_ask if first_ask is not None else start["t"]
    last = steps[-1] if steps else start
    reached = next((s["t"] for s in steps if s["dist"] <= REACH), None)
    seen = start["t"] if abs(start["off"]) < HALF_HFOV else next(
        (s["t"] for s in steps if abs(s["off"]) < HALF_HFOV), None)
    tail = [s for s in steps if s["t"] > last["t"] - STANDING_S + 1e-6]
    standing = bool(tail) and all(abs(c) <= DEAD_ZONE for s in tail for c in s["cmd"])
    before = next((s for s in steps if s["t"] >= last["t"] - STANDING_S - 1e-6), start)
    final_m = last["dist"]
    moved = math.hypot(last["x"] - before["x"], last["y"] - before["y"])
    kinds = [l["type"] for l in lines if l["type"] in ("stop", "end", "ended")]
    return {"seed": start["seed"], "reached": reached is not None,
            "stopped_at_ball": final_m <= STOPPED_M and standing,
            "parked_at_ball": final_m <= STOPPED_M and moved <= STILL_M,
            "time_s": None if reached is None else round(max(reached - t0, 0.0), 2),
            "first_seen_s": None if seen is None else round(max(seen - t0, 0.0), 2),
            "starts_in_view": abs(start["off"]) < HALF_HFOV,
            "closest_m": round(min([start["dist"]] + [s["dist"] for s in steps]), 3),
            "final_m": round(final_m, 3), "standing_at_end": standing,
            "moved_last_s_m": round(moved, 3),
            "ball_push_m": round(math.hypot(last["bx"] - start["bx"], last["by"] - start["by"]), 3),
            "ended_stop_then_end": kinds[-3:] == ["stop", "end", "ended"] if start["who"] != "expert" else None,
            "sim_s": round(last["t"] - start["t"], 2)}


def summarize(who, seeds, results):
    def mean(key, rows):
        xs = [r[key] for r in rows if r[key] is not None]
        return round(statistics.fmean(xs), 3) if xs else None
    reached = [r for r in results if r["reached"]]
    return {"who": who, "seeds": seeds, "runs": len(results), "reached": len(reached),
            "stopped_at_ball": sum(r["stopped_at_ball"] for r in results),
            "reached_and_stopped": sum(r["stopped_at_ball"] for r in reached),
            "parked_at_ball": sum(r["parked_at_ball"] for r in results),
            "reached_and_parked": sum(r["parked_at_ball"] for r in reached),
            "reach_m": REACH, "stopped_m": STOPPED_M, "standing_s": STANDING_S,
            "mean_time_to_reach_s": mean("time_s", reached),
            "median_time_to_reach_s": round(statistics.median([r["time_s"] for r in reached]), 2) if reached else None,
            "mean_first_seen_s": mean("first_seen_s", results),
            "never_saw": sum(r["first_seen_s"] is None for r in results),
            "mean_ball_push_m": mean("ball_push_m", results),
            "mean_final_m": mean("final_m", results),
            "fell": sum(bool(r.get("fell")) for r in results),
            "results": results}


def run_expert(bench, seeds, out_dir, limit):
    results = []
    for seed in seeds:
        bearing, rng_range, state = setup(bench, seed)
        run = Run(out_dir, "expert", seed, bearing, rng_range, state)
        s, t0, standing = style(seed), state["t"], 0
        # Once it says stand it stands, latched, for the recorder's STANDING_ROWS more ticks, so the
        # ceiling is scored on the same stop rule as the driver.
        while standing or state["t"] - t0 < limit:
            g = geometry(state)
            c = (0.0, 0.0, 0.0) if standing else command(g["x"], g["y"], g["yaw"], g["bx"], g["by"], state["t"] - t0, s)
            if c == (0.0, 0.0, 0.0):
                standing += 1
                if standing > STANDING_ROWS:
                    break
            state = call(bench, "/intent", {"vx": c[0], "vy": c[1], "vyaw": c[2], "hold": 0.1})
            run.see(state, list(c))
            if not state.get("upright", True):
                break
        results.append(run.close())
        print(json.dumps(results[-1]), flush=True)
    return results


def run_mac(bench, seeds, out_dir, who, mac_driver, raw=False):
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    import mac_compile_check as base
    import paramiko
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(base.HOST, username=base.USER, password=base.password(), timeout=45, banner_timeout=45)
    client.get_transport().set_keepalive(30)
    ch = client.get_transport().open_session()
    ch.set_combine_stderr(True)
    arg = "zero" if who == "zero" else mac_driver + (" -driver-raw" if raw else "")
    ch.exec_command(f"export HOME={base.Q_HOME} CFFIXED_USER_HOME={base.Q_HOME}; {MAC_APP} -driver-trial {arg}")
    pending = list(seeds)
    results, run, buf = [], None, b""
    started = time.time()

    def reply(obj):
        ch.sendall((json.dumps(obj) + "\n").encode())

    while True:
        if not ch.recv_ready():
            if ch.exit_status_ready():
                break
            select.select([ch], [], [], 1.0)
            continue
        data = ch.recv(1 << 16)
        if not data:
            break
        buf += data
        while b"\n" in buf:
            raw, buf = buf.split(b"\n", 1)
            line = raw.decode(errors="replace")
            if not line.startswith(PREFIX):
                print(f"mac| {line}", flush=True)
                continue
            req = json.loads(line[len(PREFIX):])
            op = req.get("op")
            if op == "begin":
                if run is not None:
                    results.append(run.close())
                    print(json.dumps(results[-1]), flush=True)
                    run = None
                if not pending:
                    reply({"done": True})
                    continue
                seed = pending.pop(0)
                bearing, rng_range, state = setup(bench, seed)
                run = Run(out_dir, who, seed, bearing, rng_range, state)
                reply({"seed": seed, "state": state})
            elif op == "step":
                cmd = [req["vx"], req["vy"], req["vyaw"]]
                state = call(bench, "/intent", {"vx": cmd[0], "vy": cmd[1], "vyaw": cmd[2], "hold": req["hold"]})
                run.see(state, cmd)
                reply({"state": state})
            else:
                run.event(op, req)
                reply({"ok": True})
    status = ch.recv_exit_status()
    client.close()
    if run is not None:
        results.append(run.close())
    print(f"mac exit {status}, {time.time() - started:.0f} s", flush=True)
    return results


def parse_seeds(text):
    """'5001-5010' or '5001-5010,6001-6010'."""
    seeds = []
    for part in text.split(","):
        a, _, b = part.strip().partition("-")
        seeds += range(int(a), int(b or a) + 1)
    return seeds


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--bench", default="http://127.0.0.1:8770")
    p.add_argument("--who", choices=["driver", "zero", "expert"], required=True)
    p.add_argument("--seeds", default="5001-5010")
    p.add_argument("--out", required=True)
    p.add_argument("--mac-driver", default="~/m1-driver")
    p.add_argument("--raw", action="store_true", help="driver only: play its rows without the snap")
    p.add_argument("--limit", type=float, default=60.0, help="expert only: seconds of sim time")
    p.add_argument("--rescore", action="store_true", help="no bench: score OUT/WHO's logs again")
    a = p.parse_args()
    seeds = parse_seeds(a.seeds)
    out_dir = pathlib.Path(a.out).expanduser() / a.who
    out_dir.mkdir(parents=True, exist_ok=True)
    if a.rescore:
        old = {}
        if (out_dir / "summary.json").exists():
            old = {r["seed"]: r for r in json.loads((out_dir / "summary.json").read_text())["results"]}
        paths = sorted(out_dir.glob("seed-*.jsonl"), key=lambda q: int(q.stem.split("-")[1]))
        results = [{**{k: v for k, v in old.get(score(q)["seed"], {}).items()}, **score(q), "log": str(q)}
                   for q in paths if int(q.stem.split("-")[1]) in seeds]
    elif a.who == "expert":
        results = run_expert(a.bench, seeds, out_dir, a.limit)
    else:
        results = run_mac(a.bench, seeds, out_dir, a.who, a.mac_driver, a.raw)
    summary = summarize(a.who, a.seeds, results)
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=1))
    print(json.dumps({k: v for k, v in summary.items() if k != "results"}))
    print(f"{a.who}: reached {summary['reached']} of {len(results)}, stopped at the ball {summary['stopped_at_ball']}, "
          f"parked at the ball {summary['parked_at_ball']}")


if __name__ == "__main__":
    main()
