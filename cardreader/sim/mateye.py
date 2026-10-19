"""The sim duck's head camera over a taped grid, one frame on request (duck-card-loop/4).

    $MICRODUCK_RL/.venv/bin/python cardreader/sim/mateye.py --body-port 7841 --port 8841 \\
        [--pitch-deg P --roll-deg R --yaw-deg Y --height-m H --gain G --noise N --imu-sd-deg S --seed K]

A mat for the Monte Carlo (`mc/mc_run.py --compass`): Pollen's scene with the floor a plain light
colour and a grid of dark tape lines on it (`--square` apart, `--tape` wide, 15 squares a side),
seen through the model's head camera, posed from duck-body exactly as `eye.py` poses it, except
that the trunk's orientation is MuJoCo's own (`truth_quat`), not the drifted one robotd is told:
a camera sees the world, not what the IMU believes. The tape touches nothing; the physics never
sees it, because this process has a model of its own.

Newline JSON on `--port`, one client at a time:

- `{"op": "place"}`: lay the mat so the duck's trunk is in the middle of a square and its heading
  runs along the grid, as a child seats a duck on the mat at the start of a row. Answers
  `{"ok": true, "truth": [x, y, yaw]}`. With `"seat": [forward, left, turn]` (duck-card-loop/6
  and /7: a re-seat between chapters, off the nest by that much) the nest is laid there instead.
- `{"op": "frame"}`: render one frame now. Answers one JSON line `{"w", "h", "fovy", "rot", "pos",
  "sim_time", "n"}` and then `n` bytes of 8-bit luma, row by row. `rot` and `pos` describe the
  camera in the yaw-free trunk frame (`duckcards/matcam.py`) as the duck would believe it: the
  session's mounting errors (`--pitch-deg`, `--roll-deg`, `--yaw-deg`, `--height-m`) and a fresh
  IMU tilt error each frame (`--imu-sd-deg`, on pitch and roll) are in it; the picture is not.
  The picture's brightness is scaled by `--gain` and has white noise of `--noise` levels added.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import pathlib
import socket
import socketserver
import sys
import tempfile

import mujoco
import numpy as np

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from eye import Mirror  # noqa: E402

LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float32)


def mat_scene(rl: pathlib.Path, square: float, tape: float, squares: int = 15) -> pathlib.Path:
    robot = rl / "src/mjlab_microduck/robot/microduck"
    src = (robot / "scene.xml").read_text()
    half = squares * square / 2
    lines = []
    for k in range(squares + 1):
        c = -half + k * square
        lines.append(f'<geom type="box" size="{half:.4f} {tape / 2:.4f} 0.0005" pos="0 {c:.4f} 0.0005" '
                     f'rgba="0.08 0.08 0.1 1" contype="0" conaffinity="0"/>')
        lines.append(f'<geom type="box" size="{tape / 2:.4f} {half:.4f} 0.0005" pos="{c:.4f} 0 0.0005" '
                     f'rgba="0.08 0.08 0.1 1" contype="0" conaffinity="0"/>')
    for old, new in [
        ('<include file="robot_groundcontact.xml" />',
         f'<include file="{robot / "robot_groundcontact.xml"}" />\n    <compiler meshdir="{robot / "assets"}"/>'),
        ('        <geom name="floor"', '        <body name="mat" mocap="true">' + "".join(lines)
         + '</body>\n        <geom name="floor"'),
        ('material="groundplane" />', 'rgba="0.82 0.78 0.70 1" />'),
        ('directional="true" />', 'directional="true" castshadow="false" />'),
        ("<visual>", '<visual>\n        <quality offsamples="0" />'),
    ]:
        if old not in src:
            sys.exit(f"microduck_rl's scene.xml has changed: cannot find {old!r}")
        src = src.replace(old, new, 1)
    out = pathlib.Path(tempfile.mkdtemp(prefix="mateye-")) / "mat_scene.xml"
    out.write_text(src)
    return out


def yaw_of(q) -> float:
    w, x, y, z = q
    return math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))


def rot(axis: str, a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return {"x": np.array([[1, 0, 0], [0, c, -s], [0, s, c]]),
            "y": np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]]),
            "z": np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])}[axis]


class Eye:
    def __init__(self, a):
        self.a = a
        self.mirror = Mirror(mat_scene(pathlib.Path(a.rl), a.square, a.tape))
        m = self.mirror.model
        self.cam = mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_CAMERA, "head_camera")
        turned = np.zeros(4)                     # the model's head camera faces backwards (eye.py)
        mujoco.mju_mulQuat(turned, m.cam_quat[self.cam], np.array([0.0, 1.0, 0.0, 0.0]))
        m.cam_quat[self.cam] = turned
        self.renderer = mujoco.Renderer(m, height=a.height, width=a.width)
        self.rng = np.random.default_rng(a.seed)
        self.mount = rot("z", math.radians(a.yaw_deg)) @ rot("y", math.radians(a.pitch_deg)) @ rot("x", math.radians(a.roll_deg))
        body = socket.create_connection((a.host, a.body_port), timeout=5)
        self.f = body.makefile("rw")
        self.f.write(json.dumps({"op": "hello", "protocol": 1, "joints": 15}) + "\n")
        self.f.flush()
        self.f.readline()

    def read(self) -> dict:
        self.f.write('{"op":"read"}\n')
        self.f.flush()
        r = json.loads(self.f.readline())
        q = r.get("truth_quat") or r["imu"]["quat"]
        return dict(r, imu=dict(r["imu"], quat=q))

    def place(self, seat=(0.0, 0.0, 0.0)) -> dict:
        r = self.read()
        x, y = r["trunk"][0], r["trunk"][1]
        h = yaw_of(r["imu"]["quat"])
        # duck-card-loop/6 and /7: between chapters the duck sits `seat` (forward, left, turn) off
        # the nest, so the nest, the square's middle, is the true pose less the seat.
        sx, sy, sh = seat
        h -= sh
        x -= sx * math.cos(h) - sy * math.sin(h)
        y -= sx * math.sin(h) + sy * math.cos(h)
        d = self.mirror.data
        d.mocap_pos[0] = (x, y, 0.0)
        d.mocap_quat[0] = (math.cos(h / 2), 0.0, 0.0, math.sin(h / 2))
        return {"ok": True, "truth": [x, y, h]}

    def frame(self) -> tuple[dict, bytes]:
        r = self.read()
        self.mirror.pose(r)
        d = self.mirror.data
        self.renderer.update_scene(d, camera=self.cam)
        rgb = self.renderer.render()
        gray = rgb.astype(np.float32) @ LUMA
        if self.a.gain != 1.0 or self.a.noise:
            gray = gray * self.a.gain + self.rng.normal(0.0, self.a.noise, gray.shape)
        gray = np.clip(gray, 0, 255).astype(np.uint8)
        h = yaw_of(r["imu"]["quat"])
        unyaw = rot("z", -h)
        sd = math.radians(self.a.imu_sd_deg)
        tilt = rot("y", self.rng.normal(0.0, sd)) @ rot("x", self.rng.normal(0.0, sd)) if sd else np.eye(3)
        cam_r = tilt @ self.mount @ unyaw @ d.cam_xmat[self.cam].reshape(3, 3)
        cam_p = unyaw @ (d.cam_xpos[self.cam] - np.array([r["trunk"][0], r["trunk"][1], 0.0]))
        cam_p[2] += self.a.height_m
        head = {"w": int(gray.shape[1]), "h": int(gray.shape[0]), "fovy": float(self.mirror.model.cam_fovy[self.cam]),
                "rot": [float(v) for v in cam_r.reshape(-1)], "pos": [float(v) for v in cam_p],
                "sim_time": float(r["sim_time"]), "n": int(gray.size)}
        return head, gray.tobytes()


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        eye: Eye = self.server.eye
        for line in self.rfile:
            op = json.loads(line).get("op")
            if op == "place":
                self.wfile.write((json.dumps(eye.place(json.loads(line).get("seat") or (0, 0, 0))) + "\n").encode())
            elif op == "frame":
                head, data = eye.frame()
                self.wfile.write((json.dumps(head) + "\n").encode() + data)
            else:
                self.wfile.write(b'{"ok": false}\n')
            self.wfile.flush()


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--rl", default=os.environ.get("MICRODUCK_RL"))
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--body-port", type=int, required=True)
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--square", type=float, default=0.30)
    p.add_argument("--tape", type=float, default=0.019, help="tape width, metres (3/4 inch)")
    p.add_argument("--width", type=int, default=640)
    p.add_argument("--height", type=int, default=360)
    for k in ("pitch-deg", "roll-deg", "yaw-deg", "height-m", "noise", "imu-sd-deg"):
        p.add_argument(f"--{k}", type=float, default=0.0)
    p.add_argument("--gain", type=float, default=1.0)
    p.add_argument("--seed", type=int, default=0)
    a = p.parse_args()
    if not a.rl:
        p.error("say where microduck_rl is: --rl or $MICRODUCK_RL")
    socketserver.TCPServer.allow_reuse_address = True
    server = socketserver.TCPServer((a.host, a.port), Handler)
    server.eye = Eye(a)
    print(f"== mateye ready on {a.host}:{a.port}, pose from {a.host}:{a.body_port}", flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
