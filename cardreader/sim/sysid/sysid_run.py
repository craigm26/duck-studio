"""System identification of the duck through `robot.move` only, on the real robotd and Pollen's
v8 velstand, with MuJoCo's ground truth logged beside it. Standard library only.

    python3 cardreader/sim/sysid/sysid_run.py --sock STATE/duck.sock --body-port 7831 \\
        --out cardreader/sim/sysid/raw --reps 3 --seed 1

Every command stays inside Pollen's PadDriveParams defaults and v8 velstand's training command
ranges (both vx +-0.4 m/s, vyaw +-1.0 rad/s; see README.md here). Experiments, each a trial file
`raw/<name>.jsonl.gz`:

- `step_vx_<v>_<rep>`, `step_vyaw_<w>_<rep>`: still for a random 1.0 to 2.5 s (so the step
  lands at a different moment of whatever the standing duck is doing: the starting phase), the
  step held `--hold` s, then still for 3 s. Levels: vx +-0.05 .. +-0.40 by 0.05, vyaw
  +-0.125 .. +-1.0 by 0.125.
- `ramp_*`: 0 to the bound over 8 s, held 2 s, back to 0 over 8 s.
- `deadman_<rep>`: vx 0.3 for 3 s, then nothing at all is sent for 3 s.
- `rate_<hz>`: a second connection subscribed at 10, 20 and 50 Hz for 5 s each, to see what a
  client really gets.

A trial file is one JSON object per line: `{"k": "cmd", "w": wall, "vx", "vyaw"}` for every
`robot.move` sent (20 Hz, Studio's and the card reader's rate), `{"k": "state", "w": wall,
"t", "t_ns", "policy", "move", "odom", "imu", "fallen"}` for every robot.state frame (50 Hz),
and `{"k": "truth", "w": wall, "sim_time", "x", "y", "z", "yaw"}` polled from duck-body at
50 Hz. `w` is time.monotonic() on this machine when the line was produced or arrived.
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import random
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from duckio import Body, Robotd  # noqa: E402

TICK = 0.05
VX = [round(0.05 * k, 3) for k in range(1, 9)]          # 0.05 .. 0.40
VYAW = [round(0.125 * k, 3) for k in range(1, 9)]       # 0.125 .. 1.0
VX_MAX, VYAW_MAX = 0.4, 1.0


class Trial:
    def __init__(self, robot: Robotd, body: Body, path: str):
        self.robot, self.body, self.path = robot, body, path
        self.lines = []
        self.stop = threading.Event()
        self.first = len(robot.frames)
        self.poller = threading.Thread(target=self._poll, daemon=True)

    def _poll(self):
        nxt = time.monotonic()
        while not self.stop.is_set():
            t = self.body.truth()
            self.lines.append({"k": "truth", "w": t["wall"], "sim_time": t["sim_time"], "x": t["x"],
                               "y": t["y"], "z": t["z"], "yaw": t["yaw"]})
            nxt += 0.02
            time.sleep(max(0.0, nxt - time.monotonic()))

    def __enter__(self):
        self.first = len(self.robot.frames)
        self.poller.start()
        return self

    def send(self, vx, vyaw):
        assert -VX_MAX <= vx <= VX_MAX and -VYAW_MAX <= vyaw <= VYAW_MAX, (vx, vyaw)
        self.robot.move(vx, vyaw)
        self.lines.append({"k": "cmd", "w": time.monotonic(), "vx": vx, "vyaw": vyaw})

    def hold(self, vx, vyaw, seconds):
        nxt = time.monotonic()
        for _ in range(max(1, round(seconds / TICK))):
            self.send(vx, vyaw)
            nxt += TICK
            time.sleep(max(0.0, nxt - time.monotonic()))

    def ramp(self, a, b, seconds, axis):
        n = max(1, round(seconds / TICK))
        nxt = time.monotonic()
        for i in range(n + 1):
            v = a + (b - a) * i / n
            self.send(v if axis == "vx" else 0.0, v if axis == "vyaw" else 0.0)
            nxt += TICK
            time.sleep(max(0.0, nxt - time.monotonic()))

    def __exit__(self, *exc):
        self.stop.set()
        self.poller.join()
        frames = list(self.robot.frames)
        # Frames are kept in a bounded deque; take what arrived since the trial began.
        start_w = self.lines[0]["w"] if self.lines else 0
        for w, p in frames:
            if w < start_w - 0.05:
                continue
            self.lines.append({"k": "state", "w": w, "t": p.get("t"), "t_ns": p.get("t_ns"),
                               "policy": p.get("policy"), "move": p.get("move"), "odom": p.get("odom"),
                               "imu": p.get("imu"),
                               "fallen": bool((p.get("safety") or {}).get("fallen"))})
        self.lines.sort(key=lambda d: d["w"])
        with gzip.open(self.path, "wt") as f:
            for d in self.lines:
                f.write(json.dumps(d, separators=(",", ":")) + "\n")


def upright(body: Body) -> bool:
    t = body.truth()
    return t["z"] > 0.095 and t["gravity"][2] < -0.9


def settle(robot, body, trial_name):
    """Still until the duck is upright, at most 20 s (velstand gets itself up after a fall)."""
    for _ in range(400):
        robot.move(0.0, 0.0)
        time.sleep(TICK)
        if upright(body):
            return
    print(f"  {trial_name}: the duck is not upright after 20 s", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sock", required=True)
    ap.add_argument("--body-port", type=int, required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--hold", type=float, default=5.0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--only", default="step,ramp,deadman,rate")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    rng = random.Random(a.seed)
    robot = Robotd(a.sock, hz=50)
    body = Body(a.body_port)
    only = set(a.only.split(","))
    time.sleep(0.5)

    def done(name):
        return os.path.exists(os.path.join(a.out, f"{name}.jsonl.gz"))

    if "step" in only:
        plan = [("vx", s * v) for v in VX for s in (1, -1)] + [("vyaw", s * w) for w in VYAW for s in (1, -1)]
        for rep in range(a.reps):
            rng.shuffle(plan)
            for axis, level in plan:
                name = f"step_{axis}_{level:+.3f}_{rep}"
                if done(name):
                    continue
                settle(robot, body, name)
                with Trial(robot, body, os.path.join(a.out, f"{name}.jsonl.gz")) as tr:
                    tr.hold(0.0, 0.0, rng.uniform(1.0, 2.5))
                    tr.hold(level if axis == "vx" else 0.0, level if axis == "vyaw" else 0.0, a.hold)
                    tr.hold(0.0, 0.0, 3.0)
                print(f"  {name}", flush=True)

    if "ramp" in only:
        for rep in range(max(1, a.reps - 1)):
            for axis, top in (("vx", VX_MAX), ("vx", -VX_MAX), ("vyaw", VYAW_MAX), ("vyaw", -VYAW_MAX)):
                name = f"ramp_{axis}_{top:+.2f}_{rep}"
                if done(name):
                    continue
                settle(robot, body, name)
                with Trial(robot, body, os.path.join(a.out, f"{name}.jsonl.gz")) as tr:
                    tr.hold(0.0, 0.0, 1.5)
                    tr.ramp(0.0, top, 8.0, axis)
                    tr.hold(top if axis == "vx" else 0.0, top if axis == "vyaw" else 0.0, 2.0)
                    tr.ramp(top, 0.0, 8.0, axis)
                    tr.hold(0.0, 0.0, 2.0)
                print(f"  {name}", flush=True)

    if "deadman" in only:
        for rep in range(a.reps):
            name = f"deadman_{rep}"
            if done(name):
                continue
            settle(robot, body, name)
            with Trial(robot, body, os.path.join(a.out, f"{name}.jsonl.gz")) as tr:
                tr.hold(0.0, 0.0, 1.0)
                tr.hold(0.3, 0.0, 3.0)
                tr.lines.append({"k": "silence", "w": time.monotonic()})
                time.sleep(3.0)                 # nothing sent: the deadman's turn
                tr.hold(0.0, 0.0, 1.0)
            print(f"  {name}", flush=True)

    if "rate" in only:
        for hz in (10, 20, 50):
            name = f"rate_{hz}"
            if done(name):
                continue
            other = Robotd(a.sock, hz=hz)
            time.sleep(5.0)
            frames = [(w, p.get("t")) for w, p in other.frames]
            other.close()
            with gzip.open(os.path.join(a.out, f"{name}.jsonl.gz"), "wt") as f:
                for w, t in frames:
                    f.write(json.dumps({"k": "state", "w": w, "t": t}) + "\n")
            print(f"  {name}: {len(frames)} frames in 5 s", flush=True)
    robot.move(0.0, 0.0)
    robot.close()
    body.close()


if __name__ == "__main__":
    main()
