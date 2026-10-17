#!/usr/bin/env python3
"""Every Duck Cards pack this repository ships, checked as a teacher would need it to be.

A PACK IS A PROMISE ON PAPER. Its activity cards are printed with a par, and a class that finds a
shorter row than par, or cannot solve a challenge at all, has been handed a broken game. So every
`.duckpack` under StudioKit/Sources/StudioKit/Resources/DuckPacks is held to docs/PACKS.md:

  1. it reads as duck-pack/0 against the starter deck (schema, vocabulary, every card in the deck),
     and its file is named for its id;
  2. every goal is reachable with every gate passed, using the moving cards in play;
  3. for a `steps` pack, par is exactly the breadth-first search;
  4. for a `cards` pack, par is no worse than the shortest row of plain cards (else a class would
     be told the long way round is the best one);
  5. every solution solves its challenge at par, and unrolls to no more steps than a duck runs;
  6. every `buggy` row fails, and one card swapped makes it a solution;
  7. solutions, buggy rows and finish_with use only cards in play, and Your cards the pack lends;
  8. 3 to 6 lessons, and no em or en dash anywhere in the file (the website rejects them);
  9. a shipped pack's duck square is the square the closed-loop cards walk
     (`duck-card-loop.json` square_m), and it says where that was measured (`duck_square_source`;
     both readers refuse a number without a source, or a source without a number).

The board rule, the search and the swap are `cardreader/duckcards/packs.py`; nothing is worked
out a second time here. scripts/check_duckcards_vectors.sh keeps the cardreader copies of these
files identical, byte for byte.

THIS GUARD CAN FAIL, AND IT WAS WATCHED TO (2026-10-15), each change made by hand and put back:
  - par of get-to-the-pond pond-3 set 5 -> 4: exit 1, "par is 4, and the search says 5";
  - duck-maze maze-2's goal moved behind a new wall so it cannot be reached: exit 1, "cannot be
    reached";
  - loop-the-course loop-3's buggy row replaced by its solution: exit 1, "the buggy row solves it";
  - the same buggy row replaced by three Turn left cards: exit 1, "no single card swap fixes the buggy row";
  - loop-the-course loop-4's par set 5 -> 12: exit 1, "worse than the plain row";
  - an em dash put in design-a-level's about: exit 1, "dash";
  - duck-maze's duck_square_cm set 30 -> 25: exit 1, "a Walk card walks 30 cm";
  - duck-maze's duck_square_source taken out: exit 1, "carries duck_square_source".

A CLASS'S OWN PACK IS CHECKED THE SAME WAY. Given files, it checks those instead: a class pack
Studio wrote and shared (`class-` and six letters and numbers for an id, written as class.duckpack,
no lessons) is held to every rule above except the two that are about what this repository ships,
the file named for its id and 3 to 6 lessons.

Usage:  python3 scripts/check_duck_packs.py                 # every pack this repository ships
        python3 scripts/check_duck_packs.py FILE.duckpack   # a pack from elsewhere, a class's own
"""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "cardreader"))

from duckcards.cards import Deck  # noqa: E402
from duckcards import packs as P  # noqa: E402
from duckcards.cardloop import SPEC as LOOP  # noqa: E402

SOURCE = ROOT / "StudioKit" / "Sources" / "StudioKit" / "Resources" / "DuckPacks"
DASHES = ("\u2014", "\u2013")


def check(path: pathlib.Path, deck: Deck, shipped: bool = True) -> list[str]:
    name = path.name
    text = path.read_text(encoding="utf-8")
    problems: list[str] = []
    for d in DASHES:
        if d in text:
            problems.append(f"{name}: has an em or en dash; write 'to' or a comma instead.")
    try:
        pack = P.Pack.read(text, deck)
    except P.PackError as e:
        return problems + [f"{name}: {e}"]
    if shipped and path.stem != pack.id:
        problems.append(f"{name}: the file is named {path.stem}, and the pack's id is {pack.id}.")
    if shipped and not 3 <= len(pack.lessons) <= 6:
        problems.append(f"{name}: has {len(pack.lessons)} lessons, and a pack carries 3 to 6.")
    walked = round(LOOP["square_m"] * 100, 6)
    if shipped and pack.board.duck_square_cm is not None and pack.board.duck_square_cm != walked:
        problems.append(f"{name}: says a duck square is {pack.board.duck_square_cm:g} cm, and a Walk card "
                        f"walks {walked:g} cm (duck-card-loop.json).")
    played, _ = pack.lend(deck)
    lent = {y["code"] for y in pack.yours}
    for ch in pack.challenges:
        where = f"{name} {ch.id}"
        reach = P.par_steps(ch, pack.cards)
        if reach is None:
            problems.append(f"{where}: the goal cannot be reached with every gate passed.")
            continue
        if pack.score == "steps" and ch.par != reach:
            problems.append(f"{where}: par is {ch.par}, and the search says {reach}.")
        if pack.score == "cards" and ch.par > reach:
            problems.append(f"{where}: par {ch.par} is worse than the plain row, which takes {reach} cards.")
        rows = [("solution", ch.solution)] + ([("buggy row", ch.buggy)] if ch.buggy is not None else [])
        for what, row in rows:
            for e in row:
                for code in (e.card, *e.under):
                    if code not in pack.cards and code not in lent:
                        problems.append(f"{where}: the {what} lays {code}, which is not in play.")
        result = P.play_row(pack, ch, ch.solution, played)
        if not result["solved"]:
            problems.append(f"{where}: the solution does not solve it: {result['said']}")
        elif result["score"] != ch.par:
            problems.append(f"{where}: the solution scores {result['score']}, and par is {ch.par}.")
        if len(P.steps_of(ch.solution, played)) > P.MAX_STEPS:
            problems.append(f"{where}: the solution unrolls past {P.MAX_STEPS} steps, more than a duck runs.")
        if ch.buggy is not None:
            if P.play_row(pack, ch, ch.buggy, played)["solved"]:
                problems.append(f"{where}: the buggy row solves it, so there is no bug to find.")
            elif not any(P.play_row(pack, ch, r, played)["solved"] for _, _, r in P.swaps(pack, ch.buggy, played)):
                problems.append(f"{where}: no single card swap fixes the buggy row.")
    return problems


def main(argv: list[str] | None = None) -> int:
    deck = Deck.load()
    given = [pathlib.Path(a) for a in (argv or [])]
    files = given or sorted(SOURCE.glob(f"*.{P.EXTENSION}"))
    if not files:
        print(f"check_duck_packs: no packs found in {SOURCE}", file=sys.stderr)
        return 1
    problems = [p for f in files for p in check(f, deck, shipped=not given)]
    if problems:
        print("check_duck_packs:", file=sys.stderr)
        for p in problems:
            print("  " + p, file=sys.stderr)
        return 1
    count = sum(len(P.Pack.load(f, deck).challenges) for f in files)
    print(f"check_duck_packs: {len(files)} packs, {count} challenges, every par and every row checked")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
