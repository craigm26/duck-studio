# System identification: Pollen's v8 velstand under robotd, in duck-sim

What the Microduck does with a `robot.move`, measured through `robot.move` only, on Pollen's own
stack: robotd built from pollen-robotics/microduck `d7560ef`, the v8 policy set from
`scripts/seed-policies.sh` (velstand.onnx sha256 `2fc7f8ee…f492`), and microduck_rl's
`body_server` at develop `b02fdea4` stepping MuJoCo in real time. Ground truth is MuJoCo's trunk,
read on a second connection to the body the way duck-sim's own `upright_at` reads it. Run on
2026-10-15 on a Raspberry Pi 5 (aarch64, no GPU); the world kept real time (sim/wall 1.00).

The table and the fits are `sysid.md` (written by `sysid_fit.py`); the plots are `steps_vx.png`,
`steps_vyaw.png`, `gain.png` and `ramps.png`; every trial's raw log is `raw/*.jsonl.gz` (each
`robot.move` sent, each `robot.state` frame robotd sent at 50 Hz, MuJoCo's trunk at 50 Hz).

## Which bound applies, per axis

Every command sent, here and by the cards, stays inside both Pollen's pad defaults
(`PadDriveParams::default()`, robotd-params/src/lib.rs, "what [v8 velstand] follows well on the
robot"; `cardreader/duckcards/pollen-pad-drive.json`) and the v8 velstand's training command
ranges (microduck_rl `tasks/microduck_velocity_env_cfg.py`, inherited unchanged by
`microduck_velstand_env_cfg.py`: `lin_vel_x = (-0.4, 0.4)`, `lin_vel_y = (-0.3, 0.3)`,
`ang_vel_z = (-1.0, 1.0)`, fixed, no widening curriculum).

| axis | pad default | training range | tighter |
|---|---|---|---|
| vx | -0.4 to 0.4 m/s | -0.4 to 0.4 | equal: both bind |
| vy | -0.3 to 0.3 m/s | -0.3 to 0.3 | equal (never sent: the cards do not side-step) |
| vyaw | -1.0 to 1.0 rad/s | -1.0 to 1.0 | equal: both bind |

`sysid_run.py` asserts every command against these before sending it.

## What it found

| axis, direction | stands still up to | moves every time from | delay | time constant | at the bound |
|---|---|---|---|---|---|
| vx forward | 0.20 m/s | 0.25 | 0.04 to 0.25 s | 0.2 to 0.4 s | 0.135 m/s (gain 0.34) |
| vx backward | -0.30 | -0.35 | 0.46 to 0.67 s | 0.1 to 0.2 s | -0.170 m/s (gain 0.43) |
| vyaw left, in place | 0.50 rad/s | 0.625 | under one tick | 0.3 to 1.1 s | 63 deg/s (gain 1.1) |
| vyaw right, in place | 0.25 (0.375 moved 1 of 3) | 0.50 | under one tick | 0.1 to 1.0 s | -66 deg/s (gain 1.15) |

- **A dead band, not a slope.** Below it the trunk leans a few millimetres and no foot leaves
  the floor; above it the gait starts and its speed is roughly a third of the command forward
  and two fifths backward, while yaw is followed at about the command once it turns at all.
- **Hysteresis.** On a slow ramp the forward gait starts at 0.23 and keeps going down to 0.08;
  in place, yaw starts at 0.61 to 0.62 left and 0.80 right and keeps going down to 0.07 to 0.12.
  On a slow backward ramp to -0.4 the duck never started walking at all (two of two), although a
  step to -0.35 or -0.4 started it every time. So a card steps to its speed; it never ramps.
- **Coast.** After a zero command the trunk travels 1 to 1.5 cm forward, 3 to 4 cm backward, or
  turns 7 to 10 degrees more at 1.0 rad/s.
- **No switch between policies.** With v8 nothing but velstand ever drove a tick (`policy` was
  `walk` throughout): velstand stands at zero command and robotd loads no standing network.
  (duck-sim's own params load `alpha_walking` + `alpha_stand`, which switch at a smoothed twist
  magnitude of 0.05; see docs/POLLEN-ISSUE-duck-sim-walk.md.)
- **The deadman.** With nothing sent, robotd marks the twist `limited_by: deadman` 0.50 s after
  the last `robot.move` and slews it to zero with `cmd_alpha` (applied below 0.01 at 0.8 s); the
  trunk travelled 5.5 cm after the last command at 0.3. robotd also shows a new request in its
  state a median 14 ms after it was sent.
- **The state rate a client sees.** `robot.subscribe` with `hz` 50 delivers 40 frames a second,
  20 delivers 16.7 and 10 delivers 9.2: robotd sends a tick only when at least 1/hz has passed
  since the last one sent, and with ticks every 20 ms give or take, a tick a hair early waits a
  whole tick more. Studio's 10 Hz is about 9 Hz and the reader's 20 Hz about 17 Hz.
- **Odometry against truth.** Over a trial (about 9.5 s, up to 0.8 m), robotd's contact odometry
  was within 1 mm of MuJoCo's displacement in the median (37 mm worst) and within 0.06 degrees of
  its heading (0.21 worst). In this simulator the IMU is MuJoCo's exact orientation and the
  feet do not slip much; a real duck's will be worse, which the Monte Carlo's randomized and
  stressed conditions model.
- **No falls** in 107 trials (96 steps, 8 ramps, 3 deadman).

## Rerun

```sh
python3 cardreader/sim/sysid/simstack.py up --state /tmp/ds --port 7831      # one v8 duck
python3 cardreader/sim/sysid/sysid_run.py --sock /tmp/ds/duck.sock --body-port 7831 \
        --out cardreader/sim/sysid/raw --reps 3 --seed 1
python3 cardreader/sim/sysid/simstack.py down --state /tmp/ds --port 7831
python cardreader/sim/sysid/sysid_fit.py cardreader/sim/sysid/raw cardreader/sim/sysid  # numpy, scipy, matplotlib
```

or `cardreader/sim/validate.sh`, which does all of it from a clean machine.
