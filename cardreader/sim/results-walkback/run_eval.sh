#!/bin/sh
# The one evaluation, on the shipped duck-card-loop.json (sha256 recorded on every row), fresh
# seeds: 221-224 pre-registered rows, 241-244 Walk back rows, 211-214 every row. Run once.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
"$HERE/run_batch.sh" "$HERE/raw-acceptance" acceptance 400 221 7941 - -- nominal randomized randomized-10hz stressed-10hz
"$HERE/run_batch.sh" "$HERE/raw-back" acceptance-back 400 241 7941 - -- nominal randomized randomized-10hz stressed-10hz
"$HERE/run_batch.sh" "$HERE/raw" all 400 211 7941 - -- nominal randomized randomized-10hz stressed-10hz
echo "eval done $(date)"
