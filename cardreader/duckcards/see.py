"""Finding the codes in a picture.

THE LIBRARY IS THE APRILTAG LIBRARY. `pupil_apriltags` is the AprilRobotics C
library (BSD-2) behind a Python binding, and the same C is what Studio compiles,
so the duck and the phone find the same codes in the same picture and differ
only in what they do next.

WHAT COUNTS AS SEEN. A code read with at most one bit corrected, and with a
decision margin the library itself calls confident. tag36h11 can correct more
than one bit, which is the right trade for a robot localising itself and the
wrong one for a classroom table covered in pencils, paper and other codes: a
false card is a duck that does something nobody asked for. A code the deck does
not use is ignored, and counted, so a reader can say "I see a code that is not
a Duck Card" instead of nothing.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .cards import Deck, Seen, place

MAX_HAMMING = 1
MIN_MARGIN = 20.0

_detector = None


def _get_detector():
    global _detector
    if _detector is None:
        from pupil_apriltags import Detector
        # quad_decimate 1.0: the duck's frames are 720 wide and the codes are small; halving the
        # picture before looking for squares loses the far cards first. refine_edges sharpens
        # the corners the layout depends on.
        _detector = Detector(families="tag36h11", nthreads=2, quad_decimate=1.0,
                             quad_sigma=0.0, refine_edges=1, decode_sharpening=0.25)
    return _detector


@dataclass
class Look:
    seen: list[Seen]
    foreign: int            # codes found that are not Duck Cards
    doubtful: int           # Duck Card codes found but not trusted


def detections(gray: np.ndarray) -> list[dict]:
    """The library's answer, as plain data: what the shared test vectors carry. A Repeat's entry
    gains `count` when `digits.read_counts` could read the number written on it."""
    if gray.dtype != np.uint8:
        gray = np.clip(gray, 0, 255).astype(np.uint8)
    gray = np.ascontiguousarray(gray)
    out = []
    for d in _get_detector().detect(gray):
        out.append({"id": int(d.tag_id), "hamming": int(d.hamming),
                     "margin": round(float(d.decision_margin), 2),
                     "corners": [[round(float(x), 2), round(float(y), 2)] for x, y in d.corners]})
    return out


def look(found: list[dict], deck: Deck) -> Look:
    seen, foreign, doubtful = [], 0, 0
    for d in found:
        card = deck.card(d["id"])
        if card is None:
            foreign += 1
            continue
        if d.get("hamming", 0) > MAX_HAMMING or d.get("margin", 100.0) < MIN_MARGIN:
            doubtful += 1
            continue
        seen.append(place(card, d["corners"], d.get("margin", 0.0), d.get("hamming", 0), d.get("count")))
    # Two copies of one code in one picture are two cards (a row can say Walk forward twice);
    # one card found twice is not possible, the library reports each square once.
    return Look(seen=seen, foreign=foreign, doubtful=doubtful)


def see(gray: np.ndarray, deck: Deck) -> Look:
    return look(detections(gray), deck)
