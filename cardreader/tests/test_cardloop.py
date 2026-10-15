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

    def test_every_speed_clears_the_dead_band_measured_in_duckbench(self):
        # duckbench cardloop.mjs probe, canon plant: below about 0.25 forward and about 1.2 of yaw
        # on the spot the gait marches in place, and backward needs about 0.45.
        for label in ("slow", "normal", "fast"):
            self.assertGreaterEqual(cardloop.SPEC["walk"]["speed"][label], 0.25)
            self.assertGreaterEqual(cardloop.SPEC["walk"]["back_speed"][label], 0.45)
            self.assertGreaterEqual(cardloop.SPEC["turn"]["yaw_rate"][label], 1.2)


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
