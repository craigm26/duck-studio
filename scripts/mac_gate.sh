#!/usr/bin/env bash
# The compile gate as an EXIT STATUS, not a thing to read.
#
# `mac_compile_check.py` prints xcodebuild's verdict, and reading it in a
# pipeline is how a failed build got committed once: `grep … | head` exits 0
# whatever the log said, and the `&& git commit` after it ran. This exits 0
# only when the log holds "** BUILD SUCCEEDED **" and no "error:" line from
# the compiler, and 1 otherwise, printing the offending lines. Use it as the
# left-hand side of `&&`.
#
#   python3 scripts/mac_compile_check.py --worktree > build.log 2>&1
#   bash scripts/mac_gate.sh build.log && git commit …
set -u
log="${1:?usage: mac_gate.sh <compile log>}"
errors=$(grep -E "error:" "$log" | grep -vE "IDELogStore|couldn.t be saved|didFailWithError|swift-backtrace" || true)
if grep -q "\*\* BUILD SUCCEEDED \*\*" "$log" && [ -z "$errors" ]; then
  echo "mac_gate: BUILD SUCCEEDED"
  exit 0
fi
echo "mac_gate: NOT GREEN"
grep -E "\*\* BUILD|EXIT=" "$log" | head -n 3
[ -n "$errors" ] && echo "$errors" | head -n 8
exit 1
