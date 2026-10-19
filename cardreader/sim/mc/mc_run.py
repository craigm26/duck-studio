"""Monte Carlo of Duck Cards rows on Pollen's stack: the card reader's own runner
(`duckcards.runner.run`, closing Walk and Turn on `duckcards.cardloop`) driving the real robotd
and v8 velstand in duck-sim's MuJoCo body, scored against MuJoCo's ground truth.

    python3 cardreader/sim/mc/mc_run.py --condition randomized --rows 200 --port 7841 \\
        --out cardreader/sim/results/raw --seed 11

THE CONTROLLER SEES ONLY WHAT ROBOTD REPORTS. `runner.run` is handed a `state()` that answers the
newest `robot.state` frame (as `FallWatch.state()` does on the duck), perturbed as the condition
says; MuJoCo's truth is read on a separate connection to duck-body and used only to score.

CONDITIONS (each knob is drawn per stack session, a session being `--rows-per-session` rows on
one freshly started body and robotd, or per row where it says so):

- `nominal`: nothing perturbed; state subscribed at 20 Hz, the card reader's rate.
  `nominal-10hz` and `nominal-50hz` are the same at 10 Hz (Studio's rate) and 50 Hz (robotd's
  own estimate, every tick it sends), to measure what the client's state rate costs.
- `randomized`: floor friction x U(0.5, 1.2), every body's mass and inertia x U(0.95, 1.05),
  the IMU's heading biased by U(-5, 5) deg and drifting at U(-0.5, 0.5) deg/s (all four in the
  body, body_knobs.py); per row, an added state latency U(0, 0.15) s (the controller is handed
  the newest frame that arrived at least that long ago, stamped as arriving that late), odometry noise (white, 5 mm per axis
  and 0.5 deg per frame) and an odometry scale error U(0.95, 1.05) on displacement from the row's
  start (both applied to `odom` before the controller sees it); state subscribed at 20 Hz.
- `randomized-10hz`: as `randomized`, with the state subscribed at 10 Hz, the rate Studio asks
  for.
- `stressed-10hz`: the far ends of every range together, at 10 Hz: friction x 0.5, mass x 1.05,
  IMU heading bias 5 deg and drift 0.5 deg/s (each sign drawn at random), latency 0.15 s, the
  same odometry noise, odometry scale 0.95 or 1.05 (sign drawn at random).

robotd's `robot.subscribe` delivers fewer frames than asked (sysid: 16.7 a second for 20, 9.2 for
10, 40 for 50), and that is what the controller gets.

Every condition: before each row the duck is held still for U(0.5, 2.0) s (where in its sway the
first card lands: the starting gait phase); rows are drawn in turn from the row list (`rows.py`).

SCORING. The row frame is MuJoCo's trunk pose when the first beat starts. The board rule (one
square per Walk card, a quarter turn per Turn card) gives where the duck should end, in that
frame; the position and heading error are measured where the last Walk or Turn card ended (a
skill after it, a kick, moves the duck in ways the board does not count). A row that ends early
(fell, lost, stuck, out of time) is scored as failed for position and heading, and its ending
and sentence are recorded. Raw per-row JSON lines go to `--out/<condition>.jsonl`.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import pathlib
import random
import sys
import threading
import time

HERE = pathlib.Path(__file__).resolve().parent
SIM = HERE.parent
sys.path.insert(0, str(SIM / "sysid"))
sys.path.insert(0, str(SIM.parent))
sys.path.insert(0, str(HERE))
from duckio import Body, Robotd, wrap  # noqa: E402
from simstack import Stack  # noqa: E402
from duckcards import cardloop, runner  # noqa: E402
import rows as rowlist  # noqa: E402


class Truth(threading.Thread):
    """MuJoCo's trunk at 50 Hz, kept with the wall time it was read."""

    def __init__(self, body: Body):
        super().__init__(daemon=True)
        self.body, self.log, self.stop_ = body, [], threading.Event()

    def run(self):
        nxt = time.monotonic()
        while not self.stop_.is_set():
            try:
                t = self.body.truth()
            except Exception:
                break
            self.log.append((t["wall"], t["x"], t["y"], t["yaw"], t["z"], t["gravity"][2]))
            nxt += 0.02
            time.sleep(max(0.0, nxt - time.monotonic()))

    def at(self, w):
        lo, hi = 0, len(self.log) - 1
        while lo < hi:
            mid = (lo + hi) // 2
            if self.log[mid][0] < w:
                lo = mid + 1
            else:
                hi = mid
        return self.log[lo]


class Seen:
    """What the controller is handed: robotd's newest frame, late and noisy as the row says."""

    def __init__(self, robot: Robotd, rng: random.Random, latency=0.0, noise_m=0.0, noise_deg=0.0, scale=1.0):
        self.robot, self.rng = robot, rng
        self.latency, self.noise_m, self.noise_deg, self.scale = latency, noise_m, noise_deg, scale
        self.origin = None

    def __call__(self):
        frames = self.robot.frames
        if not frames:
            return None
        now = time.monotonic()
        pick = None
        for i in range(len(frames) - 1, max(-1, len(frames) - 200), -1):
            w, p = frames[i]
            if now - w >= self.latency:
                pick = (w, p)
                break
        if pick is None:
            return None
        w, p = pick
        odom = p.get("odom")
        if isinstance(odom, dict) and (self.noise_m or self.noise_deg or self.scale != 1.0):
            x, y = odom["position"][0], odom["position"][1]
            if self.origin is None:
                self.origin = (x, y)
            ox, oy = self.origin
            x = ox + (x - ox) * self.scale + self.rng.gauss(0, self.noise_m)
            y = oy + (y - oy) * self.scale + self.rng.gauss(0, self.noise_m)
            yaw = odom["yaw"] + math.radians(self.rng.gauss(0, self.noise_deg))
            p = dict(p, odom={"position": [x, y, odom["position"][2]], "yaw": yaw})
        # Stamped when it would have ARRIVED, `latency` late: a client cannot tell a frame that
        # was delayed on the way from a fresh one (it has no clock in common with robotd), so the
        # added latency is invisible to the stale check, as transport latency is on a real link.
        return p, w + self.latency


def board_end(actions, square):
    x = y = h = 0.0
    for a in actions:
        if a == "walk_forward":
            x, y = x + square * math.cos(h), y + square * math.sin(h)
        elif a == "walk_backward":
            x, y = x - square * math.cos(h), y - square * math.sin(h)
        elif a == "turn_left":
            h += math.pi / 2
        elif a == "turn_right":
            h -= math.pi / 2
    return x, y, wrap(h)


def draw_session(cond, rng):
    if cond.startswith("nominal"):
        return {}
    if cond.startswith("stressed"):
        return {"friction": 0.5, "mass_scale": 1.05, "yaw_bias_deg": rng.choice((-5.0, 5.0)),
                "yaw_drift_dps": rng.choice((-0.5, 0.5))}
    return {"friction": round(rng.uniform(0.5, 1.2), 3), "mass_scale": round(rng.uniform(0.95, 1.05), 3),
            "yaw_bias_deg": round(rng.uniform(-5, 5), 2), "yaw_drift_dps": round(rng.uniform(-0.5, 0.5), 3)}


def draw_camera(cond, rng):
    """THE CAMERA, for duck-card-loop/4 (docs/PACKS.md, pre-registered 2026-10-18), per session:
    how far the duck's belief about its head camera is off (mounting pitch, roll and yaw, height)
    and how the picture differs (brightness gain, white noise in levels of 255), and a fresh tilt
    error on every frame (the IMU's pitch and roll). Drawn only when the spec has `compass`."""
    if cond.startswith("nominal"):
        return {"pitch_deg": 0.0, "roll_deg": 0.0, "yaw_deg": 0.0, "height_m": 0.0, "gain": 1.0,
                "noise": 0.0, "imu_sd_deg": 0.0}
    if cond.startswith("stressed"):
        return {"pitch_deg": rng.choice((-2.0, 2.0)), "roll_deg": rng.choice((-1.0, 1.0)),
                "yaw_deg": rng.choice((-1.0, 1.0)), "height_m": rng.choice((-0.005, 0.005)),
                "gain": rng.choice((0.7, 1.3)), "noise": 8.0, "imu_sd_deg": 0.3}
    return {"pitch_deg": round(rng.uniform(-2, 2), 3), "roll_deg": round(rng.uniform(-1, 1), 3),
            "yaw_deg": round(rng.uniform(-1, 1), 3), "height_m": round(rng.uniform(-0.005, 0.005), 4),
            "gain": round(rng.uniform(0.7, 1.3), 3), "noise": 4.0, "imu_sd_deg": 0.3}


class MatEye:
    """`mateye.py` for one session: started on microduck_rl's venv beside the stack, asked to lay
    the mat at each row's start and for a frame at each stop."""

    def __init__(self, body_port: int, port: int, camera: dict, seed: int, square: float):
        import subprocess
        rl = os.environ.get("MICRODUCK_RL", os.path.expanduser("~/microduck_rl"))
        args = [os.path.join(rl, ".venv/bin/python"), str(SIM / "mateye.py"), "--rl", rl,
                "--body-port", str(body_port), "--port", str(port), "--seed", str(seed),
                "--square", str(square)]
        for k, v in camera.items():
            args += [f"--{k.replace('_', '-')}", str(v)]
        # One render thread at a lower priority than the stack: a software renderer (osmesa's
        # llvmpipe) otherwise takes every core for each frame and starves the physics and robotd
        # of every session on the machine (results-compass/run1, docs/PACKS.md).
        env = dict(os.environ, MUJOCO_GL=os.environ.get("MUJOCO_GL", "egl"))
        env.setdefault("LP_NUM_THREADS", "1")
        self.proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env,
                                     preexec_fn=lambda: os.nice(10))
        line = self.proc.stdout.readline()
        if "mateye ready" not in line:
            self.proc.kill()
            raise RuntimeError(f"mateye did not start: {line.strip()}")
        import socket
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=10)
        self.f = self.sock.makefile("rwb")
        self.frames = self.fails = 0

    def place(self) -> list:
        self.f.write(b'{"op":"place"}\n')
        self.f.flush()
        return json.loads(self.f.readline())["truth"]

    def frame(self):
        import numpy as np
        try:
            self.f.write(b'{"op":"frame"}\n')
            self.f.flush()
            head = json.loads(self.f.readline())
            data = self.f.read(head["n"])
            self.frames += 1
            gray = np.frombuffer(data, dtype=np.uint8).reshape(head["h"], head["w"])
            return gray, head["fovy"], head["rot"], head["pos"]
        except Exception:
            self.fails += 1
            return None

    def close(self):
        try:
            self.sock.close()
        finally:
            self.proc.kill()
            self.proc.wait()


def draw_row(cond, rng):
    if cond.startswith("nominal"):
        return {"latency_s": 0.0, "noise_m": 0.0, "noise_deg": 0.0, "odom_scale": 1.0}
    if cond.startswith("stressed"):
        return {"latency_s": 0.15, "noise_m": 0.005, "noise_deg": 0.5, "odom_scale": rng.choice((0.95, 1.05))}
    return {"latency_s": round(rng.uniform(0.0, 0.15), 3), "noise_m": 0.005, "noise_deg": 0.5,
            "odom_scale": round(rng.uniform(0.95, 1.05), 3)}


def upright(truth: Truth):
    if not truth.log:
        return False
    _, _, _, _, z, gz = truth.log[-1]
    return z > 0.095 and gz < -0.9


SPEC_SHA = __import__("hashlib").sha256(cardloop.SPEC_FILE.read_bytes()).hexdigest()
CARD_LOG: list = []
_drive = runner.drive


def _logged_drive(loop, robot, state, sleep=time.sleep, clock=time.time):
    """runner.drive, unchanged, with how each card ended and how far off odometry said it was."""
    t0 = clock()
    done = _drive(loop, robot, state, sleep, clock)
    got = state() if state else None
    pose = cardloop.odometry(got[0]) if got else None
    entry = {"card": loop.action, "ended": done, "s": round(clock() - t0, 3)}
    if pose is not None:
        b = loop.board_after
        if loop.action.startswith("walk"):
            entry["odom_off_m"] = round(math.hypot(pose.x - b.x, pose.y - b.y), 4)
        entry["odom_off_deg"] = round(math.degrees(wrap(b.h - pose.h)), 2)
    if hasattr(loop, "trims_left"):
        entry["trims_used"] = int(cardloop.SPEC["turn"]["trims"]) - loop.trims_left
    n = getattr(loop, "cards", 1)
    if n > 1:
        # duck-card-loop/5: a merged run of n cards counts as n cards, each its time over n
        # (docs/PACKS.md), so the time criterion judges it per card as before.
        entry["s"] = round((clock() - t0) / n, 3)
        entry["merged"] = n
    CARD_LOG.extend(dict(entry) for _ in range(n))
    return done


runner.drive = _logged_drive


def run_row(robot, truth, row, cond_row, rng, square, log, eye=None):
    CARD_LOG.clear()
    steps = rowlist.steps(row)
    beats = runner.beats(steps)
    said = []                                  # (wall, line)
    seen = Seen(robot, rng, cond_row["latency_s"], cond_row["noise_m"], cond_row["noise_deg"],
                cond_row["odom_scale"])
    # The starting phase: still for a random moment first.
    still = rng.uniform(0.5, 2.0)
    end = time.monotonic() + still
    while time.monotonic() < end:
        robot.move(0.0, 0.0)
        time.sleep(0.05)
    if eye is not None:
        eye.place()                            # the child seats the duck on the mat
    t_start = time.monotonic()
    fell_any = [False]

    def say(line):
        said.append((time.monotonic(), line))

    result = runner.run(beats, robot, say=say, state=seen, clock=time.monotonic, measured=True,
                        frame=eye.frame if eye is not None else None)
    t_end = time.monotonic()
    # When each beat began: the runner says each beat's clause first, in order.
    begins, k = [], 0
    for w, line in said:
        if k < len(beats) and line == f"  {beats[k].clause}":
            begins.append(w)
            k += 1
    moving = [i for i, b in enumerate(beats) if b.kind == "card"]
    last = moving[-1] if moving else None
    w0 = begins[0] if begins else t_start
    if last is not None and last + 1 < len(begins):
        w_score = begins[last + 1]
    else:
        w_score = t_end
    s0, s1 = truth.at(w0), truth.at(w_score)
    _, x0, y0, h0, _, _ = s0
    _, x1, y1, h1, _, _ = s1
    dx, dy = x1 - x0, y1 - y0
    ex, ey = dx * math.cos(h0) + dy * math.sin(h0), -dx * math.sin(h0) + dy * math.cos(h0)
    bx, by, bh = board_end([beats[i].action for i in moving], square)
    pos_err = math.hypot(ex - bx, ey - by)
    head_err = math.degrees(abs(wrap((h1 - h0) - bh)))
    fell = any(s.get("safety", {}).get("fallen") for w, s in list(robot.frames)[-int((t_end - t_start) * 60):]
               if w >= t_start)
    card_times = []
    for i in moving:
        if i + 1 < len(begins):
            card_times.append(begins[i + 1] - begins[i] - cardloop.SPEC["between_s"])
    ending = "finished" if result == "finished" else result
    cal = getattr(runner, "LAST_CAL", None)
    calib = {"drift_est_dps": round(math.degrees(cal.rate), 4), "windows": cal.windows} if cal else {}
    runner.LAST_CAL = None
    fix = getattr(runner, "LAST_FIX", None)
    if fix is not None:
        ok = [f for f in fix.fixes if f is not None]
        calib.update({"looks": len(fix.fixes), "fixes": len(ok),
                      "fix_deg": [round(math.degrees(f[0]), 2) for f in ok],
                      "fix_cm": [round(100 * math.hypot(f[1], f[2]), 1) for f in ok]})
    runner.LAST_FIX = None
    return {"row": row["name"], "cards": len(moving), "result": ending,
            "said": [line.strip() for _, line in said if not any(line == f"  {b.clause}" for b in beats)],
            "pos_err_m": pos_err, "head_err_deg": head_err, "fell": fell,
            "row_s": t_end - t_start, "card_s": card_times, "board_end": [bx, by, math.degrees(bh)],
            "truth_end": [ex, ey, math.degrees(wrap(h1 - h0))], "card_log": list(CARD_LOG), **calib, **cond_row}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--condition", choices=["nominal", "nominal-10hz", "nominal-50hz", "randomized", "randomized-10hz", "stressed-10hz"], required=True)
    ap.add_argument("--rows", type=int, default=200)
    ap.add_argument("--rows-per-session", type=int, default=12)
    ap.add_argument("--port", type=int, default=7841)
    ap.add_argument("--state", default=None)
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--start-index", type=int, default=0, help="first row of the list to draw")
    ap.add_argument("--spec", default=None,
                    help="a card-loop spec other than the shipped duck-card-loop.json, for a candidate's "
                         "development and evaluation; its sha256 is recorded on every row")
    ap.add_argument("--rows-set", choices=["all", "acceptance", "acceptance-back"], default="all",
                    help="every pack solution and hand row, only docs/PACKS.md's pre-registered rows, "
                         "or only those of them with Walk back (judged on their own, so they need rows of their own)")
    a = ap.parse_args()
    global SPEC_SHA
    if a.spec:
        spec_file = pathlib.Path(a.spec)
        cardloop.SPEC = cardloop.load_spec(spec_file)
        SPEC_SHA = __import__("hashlib").sha256(spec_file.read_bytes()).hexdigest()
    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, f"{a.condition}.jsonl")
    done = 0
    if os.path.exists(path):
        done = sum(1 for _ in open(path))
    rng = random.Random(a.seed * 1000 + done)
    state = a.state or f"/tmp/duck-mc-{a.port}"
    hz = 10 if a.condition.endswith("10hz") else 50 if a.condition.endswith("50hz") else 20
    rows = rowlist.all_rows()
    if a.rows_set == "acceptance":
        rows = [r for r in rows if r["name"] in rowlist.ACCEPTANCE]
    if a.rows_set == "acceptance-back":
        rows = [r for r in rows if r["name"] in rowlist.ACCEPTANCE
                and any(s.action == "walk_backward" for s in rowlist.steps(r))]
    square = cardloop.SPEC["square_m"]
    i = done
    start_failures = 0
    while i < a.rows:
        knobs = draw_session(a.condition, rng)
        stack = Stack(state, a.port, "v8", knobs)
        try:
            stack.up()
        except Exception as e:
            print(f"session failed to start: {e}", flush=True)
            stack.down()
            start_failures += 1
            if start_failures >= 5:
                # Five in a row is the machine, not the draw: stop with an error rather than
                # use up draws forever.
                print(f"{a.condition}: {start_failures} sessions in a row failed to start; stopping at row {i}", flush=True)
                sys.exit(2)
            time.sleep(2)
            continue
        start_failures = 0
        eye = None
        camera = {}
        if cardloop.SPEC.get("compass"):
            camera = draw_camera(a.condition, rng)
            try:
                eye = MatEye(a.port, a.port + 1000, camera, a.seed * 1000 + i, square)
            except Exception as e:
                print(f"session failed to start its mat eye: {e}", flush=True)
                stack.down()
                start_failures += 1
                if start_failures >= 5:
                    sys.exit(2)
                continue
        robot = Robotd(str(stack.sock), hz=hz)
        body = Body(a.port)
        truth = Truth(body)
        truth.start()
        time.sleep(0.5)
        n = 0
        try:
            while n < a.rows_per_session and i < a.rows:
                row = rows[(a.start_index + i) % len(rows)]
                cr = draw_row(a.condition, rng)
                r = run_row(robot, truth, row, cr, rng, square, print, eye)
                r.update({"i": i, "condition": a.condition, "knobs": knobs, "hz": hz, "spec_sha256": SPEC_SHA})
                if camera:
                    r["camera"] = camera
                with open(path, "a") as f:
                    f.write(json.dumps(r) + "\n")
                print(f"{a.condition} {i} {r['row']}: {r['result']} pos {r['pos_err_m']*100:.1f} cm "
                      f"head {r['head_err_deg']:.1f} deg fell {r['fell']} {r['row_s']:.0f} s", flush=True)
                i += 1
                n += 1
                if r["fell"] or r["result"] != "finished":
                    # A duck that fell or stopped gets itself up; a session that cannot is restarted.
                    for _ in range(300):
                        robot.move(0.0, 0.0)
                        time.sleep(0.1)
                        if upright(truth):
                            break
                    if not upright(truth):
                        break
        finally:
            truth.stop_.set()
            if eye is not None:
                eye.close()
            robot.close()
            body.close()
            stack.down()


if __name__ == "__main__":
    main()
