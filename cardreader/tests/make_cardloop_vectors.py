"""Write cardreader/vectors/cardloop/*.json: Walk and Turn cards on odometry, step by step.

    python3 cardreader/tests/make_cardloop_vectors.py          # rewrite them
    python3 cardreader/tests/make_cardloop_vectors.py --check  # exit 1 if any would change

A vector is one card (`action`, `speed`), the board pose it starts from, a trace of odometry
samples `[t, x, y, yaw]` (t is seconds into the card), and what each sample must produce:
`[vx, vyaw]` to send, or the word the card ends on. `board_after` is where the board says the
duck is once the card is done. `cardloop.CardLoop` here and `DuckCardLoop.Card` in StudioKit
must both produce `expect` from `trace`, under the shipped `duck-card-loop.json`; the traces are
synthetic, built to walk each rule (arriving, steering, the clamp, the time cap, settling,
trimming, giving up, a card that makes no progress (stuck), and a heading that wraps past pi).

Pure Python: no numpy, no AprilTag library.
"""

from __future__ import annotations

import json
import math
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from duckcards import cardloop  # noqa: E402

OUT = HERE.parent / "vectors" / "cardloop"
SPEC = cardloop.SPEC
TICK = 1.0 / SPEC["control_hz"]


def r(v: float) -> float:
    return round(v, 6)


def walk_trace(board, sign, speed_mps, n, drift=0.0, yaw_off=0.0, start=(0.0, 0.0)):
    """A duck walking along the board line at speed_mps, `drift` metres a second to its left,
    `yaw_off` radians off the board heading."""
    bx, by, bh = board
    out = []
    for k in range(n):
        t = k * TICK
        along = sign * speed_mps * t + start[0]
        across = drift * t + start[1]
        x = bx + along * math.cos(bh) - across * math.sin(bh)
        y = by + along * math.sin(bh) + across * math.cos(bh)
        out.append([r(t), r(x), r(y), r(bh + yaw_off)])
    return out


def turn_trace(action, speed, board, k=0.9, coast_deg=2.0, then_coast_deg=None, n=400, lead=None):
    """A duck turned by the card itself: yaw follows k x the commanded vyaw, and when a command
    stops the duck keeps turning `coast_deg` the same way over the next five samples (and
    `then_coast_deg` after every later stop, when given). Built closed loop, so the trace ends
    with the card."""
    board = tuple(r(v) for v in board)
    loop = cardloop.CardLoop(action, cardloop.Pose(*board), speed, lead_deg=lead)
    bx, by, yaw = board
    out, last, coast = [], 0.0, []
    for i in range(n):
        t = i * TICK
        out.append([r(t), r(bx), r(by), r(cardloop.wrap(yaw))])
        answer = loop.step(cardloop.Pose(bx, by, round(cardloop.wrap(yaw), 6)), round(t, 6))
        if isinstance(answer, str):
            return out
        vyaw = answer[1]
        if last != 0.0 and vyaw == 0.0:
            coast = [math.copysign(deg(coast_deg) / 5, last)] * 5
            if then_coast_deg is not None:
                coast_deg = then_coast_deg
        yaw += k * vyaw * TICK + (coast.pop() if coast else 0.0)
        last = vyaw
    return out


# The lead a case's card is given (`lead_deg`), when it is not the row's first turn.
LEADS = {"turn_left_with_a_known_lead": 15.0}


def deg(d: float) -> float:
    return d * math.pi / 180.0


def ramp(start, end, n):
    return [start + (end - start) * k / max(1, n - 1) for k in range(n)]


def hold(v, n):
    return [v] * n


def cases():
    settle = int(round(SPEC["turn"]["settle_s"] / TICK))
    max_walk = int(round(SPEC["walk"]["max_s"] / TICK))
    yield ("walk_forward_arrives", "walk_forward", "normal", (0.0, 0.0, 0.0),
           walk_trace((0.0, 0.0, 0.0), 1, 0.15, 60))
    yield ("walk_forward_steers_back_onto_the_line", "walk_forward", "fast", (0.2, -0.1, 0.5),
           walk_trace((0.2, -0.1, 0.5), 1, 0.15, 60, drift=0.02, yaw_off=deg(6), start=(0.0, 0.03)))
    yield ("walk_forward_steering_is_clamped", "walk_forward", "slow", (0.0, 0.0, 0.0),
           walk_trace((0.0, 0.0, 0.0), 1, 0.15, 60, start=(0.0, -0.3), yaw_off=deg(-40)))
    yield ("walk_forward_from_a_long_way_behind", "walk_forward", None, (1.0, 1.0, math.pi / 2),
           walk_trace((1.0, 1.0, math.pi / 2), 1, 0.2, 60, start=(-0.2, 0.0)))
    yield ("walk_backward_arrives", "walk_backward", "normal", (0.5, 0.5, math.pi / 2),
           walk_trace((0.5, 0.5, math.pi / 2), -1, 0.2, 60, drift=-0.01, yaw_off=deg(3)))
    # Slow enough never to arrive before max_s, fast enough never to stall.
    creep = 1.5 * SPEC["walk"]["stall_m"] / SPEC["walk"]["stall_s"]
    stall = int(round(SPEC["walk"]["stall_s"] / TICK))
    yield ("walk_forward_out_of_time", "walk_forward", "normal", (0.0, 0.0, 0.0),
           walk_trace((0.0, 0.0, 0.0), 1, creep, max_walk + 3))
    yield ("walk_backward_is_stuck", "walk_backward", "normal", (0.0, 0.0, 0.0),
           walk_trace((0.0, 0.0, 0.0), -1, 0.0, stall + 3))
    yield ("turn_left_arrives", "turn_left", "normal", (0.0, 0.0, 0.0),
           turn_trace("turn_left", "normal", (0.0, 0.0, 0.0)))
    yield ("turn_left_with_a_known_lead", "turn_left", "normal", (0.0, 0.0, 0.0),
           turn_trace("turn_left", "normal", (0.0, 0.0, 0.0), coast_deg=13.0, lead=LEADS["turn_left_with_a_known_lead"]))
    yield ("turn_right_overshoots_and_trims_back", "turn_right", "fast", (0.1, 0.2, deg(30)),
           turn_trace("turn_right", "fast", (0.1, 0.2, deg(30)), coast_deg=40.0, then_coast_deg=1.0))
    yield ("turn_left_trims_out", "turn_left", "slow", (0.0, 0.0, 0.0),
           turn_trace("turn_left", "slow", (0.0, 0.0, 0.0), coast_deg=40.0))
    yield ("turn_left_across_pi", "turn_left", "normal", (0.0, 0.0, deg(170)),
           turn_trace("turn_left", "normal", (0.0, 0.0, deg(170))))
    yield ("turn_right_out_of_time", "turn_right", "normal", (0.0, 0.0, 0.0),
           turn_trace("turn_right", "normal", (0.0, 0.0, 0.0), k=0.08))
    yield ("turn_right_is_stuck", "turn_right", "normal", (0.0, 0.0, 0.0),
           turn_trace("turn_right", "normal", (0.0, 0.0, 0.0), k=0.0))


def run(action, speed, board, trace, lead=None):
    """What the reader makes of the trace, exactly as a vector carries it: the board rounded."""
    loop = cardloop.CardLoop(action, cardloop.Pose(*(r(v) for v in board)), speed, lead_deg=lead)
    expect = []
    for t, x, y, yaw in trace:
        answer = loop.step(cardloop.Pose(x, y, yaw), t)
        if isinstance(answer, str):
            expect.append(answer)
            break
        expect.append([r(answer[0]), r(answer[1])])
    return expect, loop.board_after, loop.coast_deg


def bodies():
    out = {}
    for name, action, speed, board, trace in cases():
        expect, after, coast = run(action, speed, board, trace, LEADS.get(name))
        if not isinstance(expect[-1], str):
            raise SystemExit(f"{name}: the trace ends before the card does")
        trace = trace[:len(expect)]
        head = {"name": name, "format": cardloop.FORMAT, "action": action, "speed": speed,
                "board": [r(v) for v in board], "board_after": [r(after.x), r(after.y), r(after.h)],
                "lead_deg": LEADS.get(name), "coast_deg": None if coast is None else r(coast)}
        # One sample to a line, so a changed rule shows as the lines it changed.
        lines = [f" {json.dumps(k)}: {json.dumps(v)}," for k, v in sorted(head.items())]
        lines.append(' "trace": [\n' + ",\n".join("  " + json.dumps(t) for t in trace) + "\n ],")
        lines.append(' "expect": [\n' + ",\n".join("  " + json.dumps(e) for e in expect) + "\n ]")
        out[name] = "{\n" + "\n".join(lines) + "\n}\n"
        json.loads(out[name])
    return out


def main() -> int:
    check = "--check" in sys.argv
    want = bodies()
    OUT.mkdir(parents=True, exist_ok=True)
    stale = [n for n, b in want.items() if not (OUT / f"{n}.json").exists() or (OUT / f"{n}.json").read_text() != b]
    gone = sorted(p.stem for p in OUT.glob("*.json") if p.stem not in want)
    if check:
        if stale or gone:
            print(f"make_cardloop_vectors: would change {stale}, would remove {gone}", file=sys.stderr)
            return 1
        print(f"make_cardloop_vectors: {len(want)} vectors, unchanged")
        return 0
    for n in stale:
        (OUT / f"{n}.json").write_text(want[n])
    for n in gone:
        (OUT / f"{n}.json").unlink()
    print(f"{len(want)} cardloop vectors" + (f", rewrote {len(stale)}" if stale else "")
          + (f", removed {len(gone)}" if gone else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
