#!/bin/bash
# The rule, for the camera: StudioKit decides where the camera stands, DuckStudio
# points it.
#
# WHY `check_no_studio_math.sh` COULD NOT DO THIS. Its nine patterns — homePose,
# actionScale, lowpass, lowPass, jointRanges, mean[, std[, exp(, \b61\b — are
# about the POLICY: the observation layout, the normaliser, the ELU. Not one of
# them can see a field of view, a zoom clamp, a viewport height or a sentence. So
# the whole of the camera arithmetic sat in the app target, invisible to the one
# guard that exists to keep arithmetic out of it, and it drifted exactly the way
# that guard's preamble predicts: `OrbitState.zoom` clamped 0.20…4.0 while
# `frame(_:)` wrote the distance straight through, and 300 was written five
# times in five files as "how tall a stage is".
#
# THE PATTERNS ARE ANCHORED, and that is not decoration. `grep "Theme."` in this
# project once matched `SoccerTheme.` and reported a clean sweep over a check
# that could not fail; every pattern below either starts at a boundary or is
# wrapped so a longer identifier cannot satisfy it.
#
# THIS GUARD CAN FAIL, AND IT WAS WATCHED TO. Reinstating
# `distance = min(max(distance / scale, 0.20), 4.0)` in `OrbitState.zoom` makes
# it exit non-zero; see the build log for the run.
#
# Usage:  scripts/check_no_camera_math.sh
# Run from anywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/DuckStudio"
ALLOW="$ROOT/scripts/camera_math_allowlist.txt"

if [ ! -d "$APP" ]; then
  echo "check_no_camera_math: no app target yet ($APP) — nothing to check."
  exit 0
fi

# Each entry is TAG|PATTERN|WHAT IT MEANS.
#
#   fov         — the field of view is the stage's own and is never written at
#                 runtime. `DuckScene.authoringFieldOfView` is what the framing
#                 is solved against; a second angle in a second file is a camera
#                 that frames a scene it is not looking through.
#   nearstop    — the zoom clamp. `StageCamera.clamped/zoomed` own it, and they
#                 own it because it became a visible button.
#   notch       — one press of that button. `StageCamera.zoomNotch`, which is
#                 also the pinch's notch and the rotor's, so the three inputs
#                 cannot disagree about how far a press goes.
#   stageheight — how tall a stage is. `StageViewport.standardHeight`.
#   glassmaths  — the visible-height-at-a-distance formula. It belongs to
#                 `StageViewport.Glass`, where `swift test` runs it against every
#                 viewport this app draws.
PATTERNS=(
  'fov|(^|[^A-Za-z])fieldOfViewInDegrees'
  'nearstop|min\(max\(.*0\.20'
  'notch|(^|[^0-9.])1\.25([^0-9]|$)'
  'stageheight|(viewportHeight|stageHeight)[^=]*=[^=]*(^|[^0-9.])(300|320|340)([^0-9]|$)'
  'glassmaths|2 \* .*tan\('
)

# The one file allowed to set the field of view is the one that builds the
# camera. Everything else about the camera is the kit's.
FOV_HOME="DuckStage.swift"

if [ ! -f "$ALLOW" ]; then
  echo "check_no_camera_math: no allow-list at $ALLOW."
  echo "  The list of screens that have NOT adopted the kit yet is part of the"
  echo "  guard; without it a pass says nothing about how much debt is left."
  exit 2
fi

status=0
grandfathered=0

for entry in "${PATTERNS[@]}"; do
  tag="${entry%%|*}"
  pattern="${entry#*|}"
  # `|| true` on the pipeline would swallow a BROKEN PATTERN as a pass, which is
  # exactly how `exp(` once let `check_no_studio_math` report a clean app target
  # for a pattern grep could not run. Exit 1 is "no matches" and is the success
  # case; exit 2 means grep could not run the pattern and must be loud. errexit
  # comes off around it for the same reason it does there: `set -e` would kill
  # the script on the first clean pattern and the guard would pass by dying.
  set +e
  hits=$(grep -rnE "$pattern" "$APP" --include='*.swift' 2>&1)
  rc=$?
  set -e
  if [ $rc -gt 1 ]; then
    echo "BROKEN PATTERN '$tag': $hits"
    exit 2
  fi
  [ -z "$hits" ] && continue

  # Previews invent numbers for nobody, and a line that is genuinely
  # presentational says so out loud.
  hits=$(printf '%s' "$hits" | grep -v '_Preview' | grep -v '// camera-ok:' || true)
  [ -z "$hits" ] && continue

  # A COMMENT IS NOT CODE, AND THIS GUARD IS ABOUT WHAT THE APP COMPUTES.
  # Dropped because the alternative is worse than the risk: `1.25` is a real
  # number in English — the transport's "Right now — 1.25 s" in a doc comment two
  # files away tripped this pattern on its first run — and a guard that fires on
  # prose is a guard people learn to route around with an allow-list entry, which
  # would then also cover the code in that file. Every pattern here has an
  # identifier or an expression in it, so a genuine violation is a line of code.
  hits=$(printf '%s' "$hits" | grep -vE ':[0-9]+:[[:space:]]*(///|//|\*|/\*)' || true)
  [ -z "$hits" ] && continue

  # The file that owns the camera is allowed to say what its field of view is.
  if [ "$tag" = "fov" ]; then
    hits=$(printf '%s' "$hits" | grep -v "/$FOV_HOME:" || true)
    [ -z "$hits" ] && continue
  fi

  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    file="${hit%%:*}"
    base="$(basename "$file")"
    # ALLOWED PER FILE AND PER TAG, never per line. Four owners are editing this
    # tree at once and a line number is stale the moment one of them saves.
    if grep -qxF "$base::$tag" "$ALLOW"; then
      grandfathered=$((grandfathered + 1))
      continue
    fi
    echo "FORBIDDEN [$tag]: $hit"
    echo "  This is the camera's arithmetic and it belongs in StudioKit —"
    echo "  StageCamera, StageViewport or DuckScene.authoringFraming."
    status=1
  done < <(printf '%s\n' "$hits")
done

# THE COUNT IS PRINTED SO A PASS CANNOT BE A PASS OVER NOTHING, and so the debt
# that is deliberately still here is visible rather than silently tolerated.
if [ $status -eq 0 ]; then
  echo "check_no_camera_math: clean — the app target points the camera and does"
  echo "  not decide where it stands."
  if [ $grandfathered -gt 0 ]; then
    echo "  $grandfathered site(s) are grandfathered in $ALLOW."
    echo "  Those screens have not adopted StageViewport/StageCamera yet. Adding"
    echo "  a NEW one fails; the list only shrinks."
  fi
else
  echo
  echo "If a line is genuinely presentational, append '// camera-ok:' and say why."
  echo "If a whole screen has not adopted the kit yet, that is an allow-list"
  echo "entry with a reason beside it — not a comment on the line."
fi
exit $status
