#!/bin/sh
# A control (docs/PACKS.md, "A control for falls", pre-registered 2026-10-18): the shipped spec,
# duck-card-loop/1, on the harness /4's repeat ran on (main after #38), fresh seeds: 521-524
# pre-registered rows, 541-544 Walk back rows, 511-514 every row. It measures how often /1 falls
# on this machine type today; it is not a candidate.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
B="$HERE/../results-walkback/run_batch.sh"
"$B" "$HERE/raw-acceptance" acceptance 400 521 7941 - -- nominal randomized randomized-10hz stressed-10hz
"$B" "$HERE/raw-back" acceptance-back 400 541 7941 - -- nominal randomized randomized-10hz stressed-10hz
"$B" "$HERE/raw" all 400 511 7941 - -- nominal randomized randomized-10hz stressed-10hz
echo "eval done $(date)"
