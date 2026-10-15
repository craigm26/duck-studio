"""Reading the number written on Repeat, through the duck's camera, simulated.

    python3 -m unittest discover -s cardreader/tests -v

THE DIGITS ARE MNIST'S TEST SPLIT. `mnist_test_digits.npz` holds the first twelve of each figure,
0 to 9, from MNIST's test split (huggingface.co/datasets/ylecun/mnist, MIT licence; `index` is each
one's place in that split), which `tools/train_digits.py` neither trains nor tunes on. Each is
written into the Repeat card's box (`scenes.write_in`, marker grey, eight tenths of the box's
height) and the card is held up to the simulated camera (`scenes.held`).

WHAT IS HELD. A blank box reads None. Up close (20 to 30 cm) most written digits read right. A
written 0 is never a count. Across every picture here, confident wrong reads stay at the few this
file states, because a wrong number is worse than a question. And a row read end to end, through
`see`, `arrange` and `program.read`, runs its Repeat the number of times written on it.
"""

from __future__ import annotations

import time
import unittest

from helpers import DECK

from duckcards.layout import arrange
from duckcards.program import read

try:
    import numpy as np
    import cv2  # noqa: F401
    from pupil_apriltags import Detector  # noqa: F401
    PICTURES = True
except ImportError:
    PICTURES = False

REPEAT = DECK.by_code("repeat")
# Up close, more than half of the written digits 1..9 must read right (34 of 54 did when this was
# written, none wrong, the rest asked about), and across every picture in this file at most one
# confident read may be wrong (none was). The reader's thresholds were set for almost no confident
# mistakes on harder pictures than these, and coverage is what that costs.
CLOSE_RIGHT = 0.55
MOST_WRONG = 1
# Where the up-close digits are held: (distance mm, yaw, roll, blur), in turn.
CLOSE = [(200, 0, 0, 1.0), (250, 15, -8, 0.6), (300, -20, 6, 1.0), (220, 30, 12, 0.6), (280, -10, -12, 1.0),
         (250, 0, 20, 1.0)]
FAR = [(400, 0, 0, 1.0), (450, 20, -6, 0.6), (500, -15, 8, 1.0), (350, -30, 0, 1.0)]


@unittest.skipUnless(PICTURES, "numpy, opencv and pupil_apriltags are needed for pictures")
class WrittenOnRepeat(unittest.TestCase):
    """Repeat held up with a digit in its box, read the way `watch` reads it."""

    @classmethod
    def setUpClass(cls):
        import scenes
        from duckcards import digits
        from duckcards.see import detections, see
        cls.scenes, cls.digits = scenes, digits
        cls.see, cls.detections = staticmethod(see), staticmethod(detections)
        z = np.load(scenes.HERE / "mnist_test_digits.npz")
        cls.xs, cls.ys = z["x"], z["y"].astype(int)
        cls._results = {}

    def held(self, figure, distance, yaw=0.0, roll=0.0, blur=1.0, seed=0, **kw):
        return self.scenes.held(REPEAT.tag, REPEAT.category, distance, yaw_deg=yaw, roll_deg=roll,
                                blur=blur, seed=seed, write=figure, **kw)

    def counts(self, img, **kw):
        return [s.count for s in self.see(img, DECK, **kw).seen if s.card.code == "repeat"]

    def results(self, name):
        """(right, wrong, refused, lost) for one set of pictures, read once and kept: "close",
        "far" (digits 1..9) and "zeros"."""
        if name not in self._results:
            ones_to_nines = [i for i in range(len(self.ys)) if self.ys[i] >= 1]
            figures, poses = {"close": (ones_to_nines[::2], CLOSE), "far": (ones_to_nines[1::4], FAR),
                              "zeros": ([i for i in range(len(self.ys)) if self.ys[i] == 0], CLOSE)}[name]
            self._results[name] = self.read_all(figures, poses) + (len(figures),)
        return self._results[name]

    def read_all(self, figures, poses):
        """(right, wrong, refused, lost) for `figures` (index, digit) held at `poses` in turn."""
        right = wrong = refused = lost = 0
        for k, i in enumerate(figures):
            distance, yaw, roll, blur = poses[k % len(poses)]
            found = self.counts(self.held(self.xs[i], distance, yaw, roll, blur, seed=k))
            if not found:
                lost += 1
            elif found[0] is None:
                refused += 1
            elif found[0] == self.ys[i]:
                right += 1
            else:
                wrong += 1
        return right, wrong, refused, lost

    def test_a_blank_box_reads_none(self):
        for distance, yaw, roll, blur in CLOSE[:3] + FAR[:2]:
            img = self.held(None, distance, yaw, roll, blur)
            (s,) = [s for s in self.see(img, DECK).seen if s.card.code == "repeat"]
            self.assertIsNone(s.count, distance)
            if distance <= 300:
                self.assertEqual(self.digits.read(img, s.corners).why, "blank", distance)

    def test_up_close_most_written_digits_read_right(self):
        right, wrong, refused, lost, n = self.results("close")
        self.assertEqual(lost, 0)
        self.assertGreaterEqual(right / n, CLOSE_RIGHT, (right, wrong, refused))

    def test_far_away_it_asks_rather_than_guesses(self):
        right, wrong, refused, lost, n = self.results("far")
        self.assertLessEqual(wrong, MOST_WRONG, (right, wrong, refused, lost))

    def test_a_written_0_is_never_a_count(self):
        right, wrong, refused, lost, n = self.results("zeros")
        self.assertEqual((right, wrong), (0, 0), (right, wrong, refused, lost))

    def test_confident_wrong_reads_across_every_picture(self):
        wrong = {name: self.results(name)[1] for name in ("close", "far", "zeros")}
        self.assertLessEqual(sum(wrong.values()), MOST_WRONG, wrong)

    def test_numbers_can_be_turned_off(self):
        threes = [i for i in range(len(self.ys)) if self.ys[i] == 3]
        img = self.held(self.xs[threes[0]], 250)
        self.assertEqual(self.counts(img, numbers=False), [None])

    def test_the_librarys_answer_stays_plain(self):
        threes = [i for i in range(len(self.ys)) if self.ys[i] == 3]
        img = self.held(self.xs[threes[0]], 250)
        (d,) = self.detections(img)
        self.assertEqual(sorted(d), ["corners", "hamming", "id", "margin"])

    def test_reading_a_repeat_card_is_quick(self):
        threes = [i for i in range(len(self.ys)) if self.ys[i] == 3]
        img = self.held(self.xs[threes[0]], 250)
        (s,) = [s for s in self.see(img, DECK, numbers=False).seen]
        self.digits.read(img, s.corners)
        t0 = time.perf_counter()
        for _ in range(10):
            self.digits.read(img, s.corners)
        self.assertLess((time.perf_counter() - t0) / 10, 0.05)

    def test_a_row_runs_its_repeat_the_number_of_times_written(self):
        """Start, Repeat with a 3 in its box, Walk forward, End repeat, End. Five cards do not fit
        the duck's 37 degrees across near enough to read the box (about four cards a look), so the
        row stands on its side, along the picture's 62 degrees up and down; the layout reads a row
        whichever way its cards face. The fixture's second 3 is written on the Repeat: its first,
        here, is a little short of sure (p 0.993) and is asked about, which is the reader being
        careful, not this row."""
        threes = [i for i in range(len(self.ys)) if self.ys[i] == 3]
        codes = ["start", "repeat", "walk_forward", "end_repeat", "end"]
        step = self.scenes.W_MM + 8.0
        placed = []
        for k, code in enumerate(codes):
            card = DECK.by_code(code)
            centre = (0.0, (k - 2) * step, 320.0)
            placed.append((card.tag, card.category, centre, (0, 1, 0), (-1, 0, 0),
                           self.xs[threes[1]] if code == "repeat" else None))
        img = self.scenes.render(placed, self.scenes.Camera(0), blur=1.0)
        program = read(arrange(self.see(img, DECK).seen), DECK)
        self.assertEqual([s.action for s in program.steps], ["walk_forward"] * 3)
        self.assertIn("Repeat says 3 times.", program.notes)
        self.assertTrue(program.complete)
        asked = read(arrange(self.see(img, DECK, numbers=False).seen), DECK)
        self.assertEqual(asked.asks, [0])


if __name__ == "__main__":
    unittest.main()
