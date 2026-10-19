# duck-card-loop/5: merge cards, to spend less time

Pre-registered in docs/PACKS.md (commit ed190ae) before any row ran.

**Verdict: replaces `/1` as the base for the next idea, by its pre-registered rule; the gain is
small and, counted over sessions, not distinguishable from noise.** No verdict `/1` passed on HF
became a fail, and long rows' position at randomized 10 Hz rose, 36.7% (22/60) to 41.7%
(50/120), under the 45 to 55% predicted. The secondary analysis (declared after the falls
control, before these rows were read; `SECONDARY.md`) finds it worse nowhere, but the rise has
p 0.18 over sessions (0.03 over rows) against both `/1` runs pooled (55/180). Long rows took 47.3 s
on average against 50.1 and 52.1 s for the two `/1` runs: 6 to 9% less time, not the fifth to a
third predicted. Rung 1 still fails (stressed 10 Hz). Four verdicts went fail to pass, among them
Walk back rows' position at randomized 10 Hz (93.1% to 95.7%), and three every-row falls verdicts
that pass only because 400 rows give a tighter bound than 209. 1 fall in 4,800 rows (nominal,
duck-maze/maze-10). Valid: 0 stale-pose stops.

The shipped spec stays `duck-card-loop/1`: `/5` is the base the next candidate starts from, not a
change to what Studio runs, and nothing passes rung 1.

- `dev/`: development only (seeds 101-102, 60 rows a condition at randomized 10 Hz and stressed
  10 Hz, the Pi), used to choose `merge.walks` from 2, 3, 4 or every walk. Not a result.
  `base1/` is `/1` on the same seeds; `all/`, `w2/`, `w3/`, `w4/` are the candidates.

  | `merge.walks` | long rows, randomized 10 Hz, position | every row, randomized 10 Hz, position | long rows' mean time |
  |---|---|---|---|
  | `/1` (none) | 8/15 | 47/60 | 47.9 s |
  | 2 | **11/15** | 50/60 | 40.8 s |
  | 3 | 7/15 | 45/60 | 44.9 s |
  | 4 | 2/15 | 41/60 | 46.8 s |
  | every walk | 3/15 | 41/60 | 42.3 s |

  Chosen: 2 (`../candidate-merge.json`). Longer merged walks lose the stops that let each card
  re-aim at the board, and that costs more than the time saved. No falls in any batch.
- `run_eval.sh`: the one evaluation, on HF Jobs (job 6ad54276c66288145227a33d, `cpu-upgrade`,
  commit b48fdc5, 2026-10-18 22:05 to 2026-10-19 04:51 UTC), seeds 621-624 (`raw-acceptance/`),
  641-644 (`raw-back/`), 611-614 (`raw/`), 400 rows a condition each.
- `hf/`: the job's `RESULTS.md`, `eval.log`, `setup.log`, `HOST.txt`, `load.log`.
- `COMPARE.md`: `/1` on HF (`../results/rung2-hf/`) beside `/5`, criterion by criterion
  (`../results-walkback/compare.py`, labels "duck-card-loop/1, HF" and "duck-card-loop/5, HF").
- `SECONDARY.md`: `../results-control/secondary.py`, `/5` against both `/1` HF runs pooled.
