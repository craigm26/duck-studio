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
