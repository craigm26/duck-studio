#!/bin/sh
# Stages 2 and 3 of run_eval.sh, each started when at most four ducks are running on this
# machine (another job shares it), on its own ports. Same seeds and rows as run_eval.sh.
HERE="$(cd "$(dirname "$0")" && pwd)"
ducks() { pgrep -fc "^python3 .*mc_run.py" || true; }
until [ "$(ducks)" -le 4 ]; do sleep 30; done
"$HERE/run_batch.sh" "$HERE/raw-back" acceptance-back 400 241 8041 - -- nominal randomized randomized-10hz stressed-10hz &
sleep 120
until [ "$(ducks)" -le 4 ]; do sleep 30; done
"$HERE/run_batch.sh" "$HERE/raw" all 400 211 8141 - -- nominal randomized randomized-10hz stressed-10hz &
wait
echo "eval done $(date)"
