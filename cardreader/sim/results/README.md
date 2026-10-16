# Closed-loop Duck Cards on Pollen's stack: the Monte Carlo

Rung 1 of docs/PACKS.md, "Acceptance": Pollen's own robotd (pollen-robotics/microduck
`d7560ef`, built debug as duck-sim builds it) driving Pollen's v8 velstand (the Hub's
`microduck-policies` tag v8) in duck-sim's MuJoCo body (microduck_rl develop `b02fdea4`), with
the card reader's own runner (`cardreader/duckcards/runner.py`) closing Walk and Turn cards on
the `odom` robotd reports, under `duck-card-loop.json` sha256 `96df70b5`. MuJoCo's trunk is the
ground truth; it only scores. Run on 2026-10-15 on one Raspberry Pi 5 (aarch64, 4 cores, no
GPU), up to eight ducks at once, each its own body and robotd; no body fell behind real time
(each body logs it when it does; none did).

**[RESULTS.md](RESULTS.md)** is every table: per condition and per criterion, the share of rows
with its Wilson interval, the median, 95th percentile (each with a bootstrap 95% interval) and
maximum of the errors and of each card's time, and PASS or FAIL, then the rows with Walk back on
their own, then every row including the packs' challenge solutions, row by row. It is written
by `../mc/mc_summary.py` from the raw rows here; nothing in it is typed by hand.

## What was run

| directory | rows | what |
|---|---|---|
| `raw/` | 209, 208, 204, 227 | every starter pack challenge's `solution` (29 rows, Repeat unrolled, Your cards lent; 2 to 28 cards) and the 11 pre-registered rows, drawn in turn, four conditions |
| `raw-acceptance/` | 400 each | the 11 pre-registered rows only (docs/PACKS.md, "Acceptance", "Rows"), four conditions |
| `raw-back/` | 320 each | the 2 pre-registered rows with Walk back, which must pass on their own and so need rows of their own (381 for the fall bound) |
| `raw-rate/` | 200 each | the pre-registered rows, nominal, with the state at 10 Hz and at 50 Hz, for the cost of the state rate |

A row is one JSON line: the row, how it ended and what was said, the ground-truth end pose
against the board rule in the row's own frame, each card's ending, time and the error odometry
reported at its end, the condition's knobs, the spec's digest.

## Conditions (fixed before the rows ran; `../mc/mc_run.py` says exactly how each is applied)

| condition | floor friction | mass | IMU heading bias, drift | state latency added | odometry noise, scale | state rate |
|---|---|---|---|---|---|---|
| nominal | x1 | x1 | 0, 0 | 0 | none | 20 Hz (the reader's) |
| randomized | x U(0.5, 1.2) | x U(0.95, 1.05) | U(-5, 5) deg, U(-0.5, 0.5) deg/s | U(0, 0.15) s | 5 mm, 0.5 deg white; x U(0.95, 1.05) | 20 Hz |
| randomized-10hz | as randomized | | | | | 10 Hz (Studio's) |
| stressed-10hz | x 0.5 | x 1.05 | +-5 deg, +-0.5 deg/s | 0.15 s | 5 mm, 0.5 deg; x 0.95 or 1.05 | 10 Hz |
| nominal-10hz, nominal-50hz | as nominal | | | | | 10 Hz, 50 Hz |

Friction and mass are drawn per stack session (12 rows on one freshly started body and robotd);
the IMU's bias and drift are applied in the body to the orientation robotd is told, so robotd's
own odometry turns with them as it would with a real IMU's; latency and odometry noise are drawn
per row and applied to what the controller is handed (a delayed frame is stamped as arriving
late, as transport latency is on a real link, so the stale check cannot see it). Before every
row the duck stands still for U(0.5, 2.0) s, so the first card starts at a different moment of
its sway (the starting gait phase). robotd's state stream delivers fewer frames than asked
(16.7 a second for 20, 9.2 for 10, 40 for 50; `../sysid/`), and that is what the controller got.

## How a row is scored

The row frame is MuJoCo's trunk pose when the first card begins. The board rule (one 30 cm
square per Walk card, a quarter turn per Turn card) says where the duck should end; position and
heading errors are where the last Walk or Turn card ended, against that (a kick after it moves
the duck in ways the board does not count). A row that ends early (trimmed out, stuck, lost,
fell, out of time) fails position and heading. Ending safely is checked on every such row: the
runner said exactly one ending sentence, returned "stopped at ...", and its `finally` sent
`robot.stop` after the card's own zero twist. Falls are robotd's `safety.fallen` during the row.
A card's time is from its first command to its ending (settles and trims included), against
Acceptance's 8 s (Walk) and 6 s (Turn).

## Reproduce

`../validate.sh` from a clean machine (pinned commits, the v8 tag, the same seeds), into a fresh
directory; compare its RESULTS.md with this one. The physics runs in real time against a
wall-clock robotd, so a second run draws the same knobs and rows but not bit-identical
trajectories: compare the rates and intervals, not the rows.

To regenerate RESULTS.md from these rows:

```sh
python3 cardreader/sim/mc/mc_summary.py cardreader/sim/results/raw cardreader/sim/results/raw-acceptance \
    cardreader/sim/results/raw-back cardreader/sim/results/raw-rate > cardreader/sim/results/RESULTS.md
```
