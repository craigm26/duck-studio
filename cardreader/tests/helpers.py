"""Cards placed by hand, for tests that do not need a picture.

`seen_at` works backwards from where a card lies to where its code's corners
would be found, using the card's own geometry, so a layout test can say "Start
here, Walk forward there, a Slow under it, the whole row upside down" in a line.
"""

from __future__ import annotations

import math
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

from duckcards.cards import (CARD_H, CARD_W, SQUARE, Deck, place)  # noqa: E402

DECK = Deck.load()


def corners_at(cx: float, cy: float, width_px: float, angle_deg: float = 0.0):
    """The code's corners, in the library's order, for a card centred at (cx, cy), `width_px`
    wide, turned `angle_deg` clockwise in the picture."""
    s = width_px / CARD_W
    a = math.radians(angle_deg)
    rx, ry = math.cos(a), math.sin(a)          # the card's right, in the picture
    dx, dy = -math.sin(a), math.cos(a)         # the card's down

    def at(u, v):    # card units, from the card's top left
        u0, v0 = (u - CARD_W / 2) * s, (v - CARD_H / 2) * s
        return (cx + u0 * rx + v0 * dx, cy + u0 * ry + v0 * dy)

    left, top, right, bottom = SQUARE
    return [at(right, top), at(left, top), at(left, bottom), at(right, bottom)]


def seen_at(code: str, cx: float, cy: float, width_px: float = 100.0, angle_deg: float = 0.0):
    return place(DECK.by_code(code), corners_at(cx, cy, width_px, angle_deg), margin=80.0)


def row_at(codes, x0=100.0, y=300.0, width=100.0, gap=12.0, angle=0.0, unders=None):
    """A row of cards, left to right in the cards' own direction, and optional unders:
    {index: [codes]} placed one card height below that card."""
    unders = unders or {}
    out = []
    a = math.radians(angle)
    rx, ry = math.cos(a), math.sin(a)
    dx, dy = -math.sin(a), math.cos(a)
    h = width * CARD_H / CARD_W
    for i, code in enumerate(codes):
        t = i * (width + gap)
        cx, cy = x0 + t * rx, y + t * ry
        out.append(seen_at(code, cx, cy, width, angle))
        for j, u in enumerate(unders.get(i, [])):
            k = (j + 1) * (h + 8)
            out.append(seen_at(u, cx + 4 * rx + k * dx, cy + 4 * ry + k * dy, width, angle))
    return out
