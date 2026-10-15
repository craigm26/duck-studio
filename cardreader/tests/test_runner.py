"""Running a row, watching for cards, and talking to the duck, without a duck.

The runner is held to RobotPlan's numbers; the frame socket to mediad's wire
shape; the robot client to robotd's; and the bridge path end to end through this
repository's own microduck-bridge and mock-robotd.
"""

from __future__ import annotations

import json
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

from helpers import DECK, row_at, seen_at

from duckcards import duck, runner
from duckcards.layout import arrange
from duckcards.program import read

ROOT = pathlib.Path(__file__).resolve().parents[2]


def program_of(seen):
    return read(arrange(seen), DECK)


class Recorder:
    """A robot that writes down what it was asked."""

    def __init__(self, skills=("kick_left", "kick_right", "sit_toggle", "roulade", "ground_pick"),
                 accept=True):
        self.calls, self.moves, self.notified = [], [], []
        self.skills, self.accept = list(skills), accept

    def call(self, method, params=None):
        self.calls.append((method, params))
        if method == "robot.skills":
            return {"skills": [{"name": "kick_right", "duration": 0.6}], "built_in": self.skills}
        if method == "robot.do":
            return {"accepted": self.accept} if self.accept is not None else {}
        if method == "robot.look":       # LookResult: the joints the head was sent to
            return {"head": {"neck_pitch": 0.0, "head_pitch": 0.61, "head_yaw": 0.0, "head_roll": 0.0},
                    "clamped": False}
        return {"accepted": True}

    def notify(self, method, params=None):
        self.notified.append((method, params))
        if method == "robot.move":
            self.moves.append(params)


class Beats(unittest.TestCase):
    def test_robotplans_numbers(self):
        program = program_of(row_at(["start", "greet", "walk_forward", "turn_left", "kick_right", "end"],
                                    unders={2: ["slow"]}))
        b = runner.beats(program.steps)
        # Walk and Turn are card beats: one square and a quarter turn on odometry, and this timed
        # twist on a duck that does not report it (test_cardloop.py runs both).
        self.assertEqual([x.kind for x in b], ["sound", "card", "card", "skill"])
        self.assertEqual([(x.action, x.speed) for x in b[1:3]], [("walk_forward", "slow"), ("turn_left", "normal")])
        self.assertEqual(b[0].name, "greet")
        self.assertAlmostEqual(b[1].twist[0], 0.1)            # 0.3 m/s x 1/3
        self.assertAlmostEqual(b[2].twist[2], 2.0 / 3.0)      # 1.0 rad/s x 2/3
        self.assertEqual((b[1].seconds, b[2].seconds), (2.0, 2.0))
        self.assertEqual((b[3].name, b[3].seconds), ("kick_right", 0.5))

    def test_robotds_names_for_the_tricks(self):
        names = {a: runner.beats(program_of([seen_at(a, 300, 300)]).steps)[0].name
                 for a in ["kick_left", "kick_right", "sit_or_stand", "roll", "peck_ground"]}
        self.assertEqual(names, {"kick_left": "kick_left", "kick_right": "kick_right",
                                 "sit_or_stand": "sit_toggle", "roll": "roulade", "peck_ground": "ground_pick"})

    def test_two_minutes_is_the_limit(self):
        program = program_of(row_at(["start"] + ["walk_forward"] * 30 + ["end"], width=20, gap=2))
        with self.assertRaises(runner.Refusal):
            runner.beats(program.steps * 3)


class Run(unittest.TestCase):
    def test_a_row_runs_as_studio_runs_it(self):
        program = program_of(row_at(["start", "walk_forward", "kick_right", "end"]))
        robot = Recorder()
        out = runner.run(runner.beats(program.steps), robot, sleep=lambda s: None, say=lambda s: None)
        self.assertEqual(out, "finished")
        methods = [m for m, _ in robot.calls]
        self.assertEqual(methods, ["robot.skills", "robot.stop", "robot.do", "robot.stop"])
        self.assertEqual(robot.calls[2][1], {"skill": "kick_right"})
        walk = [m for m in robot.moves if m["vx"] > 0]
        self.assertEqual(len(walk), 40)                       # two seconds at 20 Hz
        self.assertAlmostEqual(walk[0]["vx"], 0.2)            # normal: 0.3 x 2/3
        still = robot.moves[len(walk):]
        self.assertEqual(len(still), round((0.6 + 1.0) / runner.TICK))   # the duck's own 0.6 s, then settle

    def test_a_duck_without_the_trick_is_told_before_anything_moves(self):
        program = program_of([seen_at("roll", 300, 300)])
        robot = Recorder(skills=["kick_left"])
        with self.assertRaises(runner.Refusal) as e:
            runner.run(runner.beats(program.steps), robot, sleep=lambda s: None, say=lambda s: None)
        self.assertIn("no roulade", str(e.exception))
        self.assertEqual(robot.moves, [])

    def test_an_answer_without_accepted_is_a_no(self):
        program = program_of([seen_at("kick_left", 300, 300)])
        robot = Recorder(accept=None)
        out = runner.run(runner.beats(program.steps), robot, sleep=lambda s: None, say=lambda s: None)
        self.assertTrue(out.startswith("refused"))

    def test_heads_are_sent_only_when_asked(self):
        program = program_of(row_at(["start", "walk_forward", "end"], unders={1: ["look_left"]}))
        for heads, looks in [(False, 0), (True, 2)]:
            robot = Recorder()
            runner.run(runner.beats(program.steps), robot, heads=heads, sleep=lambda s: None, say=lambda s: None)
            self.assertEqual(sum(m == "robot.look" for m, _ in robot.calls), looks)


class Watching(unittest.TestCase):
    def feed(self, w, seen, t):
        return w.feed(program_of(seen), t)

    def test_a_card_must_hold_still_and_fires_once(self):
        w = runner.Watcher(need=3, forget=1.0)
        card = [seen_at("kick_right", 300, 300)]
        events = [self.feed(w, card, t * 0.25) for t in range(12)]
        self.assertEqual([e.kind for e in events if e], ["card"])
        self.assertIsNotNone(events[2])
        # gone for longer than `forget`, then shown again: a second kick
        for t in range(12, 20):
            self.feed(w, [], t * 0.25)
        again = [self.feed(w, card, t * 0.25) for t in range(20, 24)]
        self.assertEqual([e.kind for e in again if e], ["card"])

    def test_a_row_fires_when_complete_and_asks_when_it_is_not(self):
        w = runner.Watcher(need=2, unfinished_after=1.0)
        half = row_at(["start", "walk_forward"])
        events = [self.feed(w, half, t * 0.25) for t in range(8)]
        self.assertEqual([e.kind for e in events if e], ["unfinished"])
        whole = row_at(["start", "walk_forward", "end"])
        events = [self.feed(w, whole, 2 + t * 0.25) for t in range(4)]
        self.assertEqual([e.kind for e in events if e], ["row"])

    def test_a_repeat_nobody_can_read_is_asked_about_not_run(self):
        w = runner.Watcher(need=2, unfinished_after=1.0)
        row = row_at(["start", "repeat", "walk_forward", "end_repeat", "end"])
        events = [self.feed(w, row, t * 0.25) for t in range(8)]
        self.assertEqual([e.kind for e in events if e], ["unfinished"])
        readable = row_at(["start", "repeat", "walk_forward", "end_repeat", "end"], counts={1: 2})
        events = [self.feed(w, readable, 2 + t * 0.25) for t in range(4)]
        self.assertEqual([(e.kind, e.program.words) for e in events if e], [("row", "Walk forward. Walk forward.")])


class Gaze(unittest.TestCase):
    """robotd's idle look-around starts after two seconds nobody steered the head; in duck-sim it
    took a held card out of the picture and the duck kicked three times for one card."""

    def test_the_head_is_held_at_rest_more_often_than_robotd_lets_it_wander(self):
        robot = Recorder()
        gaze = runner.Gaze(robot)
        gaze.aim(0.0)
        for t in (0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25):
            gaze.tick(t)
        sent = [(m, p) for m, p in robot.notified if m == "robot.head"]
        self.assertEqual(sent, [("robot.head", {})] * 3)       # at 0, 1 and 2 s: the rest pose
        self.assertLess(runner.GAZE_EVERY, 2.0)
        self.assertEqual(robot.calls, [])

    def test_a_point_is_looked_at_once_then_held_by_its_joints(self):
        robot = Recorder()
        gaze = runner.Gaze(robot, runner.FLOOR_AT)
        gaze.aim(0.0)
        gaze.tick(1.0)
        gaze.tick(2.0)
        self.assertEqual([m for m, _ in robot.calls], ["robot.look"])
        x, y, z = runner.FLOOR_AT
        self.assertEqual(robot.calls[0][1], {"x": x, "y": y, "z": z})
        held = [p for m, p in robot.notified if m == "robot.head"]
        self.assertEqual(len(held), 2)
        self.assertEqual(held[0]["head_pitch"], 0.61)


class Frames(unittest.TestCase):
    def test_media_frame_is_read_and_turned_upright(self):
        import numpy as np
        w, h = 8, 4                                   # as sent: landscape, mounted a quarter turn off
        y = np.arange(w * h, dtype=np.uint8).reshape(h, w)
        uyvy = np.zeros(w * h * 2, np.uint8)
        uyvy[1::2] = y.ravel()
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "media.sock")
            srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            srv.bind(path)
            srv.listen(1)

            def serve():
                c, _ = srv.accept()
                req = json.loads(c.makefile("rb").readline())
                header = {"width": w, "height": h, "format": "UYVY", "bytes": w * h * 2,
                          "captured_at_unix_us": 5_000_000, "rotate": 90}
                c.sendall(json.dumps({"jsonrpc": "2.0", "id": req["id"], "result": header}).encode() + b"\n")
                c.sendall(uyvy.tobytes())
                c.close()
            threading.Thread(target=serve, daemon=True).start()
            frame = duck.FrameSocket(path).grab()
            srv.close()
        self.assertEqual(frame.gray.shape, (w, h))
        self.assertTrue((frame.gray == np.rot90(y, k=-1)).all())
        self.assertEqual(frame.captured_at, 5.0)


class Bridge(unittest.TestCase):
    """Through this repository's own bridge and mock robotd, the way a laptop reaches a duck."""

    def test_calls_go_through_microduck_bridge(self):
        bridge = ROOT / "bridge"
        with tempfile.TemporaryDirectory() as d:
            sock = os.path.join(d, "duck.sock")
            token_file = os.path.join(d, "token")
            with open(token_file, "w") as f:
                f.write("0123456789abcdef0123456789abcdef\n")
            os.chmod(token_file, 0o600)
            s = socket.socket()
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]
            s.close()
            mock = subprocess.Popen([sys.executable, "-u", str(bridge / "mock-robotd.py"), "--socket", sock],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            relay = None
            try:
                for _ in range(50):
                    if os.path.exists(sock):
                        break
                    time.sleep(0.1)
                relay = subprocess.Popen([sys.executable, "-u", str(bridge / "microduck-bridge.py"), "--socket", sock,
                                          "--port", str(port), "--host", "127.0.0.1", "--token-file", token_file,
                                          "--deadman", "2000"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                robot = None
                for _ in range(50):
                    try:
                        robot = duck.Robot.bridge("127.0.0.1", port, "0123456789abcdef0123456789abcdef")
                        break
                    except OSError:
                        time.sleep(0.1)
                self.assertIsNotNone(robot)
                robot.notify("robot.move", {"vx": 0.1, "vy": 0.0, "vyaw": 0.0})
                self.assertIsNotNone(robot.call("robot.stop"))
                robot.close()
                with self.assertRaises(duck.DuckError):
                    duck.Robot.bridge("127.0.0.1", port, "wrong-token-wrong-token-wrong-tok")
            finally:
                if relay:
                    relay.terminate()
                    relay.wait()
                mock.terminate()
                mock.wait()


if __name__ == "__main__":
    unittest.main()
