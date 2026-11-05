#!/usr/bin/env python3
"""M1's table for any number of arms, from m1_trial.py's folders alone.

Each arm is NAME=FOLDER, the folder holding summary.json and seed-N.jsonl. Besides the summary's
numbers it prints two read from the run logs:

- SEARCH TURN: while the ball is hidden (outside BallExpert.seen, 30 deg), the mean turn commanded,
  as a share of what the expert commands on the same ticks (it searches at full turn);
- ON THE SET: of every row the driver answered (each `ask`), how many a BallExpert could say:
  forward 0 or at least walkStart, no sideways, turn 0 or at least minTurn. 100% is the proof, from
  the run itself, that the rows went through DriverSnap. STANDS HOLD: of the chunks with a row
  whose forward is 0, how many are still from that row on (DriverSnap.chunk).

    python3 scripts/m1_table.py zero=OUT/zero snapped=OUT/driver
"""

import json
import pathlib
import statistics
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from record_ball_takes import MIN_TURN, PLAIN, SEEN, WALK_START, command  # noqa: E402

TOLERANCE = 1e-6


def on_the_set(row):
    vx, vy, vyaw = row
    return (vx == 0 or vx >= WALK_START - TOLERANCE) and vy == 0 and (vyaw == 0 or abs(vyaw) >= MIN_TURN - TOLERANCE)


def stands_hold(rows):
    at = next((i for i, r in enumerate(rows) if r[0] == 0), None)
    return None if at is None else all(r == [0, 0, 0] for r in rows[at:])


def from_logs(folder):
    asked = on = with_stand = held = 0
    driver, expert = [], []
    for path in sorted(folder.glob("seed-*.jsonl")):
        lines = [json.loads(l) for l in open(path)]
        first = next((l["t"] for l in lines if l["type"] == "ask" and "rows" in l), None)
        for l in lines:
            if l["type"] == "ask" and "rows" in l:
                asked += len(l["rows"])
                on += sum(on_the_set(r) for r in l["rows"])
                hold = stands_hold(l["rows"])
                with_stand += hold is not None
                held += hold is True
            elif l["type"] == "step" and first is not None and l["t"] > first and abs(l["off"]) >= SEEN:
                label = command(l["x"], l["y"], l["yaw"], l["bx"], l["by"], 0.0, PLAIN)
                driver.append(l["cmd"][2])
                expert.append(label[2])
    share = statistics.fmean(driver) / statistics.fmean(expert) if driver and statistics.fmean(expert) else None
    return {"search_turn": share, "search_ticks": len(driver), "on_set": on / asked if asked else None, "rows": asked,
            "held": held / with_stand if with_stand else None}


def row(name, folder):
    s = json.loads((folder / "summary.json").read_text())
    extra = from_logs(folder)
    pct = "-" if extra["on_set"] is None else f"{100 * extra['on_set']:.1f}%"
    held = "-" if extra["held"] is None else f"{100 * extra['held']:.0f}%"
    turn = "-" if extra["search_turn"] is None else f"{extra['search_turn']:.2f}"
    return [name, f"{s['reached']}/{s['runs']}", s["parked_at_ball"], s["reached_and_parked"], s["stopped_at_ball"],
            s["mean_time_to_reach_s"], s["median_time_to_reach_s"], s["mean_first_seen_s"], s["never_saw"], s["fell"], turn, pct, held]


def main():
    head = ["arm", "reached", "parked", "reached+parked", "stopped", "reach s (mean)", "reach s (median)", "first seen s",
            "never saw", "fell", "search turn", "on the set", "stands hold"]
    rows = [head]
    for arm in sys.argv[1:]:
        name, _, folder = arm.partition("=")
        rows.append([str(c) for c in row(name, pathlib.Path(folder).expanduser())])
    widths = [max(len(r[i]) for r in rows) for i in range(len(head))]
    for r in rows:
        print(" | ".join(c.ljust(w) for c, w in zip(r, widths)))


if __name__ == "__main__":
    main()
