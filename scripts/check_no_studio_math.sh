#!/bin/bash
# The rule: StudioKit computes, DuckStudio displays.
#
# This greps the shipping SwiftUI sources for tokens that could only appear if
# somebody recomputed something the kit already knows. It exists because the
# failure it prevents is silent: the moment two places know the observation
# layout, or the action scale, or which joints the low-pass treats as head
# joints, they disagree — and the disagreement shows up as a plot that is subtly
# wrong rather than as a crash. A wrong number in a debugger is worse than no
# debugger, because it is believed.
#
# Same guard shape as OpenCastor's check_no_policy_reimpl.sh, for the same
# reason. Run from anywhere; wired into the Mac build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/DuckStudio"

if [ ! -d "$APP" ]; then
  echo "check_no_studio_math: no app target yet ($APP) — nothing to check."
  exit 0
fi

# Each pattern is a thing only the kit is allowed to know.
#   homePose/actionScale/lowpass/jointRanges — robot constants, DuckKit's
#   mean[/std[/exp(                          — the normalizer and ELU, redone
#   \b61\b / \b197 774\b                     — the observation width as a literal
PATTERNS=(
  'homePose'
  'actionScale'
  'lowpass'
  'lowPass'
  'jointRanges'
  'mean\['
  'std\['
  'exp[(]'
  '\b61\b'
)

status=0
for pattern in "${PATTERNS[@]}"; do
  # --include limits this to shipping sources; previews and tests are exempt
  # because a preview inventing a number harms nobody.
  # `|| true` on the pipeline would swallow a BROKEN PATTERN as a pass. It did:
  # `exp(` is an unmatched group in ERE, grep exited 2, and the guard cheerfully
  # reported the app target clean. Exit 1 means "no matches" and is fine; exit 2
  # means grep could not run the pattern and must fail the check loudly.
  # errexit has to come OFF around this: grep exits 1 for "no matches", which
  # is the SUCCESS case here, and `set -e` would kill the script on the first
  # clean pattern — the guard would then pass by dying quietly, which is the
  # same false pass in a different costume.
  # `rc` is grep's exit for THIS pattern; `status` accumulates across all of
  # them. They were one variable, so each iteration clobbered the verdict — and
  # since the last pattern normally finds nothing, grep's exit 1 became a
  # permanent false FAILURE regardless of what any earlier pattern had found.
  set +e
  hits=$(grep -rnE "$pattern" "$APP" --include='*.swift' 2>&1)
  rc=$?
  set -e
  if [ $rc -gt 1 ]; then
    echo "BROKEN PATTERN '$pattern': $hits"
    exit 2
  fi
  hits=$(printf '%s' "$hits" | grep -v '_Preview' | grep -v '// math-ok:' || true)
  if [ -n "$hits" ]; then
    echo "FORBIDDEN: '$pattern' in the app target — this belongs in StudioKit."
    echo "$hits"
    status=1
  fi
done

if [ $status -eq 0 ]; then
  echo "check_no_studio_math: clean — the app target draws and does not compute."
else
  echo
  echo "If a line is genuinely presentational, append '// math-ok:' and say why."
fi
exit $status
