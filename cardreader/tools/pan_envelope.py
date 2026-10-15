"""How long a row the duck reads by turning its head along it: cards, looks and seconds.

    python3 cardreader/tools/pan_envelope.py               # rails at 35, 45, 60 cm and the floor
    python3 cardreader/tools/pan_envelope.py --most 16     # try rows up to 16 cards

A row of N cards, Start, N-2 others (a Slow under the first Walk forward; the deck's actions in
turn, so a long row repeats cards) and End, is put in front of the duck's camera (`tests/scenes.py`,
simulated, turned the way the head turns), and `runner.scan` reads it through a duck that holds its
head where it was sent: the scan `watch` runs, with its own turns, settle time and limits. Two
places for the duck: facing the row's middle, and facing it with Start a little left of middle.
Soft (blur 1 px) and sharp (0.6 px). A row counts as read when the joined program is the row's,
complete. The longest row is the longest read in every place and both blurs, with every shorter
row read too.

Seconds are what the scan waits for the head (`runner.SETTLE_HEAD` a turn, and once more to
look back) plus reading each picture, measured here (the duck's own processor is slower), and do
not include drawing the simulated pictures.
"""

from __future__ import annotations

import argparse
import math
import pathlib
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent / "tests"))

import scenes  # noqa: E402
from helpers import DECK, row_at  # noqa: E402

from duckcards import pan, runner  # noqa: E402
from duckcards.layout import arrange  # noqa: E402
from duckcards.program import read  # noqa: E402
from duckcards.see import see  # noqa: E402

MIDDLE = ["greet", "walk_forward", "turn_left", "kick_right", "walk_backward", "turn_right", "sit_or_stand",
          "roll", "peck_ground", "chirp", "kick_left", "coo", "stop", "alarm"]
SETTINGS = [("rail 35 cm", "rail", 350, False), ("rail 45 cm", "rail", 450, False),
            ("rail 60 cm", "rail", 600, False), ("floor 32 cm, near side", "floor", 320, False),
            ("floor 26 cm, far side, --upscale", "floor", 260, True)]


def row_of(n: int):
    codes = ["start"] + [MIDDLE[i % len(MIDDLE)] for i in range(n - 2)] + ["end"]
    unders = {codes.index("walk_forward"): ["slow"]} if "walk_forward" in codes else {}
    return codes, unders


class Duck:
    """Holds the head where it was sent; pictures the row from there."""

    REST = {"neck_pitch": 0.0, "head_pitch": 0.0, "head_yaw": 0.0, "head_roll": 0.0}

    def __init__(self, picture, joints, upscale):
        self.picture, self.upscale = picture, upscale
        self.looking = {**self.REST, **joints}       # what robot.look answers
        self.joints = dict(self.looking)
        self.seconds = 0.0          # reading pictures, not drawing them

    def call(self, method, params=None):
        if method == "robot.look":
            self.joints = dict(self.looking)
            return {"head": dict(self.looking), "clamped": False}
        return {}

    def notify(self, method, params=None):
        if method == "robot.head":
            self.joints = {"neck_pitch": 0.0, "head_pitch": 0.0, "head_yaw": 0.0, "head_roll": 0.0, **params}

    def take(self):
        img = self.picture(math.degrees(self.joints["head_yaw"]))
        t0 = time.perf_counter()
        if self.upscale:
            import cv2
            img = cv2.resize(img, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)
        seen = see(img, DECK).seen
        self.seconds += time.perf_counter() - t0
        return seen, (img.shape[1], img.shape[0])


def attempt(kind, distance, far_side, upscale, n, offset_mm, blur):
    codes, unders = row_of(n)
    cards = [(DECK.by_code(c).tag, DECK.by_code(c).category,
              [(DECK.by_code(u).tag, DECK.by_code(u).category) for u in unders.get(i, ())]) for i, c in enumerate(codes)]
    if kind == "rail":
        def picture(yaw):
            return scenes.rail(cards, distance, x_mm=offset_mm, yaw_deg=yaw, blur=blur)
        point, joints = None, {}
    else:
        pitch = math.degrees(math.atan2(scenes.HEAD_MM, distance))

        def picture(yaw):
            return scenes.floor(cards, distance, pitch, far_side=far_side, x_mm=offset_mm, yaw_deg=yaw, blur=blur)
        point, joints = runner.FLOOR_AT, {"head_pitch": math.radians(pitch)}
    duck = Duck(picture, joints, upscale)
    gaze = runner.Gaze(duck, point)
    gaze.aim(0.0)
    waited = []
    seen, size = duck.take()
    first = pan.Look(seen=seen, yaw=gaze.yaw, size=size)
    joined = runner.scan(first, arrange(seen), gaze, duck.take, sleep=waited.append, say=lambda s: None,
                         clock=lambda: 0.0)
    program = read(joined, DECK)
    want = read(arrange(row_at(codes, width=40, gap=4, unders=unders)), DECK)     # the row, placed by hand
    right = program.complete and program.words == want.words
    yaws = [abs(math.degrees(look.yaw)) for look in joined.looks]
    return right, len(joined.looks), max(yaws), sum(waited) + duck.seconds


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--most", type=int, default=14, help="the longest row to try (default 14)")
    args = p.parse_args()
    print(f"settle {runner.SETTLE_HEAD} s a turn; at most {runner.MOST_LOOKS} looks and "
          f"{math.degrees(runner.YAW_MOST):.0f} degrees each way; rows of 3 cards and fewer are not tried\n")
    print(f"{'how the row is shown':34s} {'':5s} {'facing':10s} {'cards':>5s}  {'looks':>5s}  {'turned':>6s}  "
          f"{'seconds':>7s}   first miss")
    for name, kind, distance, far in SETTINGS:
        for blur, soft in ((1.0, "soft"), (0.6, "sharp")):
            # the duck facing the middle of the row, and facing it with Start a little left of the
            # middle (right of it from the far side, where the row reads right to left)
            for where in ("middle", "Start left"):
                best, detail, miss = 3, (1, 0.0, 0.0), None
                for n in range(4, args.most + 1):
                    start_left = (n - 1) / 2 * (scenes.W_MM + 8) - 0.18 * distance
                    offset = 0.0 if where == "middle" else (-start_left if far else start_left)
                    ok, looks, turned, secs = attempt(kind, distance, far, far, n, offset, blur)
                    if ok and best == n - 1:
                        best, detail = n, (looks, turned, secs)
                    elif not ok and miss is None:
                        miss = f"{n} cards ({looks} looks)"
                    if miss and n >= best + 2:
                        break
                looks, turned, secs = detail
                print(f"{name:34s} {soft:5s} {where:10s} {best:5d}  {looks:5d}  {turned:5.0f}°  {secs:7.1f}   "
                      f"{miss or '-'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
