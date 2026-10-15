"""Does the duck walk? Hold one robot.move twist and say what MuJoCo and robotd saw.

    python3 cardreader/sim/sysid/probe_walk.py --sock ~/.cache/duck-sim/duck-a.sock \\
        --body-port 7801 --vx 0.15 --seconds 8

Sends `robot.move` at 20 Hz for --seconds (Pollen's `duck-sim drive` sends 10 Hz for 8 s at
vx 0.15), then zero for 2 s, and prints: ground-truth displacement and yaw change (MuJoCo's
trunk), robotd's odometry displacement, which policy drove the ticks (`robot.state.policy`),
what robotd applied (`move.applied`) and anything it limited, and whether it fell.
"""

from __future__ import annotations

import argparse
import collections
import json
import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from duckio import Body, Robotd, odom_of, wrap  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sock", default=os.path.expanduser("~/.cache/duck-sim/duck-a.sock"))
    ap.add_argument("--body-port", type=int, default=7801)
    ap.add_argument("--vx", type=float, default=0.15)
    ap.add_argument("--vyaw", type=float, default=0.0)
    ap.add_argument("--seconds", type=float, default=8.0)
    ap.add_argument("--hz", type=float, default=20.0)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    r = Robotd(a.sock, hz=50)
    b = Body(a.body_port)
    time.sleep(0.3)
    t0 = b.truth()
    o0 = odom_of(r.latest()[1])
    policies = collections.Counter()
    applied, limited, fallen = [], set(), False
    n = int(a.seconds * a.hz)
    start = len(r.frames)
    turned, last = 0.0, t0["yaw"]       # unwrapped: a turn past 180 degrees is not a small one
    for _ in range(n):
        r.move(a.vx, a.vyaw)
        time.sleep(1.0 / a.hz)
        now = b.truth()["yaw"]
        turned += wrap(now - last)
        last = now
    t1 = b.truth()
    turned += wrap(t1["yaw"] - last)
    o1 = odom_of(r.latest()[1])
    for _ in range(int(2 * a.hz)):
        r.move(0, 0)
        time.sleep(1.0 / a.hz)
    t2 = b.truth()
    for _, p in list(r.frames)[start:]:
        policies[p.get("policy")] += 1
        mv = p.get("move") or {}
        applied.append(mv.get("applied"))
        limited.update(mv.get("limited_by") or [])
        fallen = fallen or bool((p.get("safety") or {}).get("fallen"))
    h0 = t0["yaw"]
    dx, dy = t1["x"] - t0["x"], t1["y"] - t0["y"]
    out = {
        "vx": a.vx, "vyaw": a.vyaw, "seconds": a.seconds,
        "truth_forward_m": dx * math.cos(h0) + dy * math.sin(h0),
        "truth_left_m": -dx * math.sin(h0) + dy * math.cos(h0),
        "truth_yaw_deg": math.degrees(turned),
        "truth_after_stop_m": math.hypot(t2["x"] - t1["x"], t2["y"] - t1["y"]),
        "trunk_z_end": t2["z"],
        "odom_dist_m": math.hypot(o1[0] - o0[0], o1[1] - o0[1]) if o0 and o1 else None,
        "odom_yaw_deg": math.degrees(wrap(o1[2] - o0[2])) if o0 and o1 else None,
        "policies": dict(policies),
        "applied_last": applied[-1] if applied else None,
        "limited_by": sorted(limited),
        "fallen": fallen,
        "sim_rate": (t2["sim_time"] - t0["sim_time"]) / (t2["wall"] - t0["wall"]),
    }
    print(json.dumps(out, indent=None if a.json else 1))
    r.close()
    b.close()


if __name__ == "__main__":
    main()
