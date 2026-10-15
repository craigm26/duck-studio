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
# THIS GUARD CAN FAIL, AND IT WAS WATCHED TO: deleting one fixture vector, and
# separately changing one byte of the StudioKit deck, each made it exit 1.
# 2026-10-15, for the packs: changing one byte of the reader's copy of
# duck-maze.duckpack, deleting the reader's copy of loop-the-course.duckpack,
# and deleting the fixture copy of pack_solved.json each made it exit 1; so did
# a wrong par in get-to-the-pond, through check_duck_packs.py.
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
echo "check_duckcards_vectors: $(ls "$SRC" | wc -l | tr -d ' ') vectors, the deck and $(ls "$KIT_PACKS" | wc -l | tr -d ' ') packs agree on both sides"
