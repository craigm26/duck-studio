# Reproduction on a second machine (Acceptance, rung 2): IN PROGRESS

Status: the Monte Carlo is still running. Nothing below compares this machine's numbers with
`RESULTS.md` yet; the comparison is written only after the run ends, so the committed numbers
cannot steer it. This file is pushed at milestones so a restart loses nothing.

## The machine

| | |
|---|---|
| board | Raspberry Pi 5 Model B Rev 1.1 |
| CPU | 4 x Arm Cortex-A76, 1.5 to 2.4 GHz, aarch64 |
| memory | 16 GB, 2 GB zram swap |
| OS | Debian GNU/Linux 13 (trixie), kernel 6.18.39+rpt-rpi-2712 |
| python3 (runs mc_run.py, simstack.py) | 3.13.5 |
| uv venvs (body, analysis) | Python 3.12.14 |
| Rust | rustc 1.99.0, cargo 1.99.0 |
| uv | 0.12.21 |
| Pollen's code | microduck d7560ef, microduck_rl b02fdea4 (validate.sh's pins) |
| policies | pollen-robotics/microduck-policies v8, fetched 2026-10-16T00:56:58Z |

The first run was on Ubuntu 24.04 x86_64 in a cloud session, so this one differs in CPU
architecture (aarch64 against x86_64), OS and Python.

Shared machine: this Pi also runs a robot's services (carbot drive and voice, about 30% of one
core continuously) and other Claude sessions. That matters below.

## Commands

```sh
git checkout fcefea3          # in a fresh worktree of craigm26/duck-studio
WORK=~/duck-packs-repro/work OUT=~/duck-packs-repro/out \
  systemd-run --user --scope -p MemoryMax=10G -p MemorySwapMax=0 \
  sh cardreader/sim/validate.sh
```

ROWS=400 (default), sysid included. The `systemd-run` scope only caps this run's memory so it
cannot take the machine down; it changes nothing in the run.

## Run log

| run | start (UTC) | what finished | how it ended |
|---|---|---|---|
| 1 | 2026-10-16T00:54:29Z | setup (clone, cargo build, venvs, v8 policies) in about 3 min; sysid (00:58 to 01:16); batch `raw` (209 rows x 4 conditions, 01:16 to 02:57) | Another session's node/npm work on the same Pi took memory from about 04:05Z (MemAvailable fell to 500 to 900 MB, load 15 to 56). All four `raw-acceptance` processes died together at 04:29Z (`TimeoutError: timed out` on robotd's socket) at 366 to 374 of 400 rows; validate.sh's `wait` returned and went on, so `raw-back` ran 111 rows under the same starvation and died at 05:02Z (`robot.stop: no answer in 10.0 s`), `raw-rate` could not bring a body up, and the Pi rebooted at 05:06Z (a memory reboot: throttled 0x0, 5 V steady). |
| 2 | 2026-10-16T06:08:37Z | `raw` was complete, so it resumed in seconds (SKIP_SYSID=1) | A local llama-server another session started at 07:25Z took memory (MemAvailable about 550 MB); the Pi rebooted at 07:40Z with `raw-acceptance` at 331 to 336 of 400. |
| 3 | 2026-10-16T15:20:54Z | running | |

The rows of the unfinished batches from runs 1 and 2 are kept on the machine
(`~/duck-packs-repro/interrupted/`), not used: part of each ran while the bodies were behind
real time, and `mc_run.py` reseeds a resumed file at `seed x 1000 + rows done`, so a resumed
batch draws different conditions from an uninterrupted one. Run 3 reruns `raw-acceptance`,
`raw-back` and `raw-rate` from row 0 at validate.sh's seeds. sysid and `raw` are from run 1, which
ran with the machine otherwise quiet (MemAvailable 8.6 to 11 GB, no "behind real time" past the
bodies' start).

## Defects found so far (README and script)

1. **cardreader/README.md never mentions `validate.sh` or `mc_summary.py`.** Its "Proving it in
   duck-sim" section describes the older manual path (mediad, webrtcsink, GStreamer, `up.sh`)
   and points to `cardreader/sim/sysid/` and `cardreader/sim/results/` only. A stranger finds
   `validate.sh` through `cardreader/sim/sysid/README.md` or docs/PACKS.md's rung-1 results
   section. The `mc_summary.py` usage line is in the script's own docstring and in validate.sh.
2. **validate.sh does not stop when a Monte Carlo process dies.** `batch` backgrounds four
   `mc_run.py` and `wait`s without checking their exit codes, so a batch whose ducks all died
   (run 1: socket timeouts) is followed by the next batch and, at the end, by `mc_summary.py`
   over short files. With `set -eu` a stranger expects a failure to stop the script.
3. **`mc_run.py` retries "session failed to start" forever** (the `continue` in its loop), and
   each retry consumes the condition RNG; run 1's `raw-rate` sat in that loop until the reboot.
4. **Resuming changes the draws.** `mc_run.py` seeds `random.Random(seed * 1000 + done)`, so the
   comment in validate.sh ("mc_run.py resumes a file it finds") is true but a resumed file is not
   the same rows as an uninterrupted one. Reproducing the seeds needs an uninterrupted batch.
5. **NEEDS says "about 6 GB of memory and 4 cores" and the run is wall-clock real time.** The
   body steps in real time (`body_server.py` warns "behind real time"), so any other load on the
   machine changes the physics a row sees. The script does not check for this or record it per
   row; a reproduction on a shared machine cannot tell from the rows alone which ran starved.
6. **Wall time.** validate.sh says "about 6 hours on 4 cores". On this Pi: setup 3 min, sysid
   18 min, `raw` 101 min; the `raw-acceptance` batch runs about 4 rows a minute per condition.
7. No `/usr/bin/time` on Debian 13 by default (only matters to the wrapper used here; not a
   defect of the repository).

Nothing extra had to be installed: Rust, uv, python3 3.13, build-essential, pkg-config and
libudev-dev were already on the machine, and the cargo build, both uv venvs (mujoco 3.10.0,
onnxruntime 1.24.4 and numpy 2.4.1 all have aarch64 wheels) and the v8 seed worked first time.

## Outputs so far

- `repro/sysid/sysid.md`, `repro/sysid/sysid.json`: this machine's system identification (run 1).
- `repro/raw/*.jsonl`: batch `raw`, 209 rows per condition (run 1).
