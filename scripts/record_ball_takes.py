#!/usr/bin/env python3
"""Record the scripted ball expert's takes on duckbench: physics only, no pictures.

THE SPLIT (Craig, 2026-11-04: "any split or combination for performance is fine"). Physics runs here,
on duckbench (MuJoCo, lockstep: each /intent advances the world exactly `hold` seconds, so a take is
reproducible). Pictures are drawn later on the Mac by the app's own head-camera renderer from the
saved states, so the training pictures are exactly what the phone draws at run time.

ONE LINE PER TICK, THE BENCH'S OWN JSON. Each tick saves the full state the bench answered (root
position and quaternion, 14 joints, ball, sim time), the command in force before (state) and the
command sent now (action): DreamDataset.Take's convention. `DuckDrive.readLive` reads the saved
state back on the Mac unchanged.

THE EXPERT IS A PORT of StudioKit's BallExpert, held to it by a parity file: `--vectors OUT` writes
the commands this port gives for fixed inputs, and StudioKit's BallExpertTests reads that file and
asserts the Swift answers are the same.

    python3 scripts/record_ball_takes.py --bench http://127.0.0.1:8770 --takes 40 --out takes.jsonl
    python3 scripts/record_ball_takes.py --vectors StudioKit/Tests/StudioKitTests/Fixtures/ball-expert-vectors.json
"""

import argparse
import json
import math
import sys
import urllib.request

MAX_FORWARD, MAX_TURN, DEAD_ZONE = 0.3, 1.0, 0.05      # DuckDrive.maxForward, maxTurn, deadZone
REACH, FACING, SLOWING, ARC_FORWARD = 0.20, 0.6, 0.35, 0.25   # BallExpert
TASK = "walk to the ball"
WALKER = "alpha_walking.onnx"
MASK64 = (1 << 64) - 1


class SplitMix64:
    """StudioKit's SplitMix64(seed:): next() in [0, 1)."""

    def __init__(self, seed: int) -> None:
        self.state = seed & MASK64

    def next(self) -> float:
        self.state = (self.state + 0x9E3779B97F4A7C15) & MASK64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
        z ^= z >> 31
        return (z >> 11) * (1.0 / 9007199254740992.0)


def style(seed: int) -> dict:
    rng = SplitMix64(seed)
    return {"speed": 0.7 + 0.3 * rng.next(), "turnGain": 1.5 + 1.0 * rng.next(),
            "weave": 0.03 * rng.next(), "weavePeriod": 2 + 2 * rng.next()}


PLAIN = {"speed": 1.0, "turnGain": 2.0, "weave": 0.0, "weavePeriod": 3.0}


def command(x, y, yaw, bx, by, t, s=PLAIN):
    """BallExpert.command(x:y:yaw:bx:by:t:style:), line for line."""
    dx, dy = bx - x, by - y
    distance = math.sqrt(dx * dx + dy * dy)
    if distance <= REACH:
        return (0.0, 0.0, 0.0)
    off = math.remainder(math.atan2(dy, dx) - yaw, 2 * math.pi)
    vyaw = min(max(s["turnGain"] * off, -MAX_TURN), MAX_TURN)
    if not abs(off) < FACING:
        return (ARC_FORWARD, 0.0, -MAX_TURN if off < 0 else MAX_TURN)
    ease = min(1.0, (distance - REACH) / SLOWING)
    floor = 2 * DEAD_ZONE
    vx = max(MAX_FORWARD * s["speed"] * ease * math.cos(off), floor)
    vy = s["weave"] * math.sin(2 * math.pi * t / s["weavePeriod"])
    return (min(vx, MAX_FORWARD), vy, vyaw)


def yaw_of(q):
    """RunMetrics.yaw: q = (w, x, y, z)."""
    w, x, y, z = q
    return math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))


def call(bench, path, body=None):
    req = urllib.request.Request(f"{bench}{path}", method="POST" if body is not None else "GET",
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"content-type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        out = json.loads(r.read())
    if "error" in out:
        raise RuntimeError(f"{path}: {out['error']}")
    return out


def vectors(path):
    """Fixed inputs and this port's answers, for the Swift parity test."""
    cases = []
    rng = SplitMix64(4242)
    for i in range(64):
        x, y = -1 + 2 * rng.next(), -1 + 2 * rng.next()
        yaw = -math.pi + 2 * math.pi * rng.next()
        bx, by = -1 + 2 * rng.next(), -1 + 2 * rng.next()
        t = 10 * rng.next()
        seed = i % 7
        s = style(seed) if seed else PLAIN
        cases.append({"x": x, "y": y, "yaw": yaw, "bx": bx, "by": by, "t": t,
                      "styleSeed": seed, "command": list(command(x, y, yaw, bx, by, t, s))})
    cases.append({"x": 0, "y": 0, "yaw": 0, "bx": 0.15, "by": 0, "t": 0, "styleSeed": 0, "command": [0, 0, 0]})
    with open(path, "w") as f:
        json.dump({"source": "scripts/record_ball_takes.py", "styles": {str(k): style(k) for k in range(1, 7)},
                   "cases": cases}, f, indent=1)
    print(f"wrote {len(cases)} vectors to {path}")


def record(bench, takes, out, first_seed, limit_s, hold):
    call(bench, "/reset", {})
    call(bench, "/policy", {"policy": WALKER})
    kept = dropped = 0
    with open(out, "a") as f:
        seed = first_seed
        while kept < takes:
            seed += 1
            rng = SplitMix64(seed * 7919 + 1)
            bearing = -180 + 360 * rng.next()
            rng_range = 0.5 + 0.9 * rng.next()
            s = style(seed)
            call(bench, "/reset", {})
            call(bench, "/policy", {"policy": WALKER})
            state = call(bench, "/ball", {"bearing": bearing, "range": rng_range})
            t0 = state["t"]
            rows, previous, arrived, fell = [], (0.0, 0.0, 0.0), False, False
            while state["t"] - t0 < limit_s:
                bx, by = state["ball"][0], state["ball"][1]
                c = command(state["position"][0], state["position"][1], yaw_of(state["quaternion"]),
                            bx, by, state["t"] - t0, s)
                rows.append({"state": list(previous), "action": list(c), "bench": state})
                if c == (0.0, 0.0, 0.0):
                    arrived = True
                    break
                state = call(bench, "/intent", {"vx": c[0], "vy": c[1], "vyaw": c[2], "hold": hold})
                previous = c
                if not state.get("upright", True):
                    fell = True
                    break
            if arrived and not fell and len(rows) >= 17:
                f.write(json.dumps({"seed": seed, "task": TASK, "bearing": bearing, "range": rng_range,
                                    "style": s, "walker": WALKER, "hold": hold, "rows": rows}) + "\n")
                f.flush()
                kept += 1
                print(f"take {kept}/{takes}: seed {seed}, {len(rows)} rows ({len(rows) * hold:.1f} s)", flush=True)
            else:
                dropped += 1
                why = "fell" if fell else ("too short" if arrived else "time limit")
                print(f"seed {seed} dropped: {why}", flush=True)
    call(bench, "/stop", {})
    print(f"kept {kept}, dropped {dropped}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--bench", default="http://127.0.0.1:8770")
    p.add_argument("--takes", type=int, default=40)
    p.add_argument("--out")
    p.add_argument("--first-seed", type=int, default=0)
    p.add_argument("--limit", type=float, default=30.0, help="seconds of sim time per take")
    p.add_argument("--hold", type=float, default=0.1, help="seconds per tick: 10 fps, the dataset's rate")
    p.add_argument("--vectors", help="write the parity vectors and exit")
    a = p.parse_args()
    if a.vectors:
        vectors(a.vectors)
        return
    if not a.out:
        sys.exit("--out is required")
    record(a.bench, a.takes, a.out, a.first_seed, a.limit, a.hold)


if __name__ == "__main__":
    main()
