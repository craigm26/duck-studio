# duck-card-loop/6: a nest and chapters

Pre-registered in docs/PACKS.md (commit 8c768be) before any code or row of it. Decided by the
secondary analysis (`../results-control/secondary.py`) against `/5`'s HF run (`../results-merge/`).

**Verdict: replaces `/5` as the base, by its pre-registered rule.** Long rows' position at
randomized 10 Hz rose from 41.7% (50/120) to 63.3% (76/120), p 0.026 over sessions, under the 70
to 85% expected; worse nowhere after Holm (80 tests, 6 with p below 0.05 uncorrected). Rung 1
still fails (stressed 10 Hz). The old rule would reject it, on eight Walk back verdicts; no Walk
back row has more than 7 cards, so none was split and those rows are `/5`'s code on fresh seeds.
Valid: 1 stale-pose stop. The shipped spec stays `duck-card-loop/1`.

Long rows (10 cards or more), position within 10 cm, and mean time in the sim (re-seats not
counted):

| condition | `/5` | `/6` | `/5` time | `/6` time |
|---|---|---|---|---|
| nominal | 119/120 | 120/120 | 48.6 s | 50.8 s |
| randomized | 48/120 | 79/120 | 49.1 s | 51.4 s |
| randomized 10 Hz | 50/120 | **76/120** | 47.3 s | 50.0 s |
| stressed 10 Hz | 3/120 | 23/120 | 39.5 s | 38.1 s |

Which chapter of a long row failed (a row can fail in more than one): randomized 10 Hz, chapter
1: 15, 2: 32, 3: 16, 4: 4; stressed 10 Hz, 67, 51, 18, 8. Re-seat error (chapter 2 on) costs
about as much as a chapter's own drift.

- `run_eval.sh`: the one evaluation, on HF Jobs (job 6ad5a5dbc662881452281109, `cpu-upgrade`,
  commit 7fbd643, 2026-10-19 05:09 to 12:01 UTC), seeds 721-724 (`raw-acceptance/`), 741-744
  (`raw-back/`), 711-714 (`raw/`), 400 rows a condition each. Rows split into chapters carry a
  `chapters` list (cards, error, result and the re-seat drawn).
- No development rows: `chapters.cards` (7) was fixed by rule from `/5`'s rows, and the re-seat
  errors are pre-registered. A plumbing check (seeds 101-102, 5 long rows, the Pi) was not kept.
- `hf/`: the job's `RESULTS.md`, `eval.log`, `setup.log`, `HOST.txt`, `load.log`.
- `COMPARE.md`: `/5` on HF beside `/6`, criterion by criterion (`../results-walkback/compare.py`).
- `SECONDARY.md`: the decision, `../results-control/secondary.py`, `/6` against `/5`.
