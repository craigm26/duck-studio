"""Walk and Turn cards closed on what robotd reports: one board square, one quarter turn.

A timed card is a twist held for two seconds, and a duck held to a twist does not land on a
square: duckbench measured it (`duckbench/sim/cardsize.mjs`, `cardloop.mjs`). So when robotd's
`robot.state` carries `odom` (Pollen's contact odometry, whose `yaw` is the trunk IMU's), a
Walk card walks until odometry says the duck has covered one duck square along the card's
heading, steering onto that line, and a Turn card turns until the yaw is a quarter turn from the
card's heading, then settles and trims. Everything else a row does is unchanged.

ONE SPEC, TWO READERS. The numbers are `duck-card-loop.json`, which is StudioKit's
`Resources/DuckCards/duck-card-loop.json` byte for byte (`scripts/check_duckcards_vectors.sh`),
and the stepping rules below are `DuckCardLoop` in StudioKit (`DuckCardLoop.swift`), held to
each other by `cardreader/vectors/cardloop/*.json`: a card, a trace of odometry samples, and the
command or the stop each sample must produce. `tests/make_cardloop_vectors.py` writes them.

THE NUMBERS ARE MEASURED ON POLLEN'S STACK (duck-card-loop/1). `cardreader/sim/sysid/` identified
v8 velstand under Pollen's robotd in duck-sim through `robot.move` only: forward it stands still
up to 0.20 m/s and walks every time from 0.25 (about a third of the command, 0.09 to 0.135 m/s);
backward it stands still up to -0.30 and walks from -0.35; it turns in place from 0.625 rad/s
left and 0.5 right, about 64 degrees a second at 1.0, and coasts about 8 degrees after a turn
stops. So the speeds clear those dead bands, the caps fit docs/PACKS.md's time bounds, and a
card that makes no progress for `stall_s` ends as "stuck" (a duck that cannot do the card at the
speeds it may be sent). `cardreader/sim/results/` is the Monte Carlo.

THE BOARD. A row keeps where the duck should be: the odometry pose it started the first card at,
then one square or one quarter turn per card. Each card aims at that board pose rather than at
"one more square from wherever the last card stopped", so an overshoot or the drift of a turn is
taken back by the next card instead of adding up. A skill (a kick, a roll) moves the duck in ways
the board does not count, so after one the board's position is put back where the duck now
stands; its heading is kept.
"""

from __future__ import annotations

import json
import math
import pathlib
from dataclasses import dataclass

HERE = pathlib.Path(__file__).resolve().parent
SPEC_FILE = HERE / "duck-card-loop.json"
FORMAT = "duck-card-loop/1"
CARDS = ("walk_forward", "walk_backward", "turn_left", "turn_right")


def load_spec(path: pathlib.Path = SPEC_FILE) -> dict:
    spec = json.loads(path.read_text())
    if spec.get("format") != FORMAT:
        raise ValueError(f"{path.name} is not {FORMAT}")
    if not isinstance(spec.get("enabled_on_robot"), bool):
        raise ValueError(f"{path.name} does not say enabled_on_robot, true or false")
    if not (spec.get("validated") is None or isinstance(spec["validated"], str)):
        raise ValueError(f"{path.name}: validated is null or one line citing the results")
    return spec


SPEC = load_spec()

# THE OFF SWITCH. Closed-loop cards ship OFF for real ducks (`enabled_on_robot: false`, with
# `validated: null`) until they pass docs/PACKS.md, "Acceptance": Pollen's duck-sim, a second
# machine, and a tester's duck on a taped grid. Off, a duck runs Walk and Turn as the timed cards
# they were and the reader says this once per row (StudioKit's `DuckCardLoop.offNote`, the same
# words). `python3 -m duckcards watch --measured-cards` forces them on, for duck-sim work only.
ENABLED_ON_ROBOT: bool = SPEC["enabled_on_robot"]
OFF_NOTE = ("Walk and Turn cards on a duck are timed for now: two seconds each, and the duck does not "
            "land on board squares. Measured cards are being tested.")

# POLLEN'S PAD ENVELOPE, ONE SOURCE OF TRUTH. `pollen-pad-drive.json` is StudioKit's
# `Resources/DuckCards/pollen-pad-drive.json` byte for byte: `PadDriveParams::default()` in
# pollen-robotics/microduck `robotd-params/src/lib.rs`, with the commit it was read at. Pollen's
# own words for it: what the v8 velstand "follows well on the robot". robotd does not clamp a
# `robot.move` to it (the pad is bounded, other clients are not), so no card may ask for more.
ENVELOPE_FILE = HERE / "pollen-pad-drive.json"
ENVELOPE_FORMAT = "pollen-pad-drive/0"


def load_envelope(path: pathlib.Path = ENVELOPE_FILE) -> dict:
    env = json.loads(path.read_text())
    if env.get("format") != ENVELOPE_FORMAT:
        raise ValueError(f"{path.name} is not {ENVELOPE_FORMAT}")
    for axis in ("vx", "vy", "vyaw"):
        lo, hi = env[axis]
        if not lo <= 0 <= hi:
            raise ValueError(f"{path.name}: {axis} is not a range around zero")
    return env


ENVELOPE = load_envelope()


def envelope_problems(spec: dict, env: dict | None = None) -> list[str]:
    """Every number in a card-loop spec that would command more than Pollen's pad envelope, said
    by name, in the spec's order. The shipped spec must answer empty
    (`DuckCardLoop.envelopeProblems` says the same sentences)."""
    env = env or ENVELOPE
    forward, back = env["vx"][1], -env["vx"][0]
    turn = min(env["vyaw"][1], -env["vyaw"][0])
    w, t = spec["walk"], spec["turn"]
    checks = [(f"walk.speed.{k}", w["speed"][k], forward) for k in ("slow", "normal", "fast")]
    checks += [(f"walk.back_speed.{k}", w["back_speed"][k], back) for k in ("slow", "normal", "fast")]
    checks += [("walk.max_yaw", w["max_yaw"], turn)]
    checks += [(f"turn.yaw_rate.{k}", t["yaw_rate"][k], turn) for k in ("slow", "normal", "fast")]
    checks += [("turn.forward", abs(t["forward"]), forward if t["forward"] >= 0 else back),
               ("turn.trim_rate", t["trim_rate"], turn),
               ("turn.trim_forward", abs(t["trim_forward"]), forward if t["trim_forward"] >= 0 else back)]
    return [f"{where} is {v:g}, past Pollen's pad envelope of {limit:g}"
            for where, v, limit in checks if not 0 <= v <= limit]


def wrap(a: float) -> float:
    """An angle in (-pi, pi]."""
    while a > math.pi:
        a -= 2 * math.pi
    while a <= -math.pi:
        a += 2 * math.pi
    return a


@dataclass(frozen=True)
class Pose:
    x: float
    y: float
    h: float        # heading, radians, odometry's frame


def odometry(state: dict | None) -> Pose | None:
    """The duck's pose from one `robot.state` frame, or None when it does not say.

    Pollen's `RobotState.odom` is `{position: [x, y, z], yaw}`; a robotd from before the
    estimator sends no `odom` at all, which is the case this falls back from. A position shorter
    than two, or a yaw that is not a number, is not a pose either."""
    odom = (state or {}).get("odom")
    if not isinstance(odom, dict):
        return None
    pos, yaw = odom.get("position"), odom.get("yaw")
    if not isinstance(pos, list) or len(pos) < 2 or not all(isinstance(v, (int, float)) for v in pos[:2]):
        return None
    if not isinstance(yaw, (int, float)) or isinstance(yaw, bool):
        return None
    return Pose(float(pos[0]), float(pos[1]), float(yaw))


def speed_of(spec: dict, action: str, speed: str | None) -> float:
    """What a Speed card means on a distance card: how fast the duck walks or turns there.

    The duck's gait has a dead band (below it the duck marches on the spot), so every speed is a
    speed the gait answers to. A Turn card has one rate: the one that turns the duck in place."""
    label = speed if speed in ("slow", "normal", "fast") else "normal"
    if action == "walk_forward":
        return spec["walk"]["speed"][label]
    if action == "walk_backward":
        return spec["walk"]["back_speed"][label]
    return spec["turn"]["yaw_rate"][label]


class CardLoop:
    """One Walk or Turn card, stepped on odometry samples.

    `step(pose, t)` takes the latest pose and the seconds since the card began and answers
    `(vx, vyaw)` to send, or a string saying why the card is done: "reached", "out of time",
    "stuck" (not `stall_m` or `stall_deg` closer in `stall_s`) or, for a turn that could not be
    trimmed into tolerance, "trimmed out". `board_after` is where the duck should be once the
    card is done, whatever happened."""

    def __init__(self, action: str, board: Pose, speed: str | None = None, spec: dict | None = None):
        if action not in CARDS:
            raise ValueError(f"{action} is not a Walk or Turn card")
        self.spec = spec or SPEC
        self.action, self.board = action, board
        self.rate = speed_of(self.spec, action, speed)
        d = self.spec["square_m"]
        self.mark, self.mark_t = None, 0.0          # the last progress made, and when
        if action.startswith("walk"):
            self.sign = 1.0 if action == "walk_forward" else -1.0
            self.board_after = Pose(board.x + self.sign * d * math.cos(board.h),
                                    board.y + self.sign * d * math.sin(board.h), board.h)
        else:
            self.sign = 1.0 if action == "turn_left" else -1.0
            self.board_after = Pose(board.x, board.y, wrap(board.h + self.sign * math.pi / 2))
            self.phase, self.since = "turn", 0.0
            self.trims_left = int(self.spec["turn"]["trims"])

    def step(self, pose: Pose, t: float):
        if self.action.startswith("walk"):
            return self._walk(pose, t)
        return self._turn(pose, t)

    def _stalled(self, progress: float, t: float, enough: float, window: float) -> bool:
        """No `enough` more progress for `window` seconds."""
        if self.mark is None or progress >= self.mark + enough:
            self.mark, self.mark_t = progress, t
            return False
        return t - self.mark_t >= window

    def _walk(self, pose: Pose, t: float):
        w, b = self.spec["walk"], self.board
        dx, dy = pose.x - b.x, pose.y - b.y
        along = self.sign * (dx * math.cos(b.h) + dy * math.sin(b.h))
        across = -dx * math.sin(b.h) + dy * math.cos(b.h)
        early = w["stop_early_m"] if self.sign > 0 else w["back_stop_early_m"]
        if along >= self.spec["square_m"] - early:
            return "reached"
        if t >= w["max_s"]:
            return "out of time"
        if self._stalled(along, t, w["stall_m"], w["stall_s"]):
            return "stuck"
        steer = w["heading_gain"] * wrap(b.h - pose.h) - self.sign * w["cross_gain"] * across
        steer = max(-w["max_yaw"], min(w["max_yaw"], steer))
        return (self.sign * self.rate, steer)

    def _turn(self, pose: Pose, t: float):
        c = self.spec["turn"]
        e = wrap(self.board_after.h - pose.h)
        off = abs(e) * 180.0 / math.pi
        way = 1.0 if e >= 0 else -1.0
        if t >= c["max_s"]:
            return "out of time"
        if self.phase in ("turn", "trim"):
            trim = self.phase == "trim"
            if off <= (c["trim_stop_early_deg"] if trim else c["stop_early_deg"]):
                self.phase, self.since = "settle", t
                return (0.0, 0.0)
            if self._stalled(-off, t, c["stall_deg"], c["stall_s"]):
                return "stuck"
            return (c["trim_forward"] if trim else c["forward"], way * (c["trim_rate"] if trim else self.rate))
        if t - self.since < c["settle_s"]:
            return (0.0, 0.0)
        if off <= c["tolerance_deg"]:
            return "reached"
        if self.trims_left <= 0:
            return "trimmed out"
        self.trims_left -= 1
        self.phase = "trim"
        self.mark = None                            # a trim's progress counts from its own start
        return (c["trim_forward"], way * c["trim_rate"])


DONE_WORDS = {
    "reached": None,
    "out of time": "ran out of time before it got there",
    "stuck": "could not get there at the speeds a duck may be sent",
    "trimmed out": "stopped short of a quarter turn after its trims",
}
