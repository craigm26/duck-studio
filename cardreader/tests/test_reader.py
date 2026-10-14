"""The reader, without a duck: the deck, the geometry, rows, programs, plans, and pictures.

    python3 -m unittest discover -s cardreader/tests -v
"""

from __future__ import annotations

import json
import math
import random
import unittest

from helpers import DECK, class_deck, corners_at, row_at, seen_at, yours

from duckcards.cards import DECK_SHA256, SQUARE_SIDE, Deck, DeckError, place
from duckcards.layout import arrange
from duckcards.program import YOURS_DEPTH, check_plan, plan, read, PlanError

try:
    import numpy as np
    import cv2  # noqa: F401
    from pupil_apriltags import Detector  # noqa: F401
    PICTURES = True
except ImportError:
    PICTURES = False

EXAMPLE = ["start", "greet", "walk_forward", "turn_left", "kick_right", "end"]


def program_of(seen, deck=DECK, counts=None):
    return read(arrange(seen), deck, counts)


class TheDeck(unittest.TestCase):
    def test_the_deck_is_the_sites_byte_for_byte(self):
        self.assertEqual(Deck.digest(), DECK_SHA256)

    def test_every_card_the_deck_names_has_a_meaning_or_says_why_not(self):
        for card in DECK.cards.values():
            if card.kind in ("action", "modifier"):
                self.assertTrue(card.plan, card.code)
            else:
                self.assertIsNone(card.plan, card.code)

    def test_a_your_card_the_deck_did_not_print_is_still_a_your_card(self):
        self.assertEqual(DECK.card(250).kind, "yours")
        self.assertIsNone(DECK.card(150))
        self.assertIsNone(DECK.card(300))

    def test_the_square_is_19_point_2_percent_of_the_card(self):
        self.assertAlmostEqual(SQUARE_SIDE, 19.2, places=6)


class Geometry(unittest.TestCase):
    def test_a_card_is_found_where_it_was_put_at_any_angle(self):
        for angle in (0, 33, 90, 180, -120):
            s = seen_at("walk_forward", 400, 300, 120, angle)
            self.assertAlmostEqual(s.card_centre[0], 400, delta=0.01, msg=angle)
            self.assertAlmostEqual(s.card_centre[1], 300, delta=0.01, msg=angle)
            self.assertAlmostEqual(s.side, 120 * SQUARE_SIDE / 100, delta=0.01)


class Rows(unittest.TestCase):
    def test_a_row_reads_left_to_right(self):
        seen = row_at(EXAMPLE, unders={2: ["slow"]})
        random.Random(1).shuffle(seen)
        self.assertEqual(arrange(seen).describe(), [["start", "greet", "walk_forward/slow", "turn_left", "kick_right", "end"]])

    def test_a_row_seen_from_the_far_side_reads_the_same(self):
        seen = row_at(EXAMPLE, x0=900, angle=180, unders={2: ["slow"]})
        self.assertEqual(program_of(seen).words, "Hello. Walk forward, slow. Turn left. Kick, right.")

    def test_a_row_at_a_slant_reads_along_the_cards(self):
        seen = row_at(EXAMPLE, angle=25, unders={2: ["slow"]})
        self.assertEqual(arrange(seen).describe()[0][2], "walk_forward/slow")

    def test_a_card_turned_round_is_not_read_into_the_row(self):
        seen = row_at(["start", "walk_forward", "turn_left", "end"])
        seen[1] = seen_at("walk_forward", seen[1].card_centre[0], seen[1].card_centre[1], 100, 180)
        program = program_of(seen)
        self.assertEqual(program.words, "Turn left.")
        self.assertTrue(any("Turned the other way" in n for n in program.notes))

    def test_a_when_it_falls_row_below_the_program_is_kept_apart(self):
        main = row_at(["start", "walk_forward", "end"])
        fall = row_at(["when_falls", "greet", "turn_left", "end"], y=600)
        program = program_of(main + fall)
        self.assertEqual(program.words, "Walk forward.")
        self.assertEqual([s.action for s in program.on_fall], ["make_sound", "turn_left"])

    def test_a_speed_card_in_the_row_is_not_under_anything(self):
        program = program_of(row_at(["start", "walk_forward", "fast", "end"]))
        self.assertEqual(program.steps[0].labels["speed"], "normal")
        self.assertTrue(any("not under any card" in n for n in program.notes))


class Programs(unittest.TestCase):
    def test_the_cards_pages_example(self):
        program = program_of(row_at(EXAMPLE, unders={2: ["slow"]}))
        self.assertTrue(program.complete)
        self.assertEqual([s.labels for s in program.steps], [
            {"action": "make_sound", "sound": "greet"},
            {"action": "walk_forward", "speed": "slow", "head": "straight"},
            {"action": "turn_left", "speed": "normal", "head": "straight"},
            {"action": "kick_right"},
        ])

    def test_one_card_held_up_is_a_program_of_one(self):
        program = program_of([seen_at("kick_right", 300, 300)])
        self.assertEqual((program.kind, program.words), ("card", "Kick, right."))

    def test_several_cards_without_start_are_not_a_program_yet(self):
        program = program_of(row_at(["walk_forward", "turn_left"]))
        self.assertEqual(program.kind, "none")
        self.assertTrue(any("no Start" in n for n in program.notes))

    def test_start_without_end_is_unfinished(self):
        program = program_of(row_at(["start", "walk_forward"]))
        self.assertFalse(program.complete)
        self.assertIn("There is a Start but no End yet.", program.notes)

    def test_a_kick_takes_nothing_under_it(self):
        program = program_of(row_at(["start", "kick_left", "end"], unders={1: ["slow"]}))
        self.assertEqual(program.steps[0].labels, {"action": "kick_left"})
        self.assertTrue(any("takes nothing under it" in n for n in program.notes))

    def test_a_stop_takes_a_look_and_a_walk_takes_both(self):
        program = program_of(row_at(["start", "stop", "walk_backward", "end"],
                                    unders={1: ["look_left"], 2: ["fast", "look_up"]}))
        self.assertEqual(program.steps[0].labels, {"action": "stop", "head": "look_left"})
        self.assertEqual(program.steps[1].labels, {"action": "walk_backward", "speed": "fast", "head": "look_up"})

    def test_repeat_asks_for_its_number_and_the_row_waits(self):
        program = program_of(row_at(["start", "repeat", "walk_forward", "turn_right", "end_repeat", "end"]))
        self.assertEqual(program.asks, [0])
        self.assertFalse(program.complete)
        self.assertEqual([s.action for s in program.steps], ["walk_forward", "turn_right"])
        self.assertIn("Repeat has no number that could be read, so the row waits for one.", program.notes)

    def test_a_number_read_off_repeat_is_said_back(self):
        program = program_of(row_at(["start", "repeat", "walk_forward", "end_repeat", "end"], counts={1: 3}))
        self.assertEqual((program.asks, program.complete), ([], True))
        self.assertEqual([s.action for s in program.steps], ["walk_forward"] * 3)
        self.assertIn("Repeat says 3 times.", program.notes)

    def test_an_answer_is_used_and_wins_over_what_was_read(self):
        seen = row_at(["start", "repeat", "walk_forward", "end_repeat", "end"])
        answered = program_of(seen, counts={0: 4})
        self.assertEqual((len(answered.steps), answered.complete, answered.notes), (4, True, []))
        read_off = row_at(["start", "repeat", "walk_forward", "end_repeat", "end"], counts={1: 3})
        self.assertEqual(len(program_of(read_off, counts={0: 2}).steps), 2)

    def test_a_number_out_of_reach_is_asked_about(self):
        for count in (0, 10, -1):
            seen = row_at(["start", "repeat", "walk_forward", "end_repeat", "end"], counts={1: count})
            self.assertEqual(program_of(seen).asks, [0], count)
        self.assertEqual(program_of(row_at(["start", "repeat", "walk_forward", "end_repeat", "end"]),
                                    counts={0: 12}).asks, [0])

    def test_repeats_inside_repeats_are_asked_about_in_reading_order(self):
        seen = row_at(["start", "repeat", "walk_forward", "repeat", "turn_left", "end_repeat", "end_repeat", "end"],
                      width=60, gap=6)
        program = program_of(seen)
        self.assertEqual(program.asks, [0, 1])
        answered = program_of(seen, counts={0: 2, 1: 3})
        self.assertEqual([s.action for s in answered.steps], (["walk_forward"] + ["turn_left"] * 3) * 2)
        self.assertTrue(answered.complete)

    def test_a_when_it_falls_row_is_asked_about_after_the_main_row(self):
        main = row_at(["start", "repeat", "walk_forward", "end_repeat", "end"])
        fall = row_at(["when_falls", "repeat", "greet", "end_repeat", "end"], y=600)
        program = program_of(main + fall)
        self.assertEqual(program.asks, [0, 1])
        answered = program_of(main + fall, counts={0: 2, 1: 3})
        self.assertEqual((len(answered.steps), len(answered.on_fall)), (2, 3))


class YourCards(unittest.TestCase):
    """The cards page's spec: a Your card means what its deck file says, a `row` in the shape of
    the deck's `example.row`; a routine can call a routine, four deep, and a loop is cut."""

    def test_a_your_card_with_nothing_saved_is_skipped_by_number(self):
        program = program_of(row_at(["start", "card_1", "end"]))
        self.assertEqual(program.steps, [])
        self.assertIn("Your card 200 has no meaning saved yet, so it was skipped.", program.notes)

    def test_a_your_card_runs_the_row_its_deck_saved(self):
        deck = class_deck(yours(201, [{"card": "walk_forward", "under": ["fast"]}, {"card": "roll"}],
                                "Victory dance", "Walk forward fast, then roll."))
        self.assertEqual(deck.card(201).name, "Victory dance")
        program = program_of(row_at(["start", "card_2", "greet", "end"]), deck)
        self.assertEqual([s.labels for s in program.steps], [
            {"action": "walk_forward", "speed": "fast", "head": "straight"},
            {"action": "roll"},
            {"action": "make_sound", "sound": "greet"},
        ])
        self.assertEqual(program.notes, [])
        held = program_of([seen_at("card_2", 300, 300)], deck)
        self.assertEqual((held.kind, held.words), ("card", "Walk forward, fast. Roll."))

    def test_a_saved_repeat_carries_its_number_and_asks_nothing(self):
        deck = class_deck(yours(200, [{"card": "repeat", "times": 3}, {"card": "peck_ground"},
                                      {"card": "end_repeat"}]))
        program = program_of(row_at(["start", "card_1", "end"]), deck)
        self.assertEqual([s.action for s in program.steps], ["peck_ground"] * 3)
        self.assertEqual((program.asks, program.notes, program.complete), ([], [], True))

    def test_a_routine_calls_a_routine_four_deep_and_no_deeper(self):
        chain = [yours(200 + k, [{"card": f"card_{k + 2}"}, {"card": "greet"}]) for k in range(5)]
        program = program_of(row_at(["start", "card_1", "end"]), class_deck(*chain))
        self.assertEqual(YOURS_DEPTH, 4)
        self.assertEqual([s.action for s in program.steps], ["make_sound"] * 4)
        self.assertIn("Your card 204 sits more than 4 Your cards deep, so it was skipped.", program.notes)

    def test_a_loop_is_cut_and_both_cards_are_named(self):
        deck = class_deck(yours(201, [{"card": "kick_left"}, {"card": "card_3"}]),
                          yours(202, [{"card": "kick_right"}, {"card": "card_2"}]),
                          yours(203, [{"card": "card_4"}]))
        program = program_of(row_at(["start", "card_2", "card_4", "end"]), deck)
        self.assertEqual([s.action for s in program.steps], ["kick_left", "kick_right"])
        self.assertEqual(program.notes, [
            "Your card 202 holds Your card 201, which leads back to 202, so the loop was cut there.",
            "Your card 203 holds itself, so the loop was cut there.",
        ])

    def test_a_deck_that_says_what_the_reader_cannot_follow_is_refused_by_name(self):
        for card, why in [
            (yours(200, [{"card": "fly"}]), "'fly', which is not a card"),
            (yours(200, [{"card": "walk_forward", "under": ["sideways"]}]), "'sideways', which is not a card"),
            (yours(200, [{"card": "repeat"}, {"card": "roll"}]), "needs times"),
            (yours(200, [{"card": "repeat", "times": 12}]), "needs times"),
            (yours(200, [{"card": "roll", "times": 2}]), "only a Repeat takes times"),
            (yours(200, {"card": "roll"}), "row is not a list"),
            ({**DECK.data["cards"][0], "row": [{"card": "roll"}]}, "only a Your card stands for a row"),
        ]:
            with self.assertRaises(DeckError, msg=why) as e:
                class_deck(card)
            self.assertIn(why, str(e.exception))

    def test_a_class_deck_file_round_trips_through_load(self):
        import tempfile, pathlib
        deck = class_deck(yours(205, [{"card": "sit_or_stand"}], "Bow"))
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "class.duckcards"
            path.write_text(json.dumps(deck.data))
            again = Deck.load(path)
        self.assertEqual(again.card(205).name, "Bow")
        self.assertEqual(again.by_code("card_6").tag, 205)
        self.assertEqual(again.by_code("card_51").tag, 250)


class Plans(unittest.TestCase):
    def test_the_plan_is_one_studio_reads(self):
        p = plan(program_of(row_at(EXAMPLE, unders={2: ["slow"]})))
        check_plan(json.dumps(p))
        self.assertEqual(p["format"], "duck-intent-plan/0")
        self.assertEqual(p["model"], "duck-cards/0")
        self.assertEqual(p["request"], "Hello. Walk forward, slow. Turn left. Kick, right.")
        self.assertTrue(all(v == 1.0 for s in p["steps"] for v in s["confidence"].values()))

    def test_check_plan_refuses_what_duckintentplan_refuses(self):
        good = plan(program_of(row_at(["start", "walk_forward", "end"])))
        for broken, why in [
            ({**good, "format": "duck-intent-plan/1"}, "wrongFormat"),
            ({**good, "steps": []}, "noSteps"),
            ({k: v for k, v in good.items() if k != "request"}, "missing request"),
            ({**good, "steps": [{"clause": "x", "labels": {"action": "fly"}}]}, "unknownLabel"),
            ({**good, "steps": [{"clause": "x", "labels": {"speed": "slow"}}]}, "missing action"),
        ]:
            with self.assertRaises(PlanError, msg=why) as e:
                check_plan(broken)
            self.assertIn(why, str(e.exception))


@unittest.skipUnless(PICTURES, "numpy, opencv and pupil_apriltags are needed for pictures")
class Pictures(unittest.TestCase):
    """The duck's camera, simulated (tests/scenes.py), at distances the geometry allows."""

    @classmethod
    def setUpClass(cls):
        import scenes
        from duckcards.see import see
        cls.scenes, cls.see = scenes, staticmethod(see)

    def words(self, img, upscale=1):
        if upscale > 1:
            img = cv2.resize(img, None, fx=upscale, fy=upscale, interpolation=cv2.INTER_CUBIC)
        return program_of(self.see(img, DECK).seen).words

    def card(self, code):
        c = DECK.by_code(code)
        return c.tag, c.category

    def test_the_corner_order_is_the_librarys(self):
        img = np.full((400, 400), 255, np.uint8)
        card = self.scenes.card_image(self.card("kick_right")[0], "trick", scale=4)
        img[:card.shape[0] // 2, :card.shape[1] // 2] = cv2.resize(card, None, fx=.5, fy=.5)
        from duckcards.see import detections
        (d,) = detections(img)
        (tr, tl, bl, br) = d["corners"]
        self.assertLess(tl[0], tr[0]); self.assertLess(tl[1], bl[1]); self.assertLess(bl[0], br[0])

    def test_every_printed_code_reads_off_its_card(self):
        from duckcards.see import detections
        deck = json.loads((self.scenes.HERE.parent / "duckcards/duck-cards.json").read_text())
        printed = [c for c in deck["cards"] if c["printed"]]
        self.assertEqual(len(printed), 36)
        for c in printed:
            img = np.pad(self.scenes.card_image(c["tag"], c["category"], scale=3), 40, constant_values=255)
            self.assertEqual([d["id"] for d in detections(img)], [c["tag"]], c["code"])

    def test_one_card_held_up_at_arms_length(self):
        for dist in (200, 350, 500):
            self.assertEqual(self.words(self.scenes.held(*self.card("kick_right"), dist, yaw_deg=20, roll_deg=-8)),
                             "Kick, right.", dist)

    def test_a_short_row_in_a_rail(self):
        row = [(*self.card(c), [self.card("slow")] if c == "walk_forward" else []) for c in ["start", "walk_forward", "turn_left", "end"]]
        self.assertEqual(self.words(self.scenes.rail(row, 450)), "Walk forward, slow. Turn left.")

    def test_a_row_on_the_floor_from_the_near_side(self):
        row = [(*self.card(c), []) for c in ["start", "walk_forward", "end"]]
        pitch = math.degrees(math.atan2(self.scenes.HEAD_MM, 320))
        self.assertEqual(self.words(self.scenes.floor(row, 320, pitch)), "Walk forward.")

    def test_a_row_on_the_floor_from_the_far_side_needs_the_closer_look(self):
        row = [(*self.card(c), []) for c in ["start", "walk_forward", "end"]]
        pitch = math.degrees(math.atan2(self.scenes.HEAD_MM, 260))
        self.assertEqual(self.words(self.scenes.floor(row, 260, pitch, far_side=True), upscale=2), "Walk forward.")


if __name__ == "__main__":
    unittest.main()
