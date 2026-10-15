"""How well the duck reads the number on Repeat: right, wrong and refused, by distance.

    python3 cardreader/tools/digits_envelope.py                      # the tests' MNIST digits
    python3 cardreader/tools/digits_envelope.py --mnist DIR --per 15 # more of MNIST's test split

A Repeat card held up (`tests/scenes.py`, the duck's camera simulated), a digit from MNIST's test
split written in its box (never seen in training), at 15 to 50 cm, soft (blur 1 px) and sharp
(0.6 px), turned up to 30 degrees and rolled a little, then read through `see` exactly as `watch`
reads it. The same again with the picture shrunk to 0.41 of its size, which is what duck-sim's
camera delivers. "Refused" includes a card whose code was not found at all (counted apart).
Digits 1 to 9 only: those are the counts a Repeat can carry.
"""

from __future__ import annotations

import argparse
import io
import pathlib
import sys
import time

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent / "tests"))

DISTANCES = (150, 200, 250, 300, 400, 500)
POSES = ((0, 0), (15, -8), (30, 6), (-20, 12), (-30, -4), (10, 20))     # (yaw, roll) degrees, in turn


def digits_from(mnist: pathlib.Path | None, per: int):
    if mnist is None:
        z = np.load(HERE.parent / "tests" / "mnist_test_digits.npz")
        x, y = z["x"], z["y"]
    else:
        import pyarrow.parquet as pq
        from PIL import Image
        t = pq.read_table(mnist / "test-00000-of-00001.parquet")
        x = np.stack([np.asarray(Image.open(io.BytesIO(d["bytes"])).convert("L")) for d in t.column("image").to_pylist()])
        y = np.asarray(t.column("label").to_pylist(), np.uint8)
    idx = np.concatenate([np.nonzero(y == d)[0][:per] for d in range(1, 10)])
    return x[idx], y[idx]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mnist", type=pathlib.Path, help="MNIST's parquet directory; default the tests' fixture")
    ap.add_argument("--per", type=int, default=12, help="digits of each figure 1..9")
    args = ap.parse_args()

    import cv2
    import scenes
    from duckcards import digits
    from duckcards.cards import Deck
    from duckcards.see import see

    deck = Deck.load()
    xs, ys = digits_from(args.mnist, args.per)
    times = []
    real_read = digits.read

    def timed(gray, corners):
        t0 = time.perf_counter()
        r = real_read(gray, corners)
        times.append(time.perf_counter() - t0)
        return r

    digits.read = timed
    print(f"{len(ys)} digits, 1 to 9, from MNIST's test split\n")
    print("| camera | distance | soft: right / wrong / refused (no code) | sharp: right / wrong / refused (no code) |")
    print("|---|---|---|---|")
    totals = {}
    for res in (1.0, 0.41):
        for dist in DISTANCES:
            cells = []
            for blur in (1.0, 0.6):
                right = wrong = refused = lost = 0
                for k, (x, y) in enumerate(zip(xs, ys)):
                    yaw, roll = POSES[k % len(POSES)]
                    img = scenes.held(102, "control", dist, yaw_deg=yaw, roll_deg=roll, blur=blur, seed=k, write=x)
                    if res != 1.0:
                        img = cv2.resize(img, None, fx=res, fy=res, interpolation=cv2.INTER_AREA)
                    reps = [s for s in see(img, deck).seen if s.card.code == "repeat"]
                    if not reps:
                        lost += 1
                        refused += 1
                        continue
                    c = reps[0].count
                    if c is None:
                        refused += 1
                    elif c == int(y):
                        right += 1
                    else:
                        wrong += 1
                n = len(ys)
                t = totals.setdefault((res, blur), [0, 0, 0, 0])
                for i, v in enumerate((right, wrong, refused, n)):
                    t[i] += v
                cells.append(f"{100 * right / n:.0f}% / {wrong} / {100 * refused / n:.0f}% ({lost})")
            name = "duck, 720x1280" if res == 1.0 else "sim, 0.41x"
            print(f"| {name} | {dist // 10} cm | {cells[0]} | {cells[1]} |", flush=True)
    print()
    for (res, blur), (right, wrong, refused, n) in totals.items():
        print(f"{'duck' if res == 1.0 else 'sim 0.41x'} blur {blur}: {right} right, {wrong} wrong, {refused} refused of {n}")
    if times:
        t = np.array(times) * 1000
        print(f"\ndigits.read per Repeat card: median {np.median(t):.2f} ms, 95% {np.percentile(t, 95):.2f} ms, n={len(t)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
