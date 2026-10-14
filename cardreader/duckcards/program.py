"""Rows of cards, as the steps a duck runs and the plan Studio reads.

THE PLAN IS STUDIO'S OWN FORMAT. What comes out is `duck-intent-plan/0`, the
file `DuckIntentPlan.read` takes from the plain-language router, with
`model: "duck-cards/0"`. So a row the duck read for itself and a row Studio
read through the duck's camera become the same plan, `RobotPlan` turns either
into the same calls, and the plan editor shows either as a chain a person can
change before anything moves. `check_plan` holds every plan to the rules
`DuckIntentPlan.read` enforces, label for label.

WHAT A PLAN CANNOT SAY STAYS BESIDE IT. `duck-intent-plan/0` has no loops and
no events. Repeat is unrolled into the steps it repeats. When it falls is kept
as a second list, `on_fall`, which the duck's own runner watches for and Studio
does not run yet; the program says so in its notes rather than dropping it.

A ROW SAYS WHAT IT DID WITH EVERY CARD. A Slow under a kick, a Your card nobody
has given a meaning, a Start with no End: each is a note in the duck's words,
because "it ignored my card" is the bug a class should be able to find.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field

from .cards import Card
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

# How many times Repeat repeats when nothing can read the number written on it.
REPEAT_TIMES = 2
# A plan on a duck is held to this many steps after unrolling, so a Repeat inside a Repeat
# cannot become a plan nobody is watching the end of. RobotPlan holds the seconds; this the count.
MAX_STEPS = 40


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
    complete: bool                  # a Start and an End were both read, or a single card was
    kind: str                       # "row", "card" or "none"

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


def _compile(slots: list[Slot], notes: list[str], yours: dict[int, list[str]], deck) -> list[Step]:
    """Slots to steps: Repeat unrolled, Your cards looked up, everything else said."""
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
            notes.append(f"Nothing reads the number written on Repeat yet, so it repeats "
                         f"{REPEAT_TIMES} times.")
            inner = _compile(body, notes, yours, deck)
            for _ in range(REPEAT_TIMES):
                out.extend(inner)
            i = j
            continue
        if card.code == "end_repeat":
            notes.append("End repeat has no Repeat before it, so it was skipped.")
        elif card.kind == "yours":
            meaning = yours.get(card.tag)
            if not meaning:
                notes.append(f"Your card {card.tag} has no meaning saved yet, so it was skipped.")
            else:
                inner = [Slot(card=_seen_like(deck.by_code(code))) for code in meaning]
                out.extend(_compile(inner, notes, yours, deck))
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


def _seen_like(card: Card):
    from .cards import Seen
    return Seen(card=card, corners=[(0, 0)] * 4)


def read(layout: Layout, yours: dict[int, list[str]] | None = None, deck=None) -> Program:
    """The program in a picture's rows.

    THE PROGRAM IS THE ROW WITH START IN IT. Between Start and End, left to right, is what runs.
    A row that begins with When it falls is what runs after a fall. With no Start anywhere, one
    card on its own is a program of one step, which is how holding up a card works; several cards
    with no Start are not a program yet, and the duck says so rather than guessing which you
    meant."""
    yours = yours or {}
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
    on_fall: list[Step] = []
    if fall_row is not None:
        body = fall_row.slots[1:]
        ends = [k for k, s in enumerate(body) if s.card.card.code == "end"]
        on_fall = _compile(body[:ends[0]] if ends else body, notes, yours, deck)
    if main is None:
        actions = [s for r in layout.rows if r is not fall_row for s in r.slots
                   if s.card.card.kind in ("action", "yours")]
        others = [s for r in layout.rows if r is not fall_row for s in r.slots
                  if s.card.card.kind not in ("action", "yours")]
        if len(actions) == 1 and not [o for o in others if o.card.card.kind == "control"]:
            steps = _compile(actions, notes, yours, deck)
            return Program(steps=steps, on_fall=on_fall, notes=notes, complete=bool(steps), kind="card")
        if actions:
            notes.append("These cards have no Start, so there is no row to run yet.")
        return Program(steps=[], on_fall=on_fall, notes=notes, complete=False, kind="none")
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
    steps = _compile(body, notes, yours, deck)
    if len(steps) > MAX_STEPS:
        notes.append(f"The row unrolls to {len(steps)} steps; a duck runs at most {MAX_STEPS}.")
        steps = steps[:MAX_STEPS]
    return Program(steps=steps, on_fall=on_fall, notes=notes, complete=end is not None and bool(steps),
                   kind="row")


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
