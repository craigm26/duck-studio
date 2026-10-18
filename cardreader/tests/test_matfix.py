"""duck-card-loop/4, the mat as a compass: cardloop.MatFix and duckcards/matcam.py."""

import math
import random
import unittest

from duckcards.cardloop import MatFix, Pose

CFG = {"min_points": 30, "inlier_m": 0.05, "max_fix_deg": 20, "max_fix_m": 0.12}
S = 0.30


def seen(tu, tv, th, rng, per_line=1500, noise=0.003):
    """Tape points a duck truly at (tu, tv, th) in the row's frame would see, in its own frame."""
    pts = []
    for k in range(-8, 9):
        line = S / 2 + S * k
        for _ in range(per_line):
            t = rng.uniform(-2.5, 2.5)
            for wu, wv in ((line, t), (t, line)):
                du, dv = wu - tu, wv - tv
                f = math.cos(th) * du + math.sin(th) * dv
                l = -math.sin(th) * du + math.cos(th) * dv
                if 0.35 < f < 1.0 and abs(l) < 0.4 * f:
                    pts.append((f + rng.gauss(0, noise), l + rng.gauss(0, noise)))
    return pts


class MatFixTest(unittest.TestCase):
    def test_recovers_the_error(self):
        rng = random.Random(3)
        for _ in range(12):
            true = (rng.uniform(-0.9, 0.9), rng.uniform(-0.9, 0.9),
                    math.radians(rng.choice((0, 90, 180, -90)) + rng.uniform(-3, 3)))
            err = (rng.uniform(-0.07, 0.07), rng.uniform(-0.07, 0.07), math.radians(rng.uniform(-12, 12)))
            fix = MatFix(CFG, S)
            fix.correct(Pose(0, 0, 0))
            believed = Pose(true[0] + err[0], true[1] + err[1], true[2] + err[2])
            self.assertIsNotNone(fix.fit(seen(*true, rng), believed))
            got = fix.correct(believed)
            self.assertLess(math.hypot(got.x - true[0], got.y - true[1]), 0.01)
            self.assertLess(abs(math.degrees(math.remainder(got.h - true[2], 2 * math.pi))), 0.5)

    def test_later_poses_are_corrected_too(self):
        rng = random.Random(4)
        fix = MatFix(CFG, S)
        fix.correct(Pose(0, 0, 0))
        # Odometry believes 5 degrees left of the truth, 4 cm short.
        fix.fit(seen(0.30, 0.0, 0.0, rng), Pose(0.26, 0.0, math.radians(5)))
        # It then walks 0.30 along what it believes: truly 0.30 more along the true heading.
        after = fix.correct(Pose(0.26 + 0.30 * math.cos(math.radians(5)), 0.30 * math.sin(math.radians(5)),
                                 math.radians(5)))
        self.assertAlmostEqual(after.x, 0.60, delta=0.01)
        self.assertAlmostEqual(after.y, 0.0, delta=0.01)
        self.assertAlmostEqual(after.h, 0.0, delta=math.radians(0.5))

    def test_the_row_frame_is_where_the_row_began(self):
        rng = random.Random(5)
        fix = MatFix(CFG, S)
        start = Pose(1.7, -0.4, math.radians(33))       # odometry's frame, anywhere
        fix.correct(start)
        c, s = math.cos(start.h), math.sin(start.h)
        # Truly one square ahead in the row's frame; believed 3 cm left of it.
        believed = Pose(start.x + 0.30 * c - 0.03 * s, start.y + 0.30 * s + 0.03 * c, start.h)
        self.assertIsNotNone(fix.fit(seen(0.30, 0.0, 0.0, rng), believed))
        got = fix.correct(believed)
        self.assertAlmostEqual(got.x, start.x + 0.30 * c, delta=0.01)
        self.assertAlmostEqual(got.y, start.y + 0.30 * s, delta=0.01)

    def test_too_few_points_fix_nothing(self):
        fix = MatFix(CFG, S)
        fix.correct(Pose(0, 0, 0))
        self.assertIsNone(fix.fit([(0.5, 0.15)] * 10, Pose(0, 0, 0)))
        self.assertEqual(fix.fixes, [None])
        self.assertEqual(fix.correct(Pose(0.1, 0.2, 0.3)), Pose(0.1, 0.2, 0.3))

    def test_a_fit_past_the_limit_is_refused(self):
        rng = random.Random(6)
        fix = MatFix(CFG, S)
        fix.correct(Pose(0, 0, 0))
        # 13 cm off along both axes: the nearest lines are a square's other side, past max_fix_m.
        self.assertIsNone(fix.fit(seen(0.0, 0.0, 0.0, rng), Pose(0.13, 0.13, 0.0)))

    def test_one_family_fixes_only_across_it(self):
        rng = random.Random(7)
        fix = MatFix(CFG, S)
        fix.correct(Pose(0, 0, 0))
        # Only lines across the heading (u = const): forward is fixed, sideways is not.
        pts = [p for p in seen(0.0, 0.0, 0.0, rng) if abs(p[1]) < 0.4 * p[0]]
        across = []
        for f, l in pts:
            if abs((f - S / 2) - S * round((f - S / 2) / S)) < 0.012:
                across.append((f, l))
        got = fix.fit(across, Pose(0.04, 0.05, 0.0))
        self.assertIsNotNone(got)
        self.assertAlmostEqual(got[1], -0.04, delta=0.01)
        self.assertEqual(got[2], 0.0)


class MatcamTest(unittest.TestCase):
    def test_floor_points_lie_on_the_tape(self):
        try:
            import numpy as np
        except ImportError:
            self.skipTest("numpy")
        from duckcards import matcam
        # A camera 0.25 m up, 0.06 m ahead of the trunk, looking ahead and 20 degrees down, as
        # MuJoCo describes one: it looks down its -z, +x right, +y up.
        pitch = math.radians(20)
        fwd = np.array([math.cos(pitch), 0, -math.sin(pitch)])
        right = np.array([0, -1.0, 0])
        up = np.cross(right, -fwd)
        rot = np.stack([right, up, -fwd], axis=1)
        pos = np.array([0.06, 0.0, 0.25])
        h, w, fovy = 360, 640, 45.0
        f = (h / 2) / math.tan(math.radians(fovy) / 2)
        vs, us = np.mgrid[0:h, 0:w]
        d = rot @ np.stack([(us + 0.5 - w / 2) / f, -(vs + 0.5 - h / 2) / f, -np.ones_like(us, dtype=float)]).reshape(3, -1)
        t = np.where(d[2] < 0, -pos[2] / np.where(d[2] < 0, d[2], -1), np.inf)
        fx, fy = pos[0] + t * d[0], pos[1] + t * d[1]
        near = lambda a: np.abs((a - 0.15) - 0.3 * np.round((a - 0.15) / 0.3))   # inf past the horizon: never tape
        with np.errstate(invalid="ignore"):
            tape = (np.minimum(near(fx), near(fy)) < 0.0095) & np.isfinite(t)
        gray = np.where(tape, 20, 200).reshape(h, w).astype(np.uint8)
        pts = matcam.floor_points(gray, fovy, rot, pos, stride=1)
        self.assertGreater(len(pts), 1000)
        off = np.minimum(near(pts[:, 0]), near(pts[:, 1]))
        self.assertLess(float(off.max()), 0.0096)
        reach = np.hypot(pts[:, 0] - pos[0], pts[:, 1] - pos[1])
        self.assertTrue(((reach >= 0.2) & (reach <= 1.0)).all())


if __name__ == "__main__":
    unittest.main()
