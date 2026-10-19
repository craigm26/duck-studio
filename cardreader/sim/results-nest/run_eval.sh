#!/bin/sh
# duck-card-loop/6's one evaluation (docs/PACKS.md, pre-registered 2026-10-19), on
# cardreader/sim/candidate-nest.json (chapters.cards 7, fixed by rule from results-merge/), fresh
# seeds: 721-724 pre-registered rows, 741-744 Walk back rows, 711-714 every row. Valid only if 10 or
# fewer of its 4,800 rows stop on a stale pose.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
B="$HERE/../results-walkback/run_batch.sh"
SPEC="$HERE/../candidate-nest.json"
"$B" "$HERE/raw-acceptance" acceptance 400 721 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
"$B" "$HERE/raw-back" acceptance-back 400 741 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
"$B" "$HERE/raw" all 400 711 7941 "$SPEC" -- nominal randomized randomized-10hz stressed-10hz
echo "eval done $(date)"
