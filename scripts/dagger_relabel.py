#!/usr/bin/env python3
"""DAgger, one round: turn the driver's own M1-style runs into takes the renderer can draw.

m1_trial.py logs every tick of a run with the bench's FULL state (root, quaternion, 14 joints, ball,
sim time). This reads those logs and writes one take per run in record_ball_takes.py's shape
({"seed", "task", "rows": [{"state", "action", "bench"}]}), so `DuckStudio -render-takes` draws the
pictures the DRIVER visited, not the expert's. Each row's

- `bench` is the state the driver was looking at when it chose its next command (the start, then the
  state after every step);
- `state` is the command in force before it (the driver's own previous command, 0 at the start), as
  the driver sees it at run time;
- `action` is the label: BallExpert's command (PLAIN style) for that bench state.

ROWS DROPPED, ON PURPOSE:
- the ball within PICTURE_EDGE (0.30 m) of the root: it has left the bottom of the picture, so the
  picture is bare floor, and the expert's honest answer there (back up) is not in its vocabulary;
- rows after the expert first says stand, beyond STANDING_ROWS more: a driver that parks for 40 s
  would otherwise flood the set with one picture;
- a run with fewer than 17 rows left after that.

    python3 scripts/dagger_relabel.py ~/scratch/ball-takes/m1-dagger/driver OUT.jsonl
"""

import argparse
import json
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from record_ball_takes import PICTURE_EDGE, STANDING_ROWS, TASK, WALKER, command, yaw_of  # noqa: E402

MIN_ROWS = 17


def relabel(lines):
    """Rows for one run's log lines (dicts). Returns (rows, counts)."""
    rows, previous, standing = [], (0.0, 0.0, 0.0), 0
    counts = {"ticks": 0, "under": 0, "standing_cut": 0}
    for d in lines:
        if d.get("type") not in ("start", "step"):
            continue
        if d["type"] == "step":
            previous = tuple(float(v) for v in d["cmd"])
        bench = d.get("bench")
        if bench is None:
            raise SystemExit("this log has no full bench state: record it with round 3's m1_trial.py")
        if d["type"] == "start":
            previous = (0.0, 0.0, 0.0)
        counts["ticks"] += 1
        x, y = bench["position"][0], bench["position"][1]
        bx, by = bench["ball"][0], bench["ball"][1]
        if math.hypot(bx - x, by - y) < PICTURE_EDGE:
            counts["under"] += 1
            continue
        label = command(x, y, yaw_of(bench["quaternion"]), bx, by, 0.0)
        if label == (0.0, 0.0, 0.0):
            standing += 1
            if standing > STANDING_ROWS + 1:
                counts["standing_cut"] += 1
                continue
        rows.append({"state": list(previous), "action": list(label), "bench": bench})
    return rows, counts


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("logs", help="m1_trial.py OUT/WHO folder (seed-N.jsonl)")
    p.add_argument("out", help="takes JSONL to write")
    a = p.parse_args()
    logs = sorted(pathlib.Path(a.logs).expanduser().glob("seed-*.jsonl"))
    if not logs:
        raise SystemExit(f"no seed-*.jsonl in {a.logs}")
    kept = rows_total = 0
    totals = {"ticks": 0, "under": 0, "standing_cut": 0, "dropped_runs": 0}
    with open(pathlib.Path(a.out).expanduser(), "w") as f:
        for path in logs:
            lines = [json.loads(l) for l in path.read_text().splitlines() if l.strip()]
            seed = next(d["seed"] for d in lines if d.get("type") == "start")
            rows, counts = relabel(lines)
            for k, v in counts.items():
                totals[k] += v
            if len(rows) < MIN_ROWS:
                totals["dropped_runs"] += 1
                print(f"seed {seed} dropped: {len(rows)} rows", flush=True)
                continue
            f.write(json.dumps({"seed": seed, "task": TASK, "walker": WALKER, "hold": 0.1, "dagger": True,
                                "rows": rows}) + "\n")
            kept += 1
            rows_total += len(rows)
    print(json.dumps({"takes": kept, "rows": rows_total, **totals}))


if __name__ == "__main__":
    main()
