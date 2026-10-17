# Reproduction of the duck-sim Monte Carlo (Acceptance, rung 2): NOT REPRODUCED

docs/PACKS.md, "Acceptance", rung 2: "The same commit, conditions and seeds, run again from a
fresh checkout on a different machine, passing the same criteria." This is that attempt, for
`duck-packs-sim` at fcefea3, done from `cardreader/README.md`, docs/PACKS.md (Acceptance, Sizing)
and `cardreader/sim/validate.sh` only. `RESULTS.md` and `../sysid/sysid.md` were not opened until
this machine's run had finished and its own `mc_summary.py` output was committed (b1b1257).

**Verdict: NOT REPRODUCED**, for two separate reasons.

1. **Five PASS/FAIL verdicts on the pre-registered rows differ** (below). Every difference turns
   on one to three rows (a fall, a card a fraction of a second past its bound) or on a heading
   share a few points either side of 95%; none of the proportions differ beyond what their
   Wilson 95% intervals allow (every pair of intervals overlaps), and only one difference
   (randomized-10hz heading, 93.8% against 96.9%, Fisher exact p = 0.039) would be called
   significant on its own. But the rung's test is the verdicts, and they do not all match.
2. **This was not a different machine.** The committed rows were run on a Raspberry Pi 5
   (`README.md`: "Run on 2026-10-15 on one Raspberry Pi 5"), and they were run on *this* Pi: the
   committed `raw-acceptance/nominal.jsonl` is byte-identical to one under this host's
   `~/projects/duck-studio-wt/walkback/`, and the rung-1 working directories (`~/scratch/ducksim/`:
   pilots, `mc-v1`, `validate-smoke`) are on this host. So even a perfect match here would show a
   clean checkout reproduces on the same hardware, not that the result carries to another
   machine. Rung 2 still needs a run on different hardware (for example the x86_64 Ubuntu 24.04
   machine validate.sh names).

What did reproduce: every verdict on nominal (20 Hz), nominal-10hz and nominal-50hz; position on
every condition; the stressed condition failing position and heading; ending badly 100% in every
condition; every verdict in the packs' every-row table; and the system identification except one
step at the forward dead band's edge.

## The machine

| | |
|---|---|
| host | Raspberry Pi 5 Model B Rev 1.1 (the same host as rung 1, see above) |
| CPU | 4 x Arm Cortex-A76, 1.5 to 2.4 GHz, aarch64; no GPU used |
| memory | 16 GB, 2 GB zram swap |
| OS | Debian GNU/Linux 13 (trixie), kernel 6.18.39+rpt-rpi-2712 |
| python3 (validate.sh, mc_run.py, mc_summary.py) | 3.13.5 |
| uv venvs (body, analysis) | Python 3.12.14 |
| Rust | rustc 1.99.0, cargo 1.99.0 |
| uv | 0.12.21 |
| Pollen's code | microduck d7560ef, microduck_rl b02fdea4 (validate.sh's pins) |
| policies | pollen-robotics/microduck-policies v8, fetched 2026-10-16T00:56:58Z |

Shared machine: the Pi also runs a robot's services (carbot drive and voice, about 30% of one
core), the Duck Studio router (about 2 GB resident) and other Claude sessions.

## Commands

```sh
git checkout fcefea3          # fresh worktree of craigm26/duck-studio
WORK=~/duck-packs-repro/work OUT=~/duck-packs-repro/out \
  systemd-run --user --scope -p MemoryMax=10G -p MemorySwapMax=0 \
  sh cardreader/sim/validate.sh                      # run 1: ROWS=400, sysid included
# runs 2 and 3, after the reboots below: the same, with SKIP_SYSID=1 (validate.sh's own switch)
python3 cardreader/sim/mc/mc_summary.py $OUT/raw $OUT/raw-acceptance $OUT/raw-back $OUT/raw-rate
```

The `systemd-run` scope only caps this run's memory; it changes nothing in the run. The summary
command's output is identical (`cmp`) to the `RESULTS.md` validate.sh wrote, and is
`repro/RESULTS.md`.

## Run log and wall time

| run | UTC | what finished | how it ended |
|---|---|---|---|
| 1 | 2026-10-16 00:54:29 to 05:06 | setup (clone, cargo build, venvs, v8 seed) about 3 min; sysid 18 min (00:58 to 01:16); `raw`, 209 rows x 4, 101 min (01:16 to 02:57) | Another session's node/npm work took the memory from about 04:05 (MemAvailable 500 to 900 MB, load 15 to 56). All four `raw-acceptance` processes died at 04:29 (`TimeoutError: timed out` on robotd's socket) at 366 to 374 of 400 rows; validate.sh carried on, `raw-back` ran 111 starved rows and died at 05:02 (`robot.stop: no answer in 10.0 s`), `raw-rate` could not start a body, and the Pi rebooted at 05:06 (memory, not power: throttled 0x0, 5 V steady). |
| 2 | 06:08:37 to 07:40 | `raw` complete, resumed in seconds | A llama-server another session started at 07:25 took the memory; the Pi rebooted at 07:40 with `raw-acceptance` at 331 to 336 of 400. |
| 3 | 15:20:54 to 19:39:48 | `raw-acceptance` 400 x 4 (to 17:08), `raw-back` 320 x 4 (to 18:46), `raw-rate` 200 x 2 (to 19:39), each uninterrupted, then `RESULTS.md` | exit 0 |

**Wall time of the rows used: 6 h 22 min** (run 1's 2 h 03 min for setup, sysid and `raw`, plus
run 3's 4 h 19 min), about what validate.sh says ("about 6 hours on 4 cores"). Elapsed from first
start to finish, with the two reboots: 18 h 45 min.

The unfinished batches of runs 1 and 2 are kept on the machine (`~/duck-packs-repro/interrupted/`)
and not used: part of each ran starved, and `mc_run.py` reseeds a resumed file, so a resumed batch
would not draw what an uninterrupted one does. Run 3 reran them from row 0.

**Load during run 3.** From 15:31 to past the end, another session ran its own four-duck Monte
Carlo (`walkback`, ports 7941 to 7971) on the same Pi, so this run's four ducks shared four cores
with three to five others (sampled every 30 s from 17:39: four others in 209 of 239 samples;
load average up to 16.6; MemAvailable never under 3.2 GB). Bodies logged "behind real time" a
handful of times when sampled (0.28 to 0.85 s, one each); the sampler only sees a session's log
while it is open, so this is a lower bound. Rung 1's README says up to eight ducks ran at once
there too and no body fell behind. Whether the extra load explains the late cards below
(6.13 s and 6.02 s against a 6 s bound) cannot be told from the rows: `mc_run.py` does not record
real-time slip per row.

## Comparison: pre-registered rows (the Acceptance table)

This machine against committed. "Agree": each proportion inside the other's Wilson 95% interval
("yes"), or the two intervals only overlap ("overlap"); no pair failed to overlap. Falls give the
count and the Wilson upper bound the criterion uses. Every criterion and section, with intervals,
is in `repro/COMPARISON.md`.

| condition | criterion | this machine | committed | verdicts | agree |
|---|---|---|---|---|---|
| nominal 20 Hz | position | 452/455 = 99.3% PASS | 449/455 = 98.7% PASS | same | yes |
| | heading | 99.3% PASS | 98.7% PASS | same | yes |
| | falls | 0 (0.84%) PASS | 0 (0.84%) PASS | same | yes |
| | time | 0 late PASS | 0 late PASS | same | yes |
| | ending badly | 2/2 PASS | 6/6 PASS | same | overlap |
| randomized 20 Hz | position | 441/455 = 96.9% PASS | 441/455 = 96.9% PASS | same | yes |
| | heading | 434/455 = 95.4% PASS | 440/455 = 96.7% PASS | same | yes |
| | falls | **1 (1.23%) FAIL** | 0 (0.84%) PASS | **DIFFERENT** | overlap |
| | time | 0 late PASS | 0 late PASS | same | yes |
| | ending badly | 9/9 PASS | 7/7 PASS | same | yes |
| randomized 10 Hz | position | 437/455 = 96.0% PASS | 442/455 = 97.1% PASS | same | yes |
| | heading | **427/455 = 93.8% FAIL** | 441/455 = 96.9% PASS | **DIFFERENT** | overlap (Fisher p = 0.039) |
| | falls | 0 (0.84%) PASS | 0 (0.84%) PASS | same | yes |
| | time | **1 late (Turn 6.13 s) FAIL** | 0 late PASS | **DIFFERENT** | overlap |
| | ending badly | 16/16 PASS | 8/8 PASS | same | yes |
| stressed 10 Hz | position | 375/455 = 82.4% FAIL | 395/455 = 86.8% FAIL | same | overlap (p = 0.081) |
| | heading | 381/455 = 83.7% FAIL | 397/455 = 87.3% FAIL | same | overlap (p = 0.16) |
| | falls | **2 (1.59%) FAIL** | 0 (0.84%) PASS | **DIFFERENT** | overlap |
| | time | 0 late PASS | 0 late PASS | same | yes |
| | ending badly | 39/39 PASS | 26/26 PASS | same | yes |
| nominal 10 Hz (200) | position, heading | 99.0%, 99.0% PASS | 99.0%, 99.0% PASS | same | yes |
| | falls (200 rows cannot pass) | 0 (1.88%) FAIL | 0 (1.88%) FAIL | same | yes |
| | time, ending badly | PASS, 2/2 PASS | PASS, 2/2 PASS | same | yes |
| nominal 50 Hz (200) | position, heading | 98.5%, 98.5% PASS | 99.5%, 99.5% PASS | same | overlap |
| | falls | 0 (1.88%) FAIL | 0 (1.88%) FAIL | same | yes |
| | time, ending badly | PASS, 3/3 PASS | PASS, 1/1 PASS | same | yes |

## Comparison: the rows with Walk back, on their own

| condition | position | heading | falls | time | ending badly |
|---|---|---|---|---|---|
| nominal | 99.3% / 99.3%, PASS both | 99.5% / 99.3%, PASS both | 0 / 0, PASS both | PASS both | 2/2 / 3/3 |
| randomized | 97.3% / 96.8%, PASS both | 98.0% / 98.3%, PASS both | 0 / 0, PASS both | PASS both | 6/6 / 5/5 |
| randomized-10hz | 94.5% / 92.8%, FAIL both | 95.5% / 96.0%, PASS both | 0 / 0, PASS both | **1 late (Turn 6.13 s) FAIL / PASS** | 12/12 / 15/15 |
| stressed-10hz | 82.4% / 79.9%, FAIL both | 84.6% / 84.1%, FAIL both | 0 / 0, PASS both | **1 late (Turn 6.02 s) FAIL / PASS** | 23/23 / 30/30 |
| nominal-10hz (36) | 100% / 100% | 100% / 100% | FAIL both (36 rows) | PASS both | 0/0 both |
| nominal-50hz (36) | 97.2% / 100%, PASS both | 97.2% / 100%, PASS both | FAIL both (36 rows) | PASS both | 1/1 / 0/0 |

(this machine / committed; all proportions agree within the Wilson intervals, the 50 Hz pair by
overlap only.) In the summary's "rows without Walk back" table one more verdict differs:
randomized-10hz heading, 93.0% FAIL here against 96.5% PASS committed; the fall verdicts there
fail on both machines (372 rows cannot pass the bound with no falls).

## Comparison: the packs' own rows (every row, not pre-registered)

| condition | position | heading | falls | time | ending badly |
|---|---|---|---|---|---|
| nominal | 99.5% / 99.5% PASS | 99.5% / 99.5% PASS | 0 / 0 (209 rows) FAIL | PASS | PASS |
| randomized | 77.0% / 79.3% FAIL | 86.1% / 89.4% FAIL | 0 / 0 FAIL | PASS | PASS |
| randomized-10hz | 73.2% / 76.5% FAIL | 88.5% / 88.7% FAIL | 0 / 0 FAIL | PASS | PASS |
| stressed-10hz | 48.8% / 44.1% FAIL | 60.3% / 59.5% FAIL | 0 / 0 FAIL | PASS | PASS |

Every verdict matches and every proportion agrees within the intervals. Rows: 209 per condition
here (validate.sh's `scale 209`); committed 209, 208, 204 and 227, so the committed `raw/` batch
was not produced by validate.sh as it stands (defect 4). Row by row, the long pack rows fail on
both machines under randomization (design-a-level and loop-8 to loop-10 at 0 to 2 of 5).

## Comparison: system identification

| axis | dir | dead band (never moved up to) | moves every time from | delay L (s) | tau (s) | steady state at the bound |
|---|---|---|---|---|---|---|
| vx | + | **0.150** / 0.200 | **0.200** / 0.250 | 0.12 / 0.15 | 0.28 / 0.23 | 0.135 / 0.135 m/s |
| vx | - | 0.300 / 0.300 | 0.350 / 0.350 | 0.60 / 0.56 | 0.14 / 0.13 | -0.173 / -0.170 m/s |
| vyaw | + | 0.500 / 0.500 | 0.625 / 0.625 | 0.00 / 0.00 | 0.37 / 0.39 | 61.9 / 63.1 deg/s |
| vyaw | - | 0.250 / 0.250 | 0.500 / 0.500 | 0.00 / 0.00 | 0.23 / 0.32 | -62.3 / -65.8 deg/s |

(this machine / committed.) One step differs: a forward command of +0.200 walked 3 of 3 here
(0.069 m/s) and 0 of 3 in the committed fit, so the forward dead band's edge reads 0.15 to 0.20
here against 0.20 to 0.25 there. The forward ramps put the onset at 0.234 and 0.235 here, 0.227
and 0.229 there, so the duck sits right at that edge, and docs/PACKS.md's "stands still up to
0.20 forward and walks every time from 0.25" is one run's reading of it. Walk forward cards
command 0.30 to 0.40, so the cards are not affected. Everything else (backward dead band, both
turn dead bands, ramp drop-outs, deadman 0.50 to 0.52 s, odometry error, state rates of 8.8 /
9.2, 16.7 / 16.7 and 39.2 / 40.0 frames a second for 10, 20 and 50 Hz) agrees closely.

## Seeds

The same seeds do not give the same rows past the first stack session. Row names match row for
row, and the first session's knobs (rows 0 to 11) match exactly, but from row 12 on the
randomized conditions' knobs differ (12 of 400 equal in `raw-acceptance/randomized`; nominal,
whose knobs are fixed, 400 of 400). `mc_run.py` draws a session's knobs and each row's latency
and noise from one `random.Random`, and the number of draws a row takes depends on how it ran,
so after one session the two runs' streams part. Even nominal rows with identical knobs end
differently (row 0: 5.9 cm here, 3.4 cm committed), because the body steps in wall-clock real
time. The comparison is therefore statistical, as above, not row for row.

## Defects found in the README and the script

1. **cardreader/README.md does not mention `validate.sh` or `mc_summary.py`.** "Proving it in
   duck-sim" describes the older manual path (mediad, webrtcsink, GStreamer, `up.sh`) and points
   at `sim/sysid/` and `sim/results/`. A stranger finds validate.sh through `sim/sysid/README.md`
   or docs/PACKS.md's rung-1 section; `mc_summary.py`'s usage is in its own docstring and in
   validate.sh.
2. **validate.sh does not stop when a Monte Carlo process dies.** `batch` backgrounds four
   `mc_run.py` and `wait`s without checking their exit codes, so a batch whose ducks all died
   (run 1) is followed by the next batch and then by `mc_summary.py` over short files. Under
   `set -eu` a reader expects a failure to stop the script.
3. **`mc_run.py` retries "session failed to start" forever** (the `continue`), consuming the
   condition RNG on each try; run 1's `raw-rate` sat in that loop until the reboot.
4. **"The same seeds" do not reproduce the same conditions** (section above): the draws depend on
   timing after the first session, and a resumed file is reseeded at `seed x 1000 + rows done`.
   The committed `raw/` batch also has 208, 204 and 227 rows where validate.sh makes 209 of each,
   so it was not produced by the script as written.
5. **Real time is not checked or recorded.** The body steps in wall-clock time and warns when
   behind, but nothing records per row whether a row ran behind, and validate.sh does not check
   that the machine is otherwise idle. NEEDS asks for "about 6 GB of memory and 4 cores"; on a
   shared machine that is not enough to know the rows are clean.
6. **Nothing says which host ran rung 1.** RESULTS.md and README.md say "one Raspberry Pi 5", so
   a second run on that same Pi looks like rung 2 when it is not. Rung 1's record should name the
   host, and rung 2 should name a different one.

Nothing extra had to be installed: Rust, uv, python3 3.13, build-essential, pkg-config and
libudev-dev were already present, and the cargo build, both uv venvs (mujoco 3.10.0, onnxruntime
1.24.4 and numpy 2.4.1 have aarch64 wheels) and the v8 seed worked first time. Not a repository
defect: Debian 13 has no `/usr/bin/time` by default.

## Outputs (`repro/`)

- `RESULTS.md`: this machine's `mc_summary.py` output, committed before the comparison.
- `COMPARISON.md`: every criterion of every condition and section, both machines, Wilson intervals.
- `sysid/sysid.md`, `sysid/sysid.json`: this machine's system identification (run 1).
- `raw/`, `raw-acceptance/`, `raw-back/`, `raw-rate/`: this machine's rows, one JSON line each.
