"""Duck Card packs: reading a pack, the board rule, par, and the four starter packs.

    python3 -m unittest discover -s cardreader/tests -p test_packs.py -v
"""

from __future__ import annotations

import copy
import importlib.util
import json
import pathlib
import unittest

from helpers import DECK, class_deck, yours

from duckcards import packs as P
from duckcards.cards import Entry

ROOT = pathlib.Path(__file__).resolve().parents[2]
VECTORS = ROOT / "cardreader" / "vectors"
KIT_PACKS = ROOT / "StudioKit" / "Sources" / "StudioKit" / "Resources" / "DuckPacks"


def raw(pid: str) -> dict:
    return json.loads((P.PACKS / f"{pid}.duckpack").read_text())


def tiny(**over) -> dict:
    """A pack small enough to break one thing at a time."""
    data = {"format": "duck-pack/0", "id": "tiny", "name": "Tiny", "grades": "K", "grade_from": 0, "grade_to": 0,
            "vocabulary": "r001", "license": "CC-BY-4.0", "credit": "Duck Cards, from microduckstudio.com",
            "about": "One square to walk.", "cards": ["start", "end", "walk_forward", "turn_left", "turn_right",
                                                       "walk_backward", "greet"],
            "score": "steps", "board": {"columns": 3, "rows": 3, "square_cm": 30, "duck_square_cm": None},
            "challenges": [{"id": "t-1", "name": "Step", "start": {"at": [1, 2], "facing": "north"}, "goal": [1, 1],
                            "walls": [], "gates": [], "finish_with": None, "par": 1,
                            "solution": [{"card": "walk_forward"}], "buggy": None, "hint": "One step."}],
            "lessons": [], "yours": []}
    data.update(over)
    return data


def challenge(**over) -> dict:
    c = copy.deepcopy(tiny()["challenges"][0])
    c.update(over)
    return c


def play(pack: P.Pack, ch: P.Challenge, codes: list[str]) -> dict:
    return P.play_row(pack, ch, [Entry(c) for c in codes], DECK)


class TheVectors(unittest.TestCase):
    def test_every_pack_vector_plays_as_written(self):
        files = sorted(VECTORS.glob("pack_*.json"))
        self.assertGreaterEqual(len(files), 8)
        for f in files:
            v = json.loads(f.read_text())
            deck, _ = P.lend_yours(DECK, v["yours"])
            ch = P.challenge_of(v["challenge"], P.Board(**v["board"]), v["cards"], deck)
            got = P.play_entries(ch, P.entries(v["row"]), v["score"], deck)
            self.assertEqual(got, v["expect"], f.name)


class ReadingAPack(unittest.TestCase):
    def test_a_good_pack_reads(self):
        pack = P.Pack.read(tiny(), DECK)
        self.assertEqual(pack.challenge("t-1").goal, (1, 1))
        self.assertEqual(pack.board.duck_square_cm, None)

    def refused(self, data, words):
        with self.assertRaises(P.PackError) as e:
            P.Pack.read(data, DECK)
        self.assertIn(words, str(e.exception))
        return str(e.exception)

    def test_refusals_say_what_to_fix(self):
        self.refused(b"{not json", "not JSON")
        self.refused(tiny(format="duck-cards/0"), "format is not duck-pack/0")
        self.refused(tiny(vocabulary="r002"), "vocabulary 'r002'")
        self.refused(tiny(cards=["start", "end", "moonwalk"]), "'moonwalk', which is not a card")
        self.refused(tiny(cards=["walk_forward"]), "Every pack plays Start and End.")
        self.refused(tiny(score="time"), "score is steps or cards")
        self.refused(tiny(grade_from=3, grade_to=1), "grade_from to grade_to")
        self.refused(tiny(challenges=[challenge(goal=[3, 0])]), "t-1: the goal [3, 0] is off the 3 x 3 board.")
        self.refused(tiny(challenges=[challenge(walls=[{"between": [[0, 0], [1, 1]]}])]), "share an edge")
        self.refused(tiny(challenges=[challenge(gates=[{"at": [1, 1], "axis": "up"}])]), "axis is ns or ew")
        self.refused(tiny(challenges=[challenge(gates=[{"at": [1, 2], "axis": "ns"}])]), "start square")
        self.refused(tiny(challenges=[challenge(finish_with="walk_forward")]), "standing still")
        self.refused(tiny(challenges=[challenge(finish_with="kick_left")]), "a card in play")
        self.refused(tiny(challenges=[challenge(solution=[{"card": "repeat"}])]), "needs times, 1 to 9")
        self.refused(tiny(challenges=[challenge(solution=[{"card": "start"}])]), "leaves them out")
        self.refused(tiny(challenges=[challenge(), challenge()]), "same id")
        self.refused(tiny(yours=[yours(150, [{"card": "greet"}])]), "numbered 200 to 299")
        self.refused(tiny(yours=[{**yours(200, [{"card": "greet"}]), "code": "card_9"}]), "is called card_1")
        self.refused(tiny(yours=[yours(200, [{"card": "nope"}])]), "cannot be read")

    def test_a_pack_lends_its_your_cards_but_not_over_the_classs_own(self):
        data = tiny(yours=[yours(200, [{"card": "greet"}, {"card": "greet"}], "Double hello")])
        pack = P.Pack.read(data, DECK)
        deck, clashes = pack.lend(DECK)
        self.assertEqual(clashes, [])
        self.assertEqual(deck.card(200).name, "Double hello")
        theirs = class_deck(yours(200, [{"card": "roll"}], "Roll over"))
        kept, clashes = pack.lend(theirs)
        self.assertEqual(clashes, [200])
        self.assertEqual(kept.card(200).name, "Roll over")
        replaced, _ = pack.lend(theirs, replace=True)
        self.assertEqual(replaced.card(200).name, "Double hello")

    def test_a_card_not_in_play_still_runs_and_is_named(self):
        pack = P.Pack.read(tiny(), DECK)
        self.assertEqual(pack.not_in_play(["walk_forward", "roll", "roll"], DECK), ["Roll is not in Tiny."])
        result = play(pack, pack.challenge("t-1"), ["roll", "walk_forward"])
        self.assertTrue(result["solved"])


class TheBoardRule(unittest.TestCase):
    def setUp(self):
        self.pack = P.Pack.read(tiny(), DECK)

    def ch(self, **over):
        return P.challenge_of(challenge(**over), self.pack.board, self.pack.cards, DECK)

    def test_a_bump_stops_the_play_where_the_duck_was(self):
        ch = self.ch(walls=[{"between": [[1, 1], [1, 0]]}], goal=[1, 0])
        r = play(self.pack, ch, ["walk_forward", "walk_forward", "turn_left"])
        self.assertEqual(r["bumped_at"], 2)
        self.assertEqual(len(r["path"]), 2)
        self.assertEqual(r["ended"], {"at": [1, 1], "facing": "north"})
        self.assertEqual(r["steps"], 3)
        self.assertEqual(r["said"], "Bumped into a wall on step 2.")

    def test_walking_back_keeps_the_facing(self):
        ch = self.ch(start={"at": [1, 0], "facing": "north"}, goal=[1, 2])
        r = play(self.pack, ch, ["walk_backward", "walk_backward"])
        self.assertTrue(r["solved"])
        self.assertEqual(r["ended"], {"at": [1, 2], "facing": "north"})

    def test_a_gate_counts_only_along_its_axis(self):
        ch = self.ch(gates=[{"at": [1, 1], "axis": "ew"}])
        self.assertEqual(play(self.pack, ch, ["walk_forward"])["gates_passed"], [])
        self.assertIsNone(P.par_steps(self.ch(goal=[1, 1], gates=[{"at": [1, 1], "axis": "ew"}],
                                              walls=[{"between": [[0, 1], [1, 1]]}, {"between": [[2, 1], [1, 1]]}]),
                                      self.pack.cards))

    def test_par_is_the_shortest_path_and_counts_the_finish(self):
        ch = self.ch(goal=[0, 0])
        self.assertEqual(P.par_steps(ch, self.pack.cards), 4)       # F, F, L, F
        self.assertEqual(P.par_steps(self.ch(goal=[0, 0], finish_with="greet"), self.pack.cards), 5)
        self.assertEqual(P.par_steps(self.ch(goal=[1, 2], start={"at": [1, 0], "facing": "north"}),
                                     ["walk_forward", "turn_left"]), 4)   # no walk back: turn round first

    def test_a_loop_must_be_closed(self):
        self.assertEqual(P.open_repeats([Entry("repeat", times=2), Entry("walk_forward")]), 1)
        self.assertEqual(P.open_repeats([Entry("repeat", times=2), Entry("walk_forward"), Entry("end_repeat")]), 0)

    def test_cards_count_every_card_laid(self):
        self.assertEqual(P.card_count([Entry("repeat", times=3), Entry("walk_forward", ("slow",)),
                                       Entry("end_repeat")]), 4)

    def test_a_saved_row_unrolls_as_the_reader_unrolls_it(self):
        steps = P.steps_of([Entry("repeat", times=3), Entry("walk_forward"), Entry("turn_left"),
                            Entry("end_repeat")], DECK)
        self.assertEqual([s.action for s in steps], ["walk_forward", "turn_left"] * 3)


class TheStarterPacks(unittest.TestCase):
    def setUp(self):
        self.packs = {p.id: p for p in P.bundled(DECK)}

    def test_the_four_packs_youngest_first(self):
        self.assertEqual([p.id for p in P.bundled(DECK)],
                         ["get-to-the-pond", "duck-maze", "loop-the-course", "design-a-level"])

    def test_the_copies_are_the_studiokit_files(self):
        for p in self.packs:
            self.assertEqual((P.PACKS / f"{p}.duckpack").read_bytes(), (KIT_PACKS / f"{p}.duckpack").read_bytes(), p)

    def test_the_checker_passes(self):
        spec = importlib.util.spec_from_file_location("check_duck_packs", ROOT / "scripts" / "check_duck_packs.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        self.assertEqual(mod.main(), 0)

    def test_get_to_the_pond(self):
        p = self.packs["get-to-the-pond"]
        self.assertEqual((p.score, p.board.columns, p.board.rows, p.board.square_cm), ("steps", 3, 3, 30))
        self.assertEqual(p.cards, ("start", "end", "walk_forward", "turn_left", "turn_right"))
        self.assertEqual(len(p.challenges), 6)
        self.assertTrue(all(not c.walls for c in p.challenges[:3]))

    def test_duck_maze(self):
        p = self.packs["duck-maze"]
        self.assertEqual((p.score, p.board.columns), ("steps", 4))
        for code in ("walk_backward", "stop", "greet", "kick_right"):
            self.assertIn(code, p.cards)
        c = p.challenges
        self.assertEqual(len(c), 10)
        self.assertTrue(all(not x.walls for x in c[:2]) and c[2].walls)
        self.assertTrue(all(not x.gates for x in c[:5]) and c[5].gates)
        self.assertEqual(sum(1 for x in c if x.finish_with), 2)
        # Walk back pays somewhere: a challenge whose par needs it.
        self.assertTrue(any(P.par_steps(x, [m for m in p.cards if m != "walk_backward"]) > x.par for x in c))

    def test_loop_the_course(self):
        p = self.packs["loop-the-course"]
        self.assertEqual((p.score, p.board.columns), ("cards", 5))
        for code in ("repeat", "end_repeat", "slow", "fast", "look_left", "look_right"):
            self.assertIn(code, p.cards)
        self.assertEqual(len(p.challenges), 10)
        beats = [c.id for c in p.challenges if c.par < P.par_steps(c, p.cards)
                 and any(e.card == "repeat" for e in c.solution)]
        self.assertGreaterEqual(len(beats), 4, beats)
        self.assertGreaterEqual(sum(1 for c in p.challenges if c.buggy is not None), 2)

    def test_design_a_level(self):
        p = self.packs["design-a-level"]
        self.assertEqual((p.score, p.board.columns), ("cards", 6))
        printed = {c["code"] for c in DECK.data["cards"] if c.get("printed")}
        self.assertTrue(printed <= set(p.cards))
        self.assertIn("when_falls", p.cards)
        self.assertEqual(len(p.challenges), 3)
        lent = {y["code"] for y in p.yours}
        self.assertTrue(lent)
        self.assertTrue(all(200 <= y["tag"] <= 299 for y in p.yours))
        self.assertTrue(any(e.card in lent for c in p.challenges for e in c.solution))
        # Your cards are built from printed cards.
        for y in p.yours:
            self.assertTrue(all(e["card"] in printed for e in y["row"]), y["code"])

    def test_no_dashes_and_three_to_six_lessons(self):
        for pid, p in self.packs.items():
            text = (P.PACKS / f"{pid}.duckpack").read_text()
            self.assertNotIn("\u2014", text, pid)
            self.assertNotIn("\u2013", text, pid)
            self.assertTrue(3 <= len(p.lessons) <= 6, pid)


if __name__ == "__main__":
    unittest.main()
