"""The sim duck's head camera, rendered beside duck-sim instead of inside it.

    $MICRODUCK_RL/.venv/bin/python cardreader/sim/eye.py scene_card.xml

WHY NOT DUCK-SIM'S OWN CAMERA. `DUCK_SIM_CAMERAS=a` renders the head camera on
duck-body's physics thread at 15 frames a second. Without a GPU one frame of
this duck costs about 114 ms even with the scene lightened (`scene.py`), so the
simulated world fell to 0.52x real time and the duck fell over before it had
read a card (2026-10-14, Mesa llvmpipe, 2 cores). This process renders the same
camera at 4 frames a second from the duck's pose, read the way duck-sim's own
`upright_at` reads it (a read-only `hello` and `read` on duck-body's port), and
serves the frames on the port duck-body would have, with microduck_rl's own
`Camera`, `FrameServer` and `FrameHandler`. Pollen's mediad then turns them into
`/frame` and `media.frame` exactly as it does for duck-body's camera. The head
joints are posed from the body's positions too, so a head the reader turns
turns this camera.

Run it with microduck_rl's venv (mujoco, numpy) and `MUJOCO_GL=egl` (or
`osmesa`) on a machine without a display.
"""

from __future__ import annotations

import argparse
import json
import socket
import threading
import time
from pathlib import Path

import mujoco
import numpy as np  # noqa: F401  (mujoco's arrays)
from mjlab_microduck.sim.body_server import JOINT_NAMES
from mjlab_microduck.sim.camera import Camera, FrameHandler, FrameServer


class Mirror:
    """The scene, posed from what duck-body says the duck is doing."""

    def __init__(self, scene: Path):
        self.model = mujoco.MjModel.from_xml_path(str(scene))
        self.data = mujoco.MjData(self.model)
        self.lock = threading.Lock()

        def jid(name):
            return mujoco.mj_name2id(self.model, mujoco.mjtObj.mjOBJ_JOINT, name)

        self.trunk = int(self.model.jnt_qposadr[jid("trunk_base_freejoint")])
        self.slots = [(i, int(self.model.jnt_qposadr[jid(n)])) for i, n in enumerate(JOINT_NAMES) if jid(n) >= 0]

    def pose(self, reading: dict) -> None:
        with self.lock:
            q = self.data.qpos
            q[self.trunk:self.trunk + 3] = reading["trunk"]
            # MuJoCo's own orientation when body_knobs.py turns what robotd is told: a camera sees
            # the world, not what a drifting IMU believes.
            q[self.trunk + 3:self.trunk + 7] = reading.get("truth_quat") or reading["imu"]["quat"]
            for wire, adr in self.slots:
                q[adr] = reading["positions"][wire]
            mujoco.mj_kinematics(self.model, self.data)
            mujoco.mj_camlight(self.model, self.data)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("scene", type=Path)
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--body-port", type=int, default=7801, help="duck-body's port (duck-sim's first duck: 7801)")
    p.add_argument("--frame-port", type=int, default=7901, help="where mediad --sim-camera reads frames")
    p.add_argument("--stream-fps", type=int, default=30, help="what the frame server tells mediad")
    p.add_argument("--fps", type=float, default=4.0, help="frames rendered a second")
    a = p.parse_args()
    mirror = Mirror(a.scene)
    body = socket.create_connection((a.host, a.body_port), timeout=5)
    f = body.makefile("rw")
    f.write(json.dumps({"op": "hello", "protocol": 1, "joints": 15}) + "\n")     # as duck-sim says it
    f.flush()
    f.readline()

    def read() -> dict:
        f.write('{"op":"read"}\n')
        f.flush()
        return json.loads(f.readline())

    # The Camera turns the model's head camera round (it faces backwards in the MJCF), so it is
    # made before the first pose, or the first frame is of what is behind the duck.
    camera = Camera(mirror.model, "head_camera")
    mirror.pose(read())
    camera.render(mirror)
    server = FrameServer((a.host, a.frame_port), FrameHandler)
    server.camera, server.fps = camera, a.stream_fps
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"== eye: {a.scene.name}, pose from {a.host}:{a.body_port}, frames on {a.host}:{a.frame_port}, "
          f"{a.fps:g} a second", flush=True)
    period, n, spent = 1.0 / a.fps, 0, 0.0
    while True:
        t0 = time.perf_counter()
        r = read()
        mirror.pose(r)
        camera.render(mirror)
        n += 1
        spent += time.perf_counter() - t0
        if n % 40 == 0:
            print(f"== eye: {n} frames, {1000 * spent / 40:.0f} ms each, sim_time {r['sim_time']:.1f} s", flush=True)
            spent = 0.0
        time.sleep(max(0.0, period - (time.perf_counter() - t0)))


if __name__ == "__main__":
    raise SystemExit(main())
