"""The number a child wrote on Repeat, read off the duck's own camera.

WHERE THE BOX IS. The code's square says where the card is, but the box is four squares away, and a
homography from four corners, carried that far, misses it: on the test camera by a median of about a
card unit and by up to six at a slant, against a box 11 units wide inside. So the corners only say
where to look. The box's own printed border is found in a patch around that guess (a rounded
rectangle of known size, scored by its four sides as thin dark lines), and the number is read from
inside what was found. A Repeat whose border cannot be found is not read.

WHAT IS READ. The ink inside the border, less a margin that grows as the box gets smaller in the
picture, so the border's blur is not read as a stroke. Blank or written is decided from how much ink
there is. Written ink is put into MNIST's shape (its extent fitted to 20 by 20, centred by its mass in
28 by 28) and given to a small network (784, 256, 128, 11; float16, 430 KB) that answers 0 to 9, or
"something else" (two figures, a figure too big for the box). `tools/train_digits.py` trains it on
MNIST written into a drawn box and photographed small and soft, through this module's own `prepare`,
so what it learned from is what it is shown here.

A WRONG NUMBER IS WORSE THAN A QUESTION. A Repeat read as 4 that says 3 makes the duck do the wrong
thing and say it did the right one; a Repeat it cannot read makes the row wait and the duck ask. So a
count is given only when the network is sure and nothing else comes close (top answer at least
0.995, and 0.995 ahead of the next), when the figure does not run into the border (a figure cut
short can be another figure: a 7 without its top is a 1), and when the box is big enough in the
picture to be read (1.4 picture pixels a card unit, its inside 16 by 11 pixels: about 48 cm on the
duck's camera, 20 cm on duck-sim's). The thresholds were chosen on digits the network never trained
on, for at most one confident mistake in a thousand, and travel with the weights in `digits.npz`.
0 is never a count.

NUMPY ONLY. This runs on the duck beside the code reader: no OpenCV, no network, about a
millisecond a card.
"""

from __future__ import annotations

import math
import pathlib
from dataclasses import dataclass, field

import numpy as np

from .cards import REPEAT_MOST, SQUARE, WRITE_BOX, WRITE_EDGE

HERE = pathlib.Path(__file__).resolve().parent
WEIGHTS = HERE / "digits.npz"

PX = 4.0                    # the canonical patch: pixels per card unit
LOOK = 6.5                  # how far from where the corners put the box to look for it, card units
SCALES = (0.92, 0.96, 1.0, 1.04, 1.08)      # and how much bigger or smaller it may turn out
BORDER = WRITE_BOX[0] - WRITE_EDGE[0]       # 0.4: the printed border, card units
RADIUS = 1.4                # its corners' rounding, card units
SIDE, FIT = 28, 20          # MNIST's shape: a 28 square, the figure fitted to 20
OTHER = 10                  # the network's answer for "not one figure"

# The pictures the AprilTag library reports put a pixel's centre at its index plus a half (measured
# against the test camera's own geometry: +0.5 on both axes); this module samples at the index.
CORNER_OFFSET = 0.5


@dataclass
class Prepared:
    """What the picture says about the box, before the network: everything `read` decides on."""
    found: bool = False             # the printed border was found
    px_per_unit: float = 0.0        # how big the box is in the picture: picture pixels per card unit
    written: bool = False           # there is ink in the box
    ink: float = 0.0                # how much: card units squared of full-dark ink
    peak: float = 0.0               # and the darkest of it, 0..1
    edge: float = 0.0               # how dark the ink is where the read stops, against `peak`
    x: np.ndarray | None = None     # the figure, MNIST's shape, 0..1, when written
    box_score: float = 0.0
    box: "Box | None" = None        # where the border was found, patch pixels
    h: np.ndarray | None = None     # card units to picture pixels, from the code's corners
    why: str = ""


@dataclass
class Reading:
    count: int | None
    why: str            # "read", "blank", "cut", "unsure", "small", "no box", "zero", "other"
    figure: int | None = None       # the network's best answer, 0..9, or None for something else
    p: float = 0.0
    margin: float = 0.0
    prepared: Prepared = field(default_factory=Prepared)


# ---------------------------------------------------------------- geometry
def homography(src, dst) -> np.ndarray:
    """The 3x3 homography taking four points `src` to four points `dst`, solved with both sets
    centred and scaled so the solve is well conditioned."""
    src, dst = np.asarray(src, float), np.asarray(dst, float)

    def norm(p):
        c = p.mean(0)
        s = math.sqrt(2) / max(np.sqrt(((p - c) ** 2).sum(1)).mean(), 1e-9)
        return np.array([[s, 0, -s * c[0]], [0, s, -s * c[1]], [0, 0, 1]])

    ts, td = norm(src), norm(dst)
    a = (np.c_[src, np.ones(4)] @ ts.T)[:, :2]
    b = (np.c_[dst, np.ones(4)] @ td.T)[:, :2]
    rows, rhs = [], []
    for (x, y), (u, v) in zip(a, b):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); rhs.append(u)
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y]); rhs.append(v)
    h = np.linalg.solve(np.array(rows), np.array(rhs))
    hn = np.append(h, 1.0).reshape(3, 3)
    out = np.linalg.inv(td) @ hn @ ts
    return out / out[2, 2]


def card_to_picture(corners) -> np.ndarray:
    """Card units to picture pixels (centres at the index), from the code's four corners in the
    library's order: top right, top left, bottom left, bottom right of the black square."""
    left, top, right, bottom = SQUARE
    square = [(right, top), (left, top), (left, bottom), (right, bottom)]
    return homography(square, np.asarray(corners, float) - CORNER_OFFSET)


def _apply(h: np.ndarray, u: np.ndarray, v: np.ndarray):
    w = h[2, 0] * u + h[2, 1] * v + h[2, 2]
    return (h[0, 0] * u + h[0, 1] * v + h[0, 2]) / w, (h[1, 0] * u + h[1, 1] * v + h[1, 2]) / w, w


def px_per_unit(h: np.ndarray, u: float, v: float) -> float:
    """How many picture pixels one card unit spans at (u, v): the square root of the Jacobian's
    determinant there."""
    e = 1e-3
    x0, y0, _ = _apply(h, np.array([u]), np.array([v]))
    xu, yu, _ = _apply(h, np.array([u + e]), np.array([v]))
    xv, yv, _ = _apply(h, np.array([u]), np.array([v + e]))
    det = ((xu - x0) * (yv - y0) - (xv - x0) * (yu - y0))[0] / (e * e)
    return math.sqrt(abs(det))


def _sample(gray: np.ndarray, xs: np.ndarray, ys: np.ndarray):
    """Bilinear samples of the picture at (xs, ys), and which of them fell inside it."""
    h, w = gray.shape
    inside = (xs >= 0) & (ys >= 0) & (xs <= w - 1) & (ys <= h - 1)
    xs = np.clip(xs, 0, w - 1.001)
    ys = np.clip(ys, 0, h - 1.001)
    x0 = xs.astype(np.intp)
    y0 = ys.astype(np.intp)
    fx = (xs - x0).astype(np.float32)
    fy = (ys - y0).astype(np.float32)
    a = gray[y0, x0].astype(np.float32)
    b = gray[y0, x0 + 1].astype(np.float32)
    c = gray[y0 + 1, x0].astype(np.float32)
    d = gray[y0 + 1, x0 + 1].astype(np.float32)
    return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy, inside


# The patch the box is looked for in: the box's outside edge and LOOK around it, plus half a unit.
_PAD = LOOK + 0.5
PATCH_LEFT, PATCH_TOP = WRITE_EDGE[0] - _PAD, WRITE_EDGE[1] - _PAD
PATCH_W = int(round((WRITE_EDGE[2] - WRITE_EDGE[0] + 2 * _PAD) * PX))
PATCH_H = int(round((WRITE_EDGE[3] - WRITE_EDGE[1] + 2 * _PAD) * PX))


def patch(gray: np.ndarray, h: np.ndarray):
    """The picture around the box, resampled to PX pixels a card unit, and which of its pixels were
    in the picture."""
    js = np.arange(PATCH_W) + 0.5
    is_ = np.arange(PATCH_H) + 0.5
    u = PATCH_LEFT + js[None, :] / PX + 0 * is_[:, None]
    v = PATCH_TOP + is_[:, None] / PX + 0 * js[None, :]
    x, y, w = _apply(h, u, v)
    if np.any(w <= 0):
        return None, None
    values, inside = _sample(gray, x, y)
    return values, inside


# ---------------------------------------------------------------- finding the box
@dataclass
class Box:
    """The box as found in the patch: its outside edge in patch pixels, and how box-like it was."""
    left: float
    top: float
    right: float
    bottom: float
    score: float
    sides: tuple[float, float, float, float]


def _darkness(values: np.ndarray, paper: float) -> np.ndarray:
    return np.clip((paper - values) / max(paper, 1.0), 0.0, 1.0)


def _lines(dark: np.ndarray, axis: int, w: int = int(PX)) -> np.ndarray:
    """How much each pixel looks like a thin dark line across `axis`: its darkness less the mean of
    the darkness `w` pixels to either side. A solid patch of ink scores nothing inside it."""
    pad = [(0, 0), (0, 0)]
    pad[axis] = (w, w)
    p = np.pad(dark, pad, mode="edge")
    n = dark.shape[axis]
    lo = np.take(p, np.arange(0, n), axis=axis)
    hi = np.take(p, np.arange(2 * w, 2 * w + n), axis=axis)
    return dark - 0.5 * (lo + hi)


def _col(u: float) -> int:
    return int(round((u - PATCH_LEFT) * PX - 0.5))


def _row(v: float) -> int:
    return int(round((v - PATCH_TOP) * PX - 0.5))


def find_box(dark: np.ndarray) -> Box:
    """The printed border in the patch: the rounded rectangle of the box's size (give or take
    SCALES) whose four straight sides lie on the darkest thin lines, within LOOK of where the code
    put it. Each side is scored as the mean line strength along it, from running sums, so every
    shift and scale is tried in one go."""
    vert = _lines(dark, axis=1)      # thin vertical lines: the left and right sides
    horz = _lines(dark, axis=0)      # thin horizontal lines: the top and bottom
    cv = np.vstack([np.zeros((1, dark.shape[1])), np.cumsum(vert, axis=0)])
    ch = np.hstack([np.zeros((dark.shape[0], 1)), np.cumsum(horz, axis=1)])
    shifts = np.arange(-int(LOOK * PX), int(LOOK * PX) + 1)
    sy = shifts[:, None]
    sx = shifts[None, :]
    cx = (WRITE_EDGE[0] + WRITE_EDGE[2]) / 2
    cy = (WRITE_EDGE[1] + WRITE_EDGE[3]) / 2
    best = None
    for k in SCALES:
        hw = (WRITE_EDGE[2] - WRITE_EDGE[0]) / 2 * k
        hh = (WRITE_EDGE[3] - WRITE_EDGE[1]) / 2 * k
        # each side's middle line, and the straight run of it between the rounded corners, in
        # patch pixels before shifting
        il, ir = _col(cx - hw + BORDER / 2), _col(cx + hw - BORDER / 2)
        it, ib = _row(cy - hh + BORDER / 2), _row(cy + hh - BORDER / 2)
        ya, yz = _row(cy - hh + RADIUS), _row(cy + hh - RADIUS)
        xa, xz = _col(cx - hw + RADIUS), _col(cx + hw - RADIUS)
        ny, nx = max(yz - ya, 1), max(xz - xa, 1)
        left = (cv[ya + sy + ny, il + sx] - cv[ya + sy, il + sx]) / ny
        right = (cv[ya + sy + ny, ir + sx] - cv[ya + sy, ir + sx]) / ny
        top = (ch[it + sy, xa + sx + nx] - ch[it + sy, xa + sx]) / nx
        bottom = (ch[ib + sy, xa + sx + nx] - ch[ib + sy, xa + sx]) / nx
        # The weakest side counts twice: a box has four sides, a bar or a stroke has one or two.
        sides = np.stack([left, right, top, bottom])
        score = sides.sum(0) + sides.min(0)
        j = np.unravel_index(int(np.argmax(score)), score.shape)
        if best is None or score[j] > best[0]:
            dy, dx = int(shifts[j[0]]), int(shifts[j[1]])
            edge = ((cx - hw - PATCH_LEFT) * PX + dx, (cy - hh - PATCH_TOP) * PX + dy,
                    (cx + hw - PATCH_LEFT) * PX + dx, (cy + hh - PATCH_TOP) * PX + dy)
            best = (float(score[j]), edge, tuple(float(s[j]) for s in sides))
    score, edge, sides = best
    return Box(*edge, score=score, sides=sides)


# ---------------------------------------------------------------- the figure
def _resampler(n_in: int, n_out: int) -> np.ndarray:
    """Rows of weights taking n_in samples to n_out: linear, widened to an average when shrinking."""
    scale = n_in / n_out
    centres = (np.arange(n_out) + 0.5) * scale - 0.5
    support = max(1.0, scale)
    w = np.maximum(0.0, 1.0 - np.abs(np.arange(n_in)[None, :] - centres[:, None]) / support)
    return w / np.maximum(w.sum(1, keepdims=True), 1e-12)


def resize(img: np.ndarray, h: int, w: int) -> np.ndarray:
    return _resampler(img.shape[0], h) @ img @ _resampler(img.shape[1], w).T


def mnist_shape(ink: np.ndarray) -> np.ndarray | None:
    """Ink to MNIST's shape: the figure's extent fitted to FIT by FIT, its mass at the middle of
    SIDE by SIDE, 0..1, flattened."""
    peak = float(ink.max())
    if peak <= 0:
        return None
    rows = np.nonzero(ink.max(1) > 0.2 * peak)[0]
    cols = np.nonzero(ink.max(0) > 0.2 * peak)[0]
    crop = ink[rows[0]:rows[-1] + 1, cols[0]:cols[-1] + 1]
    k = FIT / max(crop.shape)
    h, w = max(1, int(round(crop.shape[0] * k))), max(1, int(round(crop.shape[1] * k)))
    small = np.clip(resize(crop, h, w), 0, None)
    top = float(small.max())
    if top <= 0:
        return None
    small = np.clip(small / top, 0.0, 1.0)
    mass = small.sum()
    my = (small.sum(1) * np.arange(h)).sum() / mass
    mx = (small.sum(0) * np.arange(w)).sum() / mass
    oy = int(round((SIDE - 1) / 2 - my))
    ox = int(round((SIDE - 1) / 2 - mx))
    oy = min(max(oy, 0), SIDE - h)
    ox = min(max(ox, 0), SIDE - w)
    out = np.zeros((SIDE, SIDE), np.float32)
    out[oy:oy + h, ox:ox + w] = small
    return out.reshape(-1)


def inset_units(px: float) -> float:
    """How far inside the border's inner edge the ink is read from, card units: enough to clear the
    border's blur, which in card units grows as the box shrinks in the picture."""
    return min(max(0.25 + 1.0 / max(px, 1e-6), 0.45), 1.3)


def prepare(gray: np.ndarray, corners, gates: dict | None = None) -> Prepared:
    """Everything up to the network: find the box near where the code puts it, decide blank or
    written, and put written ink into MNIST's shape."""
    g = dict(_gates() if gates is None else gates)
    out = Prepared()
    try:
        h = card_to_picture(corners)
    except np.linalg.LinAlgError:
        out.why = "no box"
        return out
    out.h = h
    values, inside = patch(gray, h)
    if values is None or inside.mean() < 0.98:
        out.why = "no box"
        return out
    paper = float(np.percentile(values, 90))
    dark = _darkness(values, paper)
    box = find_box(dark)
    out.box, out.box_score = box, box.score
    if min(box.sides) < g["side_min"]:
        out.why = "no box"
        return out
    out.found = True
    k = (box.right - box.left) / ((WRITE_EDGE[2] - WRITE_EDGE[0]) * PX)
    cu = PATCH_LEFT + (box.left + box.right) / 2 / PX
    cv = PATCH_TOP + (box.top + box.bottom) / 2 / PX
    out.px_per_unit = px_per_unit(h, cu, cv) * k
    # Inside the border, less the inset. The box's edges are in pixel-edge coordinates (pixel i
    # spans i to i + 1); a pixel is read when its centre is inside.
    m = (BORDER * k + inset_units(out.px_per_unit)) * PX
    i0, i1 = int(math.ceil(box.top + m - 0.5)), int(math.floor(box.bottom - m - 0.5)) + 1
    j0, j1 = int(math.ceil(box.left + m - 0.5)), int(math.floor(box.right - m - 0.5)) + 1
    if i1 - i0 < 4 or j1 - j0 < 4:
        out.why = "small"
        return out
    inner = dark[i0:i1, j0:j1]
    # paper's own noise, from the pixels around the box that are paper
    paper_px = dark[dark < np.percentile(dark, 60)]
    noise = 1.4826 * float(np.median(np.abs(paper_px - np.median(paper_px)))) if paper_px.size else 0.0
    floor = max(g["ink_floor"], 3.0 * noise)
    ink = np.clip(inner - floor, 0.0, None)
    out.ink = float(ink.sum()) / (PX * PX)
    out.peak = float(ink.max())
    # A figure that runs into the border goes on under it, out of sight, and a 7 cut short is a 1:
    # the three darkest pixels on the edge of what is read, against the darkest of all.
    rim = np.concatenate([ink[0], ink[-1], ink[1:-1, 0], ink[1:-1, -1]])
    out.edge = float(np.sort(rim)[-3:].mean()) / out.peak if out.peak > 0 else 0.0
    out.written = out.ink >= g["ink_min"] and out.peak >= g["peak_min"]
    if not out.written:
        out.why = "blank"
        return out
    out.x = mnist_shape(ink)
    if out.x is None:
        out.written, out.why = False, "blank"
    return out


# ---------------------------------------------------------------- the network
_model = None


class _Model:
    def __init__(self, path: pathlib.Path = WEIGHTS):
        with np.load(path, allow_pickle=False) as z:
            self.layers = []
            i = 0
            while f"w{i}" in z:
                self.layers.append((z[f"w{i}"].astype(np.float32), z[f"b{i}"].astype(np.float32)))
                i += 1
            self.gates = {k[5:]: float(z[k]) for k in z.files if k.startswith("gate_")}

    def probs(self, x: np.ndarray) -> np.ndarray:
        a = np.asarray(x, np.float32).reshape(-1, SIDE * SIDE)
        for i, (w, b) in enumerate(self.layers):
            a = a @ w + b
            if i < len(self.layers) - 1:
                np.maximum(a, 0, out=a)
        a = a - a.max(1, keepdims=True)
        e = np.exp(a)
        return e / e.sum(1, keepdims=True)


def model() -> _Model:
    global _model
    if _model is None:
        _model = _Model()
    return _model


def _gates() -> dict:
    return model().gates


def read(gray: np.ndarray, corners) -> Reading:
    """The number on a Repeat card whose code was found at `corners`, or None and why not."""
    g = _gates()
    prep = prepare(gray, corners, g)
    if not prep.found:
        return Reading(None, "no box", prepared=prep)
    if prep.px_per_unit < g["min_px"]:
        return Reading(None, "small", prepared=prep)
    if not prep.written:
        return Reading(None, "blank", prepared=prep)
    if prep.edge > g["edge_max"]:
        return Reading(None, "cut", prepared=prep)
    p = model().probs(prep.x)[0]
    order = np.argsort(p)[::-1]
    top, second = int(order[0]), int(order[1])
    figure = None if top == OTHER else top
    r = Reading(None, "unsure", figure=figure, p=float(p[top]), margin=float(p[top] - p[second]), prepared=prep)
    if r.p < g["p_min"] or r.margin < g["margin_min"]:
        return r
    if figure is None:
        r.why = "other"
    elif not 1 <= figure <= REPEAT_MOST:
        r.why = "zero"
    else:
        r.count, r.why = figure, "read"
    return r


def count(gray: np.ndarray, corners) -> int | None:
    return read(gray, corners).count
