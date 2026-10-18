# duck-card-loop/5: merge cards, to spend less time

Pre-registered in docs/PACKS.md (commit ed190ae) before any row ran.

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
- `run_eval.sh`: the one evaluation, on HF Jobs (seeds 621-624, 641-644, 611-614).
