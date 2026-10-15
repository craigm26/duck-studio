"""Write cardreader/vectors/*.json: the cases StudioKit's reader must read exactly as this one does.

    python3 cardreader/tests/make_vectors.py          # rewrite them
    python3 cardreader/tests/make_vectors.py --check  # exit 1 if any would change

A vector is what the AprilTag library answered (ids and corners, and for a Repeat the number read
off it, when one was), the class's own cards over the starter deck (`deck_cards`), the answers given
for Repeat numbers nobody could read (`counts`), and what this reader made of it all: the rows, the
program's words, notes and questions, the When it falls steps and the duck-intent-plan/0. Some
cases are cards placed by hand; three are the library's own answers to simulated duck-camera
pictures, so the Swift side is held to real corner noise, not only to arithmetic.
"""

from __future__ import annotations

import json
import math
import pathlib
import sys

from helpers import DECK, row_at, seen_at, yours

from duckcards.layout import arrange
from duckcards.program import plan, read

OUT = pathlib.Path(__file__).resolve().parents[1] / "vectors"
EXAMPLE = ["start", "greet", "walk_forward", "turn_left", "kick_right", "end"]


def as_detections(seen):
    out = []
    for s in seen:
        d = {"id": s.card.tag, "hamming": 0, "margin": 80.0,
             "corners": [[round(x, 3), round(y, 3)] for x, y in s.corners]}
        if s.count is not None:
            d["count"] = s.count
        out.append(d)
    return out


def picture_cases():
    try:
        import scenes
        from duckcards.see import detections
    except ImportError:
        return []
    C = lambda code: (DECK.by_code(code).tag, DECK.by_code(code).category)   # noqa: E731
    held = scenes.held(*C("kick_right"), 350, yaw_deg=20, roll_deg=-8)
    rail = scenes.rail([(*C("start"), []), (*C("walk_forward"), [C("slow")]), (*C("turn_left"), []), (*C("end"), [])], 450)
    pitch = math.degrees(math.atan2(scenes.HEAD_MM, 320))
    floor = scenes.floor([(*C("start"), []), (*C("walk_forward"), []), (*C("end"), [])], 320, pitch)
    return [("picture_held_card", detections(held)), ("picture_rail_row", detections(rail)),
            ("picture_floor_row", detections(floor))]


def cases():
    """(name, detections, deck_cards, counts)."""
    turned = row_at(["start", "walk_forward", "turn_left", "end"])
    turned[1] = seen_at("walk_forward", turned[1].card_centre[0], turned[1].card_centre[1], 100, 180)
    nested = ["start", "repeat", "walk_forward", "repeat", "turn_left", "end_repeat", "end_repeat", "end"]
    dance = yours(201, [{"card": "walk_forward", "under": ["fast"]}, {"card": "card_3"}],
                  "Victory dance", "Walk forward fast, then spin and roll twice.")
    spin = yours(202, [{"card": "repeat", "times": 2}, {"card": "turn_left", "under": ["fast"]}, {"card": "roll"},
                       {"card": "end_repeat"}], "Spin and roll")
    chain = [yours(200 + k, [{"card": f"card_{k + 2}"}, {"card": "greet"}]) for k in range(5)]
    out = [
        ("example_row", as_detections(row_at(EXAMPLE, unders={2: ["slow"]}))),
        ("example_row_far_side", as_detections(row_at(EXAMPLE, x0=900, angle=180, unders={2: ["slow"]}))),
        ("example_row_slanted", as_detections(row_at(EXAMPLE, angle=25, unders={2: ["slow"]}))),
        ("one_card", as_detections([seen_at("roll", 300, 300, 140, -12)])),
        ("no_start", as_detections(row_at(["walk_forward", "turn_left"]))),
        ("start_without_end", as_detections(row_at(["start", "walk_forward"]))),
        ("when_it_falls", as_detections(row_at(["start", "walk_forward", "end"]) +
                                        row_at(["when_falls", "greet", "turn_left", "end"], y=600))),
        ("repeat", as_detections(row_at(["start", "repeat", "walk_forward", "turn_right", "end_repeat", "end"]))),
        ("repeat_read", as_detections(row_at(["start", "repeat", "walk_forward", "end_repeat", "end"], counts={1: 3}))),
        ("repeat_answered", as_detections(row_at(["start", "repeat", "walk_forward", "end_repeat", "end"])),
         [], {"0": 4}),
        ("repeat_out_of_reach", as_detections(row_at(["start", "repeat", "kick_left", "end_repeat", "end"],
                                                     counts={1: 12}))),
        ("repeat_nested_asked", as_detections(row_at(nested, width=60, gap=6))),
        ("repeat_nested", as_detections(row_at(nested, width=60, gap=6, counts={3: 3})), [], {"0": 2}),
        ("repeat_in_when_it_falls", as_detections(row_at(["start", "walk_forward", "end"]) +
                                                  row_at(["when_falls", "repeat", "greet", "end_repeat", "end"], y=600))),
        ("turned_card", as_detections(turned)),
        ("stacked_unders", as_detections(row_at(["start", "stop", "walk_backward", "end"],
                                                unders={1: ["look_left"], 2: ["fast", "look_up"]}))),
        ("kick_takes_nothing", as_detections(row_at(["start", "kick_left", "end"], unders={1: ["slow"]}))),
        ("loose_speed", as_detections(row_at(["start", "walk_forward", "fast", "end"]))),
        ("your_card_unsaved", as_detections(row_at(["start", "card_1", "end"]))),
        ("your_card_saved", as_detections(row_at(["start", "card_1", "end"])),
         [yours(200, [{"card": "sit_or_stand"}, {"card": "greet"}])]),
        ("your_card_held", as_detections([seen_at("card_2", 320, 300, 130, 8)]), [dance, spin]),
        ("your_card_nested", as_detections(row_at(["start", "card_2", "kick_right", "end"])), [dance, spin]),
        ("your_card_loop", as_detections(row_at(["start", "card_2", "card_4", "end"])),
         [yours(201, [{"card": "kick_left"}, {"card": "card_3"}]), yours(202, [{"card": "kick_right"}, {"card": "card_2"}]),
          yours(203, [{"card": "card_4"}])]),
        ("your_card_too_deep", as_detections(row_at(["start", "card_1", "end"])), chain),
        ("not_duck_cards", [{"id": 7, "hamming": 0, "margin": 80.0, "corners": [[10, 10], [0, 10], [0, 20], [10, 20]]}]),
    ]
    def whole(case):
        name, dets, *rest = case
        return name, dets, (rest[0] if rest else []), (rest[1] if len(rest) > 1 else {})
    return [whole(c) for c in out + picture_cases()]


def expected(detections, deck_cards, counts):
    from duckcards.see import look
    deck = DECK.with_cards(deck_cards) if deck_cards else DECK
    seen = look(detections, deck).seen
    layout = arrange(seen)
    program = read(layout, deck, {int(k): v for k, v in counts.items()})
    return {"rows": layout.describe(), "kind": program.kind, "complete": program.complete,
            "words": program.words, "notes": program.notes, "asks": program.asks,
            "on_fall": [s.labels for s in program.on_fall],
            "plan": plan(program) if program.steps else None}


# PACK VECTORS: a challenge from a starter pack, a row, and what the board rule makes of it.
# (name, pack id, challenge id, row or the challenge's own "solution"/"buggy"). Each case is
# here for one rule of docs/PACKS.md, named in the case.
PACK_CASES = [
    ("pack_solved", "get-to-the-pond", "pond-3", "solution"),
    ("pack_bumped_wall", "duck-maze", "maze-3", [{"card": "turn_right"}, {"card": "walk_forward"}]),
    ("pack_bumped_edge", "loop-the-course", "loop-3", "buggy"),
    ("pack_gate_missed", "get-to-the-pond", "pond-6",
     [{"card": "walk_forward"}, {"card": "walk_forward"}, {"card": "turn_right"}, {"card": "walk_forward"},
      {"card": "walk_forward"}]),
    ("pack_gate_wrong_axis", "duck-maze", "maze-6",
     [{"card": c} for c in ["turn_right", "walk_forward", "turn_left", "walk_forward", "walk_forward",
                            "walk_forward", "turn_right", "walk_forward", "walk_forward"]]),
    ("pack_finish_with_satisfied", "duck-maze", "maze-7", "solution"),
    ("pack_finish_with_missed", "duck-maze", "maze-7",
     [{"card": c} for c in ["turn_left", "walk_forward", "walk_forward", "walk_forward", "turn_right",
                            "walk_forward", "greet", "walk_forward"]]),
    ("pack_repeat_unrolled", "loop-the-course", "loop-4", "solution"),
    ("pack_repeat_unclosed", "loop-the-course", "loop-2", [{"card": "repeat", "times": 4}, {"card": "walk_forward"}]),
    ("pack_repeat_bug_in_loop", "loop-the-course", "loop-6", "buggy"),
    ("pack_your_card_opened", "design-a-level", "design-1", "solution"),
    ("pack_your_card_shortcut", "design-a-level", "design-3", "solution"),
    ("pack_walk_backward", "duck-maze", "maze-4", "solution"),
    ("pack_ended_short", "get-to-the-pond", "pond-3",
     [{"card": "walk_forward"}, {"card": "walk_forward"}, {"card": "turn_right"}, {"card": "walk_forward"}]),
    ("pack_over_par", "get-to-the-pond", "pond-2",
     [{"card": c} for c in ["turn_left", "turn_left", "turn_left", "walk_forward"]]),
    ("pack_under_cards_count", "loop-the-course", "loop-1",
     [{"card": "walk_forward", "under": ["slow", "look_left"]}, {"card": "turn_right"}, {"card": "walk_forward"}]),
    ("pack_empty_row", "get-to-the-pond", "pond-1", []),
]


def pack_cases():
    from duckcards.packs import PACKS
    out = []
    for name, pid, cid, row in PACK_CASES:
        data = json.loads((PACKS / f"{pid}.duckpack").read_text())
        challenge = next(c for c in data["challenges"] if c["id"] == cid)
        if isinstance(row, str):
            row = challenge[row]
        out.append((name, {"pack": pid, "score": data["score"], "cards": data["cards"], "board": data["board"],
                           "yours": data["yours"], "challenge": challenge, "row": row}))
    return out


def pack_expected(v: dict) -> dict:
    """Only what the vector carries: a reader that can play it needs nothing else."""
    from duckcards.packs import Board, challenge_of, entries, lend_yours, play_entries
    deck, _ = lend_yours(DECK, v["yours"])
    ch = challenge_of(v["challenge"], Board(**v["board"]), v["cards"], deck)
    return play_entries(ch, entries(v["row"]), v["score"], deck)


def main() -> int:
    check = "--check" in sys.argv
    OUT.mkdir(exist_ok=True)
    stale = []
    names = set()
    bodies = []
    for name, dets, deck_cards, counts in cases():
        bodies.append((name, json.dumps({"name": name, "detections": dets, "deck_cards": deck_cards, "counts": counts,
                                         "expect": expected(dets, deck_cards, counts)}, indent=1, sort_keys=True) + "\n"))
    for name, v in pack_cases():
        bodies.append((name, json.dumps({"name": name, **v, "expect": pack_expected(v)}, indent=1, sort_keys=True) + "\n"))
    for name, body in bodies:
        names.add(name)
        path = OUT / f"{name}.json"
        if not path.exists() or path.read_text() != body:
            stale.append(name)
            if not check:
                path.write_text(body)
    gone = sorted(p.stem for p in OUT.glob("*.json") if p.stem not in names)
    if check and (stale or gone):
        print("stale vectors: " + ", ".join(stale + [f"{g} (no longer made)" for g in gone]))
        return 1
    for g in gone:
        (OUT / f"{g}.json").unlink()
    print(f"{len(bodies)} vectors" + (f", rewrote {len(stale)}" if stale and not check else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
