#!/usr/bin/env bash
# Is the bench that ships inside the app the bench duck-sounds actually has?
#
# THE FAILURE THIS EXISTS TO CATCH IS A GREEN BUILD OVER A STALE BENCH.
# `DuckStudio/Resources/phonebench` is vendored from duck-sounds by
# scripts/make_phone_bench.sh, which writes MANIFEST.json with a sha256 per
# file. `check_no_studio_math.sh` proves every file in the folder matches the
# manifest — and a folder that was never re-assembled has stale files AND a
# stale manifest that agree with each other perfectly. So that gate goes green
# while the bench on the phone answers the OLD shape: a /perform with a world
# comes back with no `stood` block, a /climb with `clip: true` comes back with
# no clip, and the app draws the scene it asked for over a run that never had
# it — the exact falsehood build 47 exists to delete, shipped by the one path
# no gate was watching. The same shape one repo over — "all structural gates
# green while the published installer could not install" — is why this is a
# script and not a paragraph.
#
# AND IT IS A SEPARATE SCRIPT, NOT A CLAUSE INSIDE check_no_studio_math.sh.
# That one is a math guard and a manifest-digest check; this one is a
# provenance check against another repository. One red gate must not mean two
# unrelated things, and this one can only be answered by re-running the
# assembler while that one is answered by deleting a line of Swift.
#
# WHAT IS COMPARED, AND WHY THESE THREE. They are the three files build 47
# changed and the three the app's own bench actually executes for the new
# shapes: duckbench-core.mjs (the /perform world, the spawn, the `stood` block,
# GET /lanes), climb_score.mjs (the clip sampler and stairsInEpisode) and
# stairs.js (readStairs). Every other vendored file is covered by the manifest
# check in check_no_studio_math.sh, which this does not repeat.
#
# THE SOURCES ARE duck-sounds' OWN sim/ AND site/, NOT ITS site/phonebench COPY.
# make_phone_bench.sh copies from sim/*.mjs and site/stairs.js, so those are
# what "fresh" means here. duck-sounds has a second assembler of its own
# (scripts/make_phonebench.sh) writing site/phonebench/assets; comparing
# against that would make this gate pass whenever the two assemblers agreed
# with each other and disagreed with the source.
#
# Usage:  scripts/check_phonebench_fresh.sh
#         DUCK_SOUNDS=/path/to/duck-sounds scripts/check_phonebench_fresh.sh
# Run from anywhere. Exit 0 = the three digests match.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${DUCK_SOUNDS:-$HOME/projects/duck-sounds}"
BUNDLE="$HERE/DuckStudio/Resources/phonebench/assets"

digest() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# A MISSING SOURCE TREE IS A FAILURE AND NOT A SKIP. This gate's whole job is to
# say the bundle came from somewhere; "I could not check" is the answer it must
# never give quietly. A checkout without duck-sounds cannot ship a phone bench.
if [ ! -d "$SOURCE/sim" ]; then
  echo "check_phonebench_fresh: no duck-sounds at $SOURCE" >&2
  echo "  Set DUCK_SOUNDS to where it is checked out. The vendored bench cannot" >&2
  echo "  be shown to be the bench without the tree it was vendored from." >&2
  exit 1
fi

if [ ! -d "$BUNDLE" ]; then
  echo "check_phonebench_fresh: no phone bench assembled ($BUNDLE)." >&2
  echo "  Run scripts/make_phone_bench.sh." >&2
  exit 1
fi

# "shipped-file-name  source-path-relative-to-duck-sounds"
PAIRS=(
  "duckbench-core.mjs  sim/duckbench-core.mjs"
  "climb_score.mjs     sim/climb_score.mjs"
  "stairs.js           site/stairs.js"
)

status=0
checked=0
for pair in "${PAIRS[@]}"; do
  # shellcheck disable=SC2086
  set -- $pair
  shipped="$BUNDLE/$1"
  origin="$SOURCE/$2"

  if [ ! -f "$origin" ]; then
    echo "MISSING SOURCE: $2 is not in $SOURCE."
    status=1
    continue
  fi
  if [ ! -f "$shipped" ]; then
    echo "MISSING FROM THE BUNDLE: assets/$1 is not there."
    echo "  Re-run scripts/make_phone_bench.sh."
    status=1
    continue
  fi

  want=$(digest "$origin")
  got=$(digest "$shipped")
  checked=$((checked + 1))
  if [ "$want" != "$got" ]; then
    echo "STALE: DuckStudio/Resources/phonebench/assets/$1"
    echo "  duck-sounds $2"
    echo "    $want"
    echo "  shipped in the app"
    echo "    $got"
    status=1
  else
    echo "  ok  assets/$1  $want"
  fi
done

# THE COUNT IS PRINTED SO A PASS CANNOT BE A PASS OVER NOTHING. A loop that
# compared no pairs would otherwise print the same clean line as one that
# compared three — the vacuous-gate failure this project has already shipped
# once (world_parity phase 1's `undefined` rise axis).
if [ $status -eq 0 ]; then
  if [ $checked -ne 3 ]; then
    echo "check_phonebench_fresh: compared $checked of 3 files — that is not a pass."
    exit 1
  fi
  echo "check_phonebench_fresh: 3 of 3 digests match $SOURCE."
else
  echo
  echo "The app would ship a bench older than the one duck-sounds has. Fix it by"
  echo "re-running the assembler, never by editing anything under"
  echo "DuckStudio/Resources/phonebench:"
  echo "    scripts/make_phone_bench.sh"
fi
exit $status
