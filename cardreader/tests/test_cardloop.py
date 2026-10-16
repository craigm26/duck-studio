"""Walk and Turn cards on odometry: the vectors StudioKit is held to, and the runner's loop.

    python3 -m unittest discover -s cardreader/tests -p test_cardloop.py -v
"""

from __future__ import annotations

import json
import math
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from duckcards import cardloop, runner  # noqa: E402
from duckcards.program import Step  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
VECTORS = ROOT / "cardreader" / "vectors" / "cardloop"
KIT_SPEC = ROOT / "StudioKit" / "Sources" / "StudioKit" / "Resources" / "DuckCards" / "duck-card-loop.json"


class Spec(unittest.TestCase):
    def test_the_reader_carries_studiokits_spec_byte_for_byte(self):
        self.assertEqual(cardloop.SPEC_FILE.read_bytes(), KIT_SPEC.read_bytes())

    def test_the_reader_carries_studiokits_envelope_byte_for_byte(self):
        kit = KIT_SPEC.parent / "pollen-pad-drive.json"
        self.assertEqual(cardloop.ENVELOPE_FILE.read_bytes(), kit.read_bytes())

    def test_the_envelope_is_pollens_pad_drive_defaults_at_a_cited_commit(self):
        env = cardloop.ENVELOPE
        self.assertEqual((env["vx"], env["vy"], env["vyaw"]), ([-0.4, 0.4], [-0.3, 0.3], [-1.0, 1.0]))
        self.assertIn("robotd-params/src/lib.rs", env["source"])
        self.assertIn("PadDriveParams", env["source"])
        self.assertRegex(env["commit"], r"^[0-9a-f]{40}$")

    def test_no_card_commands_more_than_pollens_envelope(self):
        self.assertEqual(cardloop.envelope_problems(cardloop.SPEC), [])

    def test_a_spec_past_the_envelope_is_named(self):
        import copy
        spec = copy.deepcopy(cardloop.SPEC)
        spec["walk"]["back_speed"]["fast"] = 0.45
        spec["turn"]["yaw_rate"]["slow"] = 1.5
        problems = cardloop.envelope_problems(spec)
        self.assertEqual(len(problems), 2, problems)
        self.assertEqual(problems, ["walk.back_speed.fast is 0.45, past Pollen's pad envelope of 0.4",
                                    "turn.yaw_rate.slow is 1.5, past Pollen's pad envelope of 1"])

    def test_the_runners_timed_twists_are_inside_the_envelope_too(self):
        env = cardloop.ENVELOPE
        self.assertLessEqual(runner.MAX_FORWARD, env["vx"][1])
        self.assertLessEqual(runner.MAX_BACKWARD, -env["vx"][0])
        self.assertLessEqual(runner.MAX_TURN, env["vyaw"][1])
        self.assertEqual((runner.MAX_FORWARD, runner.MAX_BACKWARD, runner.MAX_TURN), (0.3, 0.3, 1.0),
                         "DuckDrive.maxForward, maxBackward and maxTurn are these numbers; change both together")

    def test_every_speed_clears_the_dead_band_measured_in_duck_sim(self):
        # cardreader/sim/sysid/sysid.md: v8 velstand under Pollen's robotd in duck-sim stands still
        # at 0.20 forward and walks every time from 0.25; stands still at -0.30 and walks from
        # -0.35; turns in place every time from 0.625 left and 0.5 right.
        for label in ("slow", "normal", "fast"):
            self.assertGreaterEqual(cardloop.SPEC["walk"]["speed"][label], 0.25)
            self.assertGreaterEqual(cardloop.SPEC["walk"]["back_speed"][label], 0.35)
            self.assertGreaterEqual(cardloop.SPEC["turn"]["yaw_rate"][label], 0.625)
        self.assertGreaterEqual(cardloop.SPEC["turn"]["trim_rate"], 0.625)

    def test_the_caps_fit_the_acceptance_time_bounds(self):
        # docs/PACKS.md, "Acceptance": a Walk card in at most 8 s, a Turn card in at most 6 s.
        self.assertLessEqual(cardloop.SPEC["walk"]["max_s"], 8)
        self.assertLessEqual(cardloop.SPEC["turn"]["max_s"], 6)


class Vectors(unittest.TestCase):
    def test_every_vector(self):
        files = sorted(VECTORS.glob("*.json"))
        self.assertGreaterEqual(len(files), 10)
        for f in files:
            v = json.loads(f.read_text())
            with self.subTest(v["name"]):
                loop = cardloop.CardLoop(v["action"], cardloop.Pose(*v["board"]), v["speed"],
                                         lead_deg=v["lead_deg"], lead_m=v["lead_m"])
                for (t, x, y, yaw), want in zip(v["trace"], v["expect"]):
                    got = loop.step(cardloop.Pose(x, y, yaw), t)
                    if isinstance(want, str):
                        self.assertEqual(got, want)
                    else:
                        self.assertIsInstance(got, tuple, f"t={t}")
                        self.assertAlmostEqual(got[0], want[0], places=6)
                        self.assertAlmostEqual(got[1], want[1], places=6)
                after = loop.board_after
                for a, b in zip((after.x, after.y, after.h), v["board_after"]):
                    self.assertAlmostEqual(a, b, places=6)
                if v["coast_deg"] is None:
                    self.assertIsNone(loop.coast_deg)
                else:
                    self.assertAlmostEqual(loop.coast_deg, v["coast_deg"], places=5)
                if v["coast_m"] is None:
                    self.assertIsNone(loop.coast_m)
                else:
                    self.assertAlmostEqual(loop.coast_m, v["coast_m"], places=6)

    def test_the_vectors_are_what_this_reader_writes(self):
        import make_cardloop_vectors
        want = make_cardloop_vectors.bodies()
        have = {p.stem: p.read_text() for p in VECTORS.glob("*.json")}
        self.assertEqual(have, want)


class Odometry(unittest.TestCase):
    def test_robotds_three_element_position(self):
        p = cardloop.odometry({"odom": {"position": [0.1, -0.2, 0.12], "yaw": 0.5}})
        self.assertEqual(p, cardloop.Pose(0.1, -0.2, 0.5))

    def test_a_robotd_without_odometry(self):
        self.assertIsNone(cardloop.odometry({"safety": {"fallen": False}}))
        self.assertIsNone(cardloop.odometry(None))
        self.assertIsNone(cardloop.odometry({"odom": {"position": [0.1], "yaw": 0.0}}))
        self.assertIsNone(cardloop.odometry({"odom": {"position": [0.1, 0.2, 0.0]}}))


class FakeDuck:
    """A duck that goes where it is told, at a fraction of the command, and reports odometry."""

    def __init__(self, odom=True, walk=0.45, turn=0.9, falls_at=None):
        self.falls_at = falls_at        # metres walked when it falls, or None
        self.x = self.y = self.h = 0.0
        self.twist = (0.0, 0.0)
        self.odom, self.walk, self.turn = odom, walk, turn
        self.now = 1000.0
        self.calls, self.moves = [], []

    def call(self, method, params=None):
        self.calls.append((method, params))
        if method == "robot.skills":
            return {"skills": [], "built_in": ["kick_left", "kick_right"]}
        if method == "robot.do":
            self.x += 0.05 * math.cos(self.h)      # a kick nudges the duck
            self.y += 0.05 * math.sin(self.h)
        return {"accepted": True}

    def notify(self, method, params=None):
        if method == "robot.move":
            self.moves.append(params)
            self.twist = (params["vx"], params["vyaw"])

    def sleep(self, dt):
        vx, vyaw = self.twist
        self.h += self.turn * vyaw * dt
        self.x += self.walk * vx * dt * math.cos(self.h)
        self.y += self.walk * vx * dt * math.sin(self.h)
        self.now += dt

    def clock(self):
        return self.now

    def state(self):
        fallen = self.falls_at is not None and math.hypot(self.x, self.y) >= self.falls_at
        params = {"safety": {"fallen": fallen}}
        if self.odom:
            params["odom"] = {"position": [self.x, self.y, 0.12], "yaw": self.h}
        return params, self.now


def step(action, speed="normal"):
    return Step(labels={"action": action, "speed": speed}, clause=action.replace("_", " "), cards=[action])


class Runs(unittest.TestCase):
    def run_row(self, duck, actions, said):
        # Measured cards on, as `watch --measured-cards` turns them on: they ship off (OffSwitch).
        return runner.run(runner.beats([step(a) if isinstance(a, str) else step(*a) for a in actions]), duck,
                          sleep=duck.sleep, say=said.append, state=duck.state, clock=duck.clock, measured=True)

    def test_walk_turn_walk_lands_on_the_board(self):
        duck, said = FakeDuck(), []
        self.assertEqual(self.run_row(duck, ["walk_forward", "turn_left", "walk_forward"], said), "finished")
        d = cardloop.SPEC["square_m"]
        self.assertAlmostEqual(duck.x, d, delta=0.03)
        self.assertAlmostEqual(duck.y, d, delta=0.03)
        self.assertLess(abs(cardloop.wrap(duck.h - math.pi / 2)), math.radians(cardloop.SPEC["turn"]["tolerance_deg"]) + 0.05)
        self.assertNotIn(runner.TIMED_NOTE, " ".join(said))
        self.assertEqual(duck.calls[-1][0], "robot.stop")

    def test_a_skill_puts_the_board_square_where_the_duck_stands(self):
        duck, said = FakeDuck(), []
        self.run_row(duck, ["walk_forward", "kick_left", "walk_forward"], said)
        d = cardloop.SPEC["square_m"]
        # The kick's 5 cm is not walked back: the second card is one square from where it stood.
        self.assertAlmostEqual(duck.x, 2 * d + 0.05, delta=0.03)

    def test_a_duck_without_odometry_runs_the_timed_cards_and_says_so_once(self):
        duck, said = FakeDuck(odom=False), []
        self.run_row(duck, ["walk_forward", "turn_right"], said)
        self.assertEqual(sum(1 for s in said if runner.TIMED_NOTE in s), 1)
        self.assertEqual(len(duck.moves), 2 * round(runner.DEFAULT_SECONDS / runner.TICK))
        self.assertEqual(duck.moves[0], {"vx": runner.MAX_FORWARD * 2 / 3, "vy": 0.0, "vyaw": 0.0})

    def test_no_state_stream_at_all_is_timed_too(self):
        duck, said = FakeDuck(), []
        runner.run(runner.beats([step("walk_forward")]), duck, sleep=duck.sleep, say=said.append, measured=True)
        self.assertTrue(any(runner.TIMED_NOTE in s for s in said))

    def test_a_pose_that_stops_arriving_stops_the_card(self):
        duck, said = FakeDuck(), []
        frozen = duck.state()
        runner.run(runner.beats([step("walk_forward")]), duck, sleep=duck.sleep, say=said.append,
                   state=lambda: frozen, clock=duck.clock, measured=True)
        self.assertTrue(any(runner.LOST_NOTE in s for s in said))

    def test_a_fall_mid_card_ends_the_row_still_and_says_so(self):
        duck, said = FakeDuck(falls_at=0.1), []
        out = self.run_row(duck, ["walk_forward", "turn_left", "walk_forward"], said)
        self.assertEqual(out, f"stopped at walk forward: {runner.FELL_NOTE}")
        self.assertIn(f"  {runner.FELL_NOTE}", said)
        self.assertEqual(duck.moves[-1], {"vx": 0.0, "vy": 0.0, "vyaw": 0.0})
        self.assertEqual(duck.calls[-1][0], "robot.stop")
        self.assertLess(duck.x, 0.2, "the row did not go on to the next card")

    def test_a_card_that_runs_out_of_time_ends_the_row(self):
        duck, said = FakeDuck(walk=0.07), []    # creeps: never stalls, never arrives in max_s
        out = self.run_row(duck, ["walk_forward", "turn_left"], said)
        self.assertEqual(out, "stopped at walk forward: " + runner.ENDED["out of time"])
        self.assertFalse(any(m["vyaw"] > 0.7 for m in duck.moves), "the Turn card never ran")
        self.assertEqual(duck.calls[-1][0], "robot.stop")

    def test_each_later_turn_leads_by_the_rows_mean_measured_coast(self):
        made = []
        real = cardloop.CardLoop

        class Spy(real):
            def __init__(self, *a, **k):
                super().__init__(*a, **k)
                made.append(self)
        cardloop.CardLoop = Spy
        try:
            duck, said = FakeDuck(), []
            self.run_row(duck, ["turn_left", "walk_forward", "turn_right", "turn_left"], said)
        finally:
            cardloop.CardLoop = real
        turns = [c for c in made if c.action.startswith("turn")]
        self.assertEqual(turns[0].lead, cardloop.SPEC["turn"]["approach_deg"], "the first knows nothing yet")
        self.assertIsNotNone(turns[0].coast_deg)
        self.assertAlmostEqual(turns[1].lead, turns[0].coast_deg)
        self.assertAlmostEqual(turns[2].lead, (turns[0].coast_deg + turns[1].coast_deg) / 2)

    def test_each_later_walk_leads_by_the_rows_mean_measured_coast_that_way(self):
        # duck-card-loop/2, THE WALK LEAD: forward and back are kept apart, as their coasts are.
        made = []
        real = cardloop.CardLoop

        class Spy(real):
            def __init__(self, *a, **k):
                super().__init__(*a, **k)
                made.append(self)
        cardloop.CardLoop = Spy
        try:
            duck, said = FakeDuck(), []
            self.assertEqual(self.run_row(duck, ["walk_forward", "walk_backward", "walk_forward", "walk_backward",
                                                 "walk_backward"], said), "finished")
        finally:
            cardloop.CardLoop = real
        fwd = [c for c in made if c.action == "walk_forward"]
        back = [c for c in made if c.action == "walk_backward"]
        w = cardloop.SPEC["walk"]
        self.assertAlmostEqual(fwd[0].lead_m, w["approach_m"] + w["slip_m"], msg="the first forward knows nothing yet")
        self.assertAlmostEqual(back[0].lead_m, w["back_approach_m"] + w["back_slip_m"],
                               msg="nor does the first back, after a forward")
        for c in fwd + back:
            self.assertIsNotNone(c.coast_m)
        self.assertAlmostEqual(fwd[1].lead_m, fwd[0].coast_m + w["slip_m"])
        self.assertAlmostEqual(back[1].lead_m, back[0].coast_m + w["back_slip_m"])
        self.assertAlmostEqual(back[2].lead_m, (back[0].coast_m + back[1].coast_m) / 2 + w["back_slip_m"])
        # This duck stops dead (no coast) and its odometry does not slip, so the last card, leading
        # by the coast it measured and the slip, stops the slip short of its square (one back from
        # the start), not the approach short of it.
        self.assertAlmostEqual(duck.x, -cardloop.SPEC["square_m"] + w["back_slip_m"], delta=0.012)

    def test_row_lead_is_the_mean_or_nothing(self):
        self.assertIsNone(cardloop.row_lead([]))
        self.assertAlmostEqual(cardloop.row_lead([0.02, 0.04]), 0.03)

    def test_a_card_that_makes_no_progress_is_stuck_and_ends_the_row(self):
        # v8 velstand in duck-sim stands still below 0.25 forward and -0.35 back
        # (cardreader/sim/sysid): a duck that does not move is told so in stall_s, not max_s.
        duck, said = FakeDuck(walk=0.0), []     # stands still
        out = self.run_row(duck, ["walk_forward", "turn_left"], said)
        self.assertEqual(out, "stopped at walk forward: " + runner.ENDED["stuck"])
        self.assertFalse(any(m["vyaw"] > 0.5 for m in duck.moves), "the Turn card never ran")
        self.assertEqual(duck.calls[-1][0], "robot.stop")

    def test_the_endings_say_studiokits_words(self):
        # RobotPlanRunner.CardEnd.said, word for word.
        self.assertEqual(runner.ENDED, {
            "reached": None,
            "lost": "The duck stopped reporting where it is, so the row stopped there.",
            "fell": "The duck fell, so the row stopped there.",
            "out of time": "The card ran out of time before it got there, so the row stopped there.",
            "trimmed out": "The card stopped short of a quarter turn after its trims, so the row stopped there.",
            "stuck": "The duck could not do this card at the speeds it may be sent, so the row stopped there.",
        })

    def test_odometry_lost_mid_row_ends_the_row_rather_than_running_timed(self):
        duck, said = FakeDuck(), []
        frames = {"n": 0}

        def state():
            frames["n"] += 1
            return duck.state() if frames["n"] < 30 else None
        out = runner.run(runner.beats([step("walk_forward"), step("walk_forward")]), duck, sleep=duck.sleep,
                         say=said.append, state=state, clock=duck.clock, measured=True)
        self.assertTrue(out.startswith("stopped at walk forward: "), out)
        self.assertIn(runner.LOST_NOTE, out)
        self.assertFalse(any(runner.TIMED_NOTE in s for s in said))

    def test_speed_cards_set_the_walking_speed(self):
        for label in ("slow", "fast"):
            duck = FakeDuck()
            self.run_row(duck, [("walk_forward", label)], [])
            self.assertEqual(duck.moves[0]["vx"], cardloop.SPEC["walk"]["speed"][label])

    def test_stop_and_sounds_are_unchanged(self):
        b = runner.beats([step("stop"), Step(labels={"action": "make_sound", "sound": "chirp"}, clause="chirp", cards=["chirp"])])
        self.assertEqual([x.kind for x in b], ["move", "sound"])


class OffSwitch(unittest.TestCase):
    """Closed-loop cards ship OFF for real ducks until docs/PACKS.md "Acceptance" passes.
    StudioKit pins the same default and the same sentence (DuckCardLoopTests)."""

    OFF = ("Walk and Turn cards on a duck are timed for now: two seconds each, and the duck does not "
           "land on board squares. Measured cards are being tested.")

    def test_the_switch_ships_off_and_unvalidated(self):
        self.assertIs(cardloop.SPEC["enabled_on_robot"], False)
        self.assertIsNone(cardloop.SPEC["validated"])
        self.assertIs(cardloop.ENABLED_ON_ROBOT, False)
        self.assertEqual(cardloop.OFF_NOTE, self.OFF)

    def test_a_spec_without_the_switch_is_refused(self):
        import tempfile
        spec = dict(cardloop.SPEC)
        del spec["enabled_on_robot"]
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(spec, f)
        with self.assertRaises(ValueError):
            cardloop.load_spec(pathlib.Path(f.name))
        pathlib.Path(f.name).unlink()

    def test_off_a_duck_with_odometry_still_runs_timed_cards_and_says_so_once(self):
        duck, said = FakeDuck(), []
        runner.run(runner.beats([step("walk_forward"), step("turn_left"), step("walk_forward")]), duck,
                   sleep=duck.sleep, say=said.append, state=duck.state, clock=duck.clock)
        self.assertEqual(sum(1 for s in said if self.OFF in s), 1)
        self.assertFalse(any(runner.TIMED_NOTE in s for s in said))
        self.assertEqual(len(duck.moves), 3 * round(runner.DEFAULT_SECONDS / runner.TICK))
        self.assertEqual(duck.moves[0], {"vx": runner.MAX_FORWARD * 2 / 3, "vy": 0.0, "vyaw": 0.0})
        self.assertEqual(duck.calls[-1][0], "robot.stop")

    def test_the_board_report_says_the_duck_is_timed(self):
        from duckcards import packs as P
        line = P.measured(P.Board(columns=3, rows=3, square_cm=30, duck_square_cm=30,
                                  duck_square_source="somewhere"))
        self.assertEqual(line, " " + self.OFF)
        on = P.measured(P.Board(columns=3, rows=3, square_cm=30, duck_square_cm=30,
                                duck_square_source="somewhere"), measured_cards=True)
        self.assertIn("A Walk card walks one duck square, 30 cm, on odometry (somewhere)", on)

    def test_the_developer_flag_is_labelled(self):
        from duckcards import __main__ as cli
        self.assertTrue(cli.MEASURED_CARDS_LABEL.startswith("DEVELOPER: --measured-cards is on."))


if __name__ == "__main__":
    unittest.main()
