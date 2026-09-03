#!/bin/bash
# The rule, for the words on a stage: every user-visible sentence is a tested
# kit string.
#
# NOTHING IN THIS REPO GREPPED FOR `Text("` BEFORE THIS. The rule was real and
# widely followed — `Text(DriveVenue.robotIsNotDrivenYet)`,
# `Text(JointHandles.homeActionSaid)`, `Text(StageCamera.nearestSaid)` — and it
# was followed by hand, which means it held exactly as long as everybody
# remembered. A sentence typed into a view is a sentence `swift test` cannot
# read: it can say the wrong thing, contradict a kit string two files away, or
# quietly go on claiming something the code stopped doing, and nothing fails.
#
# IT SHIPS HOLDING THE DEBT RATHER THAN PRETENDING THERE IS NONE. The allow-list
# names every literal already in these five files. That is the point: the count
# is printed on every run, the list only shrinks, and a NEW literal fails on the
# first run after somebody types it.
#
# WHAT IT COVERS. `Text("…")` — which subsumes `accessibilityLabel(Text("…"))`,
# `accessibilityHint(Text("…"))` and `accessibilityValue(Text("…"))` —
# `Label("…", systemImage:)`, and `SectionHeading(text: "…")`. The last two are
# beyond what the plan asked for and are here because a label on a button and a
# heading over a list are user-visible sentences by any reading of the rule, and
# leaving either out would have made the guard trivially avoidable — a new
# sentence would simply be typed into the shape the grep cannot see.
#
# WHAT IT DELIBERATELY DOES NOT COVER. `LocalizedStringKey` properties (the
# legend's `followWord` is one), string interpolation assembled elsewhere, and
# every file outside the five this track owns. Those are named in the build log
# as the next bites, not silently implied to be clean.
#
# THIS GUARD CAN FAIL, AND THAT WAS PROVEN RATHER THAN ASSUMED: a scratch
# `Text("a literal nobody tested")` added to DuckStage.swift made it exit 1. See
# the build log for the run.
#
# Usage:  scripts/check_stage_sentences.sh
#         scripts/check_stage_sentences.sh --list   print every literal it sees
# Run from anywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/DuckStudio/Sources"
ALLOW="$ROOT/scripts/stage_sentences_allowlist.txt"

# The five files the viewport track owns. Scoped on purpose: a guard that fired
# on all sixty screens at once would have to ship with an allow-list nobody
# could read, and an allow-list nobody reads is a list nobody shrinks.
FILES=(
  DuckStage.swift
  DriveView.swift
  IntentAuthorView.swift
  ARDriveStage.swift
  JointHandleOverlay.swift
  # Build 47's fourteen new app files. Widened by the lead after review: the
  # build added seventy literals in them while this guard went on printing
  # fifty-five, which is the exact blindness the guard exists to end.
  MoveSearchRun.swift
  MoveSearchView.swift
  PadBindSheet.swift
  PadChrome.swift
  PadDesk.swift
  PadMapSection.swift
  PadMapStore.swift
  PadSheet.swift
  PolicyRenameSheet.swift
  SearchSpecStore.swift
  SequenceKeepSheet.swift
  SequenceListView.swift
  SequenceStore.swift
  TalkToTheDuckView.swift
  ControlShelfChips.swift
)

if [ ! -d "$SRC" ]; then
  echo "check_stage_sentences: no app sources yet ($SRC) — nothing to check."
  exit 0
fi
if [ ! -f "$ALLOW" ]; then
  echo "check_stage_sentences: no allow-list at $ALLOW."
  exit 2
fi

listing=0
[ "${1:-}" = "--list" ] && listing=1

status=0
allowed=0
seen=0

for name in "${FILES[@]}"; do
  file="$SRC/$name"
  if [ ! -f "$file" ]; then
    # A file this track owns that is not there is a fact worth failing on: the
    # guard would otherwise report a clean sweep over four files and a hole.
    echo "check_stage_sentences: $name is missing from $SRC."
    exit 2
  fi

  # `set +e` around the grep for the reason `check_no_studio_math` documents at
  # length: exit 1 is "no matches" and is the SUCCESS case here, and errexit
  # would kill the script on the first clean file — a guard passing by dying.
  set +e
  found=$(grep -noE '(Text\(|Label\(|SectionHeading\(text: )"([^"\\]|\\.)*"' "$file" 2>&1)
  rc=$?
  set -e
  if [ $rc -gt 1 ]; then
    echo "BROKEN PATTERN in $name: $found"
    exit 2
  fi
  [ -z "$found" ] && continue

  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    line="${hit%%:*}"
    rest="${hit#*:}"
    # Strip the opener up to the first quote, and the closing quote.
    literal="${rest#*\"}"
    literal="${literal%\"}"
    seen=$((seen + 1))
    if [ $listing -eq 1 ]; then
      printf '%s\t%s\n' "$name" "$literal"
      continue
    fi
    # MATCHED AS A FIXED WHOLE LINE. `grep -F -x` and not a pattern, because a
    # sentence is full of regex metacharacters — a full stop matches anything —
    # and `-x` is what stops a short allowed literal from satisfying a longer
    # new one that merely contains it.
    if grep -qxF "$name|$literal" "$ALLOW"; then
      allowed=$((allowed + 1))
      continue
    fi
    echo "FORBIDDEN: $name:$line draws a literal nothing tests —"
    echo "    \"$literal\""
    status=1
  done < <(printf '%s\n' "$found")
done

[ $listing -eq 1 ] && exit 0

if [ $status -eq 0 ]; then
  echo "check_stage_sentences: clean — $seen literal(s) across ${#FILES[@]} files,"
  echo "  all $allowed of them in $ALLOW."
  echo "  Every one of those is a sentence NO TEST READS. The list only shrinks:"
  echo "  move a line into StudioKit with a test and delete its entry here."
else
  echo
  echo "Put the sentence in StudioKit beside a test that reads it letter by"
  echo "letter, and draw it as Text(SomeKitType.someSaid). If it genuinely"
  echo "cannot move — it interpolates state this screen owns — add it to"
  echo "$ALLOW with a reason, and expect to be asked why."
fi
exit $status
