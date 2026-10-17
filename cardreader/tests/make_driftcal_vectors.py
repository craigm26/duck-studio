"""Write cardreader/vectors/driftcal/*.json: duck-card-loop/3's drift calibration, op by op.

    python3 cardreader/tests/make_driftcal_vectors.py          # rewrite them
    python3 cardreader/tests/make_driftcal_vectors.py --check  # exit 1 if any would change

A vector is a `calibrate` block and a list of ops: `["still", [[t, yaw], ...]]` is one still
window's samples, followed by the drift rate (rad/s) it must leave; `["correct", [t, x, y, h],
[x, y, h]]` is one raw pose and the corrected pose it must give. `cardloop.DriftCal` here and
`DuckCardLoop.DriftCal` in StudioKit must both produce every expectation. Pure Python.
"""

from __future__ import annotations

import json
import math
import pathlib
import random
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from duckcards.cardloop import DriftCal, Pose  # noqa: E402

OUT = HERE.parent / "vectors" / "driftcal"
CAL = {"before_s": 5.0, "still_after_s": 0.3, "max_dps": 1.0}


def r(v: float) -> float:
    return round(v, 9)


def window(t0, seconds, rate, h0=0.0, noise=0.0, rng=None, hz=10, coast=None):
    out = []
    for i in range(int(seconds * hz)):
        t = t0 + i / hz
        y = h0 + rate * (t - t0) + (rng.gauss(0, noise) if rng else 0.0)
        if coast and i < 2:
            y += coast * (2 - i)
        out.append([r(t), r(math.atan2(math.sin(y), math.cos(y)))])
    return out


def walk(t0, n, rate, speed=0.1, hz=10, h0=0.0, start=(0.0, 0.0)):
    """Raw odometry of a duck walking straight at `speed` while its heading reading drifts at `rate`."""
    x, y = start
    out = []
    for i in range(n):
        t = t0 + i / hz
        h = h0 + rate * (t - t0)
        if i:
            x += speed / hz * math.cos(h)
            y += speed / hz * math.sin(h)
        out.append([r(t), r(x), r(y), r(math.atan2(math.sin(h), math.cos(h)))])
    return out


def build(name, ops_in, cal=CAL):
    c = DriftCal(cal)
    ops = []
    for op in ops_in:
        if op[0] == "still":
            c.begin_still()
            for t, yaw in op[1]:
                c.sample_still(t, yaw)
            c.end_still()
            ops.append(["still", op[1], r(c.rate)])
        else:
            for t, x, y, h in op[1]:
                p = c.correct(t, Pose(x, y, h))
                ops.append(["correct", [t, x, y, h], [r(p.x), r(p.y), r(p.h)]])
    return name, {"calibrate": cal, "ops": ops}


def vectors():
    rng = random.Random(7)
    d = math.radians(0.4)
    yield build("clean_drift", [["still", window(0.0, 5.0, d)], ["correct", walk(5.0, 40, d)]])
    yield build("noisy_drift", [["still", window(0.0, 5.0, -d, noise=math.radians(0.5), rng=rng)],
                                ["correct", walk(5.0, 40, -d)]])
    yield build("coast_is_skipped", [["still", window(0.0, 3.0, d, coast=0.2)]])
    yield build("windows_pool", [["still", window(0.0, 2.0, d)], ["correct", walk(2.0, 10, d)],
                                 ["still", window(10.0, 1.0, d, h0=2.9)], ["correct", walk(11.0, 10, d, h0=2.9)]])
    yield build("heading_wraps_past_pi", [["still", window(0.0, 4.0, math.radians(0.8), h0=math.pi - 0.01)]])
    yield build("rate_is_clamped", [["still", window(0.0, 5.0, math.radians(20))]])
    yield build("too_few_samples", [["still", window(0.0, 0.5, d)]])


def main():
    check = "--check" in sys.argv
    OUT.mkdir(parents=True, exist_ok=True)
    bad = 0
    for name, v in vectors():
        p = OUT / f"{name}.json"
        text = json.dumps(v, indent=1) + "\n"
        if check:
            if not p.exists() or p.read_text() != text:
                print(f"{p.name} would change")
                bad += 1
        else:
            p.write_text(text)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
