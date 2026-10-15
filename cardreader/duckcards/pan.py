"""A row longer than one look: the head turns along it, and the looks are joined into one row.

ABOUT FOUR CARDS A LOOK. The camera gives the reader an upright 720x1280 picture, about 37°
across, so a row held where its codes can still be read fits about four cards (README). A longer
row is read the way a person reads a long shelf: turning the head along it a little at a time and
keeping track of where each card was.

A TURN OF THE HEAD IS A TURN ABOUT THE NECK, NOT THE LENS. In Pollen's alpha head
(`kinematics/assets/alpha/robot_walk.xml` at 648bf22, worked through joint by joint) the
`head_camera` site is 55.6 mm in front of the `head_yaw` axis along the optical axis and nothing to
either side, and the yaw axis is the picture's own up and down at every head_pitch. So two looks
that differ only in head_yaw differ by a turn of the camera about its own vertical, with the lens
carried 5.6 cm round a circle. A card's angle from the lens plus the head's yaw is therefore not
where the card is: taken that way, a card at the edge of one look and the same card at the far
edge of the next land 0.54 of a card's width apart, at any distance (the error and the card both
shrink with distance), which is enough to read one card as two.

SO EVERY CARD IS PUT WHERE A CAMERA ON THE YAW AXIS WOULD HAVE SEEN IT. How far away a card is
comes from the size of its code (the black square is 12.2 mm across), its code's corners are
carried back from the lens to the axis, and every look's cards land in one wide picture: across,
the angle round the axis; up and down, height over distance; both in the first look's pixels per
radian, so a card keeps its shape. A distance a tenth out moves a card 0.1 to 0.2°, a thirtieth of
a card. `layout.arrange` then reads the wide picture with its own rules, unchanged: which card is
under which, rows, a row seen from the far side running the other way, a card turned round.

THE SAME CARD IN TWO LOOKS IS ONE CARD, AND TWO CARDS STAY TWO. The head is not always quite where
it was sent, so each look after the first starts where the look next to it was found to be and is
slid across to lie on the cards it shares with the looks before it (`_line_up`): from as far as a
card and a half when a shared card has no twin nearby, from a third of a card when all it shares
is a run of one card, which could be lying on its own neighbour. Then a card with the same code
within a third of a card of one already placed is that card. Three Walk forward cards in a row are
a card's width or more apart, so they stay three. Of the copies, the one nearest the middle of its
own picture is kept: it is the least cut, the least slanted and the least moved by a wrong
distance. A card cut off at the edge of one look is simply not in it; the look next to it has it.

A JOIN THAT DOES NOT LINE UP IS REFUSED, NOT READ. Two cards from two looks nearer than 0.8 of a
card (0.9 for two copies of one code) cannot both be there; and a look that lies on none of the
cards its turn should have kept in view was not taken where the head was sent. `join` says so
(JoinError) rather than read a row with a card twice or a card lost. On looks placed by hand at
35 to 60 cm, a turn of the scan's own size is lined up right with the head off by up to about a
quarter of the turn, or by a constant 8 to 13°, when it shares a card with no twin nearby; only
2 to 3° when all it shares is a run of one card, and such a run read wrong needs 4° or more.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from .cards import CARD_W, HEIGHT_IN_SQUARES, SQUARE_SIDE, WIDTH_IN_SQUARES, Seen, place
from .layout import Layout, Row, arrange

# The picture's long side is the camera's full ~62° (mediad/src/camera.rs; tests/scenes.py).
LONG_SIDE_DEG = 62.0
# The lens is this far in front of the head_yaw axis, along the optical axis, mm (the alpha MJCF).
LENS_AHEAD_MM = 55.6
# The code's black square, mm: 19.2 hundredths of a 63.5 mm card.
SQUARE_MM = SQUARE_SIDE / CARD_W * 63.5
# In card widths: how far a look may slide to lie on a card the row holds once (REACH) and on one
# with twins nearby (SLIDE); how near two copies of one code are one card; how near cards from two
# looks may be when they are not one card (two cards with one code stand at least a card's width
# apart, so their copies may come nearer only by being one card misplaced); and how near a copy
# of a card may be to its twin in a look that shares nothing with the looks before it, which is
# that card displaced, not a second one.
REACH = 1.5
SLIDE = 0.35
SAME = 0.35
APART = 0.8
TWINS_APART = 0.9
DISPLACED = 1.5
# A card whose middle is nearer the picture's edge than this many card widths, the way its row
# runs, may have a neighbour the picture cut off: the next card's code ends about 1.6 card widths
# past this card's middle when the cards stand 8 mm apart, and two allows for wider gaps.
EDGE = 2.0
# A turn for the next look is held between these, radians.
STEP_LEAST = math.radians(5.0)
STEP_MOST = math.radians(25.0)


class JoinError(ValueError):
    pass


@dataclass
class Look:
    """The cards one picture found, and the head's yaw it was taken at."""
    seen: list[Seen]
    yaw: float = 0.0                        # robotd's head_yaw, radians: more turns the head left
    size: tuple[int, int] = (720, 1280)     # the picture, width and height in pixels

    @property
    def f(self) -> float:
        """Pixels per unit of tangent: the picture's long side spans LONG_SIDE_DEG."""
        return max(self.size) / 2 / math.tan(math.radians(LONG_SIDE_DEG) / 2)


@dataclass
class Joined(Layout):
    """The rows of several looks, laid out as one wide picture would show them. It is a `Layout`,
    so `program.read` reads it the way it reads one look."""
    looks: list[Look] = field(default_factory=list)
    new: list[int] = field(default_factory=list)       # per look, cards no look before it had
    shared: list[int] = field(default_factory=list)    # per look, cards it lay on to line up
    slid: list[float] = field(default_factory=list)    # per look, radians the head was off its yaw, by them
    copies: dict = field(default_factory=dict)         # id(a card here) -> [(look, as it found it)]

    def found_in(self, s: Seen, look: int) -> Seen | None:
        """This card as look `look` found it, or None if that look did not see it."""
        for k, c in self.copies.get(id(s), ()):
            if k == look:
                return c
        return None


@dataclass
class _Card:
    look: int
    seen: Seen              # as its own picture found it
    corners: list           # its code's corners in the wide picture
    off: float              # how far from its own picture's middle, a share of the width
    reach: float            # mm from the yaw axis to its code
    wide: Seen | None = None

    def lay(self, shift: float = 0.0) -> None:
        self.corners = [(u + shift, v) for u, v in self.corners]
        self.wide = _square(self.seen, self.corners)

    @property
    def width(self) -> float:
        return math.hypot(*self.wide.right) * WIDTH_IN_SQUARES

    @property
    def height(self) -> float:
        return math.hypot(*self.wide.down) * HEIGHT_IN_SQUARES


def _square(s: Seen, corners: list, count: int | None = None) -> Seen:
    """A card in the wide picture, where its corners put it and as big, with its down at right
    angles to its right, as on the card itself.

    A CARD SEEN SLANTING AWAY KEEPS ITS PLACE AND LOSES ITS SLANT. On the floor, every card's down
    points at the duck, and in a look turned to one side the camera draws all of them leaning the
    same way. `layout.arrange` measures rows along the cards' mean down, so a row that leans like
    that is cut into two. Where each card is (its middle, from its own code) and how big it is stay
    as the camera saw them; only the lean the camera gave its down is taken out."""
    w = place(s.card, corners, s.margin, s.hamming, s.count if count is None else count)
    n = math.hypot(*w.right) or 1.0
    k = math.hypot(*w.down) / n
    w.down = (-w.right[1] * k, w.right[0] * k)
    return w


def depth(s: Seen, f: float) -> float:
    """How far in front of the lens a card is, mm along the camera's axis, from its code's size.
    The longer of the code's two sides in the picture is the one its card is turned least away
    along: a card in a rail, turned by the head, keeps its height; a card on the floor its width."""
    return f * SQUARE_MM / max(math.hypot(*s.right), math.hypot(*s.down), 1e-6)


def _card(k: int, s: Seen, look: Look, scale: float, middle: tuple[float, float]) -> _Card:
    f = look.f
    cx, cy = look.size[0] / 2, look.size[1] / 2
    z = depth(s, f)
    ahead = z + LENS_AHEAD_MM                       # mm in front of the yaw axis
    corners = []
    for u, v in s.corners:
        x, y = (u - cx) / f * z, (v - cy) / f * z   # mm, the camera's right and down
        across = math.atan2(x, ahead) - look.yaw    # radians round the axis, to the right
        corners.append((middle[0] + scale * across, middle[1] + scale * y / math.hypot(x, ahead)))
    c = _Card(look=k, seen=s, corners=corners, off=abs(s.centre[0] - cx) / look.size[0],
              reach=math.hypot((s.centre[0] - cx) / f * z, ahead))
    c.lay()
    return c


def _in_view(p: _Card, look: Look, yaw: float, scale: float, middle: tuple[float, float]) -> bool:
    """Whether a card's code, placed from another look, should be in this look's picture with a
    card's width to spare all round, the head at `yaw`: the wide picture read back the other way."""
    across = (p.wide.centre[0] - middle[0]) / scale + yaw
    x, z = p.reach * math.sin(across), p.reach * math.cos(across) - LENS_AHEAD_MM
    if z <= 0:
        return False
    f = look.f
    u = look.size[0] / 2 + f * x / z
    v = look.size[1] / 2 + f * (p.wide.centre[1] - middle[1]) / scale * p.reach / z
    spare = f * SQUARE_MM * WIDTH_IN_SQUARES / z
    return spare <= u <= look.size[0] - spare and spare <= v <= look.size[1] - spare


def _median(xs: list[float]) -> float:
    xs = sorted(xs)
    n = len(xs)
    return xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2


def _line_up(cards: list[_Card], placed: list[list[_Card]]) -> float:
    """How far across, in wide pixels, a look's cards slide to lie on the copies already placed.

    A CARD WITH NO TWIN NEARBY SAYS WHERE IT IS; A RUN OF ONE CARD DOES NOT. A code with no twin
    within two reaches of it in this look, and one copy within a card and a half of where the
    turn put it, is that card, and the look slides to it from as far as REACH. A code with twins
    nearby, three Walk forward in a row, could be lying on its neighbour, a card's width or more
    away; it is trusted only within SLIDE, so a run is refused before it can gain or lose a card."""
    sure, near = [], []
    for c in cards:
        found = []
        for group in placed:
            p = group[0]
            if p.seen.card.tag != c.seen.card.tag:
                continue
            w, h = (p.width + c.width) / 2, (p.height + c.height) / 2
            du, dv = p.wide.centre[0] - c.wide.centre[0], p.wide.centre[1] - c.wide.centre[1]
            if abs(dv) <= SLIDE * h and abs(du) <= REACH * w:
                found.append((abs(du) / w, du))
        alone = not any(x is not c and x.seen.card.tag == c.seen.card.tag
                        and math.dist(x.wide.centre, c.wide.centre) < 2 * REACH * c.width for x in cards)
        if len(found) == 1 and alone:
            sure.append(found[0][1])
        near += [du for d, du in found if d <= SLIDE]
    if sure:
        return _median(sure)
    return _median(near) if near else 0.0


def join(looks: list[Look]) -> Joined:
    """Several looks along a row, as one row: the first look is where the head watches, and the
    others are joined onto it nearest first, so each lies on cards already placed."""
    if not looks:
        return Joined(rows=[], turned=[], direction=(1.0, 0.0))
    first = looks[0]
    scale, middle = first.f, (first.size[0] / 2, first.size[1] / 2)
    n = len(looks)
    new, shared, slid = [0] * n, [0] * n, [0.0] * n
    placed: list[list[_Card]] = []      # one list per card: its copies, the most central first
    joined: list[int] = []
    for k in sorted(range(n), key=lambda i: (abs(looks[i].yaw - first.yaw), i)):
        cards = [_card(k, s, looks[k], scale, middle) for s in looks[k].seen]
        if joined:
            # A head that turned short of one look turns short of the next as well: each look
            # starts from the look next to it, then slides at most half a card from there.
            prior = slid[min(joined, key=lambda i: abs(looks[i].yaw - looks[k].yaw))]
            if prior:
                for c in cards:
                    c.lay(-prior * scale)
            shift = _line_up(cards, placed)
            if shift:
                for c in cards:
                    c.lay(shift)
            slid[k] = prior - shift / scale
        joined.append(k)
        here = list(placed)             # a look is matched against earlier looks, never itself
        shared[k], displaced = 0, None
        for c in cards:
            match, near = None, None
            for group in here:
                if any(x.look == k for x in group):
                    continue            # one look never finds one card twice
                p = group[0]
                d = math.dist(p.wide.centre, c.wide.centre) / ((p.width + c.width) / 2)
                twin = p.seen.card.tag == c.seen.card.tag
                if twin and d <= SAME:
                    if match is None or d < match[1]:
                        match = (group, d)
                elif d < (TWINS_APART if twin else APART) and (near is None or d < near[1]):
                    near = (group, d)
                elif twin and d < DISPLACED and (displaced is None or d < displaced[1]):
                    displaced = (p, d, c)
            if match is not None:
                match[0].append(c)
                match[0].sort(key=lambda x: x.off)
                shared[k] += 1
            elif near is not None:
                raise JoinError(f"the looks do not line up: {c.seen.card.name} in one is "
                                f"{near[1]:.2f} of a card from {near[0][0].seen.card.name} in another")
            else:
                placed.append([c])
                new[k] += 1
        if here and cards and not shared[k]:
            # A look that lies on none of the cards its turn should have kept in view is a head
            # that was not where it was sent, however its cards happen to fall.
            if displaced is not None:
                p, d, c = displaced
                raise JoinError(f"the looks do not line up: they share no card, and {c.seen.card.name} "
                                f"in one is {d:.2f} of a card from {p.seen.card.name} in another")
            missed = [g[0] for g in here if _in_view(g[0], looks[k], looks[k].yaw + slid[k], scale, middle)]
            if missed:
                raise JoinError(f"the looks do not line up: {missed[0].seen.card.name} should be in "
                                "both, and the later look does not find it where the turn put it")
    wide, copies = [], {}
    for group in placed:
        keep = group[0]
        counts = {x.seen.count for x in group if x.seen.count is not None}
        # A Repeat's number read the same wherever it was read, or not at all: the row then asks.
        count = next(iter(counts)) if len(counts) == 1 else None
        s = _square(keep.seen, keep.corners, count)
        s.count = count
        copies[id(s)] = [(x.look, x.seen) for x in group]
        wide.append(s)
    layout = arrange(wide)
    return Joined(rows=layout.rows, turned=layout.turned, direction=layout.direction, looks=list(looks),
                  new=new, shared=shared, slid=slid, copies=copies)


# ---------------------------------------------------------------- which way, and how far
def main_row(layout: Layout) -> Row | None:
    """The row a reader follows: the one `program.read` reads (the first with Start that does not
    begin with When it falls), else the first with an End, else the longest of three cards or more
    (a row cut off at both ends)."""
    rows = [r for r in layout.rows if r.codes and r.codes[0] != "when_falls"]
    for want in ("start", "end"):
        for r in rows:
            if want in r.codes:
                return r
    longest = max(rows, key=lambda r: len(r.slots), default=None)
    return longest if longest is not None and len(longest.slots) >= 3 else None


def _wants(row: Row) -> tuple[bool, bool]:
    """Whether a row wants cards after its last (a Start with no End after it) and before its first
    (an End with no Start: the Start is somewhere before it). A row with neither wants both."""
    codes = row.codes
    if "start" in codes:
        return "end" not in codes[codes.index("start"):], False
    return "end" not in codes, True


def done(layout: Layout, ahead: bool) -> bool:
    """Whether a turn that way has found what it was looking for: an End after the Start (ahead),
    or the Start (behind)."""
    row = main_row(layout)
    if row is None:
        return False
    after, before = _wants(row)
    return not (after if ahead else before)


def _way(s: Seen, ahead: bool) -> tuple[float, float]:
    """The way a card's row runs in its picture: the card's own right, or its left for behind."""
    n = math.hypot(*s.right) or 1.0
    k = 1.0 if ahead else -1.0
    return (k * s.right[0] / n, k * s.right[1] / n)


def to_edge(s: Seen, size: tuple[int, int], way: tuple[float, float]) -> float:
    """How far from a card's middle to the picture's edge, going `way`, in the card's widths."""
    w, h = size
    x, y = s.card_centre
    ts = []
    if way[0] > 1e-9:
        ts.append((w - x) / way[0])
    elif way[0] < -1e-9:
        ts.append(-x / way[0])
    if way[1] > 1e-9:
        ts.append((h - y) / way[1])
    elif way[1] < -1e-9:
        ts.append(-y / way[1])
    width = math.hypot(*s.right) * WIDTH_IN_SQUARES
    return min(ts) / width if ts and width else math.inf


def _off(s: Seen, size: tuple[int, int], ahead: bool) -> int:
    """+1 if the row runs off the picture's right after this card, -1 its left, 0 neither. A row
    running more up the picture than across it is not one a turn of the head follows."""
    way = _way(s, ahead)
    if abs(way[0]) < 0.5 or to_edge(s, size, way) >= EDGE:
        return 0
    return 1 if way[0] > 0 else -1


def turns(layout: Layout, size: tuple[int, int]) -> list[tuple[int, bool]]:
    """Which ways to turn the head for the rest of a row this picture cut off, read from one
    look's own layout: (+1 to the right or -1 to the left, ahead), ahead first. A Start with no End
    whose last card is near the edge wants the cards after it; an End with no Start whose first
    card is near the edge wants the ones before it; a row of three or more with neither, cut off at
    both ends, wants both."""
    row = main_row(layout)
    if row is None:
        return []
    after, before = _wants(row)
    out = []
    if after and (way := _off(row.slots[-1].card, size, True)):
        out.append((way, True))
    if before and (way := _off(row.slots[0].card, size, False)):
        out.append((way, False))
    if after and before and len(out) < 2:
        return []
    return out


def row_in(joined: Joined, k: int) -> list[Seen]:
    """The followed row's cards as look `k` found them, in the row's order."""
    row = main_row(joined)
    found = [joined.found_in(s.card, k) for s in row.slots] if row else []
    return [s for s in found if s is not None]


def runs_on(joined: Joined, k: int, ahead: bool) -> bool:
    """Whether the row still runs off look `k`'s picture the way the head is turning: its last
    card (ahead) or first (behind) is in that look and near the edge."""
    row = main_row(joined)
    if row is None:
        return False
    end = joined.found_in(row.slots[-1 if ahead else 0].card, k)
    return end is not None and _off(end, joined.looks[k].size, ahead) != 0


def step(look: Look, row: list[Seen]) -> float:
    """How far to turn the head for the next look, radians: as far as still leaves one whole card
    in both pictures wherever the cards fall, which two pictures sharing a card's width plus the
    spacing of the cards always do. The width, spacing and distance are the row's own in this
    look. The picture moves (Z + 5.6 cm) / Z times as far as the head turns, the lens being in
    front of the axis, so the turn is that much less: 13° at 35 cm, 18° at 45 cm, 22° at 60 cm."""
    cards = row or look.seen
    if not cards:
        return STEP_LEAST
    f = look.f
    width = _median([math.hypot(*s.right) * WIDTH_IN_SQUARES for s in cards])
    gaps = [math.dist(a.card_centre, b.card_centre) for a, b in zip(cards, cards[1:])]
    spacing = max(_median(gaps), width) if gaps else 1.15 * width
    z = _median([depth(s, f) for s in cards])
    across = 2 * math.atan(look.size[0] / 2 / f)
    turn = (across - (width + spacing) / f) * z / (z + LENS_AHEAD_MM)
    return min(STEP_MOST, max(STEP_LEAST, turn))
