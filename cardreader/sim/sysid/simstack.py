"""One simulated duck, the way Pollen's `scripts/duck-sim` starts one, with the knobs this
measurement needs: the MuJoCo body (body_knobs.py, which is body_server plus randomisation) and
the real `robotd` attached to it, enabled and standing. Standard library only.

    python3 cardreader/sim/sysid/simstack.py up   --state /tmp/ds1 --port 7811 [--policy v8|alpha]
    python3 cardreader/sim/sysid/simstack.py down --state /tmp/ds1

Why not `scripts/duck-sim` itself: it starts one body per state directory with no way to set
friction, mass or the IMU's heading, and it writes `walk = alpha_walking.onnx` and
`stand = alpha_stand.onnx` into robotd's params (see docs/POLLEN-ISSUE-duck-sim-walk.md). This
starts the same two processes with the same arguments otherwise: `body_server --headless
--keyframe SIT`, `robotd --sim 127.0.0.1:PORT --params ... --socket ...`, ORT_DYLIB_PATH from
microduck_rl's venv, then `robot.enable` (duck-sim's `stand_at`) and the same upright check
(trunk above 0.095 m, gravity z below -0.9). tofd, configd, updaterd and mediad are not started:
nothing here reads depth, identity, updates or the camera, and robotd runs without them.

`--policy v8` (the default) gives robotd no `walk` or `stand` override beyond naming the seeded
v8 set's files, which is what robotd resolves on a robot (robotd-params `PolicyParams::resolved`:
walk = velstand.onnx, no standing network). `--policy alpha` writes duck-sim's own pair, to
reproduce what duck-sim does.

As a library: `Stack(...).up()` / `.down()`.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import pathlib
import signal
import socket
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent


def env_path(name: str, default: str) -> pathlib.Path:
    return pathlib.Path(os.environ.get(name, default)).expanduser()


class Stack:
    def __init__(self, state, port=7811, policy="v8", knobs=None, microduck=None, rl=None,
                 policies=None, log=print, policy_extra=""):
        self.state = pathlib.Path(state)
        self.port = int(port)
        self.policy = policy
        self.knobs = knobs or {}
        self.microduck = pathlib.Path(microduck) if microduck else env_path("MICRODUCK", "~/microduck")
        self.rl = pathlib.Path(rl) if rl else env_path("MICRODUCK_RL", "~/microduck_rl")
        self.policies = pathlib.Path(policies) if policies else env_path(
            "DUCK_SIM_POLICIES", "~/.cache/duck-sim/policies/current")
        self.sock = self.state / "duck.sock"
        self.log = log
        # Diagnosis only: raw `[policy]` lines (e.g. `action_scale = 1.0`). The Monte Carlo
        # never sets this; it runs robotd's own tuning.
        self.policy_extra = policy_extra

    # ── files ─────────────────────────────────────────────────────────────
    def params(self) -> str:
        P = self.policies
        if self.policy == "alpha":
            walk = f'walk = "{P}/alpha_walking.onnx"\nstand = "{P}/alpha_stand.onnx"\n'
        else:
            walk = f'walk = "{P}/velstand.onnx"\n'
        return ("[policy]\nenabled = true\n" + walk
                + f'sitstand = "{P}/alpha_sitstand.onnx"\n'
                + f'ground_pick = "{P}/alpha_ground_pick.onnx"\n'
                + f'kick_left = "{P}/ball_kick_left.onnx"\n'
                + f'kick_right = "{P}/ball_kick_right.onnx"\n'
                + f'roulade = "{P}/roulade.onnx"\n' + self.policy_extra + "\n"
                + '[audio]\ndevice = "default"\n')

    def ort(self) -> str:
        found = glob.glob(str(self.rl / ".venv/lib/python*/site-packages/onnxruntime/capi/libonnxruntime.so*"))
        if not found:
            raise SystemExit(f"no onnxruntime in {self.rl}/.venv")
        return sorted(found)[0]

    # ── processes ─────────────────────────────────────────────────────────
    def _pid(self, name):
        p = self.state / f"{name}.pid"
        try:
            return int(p.read_text().strip())
        except (OSError, ValueError):
            return None

    def _stop(self, name, expect):
        pid = self._pid(name)
        (self.state / f"{name}.pid").unlink(missing_ok=True)
        if not pid:
            return
        try:
            cmd = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode()
        except OSError:
            return
        if expect not in cmd:
            return
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            return
        for _ in range(50):
            if not pathlib.Path(f"/proc/{pid}").exists():
                return
            time.sleep(0.1)
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    def down(self):
        self._stop("robotd", str(self.sock))
        self._stop("body", f"--port {self.port}")
        self.sock.unlink(missing_ok=True)

    def _wait_port(self, timeout=40):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            with socket.socket() as s:
                s.settimeout(0.3)
                if s.connect_ex(("127.0.0.1", self.port)) == 0:
                    return True
            time.sleep(0.2)
        return False

    def _wait_sock(self, timeout=40):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if self.sock.exists():
                try:
                    with socket.socket(socket.AF_UNIX) as s:
                        s.connect(str(self.sock))
                        return True
                except OSError:
                    pass
            time.sleep(0.2)
        return False

    def _call(self, method, params=None):
        with socket.socket(socket.AF_UNIX) as s:
            s.settimeout(5)
            s.connect(str(self.sock))
            f = s.makefile("rw")
            msg = {"jsonrpc": "2.0", "id": 1, "method": method}
            if params is not None:
                msg["params"] = params
            f.write(json.dumps(msg) + "\n")
            f.flush()
            while True:
                r = json.loads(f.readline())
                if r.get("id") == 1:
                    return r

    def body_read(self):
        with socket.create_connection(("127.0.0.1", self.port), timeout=3) as s:
            f = s.makefile("rw")
            f.write(json.dumps({"op": "hello", "protocol": 1, "joints": 15}) + "\n")
            f.flush()
            f.readline()
            f.write('{"op":"read"}\n')
            f.flush()
            return json.loads(f.readline())

    def upright(self):
        r = self.body_read()
        return r.get("trunk_z", 0) > 0.095 and r["imu"]["gravity"][2] < -0.9, r

    def up(self, stand_timeout=25.0):
        self.down()
        self.state.mkdir(parents=True, exist_ok=True)
        (self.state / "robotd.toml").write_text(self.params())
        k = self.knobs
        body_cmd = [str(self.rl / ".venv/bin/python"), str(HERE / "body_knobs.py"),
                    "--port", str(self.port), "--headless", "--keyframe", "SIT",
                    "--friction", str(k.get("friction", 1.0)),
                    "--mass-scale", str(k.get("mass_scale", 1.0)),
                    "--yaw-bias-deg", str(k.get("yaw_bias_deg", 0.0)),
                    "--yaw-drift-dps", str(k.get("yaw_drift_dps", 0.0))]
        if k.get("bam"):
            body_cmd.append("--bam")        # diagnosis only (body_knobs.py)
        env = dict(os.environ, PYTHONPATH=str(self.rl / "src"), MUJOCO_GL="egl")
        with open(self.state / "body.log", "w") as out:
            p = subprocess.Popen(body_cmd, stdout=out, stderr=subprocess.STDOUT, env=env,
                                 start_new_session=True)
        (self.state / "body.pid").write_text(str(p.pid))
        if not self._wait_port():
            raise RuntimeError(f"the body did not come up; {self.state}/body.log")
        robotd = self.microduck / "target/debug/robotd"
        env = dict(os.environ, DUCK_RUNTIME_DIR=str(self.state), ORT_DYLIB_PATH=self.ort(),
                   RUST_LOG=os.environ.get("RUST_LOG", "info"),
                   DUCK_IDENTITY=f"sysid-{self.port}")
        with open(self.state / "robotd.log", "w") as out:
            p = subprocess.Popen([str(robotd), "--sim", f"127.0.0.1:{self.port}",
                                  "--params", str(self.state / "robotd.toml"),
                                  "--socket", str(self.sock)],
                                 stdout=out, stderr=subprocess.STDOUT, env=env, start_new_session=True)
        (self.state / "robotd.pid").write_text(str(p.pid))
        if not self._wait_sock():
            raise RuntimeError(f"robotd did not come up; {self.state}/robotd.log")
        time.sleep(1.0)
        answer = self._call("robot.enable", {"on": True})
        if not (answer.get("result") or {}).get("accepted"):
            raise RuntimeError(f"robot.enable was not accepted: {answer}")
        end = time.monotonic() + stand_timeout
        while time.monotonic() < end:
            time.sleep(0.5)
            ok, r = self.upright()
            if ok:
                time.sleep(2.0)            # let it settle, as duck-sim's `sleep 6` does
                ok, r = self.upright()
                if ok:
                    self.log(f"standing: trunk {r['trunk_z']:.3f} m, gravity z {r['imu']['gravity'][2]:.3f}")
                    return True
        raise RuntimeError("the duck did not stand up")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("what", choices=["up", "down"])
    ap.add_argument("--state", required=True)
    ap.add_argument("--port", type=int, default=7811)
    ap.add_argument("--policy", choices=["v8", "alpha"], default="v8")
    ap.add_argument("--policy-extra", default="", help="diagnosis only: raw [policy] lines")
    ap.add_argument("--knobs", default="{}", help="JSON: friction, mass_scale, yaw_bias_deg, yaw_drift_dps")
    a = ap.parse_args()
    s = Stack(a.state, a.port, a.policy, json.loads(a.knobs),
              policy_extra=a.policy_extra.replace("\\n", "\n"))
    if a.what == "up":
        s.up()
        print(f"robotd socket {s.sock}, body port {s.port}")
    else:
        s.down()


if __name__ == "__main__":
    sys.exit(main())
