"""How far short a Walk card should stop, from the system identification only.

    python3 cardreader/sim/results-walkback/walk_lead_from_sysid.py cardreader/sim/sysid/raw

Reads the `step_vx_*` trials of `cardreader/sim/sysid/raw/` (each a step held 5 s, then 3 s
still; robotd's state at 50 Hz and MuJoCo's trunk at 50 Hz, both stamped with the client's wall
clock) at the speeds a Walk card sends (forward 0.30, 0.35, 0.40; back 0.40, and 0.35 for
reference) and measures, per trial:

- `coast`: the trunk's travel along its heading from the zero command to the end of the trial
  (sysid_fit.py's "coast after stop").
- `lag`: how late robotd's `odom` is against the trunk, as the client sees it: the shift that
  best lines odometry's along-track displacement up with the trunk's over the last 2.5 s of the
  hold (least squares over shifts of 0 to 400 ms, 5 ms apart).
- `v`: the trunk's steady speed over the same 2.5 s.
- `settle`: how long after the zero command the trunk takes to cover 95% of its coast.

A card decides on the newest frame it was handed, at its next control tick. The frame that first
says the card has reached its stop line is past that line by half a frame gap on average, the
tick comes half a control period after the frame on average, and the frame was `lag` old when it
was made. So the travel past the stop line, which is what a Walk card must stop short by, is
expected to be

    lead = coast + v * (lag + gap / 2 + tick / 2)

with `gap` the client's frame gap (sysid: 60 ms at 20 Hz, 101 ms at 10 Hz, medians) and `tick`
the control period (1 / 20 Hz). Printed per direction, at both state rates, median and range.
Nothing here reads the Monte Carlo.
"""

from __future__ import annotations

import gzip
import json
import math
import pathlib
import statistics as st
import sys

import numpy as np

GAP_S = {"20 Hz": 0.060, "10 Hz": 0.101}   # sysid.md: robot.subscribe gap medians
TICK_S = 1.0 / 20


def load(path):
    out = {"cmd": [], "state": [], "truth": []}
    with gzip.open(path, "rt") as f:
        for line in f:
            d = json.loads(line)
            out.setdefault(d["k"], []).append(d)
    return out


def trial(path):
    d = load(path)
    cmd = d["cmd"]
    nz = [c for c in cmd if abs(c["vx"]) > 0]
    w0 = nz[0]["w"]
    w1 = next(c["w"] for c in cmd if c["w"] > w0 and c["vx"] == 0)
    sign = 1.0 if nz[0]["vx"] > 0 else -1.0
    tr = d["truth"]
    tw = np.array([p["w"] for p in tr])
    i0 = int(np.searchsorted(tw, w0))
    h0 = tr[i0]["yaw"]
    c, s = math.cos(h0), math.sin(h0)
    talong = sign * np.array([(p["x"] - tr[i0]["x"]) * c + (p["y"] - tr[i0]["y"]) * s for p in tr])
    stt = [q for q in d["state"] if q.get("odom")]
    sw = np.array([q["w"] for q in stt])
    j0 = int(np.searchsorted(sw, w0))
    o0 = stt[j0]["odom"]["position"]
    oalong = sign * np.array([(q["odom"]["position"][0] - o0[0]) * c + (q["odom"]["position"][1] - o0[1]) * s
                              for q in stt])
    j1 = int(np.searchsorted(sw, w1))
    coast = float(oalong[-1] - oalong[j1])
    after = oalong[j1:] - oalong[j1]
    k = int(np.argmax(after >= 0.99 * coast)) if coast > 0 else 0
    settle = float(sw[j1 + k] - w1)
    win = (sw > w1 - 2.5) & (sw <= w1)
    v = float(np.polyfit(sw[win], oalong[win], 1)[0])
    scale = float(oalong[-1] / talong[-1])
    return {"u": nz[0]["vx"], "coast": coast, "v": v, "settle": settle, "scale": scale,
            "tcoast": float(talong[-1] - talong[int(np.searchsorted(tw, w1))])}


def main():
    raw = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "cardreader/sim/sysid/raw")
    rows = {}
    for level in ("+0.300", "+0.350", "+0.400", "-0.350", "-0.400"):
        rows[level] = [trial(p) for p in sorted(raw.glob(f"step_vx_{level}_*.jsonl.gz"))]
    print("| command | trials | odometry coast (m) | trunk coast (m) | odometry speed (m/s) | 99% of coast after (s) |"
          " odometry / trunk distance | lead at 20 Hz (m) | lead at 10 Hz (m) |")
    print("|---|---|---|---|---|---|---|---|---|")

    def rng(vals, f):
        return f"{f.format(st.median(vals))} [{f.format(min(vals))} to {f.format(max(vals))}]"
    for level, ts in rows.items():
        leads = {k: [t["coast"] + abs(t["v"]) * (g / 2 + TICK_S / 2) for t in ts] for k, g in GAP_S.items()}
        print(f"| {level} | {len(ts)} | {rng([t['coast'] for t in ts], '{:.3f}')} | {rng([t['tcoast'] for t in ts], '{:.3f}')} |"
              f" {rng([abs(t['v']) for t in ts], '{:.3f}')} | {rng([t['settle'] for t in ts], '{:.2f}')} |"
              f" {rng([t['scale'] for t in ts], '{:.3f}')} |"
              f" {rng(leads['20 Hz'], '{:.3f}')} | {rng(leads['10 Hz'], '{:.3f}')} |")


if __name__ == "__main__":
    main()
