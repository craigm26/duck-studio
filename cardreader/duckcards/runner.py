"""Running what the duck read, the way Studio runs a plan, and watching for the next card.

ONE ROW, ONE BEHAVIOUR. `beats` and `run` are `RobotPlan` and
`RobotPlanRunner` (StudioKit/Sources/StudioKit/RobotPlan.swift) in Python, with
their numbers: Pollen's pad limits from `DuckDrive` (0.3 m/s, 1.0 rad/s), the
router's shares for slow, normal and fast, two seconds a step, a kick held 0.5
s and a roll 1.0 s plus a second to settle, nothing over two minutes. So the
same row of cards moves the duck the same way whether the duck read it itself
or Studio read it through the duck's camera. `tests/test_runner.py` holds the
numbers to RobotPlan's.

ONE THING THE DUCK DOES THAT STUDIO DOES NOT YET. Studio keeps a Look card in
the plan and does not send it ("the head stays where it is"). On the robot,
`robot.look` is one call away, so `--heads` sends it; it is off by default so
that the two stay the same until Studio sends heads too.

WALK AND TURN CARDS ARE TIMED ON A DUCK FOR NOW. Closed-loop cards ship off for real ducks
(`duck-card-loop.json` `enabled_on_robot: false`, docs/PACKS.md "Acceptance"): a Walk or Turn card
runs as the timed card it was and the reader says `cardloop.OFF_NOTE` once per row.
`--measured-cards` turns them on, for duck-sim work. On, they close on odometry when the duck
reports it: a Walk card is one board square
and a Turn card a quarter turn (`cardloop.py`, the same spec and rules as StudioKit's
`DuckCardLoop`), driven on `odom` from robotd's state stream when `run` is given one that carries
it. A duck that does not report odometry (a robotd from before the estimator, or no state stream)
runs them as timed cards, the RobotPlan numbers above, and the reader says so once per row.

THE DUCK ANSWERS. When it sees a card it chirps; when it has read a whole row
it says hello, waits for hands to leave the table, and runs it; a Start with no
End gets the rising "inquire". A class hears the duck read, which is the
reading made visible, and a silent duck that did nothing is the worst outcome a
reader can have.
"""

from __future__ import annotations

import math
import time
from dataclasses import dataclass

from . import cardloop, pan
from .layout import Layout
from .program import Program, Step, read

# DuckDrive and RobotPlan, number for number. Inside Pollen's pad envelope (`cardloop.ENVELOPE`,
# PadDriveParams::default(): 0.4 m/s, 1.0 rad/s); tests/test_cardloop.py holds them to it.
MAX_FORWARD, MAX_BACKWARD, MAX_TURN = 0.3, 0.3, 1.0
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
    kind: str                       # move, card, sound, skill
    clause: str
    twist: tuple[float, float, float] = (0.0, 0.0, 0.0)
    seconds: float = 0.0
    name: str = ""                  # the sound tag or the robotd skill
    head: str = "straight"
    action: str = ""                # a card beat's Walk or Turn card
    speed: str = "normal"


# Said once per row when Walk and Turn cards cannot close on odometry.
# The same sentences as StudioKit's `DuckCardLoop.timedNote` and `.lostNote`.
TIMED_NOTE = ("This duck does not report odometry, so Walk and Turn cards run as timed cards, "
              "two seconds each, and do not land on board squares.")
LOST_NOTE = "The duck stopped reporting where it is, so the row stopped there."
FELL_NOTE = "The duck fell, so the row stopped there."
# How a closed-loop card ended, and what is said when it did not arrive: the row ends there, the
# duck commanded still (docs/PACKS.md, "Acceptance"). StudioKit's `RobotPlanRunner.CardEnd.said`.
ENDED = {
    "reached": None,
    "lost": LOST_NOTE,
    "fell": FELL_NOTE,
    "out of time": "The card ran out of time before it got there, so the row stopped there.",
    "trimmed out": "The card stopped short of a quarter turn after its trims, so the row stopped there.",
    "stuck": "The duck could not do this card at the speeds it may be sent, so the row stopped there.",
}


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
            # A Walk or Turn card keeps its timed twist: it is what runs on a duck that does not
            # report odometry, and its seconds are what the row's length is held to.
            secs = min(max(DEFAULT_SECONDS, HOLD_SECONDS), MAX_MOVE_SECONDS)
            speed = s.labels.get("speed", "normal")
            out.append(Beat("card" if a in cardloop.CARDS else "move", s.clause, twist=twist(a, speed),
                            seconds=secs, head=s.labels.get("head", "straight"), action=a, speed=speed))
            total += secs
    if not out:
        raise Refusal("Every card was skipped, so there is nothing to send.")
    if total > MAX_SECONDS:
        raise Refusal(f"This row runs {total:.0f} s, and a row on a duck is held to {MAX_SECONDS:.0f} s "
                      "so somebody is still watching when it ends.")
    return out


def run(plan_beats: list[Beat], robot, heads: bool = False, sleep=time.sleep, say=print,
        state=None, clock=time.time, measured: bool | None = None) -> str:
    """RobotPlanRunner.run: skills checked first, every move held at 20 Hz, a stop at the end.

    `state()`, when given, answers the latest `robot.state` params and when they arrived (on
    `clock`), or None: Walk and Turn cards close on its `odom` when it has one AND measured cards
    are on. `measured` is the spec's `enabled_on_robot` unless given (`--measured-cards`); off,
    every Walk and Turn card runs timed and `cardloop.OFF_NOTE` is said once."""
    if measured is None:
        measured = cardloop.ENABLED_ON_ROBOT
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
    board: cardloop.Pose | None = None      # where the duck should be, odometry's frame
    timed_said = False
    coasts: list[float] = []               # every Turn card's measured coast this row (cardloop, THE LEAD)
    try:
        for b in plan_beats:
            say(f"  {b.clause}")
            if heads and b.kind in ("move", "card") and b.head != looking:
                x, y, z = LOOK_AT[b.head]
                robot.call("robot.look", {"x": x, "y": y, "z": z})
                looking = b.head
            if b.kind == "card" and not measured:
                if not timed_said:
                    say(f"  {cardloop.OFF_NOTE}")
                    timed_said = True
                hold(robot, b.twist, b.seconds, sleep)
            elif b.kind == "card":
                pose = _pose_now(state, clock)
                if pose is None and board is not None:
                    # A row that has been closing on odometry does not fall back to timed mid-row:
                    # the pose going missing between cards is the duck losing its state.
                    say(f"  {LOST_NOTE}")
                    robot.call("robot.stop")
                    return f"stopped at {b.clause}: {LOST_NOTE}"
                if pose is None:
                    if not timed_said:
                        say(f"  {TIMED_NOTE}")
                        timed_said = True
                    hold(robot, b.twist, b.seconds, sleep)
                    board = None
                    continue
                loop = cardloop.CardLoop(b.action, board or pose, b.speed, lead_deg=sum(coasts) / len(coasts) if coasts else None)
                done = drive(loop, robot, state, sleep, clock)
                board = loop.board_after
                if getattr(loop, "coast_deg", None) is not None:
                    coasts.append(loop.coast_deg)
                if ENDED.get(done):
                    say(f"  {ENDED[done]}")
                    robot.call("robot.stop")
                    return f"stopped at {b.clause}: {ENDED[done]}"
                hold(robot, (0.0, 0.0, 0.0), cardloop.SPEC["between_s"], sleep)
            elif b.kind == "move":
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
                # A skill moves the duck in ways the board does not count: the board's square is
                # put back where the duck stands, and its heading is kept.
                if board is not None:
                    pose = _pose_now(state, clock)
                    board = cardloop.Pose(pose.x, pose.y, board.h) if pose else None
    finally:
        try:
            robot.call("robot.stop")
            if heads and looking != "straight":
                x, y, z = LOOK_AT["straight"]
                robot.call("robot.look", {"x": x, "y": y, "z": z})
        except Exception:
            pass
    return "finished"


def _pose_now(state, clock) -> cardloop.Pose | None:
    """The duck's odometry now, or None: no state stream, no `odom` in it, or a frame older
    than the spec's `stale_s`."""
    if state is None:
        return None
    got = state()
    if not got:
        return None
    params, at = got
    if clock() - at > cardloop.SPEC["stale_s"]:
        return None
    return cardloop.odometry(params)


def _fallen(state) -> bool:
    """Whether the latest `robot.state` says the duck is down (`safety.fallen`)."""
    got = state() if state is not None else None
    return bool(got and ((got[0] or {}).get("safety") or {}).get("fallen") is True)


def drive(loop: "cardloop.CardLoop", robot, state, sleep=time.sleep, clock=time.time) -> str:
    """One Walk or Turn card on odometry, `robot.move` at the spec's rate. Answers how it ended:
    the loop's own word, "lost" when the pose stops arriving, or "fell"."""
    tick = 1.0 / cardloop.SPEC["control_hz"]
    n = 0
    while True:
        if _fallen(state):
            robot.notify("robot.move", {"vx": 0.0, "vy": 0.0, "vyaw": 0.0})
            return "fell"
        pose = _pose_now(state, clock)
        if pose is None:
            robot.notify("robot.move", {"vx": 0.0, "vy": 0.0, "vyaw": 0.0})
            return "lost"
        answer = loop.step(pose, n * tick)
        if isinstance(answer, str):
            robot.notify("robot.move", {"vx": 0.0, "vy": 0.0, "vyaw": 0.0})
            return answer
        robot.notify("robot.move", {"vx": answer[0], "vy": 0.0, "vyaw": answer[1]})
        sleep(tick)
        n += 1


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
    as `robot.head` every second. With no point to look at, the command is robotd's zero head
    command, the head's rest: the view a duck nobody steers has, without the wandering. (A zero
    command is not zero joints: in duck-sim it held the neck at 12.5° and the head pitched 26°.)

    Checked in duck-sim on 2026-10-14: a card held up for 45 s was kicked for once, and robotd's
    idle look-around stopped and stayed stopped; with --let-head-wander, five kicks."""

    def __init__(self, robot, point: tuple[float, float, float] | None = None, every: float = GAZE_EVERY):
        self.robot, self.point, self.every = robot, point, every
        self.joints: dict | None = None         # what the head is held at now
        self.watching: dict | None = None       # what it is held at while it watches
        self.last = -1e9
        self.aimed = -1e9                       # when it last looked back to where it watches

    def aim(self, now: float) -> None:
        """Look at the point (again, after a row has moved the head) and keep the joints."""
        self.last = self.aimed = now
        if self.point is None:
            self.joints = self.watching = {}
            self.robot.notify("robot.head", self.joints)
            return
        x, y, z = self.point
        answer = self.robot.call("robot.look", {"x": x, "y": y, "z": z}) or {}
        head = answer.get("head")
        self.joints = self.watching = head if isinstance(head, dict) else None

    @property
    def yaw(self) -> float:
        """The head_yaw the head is held at, radians (0 when nothing has steered it)."""
        return float((self.joints or {}).get("head_yaw", 0.0))

    def turn(self, yaw: float, now: float) -> dict:
        """Turn the head to `yaw` (robotd's head_yaw, radians, more is left), every other joint
        where it is held while watching, and hold it there.

        ONLY THE YAW TURNS. `robot.look` would solve head_pitch afresh for every point, and a look
        that pitches as well as turns is not the turn `pan.join` undoes. A turn of head_yaw alone
        is a turn about the picture's own vertical at any pitch, so it slides the view along a row
        in a rail, and along a row on the floor too: the row lies in the plane the turn sweeps."""
        if self.joints is None:
            self.aim(now)
        joints = {"neck_pitch": 0.0, "head_pitch": 0.0, "head_roll": 0.0, **(self.watching or {}),
                  "head_yaw": yaw}
        self.joints, self.last = joints, now
        self.robot.notify("robot.head", joints)
        return joints

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

    def ran(self, now: float) -> None:
        """A run has ended. The seconds it took are not seconds the cards were gone: the duck was
        busy, not looking, and the row is still on the table. Found in duck-sim on 2026-10-14: a
        row took about 7 s to run, longer than `forget`, and ran again as soon as it was seen."""
        if self._fired_key is not None:
            self._last_seen_fired = now

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


# ---------------------------------------------------------------- scanning
# How long the head takes to settle after a turn before a picture is worth reading. robotd eases
# every head command in, 0.2 of the way a tick at 50 Hz (`head_alpha`, robotd-params: a 0.09 s
# time constant, 99% of a turn in 0.41 s), then the policy's own 0.5 low-pass and the servo
# follow, and a frame can be a thirtieth of a second old. At 0.6 s a thousandth of the turn is
# left, 0.02° of an 18° turn; the looks are lined up on the cards they share in any case.
SETTLE_HEAD = 0.6
# How far the head turns from where it watches, each way. robotd's head_yaw travels ±170° (the
# MJCF), so `clamped` never stops a scan first; this does. A card standing in a rail that far round
# is turned that far from the camera and half again as far away, and in `tools/pan_envelope.py`
# no rail card more than about 35° (soft) to 45° (sharp) round was read at 35 to 60 cm, nor any
# floor card past 49°: a duck looking further round is looking away from the row.
YAW_MOST = math.radians(50.0)
# The most looks a scan takes, the first included.
MOST_LOOKS = 6
# A scan whose row came back unfinished is taken again after this many seconds, if the duck still
# sees the same part of the row: the End may have been put down where the duck cannot see it.
RESCAN = 10.0
# How long after the head is sent back to where it watches before a look is worth scanning from:
# robotd fades its idle look-around out over `[idle] fade_s` (1.5 s as shipped) once the head is
# steered, and then the head settles. Found in duck-sim on 2026-10-14: a scan begun as the reader
# started took its first look with the head still 11 to 14° round, called it straight ahead, and
# both of its turns were refused as not lining up.
HEAD_QUIET = 1.5 + SETTLE_HEAD


def _sides(way: int) -> str:
    return "right" if way > 0 else "left"


def scan(first: pan.Look, layout: Layout, gaze: Gaze, take, sleep=time.sleep, say=print, clock=time.time,
         settle: float = SETTLE_HEAD, most: float = YAW_MOST, looks: int = MOST_LOOKS) -> pan.Joined:
    """Turn the head along a row the first look cut off, a look at a time, and join the looks.

    The head turns (`pan.turns`) toward the cards a Start is waiting for, or toward the Start an
    End is waiting for, or both ways for a row cut off at both ends, by `pan.step` each time, so
    that every picture shares a whole card with the one before it. Each way stops when it finds
    what it was looking for, when the row ends inside the picture, when the head is as far round
    as YAW_MOST, after `looks` looks in all, or when a look does not line up with the ones before
    it (`pan.JoinError`), which is said. Then the head looks back to where it watches.

    `take()` is one picture's cards and its size: (list of Seen, (width, height))."""
    taken = [first]
    joined = pan.join(taken)
    home, turned = first.yaw, False
    for way, ahead in pan.turns(layout, first.size):
        side = _sides(way)
        at, k = home, 0
        while len(taken) < looks and not pan.done(joined, ahead):
            to = at - way * pan.step(taken[k], pan.row_in(joined, k))    # to the right is less yaw
            to = max(home - most, min(home + most, to))
            if abs(to - at) < 1e-6:
                say(f"[scan] the head turns no further {side}")
                break
            gaze.turn(to, clock())
            turned = True
            sleep(settle)
            gaze.tick(clock())
            seen, size = take()
            look = pan.Look(seen=seen, yaw=to, size=size)
            degrees = abs(math.degrees(to - home))
            try:
                joined = pan.join(taken + [look])
            except pan.JoinError as e:
                say(f"[scan] looked {side} {degrees:.0f} degrees, and the look was not used: {e}")
                break
            taken.append(look)
            at, k = to, len(taken) - 1
            n = joined.new[k]
            say(f"[scan] looked {side} {degrees:.0f} degrees: {n} more card{'' if n == 1 else 's'}")
            if not pan.runs_on(joined, k, ahead):
                break
    if turned:
        gaze.aim(clock())
        sleep(settle)
        row = pan.main_row(joined)
        say(f"[scan] looked back: {len(taken)} looks, {len(row.slots) if row else 0} cards in the row")
    return joined


@dataclass
class _Scanned:
    key: tuple
    program: Program
    when: float
    cards: list[str] | None = None      # the joined main row, as `Layout.describe` spells its cards


class Scanner:
    """When to scan, and what the duck read when it did.

    A ROW THE PICTURE CUTS OFF MUST HOLD STILL FIRST. A scan is a few seconds of a turning head, so
    it starts only when `need` pictures in a row show the same cards cut off the same way: a row
    still being laid out is not scanned at every card. Then the joined reading stands in for that
    view, picture after picture, while the duck sees the same cards (they are part of it), so the
    watcher's own rules decide: a complete row is read `need` times and runs after the hello; an
    unfinished one gets the "inquire". An unfinished reading is scanned again after RESCAN seconds,
    because the End may have been put down out of sight; a complete one stands until the view
    changes, so it runs once.

    A DRY RUN TURNS NOTHING. It sends nothing, so the head stays where it is and a joined reading
    would be one picture joined to itself; it says which way it would look and reads the one look."""

    def __init__(self, gaze: Gaze, take, deck, need: int = 3, rescan: float = RESCAN, dry: bool = False,
                 sleep=time.sleep, say=print, clock=time.time, settle: float = SETTLE_HEAD):
        self.gaze, self.take, self.deck, self.need, self.rescan, self.dry = gaze, take, deck, need, rescan, dry
        self.sleep, self.say, self.clock, self.settle = sleep, say, clock, settle
        self._key, self._count = None, 0
        self.last: _Scanned | None = None

    def read(self, look: pan.Look, layout: Layout, program: Program) -> Program:
        """The program to feed the watcher for this picture: its own, or the scan's."""
        wanted = pan.turns(layout, look.size)
        if not wanted:
            self._key, self._count = None, 0
            return program
        key = (tuple(tuple(r) for r in layout.describe()), tuple(wanted))
        last = self.last
        if last and last.key == key and (last.program.complete or self.clock() - last.when < self.rescan):
            return last.program
        # A ROW THAT RAN IS STILL THAT ROW FROM WHERE THE DUCK NOW STANDS. A kick moves the duck a
        # few centimetres and turns it a few degrees, so the next picture cuts the same row in
        # another place. Seen in duck-sim on 2026-10-14: the scan read the whole row again and it
        # ran three times. So a complete joined row stands in for any view whose cards it holds,
        # in order; a row changed where the duck can see it reads as changed.
        if last and last.program.complete and last.cards and pan.part_of(layout, last.cards):
            return last.program
        if self.clock() - self.gaze.aimed < HEAD_QUIET:
            self._key, self._count = None, 0
            return program
        self._count = self._count + 1 if key == self._key else 1
        self._key = key
        if self._count < self.need:
            return program
        self._count = 0
        if self.dry:
            way, ahead = wanted[0]
            step = math.degrees(pan.step(look, [s.card for s in pan.main_row(layout).slots]))
            self.say(f"[scan] would look {_sides(way)} {step:.0f} degrees for the "
                     f"{'cards after' if ahead else 'Start before'} these (a dry run turns nothing, so "
                     "nothing is joined)")
            self.last = _Scanned(key, program, self.clock())
            return program
        joined = scan(look, layout, self.gaze, self.take, sleep=self.sleep, say=self.say, clock=self.clock,
                      settle=self.settle)
        result = read(joined, self.deck)
        row = pan.main_row(joined)
        cards = ["/".join([s.card.card.code] + [u.card.code for u in s.under]) for s in row.slots] if row else None
        self.last = _Scanned(key, result, self.clock(), cards)
        return result
