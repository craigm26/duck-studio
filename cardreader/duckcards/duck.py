"""The duck's eyes and the duck's legs: frames in, JSON-RPC out.

EVERY SHAPE HERE IS POLLEN'S, CITED. pollen-robotics/microduck at 648bf22:

- `mediad/src/frame.rs`: a process on the robot asks `/run/mediad/media.sock`
  for `media.frame` and gets one JSON-RPC response line, a `MediaFrameHeader`
  (width, height, format "UYVY", bytes, captured_at_unix_us, rotate), then
  exactly `bytes` raw bytes, then the socket closes. One frame per connection.
  UYVY carries brightness in every odd byte, so the grey picture a code reader
  wants costs a slice, not a colour conversion.
- `rotate` is degrees clockwise the camera is mounted from upright, and
  `spaces/vision-demo/filters.py` turns a picture upright with
  `np.rot90(frame, k=-(rotate // 90))`. So does this.
- `mediad/src/web.rs`: `GET /frame` on port 8080 answers one PNG, upright.
  `DuckCamera` in StudioKit reads the same page; a reader on a laptop beside
  duck-sim (`DUCK_SIM_CAMERAS=a`) reads it too.
- `duck-ipc-proto/src/lib.rs`: robotd speaks NDJSON JSON-RPC on
  `/run/robotd.sock`. `robot.move` is a continuous intent, sent as a
  notification at 20 to 50 Hz and EXPIRING, so a reader that dies mid-walk
  leaves a duck that stops. `robot.do`, `robot.sound`, `robot.look` and
  `robot.stop` are requests and are answered.
- From a laptop, the same lines go through `microduck-bridge` (this
  repository's `bridge/`): one hello with the token, then every line relayed.
"""

from __future__ import annotations

import json
import socket
import threading
import time
from dataclasses import dataclass

import numpy as np

MEDIA_SOCKET = "/run/mediad/media.sock"
ROBOT_SOCKET = "/run/robotd.sock"


class DuckError(RuntimeError):
    pass


def _read_exact(sock: socket.socket, n: int) -> bytes:
    chunks, got = [], 0
    while got < n:
        chunk = sock.recv(min(1 << 20, n - got))
        if not chunk:
            raise DuckError(f"the frame ended after {got} of {n} bytes")
        chunks.append(chunk)
        got += len(chunk)
    return b"".join(chunks)


def _read_line(sock: socket.socket, limit: int = 65536) -> bytes:
    buf = bytearray()
    while not buf.endswith(b"\n"):
        b = sock.recv(1)
        if not b:
            break
        buf += b
        if len(buf) > limit:
            raise DuckError("a header line longer than any header")
    return bytes(buf)


def upright(gray: np.ndarray, rotate: int) -> np.ndarray:
    if rotate % 360 == 0:
        return gray
    return np.ascontiguousarray(np.rot90(gray, k=-(rotate // 90)))


@dataclass
class Frame:
    gray: np.ndarray
    captured_at: float          # seconds, the robot's clock
    rotate: int


class FrameSocket:
    """`media.frame`, on the robot itself."""

    def __init__(self, path: str = MEDIA_SOCKET, timeout: float = 3.0):
        self.path, self.timeout = path, timeout

    def grab(self) -> Frame:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(self.timeout)
            s.connect(self.path)
            s.sendall(b'{"jsonrpc":"2.0","id":1,"method":"media.frame"}\n')
            line = _read_line(s)
            try:
                reply = json.loads(line)
            except ValueError:
                raise DuckError(f"mediad answered something that is not JSON: {line[:80]!r}")
            if "error" in reply:
                raise DuckError(f"mediad: {reply['error'].get('message', reply['error'])}")
            h = reply["result"]
            w, ht, n = int(h["width"]), int(h["height"]), int(h["bytes"])
            if h.get("format") != "UYVY" or w % 2 or n != w * ht * 2:
                raise DuckError(f"a frame this reader does not know how to read: {h}")
            raw = _read_exact(s, n)
        y = np.frombuffer(raw, dtype=np.uint8)[1::2].reshape(ht, w)
        rot = int(h.get("rotate", 0))
        return Frame(gray=upright(y, rot), captured_at=int(h.get("captured_at_unix_us", 0)) / 1e6,
                     rotate=rot)


class FrameURL:
    """`GET /frame`, from anywhere that can reach port 8080: a laptop beside a duck or duck-sim."""

    def __init__(self, url: str, timeout: float = 3.0):
        self.url, self.timeout = url, timeout

    def grab(self) -> Frame:
        import io
        import urllib.request
        from PIL import Image
        with urllib.request.urlopen(self.url, timeout=self.timeout) as r:
            if r.status != 200:
                raise DuckError(f"{self.url} answered {r.status}")
            data = r.read()
        img = Image.open(io.BytesIO(data)).convert("L")
        return Frame(gray=np.asarray(img), captured_at=time.time(), rotate=0)


class Robot:
    """JSON-RPC to robotd, over its own socket or through microduck-bridge."""

    def __init__(self, sock: socket.socket, timeout: float = 5.0):
        self.sock = sock
        self.sock.settimeout(timeout)
        self.timeout = timeout
        self._id = 0
        self._lock = threading.Lock()
        self._buf = b""

    @classmethod
    def unix(cls, path: str = ROBOT_SOCKET) -> "Robot":
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(path)
        return cls(s)

    @classmethod
    def bridge(cls, host: str, port: int, token: str) -> "Robot":
        s = socket.create_connection((host, port), timeout=5)
        s.sendall(json.dumps({"microduck": "v1", "token": token}).encode() + b"\n")
        robot = cls(s)
        try:
            hello = robot._line()
        except (OSError, DuckError):
            robot.close()
            raise DuckError("microduck-bridge closed the connection before saying hello")
        if b"error" in hello:
            robot.close()
            raise DuckError(f"microduck-bridge refused: {hello.decode(errors='replace').strip()}")
        return robot

    def _line(self) -> bytes:
        while b"\n" not in self._buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise DuckError("robotd closed the connection")
            self._buf += chunk
        line, self._buf = self._buf.split(b"\n", 1)
        return line

    def notify(self, method: str, params: dict | None = None) -> None:
        msg = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params
        with self._lock:
            self.sock.sendall(json.dumps(msg).encode() + b"\n")

    def call(self, method: str, params: dict | None = None):
        with self._lock:
            self._id += 1
            want = self._id
            msg = {"jsonrpc": "2.0", "id": want, "method": method}
            if params is not None:
                msg["params"] = params
            self.sock.sendall(json.dumps(msg).encode() + b"\n")
            while True:
                reply = json.loads(self._line())
                if reply.get("id") != want:
                    continue            # a notification, or an answer nobody is waiting for
                if "error" in reply:
                    err = reply["error"]
                    raise DuckError(f"{method}: {err.get('message', err) if isinstance(err, dict) else err}")
                return reply.get("result")

    def close(self) -> None:
        try:
            self.sock.close()
        except OSError:
            pass


class FallWatch:
    """`robot.subscribe` on a connection of its own, watching `safety.fallen`.

    A fall is over when the duck reports it is no longer fallen: Pollen's robot stands itself up,
    and only then is a When it falls row worth running."""

    def __init__(self, connect, hz: int = 5):
        self.connect, self.hz = connect, hz
        self.fallen = False
        self.recovered = threading.Event()
        self._stop = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)

    def start(self) -> "FallWatch":
        self.thread.start()
        return self

    def stop(self) -> None:
        self._stop.set()

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                robot = self.connect()
                robot.sock.settimeout(2.0)
                robot.call("robot.subscribe", {"hz": self.hz})
                while not self._stop.is_set():
                    try:
                        msg = json.loads(robot._line())
                    except socket.timeout:
                        continue
                    if msg.get("method") != "robot.state":
                        continue
                    fallen = bool(((msg.get("params") or {}).get("safety") or {}).get("fallen"))
                    if self.fallen and not fallen:
                        self.recovered.set()
                    self.fallen = fallen
            except (OSError, DuckError, ValueError):
                time.sleep(1.0)
