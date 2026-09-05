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
# WHAT IT COVERS. `Text("…")`, which subsumes `accessibilityLabel(Text("…"))`,
# `accessibilityHint(Text("…"))` and `accessibilityValue(Text("…"))`; then
# `Label("…", systemImage:)`, `SectionHeading(text: "…")`, `Button("…")`,
# `Toggle("…", isOn:)`, `SecureField("…")`, `TextField("…")` and
# `Picker("…", selection:)`; and a ternary inside any of them,
# `Text(cond ? "…" : "…")`, including the shape where the second branch is on
# the next line. Both literals of a ternary are reported, each at its own line.
#
# THE FIVE CALL SHAPES AFTER THE FIRST THREE WERE ADDED IN BUILD 58, and the
# allow-list grew by what they found. This header already said that leaving a
# shape out would make the guard trivially avoidable, because a new sentence
# would simply be typed into the shape the grep cannot see. That is exactly what
# had happened: an evaluation publish form shipped `Button("Check this token")`,
# `Toggle("Private repository")`, `SecureField("hf_")` and
# `Text(isPrivate ? "Commit to a private dataset" : "Commit to a public
# dataset")` under a green gate, in a file whose own header says it draws no
# word of its own. Those five are kit constants now, and these shapes are why
# the next four cannot be.
#
# WHAT IT DELIBERATELY DOES NOT COVER. `LocalizedStringKey` properties (the
# legend's `followWord` is one), string interpolation assembled elsewhere (an
# error's `"\(name) is already here. "` is one), a literal handed to a helper
# that draws it, and every file outside the ones listed below. Those are named
# in the build log as the next bites, not silently implied to be clean.
#
# THIS GUARD CAN FAIL, AND THAT WAS PROVEN RATHER THAN ASSUMED. Build 47: a
# scratch `Text("a literal nobody tested")` added to DuckStage.swift made it
# exit 1. Build 58, once for each shape the widening added: a scratch
# `Button("a button nobody tested")` in EvalListView.swift and a scratch
# `Text(showRun ? "planted one" : "planted two")` split across two lines in
# EvalSetupView.swift made it exit 1 together, naming EvalListView.swift:71,
# EvalSetupView.swift:96 and EvalSetupView.swift:97 and quoting all three
# literals; removing them made it clean again. See the build log.
#
# Usage:  scripts/check_stage_sentences.sh
#         scripts/check_stage_sentences.sh --list   print every literal it sees
# Run from anywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/DuckStudio/Sources"
ALLOW="$ROOT/scripts/stage_sentences_allowlist.txt"

# The call shapes that put a string in front of a person. Written once because
# the ternary scan below has to look for the same openers the grep does, and two
# lists would be one list somebody updated.
OPENERS='(Text\(|Label\(|SectionHeading\(text: |Button\(|Toggle\(|SecureField\(|TextField\(|Picker\()'

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
  # Build 58's weight search. Added with the files rather than after a review
  # found them missing, which is the whole lesson of the widening above.
  WeightSearchView.swift
  WeightSearchRun.swift
  # The tuner's screen was missing from this list while the move search's was
  # in it — so the rule that every sentence is a tested kit string silently
  # stopped applying to the one screen that judges a policy.
  TuneView.swift
  # The evaluation shelf, its setup, its runner's screen, its detail view and
  # its comparison, added with the files. Nothing joins
  # stage_sentences_allowlist.txt with them: six screens entering the guard
  # with an empty contribution is the strong form of the rule, so the first
  # literal anybody types into one of them is a red gate rather than a habit.
  # That was true of three call shapes and false of five until build 58, when
  # the pattern below grew to read every shape these six files actually use.
  # Their contribution is still nothing, and it is now nothing under a grep
  # that can see a Button, a Toggle, a SecureField and a ternary.
  EvalListView.swift
  EvalSetupView.swift
  EvalRunView.swift
  EvalLogDetailView.swift
  EvalCompareView.swift
  EvalStore.swift
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
  # would kill the script on the first clean file, a guard passing by dying.
  #
  # THE OPTIONAL `cond ? ` BEFORE THE QUOTE AND THE OPTIONAL `: "..."` AFTER IT
  # are the ternary, which is the one shape the old header named as the way
  # round the guard and the one the publish form used. Both branches come back
  # in a single match and both are extracted below.
  set +e
  found=$(grep -noE "$OPENERS"'([^"]*\? )?"([^"\\]|\\.)*"( *: *"([^"\\]|\\.)*")?' "$file" 2>&1)
  rc=$?
  set -e
  if [ $rc -gt 1 ]; then
    echo "BROKEN PATTERN in $name: $found"
    exit 2
  fi

  # A TERNARY WHOSE SECOND BRANCH IS ON THE NEXT LINE is how the publish form
  # was written, so a one-line window is not enough. `awk` carries the flag
  # forward exactly one line, which keeps the reported line number the branch's
  # own rather than the whole file's after a join.
  set +e
  dangling=$(awk -v openers="$OPENERS" '
    $0 ~ openers "[^\"]*\\?[[:space:]]*\"" { pending = 1; next }
    pending && /^[[:space:]]*:[[:space:]]*"/ { print NR ":" $0; pending = 0; next }
    { pending = 0 }
  ' "$file")
  rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    echo "BROKEN TERNARY SCAN in $name: $dangling"
    exit 2
  fi

  hits=$(printf '%s\n%s\n' "$found" "$dangling" | grep -v '^$' || true)
  [ -z "$hits" ] && continue

  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    line="${hit%%:*}"
    rest="${hit#*:}"
    # EVERY LITERAL IN THE MATCH AND NOT THE FIRST. A ternary carries two, and
    # taking everything between the outer quotes would report one "literal"
    # with a quote in the middle of it, which no allow-list line can ever be.
    while IFS= read -r quoted; do
      [ -z "$quoted" ] && continue
      literal="${quoted#\"}"
      literal="${literal%\"}"
      # AN EMPTY STRING IS NOT A SENTENCE. `Text(can ? "" : why)` and
      # `Text(failure ?? "")` are the two shapes that produce one here, and an
      # allow-list line with nothing after the pipe would be a line nobody could
      # read. Nothing can hide in a literal with no characters in it.
      [ -z "$literal" ] && continue
      seen=$((seen + 1))
      if [ $listing -eq 1 ]; then
        printf '%s\t%s\n' "$name" "$literal"
        continue
      fi
      # MATCHED AS A FIXED WHOLE LINE. `grep -F -x` and not a pattern, because a
      # sentence is full of regex metacharacters, a full stop matches anything,
      # and `-x` is what stops a short allowed literal from satisfying a longer
      # new one that merely contains it.
      if grep -qxF "$name|$literal" "$ALLOW"; then
        allowed=$((allowed + 1))
        continue
      fi
      echo "FORBIDDEN: $name:$line draws a literal nothing tests:"
      echo "    \"$literal\""
      status=1
    done < <(printf '%s\n' "$rest" | grep -oE '"([^"\\]|\\.)*"' || true)
  done < <(printf '%s\n' "$hits")
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
