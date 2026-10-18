#!/bin/sh
# duck-card-loop/4's one evaluation (docs/PACKS.md, pre-registered 2026-10-18), on
# cardreader/sim/candidate-compass.json (chosen on development seeds 101-104, dev/), fresh seeds:
# 421-424 pre-registered rows, 441-444 Walk back rows, 411-414 every row. The mat eye renders on
# microduck_rl's venv; set MUJOCO_GL (osmesa on a machine without a GPU).
set -eu
# matcam.py needs numpy in the python3 that runs mc_run.py: fail now, not at the first look.
python3 -c "import numpy" || { echo "run_eval: python3 has no numpy (apt install python3-numpy)"; exit 3; }
HERE="$(cd "$(dirname "$0")" && pwd)"
B="$HERE/../results-walkback/run_batch.sh"
SPEC="$HERE/../candidate-compass.json"
"$B" "$HERE/raw-acceptance" acceptance 400 421 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
"$B" "$HERE/raw-back" acceptance-back 400 441 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
"$B" "$HERE/raw" all 400 411 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
echo "eval done $(date)"
