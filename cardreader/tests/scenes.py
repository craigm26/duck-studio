"""Pictures of cards as the duck's head camera would take them, for the tests.

THE CAMERA IS POLLEN'S. `mediad/src/camera.rs` (pollen-robotics/microduck): an
IMX219 behind a ~3.05 mm lens, the full ~62° width read out and delivered at
1280x720, `fx = (W/2) / tan(62°/2)` ≈ 1065 px. The camera is mounted a quarter
turn off, and `/frame` and the frame socket hand back the picture upright, so
the picture a reader gets is 720 wide and 1280 tall: about 37° across and 62°
up and down. The head is about 24 cm off the floor.

THE CARDS ARE DRAWN FROM THE CARD'S OWN RULES. Every card here is a white card
of the right proportions, its category's band, some clutter where the picture
and words go, and the code in exactly the place `cards.py` says it is, drawn
from the deck's own tag36h11 table. Nothing here is a photograph, so these
tests say what the geometry allows, not what a classroom's light will do.

REPEAT HAS ITS BOX. The Repeat card is drawn with its name, the box a child
writes the number in and the word "times" where the cut sheet puts them
(`cards.WRITE_EDGE`, measured), and `write=` puts a handwritten figure in the
box. Every other card is drawn exactly as before, pixel for pixel, because the
shared vectors hold the library's answers to pictures of them.

THE HEAD TURNS ABOUT THE NECK. `yaw_deg` turns the camera the way robotd's
head_yaw does (more is left): about the picture's own vertical, through a point
55.6 mm behind the lens, which is where Pollen's alpha head carries the camera
(the head_camera site in `robot_walk.xml` at 648bf22, in front of the head_yaw
axis). A camera that is not turned takes exactly the pictures it took before.
"""

from __future__ import annotations

import math
import pathlib
import sys

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from duckcards.cards import WRITE_BOX, WRITE_EDGE  # noqa: E402

W_MM, H_MM = 63.5, 88.9
FRAME_W, FRAME_H = 720, 1280
F = (1280 / 2) / math.tan(math.radians(31))     # ≈ 1065 px
HEAD_MM = 240.0
NECK_MM = 55.6          # the head_yaw axis, behind the lens

BAND = {"walk": (201, 100, 42), "speed": (122, 119, 11), "look": (194, 68, 112), "trick": (0, 149, 255),
        "sound": (62, 110, 27), "control": (68, 60, 60), "when": (48, 194, 242), "yours": (250, 250, 250)}

_TAGS: dict[int, list[str]] = {}


def tag_rows(tag: int) -> list[str]:
    if not _TAGS:
        for line in (HERE / "tag36h11.txt").read_text().splitlines():
            parts = line.split()
            if parts and not parts[0].startswith("#"):
                _TAGS[int(parts[0])] = parts[1:]
    return _TAGS[tag]


REPEAT = 102
BOX_BORDER = 0.42       # card units: one CSS pixel, as the cut sheet prints it
BOX_RADIUS = 1.4
INK = 29                # #1d1d1f, the cards' ink
MARKER = 40             # a child's marker on the card


def _rounded_rect(scale: float, shape, edge, radius: float) -> np.ndarray:
    """How much of each pixel a rounded rectangle covers, 0..1, from its signed distance: `edge`
    and `radius` in card units, pixels `scale` to a unit, a pixel's centre at its index + 0.5."""
    h, w = shape
    ys = (np.arange(h) + 0.5) / scale
    xs = (np.arange(w) + 0.5) / scale
    left, top, right, bottom = edge
    cx, cy = (left + right) / 2, (top + bottom) / 2
    qx = np.abs(xs[None, :] - cx) - ((right - left) / 2 - radius)
    qy = np.abs(ys[:, None] - cy) - ((bottom - top) / 2 - radius)
    outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
    inside = np.minimum(np.maximum(qx, qy), 0)
    d = (outside + inside - radius) * scale
    return np.clip(0.5 - d, 0.0, 1.0)


def write_in(img: np.ndarray, scale: float, figure: np.ndarray, fill: float = 0.8, ink: int = MARKER) -> None:
    """Write `figure` (a picture of ink, 0 none to 255 full, MNIST's way round) into Repeat's box:
    its ink fitted to `fill` of the box's height inside the border, at most nine tenths of its
    width, centred."""
    import cv2
    a = np.asarray(figure, np.float32) / 255.0
    rows, cols = np.nonzero(a > 0.1)
    if not len(rows):
        return
    a = a[rows.min():rows.max() + 1, cols.min():cols.max() + 1]
    left, top, right, bottom = WRITE_BOX
    k = min(fill * (bottom - top) / a.shape[0], 0.9 * (right - left) / a.shape[1]) * scale
    cx, cy = (left + right) / 2 * scale, (top + bottom) / 2 * scale
    # OpenCV puts a pixel's centre at its index: figure pixel j to card pixel k*j + t, so that the
    # figure's middle lands on the box's
    m = np.float32([[k, 0, cx - k * (a.shape[1] / 2 - 0.5) - 0.5], [0, k, cy - k * (a.shape[0] / 2 - 0.5) - 0.5]])
    alpha = cv2.warpAffine(a, m, (img.shape[1], img.shape[0]), flags=cv2.INTER_LINEAR,
                           borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    img[:] = np.clip(img * (1 - alpha) + ink * alpha, 0, 255).round().astype(np.uint8)


def card_image(tag: int, category: str, scale: float = 6.0, seed: int = 0,
               write: np.ndarray | None = None) -> np.ndarray:
    """One card, `scale` pixels per hundredth of its width, grey. `write`: a figure written in the
    Repeat card's box (see `write_in`); only Repeat has a box."""
    import cv2
    w, h = int(100 * scale), int(140 * scale)
    img = np.full((h, w), 246, np.uint8)
    rng = np.random.default_rng(seed + tag)
    b = BAND.get(category, (128, 128, 128))
    grey = int(0.114 * b[0] + 0.587 * b[1] + 0.299 * b[2])
    img[: int(13 * scale), :] = grey
    cv2.circle(img, (int(50 * scale), int(45 * scale)), int(26 * scale), 225, -1)
    # the picture: a few strokes; the name and code word: bars
    for _ in range(4):
        p = rng.integers(int(30 * scale), int(70 * scale), size=4)
        cv2.line(img, (int(p[0]), int(p[1] - 10 * scale)), (int(p[2]), int(p[3] - 10 * scale)), 60, max(2, int(2.2 * scale)))
    if tag == REPEAT:
        # Repeat's name sits higher, to leave room for the line with the box (the cut sheet's
        # own places, measured with the box): "Repeat", the box, "times", then the code word.
        cv2.rectangle(img, (int(6 * scale), int(75.5 * scale)), (int(40.5 * scale), int(84 * scale)), 30, -1)
        ring = (_rounded_rect(scale, img.shape, WRITE_EDGE, BOX_RADIUS)
                - _rounded_rect(scale, img.shape, tuple(e + s * BOX_BORDER for e, s in zip(WRITE_EDGE, (1, 1, -1, -1))),
                                BOX_RADIUS - BOX_BORDER))
        img[:] = np.clip(img * (1 - ring) + INK * ring, 0, 255).round().astype(np.uint8)
        cv2.rectangle(img, (int(20 * scale), int(87.5 * scale)), (int(33.7 * scale), int(93.5 * scale)), 93, -1)
        cv2.rectangle(img, (int(6 * scale), int(98 * scale)), (int(31 * scale), int(101.5 * scale)), 120, -1)
        if write is not None:
            write_in(img, scale, write)
    else:
        cv2.rectangle(img, (int(6 * scale), int(80 * scale)), (int(70 * scale), int(90 * scale)), 30, -1)
        cv2.rectangle(img, (int(6 * scale), int(94 * scale)), (int(40 * scale), int(98 * scale)), 120, -1)
        cv2.rectangle(img, (int(6 * scale), int(120 * scale)), (int(24 * scale), int(126 * scale)), 200, -1)
    # the code: its svg box is 71.5..95.5 across, 106.9..130.9 down, ten cells each way
    x0, y0, cell = 71.5 * scale, 106.9 * scale, 2.4 * scale
    grid = np.full((10, 10), 255, np.uint8)
    grid[1:9, 1:9] = 0
    for r, row in enumerate(tag_rows(tag)):
        for c, bit in enumerate(row):
            grid[2 + r, 2 + c] = 255 if bit == "1" else 0
    for r in range(10):
        for c in range(10):
            ys, xs = int(round(y0 + r * cell)), int(round(x0 + c * cell))
            ye, xe = int(round(y0 + (r + 1) * cell)), int(round(x0 + (c + 1) * cell))
            img[ys:ye, xs:xe] = 18 if grid[r, c] == 0 else 250
    cv2.rectangle(img, (0, 0), (w - 1, h - 1), 200, max(1, int(scale / 2)))
    return img


class Camera:
    """A pinhole looking down +z, x right, y down, turned `pitch` degrees down and set `height`
    mm above the floor (the floor is y = +height before the turn), and then turned `yaw` degrees
    to the left about its own vertical through a point `neck_mm` behind the lens."""

    def __init__(self, pitch_deg: float = 0.0, height_mm: float = HEAD_MM, yaw_deg: float = 0.0,
                 neck_mm: float = NECK_MM):
        self.pitch = math.radians(pitch_deg)
        self.height = height_mm
        self.yaw = math.radians(yaw_deg)
        self.neck = neck_mm

    def project(self, pts: np.ndarray) -> np.ndarray:
        """World points (n, 3), mm, in a frame level with the floor; pixels (n, 2)."""
        c, s = math.cos(self.pitch), math.sin(self.pitch)
        # world y down; pitching the camera down by `pitch` is turning the world up about x
        x = pts[:, 0]
        y = c * pts[:, 1] - s * pts[:, 2]
        z = s * pts[:, 1] + c * pts[:, 2]
        if self.yaw:
            # the lens goes round the neck: points from the neck, turned the other way, and back
            cy, sy = math.cos(self.yaw), math.sin(self.yaw)
            ahead = z + self.neck
            x, z = cy * x + sy * ahead, -sy * x + cy * ahead - self.neck
        if np.any(z <= 1):
            raise ValueError("behind the camera")
        return np.stack([F * x / z + FRAME_W / 2, F * y / z + FRAME_H / 2], axis=1)


def card_corners(centre, right, down) -> np.ndarray:
    """A card's four corners in the world: top-left, top-right, bottom-right, bottom-left."""
    c, r, d = (np.asarray(v, float) for v in (centre, right, down))
    r = r / np.linalg.norm(r) * W_MM / 2
    d = d / np.linalg.norm(d) * H_MM / 2
    return np.array([c - r - d, c + r - d, c + r + d, c - r + d])


def background(seed: int = 0, level: int = 150) -> np.ndarray:
    import cv2
    rng = np.random.default_rng(seed)
    bg = rng.normal(level, 10, (FRAME_H // 8, FRAME_W // 8)).astype(np.float32)
    bg = cv2.resize(bg, (FRAME_W, FRAME_H), interpolation=cv2.INTER_CUBIC)
    return np.clip(bg, 0, 255).astype(np.float32)


def render(cards, camera: Camera, seed: int = 0, blur: float = 0.9, noise: float = 4.0,
           contrast: float = 0.85, bg_level: int = 150) -> np.ndarray:
    """`cards`: (tag, category, centre, right, down) in the world, mm, and for a Repeat a sixth,
    the figure written in its box (`card_image`'s `write`). Returns the grey frame."""
    import cv2
    frame = background(seed, bg_level)
    for tag, category, centre, right, down, *write in cards:
        tex = card_image(tag, category, seed=seed, write=write[0] if write else None).astype(np.float32)
        th, tw = tex.shape
        src = np.float32([[0, 0], [tw, 0], [tw, th], [0, th]])
        dst = camera.project(card_corners(centre, right, down)).astype(np.float32)
        H = cv2.getPerspectiveTransform(src, dst)
        warped = cv2.warpPerspective(tex, H, (FRAME_W, FRAME_H), flags=cv2.INTER_AREA,
                                     borderMode=cv2.BORDER_CONSTANT, borderValue=-1)
        mask = cv2.warpPerspective(np.ones_like(tex), H, (FRAME_W, FRAME_H), flags=cv2.INTER_LINEAR)
        frame = frame * (1 - mask) + np.where(warped < 0, 0, warped) * mask
    frame = 128 + (frame - 128) * contrast
    if blur > 0:
        frame = cv2.GaussianBlur(frame, (0, 0), blur)
    rng = np.random.default_rng(seed + 99)
    frame = frame + rng.normal(0, noise, frame.shape)
    return np.clip(frame, 0, 255).astype(np.uint8)


# ---------------------------------------------------------------- the three ways
def held(tag, category, distance_mm, yaw_deg=0.0, roll_deg=0.0, x_mm=0.0, y_mm=0.0, write=None, **kw):
    """One card held up facing the duck, its centre `distance_mm` in front of the lens. `write`:
    the figure written in a Repeat card's box."""
    yaw, roll = math.radians(yaw_deg), math.radians(roll_deg)
    right = np.array([math.cos(yaw) * math.cos(roll), math.sin(roll), math.sin(yaw)])
    down = np.array([-math.cos(yaw) * math.sin(roll), math.cos(roll), 0.0])
    return render([(tag, category, (x_mm, y_mm, distance_mm), right, down, write)], Camera(0), **kw)


def _in_sight(placed, camera: Camera):
    """The cards some part of which is in front of the camera and inside the picture: a long row
    seen with the head turned runs out of the picture, and round behind a turned camera."""
    out = []
    for card in placed:
        tag, cat, centre, right, down = card[:5]
        corners = card_corners(centre, right, down)
        try:
            p = camera.project(corners)
        except ValueError:
            continue
        if p[:, 0].max() >= 0 and p[:, 0].min() < FRAME_W and p[:, 1].max() >= 0 and p[:, 1].min() < FRAME_H:
            out.append(card)
    return out


def rail(cards, distance_mm, gap_mm=8.0, y_mm=0.0, yaw_deg=0.0, x_mm=0.0, **kw):
    """A row standing in a rail facing the duck. `cards`: [(tag, category, [(tag, category)...])]
    where the inner list is what stands under that card. `x_mm` moves the row's middle to the
    right; `yaw_deg` turns the head (more is left)."""
    n = len(cards)
    step = W_MM + gap_mm
    placed = []
    for i, (tag, cat, under) in enumerate(cards):
        x = x_mm + (i - (n - 1) / 2) * step
        placed.append((tag, cat, (x, y_mm, distance_mm), (1, 0, 0), (0, 1, 0)))
        for j, (ut, uc) in enumerate(under):
            placed.append((ut, uc, (x + 3, y_mm + (j + 1) * (H_MM + 6), distance_mm), (1, 0, 0), (0, 1, 0)))
    if not yaw_deg:
        return render(placed, Camera(0), **kw)
    camera = Camera(0, yaw_deg=yaw_deg)
    return render(_in_sight(placed, camera), camera, **kw)


def floor(cards, distance_mm, pitch_deg, far_side=False, gap_mm=8.0, height_mm=HEAD_MM, yaw_deg=0.0,
          x_mm=0.0, **kw):
    """A row lying on the floor across the duck's view, its middle `distance_mm` ahead and `x_mm`
    to the right; `yaw_deg` turns the head (more is left) about its own vertical, pitched down.

    From the near side the cards' tops point away from the duck; from the far side (a class
    laid the row out facing themselves, across from the duck) they point at it, and the row reads
    right to left in the picture."""
    n = len(cards)
    step = W_MM + gap_mm
    sign = -1 if far_side else 1
    right = np.array([sign, 0.0, 0.0])
    down = np.array([0.0, 0.0, -sign])          # a card's down points at the duck from the near side
    placed = []
    for i, (tag, cat, under) in enumerate(cards):
        x = x_mm + sign * (i - (n - 1) / 2) * step
        z = distance_mm
        placed.append((tag, cat, (x, height_mm, z), right, down))
        for j, (ut, uc) in enumerate(under):
            placed.append((ut, uc, (x + sign * 3, height_mm, z - sign * (j + 1) * (H_MM + 6)), right, down))
    if not yaw_deg:
        return render(placed, Camera(pitch_deg, height_mm), **kw)
    camera = Camera(pitch_deg, height_mm, yaw_deg=yaw_deg)
    return render(_in_sight(placed, camera), camera, **kw)
