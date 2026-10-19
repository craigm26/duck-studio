#!/bin/sh
# Closed-loop Duck Cards on Pollen's own stack, end to end, from a clean machine: build Pollen's
# robotd and duck-body, seed the v8 policies, identify the duck through robot.move
# (cardreader/sim/sysid/), run the Monte Carlo (cardreader/sim/mc/) and hold it to
# docs/PACKS.md, "Acceptance" (cardreader/sim/results/RESULTS.md).
#
#   cardreader/sim/validate.sh                    # everything: about 6 hours on 4 cores
#   ROWS=40 cardreader/sim/validate.sh            # a quick look (cannot pass the fall bound)
#   SKIP_SYSID=1 cardreader/sim/validate.sh       # the Monte Carlo only
#
# NEEDS: Linux (x86_64 or aarch64), git, curl, python3 (3.12 or newer), uv, a Rust toolchain
# (cargo), pkg-config and libudev (apt: build-essential pkg-config libudev-dev), about 6 GB of
# memory and 4 cores. No GPU: the body runs headless. Nothing is installed system-wide;
# everything goes under $WORK.
#
# THE SAME COMMIT, CONDITIONS AND SEEDS as the results in this repository: Pollen's repositories
# are checked out at the commits below, the policies are the Hub's v8 tag, the seeds are fixed in
# this script. A second machine reproducing them is rung 2 of "Acceptance".
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WORK="${WORK:-$HOME/duck-cards-sim}"
ROWS="${ROWS:-400}"
MICRODUCK_SHA="${MICRODUCK_SHA:-d7560ef059c73fab4177eb247c1774013f6feb9d}"
MICRODUCK_RL_SHA="${MICRODUCK_RL_SHA:-b02fdea4902c2b93b7d34a83a6f05da4ececb7d3}"
# A fresh directory: mc_run.py resumes a file it finds, so this repository's own results are
# never appended to. Compare $OUT/RESULTS.md with cardreader/sim/results/RESULTS.md.
OUT="${OUT:-$WORK/results}"
say() { printf '== %s\n' "$*"; }

mkdir -p "$WORK"
export MICRODUCK="$WORK/microduck" MICRODUCK_RL="$WORK/microduck_rl"
export DUCK_SIM_POLICIES="$WORK/policies/current"

say "Pollen's code at the pinned commits"
[ -d "$MICRODUCK/.git" ] || git clone -q https://github.com/pollen-robotics/microduck "$MICRODUCK"
[ -d "$MICRODUCK_RL/.git" ] || git clone -q https://github.com/pollen-robotics/microduck_rl "$MICRODUCK_RL"
(cd "$MICRODUCK" && git fetch -q origin && git checkout -q "$MICRODUCK_SHA")
(cd "$MICRODUCK_RL" && git fetch -q origin && git checkout -q "$MICRODUCK_RL_SHA")

say "robotd (cargo, debug, as duck-sim builds it)"
(cd "$MICRODUCK" && cargo build -q -p robotd -p robotctl)

say "the body's venv, without torch"
if [ ! -x "$MICRODUCK_RL/.venv/bin/python" ]; then
    (cd "$MICRODUCK_RL" && uv venv -q .venv \
        && uv pip install -q --python .venv mujoco==3.10.0 numpy==2.4.1 onnxruntime==1.24.4 pillow \
        && uv pip install -q --python .venv --no-deps -e .)
fi

say "the analysis venv"
[ -x "$WORK/ana/bin/python" ] || { uv venv -q "$WORK/ana" && uv pip install -q --python "$WORK/ana" numpy scipy matplotlib; }

say "Pollen's v8 policy set"
sh "$MICRODUCK/scripts/seed-policies.sh" "$WORK/policies"
grep -q '^version=v8' "$WORK/policies/current/.source" || { echo "the policy set is not v8" >&2; exit 1; }

if [ -z "${SKIP_SYSID:-}" ]; then
    say "system identification (about 20 minutes)"
    python3 "$HERE/sysid/simstack.py" up --state "$WORK/sysid-state" --port 7831
    python3 "$HERE/sysid/sysid_run.py" --sock "$WORK/sysid-state/duck.sock" --body-port 7831 \
        --out "$WORK/sysid-raw" --reps 3 --seed 1 || true
    python3 "$HERE/sysid/simstack.py" down --state "$WORK/sysid-state" --port 7831
    "$WORK/ana/bin/python" "$HERE/sysid/sysid_fit.py" "$WORK/sysid-raw" "$WORK/sysid"
    say "fits in $WORK/sysid/sysid.md (this repository's are in cardreader/sim/sysid/)"
fi

# Which machine ran these rows, and how loaded it was while it did: a second run only counts as
# rung 2 of "Acceptance" on different hardware, and a starved machine makes late cards.
mkdir -p "$OUT"
{
    echo "host: $(hostname)"
    echo "date_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "uname: $(uname -srm)"
    echo "cpus: $(nproc)"
    echo "cpu_model: $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //')"
    echo "mem_total: $(grep MemTotal /proc/meminfo | awk '{print $2 " kB"}')"
    echo "duck_studio_commit: $(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "microduck: $MICRODUCK_SHA"
    echo "microduck_rl: $MICRODUCK_RL_SHA"
    echo "rows: $ROWS"
} > "$OUT/HOST.txt"
# One line a minute: the load average and free memory, for as long as this script runs.
( while :; do echo "$(date -u +%H:%M:%S) $(cut -d' ' -f1-3 /proc/loadavg) $(grep MemAvailable /proc/meminfo | awk '{print $2}')"; sleep 60; done ) \
    > "$OUT/load.log" 2>/dev/null &
LOADPID=$!
trap 'kill $LOADPID 2>/dev/null' EXIT

# The four batches cardreader/sim/results/ holds, at the same seeds and rows. ROWS scales them:
# 400 (the default) is what was run; anything less is a quick look that cannot pass the fall bound.
scale() { echo $(( $1 * ROWS / 400 )); }

# batch DIR ROWSET ROWS SEED0 CONDITION...: one duck per condition, in parallel, then wait.
batch() {
    dir="$1"; set="$2"; n="$3"; seed="$4"; shift 4
    say "Monte Carlo, $dir: $* ($n rows each, $set rows)"
    mkdir -p "$OUT/$dir" "$WORK/logs"
    i=0
    for cond in "$@"; do
        port=$((7841 + 10 * i))
        python3 "$HERE/mc/mc_run.py" --condition "$cond" --rows "$n" --port "$port" --rows-set "$set" \
            --out "$OUT/$dir" --seed $((seed + i)) --state "$WORK/mc-$port" \
            --spec "${SPEC:-$HERE/spec-loop1.json}" > "$WORK/logs/$dir-$cond.log" 2>&1 &
        pids="$pids $!"
        i=$((i + 1))
        sleep 20
    done
    # Every duck must finish its rows: a duck that died leaves a short file, and a summary of short
    # files would look like a result.
    failed=""
    for p in $pids; do wait "$p" || failed=1; done
    pids=""
    for cond in "$@"; do
        got=$(cat "$OUT/$dir/$cond.jsonl" 2>/dev/null | wc -l)
        [ "$got" -ge "$n" ] || { echo "$dir/$cond: $got of $n rows (log: $WORK/logs/$dir-$cond.log)" >&2; failed=1; }
    done
    [ -z "$failed" ] || { echo "a Monte Carlo batch did not finish; stopping before the summary" >&2; exit 1; }
}
pids=""

batch raw all "$(scale 209)" 11 nominal randomized randomized-10hz stressed-10hz
batch raw-acceptance acceptance "$(scale 400)" 21 nominal randomized randomized-10hz stressed-10hz
batch raw-back acceptance-back "$(scale 320)" 41 nominal randomized randomized-10hz stressed-10hz
batch raw-rate acceptance "$(scale 200)" 31 nominal-10hz nominal-50hz

python3 "$HERE/mc/mc_summary.py" "$OUT/raw" "$OUT/raw-acceptance" "$OUT/raw-back" "$OUT/raw-rate" > "$OUT/RESULTS.md"
say "results: $OUT/RESULTS.md (this repository's: cardreader/sim/results/RESULTS.md)"
