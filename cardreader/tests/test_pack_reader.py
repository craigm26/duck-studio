"""The card reader with a pack: `python3 -m duckcards watch --pack ... [--challenge ...]`.

A pack narrows, it does not refuse: a card outside it still runs and is named. A pack's Your cards
are lent, and a class's own card wins a clash. With a challenge, each row is played on the board
and reported as the board's answer, never as where the duck stopped.

    python3 -m unittest discover -s cardreader/tests -p test_pack_reader.py -v
"""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import pathlib
import tempfile
import unittest
from unittest import mock

from helpers import DECK, class_deck, row_at, yours

from duckcards import __main__ as cli
from duckcards import packs as P
from duckcards.layout import arrange
from duckcards.program import read


def program_of(seen, deck=DECK):
    return read(arrange(seen), deck)


def args(**kw) -> argparse.Namespace:
    base = {"pack": None, "challenge": None, "deck": None}
    base.update(kw)
    return argparse.Namespace(**base)


class Said:
    def __init__(self):
        self.lines = []

    def __call__(self, s):
        self.lines.append(s)

    @property
    def text(self) -> str:
        return "\n".join(self.lines)


class CardsOutsideThePack(unittest.TestCase):
    def setUp(self):
        self.pond = P.find("get-to-the-pond", DECK)

    def test_a_card_not_in_play_is_named_and_still_runs(self):
        program = program_of(row_at(["start", "walk_forward", "roll", "end"]))
        self.assertEqual(P.outside(self.pond, program, DECK), ["Roll is not in Get to the pond."])
        self.assertEqual([s.action for s in program.steps], ["walk_forward", "roll"])

    def test_under_cards_and_the_falls_row_are_looked_at_too(self):
        seen = row_at(["start", "walk_forward", "end"], unders={1: ["slow"]})
        seen += row_at(["when_falls", "greet", "end"], y=700.0)
        notes = P.outside(self.pond, program_of(seen), DECK)
        names = [DECK.by_code(c).name for c in ("slow", "when_falls", "greet")]
        self.assertEqual(notes, [f"{n} is not in Get to the pond." for n in names])

    def test_a_row_inside_the_pack_has_no_notes(self):
        program = program_of(row_at(["start", "walk_forward", "turn_left", "end"]))
        self.assertEqual(P.outside(self.pond, program, DECK), [])

    def test_a_card_held_up_is_checked_too(self):
        from helpers import seen_at
        program = program_of([seen_at("kick_left", 300, 300)])
        self.assertEqual(program.kind, "card")
        self.assertEqual(P.outside(self.pond, program, DECK), [f"{DECK.by_code('kick_left').name} is not in Get to the pond."])


class Lending(unittest.TestCase):
    def test_a_packs_your_cards_are_lent(self):
        say = Said()
        deck, pack, ch = cli._pack(args(pack="design-a-level"), DECK, say)
        self.assertEqual((deck.card(200).name, deck.card(201).name), ("Stair step", "Side of the pond"))
        self.assertIsNone(ch)
        self.assertIn("Design a level lends its Your cards: 200 Stair step; 201 Side of the pond.", say.text)
        # The lent card opens into its row when laid.
        program = program_of(row_at(["start", "card_1", "end"]), deck)
        self.assertTrue(program.steps)
        self.assertEqual(P.outside(pack, program, deck), [])

    def test_the_class_deck_wins_a_clash_and_the_number_is_said(self):
        theirs = class_deck(yours(200, [{"card": "roll"}], "Roll over"))
        say = Said()
        deck, pack, _ = cli._pack(args(pack="design-a-level"), theirs, say)
        self.assertEqual(deck.card(200).name, "Roll over")
        self.assertEqual(deck.card(201).name, "Side of the pond")
        self.assertIn("lends its Your card: 201 Side of the pond.", say.text)
        self.assertIn("The class deck already saved something else for card 200, so it keeps the class's own "
                      "meaning, not Design a level's.", say.text)

    def test_with_a_deck_file_too(self):
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "class.duckcards"
            mine = {200: yours(200, [{"card": "roll"}], "Roll over"), 201: yours(201, [{"card": "greet"}], "Hi")}
            cards = [mine.get(c["tag"], c) for c in DECK.data["cards"]]
            path.write_text(json.dumps({**DECK.data, "cards": cards}))
            say = Said()
            with contextlib.redirect_stdout(io.StringIO()):
                start = cli._deck(str(path))
            deck, _, _ = cli._pack(args(pack="design-a-level"), start, say)
        self.assertEqual((deck.card(200).name, deck.card(201).name), ("Roll over", "Hi"))
        self.assertIn("for cards 200 and 201, so they keep the class's own meaning", say.text)
        self.assertNotIn("lends its Your card", say.text)

    def test_a_pack_with_no_your_cards_says_nothing_about_lending(self):
        say = Said()
        cli._pack(args(pack="get-to-the-pond"), DECK, say)
        self.assertNotIn("Your card", say.text)


class TheChallengeReport(unittest.TestCase):
    def test_a_solution_is_reported_as_the_boards_answer(self):
        pack = P.find("get-to-the-pond", DECK)
        ch = pack.challenges[0]
        codes = ["start"] + [e.card for e in ch.solution] + ["end"]
        result, lines = P.report(pack, ch, program_of(row_at(codes, width=40, gap=4)), DECK)
        self.assertTrue(result["solved"])
        self.assertEqual(lines[0], f"[board] {ch.name} ({ch.id}): {result['said']}")
        self.assertEqual(lines[1], f"[board] solved, score {ch.par} steps, par {ch.par}.")
        self.assertIn("the board's answer for the row", lines[2])
        self.assertIn("not where the duck stopped", lines[2])
        self.assertIn("A Walk card walks one duck square, 30 cm, on odometry (duckbench simulator", lines[2])
        self.assertIn("not measured in Pollen's duck-sim or on a real duck).", lines[2])
        for line in lines:
            self.assertNotIn("landed", line)

    def test_a_bump_is_reported_and_not_solved(self):
        pack = P.find("get-to-the-pond", DECK)
        ch = pack.challenges[0]
        program = program_of(row_at(["start"] + ["walk_forward"] * 4 + ["end"], width=40, gap=4))
        result, lines = P.report(pack, ch, program, DECK)
        self.assertFalse(result["solved"])
        self.assertTrue(result["said"].startswith("Bumped into"))
        self.assertIn("[board] not solved", lines[1])

    def test_a_cards_pack_counts_the_cards_laid_and_an_open_repeat(self):
        pack = P.find("loop-the-course", DECK)
        ch = next(c for c in pack.challenges if any(e.card == "repeat" for e in c.solution))
        laid = [e.card for e in ch.solution]
        counts = {i + 1: e.times for i, e in enumerate(ch.solution) if e.card == "repeat"}
        unders = {i + 1: list(e.under) for i, e in enumerate(ch.solution) if e.under}
        seen = row_at(["start"] + laid + ["end"], width=30, gap=4, counts=counts, unders=unders)
        result, lines = P.report(pack, ch, program_of(seen), DECK)
        self.assertTrue(result["solved"], result["said"])
        self.assertEqual(result["score"], P.card_count(ch.solution))
        self.assertIn("cards, par", lines[1])
        # The same row without its End repeat runs, but is not solved on the board.
        cut = len(laid) - 1 - laid[::-1].index("end_repeat")
        without = laid[:cut] + laid[cut + 1:]
        counts2 = {k if k <= cut else k - 1: v for k, v in counts.items()}
        unders2 = {k if k <= cut else k - 1: v for k, v in unders.items()}
        seen = row_at(["start"] + without + ["end"], width=30, gap=4, counts=counts2, unders=unders2)
        result, _ = P.report(pack, ch, program_of(seen), DECK)
        self.assertFalse(result["solved"])

    def test_the_reader_prints_it_after_a_row(self):
        """`read --pack --challenge` end to end, with the picture's cards given."""
        pack = P.find("get-to-the-pond", DECK)
        ch = pack.challenges[0]
        seen = row_at(["start"] + [e.card for e in ch.solution] + ["roll", "end"], width=40, gap=4)
        out = self.run_read(seen, ["--pack", "get-to-the-pond", "--challenge", ch.id])
        self.assertIn(f"challenge: {ch.name} ({ch.id}), par {ch.par}.", out)
        self.assertIn("  note: Roll is not in Get to the pond.", out)
        self.assertIn(f"  [board] {ch.name} ({ch.id}): ", out)
        self.assertIn("the board's answer for the row", out)
        self.assertLess(out.index("note: Roll"), out.index("[board]"))

    def test_without_a_challenge_there_is_no_board(self):
        seen = row_at(["start", "walk_forward", "roll", "end"])
        out = self.run_read(seen, ["--pack", "get-to-the-pond"])
        self.assertIn("note: Roll is not in Get to the pond.", out)
        self.assertNotIn("[board]", out)

    def run_read(self, seen, extra) -> str:
        from PIL import Image
        with tempfile.TemporaryDirectory() as d:
            pic = pathlib.Path(d) / "row.png"
            Image.new("L", (8, 8)).save(pic)
            look = mock.Mock(seen=seen, foreign=0)
            buf = io.StringIO()
            with mock.patch.object(cli, "see", return_value=look), contextlib.redirect_stdout(buf):
                status = cli.main(["read", str(pic)] + extra)
        self.assertEqual(status, 0)
        return buf.getvalue()


class Refusals(unittest.TestCase):
    def refused(self, words, **kw):
        with self.assertRaises(SystemExit) as e:
            cli._pack(args(**kw), DECK, Said())
        self.assertIn(words, str(e.exception))

    def test_a_pack_nobody_can_find(self):
        self.refused("There is no pack file at nope.duckpack, and no starter pack is called that. The starter "
                     "packs are design-a-level, duck-maze, get-to-the-pond and loop-the-course.",
                     pack="nope.duckpack")
        with self.assertRaises(P.PackError):
            P.find("Get To The Pond", DECK)

    def test_a_file_that_is_not_a_pack(self):
        with tempfile.TemporaryDirectory() as d:
            bad = pathlib.Path(d) / "bad.duckpack"
            bad.write_text("{not json")
            self.refused(f"cannot use the pack {bad}: This file is not a Duck Cards pack: it is not JSON.",
                         pack=str(bad))
            bad.write_text(json.dumps({"format": "duck-cards/0"}))
            self.refused("its format is not duck-pack/0", pack=str(bad))

    def test_a_pack_file_by_path(self):
        deck, pack, _ = cli._pack(args(pack=str(P.PACKS / "duck-maze.duckpack")), DECK, Said())
        self.assertEqual(pack.id, "duck-maze")

    def test_a_challenge_the_pack_does_not_have(self):
        self.refused("Get to the pond has no challenge maze-1; its challenges are pond-1, pond-2, pond-3, "
                     "pond-4, pond-5 and pond-6.", pack="get-to-the-pond", challenge="maze-1")

    def test_a_challenge_needs_a_pack(self):
        self.refused("give the pack with --pack", challenge="pond-1")


if __name__ == "__main__":
    unittest.main()
