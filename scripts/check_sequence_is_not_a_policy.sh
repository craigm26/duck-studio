#!/bin/bash
# A SEQUENCE IS NOT A POLICY, AND THE WORD MUST NOT DRIFT.
#
# Three things in this app are easy to confuse and are not the same:
#
#   policy    a trained network on a bench. Nothing in build 47's pad-map track
#             trains, edits or records one.
#   motion    a keyframe track somebody authored joint by joint. It travels as
#             `.duckintent`, and `IntentExport` chose that extension
#             specifically so a motion and a network could not be confused.
#   sequence  a recording of what YOU drove — the stick commands, stamped on the
#             bench's own sim clock, plus the networks the bench reported while
#             you drove. A macro, not a skill.
#
# THIS CHECKS THE SENTENCES, NOT THE IDENTIFIERS. What a person reads is the
# thing that can mislead them; `policySaid` and `benchPolicy` are variable names
# nobody outside this repo will ever see, and a guard that flagged them would be
# a guard people learn to switch off. So the pass extracts every double-quoted
# string literal from the five kit files this track owns and runs the anchored
# pattern over those.
#
# The anchor is `(^|[^A-Za-z])polic(y|ies)`, which is the completeness-grep
# lesson applied: an unanchored `polic` also matches `policySaid` inside a
# sentence and `apolictic` outside one.
#
# EVERY HIT MUST CARRY ONE OF FOUR PHRASES, each genuinely about a trained
# network. The list is short on purpose: if it grows, the word is drifting.
#
# IT SHIPS ALONGSIDE THE IN-KIT TEST, NOT INSTEAD OF IT.
# `testTheWordPolicyIsOnlyEverUsedAboutATrainedNetwork` scans the sentences a
# collection knows about; this scans the FILES, so a sentence added to a type
# the collection forgot is still caught.
#
# AND IT PROVES IT CAN FAIL. A guard that cannot go red ships green for ever —
# written down twice in this project already — so the first thing it does is run
# itself over a deliberately bad fixture and fail loudly if that fixture passes.
#
# Usage:  scripts/check_sequence_is_not_a_policy.sh
# Run from anywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$ROOT/StudioKit/Sources/StudioKit"

FILES=(
  "$KIT/DuckPadMap.swift"
  "$KIT/DuckSequence.swift"
  "$KIT/PadPilot.swift"
  "$KIT/DuckTalk.swift"
  "$KIT/SequenceProposal.swift"
)

# The four sentences in this track that are genuinely about a trained network.
#   1. DuckSequence.whatThisIs           — the one place the three words are told apart
#   2. DuckSequence.benchRefusal         — POST /record takes ONE policy
#   3. SequenceProposal.grounding()      — the standing policy under the dead zone
#   4. DuckTalk.degreesAssumption        — the network decides the angle, not this app
ALLOWED=(
  'A policy is a trained network'
  'recording names one policy'
  'the standing policy takes over'
  "is the policy's business"
)

ANCHOR='(^|[^A-Za-z])polic(y|ies)'
# Every double-quoted Swift string literal on a line, escapes included, so the
# JSON sample in `DuckTalk.instructions` does not end the match early.
LITERAL='"([^"\\]|\\.)*"'

# `scan FILE` prints every offending literal in it, one per line.
#
# COMMENTS ARE STRIPPED FIRST. A comment may quote the word freely — this
# script's own preamble does, and so does the note in `DuckSequence.whatThisIs`
# explaining why its line breaks matter — and a guard that flagged those is a
# guard people learn to switch off. `sed` drops everything from `//` to the end
# of the line, which also takes any `//` inside a literal with it; no sentence in
# these five files contains one, and a URL in a refusal would be worth noticing
# anyway.
scan() {
  local file="$1"
  set +e
  sed 's|//.*||' "$file" | grep -ohE "$LITERAL" 2>/dev/null \
    | grep -E "$ANCHOR" \
    | while IFS= read -r literal; do
        ok=0
        for phrase in "${ALLOWED[@]}"; do
          case "$literal" in
            *"$phrase"*) ok=1; break ;;
          esac
        done
        [ $ok -eq 0 ] && printf '%s\n' "$literal"
      done
  set -e
}

# ── the self-test ────────────────────────────────────────────────────────────
FIXTURE="$(mktemp)"
CLEAN="$(mktemp)"
trap 'rm -f "$FIXTURE" "$CLEAN"' EXIT

cat > "$FIXTURE" <<'FIX'
    public static let bad =
        "This policy plays back what you drove, at the same points on the clock."
FIX

cat > "$CLEAN" <<'OK'
    // A comment may quote "policy" freely; comments are not sentences a
    // person reads on the glass.
    public let policySaid: String?
    public var benchPolicy: String? { policiesNamed.first }
    public static let fine =
        "A policy is a trained network and nothing here trains one."
    public static let sample =
        "{\"name\":\"Forward then left\",\"moves\":[{\"go\":\"forward\"}]}"
OK

if [ -z "$(scan "$FIXTURE")" ]; then
  echo "BROKEN CHECK: the bad fixture was not flagged."
  echo "  A guard that cannot fail passes for ever. Fix the pattern."
  exit 2
fi
if [ -n "$(scan "$CLEAN")" ]; then
  echo "BROKEN CHECK: the clean fixture was flagged —"
  scan "$CLEAN"
  echo "  Identifiers and comments are out of scope; only shipped sentences count."
  exit 2
fi
echo "check_sequence_is_not_a_policy: self-test passed — the bad fixture is caught,"
echo "  identifiers and comments are not."

# ── the real pass ────────────────────────────────────────────────────────────
status=0
checked=0
for file in "${FILES[@]}"; do
  if [ ! -f "$file" ]; then
    echo "check_sequence_is_not_a_policy: $file is not there yet — skipping."
    continue
  fi
  checked=$((checked + 1))
  offenders="$(scan "$file")"
  if [ -n "$offenders" ]; then
    echo "FORBIDDEN: \"policy\" used about something that is not a trained network,"
    echo "  in $(basename "$file"):"
    printf '%s\n' "$offenders" | sed 's/^/    /'
    status=1
  fi
done

# THE COUNT IS PRINTED SO A PASS CANNOT BE A PASS OVER NOTHING. A loop that
# found no files would otherwise report the same clean line as a full run.
if [ $status -eq 0 ]; then
  echo "check_sequence_is_not_a_policy: clean — $checked files scanned, and every"
  echo "  \"policy\" in them is about a trained network."
else
  echo
  echo "A sequence is a recording of what you drove; a motion is authored"
  echo "keyframes; a policy is a trained network. See DuckSequence.whatThisIs."
fi
exit $status
