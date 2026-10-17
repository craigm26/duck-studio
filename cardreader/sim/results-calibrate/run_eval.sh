#!/bin/sh
# duck-card-loop/3's one evaluation (docs/PACKS.md, pre-registered 2026-10-17), on
# cardreader/sim/candidate-calibrate.json (before_s 5, chosen on development seeds 101-102,
# dev/), fresh seeds: 321-324 pre-registered rows, 341-344 Walk back rows, 311-314 every row.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
B="$HERE/../results-walkback/run_batch.sh"
SPEC="$HERE/../candidate-calibrate.json"
"$B" "$HERE/raw-acceptance" acceptance 400 321 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
"$B" "$HERE/raw-back" acceptance-back 400 341 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
"$B" "$HERE/raw" all 400 311 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
echo "eval done $(date)"
