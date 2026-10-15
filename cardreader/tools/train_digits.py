"""Train the network that reads the number written on Repeat, and choose when to trust it.

    python3 cardreader/tools/train_digits.py --mnist DIR            # writes duckcards/digits.npz
    python3 cardreader/tools/train_digits.py --mnist DIR --check    # train, report, write nothing

DIR holds MNIST as Hugging Face serves it, `ylecun/mnist`: `train-00000-of-00001.parquet` and
`test-00000-of-00001.parquet`, from https://huggingface.co/datasets/ylecun/mnist (files under
`mnist/`). Its dataset card gives the licence as MIT ("license: mit"; "MIT Licence") and the data
as Yann LeCun, Corinna Cortes and Christopher J.C. Burges's. The files used were sha256
f2c01285a9f89399335b00ee4e8d499dc4e46db5e39c74903ce5618d895eb3bf (train) and
d49fcf556ce25b002b302e318ce4a11098bbfe5d4499c3f35d7c72297c52374b (test). Making the examples needs
pyarrow, Pillow and OpenCV; the network is trained in numpy, with the arithmetic the duck runs. The
duck needs only numpy and the weights this writes. `--cache DIR` keeps the examples (about 15
minutes to make on two cores) and the network, so the thresholds can be chosen again in seconds. Only the train split is used here: the last 6,000 of its 60,000 digits are
held out to choose the thresholds, and the test split is left for `tests/test_digits.py`.

WHAT IT LEARNS FROM IS WHAT THE DUCK SEES. Every example is an MNIST digit written into a drawn copy
of Repeat's box (the border, the name above, "times" beside, the code word below, at the measured
places), at a random size, place, slant, shear and stroke weight, in ink from marker black to pencil
grey; then photographed: a random pose (turned up to 40 degrees, tilted up to 25, rolled up to 30),
small (0.8 to 6 picture pixels a card unit, which is 60 cm on the duck's camera down to 10 cm, and
the sim camera at 0.41 of it), soft, low in contrast, noisy, with the code's corners found a little
wrong. Then the duck's own `digits.prepare` finds the box and shapes the ink, and that is what the
network is trained on. Two figures side by side are a class of their own, "something else", and so
is a figure too big for the box (its border cuts it, and a 7 cut short is a 1) and a blank box whose
noise the ink gate took for writing.

THE THRESHOLDS ARE CHOSEN ON DIGITS IT NEVER SAW. The held-out 6,000, written and photographed the
same way, choose: how much ink means written (so blank boxes read blank: at most one in two
hundred passes), then together how box-like the found border must be, the smallest box worth
reading, how dark the ink may be where the read stops (a figure running into the border is cut,
and asked about), and how sure the network must be (its top answer's probability, and the gap to
the second). The rule: at most one confident mistake in a thousand answers given, overall and among
boxes 3 picture pixels a unit and bigger; then the most digits read. These pictures are harder than
a classroom's on purpose (pencil grey, contrast lost, turned 40 degrees), so the coverage they show
is a floor and the mistakes a ceiling.

SEEDED. The same files and this script give the same examples; the network's training is seeded
too, though a multi-threaded BLAS can still move its last bits.
"""

from __future__ import annotations

import argparse
import io
import json
import math
import multiprocessing as mp
import os
import pathlib
import sys
import time

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from duckcards import digits  # noqa: E402
from duckcards.cards import SQUARE, WRITE_BOX, WRITE_EDGE  # noqa: E402

SEED = 20261014
HELD_OUT = 6000
F = 1065.0                    # the duck's camera, pixels; only the shape of the perspective depends on it
MM = 0.635                    # millimetres to a card unit
R = 6.0                       # the drawn card: pixels a card unit
CANVAS = (-8.0, 70.0, 36.0, 112.0)     # the part of the card drawn: left, top, right, bottom
OPEN = dict(side_min=-1e9, ink_floor=0.06, ink_min=0.0, peak_min=0.0)
ERR_BOX = 1.0                 # a border found further than this from the true one, card units, is wrong


def load_mnist(directory: pathlib.Path):
    import pyarrow.parquet as pq
    from PIL import Image
    out = {}
    for split in ("train", "test"):
        t = pq.read_table(directory / f"{split}-00000-of-00001.parquet")
        images = t.column("image").to_pylist()
        x = np.stack([np.asarray(Image.open(io.BytesIO(d["bytes"])).convert("L")) for d in images])
        y = np.asarray(t.column("label").to_pylist(), np.uint8)
        out[split] = (x, y)
    return out


# ---------------------------------------------------------------- drawing the box
def _rounded(shape, edge, radius):
    h, w = shape
    u = CANVAS[0] + (np.arange(w) + 0.5) / R
    v = CANVAS[1] + (np.arange(h) + 0.5) / R
    left, top, right, bottom = edge
    cx, cy = (left + right) / 2, (top + bottom) / 2
    qx = np.abs(u[None, :] - cx) - ((right - left) / 2 - radius)
    qy = np.abs(v[:, None] - cy) - ((bottom - top) / 2 - radius)
    d = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - radius
    return np.clip(0.5 - d * R, 0, 1)


def _rect(img, l, t, r, b, level):
    import cv2
    p = lambda u, v: (int(round((u - CANVAS[0]) * R)), int(round((v - CANVAS[1]) * R)))  # noqa: E731
    cv2.rectangle(img, p(l, t), p(r, b), float(level), -1)


def _words(img, rng, l, t, r, b, level):
    """A word: a solid bar half the time (as the test camera draws it), letters the other half."""
    if rng.random() < 0.5:
        _rect(img, l, t, r, b, level)
        return
    u = l
    while u < r - 0.5:
        w = rng.uniform(1.0, 2.6)
        top = t + (rng.uniform(0, 0.35) * (b - t) if rng.random() < 0.5 else 0)
        _rect(img, u, top, min(u + w, r), b, level)
        u += w + rng.uniform(0.35, 0.8)


BORDERS = (0.38, 0.42, 0.46, 0.5, 0.55, 0.62)     # printed border widths drawn, card units
_RINGS: dict[float, np.ndarray] = {}


def _ring(shape, border):
    if border not in _RINGS:
        inner = tuple(e + s * border for e, s in zip(WRITE_EDGE, (1, 1, -1, -1)))
        _RINGS[border] = (_rounded(shape, WRITE_EDGE, 1.4) - _rounded(shape, inner, 1.4 - border)).astype(np.float32)
    return _RINGS[border]


def card(rng):
    """The card around the box, as reflectance: paper 1, the border, the name, "times", the code
    word, and beyond the card's left edge whatever it lies on."""
    w = int(round((CANVAS[2] - CANVAS[0]) * R))
    h = int(round((CANVAS[3] - CANVAS[1]) * R))
    img = np.ones((h, w), np.float32)
    off = int(round((0 - CANVAS[0]) * R))
    img[:, :off] = rng.uniform(0.2, 0.9)
    _words(img, rng, 6, 75.5, rng.uniform(36, 42), 84, rng.uniform(0.08, 0.2))
    ring = _ring(img.shape, BORDERS[int(rng.integers(len(BORDERS)))])
    img *= 1 - ring * (1 - rng.uniform(0.08, 0.2))
    _words(img, rng, rng.uniform(19.6, 20.6), rng.uniform(87, 88.2), 33.7, rng.uniform(93, 94), rng.uniform(0.3, 0.5))
    _words(img, rng, 6, 98, rng.uniform(28, 33), 101.5, rng.uniform(0.3, 0.55))
    return img


def _crop(a):
    rows, cols = np.nonzero(a > 0.1)
    return a[rows.min():rows.max() + 1, cols.min():cols.max() + 1]


def write(img, rng, figure, centre, height, aspect=1.0, angle=0.0, shear=0.0, weight=0, ink=0.1):
    """Write `figure` (MNIST's way: 0..255 ink) into the card, `height` card units tall, centred at
    `centre`, slanted `angle` degrees and sheared, its strokes thickened by `weight` pixels (thinned
    when negative), in ink of reflectance `ink`."""
    import cv2
    a = _crop(figure.astype(np.float32) / 255.0)
    k = height * R / a.shape[0]
    c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    lin = np.array([[c, -s], [s, c]]) @ np.array([[1, shear], [0, 1]]) @ np.diag([k * aspect, k])
    src_c = np.array([(a.shape[1] - 1) / 2, (a.shape[0] - 1) / 2])
    dst_c = np.array([(centre[0] - CANVAS[0]) * R - 0.5, (centre[1] - CANVAS[1]) * R - 0.5])
    m = np.c_[lin, dst_c - lin @ src_c].astype(np.float32)
    alpha = cv2.warpAffine(a, m, (img.shape[1], img.shape[0]), flags=cv2.INTER_LINEAR)
    if weight:
        size = 2 * abs(weight) + 1
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (size, size))
        alpha = cv2.dilate(alpha, kernel) if weight > 0 else cv2.erode(alpha, kernel)
    img *= 1 - np.clip(alpha, 0, 1) * (1 - ink)


# ---------------------------------------------------------------- photographing it
def _rot(yaw, pitch, roll):
    y, p, r = (math.radians(a) for a in (yaw, pitch, roll))
    ry = np.array([[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]])
    rx = np.array([[1, 0, 0], [0, math.cos(p), -math.sin(p)], [0, math.sin(p), math.cos(p)]])
    rz = np.array([[math.cos(r), -math.sin(r), 0], [math.sin(r), math.cos(r), 0], [0, 0, 1]])
    return rz @ ry @ rx


def camera(rng, s):
    """Card units to picture pixels for a random pose, `s` picture pixels a card unit at the box."""
    rot = _rot(rng.uniform(-40, 40), rng.uniform(-25, 25), rng.uniform(-30, 30))
    z = F * MM / s
    box = np.array([(WRITE_EDGE[0] + WRITE_EDGE[2]) / 2, (WRITE_EDGE[1] + WRITE_EDGE[3]) / 2])
    at = np.array([z * math.tan(math.radians(rng.uniform(-12, 12))), z * math.tan(math.radians(rng.uniform(-12, 12))), z])
    t = at - rot @ np.array([box[0] * MM, box[1] * MM, 0.0])
    k = np.array([[F, 0, 0], [0, F, 0], [0, 0, 1.0]])
    return k @ np.c_[rot[:, 0] * MM, rot[:, 1] * MM, t]


def _project(h, pts):
    p = np.c_[np.asarray(pts, float), np.ones(len(pts))] @ h.T
    return p[:, :2] / p[:, 2:]


def photograph(img, rng, s):
    """The drawn card through a random camera: the picture (uint8, cropped round the box), the card
    to picture homography for that crop, with pixel centres at the index."""
    import cv2
    h = camera(rng, s)
    corners = [(CANVAS[0], CANVAS[1]), (CANVAS[2], CANVAS[1]), (CANVAS[2], CANVAS[3]), (CANVAS[0], CANVAS[3])]
    p = _project(h, corners)
    if not np.all(np.isfinite(p)):
        return None
    x0, y0 = np.floor(p.min(0)).astype(int) - 2
    x1, y1 = np.ceil(p.max(0)).astype(int) + 2
    if x1 - x0 > 1400 or y1 - y0 > 1400:
        return None
    shift = np.array([[1, 0, -x0], [0, 1, -y0], [0, 0, 1.0]])
    h = shift @ h
    # canvas pixel (j, i), centre at index: card unit CANVAS + (j + .5)/R
    to_units = np.array([[1 / R, 0, CANVAS[0] + 0.5 / R], [0, 1 / R, CANVAS[1] + 0.5 / R], [0, 0, 1.0]])
    m = h @ to_units
    shrink = R / s
    src = img
    if shrink > 1.2:
        src = cv2.GaussianBlur(img, (0, 0), 0.45 * shrink)
    illum = rng.uniform(110, 250)
    ground = rng.uniform(0.15, 0.9) * illum
    pic = cv2.warpPerspective(src * illum, m, (int(x1 - x0), int(y1 - y0)), flags=cv2.INTER_LINEAR,
                              borderMode=cv2.BORDER_CONSTANT, borderValue=float(ground))
    # light falling off across the picture, the lens's blur, contrast lost, the sensor's noise
    yy, xx = np.mgrid[0:pic.shape[0], 0:pic.shape[1]].astype(np.float32)
    g = 1 + rng.uniform(-0.12, 0.12) * (xx / max(pic.shape[1], 1) - 0.5) + rng.uniform(-0.12, 0.12) * (yy / max(pic.shape[0], 1) - 0.5)
    pic = pic * g
    pic = cv2.GaussianBlur(pic, (0, 0), rng.uniform(0.45, 1.35))
    pic = 128 + (pic - 128) * rng.uniform(0.6, 1.0)
    pic = pic + rng.normal(0, rng.uniform(0.5, 5.0), pic.shape)
    return np.clip(pic, 0, 255).round().astype(np.uint8), h


# ---------------------------------------------------------------- one example
def example(rng, figure, label, kind, figures=None, digit=-1):
    """One photographed box. `kind`: "digit", "blank", "two" or "over" (a figure taller than the
    box). Returns a dict, or None
    when the camera could not see it."""
    s = math.exp(rng.uniform(math.log(0.8), math.log(6.0)))
    img = card(rng)
    left, top, right, bottom = WRITE_BOX
    bw, bh = right - left, bottom - top
    ink = rng.uniform(0.04, 0.45)
    weight = int(rng.choice([-1, 0, 0, 0, 1, 1, 2]))
    if kind in ("digit", "over"):
        # A figure taller than the box is cut by its border, and a cut 7 is a 1: it is "something
        # else", to be asked about, not read.
        height = bh * (rng.uniform(1.05, 1.3) if kind == "over" else rng.uniform(0.5, 0.85))
        a = _crop(figure.astype(np.float32) / 255.0)
        aspect = rng.uniform(0.8, 1.25)
        width = height * a.shape[1] / a.shape[0] * aspect
        if width > bw:
            height *= bw / width
            width = bw
        sx, sy = max(bw - width, 0) / 2, max(bh - height, 0) / 2
        centre = ((left + right) / 2 + rng.uniform(-1, 1) * sx + rng.normal(0, 0.3),
                  (top + bottom) / 2 + rng.uniform(-1, 1) * sy + rng.normal(0, 0.25))
        write(img, rng, figure, centre, height, aspect, float(np.clip(rng.normal(0, 6), -15, 15)),
              rng.uniform(-0.25, 0.25), weight, ink)
    elif kind == "two":
        height = bh * rng.uniform(0.6, 0.95)
        for j, f in enumerate(figures):
            cx = left + bw * (0.27 if j == 0 else 0.73) + rng.normal(0, 0.3)
            write(img, rng, f, (cx, (top + bottom) / 2 + rng.normal(0, 0.3)), height, rng.uniform(0.8, 1.1),
                  rng.normal(0, 4), rng.uniform(-0.2, 0.2), weight, ink)
    shot = photograph(img, rng, s)
    if shot is None:
        return None
    pic, h = shot
    left_, top_, right_, bottom_ = SQUARE
    square = [(right_, top_), (left_, top_), (left_, bottom_), (right_, bottom_)]
    corners = _project(h, square) + rng.normal(0, rng.uniform(0.05, 0.3), (4, 2)) + digits.CORNER_OFFSET
    prep = digits.prepare(pic, corners, OPEN)
    out = {"label": label, "kind": kind, "s": s, "found": prep.box is not None, "err": 99.0,
           "score": prep.box_score, "side": -1.0, "ink": prep.ink, "peak": prep.peak, "px": prep.px_per_unit,
           "edge": prep.edge, "digit": digit, "x": None}
    if prep.box is not None:
        b = prep.box
        side = min(b.sides)
        found = np.array([(b.left, b.top), (b.right, b.top), (b.right, b.bottom), (b.left, b.bottom)])
        fx, fy, _ = digits._apply(prep.h, digits.PATCH_LEFT + found[:, 0] / digits.PX,
                                  digits.PATCH_TOP + found[:, 1] / digits.PX)
        L, T, Rr, B = WRITE_EDGE
        truth = _project(h, [(L, T), (Rr, T), (Rr, B), (L, B)])
        out["err"] = float(np.hypot(fx - truth[:, 0], fy - truth[:, 1]).max() / s)
        out["side"] = side
    if prep.x is not None:
        out["x"] = np.round(prep.x * 255).astype(np.uint8)
    return out


KINDS = (("digit", 0.84), ("blank", 0.08), ("two", 0.04), ("over", 0.04))


def _chunk(job):
    os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
    seed, xs, ys, n = job
    rng = np.random.default_rng(seed)
    names = [k for k, _ in KINDS]
    weights = np.array([w for _, w in KINDS])
    rows = []
    while len(rows) < n:
        kind = names[rng.choice(len(names), p=weights)]
        i = int(rng.integers(len(xs)))
        if kind == "digit":
            r = example(rng, xs[i], int(ys[i]), kind)
        elif kind == "over":
            r = example(rng, xs[i], digits.OTHER, kind, digit=int(ys[i]))
        elif kind == "two":
            j = int(rng.integers(len(xs)))
            r = example(rng, None, digits.OTHER, kind, figures=(xs[i], xs[j]))
        else:
            r = example(rng, None, digits.OTHER, kind)
        if r is not None:
            rows.append(r)
    return rows


def make(xs, ys, n, seed, workers, chunk=1000):
    jobs = [(seed + k, xs, ys, min(chunk, n - k * chunk)) for k in range((n + chunk - 1) // chunk)]
    with mp.get_context("fork").Pool(workers) as pool:
        parts = pool.map(_chunk, jobs)
    rows = [r for part in parts for r in part]
    cols = {k: np.array([r[k] for r in rows])
            for k in ("label", "s", "err", "score", "side", "ink", "peak", "px", "found", "edge", "digit")}
    cols["kind"] = np.array([r["kind"] for r in rows])
    has = np.array([r["x"] is not None for r in rows])
    x = np.zeros((len(rows), digits.SIDE * digits.SIDE), np.uint8)
    for k, r in enumerate(rows):
        if r["x"] is not None:
            x[k] = r["x"]
    cols["x"], cols["has_x"] = x, has
    return cols


# ---------------------------------------------------------------- choosing the gates
def written_gates(d):
    """Blank or written: the least ink a written box shows, set so blank boxes read blank."""
    ok = d["found"] & (d["err"] <= ERR_BOX)
    blank = ok & (d["kind"] == "blank")
    digit = ok & (d["kind"] == "digit")
    best = None
    for ink_min in (0.5, 0.75, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0):
        for peak_min in (0.08, 0.1, 0.12, 0.15, 0.2, 0.25):
            blank_pass = ((d["ink"] >= ink_min) & (d["peak"] >= peak_min))[blank].mean()
            digit_pass = ((d["ink"] >= ink_min) & (d["peak"] >= peak_min))[digit].mean()
            if blank_pass <= 0.005 and (best is None or digit_pass > best[2]):
                best = (ink_min, peak_min, digit_pass, blank_pass)
    return best


def box_gate(d, min_px):
    """How box-like a found border must be: the weakest side's line strength above which borders
    found in the wrong place are rare, among boxes big enough to read."""
    big = d["found"] & (d["px"] >= min_px)
    wrong = big & (d["err"] > ERR_BOX)
    right = big & (d["err"] <= ERR_BOX)
    for side_min in np.arange(0.0, 0.3, 0.005):
        if (wrong & (d["side"] >= side_min)).sum() <= 0.001 * (right & (d["side"] >= side_min)).sum():
            return float(side_min), float((right & (d["side"] >= side_min)).sum() / max(right.sum(), 1))
    return 0.3, 0.0


def decisions(d, probs, g):
    """What `digits.read` would answer for every example, under gates `g`: count or None."""
    passed = (d["found"] & (d["side"] >= g["side_min"]) & (d["px"] >= g["min_px"])
              & (d["ink"] >= g["ink_min"]) & (d["peak"] >= g["peak_min"]) & d["has_x"]
              & (d["edge"] <= g["edge_max"]))
    order = np.argsort(-probs, axis=1)
    top = order[:, 0]
    p1 = probs[np.arange(len(probs)), top]
    p2 = probs[np.arange(len(probs)), order[:, 1]]
    sure = passed & (p1 >= g["p_min"]) & (p1 - p2 >= g["margin_min"]) & (top >= 1) & (top <= 9)
    return np.where(sure, top, -1)


def score(d, answer):
    """Shares of written digits 1..9 read right, read wrong, and refused; and confident answers
    given for anything that is not one digit 1..9 (a 0, two figures, a figure cut by the border, a
    blank box)."""
    real = (d["kind"] == "digit") & (d["label"] >= 1)
    given = answer >= 0
    right = real & given & (answer == d["label"])
    itself = (d["kind"] == "over") & (answer == d["digit"])
    wrong = given & ~(real & (answer == d["label"])) & ~itself
    return right.sum() / max(real.sum(), 1), wrong.sum(), given.sum(), real.sum()


# ---------------------------------------------------------------- the network
def train(X, Y, sizes=(256, 128), epochs=20, batch=256, lr=2e-3, l2=1e-5, seed=SEED):
    """A small fully connected network, ReLU, softmax, trained with Adam on a cosine schedule, in
    float32 numpy: the same arithmetic `digits._Model` runs on the duck."""
    rng = np.random.default_rng(seed)
    classes = digits.OTHER + 1
    dims = [X.shape[1], *sizes, classes]
    W = [(rng.normal(0, math.sqrt(2 / a), (a, b))).astype(np.float32) for a, b in zip(dims[:-1], dims[1:])]
    B = [np.zeros(b, np.float32) for b in dims[1:]]
    m = [np.zeros_like(p) for p in W + B]
    v = [np.zeros_like(p) for p in W + B]
    b1, b2, eps, step = 0.9, 0.999, 1e-8, 0
    for epoch in range(epochs):
        rate = lr * 0.5 * (1 + math.cos(math.pi * epoch / epochs))
        order = rng.permutation(len(X))
        loss = 0.0
        for start in range(0, len(X), batch):
            idx = order[start:start + batch]
            acts = [X[idx]]
            for i in range(len(W)):
                z = acts[-1] @ W[i] + B[i]
                acts.append(np.maximum(z, 0) if i < len(W) - 1 else z)
            z = acts[-1] - acts[-1].max(1, keepdims=True)
            p = np.exp(z)
            p /= p.sum(1, keepdims=True)
            yb = Y[idx]
            loss -= float(np.log(p[np.arange(len(yb)), yb] + 1e-12).sum())
            g = p
            g[np.arange(len(yb)), yb] -= 1
            g /= len(yb)
            grads_w, grads_b = [None] * len(W), [None] * len(W)
            for i in reversed(range(len(W))):
                grads_w[i] = acts[i].T @ g + l2 * W[i]
                grads_b[i] = g.sum(0)
                if i:
                    g = (g @ W[i].T) * (acts[i] > 0)
            step += 1
            for j, (param, grad) in enumerate(zip(W + B, grads_w + grads_b)):
                m[j] = b1 * m[j] + (1 - b1) * grad
                v[j] = b2 * v[j] + (1 - b2) * grad * grad
                param -= rate * (m[j] / (1 - b1 ** step)) / (np.sqrt(v[j] / (1 - b2 ** step)) + eps)
        print(f"  epoch {epoch + 1}: loss {loss / len(X):.4f}", flush=True)
    return list(zip(W, B))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mnist", required=True, type=pathlib.Path)
    ap.add_argument("--out", type=pathlib.Path, default=HERE.parent / "duckcards" / "digits.npz")
    ap.add_argument("--train", type=int, default=240_000)
    ap.add_argument("--val", type=int, default=36_000)
    ap.add_argument("--workers", type=int, default=max(1, min(4, os.cpu_count() or 1)))
    ap.add_argument("--epochs", type=int, default=20)
    ap.add_argument("--cache", type=pathlib.Path, help="keep the made examples here and reuse them")
    ap.add_argument("--check", action="store_true", help="train and report; write no weights")
    ap.add_argument("--retrain", action="store_true", help="train again even when --cache holds a network")
    args = ap.parse_args()

    t0 = time.time()
    mnist = load_mnist(args.mnist)
    x, y = mnist["train"]
    fit_x, fit_y = x[:-HELD_OUT], y[:-HELD_OUT]
    val_x, val_y = x[-HELD_OUT:], y[-HELD_OUT:]
    sets = {}
    for name, (xs, ys, n, seed) in {"train": (fit_x, fit_y, args.train, SEED),
                                    "val": (val_x, val_y, args.val, SEED + 10_000_000)}.items():
        path = args.cache / f"{name}.npz" if args.cache else None
        if path and path.exists():
            with np.load(path) as z:
                sets[name] = {k: z[k] for k in z.files}
        else:
            sets[name] = make(xs, ys, n, seed, args.workers)
            if path:
                path.parent.mkdir(parents=True, exist_ok=True)
                np.savez(path, **sets[name])
        print(f"{name}: {len(sets[name]['label'])} examples ({time.time() - t0:.0f} s)", flush=True)

    tr, va = sets["train"], sets["val"]
    # the box finder, judged against where the box really was
    for name, d in (("train", tr), ("val", va)):
        for lo, hi in ((0.8, 1.2), (1.2, 1.6), (1.6, 2.2), (2.2, 3.0), (3.0, 4.5), (4.5, 6.0)):
            m = (d["s"] >= lo) & (d["s"] < hi)
            print(f"  {name} box at {lo}-{hi} px/unit: found within {ERR_BOX} unit {np.mean(d['err'][m] <= ERR_BOX):.3f}")

    ink_min, peak_min, digit_pass, blank_pass = written_gates(va)
    print(f"written: ink >= {ink_min} units^2 and peak >= {peak_min}: digits {digit_pass:.3f} pass, blanks {blank_pass:.4f}")

    # train on what the duck would pass to the network: a found border near the true one, ink
    use = tr["has_x"] & tr["found"] & (tr["err"] <= ERR_BOX) & (tr["ink"] >= ink_min) & (tr["peak"] >= peak_min)
    use |= tr["has_x"] & (tr["kind"] != "digit")
    X = tr["x"][use].astype(np.float32) / 255.0
    Y = tr["label"][use].astype(np.int64)
    print(f"training on {len(Y)} examples, classes {np.bincount(Y, minlength=11).tolist()}", flush=True)
    net_path = args.cache / "net.npz" if args.cache else None
    if net_path and net_path.exists() and not args.retrain:
        with np.load(net_path) as z:
            layers = [(z[f"w{i}"], z[f"b{i}"]) for i in range(len([k for k in z.files if k.startswith("w")]))]
        print("network: from the cache", flush=True)
    else:
        layers = train(X, Y, epochs=args.epochs)
        layers = [(w.astype(np.float16), b.astype(np.float16)) for w, b in layers]
        if net_path:
            np.savez(net_path, **{f"{k}{i}": a for i, (w, b) in enumerate(layers) for k, a in (("w", w), ("b", b))})
    print(f"trained ({time.time() - t0:.0f} s)", flush=True)

    def probs(xs):
        a = xs.astype(np.float32) / 255.0
        for i, (w, b) in enumerate(layers):
            a = a @ w.astype(np.float32) + b.astype(np.float32)
            if i < len(layers) - 1:
                a = np.maximum(a, 0)
        a = a - a.max(1, keepdims=True)
        e = np.exp(a)
        return e / e.sum(1, keepdims=True)

    pv = probs(va["x"])
    ok = va["has_x"] & va["found"] & (va["err"] <= ERR_BOX) & (va["ink"] >= ink_min) & (va["peak"] >= peak_min)
    raw = (np.argmax(pv, 1) == va["label"])[ok & (va["kind"] == "digit")].mean()
    print(f"held-out raw accuracy on found, written digits 0-9: {raw:.4f}")
    for lo, hi in ((0.8, 1.2), (1.2, 1.6), (1.6, 2.2), (2.2, 3.0), (3.0, 4.5), (4.5, 6.0)):
        m = ok & (va["kind"] == "digit") & (va["s"] >= lo) & (va["s"] < hi)
        print(f"  {lo}-{hi} px/unit: raw accuracy {(np.argmax(pv, 1) == va['label'])[m].mean():.3f} (n={m.sum()})")

    # the gates: smallest box, box-likeness, sureness. At most one confident mistake in a thousand
    # answers given, overall and among the boxes read from 3 px a unit up; then the most digits read.
    best, fallback = None, None
    near = va["s"] >= 3.0
    va_near = {k: va[k][near] for k in ("kind", "label", "digit")}
    # The side gate alone, at `box_gate`'s strictest, refuses many boxes found in the right place
    # at 30 cm and beyond; the gates after it also refuse what a wrong place shows. So it is chosen
    # with them, from `box_gate`'s value down.
    combos = [(min_px, side_min, edge_max, p_min, margin_min)
              for min_px in (1.4, 1.6, 2.0, 2.5)
              for side_min in sorted({0.06, 0.08, 0.1, 0.12, box_gate(va, min_px)[0]})
              for edge_max in (0.5, 0.6, 0.7, 0.8)
              for p_min in (0.95, 0.98, 0.99, 0.995, 0.998, 0.999)
              for margin_min in (0.9, 0.95, 0.98, 0.99, 0.995)
              if margin_min <= p_min]
    for min_px, side_min, edge_max, p_min, margin_min in combos:
        g = dict(OPEN, side_min=side_min, min_px=min_px, ink_min=ink_min, peak_min=peak_min,
                 edge_max=edge_max, p_min=p_min, margin_min=margin_min)
        ans = decisions(va, pv, g)
        cover, wrong, given, real = score(va, ans)
        _, wrong_near, given_near, _ = score(va_near, ans[near])
        rate = wrong / max(given, 1)
        if fallback is None or (rate, -cover) < (fallback[0], -fallback[1]):
            fallback = (rate, cover, wrong, given, g)
        if (wrong_near <= 0.001 * max(given_near, 1) and rate <= 0.001
                and (best is None or cover > best[0])):
            best = (cover, wrong, given, g)
    if best is None:
        print(f"NO GATES MEET ONE IN A THOUSAND; the strictest found: {fallback[0]:.4f} wrong a given answer")
        best = fallback[1:]
    cover, wrong, given, g = best
    gates = {"side_min": g["side_min"], "ink_floor": OPEN["ink_floor"], "ink_min": ink_min,
             "peak_min": peak_min, "edge_max": g["edge_max"], "min_px": g["min_px"], "p_min": g["p_min"],
             "margin_min": g["margin_min"]}
    print("gates: " + json.dumps(gates))
    print(f"held-out: digits 1-9 read right {cover:.3f}; confident wrong {wrong} of {given} answers given")
    ans = decisions(va, pv, gates)
    for lo, hi in ((0.8, 1.2), (1.2, 1.6), (1.6, 2.2), (2.2, 3.0), (3.0, 4.5), (4.5, 6.0)):
        m = (va["s"] >= lo) & (va["s"] < hi) & (va["kind"] == "digit") & (va["label"] >= 1)
        given_m = (ans >= 0) & m
        print(f"  {lo}-{hi} px/unit: read right {np.mean(ans[m] == va['label'][m]):.3f}, "
              f"wrong {np.sum(given_m & (ans != va['label']))}, refused {np.mean(ans[m] < 0):.3f}  (n={m.sum()})")
    for kind in ("blank", "two", "over"):
        m = va["kind"] == kind
        print(f"  {kind}: given a count {int((ans[m] >= 0).sum())} of {m.sum()}"
              + (f", {int((ans[m] == va['digit'][m]).sum())} of them the figure itself" if kind == "over" else ""))
    zero = (va["kind"] == "digit") & (va["label"] == 0)
    print(f"  written 0: given a count {int((ans[zero] >= 0).sum())} of {zero.sum()}")

    if args.check:
        return 0
    payload = {}
    for i, (w, b) in enumerate(layers):
        payload[f"w{i}"], payload[f"b{i}"] = w, b
    for k, v in gates.items():
        payload[f"gate_{k}"] = np.float64(v)
    payload["about"] = np.array(json.dumps({
        "trained_on": "MNIST (huggingface.co/datasets/ylecun/mnist, MIT), train split less its last 6000",
        "script": "cardreader/tools/train_digits.py", "seed": SEED, "examples": int(len(Y)),
        "held_out_read_right_1_9": round(float(cover), 4), "held_out_confident_wrong": int(wrong),
        "held_out_answers": int(given), "raw_accuracy": round(float(raw), 4)}))
    np.savez_compressed(args.out, **payload)
    print(f"wrote {args.out} ({args.out.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
