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
FORMATS = ("duck-card-loop/1", "duck-card-loop/3", "duck-card-loop/4")    # /3 adds `calibrate` (DriftCal), /4 `compass` (MatFix)
CARDS = ("walk_forward", "walk_backward", "turn_left", "turn_right")


def load_spec(path: pathlib.Path = SPEC_FILE) -> dict:
    spec = json.loads(path.read_text())
    if spec.get("format") not in FORMATS:
        raise ValueError(f"{path.name} is not {' or '.join(FORMATS)}")
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

    def __init__(self, action: str, board: Pose, speed: str | None = None, spec: dict | None = None,
                 lead_deg: float | None = None):
        if action not in CARDS:
            raise ValueError(f"{action} is not a Walk or Turn card")
        self.spec = spec or SPEC
        self.action, self.board = action, board
        self.rate = speed_of(self.spec, action, speed)
        d = self.spec["square_m"]
        self.mark, self.mark_t = None, 0.0          # the last progress made, and when
        # THE LEAD. A turn is commanded still `lead` degrees short of its heading, because the duck
        # coasts on after the zero twist, and how far is not known in advance: 6 to 17 degrees
        # at 1.0 rad/s in duck-sim, 20 to 31 on a slippery floor with a late state stream
        # (cardreader/sim/sysid, results/). So the first stop is followed by a settle in which
        # the coast is measured (`coast_deg`), and a trim stops that far short. A card that knows
        # nothing yet (`lead_deg` None: the row's first turn) stops `approach_deg` short, far
        # enough that it seldom overshoots, measures, then trims if it must; the runner hands the
        # mean of the row's measured coasts to each later Turn card as its `lead_deg`. A short
        # trim turns the trunk and springs back, so a trim is held `trim_min_s` and only an error
        # past `tolerance_deg` is trimmed.
        t = self.spec["turn"]
        self.lead = self._clamp_lead(t["approach_deg"] if lead_deg is None else lead_deg)
        self.coast_deg: float | None = None
        self.stop_e, self.stop_way = 0.0, 1.0
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
            # A trim is held at least `trim_min_s`: a shorter one never gets past the gait's dead band.
            if off <= (self.trim_lead() if trim else self.lead) and (not trim or t - self.since >= c["trim_min_s"]):
                self.phase, self.since = "settle", t
                self.stop_e, self.stop_way = e, way
                return (0.0, 0.0)
            if self._stalled(-off, t, c["stall_deg"], c["stall_s"]):
                return "stuck"
            return (c["trim_forward"] if trim else c["forward"], way * (c["trim_rate"] if trim else self.rate))
        if t - self.since < c["settle_s"]:
            return (0.0, 0.0)
        if self.phase == "settle":
            if self.coast_deg is None:
                # How far it went on after the first zero twist, in the direction it was turning.
                # Only the first: a trim may be too short a command to say anything about it.
                self.coast_deg = self._clamp_lead((self.stop_e - e) * self.stop_way * 180.0 / math.pi)
            self.phase = "settled"
        if off <= c["tolerance_deg"]:
            return "reached"
        if self.trims_left <= 0:
            return "trimmed out"
        self.trims_left -= 1
        self.phase, self.since = "trim", t
        self.mark = None                            # a trim's progress counts from its own start
        return (c["trim_forward"], way * c["trim_rate"])

    def _clamp_lead(self, v: float) -> float:
        lo, hi = self.spec["turn"]["lead_deg"]
        return max(lo, min(hi, v))

    def trim_lead(self) -> float:
        """How far short a trim stops: the coast this card measured at its first stop (a trim
        only ever follows a settle, so it is always known by then)."""
        # The coast was measured turning at the card's rate; a trim turns at `trim_rate`, and the coast
        # scales with how fast it was going.
        known = self.coast_deg if self.coast_deg is not None else self.lead
        return known * self.spec["turn"]["trim_rate"] / self.rate


class DriftCal:
    """CALIBRATE AT EVERY STOP (duck-card-loop/3, docs/PACKS.md, pre-registered 2026-10-17).

    Odometry's yaw is the trunk IMU's, and an IMU's heading drifts: up to 0.5 deg/s in the
    randomized conditions, 30 degrees over a minute-long row, and the controller cannot see it.
    Standing still the true turn rate is about zero, so the yaw rate odometry reports then is the
    drift. `still()` windows feed it; the rate is the pooled least-squares slope of yaw on time over
    every window so far, each window with its own intercept; `correct()` takes it out of every pose:
    heading less rate times the time since the first pose, and each position step rotated by the
    same correction, so position integrates the corrected heading."""

    def __init__(self, cal: dict):
        self.still_after = float(cal["still_after_s"])
        self.max_rate = math.radians(float(cal["max_dps"]))
        self.rate = 0.0                       # rad/s, the drift taken out
        self.sxy = self.sxx = 0.0             # pooled sums over every finished window
        self.windows = 0
        self.cur: list[tuple[float, float]] | None = None
        self.cur_start: float | None = None
        self.t0: float | None = None
        self.raw: Pose | None = None
        self.x = self.y = 0.0

    def begin_still(self) -> None:
        self.cur, self.cur_start = [], None

    def sample_still(self, t: float, yaw: float) -> None:
        if self.cur is None:
            return
        if self.cur_start is None:
            self.cur_start = t
        if t - self.cur_start < self.still_after or (self.cur and t <= self.cur[-1][0]):
            return
        y = yaw if not self.cur else self.cur[0][1] + wrap(yaw - self.cur[0][1])
        self.cur.append((t, y))

    def end_still(self) -> None:
        w, self.cur = self.cur or [], None
        if len(w) < 3:
            return
        tm = sum(t for t, _ in w) / len(w)
        ym = sum(y for _, y in w) / len(w)
        self.sxy += sum((t - tm) * (y - ym) for t, y in w)
        self.sxx += sum((t - tm) ** 2 for t, _ in w)
        self.windows += 1
        if self.sxx > 0:
            self.rate = max(-self.max_rate, min(self.max_rate, self.sxy / self.sxx))

    def correct(self, t: float, pose: Pose) -> Pose:
        if self.t0 is None:
            self.t0, self.raw, self.x, self.y = t, pose, pose.x, pose.y
        d = -self.rate * (t - self.t0)
        dx, dy = pose.x - self.raw.x, pose.y - self.raw.y
        self.x += dx * math.cos(d) - dy * math.sin(d)
        self.y += dx * math.sin(d) + dy * math.cos(d)
        self.raw = pose
        return Pose(self.x, self.y, wrap(pose.h + d))


class MatFix:
    """THE MAT AS A COMPASS (duck-card-loop/4, docs/PACKS.md, pre-registered 2026-10-18).

    `/3` showed a sensor inside the duck cannot tell drift from the duck's own creep; the taped
    grid is outside it. At every stop `matcam.floor_points` turns one head-camera frame into floor
    points of tape, in the duck's own frame; `fit` places them where the controller believes the
    duck is, and finds the small turn about the duck and shift (`dh`, `dx`, `dy`, in the row's
    frame) that lays them on the grid: lines `square_m` apart, half a square either side of the
    square the row began on, along and across the heading it began with. Each point counts for
    the nearer line family; a family with fewer than `min_points` points fixes nothing across it.
    A fit with too few points, or one larger than `max_fix_deg` or `max_fix_m` (it would be a
    neighbouring line, not this one), is refused. `correct` applies every accepted fix so far to
    odometry: a turn and a shift, kept as one rigid correction."""

    def __init__(self, compass: dict, square_m: float):
        self.s = float(square_m)
        self.min_points = int(compass["min_points"])
        self.inlier = float(compass["inlier_m"])
        self.max_h = math.radians(float(compass["max_fix_deg"]))
        self.max_m = float(compass["max_fix_m"])
        self.ct, self.cx, self.cy = 0.0, 0.0, 0.0       # odometry to the mat's frame
        self.origin: Pose | None = None                 # the row's first corrected pose
        self.fixes: list[tuple[float, float, float] | None] = []     # each look: (dh, dx, dy) or None

    def correct(self, pose: Pose) -> Pose:
        c, s = math.cos(self.ct), math.sin(self.ct)
        out = Pose(c * pose.x - s * pose.y + self.cx, s * pose.x + c * pose.y + self.cy, wrap(pose.h + self.ct))
        if self.origin is None:
            self.origin = out
        return out

    def fit(self, points, pose: Pose):
        """`points`: (forward, left) metres from the duck, `pose`: corrected, odometry's frame.
        Answers (dh, dx, dy) in the row's frame, applied, or None when refused."""
        o = self.origin or pose
        co, so = math.cos(o.h), math.sin(o.h)
        px, py = pose.x - o.x, pose.y - o.y
        pu, pv = co * px + so * py, -so * px + co * py              # the duck, row frame
        ph = wrap(pose.h - o.h)
        ch, sh = math.cos(ph), math.sin(ph)
        q = [(pu + ch * f - sh * l, pv + sh * f + ch * l) for f, l in points]
        if len(q) < self.min_points:
            self.fixes.append(None)
            return None
        dh, du, dv = self._coarse(q, pu, pv)
        nu = nv = 0
        for _ in range(8):
            c, s = math.cos(dh), math.sin(dh)
            a = [[0.0] * 3 for _ in range(3)]
            b = [0.0] * 3
            nu = nv = 0
            for qu, qv in q:
                ru, rv = qu - pu, qv - pv
                u = pu + c * ru - s * rv + du
                v = pv + s * ru + c * rv + dv
                eu = u - self.s * (math.floor(u / self.s - 0.5) + 0.5)     # past the line below
                ev = v - self.s * (math.floor(v / self.s - 0.5) + 0.5)
                eu = eu - self.s if eu > self.s / 2 else eu
                ev = ev - self.s if ev > self.s / 2 else ev
                if abs(eu) <= abs(ev):
                    if abs(eu) > self.inlier:
                        continue
                    j, r = (-(v - pv), 1.0, 0.0), eu
                    nu += 1
                else:
                    if abs(ev) > self.inlier:
                        continue
                    j, r = (u - pu, 0.0, 1.0), ev
                    nv += 1
                for i in range(3):
                    b[i] -= j[i] * r
                    for k in range(3):
                        a[i][k] += j[i] * j[k]
            if nu + nv < self.min_points:
                self.fixes.append(None)
                return None
            free = [0] + ([1] if nu >= self.min_points else []) + ([2] if nv >= self.min_points else [])
            du = du if 1 in free else 0.0           # no lines of a family seen: no shift across them
            dv = dv if 2 in free else 0.0
            step = _solve([[a[i][k] for k in free] for i in free], [b[i] for i in free])
            if step is None:
                self.fixes.append(None)
                return None
            got = dict(zip(free, step))
            dh += got.get(0, 0.0)
            du += got.get(1, 0.0)
            dv += got.get(2, 0.0)
            if max(abs(x) for x in step) < 1e-5:
                break
        if abs(dh) > self.max_h or math.hypot(du, dv) > self.max_m:
            self.fixes.append(None)
            return None
        # Turn dh about the duck, then shift (du, dv) of the row's frame, made a correction of
        # odometry: new = T(old), T a turn dh about the duck's corrected position and a shift.
        c, s = math.cos(dh), math.sin(dh)
        ex, ey = self.cx - pose.x, self.cy - pose.y
        sx, sy = co * du - so * dv, so * du + co * dv
        self.cx = c * ex - s * ey + pose.x + sx
        self.cy = s * ex + c * ey + pose.y + sy
        self.ct = wrap(self.ct + dh)
        self.fixes.append((dh, du, dv))
        return dh, du, dv


    def _coarse(self, q, pu, pv):
        """The start for the fit: every turn about the duck on a half-degree grid within
        `max_fix_deg`, each scored by how tightly the points bunch across each line family modulo
        the square (the length of their mean phase); the best turn, and the shifts its phases give,
        the nearer way round."""
        step = max(1, len(q) // 600)
        sub = q[::step]
        k = 2 * math.pi / self.s
        best = None
        n = int(math.degrees(self.max_h) / 0.5)
        for i in range(-n, n + 1):
            dh = math.radians(0.5 * i)
            c, s = math.cos(dh), math.sin(dh)
            cu = su = cv = sv = 0.0
            for qu, qv in sub:
                ru, rv = qu - pu, qv - pv
                u = pu + c * ru - s * rv - self.s / 2
                v = pv + s * ru + c * rv - self.s / 2
                cu += math.cos(k * u)
                su += math.sin(k * u)
                cv += math.cos(k * v)
                sv += math.sin(k * v)
            ru, rv = math.hypot(cu, su), math.hypot(cv, sv)
            if best is None or ru + rv > best[0]:
                # A family whose points do not bunch (too few on its lines) gives no shift.
                best = (ru + rv, dh, -math.atan2(su, cu) / k if ru > 0.2 * len(sub) else 0.0,
                        -math.atan2(sv, cv) / k if rv > 0.2 * len(sub) else 0.0)
        return best[1], best[2], best[3]


def _solve(a, b):
    """a x = b for a small symmetric system, by Gaussian elimination; None if singular."""
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for i in range(n):
        piv = max(range(i, n), key=lambda r: abs(m[r][i]))
        if abs(m[piv][i]) < 1e-9:
            return None
        m[i], m[piv] = m[piv], m[i]
        for r in range(n):
            if r != i:
                f = m[r][i] / m[i][i]
                for k in range(i, n + 1):
                    m[r][k] -= f * m[i][k]
    return [m[i][n] / m[i][i] for i in range(n)]


DONE_WORDS = {
    "reached": None,
    "out of time": "ran out of time before it got there",
    "stuck": "could not get there at the speeds a duck may be sent",
    "trimmed out": "stopped short of a quarter turn after its trims",
}
