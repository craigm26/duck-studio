#!/bin/bash
# THE GATE IS GONE BY DELETION, AND THIS IS WHAT KEEPS IT GONE.
#
# Before build 47 the Control tab refused to drive until somebody picked a
# policy out of a list, because `/health` says what a bench HOLDS and never says
# what it has LOADED. That refusal was honest and it was the wrong shape: a
# bench always has something on the servos, `DuckDrive.Live.policy` names it on
# every single reply, and nothing in either target read it. So the gate was
# deleted rather than replaced with a better guess — `@State private var chosen`
# went, `"no policy loaded"` went, and the footnote telling somebody to pick a
# policy went with them.
#
# A DELETION HAS NO TEST UNLESS SOMEBODY WRITES ONE. Anything can put those
# three back: a merge, a revert, somebody restoring a picker because a bench
# looked odd. This greps `DriveView.swift` for all three, anchored so `chosen`
# does not also match `chosenName` or `unchosen`.
#
# IT PROVES IT CAN FAIL BEFORE IT PASSES. A guard that cannot fail ships green
# for ever — this project has written that lesson down twice, once as a grep
# that matched a substring and once as a check that could never go red. So the
# first thing this does is run its own patterns over a fixture holding the
# deleted lines, and fail LOUDLY if any of them fails to hit.
#
# Usage:  scripts/check_no_policy_gate.sh
# Run from anywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/DuckStudio/Sources/DriveView.swift"

# Each pattern is one of the three things the gate was made of.
#   the state that held the pick, anchored so `chosenName` is not a hit
#   the readout that admitted the app could not name what was driving
#   the footnote that told somebody Drive was waiting for them
PATTERNS=(
  '(^|[^A-Za-z])chosen([^A-Za-z]|$)'
  'no policy loaded'
  'Pick a policy to drive with'
)

# ── the self-test ────────────────────────────────────────────────────────────
#
# The fixture is written here rather than kept in the tree, so it cannot drift
# from the patterns and cannot be edited to make the guard pass.
FIXTURE="$(mktemp)"
trap 'rm -f "$FIXTURE"' EXIT
cat > "$FIXTURE" <<'FIX'
    @State private var chosen = ""
    private var policyLine: String {
        guard !chosen.isEmpty else { return "no policy loaded" }
        return "policy \(chosen)"
    }
    Text("Pick a policy to drive with. The bench does not say which one it has loaded, so nothing is chosen for you.")
    // NOT A HIT: chosenName, unchosen, theChosenOne
FIX

for pattern in "${PATTERNS[@]}"; do
  set +e
  grep -qE "$pattern" "$FIXTURE"
  rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    echo "BROKEN CHECK: '$pattern' does not match the fixture it was written for."
    echo "  A guard that cannot fail is a guard that passes for ever. Fix the pattern."
    exit 2
  fi
done

# And the anchoring is proved in the other direction too: a word that merely
# CONTAINS `chosen` must not be a hit, or the guard would fail on innocent code
# and get switched off.
INNOCENT="$(mktemp)"
trap 'rm -f "$FIXTURE" "$INNOCENT"' EXIT
printf '    let chosenName = "x"\n    let unchosen = 0\n' > "$INNOCENT"
set +e
grep -qE '(^|[^A-Za-z])chosen([^A-Za-z]|$)' "$INNOCENT"
rc=$?
set -e
if [ $rc -eq 0 ]; then
  echo "BROKEN CHECK: the anchor matches 'chosenName' or 'unchosen'."
  exit 2
fi

echo "check_no_policy_gate: self-test passed — all three patterns hit the fixture,"
echo "  and the anchor rejects chosenName/unchosen."

# ── the real pass ────────────────────────────────────────────────────────────
if [ ! -f "$TARGET" ]; then
  echo "check_no_policy_gate: no $TARGET — nothing to check."
  exit 0
fi

# COMMENTS ARE STRIPPED FOR THE `chosen` PASS AND ONLY FOR IT. "chosen" is an
# ordinary English past participle and `DriveView` uses it as one — "two radii
# chosen independently", "a width chosen so the duck is never behind the panel".
# Flagging prose would make this gate unpassable and it would be switched off.
# The other two patterns are whole sentences that only ever appear inside a
# string literal, so they are grepped raw.
STRIPPED="$(mktemp)"
trap 'rm -f "$FIXTURE" "$INNOCENT" "$STRIPPED"' EXIT
sed 's|//.*||' "$TARGET" | grep -n '' > "$STRIPPED"

status=0
for pattern in "${PATTERNS[@]}"; do
  set +e
  if [ "$pattern" = '(^|[^A-Za-z])chosen([^A-Za-z]|$)' ]; then
    hits=$(grep -E "$pattern" "$STRIPPED")
  else
    hits=$(grep -nE "$pattern" "$TARGET")
  fi
  rc=$?
  set -e
  if [ $rc -gt 1 ]; then
    echo "BROKEN PATTERN '$pattern': grep exited $rc"
    exit 2
  fi
  if [ -n "$hits" ]; then
    echo "FORBIDDEN: the policy gate is back in DriveView.swift — '$pattern'"
    echo "$hits"
    status=1
  fi
done

if [ $status -eq 0 ]; then
  echo "check_no_policy_gate: clean — DriveView drives without asking for a policy first."
else
  echo
  echo "The sticks are mapped by DuckPadMap and what is DRIVING is read off"
  echo "DuckDrive.Live.policy. See DuckPadMap.sticksAreAlwaysMapped and"
  echo "DuckPadMap.drivingLine(mapped:benchSaid:)."
fi
exit $status
