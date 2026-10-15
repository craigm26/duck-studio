#!/bin/bash
# The rule, for Duck Cards: one deck, one set of answers, two readers.
#
# THE DUCK READS CARDS WITH `cardreader/` (Python, on the robot) AND STUDIO WITH
# `DuckCards` (Swift, in StudioKit). They are held to each other by
# `cardreader/vectors`: what the AprilTag library answered for a picture, and
# what the reader must make of it. StudioKit's test target carries a copy of
# those files, because a test bundle cannot reach outside its package, and a copy
# is a thing that drifts. So is the deck: StudioKit ships microduckstudio.com's
# `duck-cards.json`, and so does `cardreader/`.
#
# This fails when any copy differs from its source by a byte, or when a vector
# exists on one side only. `make_vectors.py --check` (run here too) fails when
# the Python reader would now write different vectors than the ones on disk.
#
# THE PACKS TRAVEL THE SAME WAY. StudioKit ships the Duck Card packs
# (`Resources/DuckPacks/*.duckpack`), the reader carries the same files in
# `cardreader/duckcards/packs`, and the pack vectors (`pack_*.json`) sit beside
# the card vectors. A pack on one side only, or one byte apart, fails here; then
# `check_duck_packs.py` checks every par and every row in them.
#
# SO DO WALK AND TURN ON ODOMETRY. `duck-card-loop.json` (the closed-loop card
# spec) ships in StudioKit's Resources/DuckCards and in cardreader/duckcards, and
# `vectors/cardloop/*.json` hold DuckCardLoop and cardloop.py to the same commands
# on the same odometry traces; `make_cardloop_vectors.py --check` fails when the
# reader would write different ones (it needs only python3).
#
# THIS GUARD CAN FAIL, AND IT WAS WATCHED TO: deleting one fixture vector, and
# separately changing one byte of the StudioKit deck, each made it exit 1.
# 2026-10-15, for the packs: changing one byte of the reader's copy of
# duck-maze.duckpack, deleting the reader's copy of loop-the-course.duckpack,
# and deleting the fixture copy of pack_solved.json each made it exit 1; so did
# a wrong par in get-to-the-pond, through check_duck_packs.py. For the card loop:
# max_yaw changed in the reader's duck-card-loop.json ("not StudioKit's, byte for
# byte"), the fixture copy of cardloop/turn_left_arrives.json deleted ("Only in"),
# and walk_forward_arrives.json's speed edited in both copies ("would change")
# each made it exit 1. For Pollen's envelope (pollen-pad-drive.json): the
# unclamped duck-card-loop.json (back 0.45, Fast 0.45, turn and trim 1.5) made it
# exit 1 with eight "past Pollen's pad envelope" lines, before the clamp.
#
# Usage:  scripts/check_duckcards_vectors.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/cardreader/vectors"
COPY="$ROOT/StudioKit/Tests/StudioKitTests/Fixtures/DuckCards/vectors"
fail=0

if ! diff -rq "$SRC" "$COPY" >/dev/null; then
  echo "check_duckcards_vectors: StudioKit's vectors differ from cardreader/vectors:" >&2
  diff -rq "$SRC" "$COPY" >&2 || true
  echo "  copy them: cp cardreader/vectors/*.json $COPY/" >&2
  fail=1
fi

LOOP="$ROOT/cardreader/duckcards/duck-card-loop.json"
KIT_LOOP="$ROOT/StudioKit/Sources/StudioKit/Resources/DuckCards/duck-card-loop.json"
if ! cmp -s "$LOOP" "$KIT_LOOP"; then
  echo "check_duckcards_vectors: the reader's duck-card-loop.json is not StudioKit's, byte for byte" >&2
  echo "  copy it: cp $KIT_LOOP $LOOP" >&2
  fail=1
fi

ENV="$ROOT/cardreader/duckcards/pollen-pad-drive.json"
KIT_ENV="$ROOT/StudioKit/Sources/StudioKit/Resources/DuckCards/pollen-pad-drive.json"
if ! cmp -s "$ENV" "$KIT_ENV"; then
  echo "check_duckcards_vectors: the reader's pollen-pad-drive.json is not StudioKit's, byte for byte" >&2
  echo "  copy it: cp $KIT_ENV $ENV" >&2
  fail=1
fi

DECK="$ROOT/cardreader/duckcards/duck-cards.json"
KIT_DECK="$ROOT/StudioKit/Sources/StudioKit/Resources/DuckCards/duck-cards.json"
if ! cmp -s "$DECK" "$KIT_DECK"; then
  echo "check_duckcards_vectors: StudioKit's deck is not cardreader's deck, byte for byte" >&2
  fail=1
fi

PACKS="$ROOT/cardreader/duckcards/packs"
KIT_PACKS="$ROOT/StudioKit/Sources/StudioKit/Resources/DuckPacks"
if ! diff -rq "$KIT_PACKS" "$PACKS" >/dev/null; then
  echo "check_duckcards_vectors: the reader's packs differ from StudioKit's:" >&2
  diff -rq "$KIT_PACKS" "$PACKS" >&2 || true
  echo "  copy them: cp $KIT_PACKS/*.duckpack $PACKS/" >&2
  fail=1
fi

if command -v python3 >/dev/null; then
  python3 "$ROOT/scripts/check_duck_packs.py" || fail=1
  # No closed-loop card may command more than Pollen's pad envelope (pollen-pad-drive.json).
  if ! python3 - "$ROOT" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/cardreader")
from duckcards import cardloop
problems = cardloop.envelope_problems(cardloop.SPEC)
for p in problems:
    print(f"check_duckcards_vectors: duck-card-loop.json: {p}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY
  then
    fail=1
  fi
  python3 "$ROOT/cardreader/tests/make_cardloop_vectors.py" --check || fail=1
fi

if command -v python3 >/dev/null && python3 -c "import numpy, pupil_apriltags, cv2" 2>/dev/null; then
  (cd "$ROOT/cardreader/tests" && python3 make_vectors.py --check) || fail=1
else
  echo "check_duckcards_vectors: python3 with numpy, pupil_apriltags and opencv not here;" \
       "the copies were compared, the vectors were not regenerated"
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "check_duckcards_vectors: $(ls "$SRC"/*.json | wc -l | tr -d ' ') card and pack vectors," \
     "$(ls "$SRC"/cardloop/*.json | wc -l | tr -d ' ') card-loop vectors, the deck, the card-loop spec" \
     "and $(ls "$KIT_PACKS" | wc -l | tr -d ' ') packs agree on both sides"
