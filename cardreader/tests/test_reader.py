"""The reader, without a duck: the deck, the geometry, rows, programs, plans, and pictures.

    python3 -m unittest discover -s cardreader/tests -v
"""

from __future__ import annotations

import json
import math
import random
import unittest

from helpers import DECK, corners_at, row_at, seen_at

from duckcards.cards import DECK_SHA256, SQUARE_SIDE, Deck, place
from duckcards.layout import arrange
from duckcards.program import check_plan, plan, read, PlanError, REPEAT_TIMES

try:
    import numpy as np
    import cv2  # noqa: F401
    from pupil_apriltags import Detector  # noqa: F401
    PICTURES = True
except ImportError:
    PICTURES = False

EXAMPLE = ["start", "greet", "walk_forward", "turn_left", "kick_right", "end"]


def program_of(seen, yours=None):
    return read(arrange(seen), yours or {}, DECK)


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

    def test_repeat_is_unrolled_and_says_how_many_times(self):
        program = program_of(row_at(["start", "repeat", "walk_forward", "turn_right", "end_repeat", "end"]))
        self.assertEqual([s.action for s in program.steps], ["walk_forward", "turn_right"] * REPEAT_TIMES)
        self.assertTrue(any("repeats 2 times" in n for n in program.notes))

    def test_a_your_card_runs_what_the_class_saved_for_it(self):
        seen = row_at(["start", "card_1", "end"])
        self.assertEqual(program_of(seen).steps, [])
        self.assertTrue(any("no meaning saved" in n for n in program_of(seen).notes))
        program = program_of(seen, {200: ["sit_or_stand", "greet"]})
        self.assertEqual([s.action for s in program.steps], ["sit_or_stand", "make_sound"])


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
