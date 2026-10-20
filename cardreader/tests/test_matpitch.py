"""duck-card-loop/7, the mat calibrates the camera: matcam.repitch and matcam.pitch_scores."""

import math
import unittest

try:
    import numpy as np
except ImportError:          # the reader runs without numpy; only a reader that looks needs it
    np = None


def frame(true_pitch_deg, believed_pitch_deg, turn_deg=0.0, shift=(0.0, 0.0), height=0.25):
    """A camera `height` up and 0.06 m ahead of the trunk, truly pitched `true_pitch_deg` down,
    over a grid of 1.9 cm tape lines 0.30 m apart, the duck turned `turn_deg` and shifted on it;
    the picture and the rotation the duck believes (pitched `believed_pitch_deg`)."""
    from duckcards import matcam

    def rot_of(pitch):
        p = math.radians(pitch)
        fwd = np.array([math.cos(p), 0, -math.sin(p)])
        right = np.array([0, -1.0, 0])
        up = np.cross(right, -fwd)
        return np.stack([right, up, -fwd], axis=1)

    pos = np.array([0.06, 0.0, height])
    h, w, fovy = 360, 640, 45.0
    f = (h / 2) / math.tan(math.radians(fovy) / 2)
    vs, us = np.mgrid[0:h, 0:w]
    d = rot_of(true_pitch_deg) @ np.stack([(us + 0.5 - w / 2) / f, -(vs + 0.5 - h / 2) / f,
                                           -np.ones_like(us, dtype=float)]).reshape(3, -1)
    t = np.where(d[2] < 0, -pos[2] / np.where(d[2] < 0, d[2], -1), np.inf)
    fx, fy = pos[0] + t * d[0], pos[1] + t * d[1]
    a = math.radians(turn_deg)
    gx = math.cos(a) * fx - math.sin(a) * fy + shift[0]
    gy = math.sin(a) * fx + math.cos(a) * fy + shift[1]
    near = lambda v: np.abs((v - 0.15) - 0.3 * np.round((v - 0.15) / 0.3))
    with np.errstate(invalid="ignore"):
        tape = (np.minimum(near(gx), near(gy)) < 0.0095) & np.isfinite(t)
    gray = np.where(tape, 20, 200).reshape(h, w).astype(np.uint8)
    return matcam.floor_points(gray, fovy, rot_of(believed_pitch_deg), pos, stride=1), pos


@unittest.skipIf(np is None, "numpy")
class MatPitchTest(unittest.TestCase):
    def best(self, pts, pos):
        from duckcards import matcam
        deltas = np.radians(np.arange(-4, 4.05, 0.1))
        return math.degrees(deltas[int(np.argmax(matcam.pitch_scores(pts, pos, 0.30, deltas)))])

    def test_a_pitch_error_is_found(self):
        for err in (-2.0, -1.0, 1.0, 2.0):
            pts, pos = frame(20 + err, 20, turn_deg=3.0, shift=(0.04, -0.07))
            self.assertAlmostEqual(self.best(pts, pos), err, delta=0.25, msg=f"error {err}")

    def test_no_error_is_found_as_none(self):
        pts, pos = frame(20, 20, turn_deg=-4.0, shift=(-0.05, 0.02))
        self.assertAlmostEqual(self.best(pts, pos), 0.0, delta=0.25)

    def test_repitch_by_the_error_puts_the_lines_back(self):
        from duckcards import matcam
        pts, pos = frame(22, 20)
        fixed = matcam.repitch(pts, pos, math.radians(2.0))
        near = lambda v: np.abs((v - 0.15) - 0.3 * np.round((v - 0.15) / 0.3))
        self.assertLess(float(np.percentile(np.minimum(near(fixed[:, 0]), near(fixed[:, 1])), 95)), 0.012)
        self.assertGreater(float(np.percentile(np.minimum(near(pts[:, 0]), near(pts[:, 1])), 95)), 0.02)


if __name__ == "__main__":
    unittest.main()
