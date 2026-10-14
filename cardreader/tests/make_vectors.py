"""Write cardreader/vectors/*.json: the cases StudioKit's reader must read exactly as this one does.

    python3 cardreader/tests/make_vectors.py          # rewrite them
    python3 cardreader/tests/make_vectors.py --check  # exit 1 if any would change

A vector is what the AprilTag library answered (ids and corners), and what this reader made of it:
the rows, the program's words and notes, the When it falls steps and the duck-intent-plan/0. Some
cases are cards placed by hand; three are the library's own answers to simulated duck-camera
pictures, so the Swift side is held to real corner noise, not only to arithmetic.
"""

from __future__ import annotations

import json
import math
import pathlib
import sys

from helpers import DECK, row_at, seen_at

from duckcards.layout import arrange
from duckcards.program import plan, read

OUT = pathlib.Path(__file__).resolve().parents[1] / "vectors"
EXAMPLE = ["start", "greet", "walk_forward", "turn_left", "kick_right", "end"]


def as_detections(seen):
    return [{"id": s.card.tag, "hamming": 0, "margin": 80.0,
             "corners": [[round(x, 3), round(y, 3)] for x, y in s.corners]} for s in seen]


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
    return [("picture_held_card", detections(held), {}), ("picture_rail_row", detections(rail), {}),
            ("picture_floor_row", detections(floor), {})]


def cases():
    turned = row_at(["start", "walk_forward", "turn_left", "end"])
    turned[1] = seen_at("walk_forward", turned[1].card_centre[0], turned[1].card_centre[1], 100, 180)
    out = [
        ("example_row", as_detections(row_at(EXAMPLE, unders={2: ["slow"]})), {}),
        ("example_row_far_side", as_detections(row_at(EXAMPLE, x0=900, angle=180, unders={2: ["slow"]})), {}),
        ("example_row_slanted", as_detections(row_at(EXAMPLE, angle=25, unders={2: ["slow"]})), {}),
        ("one_card", as_detections([seen_at("roll", 300, 300, 140, -12)]), {}),
        ("no_start", as_detections(row_at(["walk_forward", "turn_left"])), {}),
        ("start_without_end", as_detections(row_at(["start", "walk_forward"])), {}),
        ("when_it_falls", as_detections(row_at(["start", "walk_forward", "end"]) +
                                        row_at(["when_falls", "greet", "turn_left", "end"], y=600)), {}),
        ("repeat", as_detections(row_at(["start", "repeat", "walk_forward", "turn_right", "end_repeat", "end"])), {}),
        ("turned_card", as_detections(turned), {}),
        ("stacked_unders", as_detections(row_at(["start", "stop", "walk_backward", "end"],
                                                unders={1: ["look_left"], 2: ["fast", "look_up"]})), {}),
        ("kick_takes_nothing", as_detections(row_at(["start", "kick_left", "end"], unders={1: ["slow"]})), {}),
        ("loose_speed", as_detections(row_at(["start", "walk_forward", "fast", "end"])), {}),
        ("your_card_unsaved", as_detections(row_at(["start", "card_1", "end"])), {}),
        ("your_card_saved", as_detections(row_at(["start", "card_1", "end"])), {"200": ["sit_or_stand", "greet"]}),
        ("not_duck_cards", [{"id": 7, "hamming": 0, "margin": 80.0, "corners": [[10, 10], [0, 10], [0, 20], [10, 20]]}], {}),
    ]
    return out + picture_cases()


def expected(detections, yours):
    from duckcards.see import look
    seen = look(detections, DECK).seen
    layout = arrange(seen)
    program = read(layout, {int(k): v for k, v in yours.items()}, DECK)
    return {"rows": layout.describe(), "kind": program.kind, "complete": program.complete,
            "words": program.words, "notes": program.notes,
            "on_fall": [s.labels for s in program.on_fall],
            "plan": plan(program) if program.steps else None}


def main() -> int:
    check = "--check" in sys.argv
    OUT.mkdir(exist_ok=True)
    stale = []
    for name, dets, yours in cases():
        body = json.dumps({"name": name, "detections": dets, "yours": yours,
                           "expect": expected(dets, yours)}, indent=1, sort_keys=True) + "\n"
        path = OUT / f"{name}.json"
        if not path.exists() or path.read_text() != body:
            stale.append(name)
            if not check:
                path.write_text(body)
    if check and stale:
        print("stale vectors: " + ", ".join(stale))
        return 1
    print(f"{len(cases())} vectors" + (f", rewrote {len(stale)}" if stale and not check else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
