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


def repitch(points, pos, delta: float) -> np.ndarray:
    """duck-card-loop/7: `points` as they would have been found had the camera been pitched
    `delta` radians further down than `pos`'s frame believed: each ray from the camera to its point
    turned `delta` about the duck's left axis and met with the floor again. Rays that no longer
    meet it are dropped."""
    q = np.asarray(points, dtype=np.float64).reshape(-1, 2)
    p = np.asarray(pos, dtype=np.float64).reshape(3)
    dx, dy = q[:, 0] - p[0], q[:, 1] - p[1]
    dz = np.full(len(q), -p[2])
    c, s = np.cos(delta), np.sin(delta)
    rx, rz = c * dx + s * dz, -s * dx + c * dz
    ok = rz < -1e-6
    t = -p[2] / rz[ok]
    return np.stack([p[0] + t * rx[ok], p[1] + t * dy[ok]], axis=1)


def pitch_scores(points, pos, square: float, deltas, max_turn_deg: float = 20.0, turn_step_deg: float = 0.5,
                 most: int = 400, harmonics: int = 4) -> np.ndarray:
    """duck-card-loop/7, THE MAT CALIBRATES THE CAMERA. For each pitch error in `deltas`
    (radians), how well the points, `repitch`ed by it, lie on a grid of lines `square` apart:
    the best over turns within `max_turn_deg` of the squared lengths of the mean phase of their
    forward and left coordinates modulo the square, summed over the first `harmonics` multiples
    of the grid's frequency. A pitch error squeezes or stretches the floor along the view, so lines
    at different distances fall out of phase; the right correction puts them back. The first
    harmonic alone hardly sees a few per cent of squeeze and leans about a degree on synthetic
    frames; four find it within a tenth of a degree (tests/test_matpitch.py). Translation does not
    change the score, so the duck's position need not be known."""
    q = np.asarray(points, dtype=np.float64).reshape(-1, 2)
    if len(q) > most:
        q = q[:: -(-len(q) // most)]
    k = 2 * np.pi / square
    turns = np.radians(np.arange(-max_turn_deg, max_turn_deg + turn_step_deg / 2, turn_step_deg))[:, None]
    ct, st = np.cos(turns), np.sin(turns)
    out = np.zeros(len(deltas))
    for i, d in enumerate(deltas):
        r = repitch(q, pos, float(d))
        if len(r) < 2:
            continue
        u = ct * r[:, 0] - st * r[:, 1]
        v = st * r[:, 0] + ct * r[:, 1]
        coh = sum(np.abs(np.exp(1j * m * k * u).mean(axis=1)) ** 2 + np.abs(np.exp(1j * m * k * v).mean(axis=1)) ** 2
                  for m in range(1, harmonics + 1))
        out[i] = coh.max()
    return out
