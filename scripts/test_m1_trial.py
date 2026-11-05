#!/usr/bin/env python3
"""m1_trial.py's scoring, on made-up logs: no bench, no Mac.

    python3 -m unittest scripts/test_m1_trial.py
"""

import json
import math
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import m1_trial  # noqa: E402
from statistics import StatisticsError as statistics_error  # noqa: E402


def write_log(folder, who, ticks, ball_moves=0.0, start_off=2.0, ask_at=1.2):
    """A run straight down the x axis toward a ball at x = 1: `ticks` is a list of (x, cmd)."""
    path = pathlib.Path(folder) / f"seed-{len(list(pathlib.Path(folder).iterdir())) + 1}.jsonl"
    lines = [{"type": "start", "seed": 7, "who": who, "bearing": 0, "range": 1.0, "t": 0.0, "x": 0.0, "y": 0.0,
              "yaw": 0.0, "bx": 1.0, "by": 0.0, "dist": 1.0, "off": start_off, "upright": True}]
    if who != "expert":
        lines.append({"type": "ask", "op": "ask", "t": ask_at, "ms": 5, "rows": [[0, 0, 0]]})
    for i, (x, cmd) in enumerate(ticks):
        t = ask_at + 0.1 * (i + 1) if who != "expert" else 0.1 * (i + 1)
        bx = 1.0 + ball_moves * (i + 1) / len(ticks)
        off = start_off if i < 3 else 0.0
        lines.append({"type": "step", "cmd": cmd, "t": round(t, 3), "x": x, "y": 0.0, "yaw": 0.0, "bx": bx,
                      "by": 0.0, "dist": abs(bx - x), "off": off, "upright": True})
    if who != "expert":
        lines += [{"type": "stop", "op": "stop"}, {"type": "end", "op": "end"}, {"type": "ended", "op": "ended"}]
    path.write_text("".join(json.dumps(l) + "\n" for l in lines))
    return path


WALK, STILL = [0.2, 0.0, 0.0], [0.0, 0.0, 0.0]


class ScoreTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)

    def test_reaches_and_stands_is_stopped_at_the_ball(self):
        ticks = [(0.1 * i, WALK) for i in range(1, 9)] + [(0.82, STILL)] * 12
        r = m1_trial.score(write_log(self.dir.name, "driver", ticks))
        self.assertTrue(r["reached"])
        self.assertTrue(r["standing_at_end"])
        self.assertTrue(r["stopped_at_ball"])
        self.assertAlmostEqual(r["time_s"], 0.7)        # first tick within REACH, 0.35 m: x = 0.7 at t = 1.2 + 0.7
        self.assertAlmostEqual(r["first_seen_s"], 0.4)  # the heading comes within the camera on the 4th tick
        self.assertEqual(r["ball_push_m"], 0.0)
        self.assertEqual(r["moved_last_s_m"], 0.0)
        self.assertTrue(r["ended_stop_then_end"])

    def test_walking_through_reaches_but_does_not_stop(self):
        ticks = [(0.1 * i, WALK) for i in range(1, 16)]
        r = m1_trial.score(write_log(self.dir.name, "driver", ticks, ball_moves=0.4))
        self.assertTrue(r["reached"])
        self.assertFalse(r["standing_at_end"])
        self.assertFalse(r["stopped_at_ball"])
        self.assertFalse(r["parked_at_ball"])
        self.assertAlmostEqual(r["ball_push_m"], 0.4)

    def test_a_creep_above_the_dead_zone_is_not_standing(self):
        creep = [m1_trial.DEAD_ZONE + 0.035, 0.0, 0.0]   # the v3 driver's standing vx, 0.085
        ticks = [(0.1 * i, WALK) for i in range(1, 9)] + [(0.82, creep)] * 12
        r = m1_trial.score(write_log(self.dir.name, "driver", ticks))
        self.assertTrue(r["reached"])
        self.assertFalse(r["stopped_at_ball"])
        self.assertTrue(r["parked_at_ball"])          # the walker did not step for it: still, so parked

    def test_standing_short_of_the_line_is_not_stopped(self):
        ticks = [(0.1 * i, WALK) for i in range(1, 5)] + [(0.4, STILL)] * 12
        r = m1_trial.score(write_log(self.dir.name, "driver", ticks))
        self.assertFalse(r["reached"])
        self.assertTrue(r["standing_at_end"])
        self.assertFalse(r["stopped_at_ball"])       # 0.6 m away
        self.assertIsNone(r["time_s"])

    def test_never_seen(self):
        ticks = [(0.0, STILL)] * 2
        r = m1_trial.score(write_log(self.dir.name, "zero", ticks))
        self.assertIsNone(r["first_seen_s"])
        self.assertFalse(r["starts_in_view"])

    def test_expert_clock_starts_at_the_start(self):
        ticks = [(0.1 * i, WALK) for i in range(1, 9)] + [(0.82, STILL)] * 16
        r = m1_trial.score(write_log(self.dir.name, "expert", ticks))
        self.assertAlmostEqual(r["time_s"], 0.7)
        self.assertTrue(r["stopped_at_ball"])
        self.assertIsNone(r["ended_stop_then_end"])

    def test_summary_counts(self):
        stop = m1_trial.score(write_log(self.dir.name, "driver", [(0.1 * i, WALK) for i in range(1, 9)]
                                        + [(0.82, STILL)] * 12))
        through = m1_trial.score(write_log(self.dir.name, "driver", [(0.1 * i, WALK) for i in range(1, 16)],
                                           ball_moves=0.4))
        s = m1_trial.summarize("driver", "7", [stop, through])
        self.assertEqual((s["runs"], s["reached"], s["stopped_at_ball"], s["reached_and_stopped"]), (2, 2, 1, 1))
        self.assertEqual((s["parked_at_ball"], s["reached_and_parked"]), (1, 1))
        self.assertAlmostEqual(s["mean_ball_push_m"], 0.2)
        self.assertEqual(s["never_saw"], 0)


class FullStateTests(unittest.TestCase):
    """Round 3: every tick keeps the bench's whole state, so DAgger can draw the driver's own pictures."""

    def test_start_and_every_step_carry_the_bench_state(self):
        def state(t, x):
            return {"t": t, "position": [x, 0.0, 0.116], "quaternion": [1, 0, 0, 0], "upright": True,
                    "joints": [0.01 * i for i in range(14)], "ball": [1.0, 0.0, 0.05], "ballRadius": 0.05}
        with tempfile.TemporaryDirectory() as d:
            run = m1_trial.Run(pathlib.Path(d), "expert", 7, 0.0, 1.0, state(0.5, 0.0))
            run.see(state(0.6, 0.1), [0.25, 0.0, 0.0])
            run.see(state(0.7, 0.2), [0.25, 0.0, 0.0])
            run.f.close()
            lines = [json.loads(l) for l in open(run.path)]
        self.assertEqual([l["type"] for l in lines], ["start", "step", "step"])
        self.assertEqual(lines[0]["bench"], state(0.5, 0.0))
        self.assertEqual(lines[2]["bench"]["joints"], state(0.7, 0.2)["joints"])
        self.assertEqual(lines[2]["bench"]["position"], [0.2, 0.0, 0.116])
        self.assertAlmostEqual(lines[2]["dist"], 0.8)

    def test_stopped_line_is_past_the_reach(self):
        self.assertEqual(m1_trial.REACH, 0.35)
        self.assertAlmostEqual(m1_trial.STOPPED_M, 0.40)


class AppStartTests(unittest.TestCase):
    """The flag that was parsed and never read: a run called "app start" was not one."""

    def test_the_flag_reaches_setup_and_settles_on_stop(self):
        calls = []
        real, flag, argv = m1_trial.call, m1_trial.APP_START, sys.argv
        m1_trial.call = lambda bench, path, body: calls.append(path) or {}
        try:
            with tempfile.TemporaryDirectory() as out:
                sys.argv = ["m1_trial.py", "--who", "expert", "--app-start", "--rescore", "--out", out]
                try:
                    m1_trial.main()
                except (ValueError, IndexError, SystemExit, statistics_error):
                    pass  # no logs to score; only the flag matters here
            self.assertTrue(m1_trial.APP_START)
            m1_trial.setup("bench", 8001)
            self.assertEqual(calls, ["/reset", "/policy", "/ball", "/stop"])
        finally:
            m1_trial.call, m1_trial.APP_START, sys.argv = real, flag, argv


class SeedTests(unittest.TestCase):
    def test_ranges_and_lists(self):
        self.assertEqual(m1_trial.parse_seeds("5001-5003"), [5001, 5002, 5003])
        self.assertEqual(m1_trial.parse_seeds("5001-5002,6001-6002"), [5001, 5002, 6001, 6002])
        self.assertEqual(m1_trial.parse_seeds("9"), [9])

    def test_half_width_is_the_cameras(self):
        self.assertAlmostEqual(math.degrees(m1_trial.HALF_HFOV), 36.98, places=2)


if __name__ == "__main__":
    unittest.main()
