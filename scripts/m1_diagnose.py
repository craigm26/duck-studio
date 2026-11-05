#!/usr/bin/env python3
"""Rescue ladder rung 1, the diagnosis half: read M1's run logs and name the failure signatures.

READS ONLY THE LOGS m1_trial.py WROTE; nothing is edited, nothing is re-run. The plan's three
signatures, each judged per run on the ticks after the pilot's first ask:
- DRIFT: while the ball is dead ahead (|off| < 0.15 rad) and further than the reach, the mean vy
  and the mean vyaw minus what the expert would command on the same states.
- UNDER-TURNING: the heading error to the ball shrinking slower than the expert's on the same
  seed (time until |off| < BallExpert.seen, 30 deg; round 1 used facing, 0.6 rad), and the mean turn toward the ball (sign(off) * vyaw)
  against the expert's labels on the same states.
- OVERSHOOT: ticks inside the reach radius with vx above the dead zone (still walking).
- NO STOP: after the run first reaches, the share of ticks still walking and the mean vx asked;
  and the same under the camera (closer than UNDER_CAMERA, 0.30 m, where the ball has left the
  bottom of the head picture: measured on 40 dataset-v3 episodes, 2026-11-04), where the picture
  holds no ball. Since round 3 the reach (BallExpert.reach, 0.35 m) is outside that, so a driver that
  stops at the line still sees the ball.
A signature is systematic when at least 3 failed runs share it.

THE HEAD CAMERA SEES ABOUT +-37 DEGREES (fovy 45 at 320 x 176), so every number is also split by
whether the ball was in view, judged from the root's heading (the head's own turn is ignored).

    python3 scripts/m1_diagnose.py ~/scratch/ball-takes/m1-v1 --policy ~/scratch/ball-takes/driver-v1/policy.json
"""

import argparse
import json
import math
import pathlib
import statistics
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from record_ball_takes import DEAD_ZONE, PLAIN, REACH, SEEN as FACING, command  # noqa: E402

AHEAD = 0.15
UNDER_CAMERA = 0.30
HALF_HFOV = math.atan(math.tan(math.radians(45 / 2)) * 320 / 176)


def load(path):
    lines = [json.loads(l) for l in open(path)]
    first_ask = next((l["t"] for l in lines if l["type"] == "ask" and "rows" in l), None)
    steps = [l for l in lines if l["type"] == "step"]
    if first_ask is not None:
        steps = [s for s in steps if s["t"] > first_ask + 1e-6]
    return lines[0], steps, [l for l in lines if l["type"] == "ask" and "rows" in l]


def mean(xs):
    return statistics.fmean(xs) if xs else None


def r(x, n=3):
    return None if x is None else round(x, n)


def expert_label(s):
    return command(s["x"], s["y"], s["yaw"], s["bx"], s["by"], 0.0, PLAIN)


def time_to_face(steps):
    t0 = steps[0]["t"] if steps else 0
    for s in steps:
        if abs(s["off"]) < FACING:
            return round(s["t"] - t0, 1)
    return None


def run_report(path, expert_steps, std):
    start, steps, asks = load(path)
    out = {"seed": start["seed"], "bearing_deg": round(start["bearing"]), "range_m": round(start["range"], 2),
           "starts_in_view": abs(start["off"]) < HALF_HFOV}
    view = [s for s in steps if abs(s["off"]) < HALF_HFOV]
    hidden = [s for s in steps if abs(s["off"]) >= HALF_HFOV]
    out["share_in_view"] = r(len(view) / len(steps), 2) if steps else None
    out["closest_m"] = r(min(s["dist"] for s in steps)) if steps else None
    out["reached"] = any(s["dist"] <= REACH for s in steps)
    # Under-turning.
    for name, group in (("hidden", hidden), ("in_view", [s for s in view if abs(s["off"]) > AHEAD])):
        toward = [math.copysign(1, s["off"]) * s["cmd"][2] for s in group]
        label = [math.copysign(1, s["off"]) * expert_label(s)[2] for s in group]
        # The round 2 expert searches RIGHT when the ball is hidden, whichever side it is on, so a
        # hidden "toward" can be negative by design: the raw vyaw against the expert's is beside it.
        out[f"turn_toward_{name}"] = {"ticks": len(group), "driver": r(mean(toward)), "expert": r(mean(label)),
                                      "wrong_way_share": r(mean([t < -0.05 for t in toward]), 2) if group else None,
                                      "vyaw": r(mean([s["cmd"][2] for s in group])),
                                      "expert_vyaw": r(mean([expert_label(s)[2] for s in group]))}
    out["time_to_face_s"] = time_to_face(steps)
    out["expert_time_to_face_s"] = time_to_face(expert_steps)
    # Drift.
    ahead = [s for s in steps if abs(s["off"]) < AHEAD and s["dist"] > REACH]
    out["drift_ahead"] = {"ticks": len(ahead), "vy": r(mean([s["cmd"][1] for s in ahead])),
                          "vyaw_minus_expert": r(mean([s["cmd"][2] - expert_label(s)[2] for s in ahead])),
                          "vx": r(mean([s["cmd"][0] for s in ahead]))}
    # Overshoot.
    inside = [s for s in steps if s["dist"] <= REACH]
    out["overshoot"] = {"ticks_inside": len(inside), "walking_inside": sum(s["cmd"][0] > DEAD_ZONE for s in inside),
                        "final_m": r(steps[-1]["dist"]) if steps else None}
    # No stop.
    first = next((i for i, s in enumerate(steps) if s["dist"] <= REACH), None)
    after = steps[first:] if first is not None else []
    under = [s for s in steps if s["dist"] <= UNDER_CAMERA]
    for name, group in (("after_reach", after), ("under_camera", under)):
        out[name] = {"ticks": len(group), "walking_share": r(mean([s["cmd"][0] > DEAD_ZONE for s in group]), 2),
                     "vx": r(mean([s["cmd"][0] for s in group]))}
    # What the driver asked for (its own rows, before the pilot's clamp and easing).
    rows = [row for a in asks for row in a["rows"][:20]]
    out["asked_mean"] = [r(mean([row[c] for row in rows])) for c in range(3)] if rows else None
    out["asked_vyaw_abs_mean"] = r(mean([abs(row[2]) for row in rows])) if rows else None
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("root")
    p.add_argument("--who", default="driver")
    p.add_argument("--policy", help="the driver's policy.json, for normalised action units")
    a = p.parse_args()
    root = pathlib.Path(a.root).expanduser()
    std = json.load(open(pathlib.Path(a.policy).expanduser()))["act_std"] if a.policy else [1, 1, 1]
    reports = []
    for path in sorted((root / a.who).glob("seed-*.jsonl")):
        seed = path.stem.split("-")[1]
        ex = root / "expert" / f"seed-{seed}.jsonl"
        expert_steps = load(ex)[1] if ex.exists() else []
        reports.append(run_report(path, expert_steps, std))
    failed = [x for x in reports if not x["reached"]]

    def count(pred):
        return sum(1 for x in failed if pred(x))

    under = count(lambda x: (x["turn_toward_hidden"]["ticks"] > 0 and x["turn_toward_hidden"]["driver"] is not None
                             and x["turn_toward_hidden"]["driver"] < 0.5 * x["turn_toward_hidden"]["expert"])
                  or (x["time_to_face_s"] is None or (x["expert_time_to_face_s"] is not None
                                                     and x["time_to_face_s"] > 2 * x["expert_time_to_face_s"])))
    drift = count(lambda x: x["drift_ahead"]["ticks"] >= 10 and (abs(x["drift_ahead"]["vyaw_minus_expert"]) > 0.1
                                                                 or abs(x["drift_ahead"]["vy"]) > 0.01))
    over = sum(1 for x in reports if x["overshoot"]["walking_inside"] > 0)
    no_stop = sum(1 for x in reports if x["reached"] and x["after_reach"]["walking_share"] is not None
                  and x["after_reach"]["walking_share"] > 0.5)
    pooled_ahead = [x["drift_ahead"]["vyaw_minus_expert"] for x in failed if x["drift_ahead"]["ticks"] >= 10]
    summary = {"runs": len(reports), "reached": len(reports) - len(failed), "failed": len(failed),
               "half_hfov_deg": round(math.degrees(HALF_HFOV), 1),
               "signatures_in_failed_runs": {"under_turning": under, "drift": drift},
               "overshoot_runs_any": over,
               "reached_but_kept_walking": no_stop,
               "pooled_after_reach_vx": r(mean([s for x in reports for s in [x["after_reach"]["vx"]] if s is not None])),
               "pooled_under_camera_vx": r(mean([s for x in reports for s in [x["under_camera"]["vx"]] if s is not None])),
               "act_std": std,
               "pooled_failed_ahead_vyaw_offset": r(mean(pooled_ahead)),
               "pooled_failed_ahead_vyaw_offset_normalised": r(mean(pooled_ahead) / std[2]) if pooled_ahead else None,
               "runs_detail": reports}
    out = root / a.who / "diagnosis.json"
    out.write_text(json.dumps(summary, indent=1))
    print(json.dumps({k: v for k, v in summary.items() if k != "runs_detail"}, indent=1))
    for x in reports:
        print(x["seed"], "reached" if x["reached"] else "missed", f"bearing {x['bearing_deg']:+4d}",
              f"in view at start {x['starts_in_view']!s:5}", f"in view {x['share_in_view']}",
              f"closest {x['closest_m']}", "face", x["time_to_face_s"], "vs expert", x["expert_time_to_face_s"],
              "toward(hidden)", x["turn_toward_hidden"]["driver"], "vs", x["turn_toward_hidden"]["expert"],
              "toward(view)", x["turn_toward_in_view"]["driver"], "vs", x["turn_toward_in_view"]["expert"],
              "wrong-way(view)", x["turn_toward_in_view"]["wrong_way_share"],
              "ahead", x["drift_ahead"], "overshoot", x["overshoot"], "after reach", x["after_reach"],
              "under camera", x["under_camera"])


if __name__ == "__main__":
    main()
