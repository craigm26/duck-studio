# duck-card-loop/3: calibrate at every stop

Pre-registered in docs/PACKS.md (commit 4b20dfc) before any row ran.

**Verdict: rejected by its own decision rule** (docs/PACKS.md, "Candidate change: calibrate at
every stop", Result). Long rows' position at randomized 10 Hz rose (36.7% to 45.8%), but verdicts
`/1` passed on HF became fails: falls (randomized; Walk back nominal, randomized, stressed 10 Hz)
and every-row position at nominal (99.0% to 81.5%). The drift estimate sits about 0.15 deg/s low
even with no drift injected: a standing duck's yaw moves, and an IMU-only estimate takes that for
drift.

- `dev/`: development only (seeds 101-102, 60 rows a condition, the Pi), used to choose
  `calibrate.before_s` 5 over 3. Not a result.
- `run_eval.sh`: the one evaluation, run on HF Jobs (job 6ad3b3995ccb47ba0f7bc52e, `cpu-upgrade`,
  commit 0b57687, 2026-10-17 17:43 to 02:31 UTC) from a fresh checkout; rows in `raw-acceptance/`
  (seeds 321-324), `raw-back/` (341-344), `raw/` (311-314), 400 rows a condition each.
- `hf/`: the job's `RESULTS.md` (mc_summary), `eval.log`, `setup.log`, `HOST.txt`, `load.log`. No
  "behind real time" line in any log.
- `COMPARE.md`: `/1` on HF (`../results/rung2-hf/`) beside `/3`, criterion by criterion:

      python3 cardreader/sim/results-walkback/compare.py \
        --before cardreader/sim/results/rung2-hf/raw cardreader/sim/results/rung2-hf/raw-acceptance cardreader/sim/results/rung2-hf/raw-back \
        --after cardreader/sim/results-calibrate/raw cardreader/sim/results-calibrate/raw-acceptance cardreader/sim/results-calibrate/raw-back \
        --before-label "duck-card-loop/1, HF" --after-label "duck-card-loop/3, HF" \
        --title "duck-card-loop/1 on HF (results/rung2-hf) beside duck-card-loop/3 (calibrate at every stop) on HF"

The shipped spec stays `duck-card-loop/1`. The `/3` code (DriftCal in both readers, its shared
vectors) stays on main, used only by a spec that asks for `calibrate`, so this result can be rerun.
