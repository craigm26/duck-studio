#!/bin/sh
# duck-card-loop/5's one evaluation (docs/PACKS.md, pre-registered 2026-10-18), on
# cardreader/sim/candidate-merge.json (merge.walks chosen on development seeds 101-102, dev/), fresh
# seeds: 621-624 pre-registered rows, 641-644 Walk back rows, 611-614 every row. Valid only if 10 or
# fewer of its 4,800 rows stop on a stale pose.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
B="$HERE/../results-walkback/run_batch.sh"
SPEC="$HERE/../candidate-merge.json"
"$B" "$HERE/raw-acceptance" acceptance 400 621 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
"$B" "$HERE/raw-back" acceptance-back 400 641 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
"$B" "$HERE/raw" all 400 611 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
echo "eval done $(date)"
