# duck-sim: the duck does not step under `robot.move` (draft issue for pollen-robotics/microduck, not filed)

Written 2026-10-15 from duck-studio's `duck-packs-sim` branch. Everything here was reproduced on
pollen-robotics/microduck `d7560ef` (main) and microduck_rl `b02fdea4` (develop), with the
official v8 policy set, on a Raspberry Pi 5 (aarch64, Debian 13, no GPU) where duck-sim keeps real
time (`scripts/duck-sim realtime`: 1.00). The 2026-10-14 symptom was seen on Ubuntu 24.04 x86.

## Symptom

`scripts/duck-sim` brings a duck up standing, and then `scripts/duck-sim drive` (vx 0.15 for 8 s)
does not walk it: the trunk moves 6 mm. A client sending Studio's timed twists (0.2 m/s forward,
1.0 rad/s turning) sees the same: robotd applies the command (`move.applied` equals it, nothing in
`limited_by`, `policy` is `walk`) and the duck stays where it is.

## Two causes, one of them duck-sim's

### 1. duck-sim runs the retired alpha pair, not the robot's v8 velstand

`scripts/duck-sim` `up()` writes this into robotd's params:

```toml
[policy]
walk = "$POLICIES/alpha_walking.onnx"
stand = "$POLICIES/alpha_stand.onnx"
```

On a robot nothing says that: robotd resolves `walk = velstand.onnx` and no standing network
(robotd-params `PolicyParams::resolved_with`, "The velstand gait (set v5) walks on a twist and
stands still at zero command, so no standing network is loaded by default"). So every duck-sim
since v5 has been driving `alpha_walking`, the walk anchor whose in-place yaw is documented in
microduck_rl `docs/velstand_policy.md` ("fed 0.6 → 0, 1.0 → 0.35 in place"), with the
magnitude switch to `alpha_stand` at 0.05 that no robot has any more.

Measured in duck-sim through `robot.move` (MuJoCo's trunk, 6 s at each command, unchanged
duck-sim, alpha pair):

| command | alpha pair (duck-sim as shipped) | v8 velstand (robotd's default) |
|---|---|---|
| vx 0.15 | 5 mm | 6 mm |
| vx 0.20 | 7 mm | 0.33 m |
| vx 0.30 | 0.69 m | 0.55 m |
| vx -0.30 | 5 mm | 1 mm |
| vx -0.40 | -1.09 m | -0.91 m |
| vyaw +1.0, in place | 8.7 degrees | about 62 degrees a second (370 degrees in 6 s) |
| vyaw -1.0, in place | -14.3 degrees | about -62 degrees a second |

So with duck-sim as shipped, turning in place at the pad's full 1.0 rad/s does not turn the duck,
and nothing below 0.3 forward walks.

**Proposed fix:** drop `walk` and `stand` from the params `up()` writes, and name only what has no
release directory to resolve against, or name `walk = "$POLICIES/velstand.onnx"` and no `stand`.
Either makes duck-sim run what a robot runs. Until then, a user can do it at runtime with
robotctl, which does not change the robot's behaviour; it makes the simulator match the robot:

```sh
scripts/duck-sim ctl policy load walk ~/.cache/duck-sim/policies/current/velstand.onnx
scripts/duck-sim ctl policy load stand none
```

### 2. Every command sent was below v8 velstand's dead band

Even with v8, vx 0.15 does not step. Identified step by step in duck-sim (duck-studio
`cardreader/sim/sysid/sysid.md`, 3 repetitions per level, starting phase varied):

| axis | stands still up to | moves every time from | achieved at the pad bound |
|---|---|---|---|
| vx forward | 0.20 m/s | 0.25 | 0.135 m/s at 0.4 |
| vx backward | -0.30 | -0.35 | -0.170 m/s at -0.4 |
| vyaw in place, left | 0.50 rad/s | 0.625 | 63 deg/s at 1.0 |
| vyaw in place, right | 0.25 to 0.375 | 0.50 | -66 deg/s at -1.0 |

On a slow ramp the gait is hysteretic: forward it starts at 0.23 and stops at 0.08; backward,
ramping to -0.4 over 8 s never started it (twice), while a step to -0.35 did every time.

`scripts/duck-sim drive` defaults to vx 0.15, below the forward dead band of both policies, so
Pollen's own demo cannot walk the simulated duck with either.

**Proposed fix:** `drive` at 0.3 (or the pad's 0.4); and, since a client cannot tell "below the
dead band" from "ignored", say the dead band where the pad envelope is said
(`PadDriveParams` docs, `docs/robot/simulation.md`). Whether a real duck has the same dead band
was not measured here; microduck_rl's velstand eval (in place ±0.3 → +0.08/−0.22) suggests the
training sim has a smaller one.

## Not the cause, checked

- **Real time.** The body kept 1.00 throughout (`sim_time` against the wall clock).
- **The deadman.** Fires 0.50 s after the last `robot.move`, as documented; clients sent at 10
  and 20 Hz.
- **robotd's tuning.** `action_scale = 1.0` and `legs_lowpass = 1.0` (the training's unfiltered,
  unscaled actions) left the dead band where it was (vx 0.15: 7 mm; -0.3: 1 mm).
- **The actuator model.** duck-body drives the scene's `chosen_actuator` position servos, which
  `scripts/infer_policy.py` calls "NOT the actuator the policy was trained with". Driving the
  joints with the BAM M6 XL330 model instead (as `infer_policy.py` does, duck-studio
  `cardreader/sim/sysid/body_knobs.py --bam`, diagnosis only) left the forward and backward dead
  bands where they were (vx 0.15: 4 mm; -0.3: 1 mm; 0.3: 0.44 m). It may still matter for other
  things; it is not why the duck does not step.

## Smaller things found on the way

- **`robot.subscribe` delivers fewer frames than asked.** At `hz` 50, 40 a second; at 20, 16.7;
  at 10, 9.2. robotd's per-subscriber decimation sends a tick only when `last_sent.elapsed() >=
  1/hz`, and ticks arrive every 20 ms give or take, so a tick a hair early is dropped and the next
  one taken. Proposed fix: compare against `1/hz` minus half a tick, or count ticks.
- **duck-sim never moves a seeded set forward.** `policies()` runs `seed-policies.sh` only when
  `alpha_stand.onnx` is missing, so a state directory seeded at v5 keeps v5 after the daemon moves
  to v8 (this machine's `~/.cache/duck-sim` still had v5's velstand). `seed-policies.sh` itself
  would move it up; it is just not called. Proposed fix: call it every `up`; it exits at once when
  the set is current.

## Reproduce

```sh
git clone https://github.com/pollen-robotics/microduck && cd microduck
cargo build -p robotd -p robotctl -p tof -p sounds -p configd -p updater
git clone -b develop https://github.com/pollen-robotics/microduck_rl ~/Pollen/microduck_rl
(cd ~/Pollen/microduck_rl && uv venv .venv && uv pip install --python .venv mujoco==3.10.0 numpy==2.4.1 \
   onnxruntime==1.24.4 && uv pip install --python .venv --no-deps -e .)
DUCK_SIM_VIEWER=0 scripts/duck-sim
scripts/duck-sim drive                 # does not walk (alpha pair, 0.15)
scripts/duck-sim drive 0.3             # walks
scripts/duck-sim drive 0 1.0           # alpha pair: does not turn
scripts/duck-sim ctl policy load walk ~/.cache/duck-sim/policies/current/velstand.onnx
scripts/duck-sim ctl policy load stand none
scripts/duck-sim drive 0 1.0           # v8: turns about 60 degrees a second
scripts/duck-sim drive                 # v8: still does not walk at 0.15
```

duck-studio's `cardreader/sim/sysid/probe_walk.py` prints the ground-truth displacement of any
one command next to what robotd reported.
