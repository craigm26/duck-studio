"""Cards placed by hand, for tests that do not need a picture.

`seen_at` works backwards from where a card lies to where its code's corners
would be found, using the card's own geometry, so a layout test can say "Start
here, Walk forward there, a Slow under it, the whole row upside down" in a line.

`rail_looks` does the same for a row standing in a rail in front of the duck,
seen with the head turned: the duck's camera (`scenes.py`'s, without the
pixels), turned about its own vertical through a point 55.6 mm behind the lens,
as Pollen's head turns. A card whose code is not wholly in a picture is not in
that look, as the AprilTag library would not find it.
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


def yours(tag: int, row: list, name: str = "Your card", does: str | None = None) -> dict:
    """A Your card as a class's deck file saves it: the spec's `row`, beside a name."""
    entry = {"tag": tag, "code": f"card_{tag - 199}", "name": name, "category": "yours", "kind": "yours",
             "plan": None, "row": row}
    if does:
        entry["does"] = does
    return entry


def class_deck(*cards: dict) -> Deck:
    return DECK.with_cards(list(cards))


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


def seen_at(code: str, cx: float, cy: float, width_px: float = 100.0, angle_deg: float = 0.0,
            count: int | None = None):
    return place(DECK.by_code(code), corners_at(cx, cy, width_px, angle_deg), margin=80.0, count=count)


CARD_MM = (63.5, 88.9)
FRAME = (720, 1280)
F = (FRAME[1] / 2) / math.tan(math.radians(31))      # the duck's camera, as tests/scenes.py has it
LENS_AHEAD_MM = 55.6


def project(p, yaw_deg: float):
    """A point in front of the duck (mm: right, down, ahead of the lens when the head is straight)
    to the picture taken with the head turned `yaw_deg` (+ is left)."""
    a = math.radians(yaw_deg)
    ahead = p[2] + LENS_AHEAD_MM
    x = p[0] * math.cos(a) + ahead * math.sin(a)
    z = -p[0] * math.sin(a) + ahead * math.cos(a) - LENS_AHEAD_MM
    return (F * x / z + FRAME[0] / 2, F * p[1] / z + FRAME[1] / 2)


def code_corners(centre, right, down, yaw_deg: float):
    """A card's code's corners in the picture, in the library's order, for a card in the world."""
    def at(u, v):    # card units, from the card's top left
        du, dv = (u - CARD_W / 2) / CARD_W * CARD_MM[0], (v - CARD_H / 2) / CARD_H * CARD_MM[1]
        return project([centre[i] + du * right[i] + dv * down[i] for i in range(3)], yaw_deg)
    left, top, rt, bottom = SQUARE
    return [at(rt, top), at(left, top), at(left, bottom), at(rt, bottom)]


def rail_looks(codes, distance_mm, yaws_deg, unders=None, far_side=False, gap_mm=8.0, x_mm=0.0,
               told_deg=None, edge_px=2.0):
    """A row standing in a rail `distance_mm` in front of the lens, its middle `x_mm` to the right,
    seen with the head turned to each of `yaws_deg`: one `pan.Look` per turn, holding the cards
    whose code is wholly in that picture. From the far side the row stands upside down and runs
    right to left. `told_deg`: the yaw each look says it was taken at, when the head was not
    where it was sent. `unders`: {index: [codes]}, standing under that card."""
    from duckcards.pan import Look
    unders = unders or {}
    k = -1.0 if far_side else 1.0
    right, down = (k, 0.0, 0.0), (0.0, k, 0.0)
    step = CARD_MM[0] + gap_mm
    placed = []
    for i, code in enumerate(codes):
        x = x_mm + k * (i - (len(codes) - 1) / 2) * step
        placed.append((code, (x, 0.0, distance_mm)))
        for j, u in enumerate(unders.get(i, [])):
            placed.append((u, (x + k * 3, k * (j + 1) * (CARD_MM[1] + 6), distance_mm)))
    looks = []
    for n, yaw in enumerate(yaws_deg):
        seen = []
        for code, centre in placed:
            corners = code_corners(centre, right, down, yaw)
            if all(edge_px <= u <= FRAME[0] - edge_px and edge_px <= v <= FRAME[1] - edge_px for u, v in corners):
                seen.append(place(DECK.by_code(code), corners, margin=80.0))
        said = yaw if told_deg is None else told_deg[n]
        looks.append(Look(seen=seen, yaw=math.radians(said), size=FRAME))
    return looks


def row_at(codes, x0=100.0, y=300.0, width=100.0, gap=12.0, angle=0.0, unders=None, counts=None):
    """A row of cards, left to right in the cards' own direction, and optional unders:
    {index: [codes]} placed one card height below that card, and numbers read off Repeat cards:
    {index: count}."""
    unders = unders or {}
    counts = counts or {}
    out = []
    a = math.radians(angle)
    rx, ry = math.cos(a), math.sin(a)
    dx, dy = -math.sin(a), math.cos(a)
    h = width * CARD_H / CARD_W
    for i, code in enumerate(codes):
        t = i * (width + gap)
        cx, cy = x0 + t * rx, y + t * ry
        out.append(seen_at(code, cx, cy, width, angle, count=counts.get(i)))
        for j, u in enumerate(unders.get(i, [])):
            k = (j + 1) * (h + 8)
            out.append(seen_at(u, cx + 4 * rx + k * dx, cy + 4 * ry + k * dy, width, angle))
    return out
