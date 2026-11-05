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

REACHED means the duck's root came within BallExpert.reach (0.20 m) of the ball's centre at any tick
of the run. Each run's every tick, every chunk the driver answered and the stop/end order is saved as
JSON lines in OUT/WHO/seed-N.jsonl, with OUT/WHO/summary.json beside them.

    python3 scripts/m1_trial.py --who expert --out ~/scratch/ball-takes/m1-v1
    python3 scripts/m1_trial.py --who driver --mac-driver '~/m1-driver' --out ~/scratch/ball-takes/m1-v1
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
from record_ball_takes import REACH, WALKER, SplitMix64, call, command, style, yaw_of  # noqa: E402

PREFIX = "TRIAL>"
MAC_APP = "~/m1-app/DuckStudio.app/Contents/MacOS/DuckStudio"


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
        self.t0 = state["t"]
        self.first_ask_t = None
        self.reached_t = None
        self.closest = math.inf
        self.fell = False
        self.asks, self.ask_ms, self.refusals, self.tail = 0, [], [], []
        self.last = None
        self.write({"type": "start", "seed": seed, "who": who, "bearing": bearing, "range": rng_range,
                    **geometry(state)})
        self.see(state, None)

    def write(self, obj):
        self.f.write(json.dumps(obj) + "\n")

    def see(self, state, cmd):
        g = geometry(state)
        self.last = g
        self.closest = min(self.closest, g["dist"])
        if g["dist"] <= REACH and self.reached_t is None:
            self.reached_t = g["t"]
        if not g["upright"]:
            self.fell = True
        if cmd is not None:
            self.write({"type": "step", "cmd": cmd, **g})

    def event(self, kind, req):
        self.tail.append(kind)
        if kind == "ask":
            if "refused" in req:
                self.refusals.append(req["refused"])
            else:
                self.asks += 1
                self.ask_ms.append(req.get("ms", 0))
                if self.first_ask_t is None:
                    self.first_ask_t = req.get("t")
        self.write({"type": kind, **req})

    def close(self, limit_ok=True):
        self.f.close()
        start = self.first_ask_t if self.first_ask_t is not None else self.t0
        tail = [k for k in self.tail if k in ("stop", "end", "ended")]
        return {"seed": self.seed, "reached": self.reached_t is not None,
                "time_s": None if self.reached_t is None else round(self.reached_t - start, 2),
                "closest_m": round(self.closest, 3), "final_m": round(self.last["dist"], 3),
                "fell": self.fell, "asks": self.asks, "refusals": self.refusals,
                "ask_ms_p50": round(statistics.median(self.ask_ms), 1) if self.ask_ms else None,
                "ended_stop_then_end": tail[-3:] == ["stop", "end", "ended"] if self.who != "expert" else None,
                "sim_s": round(self.last["t"] - self.t0, 2), "log": str(self.path)}


def run_expert(bench, seeds, out_dir, limit):
    results = []
    for seed in seeds:
        bearing, rng_range, state = setup(bench, seed)
        run = Run(out_dir, "expert", seed, bearing, rng_range, state)
        s, t0 = style(seed), state["t"]
        while state["t"] - t0 < limit:
            g = geometry(state)
            c = command(g["x"], g["y"], g["yaw"], g["bx"], g["by"], state["t"] - t0, s)
            if c == (0.0, 0.0, 0.0):
                break
            state = call(bench, "/intent", {"vx": c[0], "vy": c[1], "vyaw": c[2], "hold": 0.1})
            run.see(state, list(c))
            if not state.get("upright", True):
                break
        results.append(run.close())
        print(json.dumps(results[-1]), flush=True)
    return results


def run_mac(bench, seeds, out_dir, who, mac_driver):
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    import mac_compile_check as base
    import paramiko
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(base.HOST, username=base.USER, password=base.password(), timeout=45, banner_timeout=45)
    client.get_transport().set_keepalive(30)
    ch = client.get_transport().open_session()
    ch.set_combine_stderr(True)
    arg = "zero" if who == "zero" else mac_driver
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
    a, _, b = text.partition("-")
    return list(range(int(a), int(b or a) + 1))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--bench", default="http://127.0.0.1:8770")
    p.add_argument("--who", choices=["driver", "zero", "expert"], required=True)
    p.add_argument("--seeds", default="5001-5010")
    p.add_argument("--out", required=True)
    p.add_argument("--mac-driver", default="~/m1-driver")
    p.add_argument("--limit", type=float, default=60.0, help="expert only: seconds of sim time")
    a = p.parse_args()
    seeds = parse_seeds(a.seeds)
    out_dir = pathlib.Path(a.out).expanduser() / a.who
    out_dir.mkdir(parents=True, exist_ok=True)
    if a.who == "expert":
        results = run_expert(a.bench, seeds, out_dir, a.limit)
    else:
        results = run_mac(a.bench, seeds, out_dir, a.who, a.mac_driver)
    reached = sum(r["reached"] for r in results)
    summary = {"who": a.who, "seeds": a.seeds, "runs": len(results), "reached": reached, "reach_m": REACH,
               "results": results}
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=1))
    print(f"{a.who}: reached {reached} of {len(results)}")


if __name__ == "__main__":
    main()
