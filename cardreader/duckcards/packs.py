"""Duck Card packs: a game for the cards, set for a grade band, and the board it is played on.

A pack is one JSON file, `duck-pack/0`, shared as `.duckpack` (docs/PACKS.md is the spec). It
names the cards in play, a board, a ramp of challenges and the teacher's lessons. This module
reads one and refuses it in sentences, plays a row on a challenge's board, and works out par.

THE BOARD RULE IS EXACT; THE DUCK IS NOT. On the board one Walk card moves one square and one
Turn card is a quarter turn. A Microduck walks for a time, and drifts, so nothing here says where
a real duck would stop. `duck_square_cm` stays null until someone measures it.

A ROW BECOMES STEPS THE WAY THE READER ALREADY MAKES THEM. A challenge's `solution` is a saved
row, in the shape a Your card's row is saved in, so it goes through `program.table` and
`program.read` like any other saved row: Repeat unrolled, Your cards opened, nothing re-written
here. What the board plays is exactly what the duck would run.

THE SAME ANSWERS IN SWIFT. `StudioKit/Sources/StudioKit/DuckPacks.swift` is this file again, for
Studio. `vectors/pack_*.json` holds both to one result, byte for byte in what they say.
"""

from __future__ import annotations

import json
import pathlib
import re
from collections import deque
from dataclasses import dataclass

from .cards import REPEAT_MOST, Deck, DeckError, Entry
from .program import MAX_STEPS, Step, read, table

FORMAT = "duck-pack/0"
EXTENSION = "duckpack"
PACKS = pathlib.Path(__file__).resolve().parent / "packs"

FACINGS = ("north", "east", "south", "west")
# Which way each facing moves on the printed board: x grows to the right, y grows down the page.
AHEAD = {"north": (0, -1), "east": (1, 0), "south": (0, 1), "west": (-1, 0)}
AXES = ("ns", "ew")
SCORES = ("steps", "cards")
# The cards that move the duck on the board. Everything else is a step taken standing still.
MOVES = ("walk_forward", "walk_backward", "turn_left", "turn_right")
# A board this size still fits a classroom floor in 30 cm squares, and keeps the search small.
LARGEST_BOARD = 12
GRADES = range(-1, 13)
ID = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")


class PackError(ValueError):
    pass


@dataclass(frozen=True)
class Place:
    at: tuple[int, int]
    facing: str

    def json(self) -> dict:
        return {"at": [self.at[0], self.at[1]], "facing": self.facing}


@dataclass(frozen=True)
class Gate:
    at: tuple[int, int]
    axis: str


@dataclass(frozen=True)
class Challenge:
    id: str
    name: str
    columns: int
    rows: int
    start: Place
    goal: tuple[int, int]
    walls: frozenset            # of frozenset({a, b}): the two squares a wall sits between
    gates: tuple[Gate, ...]
    finish_with: str | None
    par: int
    solution: tuple[Entry, ...]
    buggy: tuple[Entry, ...] | None
    hint: str


@dataclass(frozen=True)
class Lesson:
    title: str
    skill: str
    body: str
    ask: str


@dataclass(frozen=True)
class Board:
    columns: int
    rows: int
    square_cm: float
    duck_square_cm: float | None


@dataclass
class Pack:
    data: dict
    id: str
    name: str
    grades: str
    grade_from: int
    grade_to: int
    vocabulary: str
    about: str
    cards: tuple[str, ...]
    score: str
    board: Board
    challenges: tuple[Challenge, ...]
    lessons: tuple[Lesson, ...]
    yours: tuple[dict, ...]

    @classmethod
    def read(cls, data: dict | bytes | str, deck: Deck) -> "Pack":
        """A pack, read strictly against the deck it names. Refused with a sentence that says what
        to fix, so a teacher who edited a file by hand can find the line."""
        return _read(data, deck)

    @classmethod
    def load(cls, path, deck: Deck) -> "Pack":
        return _read(pathlib.Path(path).read_bytes(), deck)

    def challenge(self, cid: str) -> Challenge:
        for c in self.challenges:
            if c.id == cid:
                return c
        raise KeyError(cid)

    def lend(self, deck: Deck, replace: bool = False) -> tuple[Deck, list[int]]:
        """The deck with this pack's Your cards in it (`lend_yours`)."""
        return lend_yours(deck, self.yours, replace)

    def in_play(self, code: str) -> bool:
        return code in self.cards

    def not_in_play(self, codes, deck: Deck) -> list[str]:
        """The cards among `codes` this pack does not play, in the words a reader says them:
        a card not in play still runs, and the class hears that it is outside the game."""
        out = []
        for code in dict.fromkeys(codes):
            if code not in self.cards:
                out.append(f"{deck.by_code(code).name} is not in {self.name}.")
        return out


def entries(row: list[dict]) -> list[Entry]:
    """A row as a file spells it, `[{"card", "under"?, "times"?}]`, as entries. Read loosely: a
    row from a pack has already been read strictly by `Pack.read`."""
    return [Entry(card=e["card"], under=tuple(e.get("under", [])), times=e.get("times")) for e in row]


def lend_yours(deck: Deck, yours, replace: bool = False) -> tuple[Deck, list[int]]:
    """A deck with a pack's Your cards in it, the way `Deck.lend` takes a class's file.

    A CLASS'S OWN CARD IS NOT WRITTEN OVER WITHOUT ASKING. Where the class already saved a
    different row for the same number, that card keeps the class's meaning unless `replace`; the
    numbers are returned either way, so a screen can ask."""
    clashes = []
    lent = []
    for y in yours:
        have = deck.cards.get(y["tag"])
        if have is not None and have.row and have.row != deck_entries(y):
            clashes.append(y["tag"])
            if not replace:
                continue
        lent.append(y)
    if not lent:
        return deck, clashes
    by_tag = {c["tag"]: c for c in deck.data["cards"]}
    for y in lent:
        by_tag[y["tag"]] = y
    merged, _ = deck.lend({**deck.data, "cards": [by_tag[t] for t in sorted(by_tag)]})
    return merged, clashes


def deck_entries(y: dict) -> tuple[Entry, ...]:
    return tuple(Entry(card=e["card"], under=tuple(e.get("under", [])), times=e.get("times"))
                 for e in y.get("row") or [])


# ---------------------------------------------------------------------------------------------
# reading a pack

def _need(cond: bool, message: str) -> None:
    if not cond:
        raise PackError(message)


def _text(d: dict, key: str, where: str) -> str:
    v = d.get(key)
    _need(isinstance(v, str) and v.strip() != "", f"{where} needs {key}, written as words.")
    return v


def _int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def _square(v, columns: int, rows: int, where: str, what: str) -> tuple[int, int]:
    _need(isinstance(v, list) and len(v) == 2 and all(_int(n) for n in v),
          f"{where}: {what} needs a square written as [x, y].")
    x, y = v
    _need(0 <= x < columns and 0 <= y < rows,
          f"{where}: {what} [{x}, {y}] is off the {columns} x {rows} board.")
    return (x, y)


def _row(v, deck: Deck, where: str, what: str) -> tuple[Entry, ...]:
    _need(isinstance(v, list), f"{where}: {what} is a list of cards.")
    out = []
    for e in v:
        _need(isinstance(e, dict) and isinstance(e.get("card"), str),
              f"{where}: every card in {what} needs a card code.")
        code = e["card"]
        under = e.get("under", [])
        _need(isinstance(under, list) and all(isinstance(u, str) for u in under),
              f"{where}: under {code} in {what} is not a list of card codes.")
        for c in (code, *under):
            try:
                deck.by_code(c)
            except KeyError:
                raise PackError(f"{where}: {what} holds {c!r}, which is not a card in the deck.") from None
        times = e.get("times")
        if code == "repeat":
            _need(_int(times) and 1 <= times <= REPEAT_MOST,
                  f"{where}: a Repeat in {what} needs times, 1 to {REPEAT_MOST}.")
        else:
            _need(times is None, f"{where}: only a Repeat takes times, and {what} gives one to {code}.")
        _need(code not in ("start", "end"),
              f"{where}: {what} is the row between Start and End, so it leaves them out.")
        out.append(Entry(card=code, under=tuple(under), times=times))
    return tuple(out)


def _challenge(c, board: Board, cards: tuple[str, ...], deck: Deck, n: int) -> Challenge:
    _need(isinstance(c, dict), f"Challenge {n} is not written as a challenge.")
    cid = c.get("id")
    _need(isinstance(cid, str) and bool(ID.match(cid)),
          f"Challenge {n} needs an id in small letters, numbers and dashes, like pond-3.")
    where = cid
    name = _text(c, "name", where)
    columns = c.get("columns", board.columns)
    rows = c.get("rows", board.rows)
    _need(_int(columns) and _int(rows) and 1 <= columns <= LARGEST_BOARD and 1 <= rows <= LARGEST_BOARD,
          f"{where}: a board is 1 to {LARGEST_BOARD} squares each way.")
    start = c.get("start")
    _need(isinstance(start, dict), f"{where} needs a start: a square and a facing.")
    at = _square(start.get("at"), columns, rows, where, "the start")
    facing = start.get("facing")
    _need(facing in FACINGS, f"{where}: the start faces north, east, south or west.")
    goal = _square(c.get("goal"), columns, rows, where, "the goal")
    walls = set()
    for w in c.get("walls") or []:
        between = w.get("between") if isinstance(w, dict) else None
        _need(isinstance(between, list) and len(between) == 2, f"{where}: a wall sits between two squares.")
        a = _square(between[0], columns, rows, where, "a wall")
        b = _square(between[1], columns, rows, where, "a wall")
        _need(abs(a[0] - b[0]) + abs(a[1] - b[1]) == 1,
              f"{where}: a wall sits between two squares that share an edge, and "
              f"[{a[0]}, {a[1]}] and [{b[0]}, {b[1]}] do not.")
        walls.add(frozenset((a, b)))
    gates = []
    for g in c.get("gates") or []:
        _need(isinstance(g, dict), f"{where}: a gate needs a square and an axis.")
        gat = _square(g.get("at"), columns, rows, where, "a gate")
        _need(g.get("axis") in AXES, f"{where}: a gate's axis is ns or ew.")
        _need(gat != at, f"{where}: a gate on the start square can never be walked into.")
        gates.append(Gate(at=gat, axis=g["axis"]))
    finish = c.get("finish_with")
    if finish is not None:
        _need(isinstance(finish, str) and finish in cards,
              f"{where}: finish_with must be a card in play.")
        _need(finish not in MOVES and finish not in ("start", "end", "repeat", "end_repeat"),
              f"{where}: finish_with is a card the duck does standing still, like Hello.")
    par = c.get("par")
    _need(_int(par) and par >= 0, f"{where} needs a par, a whole number.")
    solution = _row(c.get("solution"), deck, where, "the solution")
    buggy = c.get("buggy")
    buggy = None if buggy is None else _row(buggy, deck, where, "the buggy row")
    hint = _text(c, "hint", where)
    return Challenge(id=cid, name=name, columns=columns, rows=rows, start=Place(at, facing), goal=goal,
                     walls=frozenset(walls), gates=tuple(gates), finish_with=finish, par=par,
                     solution=solution, buggy=buggy, hint=hint)


def challenge_of(c: dict, board: Board, cards, deck: Deck) -> Challenge:
    """One challenge read on its own, as a vector carries it."""
    return _challenge(c, board, tuple(cards), deck, 1)


def _read(data, deck: Deck) -> Pack:
    if isinstance(data, (bytes, str)):
        try:
            data = json.loads(data)
        except ValueError:
            raise PackError("This file is not a Duck Cards pack: it is not JSON.") from None
    _need(isinstance(data, dict) and data.get("format") == FORMAT,
          f"This file is not a Duck Cards pack: its format is not {FORMAT}.")
    pid = data.get("id")
    _need(isinstance(pid, str) and bool(ID.match(pid)),
          "The pack needs an id in small letters, numbers and dashes, like get-to-the-pond.")
    for key in ("name", "grades", "about", "license", "credit"):
        _text(data, key, "The pack")
    lo, hi = data.get("grade_from"), data.get("grade_to")
    _need(_int(lo) and _int(hi) and lo in GRADES and hi in GRADES and lo <= hi,
          "The pack's grades run from grade_from to grade_to: PreK is -1, K is 0, then 1 to 12.")
    _need(data.get("vocabulary") == deck.vocabulary,
          f"The pack is written for vocabulary {data.get('vocabulary')!r}, and this deck is "
          f"{deck.vocabulary!r}.")
    score = data.get("score")
    _need(score in SCORES, "The pack's score is steps or cards.")

    # Your cards first: a solution may hold them, so the deck it is read against must have them.
    yours = data.get("yours") or []
    _need(isinstance(yours, list), "The pack's yours is a list of Your cards.")
    lo_y, hi_y = deck.yours_range
    for y in yours:
        _need(isinstance(y, dict) and _int(y.get("tag")) and lo_y <= y["tag"] <= hi_y
              and y.get("kind") == "yours",
              f"Every card in yours is a Your card, numbered {lo_y} to {hi_y}.")
        _need(y.get("code") == deck.card(y["tag"]).code,
              f"Your card {y['tag']} is called {deck.card(y['tag']).code}, not {y.get('code')!r}.")
        _need(isinstance(y.get("row"), list) and len(y["row"]) > 0,
              f"Your card {y['tag']} in this pack needs the row it stands for.")
        _text(y, "name", f"Your card {y['tag']}")
    tags = [y["tag"] for y in yours]
    _need(len(set(tags)) == len(tags), "Two Your cards in this pack have the same number.")
    probe = Pack(data=data, id=pid, name=data["name"], grades=data["grades"], grade_from=lo, grade_to=hi,
                 vocabulary=data["vocabulary"], about=data["about"], cards=(), score=score, board=None,
                 challenges=(), lessons=(), yours=tuple(yours))
    try:
        played, _ = probe.lend(deck, replace=True)
    except DeckError as e:
        raise PackError(f"A Your card in this pack cannot be read: {e}.") from None

    cards = data.get("cards")
    _need(isinstance(cards, list) and all(isinstance(c, str) for c in cards),
          "The pack's cards is a list of card codes.")
    for code in cards:
        try:
            played.by_code(code)
        except KeyError:
            raise PackError(f"The pack plays {code!r}, which is not a card in the deck.") from None
    _need(len(set(cards)) == len(cards), "The pack names a card in play twice.")
    _need("start" in cards and "end" in cards, "Every pack plays Start and End.")

    b = data.get("board")
    _need(isinstance(b, dict), "The pack needs a board.")
    columns, rows = b.get("columns"), b.get("rows")
    _need(_int(columns) and _int(rows) and 1 <= columns <= LARGEST_BOARD and 1 <= rows <= LARGEST_BOARD,
          f"The pack's board is 1 to {LARGEST_BOARD} squares each way.")
    square = b.get("square_cm")
    _need(isinstance(square, (int, float)) and not isinstance(square, bool) and square > 0,
          "The board's square_cm is the size of a printed square, in centimetres.")
    duck = b.get("duck_square_cm")
    _need(duck is None or (isinstance(duck, (int, float)) and not isinstance(duck, bool) and duck > 0),
          "duck_square_cm is null until one Walk forward has been measured, then centimetres.")
    board = Board(columns=columns, rows=rows, square_cm=square, duck_square_cm=duck)

    raw = data.get("challenges")
    _need(isinstance(raw, list) and len(raw) > 0, "The pack needs at least one challenge.")
    challenges = tuple(_challenge(c, board, tuple(cards), played, n + 1) for n, c in enumerate(raw))
    ids = [c.id for c in challenges]
    _need(len(set(ids)) == len(ids), "Two challenges in this pack have the same id.")

    lessons = []
    for le in data.get("lessons") or []:
        _need(isinstance(le, dict), "Every lesson has a title, a skill, a body and a question to ask.")
        lessons.append(Lesson(**{k: _text(le, k, "A lesson") for k in ("title", "skill", "body", "ask")}))
    return Pack(data=data, id=pid, name=data["name"], grades=data["grades"], grade_from=lo, grade_to=hi,
                vocabulary=data["vocabulary"], about=data["about"], cards=tuple(cards), score=score,
                board=board, challenges=challenges, lessons=tuple(lessons), yours=tuple(yours))


def bundled(deck: Deck) -> list[Pack]:
    """The starter packs this reader carries, youngest grades first."""
    packs = [Pack.load(p, deck) for p in sorted(PACKS.glob(f"*.{EXTENSION}"))]
    return sorted(packs, key=lambda p: (p.grade_from, p.grade_to, p.id))


# ---------------------------------------------------------------------------------------------
# a row, as steps and as cards

def steps_of(row, deck: Deck) -> list[Step]:
    """The steps a saved row makes, by the reader's own rules (`program.table`, then `read`)."""
    return read(table(row, deck), deck).steps


def card_count(row) -> int:
    """Cards laid between Start and End: every card, Repeat and End repeat among them, and every
    card under one. A Your card is one card, which is what it is for."""
    return sum(1 + len(e.under) for e in row)


# ---------------------------------------------------------------------------------------------
# the board

def _turn(facing: str, by: int) -> str:
    return FACINGS[(FACINGS.index(facing) + by) % 4]


def _walk(ch: Challenge, at: tuple[int, int], way: tuple[int, int]) -> tuple[int, int] | str:
    """Where a walk from `at` lands, or why it does not: "edge" or "wall"."""
    to = (at[0] + way[0], at[1] + way[1])
    if not (0 <= to[0] < ch.columns and 0 <= to[1] < ch.rows):
        return "edge"
    if frozenset((at, to)) in ch.walls:
        return "wall"
    return to


def _axis(way: tuple[int, int]) -> str:
    return "ns" if way[0] == 0 else "ew"


def _gates_at(ch: Challenge, to: tuple[int, int], way: tuple[int, int]) -> list[int]:
    return [k for k, g in enumerate(ch.gates) if g.at == to and g.axis == _axis(way)]


def _name(code: str, deck: Deck | None) -> str:
    if deck is None:
        return code
    try:
        return deck.by_code(code).name
    except KeyError:
        return code


def open_repeats(row) -> int:
    """Repeat cards in a row with no End repeat to close them. The reader still runs such a row
    (the Repeat goes on to the end of the row, and it says so), but the board does not count it as
    solved: a loop is Repeat and End repeat, and a par that a missing card could beat would teach
    the missing card."""
    depth = 0
    for e in row:
        if e.card == "repeat":
            depth += 1
        elif e.card == "end_repeat" and depth:
            depth -= 1
    return depth


def play(ch: Challenge, steps: list[Step], cards: int, score: str, deck: Deck | None = None,
         unclosed: int = 0) -> dict:
    """A program played on the challenge's board, by the board rule. The JSON both readers make.

    A BUMP STOPS THE PLAY. A walk into a wall or off the board leaves the duck where it was, and
    nothing after it is played, because a class watching a duck walk into a wall needs to know
    which card did it, not where the rest of the row would have gone."""
    at, facing = ch.start.at, ch.start.facing
    path = [Place(at, facing).json()]
    passed: set[int] = set()
    bumped, why = None, None
    for i, step in enumerate(steps, start=1):
        action = step.action
        if action in ("walk_forward", "walk_backward"):
            dx, dy = AHEAD[facing]
            way = (dx, dy) if action == "walk_forward" else (-dx, -dy)
            to = _walk(ch, at, way)
            if isinstance(to, str):
                bumped, why = i, to
                break
            at = to
            passed.update(_gates_at(ch, at, way))
        elif action == "turn_left":
            facing = _turn(facing, -1)
        elif action == "turn_right":
            facing = _turn(facing, 1)
        path.append(Place(at, facing).json())
    count = len(steps)
    missed = len(ch.gates) - len(passed)
    finished = ch.finish_with is None or (bool(steps) and steps[-1].cards[0] == ch.finish_with)
    solved = bumped is None and bool(steps) and at == ch.goal and missed == 0 and finished and not unclosed
    value = count if score == "steps" else cards
    if bumped is not None:
        said = (f"Bumped into a wall on step {bumped}." if why == "wall"
                else f"Bumped into the edge of the board on step {bumped}.")
    elif not steps:
        said = "The row has no steps to play."
    elif at != ch.goal:
        away = abs(at[0] - ch.goal[0]) + abs(at[1] - ch.goal[1])
        said = f"The duck ended {away} square{'s' if away > 1 else ''} away from the goal."
    elif missed:
        said = f"The duck reached the goal but missed {missed} gate{'s' if missed > 1 else ''}."
    elif not finished:
        said = f"The duck reached the goal but did not finish with {_name(ch.finish_with, deck)}."
    elif unclosed:
        said = "The duck reached the goal, but a Repeat has no End repeat. Close every loop."
    else:
        unit = "steps" if score == "steps" else "cards"
        how = "in" if score == "steps" else "with"
        if value == ch.par:
            said = f"Solved {how} {value} {unit}, which is par."
        elif value > ch.par:
            said = f"Solved {how} {value} {unit}. Par is {ch.par}, so a shorter row is out there."
        else:
            said = f"Solved {how} {value} {unit}, under par {ch.par}. Tell whoever wrote the challenge."
    return {"solved": solved, "path": path, "bumped_at": bumped, "gates_passed": sorted(passed),
            "ended": Place(at, facing).json(), "steps": count, "cards": cards, "score": value,
            "par": ch.par, "said": said}


def play_entries(ch: Challenge, row, score: str, deck: Deck) -> dict:
    """A saved row played on a challenge, scored by `score`. The deck should already hold the
    pack's Your cards (`Pack.lend`)."""
    return play(ch, steps_of(row, deck), card_count(row), score, deck, open_repeats(row))


def play_row(pack: Pack, ch: Challenge, row, deck: Deck) -> dict:
    return play_entries(ch, row, pack.score, deck)


def par_steps(ch: Challenge, moves) -> int | None:
    """The fewest board steps that solve the challenge, by breadth-first search over (square,
    facing, gates passed), with the moving cards in play. One more if it must finish with a card.
    None when the goal cannot be reached with every gate passed."""
    moves = [m for m in MOVES if m in moves]
    full = (1 << len(ch.gates)) - 1
    first = (ch.start.at, ch.start.facing, 0)
    seen = {first: 0}
    todo = deque([first])
    extra = 0 if ch.finish_with is None else 1
    while todo:
        state = todo.popleft()
        at, facing, mask = state
        if at == ch.goal and mask == full:
            return seen[state] + extra
        for m in moves:
            if m in ("turn_left", "turn_right"):
                nxt = (at, _turn(facing, -1 if m == "turn_left" else 1), mask)
            else:
                dx, dy = AHEAD[facing]
                way = (dx, dy) if m == "walk_forward" else (-dx, -dy)
                to = _walk(ch, at, way)
                if isinstance(to, str):
                    continue
                nm = mask
                for k in _gates_at(ch, to, way):
                    nm |= 1 << k
                nxt = (to, facing, nm)
            if nxt not in seen:
                seen[nxt] = seen[state] + 1
                todo.append(nxt)
    return None


def par(pack: Pack, ch: Challenge) -> int | None:
    """Par as the pack scores it. For steps, the search; for cards, what the author found, and
    the checks hold the solution to it."""
    return par_steps(ch, pack.cards) if pack.score == "steps" else ch.par


def swaps(pack: Pack, row, deck: Deck) -> list[tuple[int, str, tuple[Entry, ...]]]:
    """Every row one card swap away: one card that does something on its own (a move, a sound, a
    trick or a Your card) replaced by another such card in play, its under-cards kept. This is
    the cards page's Find the bug: one wrong card, fixed with a single swap."""
    def swappable(code):
        return deck.by_code(code).kind in ("action", "yours")
    out = []
    for i, e in enumerate(row):
        if not swappable(e.card):
            continue
        for code in pack.cards:
            if code == e.card or not swappable(code):
                continue
            out.append((i, code, tuple(row[:i]) + (Entry(card=code, under=e.under),) + tuple(row[i + 1:])))
    return out


# ---------------------------------------------------------------------------------------------
# the card reader with a pack (`python3 -m duckcards watch --pack ...`)

def listed(items: list[str]) -> str:
    """Words joined the way a sentence lists them: a, b and c."""
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " and " + items[-1]


def find(path_or_id: str, deck: Deck) -> Pack:
    """A pack named the way a person types it: a `.duckpack` file, or the id of a starter pack this
    reader carries. Refused with a sentence that says which, and what the starter packs are."""
    path = pathlib.Path(path_or_id).expanduser()
    if not path.is_file() and ID.match(path_or_id) and (PACKS / f"{path_or_id}.{EXTENSION}").is_file():
        path = PACKS / f"{path_or_id}.{EXTENSION}"
    if not path.is_file():
        ids = sorted(p.stem for p in PACKS.glob(f"*.{EXTENSION}"))
        raise PackError(f"There is no pack file at {path_or_id}, and no starter pack is called that. "
                        f"The starter packs are {listed(ids)}.")
    try:
        data = path.read_bytes()
    except OSError as e:
        raise PackError(f"The pack {path_or_id} could not be opened: {e.strerror or e}.") from None
    return Pack.read(data, deck)


def lent_words(pack: Pack, deck: Deck, clashes: list[int]) -> list[str]:
    """What lending a pack's Your cards did, for the reader to say. The class deck's own card wins
    a clash, as it does in Studio until someone there chooses to replace it."""
    if not pack.yours:
        return []
    kept = set(clashes)
    lent = [f"{y['tag']} {y['name']}" for y in pack.yours if y["tag"] not in kept]
    out = []
    if lent:
        out.append(f"{pack.name} lends its Your card{'s' if len(lent) > 1 else ''}: {'; '.join(lent)}.")
    if clashes:
        nums = listed([str(t) for t in clashes])
        one = len(clashes) == 1
        out.append(f"The class deck already saved something else for card{'' if one else 's'} {nums}, so "
                   f"{'it keeps' if one else 'they keep'} the class's own meaning, not {pack.name}'s.")
    return out


def outside(pack: Pack, program, deck: Deck) -> list[str]:
    """Notes for the cards a program laid that the pack does not play. They still run: a pack
    narrows what is printed and offered, not what a duck may do."""
    return pack.not_in_play(program.laid, deck)


# Said beside every board play the reader prints. The board rule is exact; the duck is not, and
# nothing watched where the duck itself stopped.
NOT_THE_DUCK = "This is the board's answer for the row (one Walk card, one square), not where the duck stopped."
UNMEASURED = " One Walk card has not been measured on a duck yet."


def report(pack: Pack, ch: Challenge, program, deck: Deck) -> tuple[dict, list[str]]:
    """The board play of a row the reader ran, and the lines it says about it. The row is played
    as laid: the steps the reader made, the cards between Start and End, any Repeat left open."""
    result = play(ch, program.steps, card_count(program.row), pack.score, deck, open_repeats(program.row))
    unit = "steps" if pack.score == "steps" else "cards"
    lines = [f"[board] {ch.name} ({ch.id}): {result['said']}",
             f"[board] {'solved' if result['solved'] else 'not solved'}, score {result['score']} {unit}, "
             f"par {result['par']}.",
             "[board] " + NOT_THE_DUCK + (UNMEASURED if pack.board.duck_square_cm is None else "")]
    return result, lines


__all__ = ["FORMAT", "EXTENSION", "PACKS", "MAX_STEPS", "PackError", "Pack", "Challenge", "Place", "Gate",
           "Board", "Lesson", "bundled", "steps_of", "card_count", "play", "play_row", "play_entries", "open_repeats", "lend_yours", "entries", "par_steps", "par",
           "swaps", "challenge_of", "find", "lent_words", "outside", "report"]
