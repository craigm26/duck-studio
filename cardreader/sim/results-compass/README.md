# duck-card-loop/4: the mat as a compass

Pre-registered in docs/PACKS.md (commit 7cc2b07) before any development row ran.

- `dev/base`: development only (seeds 101-102, 60 rows each of randomized-10hz and
  stressed-10hz, the Pi), on `../candidate-compass.json` as pre-registered. Not a result. Every one
  of 825 looks was accepted; randomized-10hz 60/60 position and heading (long rows 15/15);
  stressed-10hz 47/60 position, its misses mostly Turn right cards trimmed out short at friction
  0.5, as `/1`'s are (28 such rows in `../results/rung2-hf/raw`), before any look. No setting was
  changed after it.
- `run_eval.sh`: the one evaluation, on HF Jobs from a fresh checkout; rows in `raw-acceptance/`
  (seeds 421-424), `raw-back/` (441-444), `raw/` (411-414).

**A first launch scored nothing** (HF job 6ad43ba85ccb47ba0f7c0b28 at 4e7e3d8, 2026-10-18 03:23 to
03:34 UTC): that machine's `python3` had no numpy, so every row stopped at its first look with
`ModuleNotFoundError` before any row was scored or written (0 rows in every file). No setting
changed; `run_eval.sh` now checks for numpy first and the job installs `python3-numpy`, and the
evaluation was launched again, unchanged, on the same seeds.
