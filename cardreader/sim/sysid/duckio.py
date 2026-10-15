"""Talking to Pollen's robotd and to duck-sim's MuJoCo body, for system identification and the
Monte Carlo. Standard library only.

- `Robotd`: robotd's own socket, NDJSON JSON-RPC (pollen-robotics/microduck
  `duck-ipc-proto`). `robot.subscribe {"hz": N}` streams `robot.state` notifications on the
  same connection; `robot.move {vx, vy, vyaw}` is a notification that expires after
  `safety.deadman_ms` (500 ms). A reader thread keeps every state frame with the wall time it
  arrived (`time.monotonic()`), so a log has both the robot's clock (`t`, `t_ns`) and ours.
- `Body`: duck-sim's body server (microduck_rl `mjlab_microduck.sim.body_server`), the TCP
  port robotd itself is attached to. `{"op":"read"}` answers MuJoCo's own trunk position
  (`trunk`), trunk orientation (`imu.quat`, before anything robotd does to it) and `sim_time`:
  the ground truth. The body server is a threading server, so a second client reads beside
  robotd, the way duck-sim's `upright_at` and cardreader/sim/scene.py --from-duck do. Ground
  truth is only ever used to score; the controller never sees it.

Every number the controller is allowed to use comes from `Robotd.latest()`.
"""

from __future__ import annotations

import json
import math
import socket
import threading
import time
from collections import deque


class Robotd:
    def __init__(self, path: str, hz: int | None = 50, keep: int = 200000):
        self.path = path
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.sock.settimeout(5.0)
        self.wlock = threading.Lock()
        self._id = 0
        self._answers: dict[int, dict] = {}
        self._cv = threading.Condition()
        self.frames: deque = deque(maxlen=keep)      # (arrived_monotonic, params)
        self._latest = None
        self.closed = False
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        self.subscribed = None
        if hz is not None:
            self.subscribed = self.call("robot.subscribe", {"hz": hz} if hz else {})

    def _read(self):
        buf = b""
        while not self.closed:
            try:
                chunk = self.sock.recv(1 << 20)
            except socket.timeout:
                continue
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                if msg.get("method") == "robot.state":
                    now = time.monotonic()
                    p = msg.get("params") or {}
                    self._latest = (now, p)
                    self.frames.append((now, p))
                elif "id" in msg:
                    with self._cv:
                        self._answers[msg["id"]] = msg
                        self._cv.notify_all()
        self.closed = True

    def call(self, method: str, params: dict | None = None, timeout: float = 10.0):
        with self.wlock:
            self._id += 1
            want = self._id
            msg = {"jsonrpc": "2.0", "id": want, "method": method}
            if params is not None:
                msg["params"] = params
            self.sock.sendall(json.dumps(msg).encode() + b"\n")
        end = time.monotonic() + timeout
        with self._cv:
            while want not in self._answers:
                left = end - time.monotonic()
                if left <= 0:
                    raise TimeoutError(f"{method}: no answer in {timeout} s")
                self._cv.wait(left)
            reply = self._answers.pop(want)
        if "error" in reply:
            raise RuntimeError(f"{method}: {reply['error']}")
        return reply.get("result")

    def notify(self, method: str, params: dict | None = None):
        msg = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params
        with self.wlock:
            self.sock.sendall(json.dumps(msg).encode() + b"\n")

    def move(self, vx: float, vyaw: float, vy: float = 0.0):
        self.notify("robot.move", {"vx": float(vx), "vy": float(vy), "vyaw": float(vyaw)})

    def latest(self):
        """(arrived_monotonic, params) of the newest robot.state, or None."""
        return self._latest

    def close(self):
        self.closed = True
        try:
            self.sock.close()
        except OSError:
            pass


class Body:
    """duck-sim's MuJoCo body, read-only: where the duck really is."""

    def __init__(self, port: int, host: str = "127.0.0.1"):
        self.sock = socket.create_connection((host, port), timeout=5)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.f = self.sock.makefile("rw")
        self.lock = threading.Lock()
        self._ask({"op": "hello", "protocol": 1, "joints": 15})

    def _ask(self, req: dict) -> dict:
        with self.lock:
            self.f.write(json.dumps(req) + "\n")
            self.f.flush()
            return json.loads(self.f.readline())

    def truth(self) -> dict:
        """{sim_time, x, y, z, yaw, quat, trunk_z}: MuJoCo's trunk, world frame."""
        r = self._ask({"op": "read"})
        # body_knobs.py may turn what robotd is told; `truth_quat` is MuJoCo's own.
        w, x, y, z = r.get("truth_quat") or r["imu"]["quat"]
        yaw = math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
        tx, ty, tz = r.get("trunk", [float("nan")] * 3)
        return {"sim_time": r.get("sim_time"), "x": tx, "y": ty, "z": tz, "yaw": yaw,
                "quat": [w, x, y, z], "gravity": r["imu"]["gravity"], "wall": time.monotonic()}

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def odom_of(params: dict):
    """(x, y, yaw) from a robot.state frame, or None."""
    o = (params or {}).get("odom")
    if not isinstance(o, dict):
        return None
    p, yaw = o.get("position"), o.get("yaw")
    if not isinstance(p, list) or len(p) < 2 or not isinstance(yaw, (int, float)):
        return None
    return float(p[0]), float(p[1]), float(yaw)


def wrap(a: float) -> float:
    while a > math.pi:
        a -= 2 * math.pi
    while a <= -math.pi:
        a += 2 * math.pi
    return a
