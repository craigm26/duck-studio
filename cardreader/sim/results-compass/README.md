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
