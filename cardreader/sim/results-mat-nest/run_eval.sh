#!/bin/sh
# duck-card-loop/7's one evaluation (docs/PACKS.md, "/4b", pre-registered 2026-10-19), on
# cardreader/sim/candidate-mat-nest.json (/6 with /4's mat and the mat calibrating the camera's
# pitch), fresh seeds: 821-824 pre-registered rows, 841-844 Walk back rows, 811-814 every row. The
# mat eye renders on microduck_rl's venv on one thread at nice 10 (mc/mc_run.py MatEye); set
# MUJOCO_GL (osmesa without a GPU). Valid only if 10 or fewer of its 4,800 rows stop on a stale pose.
set -eu
python3 -c "import numpy" || { echo "run_eval: python3 has no numpy (apt install python3-numpy)"; exit 3; }
HERE="$(cd "$(dirname "$0")" && pwd)"
B="$HERE/../results-walkback/run_batch.sh"
SPEC="$HERE/../candidate-mat-nest.json"
"$B" "$HERE/raw-acceptance" acceptance 400 821 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
"$B" "$HERE/raw-back" acceptance-back 400 841 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
"$B" "$HERE/raw" all 400 811 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
echo "eval done $(date)"
