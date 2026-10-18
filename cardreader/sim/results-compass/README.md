# duck-card-loop/4: the mat as a compass

Pre-registered in docs/PACKS.md (commit 7cc2b07) before any development row ran.

- `dev/base`: development only (seeds 101-102, 60 rows each of randomized-10hz and
  stressed-10hz, the Pi), on `../candidate-compass.json` as pre-registered. Not a result. Every one
  of 825 looks was accepted; randomized-10hz 60/60 position and heading (long rows 15/15);
  stressed-10hz 47/60 position, its misses mostly Turn right cards trimmed out short at friction
  0.5, as `/1`'s are (28 such rows in `../results/rung2-hf/raw`), before any look. No setting was
  changed after it.
- `run_eval.sh`: the evaluation, on HF Jobs from a fresh checkout; rows in `raw-acceptance/`
  (seeds 421-424), `raw-back/` (441-444), `raw/` (411-414).
- `run1/`: the first scored evaluation (HF job 6ad43e48c66288145226f848, commit 6c7f14d,
  2026-10-18 03:35 to 11:21 UTC, 4,800 rows): its rows, `hf/` (the job's `RESULTS.md`,
  `eval.log`, `setup.log`, `HOST.txt`, `load.log`) and `COMPARE.md` against `/1` on HF:

      python3 cardreader/sim/results-walkback/compare.py \
        --before cardreader/sim/results/rung2-hf/raw cardreader/sim/results/rung2-hf/raw-acceptance cardreader/sim/results/rung2-hf/raw-back \
        --after cardreader/sim/results-compass/run1/raw cardreader/sim/results-compass/run1/raw-acceptance cardreader/sim/results-compass/run1/raw-back \
        --before-label "duck-card-loop/1, HF" --after-label "duck-card-loop/4, HF run 1" \
        --title "duck-card-loop/1 on HF (results/rung2-hf) beside duck-card-loop/4 (the mat as a compass), HF run 1"

  Rejected by the rule: long rows at randomized 10 Hz 36.7% to 80.8% position, but falls in
  every condition (146 in all) and nominal position below the bar. 170 rows stopped on a stale
  pose (2 in `/1`'s run), 17 falls came before any look, and the host's load median was 260: the
  software renderer starved the stack. See docs/PACKS.md for the repeat, pre-registered after it,
  with the renderer on one thread at nice 10, valid only if 10 or fewer rows stop on a stale pose.

**A first launch scored nothing** (HF job 6ad43ba85ccb47ba0f7c0b28 at 4e7e3d8, 2026-10-18 03:23 to
03:34 UTC): that machine's `python3` had no numpy, so every row stopped at its first look with
`ModuleNotFoundError` before any row was scored or written (0 rows in every file). No setting
changed; `run_eval.sh` now checks for numpy first and the job installs `python3-numpy`, and the
evaluation was launched again, unchanged, on the same seeds.

**The repeat** (HF job 6ad4acdcc6628814522735d7, commit dbff60d, 2026-10-18 11:27 to 18:47 UTC,
the mat eye on one render thread at nice 10, same seeds): rows in `raw-acceptance/`, `raw-back/`,
`raw/`; the job's files in `hf/`; `COMPARE.md` against `/1` on HF (the command above, with these
directories and the label "duck-card-loop/4, HF repeat"). 11 rows stopped on a stale pose, one
past the pre-registered 10: **inconclusive**. Had it counted, the rule rejects it on falls (8 in
all, 3 before any look). Long rows at randomized 10 Hz 36.7% to 92.5% position. `/4` is not adopted.
