# A control for falls: duck-card-loop/1 again on HF

Pre-registered in docs/PACKS.md (#40) before any row ran. Not a candidate; changes nothing that
ships.

**Result: `/1` fell 2 times in 4,800 rows** (pre-registered rows, stressed 10 Hz, row LLRR on its
4th card; every row, nominal, row FLLF on its 1st card). That is under the pre-registered 3, so
by the rule written beforehand the falls belong to the mat: `/4` stays not adopted, and no
amendment to how falls are judged is made. Valid: 0 stale-pose stops (gate 10).

- `run_eval.sh`: the run, on HF Jobs (job 6ad5217e5ccb47ba0f7c6eb4, `cpu-upgrade`, commit 2d6cadc,
  2026-10-18 19:45 to 2026-10-19 02:51 UTC), seeds 521-524 (`raw-acceptance/`), 541-544
  (`raw-back/`), 511-514 (`raw/`), 400 rows a condition each.
- `hf/`: the job's `RESULTS.md`, `eval.log`, `setup.log`, `HOST.txt`, `load.log`.
- `COMPARE.md`: `/1` on HF twice, `../results/rung2-hf/` beside this run, criterion by criterion
  (`../results-walkback/compare.py`). **Seven verdicts differ between two runs of the same
  loop**, two of them pass to fail on falls: one fall in 510 rows puts the Wilson upper bound at
  1.10%, over the 1% bound, so at this size the falls criterion passes only with no falls at all.

## What the control found beyond its question

Rows are not independent. `../mc/mc_run.py` draws a condition's knobs (friction, mass, yaw bias
and drift) once per session of 12 rows, so 400 rows of a randomized condition are about 34 ducks.
Intervals that treat rows as independent (Wilson, Fisher) are too narrow, which is why `/1` can
look different from itself. `secondary.py` judges "worse" and "rises" by a permutation test over
sessions, the family of 80 "worse" tests held to 0.05 by Holm. It was written after this run's
rows and before any row of `/5` (`../results-merge/`) was read; docs/PACKS.md, "Secondary
analysis", says how it is used.

- `SELF.md`, `SELF-reverse.md`: `/1` against `/1` each way. Not worse anywhere after correction,
  and long rows do not "rise" (p 0.72 and 0.29): the test behaves as it should when nothing
  changed. Uncorrected, it flags one place in one direction.
- `POSTHOC-*.md`: **exploratory, after the fact, verdicts unchanged.** Against both `/1` runs
  pooled. `/3`: worse at nominal (position, heading), as its rejection said. `/4` repeat: its
  falls are within `/1`'s own (not significant), but Walk back rows at stressed 10 Hz are worse
  on position (158/493 failing against 177/896, p < 0.001), while long rows' position at
  randomized 10 Hz rises (111/120 against 55/180, p 0.0002). `/4` run 1 (starved): worse in 23
  places.
