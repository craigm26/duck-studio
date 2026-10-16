"""The rows the Monte Carlo runs: every starter pack challenge's `solution` (each pack's Your
cards lent, Repeat unrolled, by the reader's own `packs.steps_of`), plus the hand-written rows
duckbench measured (F F L F R F; F L L F; F F B; L L R R; F F F F; F R F R F R F R).

    python3 cardreader/sim/mc/rows.py        # list them
"""

from __future__ import annotations

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))
from duckcards import packs  # noqa: E402
from duckcards.cards import Deck  # noqa: E402

LETTERS = {"F": "walk_forward", "B": "walk_backward", "L": "turn_left", "R": "turn_right"}
# docs/PACKS.md, "Acceptance", "Rows": duckbench's seven, then Measure my duck's five. A speed in
# brackets is a Speed card under the card.
EXTRA = ["F F L F R F", "F R F R F R F R", "F L L F", "F F B", "F(slow) F(fast) L(slow) F R(fast) B(slow)",
         "L L R R", "F F F F", "F", "F F", "F F F", "L L L L"]


# The pre-registered rows, by the names `all_rows` gives them.
ACCEPTANCE = {e.replace(" ", "") for e in EXTRA}


def _entry(token: str) -> dict:
    card, _, speed = token.partition("(")
    e = {"card": LETTERS[card]}
    if speed:
        e["under"] = [speed.rstrip(")")]
    return e


def all_rows() -> list[dict]:
    deck = Deck.load()
    out = []
    for p in packs.bundled(deck):
        lent, _ = p.lend(deck)
        for ch in p.challenges:
            if not ch.solution:
                continue
            out.append({"name": f"{p.id}/{ch.id}", "entries": list(ch.solution), "deck": lent})
    for e in EXTRA:
        out.append({"name": e.replace(" ", ""), "entries": packs.entries([_entry(c) for c in e.split()]), "deck": deck})
    return out


def steps(row: dict):
    return packs.steps_of(row["entries"], row["deck"])


if __name__ == "__main__":
    for r in all_rows():
        print(r["name"], " ".join(s.action for s in steps(r)))
