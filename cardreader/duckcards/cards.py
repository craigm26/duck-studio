"""The deck, and where a card is once its code has been found in a picture.

THE DECK TRAVELS BYTE FOR BYTE. `duck-cards.json` is microduckstudio.com's
`public/cards/duck-cards.json` (craigm26/microduck-com 5755fcc), copied without
a byte changed and pinned by sha256 in the tests, for the reason the stairs
challenge ships as files rather than retyped: a reader that carried its own
idea of what code 61 means would be a second deck, and the second deck is the
one that is wrong when they disagree.

WHERE THE CARD IS, FROM WHERE ITS CODE IS. A camera finds the code, not the
card. The code's black square is 19.2% of the card's width and sits at a fixed
place in its bottom right corner, because the site draws every card from the
same rules (`site.css`, the Duck Cards section, every size a share of the
card's own width). In those units, a card is 100 wide and 140 tall, and the
black square runs from 73.9 to 93.1 across and 109.3 to 128.5 down. So one
square, found at any size and turned any way, says where the whole card is and
which way is up on it. `tests/test_cards.py` checks these numbers against the
card geometry again, and the scene tests find cards drawn from them.
"""

from __future__ import annotations

import hashlib
import json
import math
import pathlib
from dataclasses import dataclass, field

HERE = pathlib.Path(__file__).resolve().parent
DECK_FILE = HERE / "duck-cards.json"
DECK_SHA256 = "4889f6e245f0d53b5b6699aca0d32f83a0b6d71f21334bace119ab50dd542dd4"

# The card in its own units: 100 wide, 140 tall (63.5 x 88.9 mm), and the code's black square.
CARD_W, CARD_H = 100.0, 140.0
SQUARE = (73.9, 109.3, 93.1, 128.5)          # left, top, right, bottom
SQUARE_SIDE = SQUARE[2] - SQUARE[0]           # 19.2
SQUARE_CX = (SQUARE[0] + SQUARE[2]) / 2       # 83.5
SQUARE_CY = (SQUARE[1] + SQUARE[3]) / 2       # 118.9
# The card's centre, from the square's centre, in squares along the card's right and down.
CENTRE_RIGHT = (CARD_W / 2 - SQUARE_CX) / SQUARE_SIDE    # -1.745
CENTRE_DOWN = (CARD_H / 2 - SQUARE_CY) / SQUARE_SIDE     # -2.547
WIDTH_IN_SQUARES = CARD_W / SQUARE_SIDE                   # 5.208
HEIGHT_IN_SQUARES = CARD_H / SQUARE_SIDE                  # 7.292


@dataclass(frozen=True)
class Card:
    tag: int
    code: str
    name: str
    category: str
    kind: str                  # action, modifier, control, event, yours
    plan: dict | None          # the labels this card puts into a plan, as the deck says
    write_in: str | None = None


class Deck:
    def __init__(self, data: dict):
        if data.get("format") != "duck-cards/0":
            raise ValueError(f"not a duck-cards/0 deck: {data.get('format')!r}")
        self.vocabulary = data["vocabulary"]
        self.plan_format = data["plan_format"]
        self.tag_family = data["tag_family"]
        self.categories = {c["id"]: c for c in data["categories"]}
        self.cards: dict[int, Card] = {}
        for c in data["cards"]:
            card = Card(tag=c["tag"], code=c["code"], name=c["name"], category=c["category"],
                        kind=c["kind"], plan=c.get("plan"), write_in=c.get("write_in"))
            self.cards[card.tag] = card
        lo, hi = self.categories["yours"]["codes"]
        self.yours_range = (lo, hi)

    @classmethod
    def load(cls, path: pathlib.Path = DECK_FILE) -> "Deck":
        raw = path.read_bytes()
        return cls(json.loads(raw))

    @staticmethod
    def digest(path: pathlib.Path = DECK_FILE) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def card(self, tag: int) -> Card | None:
        """The card a code means, or None for a code the deck does not use.

        A Your card the starter deck did not print (it prints 200 to 208) is still a Your card:
        the whole range 200 to 299 is set aside for them, so a class that made a tenth one has
        not made a stranger's code."""
        if tag in self.cards:
            return self.cards[tag]
        lo, hi = self.yours_range
        if lo <= tag <= hi:
            return Card(tag=tag, code=f"card_{tag - lo + 1}", name="Your card", category="yours",
                        kind="yours", plan=None)
        return None

    def by_code(self, code: str) -> Card:
        for card in self.cards.values():
            if card.code == code:
                return card
        raise KeyError(code)


@dataclass
class Seen:
    """One card found in one picture."""
    card: Card
    corners: list[tuple[float, float]]   # the AprilTag library's order: p[0] .. p[3]
    margin: float = 0.0
    hamming: int = 0
    # Worked out from the corners:
    centre: tuple[float, float] = (0.0, 0.0)        # the square's centre
    right: tuple[float, float] = (1.0, 0.0)         # one square to the card's right, in pixels
    down: tuple[float, float] = (0.0, 1.0)          # one square down the card, in pixels
    card_centre: tuple[float, float] = (0.0, 0.0)
    extra: dict = field(default_factory=dict)

    @property
    def side(self) -> float:
        """The square's side in pixels: how big the card looks."""
        return (math.hypot(*self.right) + math.hypot(*self.down)) / 2


def place(card: Card, corners, margin: float = 0.0, hamming: int = 0) -> Seen:
    """Where the card is, from the four corners of its code.

    THE CORNER ORDER IS THE LIBRARY'S, AND IT WAS MEASURED, NOT REMEMBERED. For a code drawn
    upright, the AprilTag library (and pupil_apriltags, which wraps it) answers top right, top
    left, bottom left, bottom right: p[0] to p[3]. `tests/test_cards.py` draws an upright code and
    holds the reader to that order, so a library that changed it would fail there first rather
    than make every row read backwards."""
    p = [(float(x), float(y)) for x, y in corners]
    tr, tl, bl, br = p
    right = ((tr[0] - tl[0] + br[0] - bl[0]) / 2, (tr[1] - tl[1] + br[1] - bl[1]) / 2)
    down = ((bl[0] - tl[0] + br[0] - tr[0]) / 2, (bl[1] - tl[1] + br[1] - tr[1]) / 2)
    centre = (sum(q[0] for q in p) / 4, sum(q[1] for q in p) / 4)
    card_centre = (centre[0] + CENTRE_RIGHT * right[0] + CENTRE_DOWN * down[0],
                   centre[1] + CENTRE_RIGHT * right[1] + CENTRE_DOWN * down[1])
    return Seen(card=card, corners=p, margin=margin, hamming=hamming, centre=centre,
                right=right, down=down, card_centre=card_centre)
