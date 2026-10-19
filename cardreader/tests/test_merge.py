"""duck-card-loop/5, merge cards: cardloop.CardLoop(cards=n) and runner.merged."""

import math
import unittest

from duckcards import cardloop, runner
from duckcards.cardloop import CardLoop, Pose


def drive(loop, pose, dt=0.05, walk=0.45, turn=0.9, coast=0.0, limit=60.0):
    """A plain duck: walks `walk` m/s per unit of vx, turns `turn` of vyaw, and coasts `coast` rad
    on after a turn's zero twist. Answers how the card ended and where the duck is."""
    t, x, y, h, was = 0.0, pose.x, pose.y, pose.h, 0.0
    while t < limit:
        got = loop.step(Pose(x, y, h), t)
        if isinstance(got, str):
            return got, Pose(x, y, h)
        vx, vyaw = got
        if was and not vyaw:
            h += coast * (1 if was > 0 else -1)
        was = vyaw
        h += turn * vyaw * dt
        x += walk * vx * dt * math.cos(h)
        y += walk * vx * dt * math.sin(h)
        t += dt
    return "limit", Pose(x, y, h)


class MergedCardsTest(unittest.TestCase):
    def test_three_walks_as_one_end_where_the_third_would(self):
        loop = CardLoop("walk_forward", Pose(0, 0, 0), cards=3)
        self.assertAlmostEqual(loop.board_after.x, 0.9)
        how, at = drive(loop, Pose(0, 0, 0))
        self.assertEqual(how, "reached")
        self.assertAlmostEqual(at.x, 0.9, delta=0.03)

    def test_a_half_turn_never_takes_the_other_way_round(self):
        for start in (0.0, 0.05, -0.05):         # the board 180 degrees off, give or take
            loop = CardLoop("turn_left", Pose(0, 0, 0), cards=2)
            how, at = drive(loop, Pose(0, 0, start), coast=math.radians(8))
            self.assertEqual(how, "reached")
            self.assertLess(abs(math.degrees(cardloop.wrap(at.h - math.pi))), 14.5)
            self.assertGreater(loop.turned, math.radians(150), "it turned left, the long way it was asked")

    def test_one_card_is_unchanged(self):
        a = CardLoop("turn_right", Pose(0, 0, 0.3))
        b = CardLoop("turn_right", Pose(0, 0, 0.3), cards=1)
        for t, h in ((0.0, 0.3), (0.5, 0.0), (1.0, -0.8), (1.6, -1.2)):
            self.assertEqual(a.step(Pose(0, 0, h), t), b.step(Pose(0, 0, h), t))

    def test_three_turns_do_not_merge_as_one(self):
        with self.assertRaises(ValueError):
            CardLoop("turn_left", Pose(0, 0, 0), cards=3)

    def test_the_time_limit_scales_with_the_cards(self):
        loop = CardLoop("walk_forward", Pose(0, 0, 0), cards=2)
        self.assertNotEqual(loop.step(Pose(0.01, 0, 0), cardloop.SPEC["walk"]["max_s"] + 1), "out of time")
        self.assertEqual(loop.step(Pose(0.02, 0, 0), 2 * cardloop.SPEC["walk"]["max_s"]), "out of time")


class MergedTest(unittest.TestCase):
    def beats(self, actions, speeds=None):
        return [runner.Beat(kind="card", clause=a, action=a, speed=(speeds or {}).get(i, "normal"))
                for i, a in enumerate(actions)]

    def setUp(self):
        self.saved = cardloop.SPEC

    def tearDown(self):
        cardloop.SPEC = self.saved

    def test_merging_follows_the_spec(self):
        row = self.beats(["walk_forward"] * 3 + ["turn_left"] * 3 + ["walk_forward"])
        self.assertEqual(runner.merged(row, 0), 2, "the shipped spec (/6) merges two walks")
        cardloop.SPEC = {k: v for k, v in self.saved.items() if k != "merge"}
        self.assertEqual(runner.merged(row, 0), 1, "a spec with no merge merges nothing")
        cardloop.SPEC = dict(self.saved, merge={"walks": 0})
        self.assertEqual(runner.merged(row, 0), 3)
        self.assertEqual(runner.merged(row, 3), 2, "turns two at a time")
        self.assertEqual(runner.merged(row, 5), 1)
        cardloop.SPEC = dict(self.saved, merge={"walks": 2})
        self.assertEqual(runner.merged(row, 0), 2)

    def test_a_change_of_speed_or_card_breaks_a_run(self):
        cardloop.SPEC = dict(self.saved, merge={"walks": 0})
        row = self.beats(["walk_forward", "walk_forward", "walk_backward"], speeds={1: "fast"})
        self.assertEqual(runner.merged(row, 0), 1)
        self.assertEqual(runner.merged(self.beats(["turn_left", "turn_right"]), 0), 1)


if __name__ == "__main__":
    unittest.main()


class MergedRowTest(unittest.TestCase):
    def setUp(self):
        self.saved = cardloop.SPEC
        cardloop.SPEC = dict(self.saved, merge={"walks": 0})

    def tearDown(self):
        cardloop.SPEC = self.saved

    def test_a_row_with_runs_lands_on_the_board_without_stopping_between_merged_cards(self):
        from test_cardloop import FakeDuck, step
        duck, said = FakeDuck(), []
        row = ["walk_forward"] * 3 + ["turn_left"] * 2 + ["walk_forward"]
        out = runner.run(runner.beats([step(a) for a in row]), duck, sleep=duck.sleep, say=said.append,
                         state=duck.state, clock=duck.clock, measured=True)
        self.assertEqual(out, "finished")
        d = cardloop.SPEC["square_m"]
        self.assertAlmostEqual(duck.x, 2 * d, delta=0.04)
        self.assertAlmostEqual(duck.y, 0.0, delta=0.04)
        self.assertLess(abs(math.degrees(cardloop.wrap(duck.h - math.pi))), cardloop.SPEC["turn"]["tolerance_deg"] + 3)
        self.assertEqual(sum(1 for s in said if s.strip() == "walk forward"), 4, "every card's clause is still said")
        # The duck never stood still between the three walks: no zero twist until the walk's end.
        first_turn = next(i for i, m in enumerate(duck.moves) if m["vyaw"] and abs(m["vyaw"]) > 0.7)
        walks = duck.moves[:first_turn]
        stills = [i for i, m in enumerate(walks) if m == {"vx": 0.0, "vy": 0.0, "vyaw": 0.0}]
        moving = [i for i, m in enumerate(walks) if m["vx"] > 0]
        self.assertTrue(stills and min(stills) > max(moving), "one stop, after the last square")
