"""duck-card-loop/6, a nest and chapters: runner.chapters, and mc_run's re-seat and scoring."""

import json
import math
import pathlib
import random
import sys
import unittest

from duckcards import cardloop, runner

SIM = pathlib.Path(__file__).resolve().parents[1] / "sim"
sys.path.insert(0, str(SIM / "mc"))
import mc_run  # noqa: E402


def beats(kinds):
    return [runner.Beat(kind=k, clause=f"{k} {i}", action="walk_forward" if k == "card" else None)
            for i, k in enumerate(kinds)]


def cards(parts):
    return [sum(1 for b in p if b.kind == "card") for p in parts]


class ChaptersTest(unittest.TestCase):
    def test_the_fewest_chapters_as_equal_as_possible(self):
        for n, want in [(7, [7]), (8, [4, 4]), (10, [5, 5]), (15, [5, 5, 5]), (16, [6, 5, 5]),
                        (20, [7, 7, 6]), (24, [6, 6, 6, 6]), (28, [7, 7, 7, 7])]:
            self.assertEqual(cards(runner.chapters(beats(["card"] * n), 7)), want, n)

    def test_beats_that_are_not_cards_stay_with_the_chapter_before(self):
        row = beats(["sound"] + ["card"] * 5 + ["skill"] + ["card"] * 5 + ["sound"])
        parts = runner.chapters(row, 7)
        self.assertEqual([[b.kind for b in p] for p in parts],
                         [["sound"] + ["card"] * 5 + ["skill"], ["card"] * 5 + ["sound"]])
        self.assertEqual([b for p in parts for b in p], row, "nothing lost, nothing reordered")

    def test_only_a_spec_with_chapters_splits(self):
        row = beats(["card"] * 20)
        self.assertEqual(cards(runner.chapters(row)), [7, 7, 6], "the shipped spec is /6")
        saved = cardloop.SPEC
        try:
            cardloop.SPEC = cardloop.load_spec(SIM / "spec-loop1.json")
            self.assertEqual(len(runner.chapters(row)), 1, "/1 plays a row whole")
        finally:
            cardloop.SPEC = saved


class Truth:
    def __init__(self, poses):
        self.poses = poses                     # [(wall, x, y, h)]

    def at(self, w):
        best = min(self.poses, key=lambda p: abs(p[0] - w))
        return (best[0], best[1], best[2], best[3], 0.2, -1.0)


class ReseatTest(unittest.TestCase):
    def test_a_seat_error_is_scored_against_the_true_nest(self):
        d = cardloop.SPEC["square_m"]
        part = beats(["card", "card"])
        said = [(1.0, "  card 0"), (2.0, "  card 1")]
        # The duck truly sits 2 cm left of the nest and turned 4 degrees; it then walks two squares
        # along where it believes ahead is, which is its own true heading.
        sh = math.radians(4)
        nest = (0.5, -0.2, math.radians(30))
        x0 = nest[0] - 0.02 * math.sin(nest[2])
        y0 = nest[1] + 0.02 * math.cos(nest[2])
        h0 = nest[2] + sh
        x1, y1 = x0 + 2 * d * math.cos(h0), y0 + 2 * d * math.sin(h0)
        truth = Truth([(1.0, x0, y0, h0), (3.0, x1, y1, h0)])
        perfect = mc_run._score(part, said, truth, 0.5, 3.0, d)
        self.assertAlmostEqual(perfect["pos_err_m"], 0.0, places=6, msg="from where it sat, it did its cards")
        got = mc_run._score(part, said, truth, 0.5, 3.0, d, seat=(0.0, 0.02, sh))
        # Against the nest: two squares along a heading 4 degrees off, from 2 cm left.
        ex, ey = 2 * d * math.cos(sh), 0.02 + 2 * d * math.sin(sh)
        self.assertAlmostEqual(got["pos_err_m"], math.hypot(ex - 2 * d, ey), places=6)
        self.assertAlmostEqual(got["head_err_deg"], 4.0, places=6)

    def test_seat_errors_by_condition(self):
        rng = random.Random(1)
        self.assertEqual(mc_run.draw_seat("nominal", rng), (0.0, 0.0, 0.0))
        for _ in range(20):
            x, y, h = mc_run.draw_seat("stressed-10hz", rng)
            self.assertAlmostEqual(math.hypot(x, y), 0.03, places=9)
            self.assertAlmostEqual(abs(math.degrees(h)), 5.0, places=9)
        got = [mc_run.draw_seat("randomized-10hz", rng) for _ in range(4000)]
        sd = lambda v: math.sqrt(sum(a * a for a in v) / len(v))
        self.assertAlmostEqual(sd([g[0] for g in got]), 0.015, delta=0.001)
        self.assertAlmostEqual(math.degrees(sd([g[2] for g in got])), 3.0, delta=0.2)


if __name__ == "__main__":
    unittest.main()


class SplitVectorsTest(unittest.TestCase):
    """vectors/chapters/split.json: the chapters StudioKit's DuckCardLoop.chapters must make too."""

    def test_the_split_vectors(self):
        data = json.loads((pathlib.Path(__file__).resolve().parent.parent / "vectors/chapters/split.json").read_text())
        for row in data["rows"]:
            got = runner.chapters(beats(row["kinds"]), row["cards"])
            self.assertEqual([len(c) for c in got], row["chapters"], row["name"])


class NestRowTest(unittest.TestCase):
    """runner.run with a `nest`: the row stops between chapters, says so, and starts again from
    where the duck was put down."""

    def test_a_long_row_waits_for_the_nest_and_starts_again_from_it(self):
        from test_cardloop import FakeDuck, step
        duck, said, asked = FakeDuck(), [], []

        def nest(k, of):
            asked.append((k, of))
            duck.x, duck.y, duck.h = duck.x + 0.05, duck.y - 0.04, duck.h + 0.1   # put down a little off

        out = runner.run(runner.beats([step("walk_forward")] * 10), duck, sleep=duck.sleep, say=said.append,
                         state=duck.state, clock=duck.clock, measured=True, nest=nest)
        self.assertEqual(out, "finished")
        self.assertEqual(asked, [(2, 2)])
        self.assertIn(runner.nest_note(2, 2), [s.strip() for s in said])
        # The second chapter walked its five squares along where the duck was put down, not back
        # onto the first chapter's line.
        d = cardloop.SPEC["square_m"]
        x0, y0 = 5 * d + 0.05, -0.04                # about where it was put down
        self.assertAlmostEqual(duck.x, x0 + 5 * d * math.cos(0.1), delta=0.06)
        self.assertAlmostEqual(duck.y, y0 + 5 * d * math.sin(0.1), delta=0.06)

    def test_no_nest_plays_the_row_whole(self):
        from test_cardloop import FakeDuck, step
        duck, said = FakeDuck(), []
        out = runner.run(runner.beats([step("walk_forward")] * 10), duck, sleep=duck.sleep, say=said.append,
                         state=duck.state, clock=duck.clock, measured=True)
        self.assertEqual(out, "finished")
        self.assertFalse([s for s in said if "Chapter" in s])
        self.assertAlmostEqual(duck.x, 10 * cardloop.SPEC["square_m"], delta=0.06)
