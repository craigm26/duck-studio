#!/bin/bash
# THE WORD THIS APP DOES NOT SAY. The loop is edit, score, keep.
#
# "RLHF" names a training method with a gradient in it. Nothing in this app
# computes a gradient, learns a weight, or trains anything: the tuner searches
# twenty-eight numbers and folds the best of them into somebody else's network;
# the keyframe search changes poses and times and keeps whichever version the
# bench scored highest. Calling either one RLHF — or calling the objective a
# reward model — would be the app claiming a capability it does not have, in the
# one place a person is most likely to believe it.
#
# THIS GENERALISES A SINGLE HAND-WRITTEN ASSERTION. `StairsChallengeTests:272`
# checked one sentence for one word. A grep over every string literal in both
# shipping trees checks all of them, including the ones nobody has written yet.
#
# WHAT IT COUNTS. A line that contains a double-quoted string and one of the
# forbidden phrases inside it, under DuckStudio/Sources or StudioKit/Sources.
#
# WHAT IT DELIBERATELY DOES NOT COUNT:
#
#   1. `///` doc comments. `PreferenceSearch.swift:10` and
#      `PreferenceSearchView.swift:7` legitimately NAME the field the technique
#      comes from, to a reader of the code, and a rule that could not tell a
#      doc comment from a sentence on a screen would delete the explanation and
#      keep nothing.
#   2. A DENIAL of "reward model". `MoveSearch.notTraining` opens "This is not
#      training and it is not a reward model", and two sentences this app has
#      shipped since build 44 — `StairsChallenge.editedVersionNote` and
#      `BallChallenge.editedVersionNote` — say "There is no reward model in this
#      loop — you are the judge, and the bench is the measurement." Those are
#      the sentences the rule exists to protect, not the ones it exists to
#      catch. A ban that could not tell a denial from a claim would delete the
#      correction and leave the confusion, so "reward model" is allowed only on
#      a line that also carries "no reward model" or "not a reward model".
#      "RLHF" has no such exemption: there is no sentence in this app that needs
#      the acronym, and the plain-words correction is always available.
#   3. Test files. A test asserting that a sentence does NOT contain the word has
#      to contain the word.
#
# PROVEN ABLE TO FAIL, not assumed: run against a scratch file carrying the word
# before it was wired in, it reported the hit and exited 1. Re-prove it the same
# way after any change here.
#
# Usage:  scripts/check_no_rlhf_in_copy.sh
# Run from anywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

status=0
scanned=0
for tree in "$ROOT/DuckStudio/Sources" "$ROOT/StudioKit/Sources"; do
  if [ ! -d "$tree" ]; then
    echo "check_no_rlhf_in_copy: no sources at $tree — nothing to check."
    continue
  fi

  while IFS= read -r file; do
    scanned=$((scanned + 1))
    # errexit OFF around grep: exit 1 is "no matches", which is the success
    # case here, and `set -e` would kill the script on the first clean file —
    # the guard would then pass by dying quietly. Exit 2 means grep could not
    # run the pattern and must still be loud.
    set +e
    hits=$(grep -nE '"[^"]*([Rr][Ll][Hh][Ff]|[Rr]eward model)[^"]*"' "$file" 2>&1)
    rc=$?
    set -e
    if [ $rc -gt 1 ]; then
      echo "BROKEN PATTERN in '$file': $hits"
      exit 2
    fi
    [ -z "$hits" ] && continue

    # Drop the two exemptions, line by line.
    kept=$(printf '%s\n' "$hits" \
      | grep -v '^[0-9]*: *///' \
      | grep -vE '(no|not a) reward model' \
      || true)
    if [ -n "$kept" ]; then
      echo "FORBIDDEN: product copy in ${file#$ROOT/} says a word this app does not say."
      printf '%s\n' "$kept"
      echo "  The loop is edit, score, keep. Say that instead."
      status=1
    fi
  done < <(find "$tree" -name '*.swift' -type f | sort)
done

if [ $status -eq 0 ]; then
  echo "check_no_rlhf_in_copy: clean — $scanned files, no shipped string says RLHF"
  echo "  and no string claims a reward model."
fi
exit $status
