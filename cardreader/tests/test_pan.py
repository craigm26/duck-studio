"""A row longer than one look: joining looks, which way to turn, and the duck turning its head.

    python3 -m unittest discover -s cardreader/tests -v

The looks placed by hand come from `helpers.rail_looks`, the duck's camera without the pixels,
turned about its own vertical through a point 55.6 mm behind the lens as Pollen's head turns. The
pictures come from `scenes.py`'s camera turned the same way, and the scans from a duck that holds
its head where it was sent and a camera that pictures the row from there.
"""

from __future__ import annotations

import math
import unittest

from helpers import DECK, code_corners, project, rail_looks, row_at

from duckcards import pan, runner
from duckcards.layout import arrange
from duckcards.program import read

try:
    import numpy as np
    import cv2  # noqa: F401
    from pupil_apriltags import Detector  # noqa: F401
    PICTURES = True
except ImportError:
    PICTURES = False

EXAMPLE = ["start", "greet", "walk_forward", "turn_left", "kick_right", "end"]
LONG = ["start", "greet", "walk_forward", "turn_left", "kick_right", "walk_backward", "turn_right", "end"]
WORDS = "Hello. Walk forward, slow. Turn left. Kick, right. Walk back. Turn right."
SIZE = (720, 1280)


def codes(layout):
    return layout.describe()


class Joining(unittest.TestCase):
    """Looks placed by hand: a rail row 45 cm away unless a test says otherwise."""

    def test_a_long_row_seen_in_three_looks_is_one_row(self):
        looks = rail_looks(LONG, 450, [20, 0, -20], unders={2: ["slow"]})
        self.assertTrue(all(len(look.seen) < len(LONG) for look in looks))
        joined = pan.join(looks)
        self.assertEqual(codes(joined), [["start", "greet", "walk_forward/slow", "turn_left", "kick_right",
                                          "walk_backward", "turn_right", "end"]])
        program = read(joined, DECK)
        self.assertEqual((program.words, program.complete, program.notes), (WORDS, True, []))
        self.assertEqual(sum(joined.new), 9)
        self.assertTrue(all(abs(s) < math.radians(0.2) for s in joined.slid), joined.slid)

    def test_one_look_joins_into_what_it_says_alone(self):
        (look,) = rail_looks(LONG, 600, [0], unders={2: ["slow"]})
        self.assertEqual(codes(pan.join([look])), codes(arrange(look.seen)))

    def test_the_order_the_looks_come_in_does_not_matter(self):
        looks = rail_looks(LONG, 450, [0, 20, -20])
        self.assertEqual(codes(pan.join(looks)), [LONG])

    def test_three_walks_in_a_row_stay_three(self):
        row = ["start", "walk_forward", "walk_forward", "walk_forward", "turn_left", "walk_forward", "end"]
        for distance in (350, 450, 600):
            looks = rail_looks(row, distance, [20, 0, -20])
            self.assertTrue(any(len([s for s in look.seen if s.card.code == "walk_forward"]) >= 2 for look in looks))
            self.assertEqual(codes(pan.join(looks)), [row], distance)

    def test_a_row_seen_from_the_far_side_reads_the_same(self):
        looks = rail_looks(LONG, 450, [20, 0, -20], unders={2: ["slow"]}, far_side=True)
        joined = pan.join(looks)
        self.assertEqual(read(joined, DECK).words, WORDS)

    def test_a_card_cut_off_at_the_edge_of_one_look_is_read_once(self):
        looks = rail_looks(LONG, 450, [20, 0, -20], x_mm=55)
        # Walk forward stands near the right edge of the look 20° to the left, its code half out
        # of the picture, so that look does not have it; the look straight ahead does.
        x = 55 + (2 - (len(LONG) - 1) / 2) * (63.5 + 8)
        inside = [0 <= u <= SIZE[0] for u, v in code_corners((x, 0, 450), (1, 0, 0), (0, 1, 0), 20)]
        self.assertTrue(any(inside) and not all(inside))
        self.assertNotIn("walk_forward", [s.card.code for s in looks[0].seen])
        self.assertIn("walk_forward", [s.card.code for s in looks[1].seen])
        self.assertEqual(codes(pan.join(looks)), [LONG])

    def test_an_under_card_found_in_another_look_than_its_card_is_still_under_it(self):
        looks = rail_looks(LONG, 450, [12, 0, -12], unders={2: ["fast"]})
        (left, middle, right) = looks
        middle.seen = [s for s in middle.seen if s.card.code != "fast"]          # a hand in front
        left.seen = [s for s in left.seen if s.card.code != "walk_forward"]
        self.assertEqual(codes(pan.join(looks))[0][2], "walk_forward/fast")

    def test_looks_that_share_nothing_they_should_are_refused(self):
        """Walk forward and Fast are all the left look and the middle one have in common; with
        each missed by one of them, nothing says the two line up."""
        looks = rail_looks(LONG, 450, [20, 0, -20], unders={2: ["fast"]})
        (left, middle, right) = looks
        middle.seen = [s for s in middle.seen if s.card.code != "fast"]
        left.seen = [s for s in left.seen if s.card.code != "walk_forward"]
        with self.assertRaises(pan.JoinError):
            pan.join(looks)

    def test_a_number_on_repeat_read_in_one_look_is_kept_and_two_that_differ_are_asked(self):
        row = ["start", "repeat", "walk_forward", "end_repeat", "turn_left", "kick_right", "end"]
        looks = rail_looks(row, 450, [15, -8], x_mm=100)
        (a,) = [s for s in looks[0].seen if s.card.code == "repeat"]
        (b,) = [s for s in looks[1].seen if s.card.code == "repeat"]
        a.count = 3
        self.assertEqual([s.action for s in read(pan.join(looks), DECK).steps], ["walk_forward"] * 3 + ["turn_left"])
        b.count = 4
        self.assertEqual(read(pan.join(looks), DECK).asks, [0])

    def test_the_lens_is_in_front_of_the_neck(self):
        """Taken as a turn about the lens, each 20° look lies 2.4° from where it is, which it would
        have to slide to line up: two thirds of all a run of one card may slide."""
        looks = rail_looks(LONG, 450, [20, 0, -20])
        joined = pan.join(looks)
        self.assertEqual(codes(joined), [LONG])
        self.assertLess(max(abs(math.degrees(s)) for s in joined.slid), 0.1)
        kept, pan.LENS_AHEAD_MM = pan.LENS_AHEAD_MM, 0.0
        try:
            slid = [math.degrees(s) for s in pan.join(looks).slid]
        finally:
            pan.LENS_AHEAD_MM = kept
        self.assertAlmostEqual(slid[1], -2.4, delta=0.2)
        self.assertAlmostEqual(slid[2], -4.8, delta=0.3)


class YawOff(unittest.TestCase):
    """The head is not always where it was sent. A look is lined up on the cards it shares, and
    one that cannot be is refused, not read."""

    def test_a_head_a_few_degrees_off_is_lined_up(self):
        for off in (-3.0, 2.0, 6.0):
            looks = rail_looks(LONG, 450, [20, 0, -20], told_deg=[20, off, -20 + off])
            joined = pan.join(looks)
            self.assertEqual(codes(joined), [LONG], off)
            self.assertAlmostEqual(math.degrees(joined.slid[1]), -off, delta=0.2)

    def test_a_head_that_turns_short_every_time_is_lined_up(self):
        looks = rail_looks(LONG, 450, [20 * 0.85, 0, -20 * 0.85], told_deg=[20, 0, -20])
        joined = pan.join(looks)
        self.assertEqual(codes(joined), [LONG])

    def test_a_run_of_one_card_is_lined_up_close_and_refused_further_off(self):
        """Three Walk forward side by side cannot say which of them a look lies on: within a third
        of a card the head is trusted to pick, and from there to three quarters the join refuses."""
        row = ["start", "walk_forward", "walk_forward", "walk_forward", "walk_forward", "walk_forward", "end"]
        right = refused = 0
        for tenth in range(0, 51, 5):
            off = tenth / 10
            looks = rail_looks(row, 450, [15, 0, -15], told_deg=[15, off, -15 + off])
            try:
                joined = pan.join(looks)
            except pan.JoinError:
                refused += 1
                self.assertGreater(off, 2.5)
                continue
            self.assertEqual(codes(joined), [row], off)
            right += 1
        self.assertEqual((right, refused), (6, 5))

    def test_a_card_the_row_holds_once_lines_a_look_up_from_further_off(self):
        """Sent 18° to the right, the head turned anywhere from 9° to 27°: Turn left, Kick right
        and End are each one card, so the look slides to them; further off it is refused."""
        truth = codes(pan.join(rail_looks(EXAMPLE, 450, [0, -18])))
        for off in (-9.0, -6.0, -3.0, 3.0, 6.0, 9.0):
            joined = pan.join(rail_looks(EXAMPLE, 450, [0, -18 + off], told_deg=[0, -18]))
            self.assertEqual(codes(joined), truth, off)
            self.assertAlmostEqual(math.degrees(joined.slid[1]), off, delta=0.2)
        for off in (-14.0, -11.0, 11.0, 14.0):
            with self.assertRaises(pan.JoinError, msg=off):
                pan.join(rail_looks(EXAMPLE, 450, [0, -18 + off], told_deg=[0, -18]))

    def test_a_head_that_did_not_turn_at_all_is_refused(self):
        looks = rail_looks(LONG, 450, [0, 0], told_deg=[0, -18])
        with self.assertRaises(pan.JoinError):
            pan.join(looks)


class Turning(unittest.TestCase):
    """Which way to look, and how far, from one look's own layout."""

    def turns(self, codes_, x_mm, far_side=False, distance=450):
        (look,) = rail_looks(codes_, distance, [0], x_mm=x_mm, far_side=far_side)
        return pan.turns(arrange(look.seen), look.size)

    def test_a_start_whose_row_runs_off_the_right_looks_right(self):
        self.assertEqual(self.turns(LONG, 200), [(1, True)])

    def test_a_row_from_the_far_side_runs_the_other_way(self):
        self.assertEqual(self.turns(LONG, -200, far_side=True), [(-1, True)])

    def test_an_end_whose_start_is_cut_off_on_the_left_looks_left(self):
        self.assertEqual(self.turns(LONG, -200), [(-1, False)])

    def test_a_row_cut_off_at_both_ends_looks_both_ways(self):
        self.assertEqual(self.turns(LONG, 0), [(1, True), (-1, False)])

    def test_a_whole_row_in_the_picture_looks_nowhere(self):
        self.assertEqual(self.turns(["start", "walk_forward", "end"], 0), [])

    def test_a_start_with_no_end_and_room_after_it_is_unfinished_not_cut_off(self):
        seen = row_at(["start", "walk_forward"], x0=150, width=110)
        self.assertEqual(pan.turns(arrange(seen), SIZE), [])

    def test_a_row_up_the_picture_is_not_followed_by_turning(self):
        seen = row_at(["start", "walk_forward", "turn_left"], x0=360, y=900, width=110, angle=-90)
        self.assertEqual(pan.turns(arrange(seen), SIZE), [])

    def test_a_turn_keeps_a_whole_card_in_both_pictures(self):
        for distance, degrees in ((350, 13), (450, 18), (600, 22)):
            (look,) = rail_looks(LONG, distance, [0])
            step = math.degrees(pan.step(look, [s.card for s in pan.main_row(arrange(look.seen)).slots]))
            self.assertAlmostEqual(step, degrees, delta=1.0, msg=distance)

    def test_the_test_camera_turns_the_way_the_head_does(self):
        """More head_yaw is a turn to the left: what was straight ahead moves right."""
        self.assertGreater(project((0, 0, 500), 10)[0], SIZE[0] / 2)
        self.assertAlmostEqual(project((0, 0, 500), 0)[0], SIZE[0] / 2)


class Duck:
    """A robot that holds its head where it was sent, and its camera, picturing the row from
    there: `picture(yaw_deg)` is the grey picture with the head turned that far."""

    REST = {"neck_pitch": 0.0, "head_pitch": 0.0, "head_yaw": 0.0, "head_roll": 0.0}

    def __init__(self, picture, look_joints=None):
        from duckcards.see import see
        self.picture, self.see = picture, see
        self.calls, self.heads = [], []
        self.look_joints = dict(look_joints or self.REST)
        self.joints = dict(self.REST)

    def call(self, method, params=None):
        self.calls.append((method, params))
        if method == "robot.look":
            self.joints = dict(self.look_joints)
            return {"head": dict(self.look_joints), "clamped": False}
        return {"accepted": True}

    def notify(self, method, params=None):
        if method == "robot.head":
            self.heads.append(dict(params))
            self.joints = {**self.REST, **params}

    def take(self):
        img = self.picture(math.degrees(self.joints["head_yaw"]))
        return self.see(img, DECK).seen, (img.shape[1], img.shape[0])


@unittest.skipUnless(PICTURES, "numpy, opencv and pupil_apriltags are needed for pictures")
class Pictures(unittest.TestCase):
    """The duck's camera, simulated (tests/scenes.py), turned the way its head turns."""

    @classmethod
    def setUpClass(cls):
        import scenes
        from duckcards.see import see
        cls.scenes, cls.see = scenes, staticmethod(see)

    def card(self, code, under=()):
        c = DECK.by_code(code)
        return (c.tag, c.category, [(DECK.by_code(u).tag, DECK.by_code(u).category) for u in under])

    def row(self, codes_, unders=None):
        unders = unders or {}
        return [self.card(c, unders.get(i, ())) for i, c in enumerate(codes_)]

    def look(self, img, yaw_deg):
        return pan.Look(seen=self.see(img, DECK).seen, yaw=math.radians(yaw_deg), size=(img.shape[1], img.shape[0]))

    def test_a_camera_that_is_not_turned_takes_the_same_pictures(self):
        pts = np.array([[-80.0, 30.0, 400.0], [120.0, -60.0, 650.0]])
        still = self.scenes.Camera(20).project(pts)
        barely = self.scenes.Camera(20, yaw_deg=1e-9).project(pts)
        self.assertTrue(np.allclose(still, barely, atol=1e-6))
        turned = self.scenes.Camera(0, yaw_deg=12).project(np.array([[40.0, 0.0, 450.0]]))[0]
        self.assertAlmostEqual(turned[0], project((40.0, 0.0, 450.0), 12)[0], places=6)

    def test_the_example_row_in_a_rail_from_three_turns_of_the_head(self):
        row = self.row(EXAMPLE, {2: ["slow"]})
        looks = [self.look(self.scenes.rail(row, 450, yaw_deg=y), y) for y in (18, 0, -18)]
        self.assertFalse(any(read(arrange(look.seen), DECK).complete for look in looks))
        program = read(pan.join(looks), DECK)
        self.assertEqual((program.words, program.complete), ("Hello. Walk forward, slow. Turn left. Kick, right.", True))
        self.assertEqual(program.steps[1].labels, {"action": "walk_forward", "speed": "slow", "head": "straight"})

    def test_a_long_row_on_the_floor_from_turned_looks(self):
        pitch = math.degrees(math.atan2(self.scenes.HEAD_MM, 320))
        row = self.row(LONG, {2: ["slow"]})
        looks = [self.look(self.scenes.floor(row, 320, pitch, yaw_deg=y), y) for y in (24, 12, 0, -12, -24)]
        program = read(pan.join(looks), DECK)
        self.assertEqual((program.words, program.complete), (WORDS, True))

    # ------------------------------------------------------------ scanning, through a duck
    def scan(self, picture, look_joints=None, point=None):
        duck = Duck(picture, look_joints)
        gaze = runner.Gaze(duck, point)
        gaze.aim(0.0)
        said = []
        seen, size = duck.take()
        first = pan.Look(seen=seen, yaw=gaze.yaw, size=size)
        joined = runner.scan(first, arrange(seen), gaze, duck.take, sleep=lambda s: None, say=said.append,
                             clock=lambda: 0.0)
        return duck, joined, said

    def test_a_scan_reads_the_rest_of_the_row_and_looks_back(self):
        row = self.row(EXAMPLE, {2: ["slow"]})
        duck, joined, said = self.scan(lambda yaw: self.scenes.rail(row, 450, x_mm=120, yaw_deg=yaw))
        program = read(joined, DECK)
        self.assertEqual((program.words, program.complete), ("Hello. Walk forward, slow. Turn left. Kick, right.", True))
        turns = [h["head_yaw"] for h in duck.heads if h]
        self.assertTrue(turns and all(t < 0 for t in turns), turns)            # to the right is less yaw
        self.assertEqual(duck.heads[-1], {})                                   # looked back to rest
        self.assertEqual(duck.joints["head_yaw"], 0.0)
        self.assertRegex(said[0], r"^\[scan\] looked right \d+ degrees: \d+ more cards?$")
        self.assertTrue(said[-1].startswith("[scan] looked back: "), said)

    def test_an_end_whose_start_is_cut_off_is_scanned_the_other_way(self):
        row = self.row(LONG, {2: ["slow"]})
        duck, joined, said = self.scan(lambda yaw: self.scenes.rail(row, 450, x_mm=-170, yaw_deg=yaw))
        self.assertEqual(read(joined, DECK).words, WORDS)
        turns = [h["head_yaw"] for h in duck.heads if h]
        self.assertTrue(turns and all(t > 0 for t in turns), turns)

    def test_a_long_rail_row_seen_from_its_middle(self):
        row = self.row(LONG, {2: ["slow"]})
        duck, joined, said = self.scan(lambda yaw: self.scenes.rail(row, 450, yaw_deg=yaw))
        self.assertEqual(read(joined, DECK).words, WORDS)
        yaws = [h["head_yaw"] for h in duck.heads if h]
        self.assertTrue(min(yaws) < 0 < max(yaws), yaws)                      # both ways

    def test_a_row_on_the_floor_is_scanned_with_the_head_pitched_down(self):
        pitch = math.degrees(math.atan2(self.scenes.HEAD_MM, 320))
        row = self.row(LONG, {2: ["slow"]})
        floor_joints = {"neck_pitch": 0.0, "head_pitch": 0.61, "head_yaw": 0.0, "head_roll": 0.0}
        duck, joined, said = self.scan(lambda yaw: self.scenes.floor(row, 320, pitch, yaw_deg=yaw),
                                       floor_joints, runner.FLOOR_AT)
        self.assertEqual(read(joined, DECK).words, WORDS)
        self.assertTrue(all(h["head_pitch"] == 0.61 for h in duck.heads))     # only the yaw turned
        self.assertEqual([m for m, _ in duck.calls].count("robot.look"), 2)    # watching, and back

    def test_the_watcher_runs_a_scanned_row_once(self):
        row = self.row(EXAMPLE, {2: ["slow"]})
        duck = Duck(lambda yaw: self.scenes.rail(row, 450, x_mm=120, yaw_deg=yaw))
        gaze = runner.Gaze(duck)
        gaze.aim(0.0)
        said = []
        scanner = runner.Scanner(gaze, duck.take, DECK, need=3, sleep=lambda s: None, say=said.append,
                                 clock=lambda: 0.0)
        watcher = runner.Watcher(need=3)
        seen, size = duck.take()
        layout = arrange(seen)
        alone = read(layout, DECK)
        self.assertFalse(alone.complete)
        events = []
        for t in range(12):
            program = scanner.read(pan.Look(seen=seen, yaw=gaze.yaw, size=size), layout, alone)
            event = watcher.feed(program, t * 0.25)
            if event:
                events.append((event.kind, event.program.words))
        self.assertEqual(events, [("row", "Hello. Walk forward, slow. Turn left. Kick, right.")])
        self.assertEqual(sum(s.startswith("[scan] looked back") for s in said), 1)

    def test_a_dry_run_says_where_it_would_look_and_turns_nothing(self):
        row = self.row(EXAMPLE)
        duck = Duck(lambda yaw: self.scenes.rail(row, 450, x_mm=120, yaw_deg=yaw))
        gaze = runner.Gaze(duck)
        gaze.aim(0.0)
        said = []
        scanner = runner.Scanner(gaze, duck.take, DECK, need=1, dry=True, say=said.append, clock=lambda: 0.0)
        seen, size = duck.take()
        layout = arrange(seen)
        program = scanner.read(pan.Look(seen=seen, yaw=0.0, size=size), layout, read(layout, DECK))
        self.assertFalse(program.complete)
        self.assertEqual(duck.heads, [{}])
        self.assertRegex(said[0], r"^\[scan\] would look right \d+ degrees")


if __name__ == "__main__":
    unittest.main()
