"""duck-sim's MuJoCo body (microduck_rl `mjlab_microduck.sim.body_server`), unchanged except for
the randomisation knobs the Monte Carlo needs. Run it with microduck_rl's venv:

    $MICRODUCK_RL/.venv/bin/python cardreader/sim/sysid/body_knobs.py --port 7811 --headless \\
        --friction 0.8 --mass-scale 1.03 --yaw-bias-deg 2 --yaw-drift-dps 0.3

Every other argument is body_server's own and is passed through. What each knob does, exactly:

- `--friction F`: every geom's sliding friction (`model.geom_friction[:, 0]`) times F, once,
  after the world is built. MuJoCo takes the larger of two touching geoms' friction (both are
  priority 0 here), so scaling every geom scales every contact's sliding friction by F, the
  feet on the floor included. Torsional and rolling friction are left alone.
- `--mass-scale M`: every body of every duck (`body_mass` and `body_inertia`, everything but
  the world body) times M: a heavier or lighter duck with the same mass distribution.
- `--yaw-bias-deg B`, `--yaw-drift-dps D`: what robotd is told the trunk IMU's orientation is
  (`imu.quat` in the `read` answer) is turned about the world's vertical by B + D x sim_time
  degrees. robotd's contact odometry takes its heading from that quaternion
  (pollen-robotics/microduck `odometry::Odometry::update`), so this is a heading bias and a
  heading drift exactly where a real IMU's would enter. Projected gravity and the body-frame
  gyro are unchanged by a turn about the vertical, so the policy sees the same robot. The true
  orientation is added to the answer as `truth_quat` (ignored by robotd, whose parser ignores
  unknown fields, like `trunk` and `trunk_z`), for scoring only.

Nothing here changes how the body steps, its timestep, its actuators or its scene.
"""

from __future__ import annotations

import argparse
import math
import sys

import numpy as np
from mjlab_microduck.sim import body_server as bs


def main() -> None:
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--friction", type=float, default=1.0)
    ap.add_argument("--mass-scale", type=float, default=1.0)
    ap.add_argument("--yaw-bias-deg", type=float, default=0.0)
    ap.add_argument("--yaw-drift-dps", type=float, default=0.0)
    ap.add_argument("--bam", action="store_true",
                    help="DIAGNOSIS ONLY, not duck-sim: drive the joints with the BAM M6 XL330 model "
                         "the policies were trained against (microduck_rl scripts/infer_policy.py's "
                         "default) instead of the scene's position actuators")
    knobs, rest = ap.parse_known_args()

    world_init = bs.World.__init__

    def init(self, scene, count=1):
        if knobs.bam:
            bam_world(self, scene, count)
        else:
            world_init(self, scene, count)
        m = self.model
        if knobs.friction != 1.0:
            m.geom_friction[:, 0] *= knobs.friction
        if knobs.mass_scale != 1.0:
            m.body_mass[1:] *= knobs.mass_scale
            m.body_inertia[1:] *= knobs.mass_scale
        print(f"== knobs: friction x{knobs.friction:.3f}, mass x{knobs.mass_scale:.3f}, "
              f"imu yaw bias {knobs.yaw_bias_deg:+.2f} deg, drift {knobs.yaw_drift_dps:+.3f} deg/s",
              flush=True)

    bs.World.__init__ = init

    sensors = bs.Body.sensors

    def biased(self):
        out = sensors(self)
        q = np.array(out["imu"]["quat"], dtype=float)
        out["truth_quat"] = [float(v) for v in q]
        theta = math.radians(knobs.yaw_bias_deg + knobs.yaw_drift_dps * float(out["sim_time"]))
        if theta != 0.0:
            turn = np.array([math.cos(theta / 2), 0.0, 0.0, math.sin(theta / 2)])
            turned = np.zeros(4)
            bs.mujoco.mju_mulQuat(turned, turn, q)
            out["imu"]["quat"] = [float(v) for v in turned]
        return out

    bs.Body.sensors = biased
    if knobs.bam:
        patch_bam()
    sys.argv = [sys.argv[0]] + rest
    bs.main()


# ── BAM, for the diagnosis in docs/POLLEN-ISSUE-duck-sim-walk.md ──────────────────────────────
# The same conversion as microduck_rl scripts/infer_policy.py `load_mujoco_with_bam` (which mirrors
# bam.mjlab.BamActuator.edit_spec, what training does): position actuators become torque motors
# bounded by vin x kt / R, joint damping and frictionloss are zeroed (BAM writes them every step),
# the stiff friction constraint, and bam.mujoco.MujocoController.update() before every mj_step.
# robotd's position target goes to the controller's q_target and robotd's gain to the firmware kp
# (kp_fw = 200 x kp / 200, so the standing gain ratio still applies). One duck only.

VIN = 7.4
STIFF_SOLREF = (-5.0e4, -2.0e2)
STIFF_SOLIMP = (0.99, 0.9999, 0.001, 0.5, 2.0)


def bam_world(world, scene, count):
    import threading
    import mujoco
    from bam.model import load_model
    from bam.mujoco import MujocoController
    if count != 1:
        raise SystemExit("--bam drives one duck")
    bam = load_model(motor_name="xl330", model="m6")
    bam.actuator.kp = 200.0
    bam.actuator.vin = VIN
    bam.actuator.max_current = None
    limit = bam.actuator.vin * bam.kt.value / bam.R.value
    spec = mujoco.MjSpec.from_file(str(scene))
    names = []
    for act in spec.actuators:
        target = act.target if isinstance(act.target, str) else act.target.name
        if target.startswith("passive_"):
            continue
        act.set_to_motor()
        act.forcelimited = True
        act.forcerange = (-limit, limit)
        act.ctrllimited = False
        act.gear = [1.0, 0, 0, 0, 0, 0]
        names.append(act.name)
        for joint in spec.joints:
            if joint.name == target:
                joint.damping = np.zeros((3, 1))
                joint.frictionloss = 0.0
                joint.solref_friction = STIFF_SOLREF
                joint.solimp_friction = STIFF_SOLIMP
                break
    world.model = spec.compile()
    world.model.opt.timestep = bs.TIMESTEP
    world.data = mujoco.MjData(world.model)
    world.lock = threading.Lock()
    world.bodies = []
    world.bam = MujocoController(bam, names, world.model, world.data)
    world.bam_index = {n: i for i, n in enumerate(names)}
    print(f"== BAM m6 xl330 on {len(names)} joints, vin {VIN} V, force limit {limit:.3f} N m", flush=True)


def patch_bam():
    import mujoco

    def step(self, times=1):
        with self.lock:
            for _ in range(times):
                self.bam.update()
                mujoco.mj_step(self.model, self.data)
                for body in self.bodies:
                    if not body.released:
                        body.restore()

    bs.World.step = step

    def targets_from_ctrl(body):
        w = body.world
        for a in body.actuators:
            name = mujoco.mj_id2name(w.model, mujoco.mjtObj.mjOBJ_ACTUATOR, a)
            w.bam.q_target[w.bam_index[name]] = w.data.ctrl[a]

    def set_targets(self, wire):
        with self.world.lock:
            for slot, wire_index in enumerate(self.to_wire):
                self.world.data.ctrl[self.actuators[slot]] = wire[wire_index]
            targets_from_ctrl(self)

    def apply_torque(self):
        self.world.bam.model.actuator.kp = (self.kp if self.torque_on else 0.0)
        targets_from_ctrl(self)

    place = bs.Body.place

    def placed(self, pose, trunk_z, offset_y):
        place(self, pose, trunk_z, offset_y)
        self.world.bam.reset(self.world.data.qpos) if hasattr(self.world.bam, "reset") else None
        targets_from_ctrl(self)

    bs.Body.set_targets = set_targets
    bs.Body._apply_torque = apply_torque
    bs.Body.place = placed


if __name__ == "__main__":
    main()
