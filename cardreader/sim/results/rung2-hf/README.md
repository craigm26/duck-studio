# Rung 2 on a different machine: HF Jobs, x86

The committed Monte Carlo (`../`, duck-card-loop/1 at fcefea3) was made on a Raspberry Pi 5. The
first attempt at rung 2 (branch duck-packs-sim-repro) ran on that same Pi, so it could not count.
This one ran on Hugging Face Jobs, `cpu-upgrade` (8 vCPU of an AMD EPYC 7R13 host, x86_64), job
6ad2840c5ccb47ba0f7b59e1, 2026-10-16 20:07 to 2026-10-17 02:23 UTC (6 h 16 min including the build).

- **What ran:** `cardreader/sim/validate.sh` at 40edf69, with defaults (ROWS=400, sysid included). The
  controller, conditions, seeds and criteria are fcefea3's; 40edf69 changes only the script (it records
  `HOST.txt` and `load.log`, and stops on a duck that died). Nothing extra had to be installed beyond
  validate.sh's NEEDS line. No duck logged "behind real time". `load.log` is the host's, not the job's
  (the host has 64 cores), so it cannot show whether this job was starved.
- **Every row:** `COMPARE.md`, each criterion beside the committed one with Wilson 95% intervals.
- **System identification:** `sysid/sysid.md`. It matches the committed fits within the trial spread;
  forward walks from 0.25 (0.20 three times out of three here), the ramp onset is 0.23 on both.

## Verdict

**Rung 2: NOT REPRODUCED, by one verdict.** Of every rung-1 verdict (pre-registered rows and Walk back
rows, five criteria, four conditions), one differs: pre-registered rows, randomized 10 Hz, heading,
committed PASS 96.9% [94.9, 98.2], here FAIL 94.9% [92.5, 96.6]. The intervals overlap. The
same-Pi repeat got 93.8% for the same criterion. Two later runs both below 95% say the committed
PASS was the lucky draw: heading at Studio's 10 Hz rate sits at about 95%, on the line.

Everything else agrees:
- Every other verdict matches, including both runs failing rung 1 (stressed 10 Hz, and Walk back at
  randomized 10 Hz on position).
- **No falls** in any of this run's 4,128 rows, as in the committed run. The 1 to 2 falls a condition
  in the same-Pi repeat, and the 11 in the Walk lead's evaluation, came while that Pi was overloaded.
- The packs' long rows (10 cards or more) agree within intervals: randomized 33 to 42%, stressed 0%.

Rung 1 is not passed on either machine.
