"""Running what the duck read, the way Studio runs a plan, and watching for the next card.

ONE ROW, ONE BEHAVIOUR. `beats` and `run` are `RobotPlan` and
`RobotPlanRunner` (StudioKit/Sources/StudioKit/RobotPlan.swift) in Python, with
their numbers: Pollen's pad limits from `DuckDrive` (0.3 m/s, 1.5 rad/s), the
router's shares for slow, normal and fast, two seconds a step, a kick held 0.5
s and a roll 1.0 s plus a second to settle, nothing over two minutes. So the
same row of cards moves the duck the same way whether the duck read it itself
or Studio read it through the duck's camera. `tests/test_runner.py` holds the
numbers to RobotPlan's.

ONE THING THE DUCK DOES THAT STUDIO DOES NOT YET. Studio keeps a Look card in
the plan and does not send it ("the head stays where it is"). On the robot,
`robot.look` is one call away, so `--heads` sends it; it is off by default so
that the two stay the same until Studio sends heads too.

THE DUCK ANSWERS. When it sees a card it chirps; when it has read a whole row
it says hello, waits for hands to leave the table, and runs it; a Start with no
End gets the rising "inquire". A class hears the duck read, which is the
reading made visible, and a silent duck that did nothing is the worst outcome a
reader can have.
"""

from __future__ import annotations

import time
from dataclasses import dataclass

from .program import Program, Step

# DuckDrive and RobotPlan, number for number.
MAX_FORWARD, MAX_BACKWARD, MAX_TURN = 0.3, 0.3, 1.5
SHARES = {"slow": 1.0 / 3.0, "normal": 2.0 / 3.0, "fast": 1.0}
DEFAULT_SECONDS = 2.0
HOLD_SECONDS = 0.1
MAX_MOVE_SECONDS = 30.0
MAX_SECONDS = 120.0
SETTLE_SECONDS = 1.0
ROBOTD_SKILL = {"kick_left": "kick_left", "kick_right": "kick_right", "sit_or_stand": "sit_toggle",
                "roll": "roulade", "peck_ground": "ground_pick"}
SKILL_SECONDS = {"kick_left": 0.5, "kick_right": 0.5, "roulade": 1.0, "ground_pick": 2.8, "sit_toggle": 2.0}
TICK = 0.05     # robot.move at 20 Hz, the bottom of the contract's 20 to 50

# Where a Look card points the head, as a point in the trunk frame (metres; the floor is about
# 0.12 m below the trunk origin, duck-ipc-proto LookParams).
LOOK_AT = {"straight": (0.5, 0.0, 0.05), "look_left": (0.4, 0.3, 0.05), "look_right": (0.4, -0.3, 0.05),
           "look_up": (0.4, 0.0, 0.35), "look_down": (0.3, 0.0, -0.12)}
FLOOR_AT = (0.32, 0.0, -0.12)


@dataclass
class Beat:
    kind: str                       # move, sound, skill
    clause: str
    twist: tuple[float, float, float] = (0.0, 0.0, 0.0)
    seconds: float = 0.0
    name: str = ""                  # the sound tag or the robotd skill
    head: str = "straight"


class Refusal(Exception):
    pass


def twist(action: str, speed: str) -> tuple[float, float, float]:
    share = 1.0 if action == "stop" else SHARES.get(speed, 2.0 / 3.0)
    return {"walk_forward": (MAX_FORWARD * share, 0.0, 0.0),
            "walk_backward": (-MAX_BACKWARD * share, 0.0, 0.0),
            "turn_left": (0.0, 0.0, MAX_TURN * share),
            "turn_right": (0.0, 0.0, -MAX_TURN * share),
            "stop": (0.0, 0.0, 0.0)}[action]


def beats(steps: list[Step]) -> list[Beat]:
    out, total = [], 0.0
    for s in steps:
        a = s.action
        if a in ROBOTD_SKILL:
            name = ROBOTD_SKILL[a]
            secs = SKILL_SECONDS.get(name, 1.0)
            out.append(Beat("skill", s.clause, seconds=secs, name=name))
            total += secs + SETTLE_SECONDS
        elif a == "make_sound":
            out.append(Beat("sound", s.clause, name=s.labels.get("sound", "chirp")))
        elif a in ("walk_forward", "walk_backward", "turn_left", "turn_right", "stop"):
            secs = min(max(DEFAULT_SECONDS, HOLD_SECONDS), MAX_MOVE_SECONDS)
            out.append(Beat("move", s.clause, twist=twist(a, s.labels.get("speed", "normal")),
                            seconds=secs, head=s.labels.get("head", "straight")))
            total += secs
    if not out:
        raise Refusal("Every card was skipped, so there is nothing to send.")
    if total > MAX_SECONDS:
        raise Refusal(f"This row runs {total:.0f} s, and a row on a duck is held to {MAX_SECONDS:.0f} s "
                      "so somebody is still watching when it ends.")
    return out


def run(plan_beats: list[Beat], robot, heads: bool = False, sleep=time.sleep, say=print) -> str:
    """RobotPlanRunner.run: skills checked first, every move held at 20 Hz, a stop at the end."""
    wanted = sorted({b.name for b in plan_beats if b.kind == "skill"})
    durations: dict[str, float] = {}
    if wanted:
        reply = robot.call("robot.skills") or {}
        names = [r["name"] for r in reply.get("skills", []) if "name" in r]
        for r in reply.get("skills", []):
            if isinstance(r.get("duration"), (int, float)):
                durations[r["name"]] = float(r["duration"])
        names += [n for n in reply.get("built_in", []) if n not in names]
        missing = [n for n in wanted if n not in names]
        if missing:
            raise Refusal(f"This duck has no {', '.join(missing)}. Nothing was sent.")
    looking = "straight"
    try:
        for b in plan_beats:
            say(f"  {b.clause}")
            if heads and b.kind == "move" and b.head != looking:
                x, y, z = LOOK_AT[b.head]
                robot.call("robot.look", {"x": x, "y": y, "z": z})
                looking = b.head
            if b.kind == "move":
                hold(robot, b.twist, b.seconds, sleep)
            elif b.kind == "sound":
                try:
                    robot.call("robot.sound", {"tag": b.name})
                except Exception as e:          # a sound is not worth stopping a row for
                    say(f"  (no {b.name}: {e})")
            elif b.kind == "skill":
                robot.call("robot.stop")
                answer = robot.call("robot.do", {"skill": b.name}) or {}
                if answer.get("accepted") is not True:   # RobotIntentAnswer: no "accepted" is a no
                    robot.call("robot.stop")
                    why = answer.get("reason") or ("The duck answered without saying whether it accepted."
                                                   if "accepted" not in answer else f"The duck refused {b.name}.")
                    return f"refused at {b.clause}: {why}"
                hold(robot, (0.0, 0.0, 0.0), durations.get(b.name, b.seconds) + SETTLE_SECONDS, sleep)
    finally:
        try:
            robot.call("robot.stop")
            if heads and looking != "straight":
                x, y, z = LOOK_AT["straight"]
                robot.call("robot.look", {"x": x, "y": y, "z": z})
        except Exception:
            pass
    return "finished"


def hold(robot, tw: tuple[float, float, float], seconds: float, sleep=time.sleep) -> None:
    n = max(1, round(seconds / TICK))
    for _ in range(n):
        robot.notify("robot.move", {"vx": tw[0], "vy": tw[1], "vyaw": tw[2]})
        sleep(TICK)


# robotd's idle look-around (robotd/src/idle_head.rs) starts once nobody has steered the head for
# `[idle] after_s`, two seconds as shipped. The reader steers it more often than that.
GAZE_EVERY = 1.0


class Gaze:
    """Holds the duck's head still while it watches for cards.

    FOUND IN DUCK-SIM, 2026-10-14. A card held up in front of a duck that is standing still was
    acted on three times in twenty seconds: robotd's idle look-around swung the head about 18°
    each way, the card left the picture for longer than the watcher's `forget`, and came back as
    a new card. A duck reading cards looks at them. So the reader steers the head itself, as
    LookResult's own doc says to hold a gaze: `robot.look` once, then its answer's joints again
    as `robot.head` every second. With no point to look at, the joints are the head's rest
    (all zero), which is the view a duck nobody steers has, without the wandering."""

    def __init__(self, robot, point: tuple[float, float, float] | None = None, every: float = GAZE_EVERY):
        self.robot, self.point, self.every = robot, point, every
        self.joints: dict | None = None
        self.last = -1e9

    def aim(self, now: float) -> None:
        """Look at the point (again, after a row has moved the head) and keep the joints."""
        self.last = now
        if self.point is None:
            self.joints = {}
            self.robot.notify("robot.head", self.joints)
            return
        x, y, z = self.point
        answer = self.robot.call("robot.look", {"x": x, "y": y, "z": z}) or {}
        head = answer.get("head")
        self.joints = head if isinstance(head, dict) else None

    def tick(self, now: float) -> None:
        if now - self.last < self.every:
            return
        if self.joints is None:
            self.aim(now)
        else:
            self.last = now
            self.robot.notify("robot.head", self.joints)


# ---------------------------------------------------------------- watching
@dataclass
class Event:
    kind: str           # card, row, unfinished
    program: Program


class Watcher:
    """Turns a stream of single-picture reads into a few decisions.

    A READ MUST HOLD STILL. One picture can catch a hand mid-swap; `need` pictures in a row reading
    the same thing is a card someone is showing. A card that has fired does not fire again until
    it has been gone for `forget` seconds, so holding a card up is one kick, not one a frame."""

    def __init__(self, need: int = 3, forget: float = 1.5, unfinished_after: float = 4.0):
        self.need, self.forget, self.unfinished_after = need, forget, unfinished_after
        self._key, self._count = None, 0
        self._fired_key, self._last_seen_fired = None, -1e9
        self._start_since = None
        self._asked = False

    def feed(self, program: Program, now: float) -> Event | None:
        key = (program.kind, program.words, program.complete)
        if program.kind == "none" or not program.steps:
            key = None
        if key == self._key:
            self._count += 1
        else:
            self._key, self._count = key, 1 if key else 0
        if self._fired_key is not None and key == self._fired_key:
            self._last_seen_fired = now
        if self._fired_key is not None and now - self._last_seen_fired > self.forget:
            self._fired_key = None
        # A Start with no End, held long enough to be on purpose.
        if program.kind == "row" and not program.complete:
            self._start_since = self._start_since or now
            if not self._asked and now - self._start_since >= self.unfinished_after:
                self._asked = True
                return Event("unfinished", program)
        else:
            self._start_since, self._asked = None, False
        if key and self._count >= self.need and key != self._fired_key:
            if program.kind == "row" and not program.complete:
                return None
            self._fired_key, self._last_seen_fired = key, now
            return Event("card" if program.kind == "card" else "row", program)
        return None
