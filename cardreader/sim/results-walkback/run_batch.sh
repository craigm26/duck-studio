#!/bin/sh
# run_batch.sh DIR ROWSET ROWS SEED0 PORT0 [SPEC] -- CONDITION...
# One duck per condition, in parallel, on Pollen's stack as cardreader/sim/results/ ran it
# (~/scratch/ducksim: microduck d7560ef, microduck_rl b02fdea4, v8 policies). SPEC, when given and
# not "-", is a candidate spec for the development seeds only; the evaluation runs the shipped
# duck-card-loop.json.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
SIM="$(cd "$HERE/.." && pwd)"
S=${STACK:-$HOME/scratch/ducksim}
export MICRODUCK=$S/microduck MICRODUCK_RL=$S/microduck_rl DUCK_SIM_POLICIES=$S/policies/current
dir=$1; set_=$2; n=$3; seed=$4; port=$5; spec=$6; shift 6
[ "$1" = "--" ] && shift
mkdir -p "$dir" "$dir/logs"
i=0
for cond in "$@"; do
  p=$((port + 10 * i))
  extra=""
  [ "$spec" != "-" ] && extra="--spec $spec"
  python3 "$SIM/mc/mc_run.py" --condition "$cond" --rows "$n" --port "$p" --rows-set "$set_" \
      --out "$dir" --seed $((seed + i)) --state "$S/wb-state-$p" $extra > "$dir/logs/$cond.log" 2>&1 &
  i=$((i + 1))
  sleep 20
done
wait
