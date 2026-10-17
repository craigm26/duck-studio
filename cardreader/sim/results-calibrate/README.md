# duck-card-loop/3: calibrate at every stop

Pre-registered in docs/PACKS.md (commit 4b20dfc) before any row ran.

- `dev/`: development only (seeds 101-102, 60 rows a condition, the Pi), used to choose
  `calibrate.before_s` 5 over 3. Not a result.
- `run_eval.sh`: the one evaluation, run on HF Jobs from a fresh checkout; its rows land in
  `raw-acceptance/`, `raw-back/`, `raw/`.
