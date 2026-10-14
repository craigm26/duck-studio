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
which way is up on it. `tests/test_reader.py` checks the square's share of the
card, and its picture tests find cards drawn from these numbers.
"""

from __future__ import annotations

import hashlib
import json
import math
import pathlib
from dataclasses import dataclass

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
class Entry:
    """One card of a saved row, in the deck's own `example.row` shape: the card, the cards under
    it, and for a Repeat the number of times, which a saved row always carries."""
    card: str
    under: tuple[str, ...] = ()
    times: int | None = None


@dataclass(frozen=True)
class Card:
    tag: int
    code: str
    name: str
    category: str
    kind: str                  # action, modifier, control, event, yours
    plan: dict | None          # the labels this card puts into a plan, as the deck says
    write_in: str | None = None
    row: tuple[Entry, ...] | None = None    # what a Your card stands for, once a class saved it
    does: str | None = None


# A number written on Repeat is one figure in a small box.
REPEAT_MOST = 9


class DeckError(ValueError):
    pass


def _entries(code: str, row) -> tuple[Entry, ...] | None:
    """A Your card's `row`, read strictly: a deck that says something this cannot follow is refused
    by name, rather than run as something nobody saved."""
    if row is None:
        return None
    if not isinstance(row, list):
        raise DeckError(f"{code}: row is not a list")
    out = []
    for e in row:
        if not isinstance(e, dict) or not isinstance(e.get("card"), str):
            raise DeckError(f"{code}: every card in its row needs a card code")
        under = e.get("under", [])
        if not isinstance(under, list) or not all(isinstance(u, str) for u in under):
            raise DeckError(f"{code}: under {e['card']} is not a list of card codes")
        times = e.get("times")
        if e["card"] == "repeat":
            if not isinstance(times, int) or isinstance(times, bool) or not 1 <= times <= REPEAT_MOST:
                raise DeckError(f"{code}: a Repeat in its row needs times, 1 to {REPEAT_MOST}")
        elif times is not None:
            raise DeckError(f"{code}: only a Repeat takes times")
        out.append(Entry(card=e["card"], under=tuple(under), times=times))
    return tuple(out)


class Deck:
    """The cards a code can mean: the starter deck, or a class's copy of it with Your cards saved.

    A YOUR CARD MEANS WHAT ITS DECK FILE SAYS. The cards page's spec puts the meaning in the deck,
    not in a phone or a duck: a Your card gains a `row`, in the shape of the deck's `example.row`,
    and a name and a `does` sentence beside it. So a class's deck file is the starter deck with
    some of the 200s filled in, and the duck and Studio read the same file the same way."""

    def __init__(self, data: dict):
        if data.get("format") != "duck-cards/0":
            raise DeckError(f"not a duck-cards/0 deck: {data.get('format')!r}")
        self.data = data
        self.vocabulary = data["vocabulary"]
        self.plan_format = data["plan_format"]
        self.tag_family = data["tag_family"]
        self.categories = {c["id"]: c for c in data["categories"]}
        lo, hi = self.categories["yours"]["codes"]
        self.yours_range = (lo, hi)
        self.cards: dict[int, Card] = {}
        for c in data["cards"]:
            card = Card(tag=c["tag"], code=c["code"], name=c["name"], category=c["category"],
                        kind=c["kind"], plan=c.get("plan"), write_in=c.get("write_in"),
                        row=_entries(c["code"], c.get("row")), does=c.get("does"))
            if card.row is not None and card.kind != "yours":
                raise DeckError(f"{card.code}: only a Your card stands for a row")
            self.cards[card.tag] = card
        for card in self.cards.values():
            for e in card.row or ():
                for code in (e.card, *e.under):
                    try:
                        self.by_code(code)
                    except KeyError:
                        raise DeckError(f"{card.code}: its row holds {code!r}, which is not a card") from None

    @classmethod
    def load(cls, path: pathlib.Path = DECK_FILE) -> "Deck":
        raw = pathlib.Path(path).read_bytes()
        return cls(json.loads(raw))

    @staticmethod
    def digest(path: pathlib.Path = DECK_FILE) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def with_cards(self, entries: list[dict]) -> "Deck":
        """This deck with some cards written over, by code number: a class's deck in a line."""
        by_tag = {c["tag"]: c for c in self.data["cards"]}
        for e in entries:
            by_tag[e["tag"]] = e
        return Deck({**self.data, "cards": [by_tag[t] for t in sorted(by_tag)]})

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
        if code.startswith("card_") and code[5:].isdigit():
            card = self.card(self.yours_range[0] + int(code[5:]) - 1)
            if card is not None and card.code == code:
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
    count: int | None = None        # the number written on a Repeat, when something could read it

    @property
    def side(self) -> float:
        """The square's side in pixels: how big the card looks."""
        return (math.hypot(*self.right) + math.hypot(*self.down)) / 2


def place(card: Card, corners, margin: float = 0.0, hamming: int = 0, count: int | None = None) -> Seen:
    """Where the card is, from the four corners of its code.

    THE CORNER ORDER IS THE LIBRARY'S, AND IT WAS MEASURED, NOT REMEMBERED. For a code the way a
    Duck Card prints it (turned half round from the library's own drawing; see the README), the
    AprilTag library and pupil_apriltags, which wraps it, answer top right, top left, bottom
    left, bottom right: p[0] to p[3]. `tests/test_reader.py` draws a card and holds the reader to
    that order, so a library that changed it would fail there first rather than make every row
    read backwards."""
    p = [(float(x), float(y)) for x, y in corners]
    tr, tl, bl, br = p
    right = ((tr[0] - tl[0] + br[0] - bl[0]) / 2, (tr[1] - tl[1] + br[1] - bl[1]) / 2)
    down = ((bl[0] - tl[0] + br[0] - tr[0]) / 2, (bl[1] - tl[1] + br[1] - tr[1]) / 2)
    centre = (sum(q[0] for q in p) / 4, sum(q[1] for q in p) / 4)
    card_centre = (centre[0] + CENTRE_RIGHT * right[0] + CENTRE_DOWN * down[0],
                   centre[1] + CENTRE_RIGHT * right[1] + CENTRE_DOWN * down[1])
    return Seen(card=card, corners=p, margin=margin, hamming=hamming, centre=centre,
                right=right, down=down, card_centre=card_centre, count=count)
