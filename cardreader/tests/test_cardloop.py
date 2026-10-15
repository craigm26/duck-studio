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

    def test_forward_speeds_clear_the_dead_band_measured_in_duckbench(self):
        # duckbench cardloop.mjs probe, canon plant: below about 0.25 forward the gait marches in
        # place. Walk back (0.4) and Turn (1.0) are held to Pollen's envelope, which is below what
        # duckbench's canon plant needed (about 0.45 back, about 1.2 turning on the spot): whether
        # the v8 velstand in Pollen's duck-sim moves at them is the duck-sim run's to measure.
        for label in ("slow", "normal", "fast"):
            self.assertGreaterEqual(cardloop.SPEC["walk"]["speed"][label], 0.25)


class Vectors(unittest.TestCase):
    def test_every_vector(self):
        files = sorted(VECTORS.glob("*.json"))
        self.assertGreaterEqual(len(files), 10)
        for f in files:
            v = json.loads(f.read_text())
            with self.subTest(v["name"]):
                loop = cardloop.CardLoop(v["action"], cardloop.Pose(*v["board"]), v["speed"])
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

    def __init__(self, odom=True, walk=0.45, turn=0.9):
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
        params = {"safety": {"fallen": False}}
        if self.odom:
            params["odom"] = {"position": [self.x, self.y, 0.12], "yaw": self.h}
        return params, self.now


def step(action, speed="normal"):
    return Step(labels={"action": action, "speed": speed}, clause=action.replace("_", " "), cards=[action])


class Runs(unittest.TestCase):
    def run_row(self, duck, actions, said):
        return runner.run(runner.beats([step(a) if isinstance(a, str) else step(*a) for a in actions]), duck,
                          sleep=duck.sleep, say=said.append, state=duck.state, clock=duck.clock)

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
        runner.run(runner.beats([step("walk_forward")]), duck, sleep=duck.sleep, say=said.append)
        self.assertTrue(any(runner.TIMED_NOTE in s for s in said))

    def test_a_pose_that_stops_arriving_stops_the_card(self):
        duck, said = FakeDuck(), []
        frozen = duck.state()
        runner.run(runner.beats([step("walk_forward")]), duck, sleep=duck.sleep, say=said.append,
                   state=lambda: frozen, clock=duck.clock)
        self.assertTrue(any(runner.LOST_NOTE in s for s in said))

    def test_speed_cards_set_the_walking_speed(self):
        for label in ("slow", "fast"):
            duck = FakeDuck()
            self.run_row(duck, [("walk_forward", label)], [])
            self.assertEqual(duck.moves[0]["vx"], cardloop.SPEC["walk"]["speed"][label])

    def test_stop_and_sounds_are_unchanged(self):
        b = runner.beats([step("stop"), Step(labels={"action": "make_sound", "sound": "chirp"}, clause="chirp", cards=["chirp"])])
        self.assertEqual([x.kind for x in b], ["move", "sound"])


if __name__ == "__main__":
    unittest.main()
