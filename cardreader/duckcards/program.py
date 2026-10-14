"""Rows of cards, as the steps a duck runs and the plan Studio reads.

THE PLAN IS STUDIO'S OWN FORMAT. What comes out is `duck-intent-plan/0`, the
file `DuckIntentPlan.read` takes from the plain-language router, with
`model: "duck-cards/0"`. So a row the duck read for itself and a row Studio
read through the duck's camera become the same plan, `RobotPlan` turns either
into the same calls, and the plan editor shows either as a chain a person can
change before anything moves. `check_plan` holds every plan to the rules
`DuckIntentPlan.read` enforces, label for label.

WHAT A PLAN CANNOT SAY STAYS BESIDE IT. `duck-intent-plan/0` has no loops and
no events. Repeat is unrolled into the steps it repeats, as many times as the
number written on it says. When it falls is kept as a second list, `on_fall`,
which the duck's own runner watches for and Studio does not run yet. A Your
card is opened into the row its deck saved for it, which may hold Your cards
of its own.

A ROW SAYS WHAT IT DID WITH EVERY CARD. A Slow under a kick, a Your card nobody
has given a meaning, a Start with no End: each is a note in the duck's words,
because "it ignored my card" is the bug a class should be able to find. What
the reader cannot decide alone, a Repeat whose number it cannot read, it asks
(`Program.asks`), and the row waits for the answer.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field

from .cards import REPEAT_MOST, Card, Deck, Seen
from .layout import Layout, Row, Slot

FORMAT = "duck-intent-plan/0"
MODEL = "duck-cards/0"

# DuckIntentPlan.Vocabulary, r001, word for word.
ACTIONS = ["walk_forward", "walk_backward", "turn_left", "turn_right", "stop", "kick_left",
           "kick_right", "sit_or_stand", "roll", "peck_ground", "make_sound", "unsupported"]
SPEEDS = ["slow", "normal", "fast"]
HEADS = ["straight", "look_left", "look_right", "look_up", "look_down"]
SOUNDS = ["greet", "alarm", "inquire", "peck", "chirp", "coo", "wheee"]
VOCABULARY = {"action": ACTIONS, "speed": SPEEDS, "head": HEADS, "sound": SOUNDS}

# Which heads an action carries (DuckIntentPlan.Node.heads): a walk or turn takes a speed and a
# head, a stop takes a head, a sound takes its sound, and a trick takes nothing under it.
CARRIES = {"walk_forward": {"speed", "head"}, "walk_backward": {"speed", "head"},
           "turn_left": {"speed", "head"}, "turn_right": {"speed", "head"}, "stop": {"head"},
           "make_sound": {"sound"}}

# A plan on a duck is held to this many steps after unrolling, so a Repeat inside a Repeat
# cannot become a plan nobody is watching the end of. RobotPlan holds the seconds; this the count.
MAX_STEPS = 40
# A Your card may hold Your cards, and those may hold more, this many deep and no deeper.
YOURS_DEPTH = 4


@dataclass
class Step:
    labels: dict[str, str]
    clause: str
    cards: list[str]                 # the codes it came from, the card first, then anything under it

    @property
    def action(self) -> str:
        return self.labels["action"]


@dataclass
class Program:
    steps: list[Step]
    on_fall: list[Step]
    notes: list[str]
    complete: bool                  # a Start and an End were read, or a single card, and nothing is asked
    kind: str                       # "row", "card" or "none"
    # The Repeat cards whose number nobody could read, counted along the row from 0 (then along
    # the When it falls row). The row waits for these: Studio asks, the duck asks with a sound.
    asks: list[int] = field(default_factory=list)

    @property
    def words(self) -> str:
        """The row read back the way the cards page reads its example."""
        return " ".join(s.clause + "." for s in self.steps)


def _clause(card: Card, under: list[Card]) -> str:
    parts = [card.name]
    for u in under:
        parts.append(u.name.lower())
    return ", ".join(parts)


def _step(slot: Slot, notes: list[str]) -> Step | None:
    card = slot.card.card
    labels = dict(card.plan or {})
    if "action" not in labels:
        return None
    carries = CARRIES.get(labels["action"], set())
    kept: list[Card] = []
    for u in slot.under:
        head, value = next(iter((u.card.plan or {}).items()), (None, None))
        if head is None:
            continue
        if head not in carries:
            notes.append(f"{card.name} takes nothing under it, so {u.card.name} was not used.")
            continue
        if head in labels and labels[head] != value:
            notes.append(f"{card.name} has two {head} cards under it; the first was used.")
            continue
        labels[head] = value
        kept.append(u.card)
    for head in ("speed", "head"):
        if head in carries and head not in labels:
            labels[head] = "normal" if head == "speed" else "straight"
    return Step(labels=labels, clause=_clause(card, kept),
                cards=[card.code] + [u.code for u in kept])


class _Reading:
    """What one read keeps across the rows it compiles: the deck, the answers given for Repeat
    numbers, how many Repeat cards have been met, and which of them are still asked about."""

    def __init__(self, deck: Deck, counts: dict[int, int] | None):
        self.deck = deck
        self.counts = dict(counts or {})
        self.repeats = 0
        self.asks: list[int] = []


def _saved(card: Card, times: int | None = None) -> Seen:
    """A card from a saved row: where it lies does not matter, only what it is."""
    return Seen(card=card, corners=[], count=times)


def _times(slot: Slot, notes: list[str], state: _Reading, saved: bool) -> int:
    """How many times a Repeat repeats.

    THE NUMBER IS WRITTEN ON THE CARD, AND A READER THAT CANNOT READ IT ASKS. That is the cards
    page's rule. A saved row carries its numbers. On the table, an answer someone gave wins, then
    a number read off the card (said back, because handwriting is read, not known), and otherwise
    the Repeat is asked about and the row waits; meanwhile what it holds is shown once."""
    if saved:
        return slot.card.count or 1
    index = state.repeats
    state.repeats += 1
    answered = state.counts.get(index)
    if isinstance(answered, int) and 1 <= answered <= REPEAT_MOST:
        return answered
    read_off = slot.card.count
    if isinstance(read_off, int) and 1 <= read_off <= REPEAT_MOST:
        notes.append(f"Repeat says {read_off} times.")
        return read_off
    state.asks.append(index)
    notes.append("Repeat has no number that could be read, so the row waits for one.")
    return 1


def _compile(slots: list[Slot], notes: list[str], state: _Reading, inside: tuple[int, ...] = ()) -> list[Step]:
    """Slots to steps: Repeat unrolled, Your cards opened, everything else said. `inside` is the
    Your cards being opened, outermost first, when these slots are a saved row."""
    out: list[Step] = []
    i = 0
    while i < len(slots):
        slot = slots[i]
        card = slot.card.card
        if card.code == "repeat":
            depth, j = 1, i + 1
            while j < len(slots) and depth:
                code = slots[j].card.card.code
                depth += {"repeat": 1, "end_repeat": -1}.get(code, 0)
                j += 1
            body = slots[i + 1:j - 1] if depth == 0 else slots[i + 1:j]
            if depth:
                notes.append("Repeat has no End repeat after it, so it repeats to the end of the row.")
            times = _times(slot, notes, state, saved=bool(inside))
            inner = _compile(body, notes, state, inside)
            for _ in range(times):
                out.extend(inner)
            i = j
            continue
        if card.code == "end_repeat":
            notes.append("End repeat has no Repeat before it, so it was skipped.")
        elif card.kind == "yours":
            out.extend(_open(card, notes, state, inside))
        elif card.kind == "event":
            notes.append(f"{card.name} starts a row of its own; in the middle of a row it was skipped.")
        elif card.kind == "modifier":
            notes.append(f"{card.name} is not under any card, so it was not used.")
        elif card.kind == "control":
            notes.append(f"A second {card.name} in the row was skipped.")
        else:
            step = _step(slot, notes)
            if step:
                out.append(step)
        i += 1
    return out


def _open(card: Card, notes: list[str], state: _Reading, inside: tuple[int, ...]) -> list[Step]:
    """A Your card, opened into the row its deck saved for it.

    A ROUTINE CAN CALL A ROUTINE, FOUR DEEP, AND NEVER ITSELF. The cards page's spec: the read
    stops on a loop, naming both cards, and below a depth of four. A card that is skipped says
    which card it was, because a class looking at a duck that did nothing needs the number.
    The meaning is looked up in the deck this read was given, whichever deck found the code."""
    tag = card.tag
    card = state.deck.card(tag) or card
    if tag in inside:
        holder = inside[-1]
        if holder == tag:
            notes.append(f"Your card {tag} holds itself, so the loop was cut there.")
        else:
            notes.append(f"Your card {holder} holds Your card {tag}, which leads back to {holder}, "
                         "so the loop was cut there.")
        return []
    if len(inside) >= YOURS_DEPTH:
        notes.append(f"Your card {tag} sits more than {YOURS_DEPTH} Your cards deep, so it was skipped.")
        return []
    if not card.row:
        notes.append(f"Your card {tag} has no meaning saved yet, so it was skipped.")
        return []
    deck = state.deck
    slots = [Slot(card=_saved(deck.by_code(e.card), e.times),
                  under=[_saved(deck.by_code(u)) for u in e.under]) for e in card.row]
    return _compile(slots, notes, state, inside + (tag,))


def read(layout: Layout, deck: Deck, counts: dict[int, int] | None = None) -> Program:
    """The program in a picture's rows.

    THE PROGRAM IS THE ROW WITH START IN IT. Between Start and End, left to right, is what runs.
    A row that begins with When it falls is what runs after a fall. With no Start anywhere, one
    card on its own is a program of one step, which is how holding up a card works; several cards
    with no Start are not a program yet, and the duck says so rather than guessing which you
    meant.

    `counts` answers Repeat numbers nobody could read: {position: times}, positions as
    `Program.asks` gives them."""
    state = _Reading(deck, counts)
    notes: list[str] = []
    main: Row | None = None
    fall_row: Row | None = None
    for row in layout.rows:
        codes = row.codes
        if codes and codes[0] == "when_falls":
            fall_row = fall_row or row
        elif "start" in codes and main is None:
            main = row
    if layout.turned:
        names = ", ".join(s.card.name for s in layout.turned)
        notes.append(f"Turned the other way from the rest, so not read: {names}.")
    end = None
    if main is None:
        actions = [s for r in layout.rows if r is not fall_row for s in r.slots
                   if s.card.card.kind in ("action", "yours")]
        others = [s for r in layout.rows if r is not fall_row for s in r.slots
                  if s.card.card.kind not in ("action", "yours")]
        if len(actions) == 1 and not [o for o in others if o.card.card.kind == "control"]:
            kind, steps = "card", _compile(actions, notes, state)
        else:
            if actions:
                notes.append("These cards have no Start, so there is no row to run yet.")
            kind, steps = "none", []
    else:
        kind = "row"
        codes = main.codes
        start = codes.index("start")
        end = codes.index("end", start) if "end" in codes[start:] else None
        if start > 0:
            notes.append("Cards before Start are not part of the row.")
        if end is None:
            notes.append("There is a Start but no End yet.")
            body = main.slots[start + 1:]
        else:
            if end + 1 < len(codes):
                notes.append("Cards after End are not part of the row.")
            body = main.slots[start + 1:end]
        steps = _compile(body, notes, state)
        if len(steps) > MAX_STEPS:
            notes.append(f"The row unrolls to {len(steps)} steps; a duck runs at most {MAX_STEPS}.")
            steps = steps[:MAX_STEPS]
    on_fall: list[Step] = []
    if fall_row is not None:
        body = fall_row.slots[1:]
        ends = [k for k, s in enumerate(body) if s.card.card.code == "end"]
        on_fall = _compile(body[:ends[0]] if ends else body, notes, state)
    if kind == "card":
        complete = bool(steps) and not state.asks
    elif kind == "row":
        complete = end is not None and bool(steps) and not state.asks
    else:
        complete = False
    # Two Repeats nobody could read, or two loose Speed cards, are said once: a note explains, and
    # `asks` keeps the count.
    said = list(dict.fromkeys(notes))
    return Program(steps=steps, on_fall=on_fall, notes=said, complete=complete, kind=kind,
                   asks=list(state.asks))


def plan(program: Program, steps: list[Step] | None = None) -> dict:
    """`duck-intent-plan/0`, as `DuckIntentPlan.read` takes it. A card is not a guess, so every
    label is sent at confidence 1.0, and nothing is flagged for being unsure."""
    steps = program.steps if steps is None else steps
    return {
        "format": FORMAT,
        "request": " ".join(s.clause + "." for s in steps),
        "model": MODEL,
        "steps": [{"clause": s.clause, "labels": dict(s.labels),
                   "confidence": {k: 1.0 for k in s.labels}} for s in steps],
    }


class PlanError(ValueError):
    pass


def check_plan(data: dict | str | bytes) -> dict:
    """Every rule `DuckIntentPlan.read` applies, in its order, with its refusals."""
    if isinstance(data, (str, bytes)):
        try:
            data = json.loads(data)
        except ValueError:
            raise PlanError("notJSON")
    if not isinstance(data, dict):
        raise PlanError("notJSON")
    if not isinstance(data.get("format"), str):
        raise PlanError("missing format")
    if data["format"] != FORMAT:
        raise PlanError(f"wrongFormat {data['format']}")
    if not isinstance(data.get("request"), str):
        raise PlanError("missing request")
    steps = data.get("steps")
    if not isinstance(steps, list):
        raise PlanError("missing steps")
    if not steps:
        raise PlanError("noSteps")
    for step in steps:
        if not isinstance(step.get("clause"), str):
            raise PlanError("missing clause")
        labels = step.get("labels")
        if not isinstance(labels, dict) or not all(isinstance(v, str) for v in labels.values()):
            raise PlanError(f"missing labels for {step['clause']!r}")
        if "action" not in labels:
            raise PlanError(f"missing action for {step['clause']!r}")
        for head, label in labels.items():
            if head in VOCABULARY and label not in VOCABULARY[head]:
                raise PlanError(f"unknownLabel {head} {label}")
    return data
