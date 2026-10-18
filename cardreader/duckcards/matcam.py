"""THE MAT AS A COMPASS, the camera half (duck-card-loop/4, docs/PACKS.md).

One head-camera frame in, the taped grid's floor points out: every dark pixel below the horizon
whose ray meets the floor between `near` and `far` metres from the duck, as (forward, left) metres
from the trunk in the duck's own heading-aligned frame. `cardloop.MatFix` fits the grid to them.

The camera is described the way MuJoCo describes one: `fovy` degrees over the image's height, the
camera looking down its own -z with +x to the right and +y up in the picture, and `rot` (3x3, row
major, camera to frame) and `pos` (metres) giving the camera in the yaw-free trunk frame: x the
trunk's heading, y its left, z up, the origin on the floor under the trunk. That frame needs only
what a duck knows without a compass: its legs (height), its IMU's gravity (pitch and roll) and
where the camera sits on its head.

numpy only, so a reader without OpenCV can run it.
"""

from __future__ import annotations

import numpy as np


def floor_points(gray: np.ndarray, fovy_deg: float, rot, pos, stride: int = 2, near: float = 0.2,
                 far: float = 1.0, dark: float = 0.55) -> np.ndarray:
    """(N, 2) floor points of tape: (forward, left) metres from the trunk. Empty if none."""
    g = np.asarray(gray, dtype=np.float32)[::stride, ::stride]
    h_img, w_img = np.asarray(gray).shape[:2]
    f = (h_img / 2.0) / np.tan(np.radians(fovy_deg) / 2.0)
    vs, us = np.mgrid[0:h_img:stride, 0:w_img:stride]
    x = (us + 0.5 - w_img / 2.0) / f
    y = -(vs + 0.5 - h_img / 2.0) / f
    r = np.asarray(rot, dtype=np.float64).reshape(3, 3)
    p = np.asarray(pos, dtype=np.float64).reshape(3)
    dx = r[0, 0] * x + r[0, 1] * y - r[0, 2]
    dy = r[1, 0] * x + r[1, 1] * y - r[1, 2]
    dz = r[2, 0] * x + r[2, 1] * y - r[2, 2]
    down = dz < -1e-6
    t = np.where(down, -p[2] / np.where(down, dz, -1.0), np.inf)
    fx, fy = p[0] + t * dx, p[1] + t * dy
    rng = np.hypot(fx - p[0], fy - p[1])
    floor = down & (rng >= near) & (rng <= far)
    if not floor.any():
        return np.zeros((0, 2))
    ref = float(np.median(g[floor]))
    tape = floor & (g < dark * ref)
    return np.stack([fx[tape], fy[tape]], axis=1)
