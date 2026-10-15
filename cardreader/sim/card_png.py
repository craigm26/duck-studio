"""A Duck Card as a picture, for a duck-sim scene: drawn the way the cards print it.

    python3 cardreader/sim/card_png.py kick_right kick_right.png
    python3 cardreader/sim/card_png.py repeat repeat3.png --write 3

THE CODE IS DRAWN AS THE CARDS PRINT IT, turned half round from the AprilTag
library's own drawing (cardreader/README.md), by the same `tests/scenes.py`
the reader's tests draw with, so a card in the simulator is the card on the
table. `--write N` puts a handwritten N in a Repeat card's box: the first N in
`tests/mnist_test_digits.npz`, digits from MNIST's test split that the
number reader never trained on.
"""

from __future__ import annotations

import argparse
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent / "tests"))

import numpy as np  # noqa: E402

import scenes  # noqa: E402
from duckcards.cards import Deck  # noqa: E402


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("code", help="the card's code word, e.g. kick_right, start, repeat, card_2")
    p.add_argument("out", help="the PNG to write")
    p.add_argument("--scale", type=float, default=8.0, help="pixels per hundredth of the card's width")
    p.add_argument("--write", type=int, help="a handwritten figure in a Repeat card's box")
    a = p.parse_args()
    import cv2
    card = Deck.load().by_code(a.code)
    figure = None
    if a.write is not None:
        digits = np.load(HERE.parent / "tests" / "mnist_test_digits.npz")
        figure = digits["x"][list(digits["y"]).index(a.write)]
    cv2.imwrite(a.out, scenes.card_image(card.tag, card.category, scale=a.scale, write=figure))
    print(f"wrote {a.out}: {card.name} ({card.tag})" + (f", {a.write} written in its box" if figure is not None else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
