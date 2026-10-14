"""Cards found in a picture, put back into the rows a class laid out.

READ THE WAY THE CARDS FACE, NOT THE WAY THE PICTURE DOES. A row on the floor
seen from the far side is upside down in the picture, and a duck reading it
left to right in pixels would run it backwards. Every code says which way is up
on its own card, so the row's direction is the cards' own "right", averaged over
them, and "under" is the cards' own "down". A row seen from either side reads
the same.

THREE MEASUREMENTS, ALL IN CARDS. Positions are projected onto the row's
direction ("along") and the cards' down ("across"), and every threshold is a
share of a card's own size in this picture, so the same rules read a card held
at 20 cm and a row on the floor at 60 cm:

- a Speed or Look card is UNDER a card when it sits about one card lower and
  overlaps it sideways (`tests/test_layout.py` holds the window),
- cards about one card or more apart across are on different ROWS,
- along a row, order is position.

A modifier that is under nothing stays in its row, and the program says what it
did with it rather than dropping it unseen.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from .cards import HEIGHT_IN_SQUARES, WIDTH_IN_SQUARES, Seen

# Under: this many card heights below the card above it, and within this many card widths sideways.
UNDER_BELOW = (0.45, 1.65)
UNDER_SIDEWAYS = 0.6
# A new row starts when a card sits this many card heights below the row so far.
NEW_ROW = 0.6
# A card turned more than this many degrees away from the row's own direction is not in it.
TURNED = 50.0


@dataclass
class Slot:
    card: Seen
    under: list[Seen] = field(default_factory=list)


@dataclass
class Row:
    slots: list[Slot]

    @property
    def codes(self) -> list[str]:
        return [s.card.card.code for s in self.slots]


@dataclass
class Layout:
    rows: list[Row]
    turned: list[Seen]          # cards facing another way from the rest: not read into any row
    direction: tuple[float, float]

    def describe(self) -> list[list[str]]:
        """Rows as code lists, with an under-card after its card as `walk_forward/slow`."""
        return [["/".join([s.card.card.code] + [u.card.code for u in s.under]) for s in r.slots]
                for r in self.rows]


def _unit(v):
    n = math.hypot(*v)
    return (v[0] / n, v[1] / n) if n else (1.0, 0.0)


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def arrange(seen: list[Seen]) -> Layout:
    if not seen:
        return Layout(rows=[], turned=[], direction=(1.0, 0.0))
    # The row's direction: the way most cards face. A mean of unit vectors is dominated by the
    # majority, so one card upside down among five does not swing it; that card is set aside.
    rights = [_unit(s.right) for s in seen]
    direction = _unit((sum(r[0] for r in rights), sum(r[1] for r in rights)))
    if math.hypot(sum(r[0] for r in rights), sum(r[1] for r in rights)) < 1e-6:
        direction = rights[0]
    cos_turned = math.cos(math.radians(TURNED))
    facing = [s for s, r in zip(seen, rights) if _dot(r, direction) >= cos_turned]
    turned = [s for s, r in zip(seen, rights) if _dot(r, direction) < cos_turned]
    downs = [_unit(s.down) for s in facing]
    down = _unit((sum(d[0] for d in downs), sum(d[1] for d in downs)))

    def along(s: Seen) -> float:
        return _dot(s.card_centre, direction)

    def across(s: Seen) -> float:
        return _dot(s.card_centre, down)

    def width(s: Seen) -> float:
        return math.hypot(*s.right) * WIDTH_IN_SQUARES

    def height(s: Seen) -> float:
        return math.hypot(*s.down) * HEIGHT_IN_SQUARES

    modifiers = [s for s in facing if s.card.kind == "modifier"]
    mains = [s for s in facing if s.card.kind != "modifier"]

    # Under-cards first, top down: each modifier goes under the nearest card above it. A second
    # modifier under the first (a walk carrying a Speed and a Look) belongs to the same card.
    under_of: dict[int, list[Seen]] = {}
    owner: dict[int, Seen] = {}
    loose: list[Seen] = []
    for m in sorted(modifiers, key=across):
        best, best_d = None, None
        for c in mains + [x for x in modifiers if id(x) in owner]:
            h = (height(c) + height(m)) / 2
            w = (width(c) + width(m)) / 2
            below = (across(m) - across(c)) / h
            side = abs(along(m) - along(c)) / w
            if UNDER_BELOW[0] <= below <= UNDER_BELOW[1] and side <= UNDER_SIDEWAYS:
                d = abs(below - 1.0) + side
                if best_d is None or d < best_d:
                    best, best_d = c, d
        if best is None:
            loose.append(m)
        else:
            main = owner.get(id(best), best)
            owner[id(m)] = main
            under_of.setdefault(id(main), []).append(m)

    # Rows: sweep down the cards' own "down", starting a row at each clear gap.
    line_cards = sorted(mains + loose, key=across)
    rows_of: list[list[Seen]] = []
    for s in line_cards:
        if rows_of:
            row = rows_of[-1]
            mean = sum(across(x) for x in row) / len(row)
            h = sum(height(x) for x in row) / len(row)
            if (across(s) - mean) / h < NEW_ROW:
                row.append(s)
                continue
        rows_of.append([s])
    rows = []
    for cards in rows_of:
        cards.sort(key=along)
        rows.append(Row(slots=[Slot(card=c, under=sorted(under_of.get(id(c), []), key=across))
                               for c in cards]))
    return Layout(rows=rows, turned=turned, direction=direction)
