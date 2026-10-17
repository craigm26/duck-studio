# duck-card-loop/2 (the Walk lead), rerun on HF Jobs

The same evaluation as `../run_eval.sh` (seeds 211–214, 221–224, 241–244; 400 rows per condition per
directory), run at de67d20 on a Hugging Face Jobs `cpu-upgrade` machine (AMD EPYC 7R13, see `HOST.txt`),
to tell the Pi evaluation's 11 falls apart from the change. Job 6ad2b13d5ccb47ba0f7b7e59, 7 h 37 min,
exit 0, every condition 400/400 rows, no "behind real time" line in any log.

- `COMPARE-pi-vs-hf.md`: the Pi evaluation beside this one, same commit.
- `COMPARE-loop1-vs-loop2-hf.md`: duck-card-loop/1 (rung 2 on HF Jobs, 40edf69, branch
  duck-packs-sim-rung2) beside duck-card-loop/2 here: both on the same kind of idle machine.

## Verdict

- **Falls: 0 in 4,800 rows.** The Pi evaluation's 11 falls were the overloaded Pi, not the Walk lead.
- **Everything else reproduces the Pi evaluation.** Against duck-card-loop/1 on HF Jobs:
  - Walk back position at randomized 10 Hz improves: FAIL 93.1% → PASS 96.3%. This is what the lead was for.
  - Walk back heading gets worse: randomized 98.3% PASS → 92.5% FAIL; randomized 10 Hz 93.8% → 92.7% (both FAIL).
  - Pre-registered randomized 10 Hz heading is 94.9% on both: FAIL either way, on the line.
  - Long rows (10 cards or more), randomized 10 Hz position: 36.7% → 20.0%.
- Rung 1 FAILS for both controllers. **duck-card-loop/2 stays not adopted**: it trades one failing
  position row for a newly failing heading row and makes long rows worse.
