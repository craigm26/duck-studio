"""duck-card-loop/3's DriftCal: the drift a still duck's odometry shows is taken out of every pose."""

import math
import random
import unittest

from duckcards import cardloop
from duckcards.cardloop import DriftCal, Pose

CAL = {"before_s": 5.0, "still_after_s": 0.3, "max_dps": 1.0}


def window(cal, t0, seconds, rate, h0=0.0, noise=0.0, rng=None, hz=10):
    cal.begin_still()
    for i in range(int(seconds * hz)):
        t = t0 + i / hz
        cal.sample_still(t, h0 + rate * (t - t0) + (rng.gauss(0, noise) if rng else 0.0))
    cal.end_still()


class DriftCalTest(unittest.TestCase):
    def test_a_clean_drift_is_measured_exactly(self):
        cal = DriftCal(CAL)
        window(cal, 0.0, 5.0, math.radians(0.4))
        self.assertAlmostEqual(math.degrees(cal.rate), 0.4, places=6)

    def test_noise_leaves_a_small_error(self):
        rng = random.Random(1)
        errs = []
        for _ in range(200):
            cal = DriftCal(CAL)
            window(cal, 0.0, 5.0, math.radians(-0.5), noise=math.radians(0.5), rng=rng)
            errs.append(math.degrees(cal.rate) + 0.5)
        sd = (sum(e * e for e in errs) / len(errs)) ** 0.5
        self.assertLess(sd, 0.1)          # pre-registered expectation: about 0.06 deg/s

    def test_samples_before_still_after_are_ignored(self):
        cal = DriftCal(CAL)
        cal.begin_still()
        cal.sample_still(0.0, 1.0)        # still coasting from the card before
        cal.sample_still(0.1, 0.5)
        for i in range(3, 30):
            cal.sample_still(i / 10, 0.0)
        cal.end_still()
        self.assertAlmostEqual(cal.rate, 0.0, places=9)

    def test_windows_pool_with_their_own_intercepts(self):
        cal = DriftCal(CAL)
        r = math.radians(0.3)
        window(cal, 0.0, 2.0, r, h0=0.0)
        window(cal, 10.0, 2.0, r, h0=1.2)  # a turn in between: a different heading, the same drift
        self.assertAlmostEqual(cal.rate, r, places=9)

    def test_the_rate_is_clamped(self):
        cal = DriftCal(CAL)
        window(cal, 0.0, 5.0, math.radians(20))
        self.assertAlmostEqual(math.degrees(cal.rate), 1.0, places=9)

    def test_correct_takes_the_drift_out_of_heading_and_position(self):
        cal = DriftCal(CAL)
        r = math.radians(0.5)
        window(cal, 0.0, 5.0, r)
        # Then the duck walks straight along x at 0.1 m/s; odometry's heading drifts by r, so it
        # integrates the walk along a curving heading. Corrected, it is straight again.
        x = y = 0.0
        last = None
        for i in range(200):
            t = 5.0 + i / 10
            h = r * (t - 5.0)
            if last is not None:
                x += 0.01 * math.cos(h)
                y += 0.01 * math.sin(h)
            last = cal.correct(t, Pose(x, y, h))
        self.assertAlmostEqual(last.h, 0.0, places=9)
        self.assertAlmostEqual(last.y, 0.0, places=9)
        self.assertAlmostEqual(last.x, 1.99, places=6)

    def test_the_shipped_spec_does_not_calibrate(self):
        self.assertIsNone(cardloop.SPEC.get("calibrate"))
        self.assertFalse(cardloop.SPEC["enabled_on_robot"])


if __name__ == "__main__":
    unittest.main()
