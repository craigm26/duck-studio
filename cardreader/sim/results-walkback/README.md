# The Walk lead (duck-card-loop/2): a candidate change, on Pollen's stack

A candidate, not shipped: `enabled_on_robot` stays `false`, and docs/PACKS.md "Acceptance" is
unchanged. Same stack, conditions, scoring and criteria as `../results/` (fcefea3,
`duck-card-loop/1`); only the controller changed, and it carries a new format id so the two sets
of rows can never be mixed (every row records its spec's sha256).

## What changed

`duck-card-loop/1` stopped a Walk card a fixed 1.2 cm short forward and 3.5 cm short back. Walk
back overshot at Studio's 10 Hz. `duck-card-loop/2` gives Walk cards the lead Turn cards already
have: the row's first Walk card each way stops `approach_m` forward or `back_approach_m` back
short of its square, holds still `settle_s` (`back_settle_s`), and measures how far odometry
says it went on (`coast_m`, clamped to `lead_m`); each later Walk card the same way leads by the
mean of the row's measured coasts that way. Forward and back are kept apart. A Walk card does
not trim. Python (`cardreader/duckcards/cardloop.py`, `runner.py`) and Swift (`DuckCardLoop`,
`RobotPlanRunner`) in step, held by `cardreader/vectors/cardloop/*.json` (four new vectors).

## Where the numbers came from

From the system identification only (`../sysid/raw/`, not the Monte Carlo):
`walk_lead_from_sysid.py` (its table: `WALK_LEAD.md`).

## Seeds

- Development (all tuning, nothing else): `dev/`, seeds 101 to 104.
- Evaluation (run once, after the spec was fixed): seeds 211 to 214 (`raw/`, every row),
  221 to 224 (`raw-acceptance/`), 241 to 244 (`raw-back/`). fcefea3 used 11 to 14, 21 to 24,
  31 and 32, 41 to 44. `mc_run.py` seeds its generator with `seed * 1000 + rows done`, so no two
  of these draw the same stream.

## What was tuned on the development seeds (`dev/`, `dev/DEV.md`)

Sixty rows per condition, randomized-10hz and stressed-10hz only, candidates sharing seeds so
each pair drew the same knobs:

- **A** (`dev/candidate-A-back-only.json`): the Walk back lead only (0.052 m, settle 0.8 s);
  forward as duck-card-loop/1.
- **B** (`dev/candidate-B-back-and-forward.json`): A plus the forward lead (0.022 m, settle 0.4 s).
  On the forward-only rows its last card's overshoot median went from 2.6 to -0.6 cm
  (randomized-10hz) and 4.3 to 2.4 cm (stressed), so forward was kept.
- **C** (`dev/candidate-C-back-only-trunk-lead.json`): A with the back lead raised by the sysid
  odometry scale (odometry counts 0.956 of the trunk's distance walking back: 1.3 cm a square).
  On the Walk back rows the median position error went from 4.4 to 3.5 cm (randomized-10hz).
  Kept as `back_slip_m` 0.013, added to every Walk back lead.

The shipped candidate is B plus C's slip (spec sha256 `8850df7f`); that exact combination was
not itself run on the development seeds. Nothing else was changed after the evaluation began.

## The evaluation (run once)

`run_eval.sh` (stage 1) then `schedule_eval.sh` (stages 2 and 3, started as the machine had
room): 400 rows per condition in each of `raw-acceptance/`, `raw-back/` and `raw/`, 4,800 rows,
on the spec above. `RESULTS.md` is `mc_summary.py` over them, exactly as `../results/RESULTS.md`
was made; `COMPARE.md` is `compare.py`, fcefea3 beside this, every criterion with its Wilson
interval.

**A caveat on falls, measured and not removed.** fcefea3 had no fall in 4,128 rows. This run
had 11 (4 nominal, 2 randomized, 3 randomized-10hz, 2 stressed; plus, in the same rows, one
stale pose, one Turn out of time at 6.46 s and one stuck Turn). They cluster: rows 215 to 226 of all four
pre-registered batches at once, about 10:36 to 10:40 PDT by the batches' progress, which is when the bodies of a
reproduction of fcefea3 running on the same Raspberry Pi logged "behind real time"
(`~/duck-packs-repro/behind.txt`, 17:33 to 17:39 UTC), and that reproduction, on
duck-card-loop/1, fell 3 times in the same hours. The other falls (nominal row 49, randomized row 12,
Walk back randomized row 169) could not be placed in time as closely. So the falls look like a loaded simulator, not the
controller, but that is an inference from timing; the rows count as measured. The Walk back
batch and the every-row batch, run after the reproduction finished, had 1 and 0 falls.

## What it says

- **Walk back position now passes at Studio's 10 Hz**: 97.0% [95.0, 98.1] of 493 rows, was
  92.8% [89.9, 94.9]. Median error 3.4 cm, was 5.8. Stressed improves (79.9% to 88.4%) and
  still fails.
- **Walk back heading got worse**: randomized-10hz 96.0% to 93.5% [91.0, 95.4] (now FAIL);
  stressed 84.1% to 73.4%; nominal median 3.4 to 4.9 degrees. Odometry's heading at the end of a
  Walk back card is off by a median 4.6 to 5.2 degrees after the settle, against 2.2 to 3.0 at
  duck-card-loop/1's stop: the duck yaws in its coast and settle, and nothing steers then.
- **The pre-registered rows overall at 10 Hz now fail** position (94.7%) and heading (93.9%);
  some of that is the stall cluster (6 of the 26 rows in it fail), and outside it 25 of 374
  rows still fail one or the other.
- **Rung 1: not passed**, as before. Stressed fails as before; falls fail in every condition as
  measured.
- **The packs' long rows did not improve; at 10 Hz they got worse** (10 cards or more:
  41.7% to 21.7% within 10 cm, randomized-10hz). Each Walk card now settles, so a long row takes
  longer (median 49.1 to 51.9 s at 10 Hz) and the IMU drift has longer to act; the lead does
  nothing for the drift that fails these rows.
