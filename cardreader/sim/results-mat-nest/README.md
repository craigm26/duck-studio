# duck-card-loop/7 ("/4b"): the mat on the nest, the camera calibrated by the mat

Pre-registered in docs/PACKS.md (commit e119d7f) before any evaluation row of it. Decided by the
secondary analysis (`../results-control/secondary.py`) against `/6`'s HF run (`../results-nest/`).

**Verdict: replaces `/6` as the base, by its pre-registered rule, and every expectation said in
advance held.** Long rows' position at randomized 10 Hz rose from 63.3% (76/120) to 97.5%
(117/120), p 0.0002 over sessions, above the 90% expected. Worse nowhere after Holm (80 tests; 1
below 0.05 uncorrected: nominal heading on the pre-registered rows, 2/510 against 7/510). Walk back
rows' position at stressed 10 Hz went from 73.8% (129/493 failing) to 89.2% (53/493). Rung 1 still
fails (stressed 10 Hz, position 91.4% on the pre-registered rows). Valid: 0 stale-pose stops. The
shipped spec stays `duck-card-loop/6` until the mat is ported (no head camera path in StudioKit
yet) and a printed mat exists. `enabled_on_robot` stays false.

Long rows (10 cards or more), position within 10 cm by "Acceptance" (from `SECONDARY.md`), and
mean time in the sim (re-seats not counted):

| condition | `/6` | `/7` | `/6` time | `/7` time |
|---|---|---|---|---|
| nominal | 120/120 | 119/120 | 50.8 s | 55.9 s |
| randomized | 79/120 | 117/120 | 51.4 s | 56.3 s |
| randomized 10 Hz | 76/120 | **117/120** | 50.0 s | 56.6 s |
| stressed 10 Hz | 23/120 | 57/120 | 38.1 s | 42.2 s |

The looks cost about 5 s on a long row.

**The hypothesis it tested.** `/4`'s stressed Walk back rows split on the session's camera pitch
error (post hoc: +2 degrees, 89 of 214 finished rows past 10 cm; -2 degrees, 1 of 142). With the
pitch taken out by the mat, the split is gone: +2 degrees, 20 of 180 finished rows past 10 cm
(median 6.7 cm); -2 degrees, 26 of 220 (median 7.0 cm).

**The pitch it took out**, each look's estimate against the session's camera pitch (the estimate is
its mirror, by the sign convention the plumbing check found), over 4,800 rows (11 with no look):

| condition | looks | mean error | median abs | 95th pct abs | chapters within 0.5 degree |
|---|---|---|---|---|---|
| nominal | 5,355 | +0.00 | 0.00 | 0.00 | 100.0% |
| randomized | 5,359 | +0.05 | 0.20 | 0.59 | 91.5% |
| randomized 10 Hz | 5,313 | +0.01 | 0.19 | 0.59 | 92.4% |
| stressed 10 Hz | 4,638 | +0.10 | 0.40 | 0.80 | 78.5% |

Unbiased, within half a degree in most chapters as expected; stressed sessions are wider, as the
IMU's tilt and roll errors were expected to pass partly for pitch.

- `run_eval.sh`: the one evaluation, on HF Jobs (job 6ad654ca5275124786e0b675, `cpu-upgrade`, 64
  cores, commit e119d7f, 2026-10-19 17:35 to about 01:07 UTC), seeds 821-824 (`raw-acceptance/`),
  841-844 (`raw-back/`), 811-814 (`raw/`), 400 rows a condition each. Rows carry `pitch_deg` (per
  chapter, per look) and `camera` (the session's errors).
- Development was plumbing only (seeds 101-104, the Pi, not kept); nothing was chosen on it.
- `hf/`: the job's `RESULTS.md`, `eval.log`, `setup.log`, `HOST.txt`, `load.log`.
- `COMPARE.md`: `/6` on HF beside `/7`, criterion by criterion (`../results-walkback/compare.py`).
- `SECONDARY.md`: the decision, `../results-control/secondary.py`, `/7` against `/6`.
- What it does not show: a real lens, real light or a real taped mat.
