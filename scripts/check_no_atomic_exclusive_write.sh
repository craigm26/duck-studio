#!/bin/bash
# The rule: a Data write never asks for both `.atomic` and `.withoutOverwriting`.
#
# On the Swift-native Foundation that every iPhone since iOS 18 runs, that pair
# is not an error but a trap — `Data.swift`: "Fatal error: withoutOverwriting is
# not supported with atomic" — because an atomic write is a temp file renamed
# over the name and a rename cannot be exclusive. Build 58 of Microduck Studio
# crashed at the end of every evaluation run and on every imported log exactly
# there (EvalStore.save, 2026-09-05 crash report from TestFlight). No test can
# catch a fatalError inside Foundation, the Linux parity gate writes its files
# with Python, and the Mac compile gate is happy with the call — so this is the
# only gate that sees it. Same shape as check_no_studio_math.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

set +e
hits=$(grep -rnE '\.atomic[^]]*\.withoutOverwriting|\.withoutOverwriting[^]]*\.atomic' \
         "$ROOT/DuckStudio/Sources" "$ROOT/StudioKit/Sources" --include='*.swift' 2>&1)
rc=$?
set -e
if [ $rc -gt 1 ]; then
  echo "check_no_atomic_exclusive_write: grep could not run: $hits"
  exit 2
fi
if [ -n "$hits" ]; then
  echo "check_no_atomic_exclusive_write: FAIL — .atomic and .withoutOverwriting together trap on device:"
  echo "$hits"
  exit 1
fi
echo "check_no_atomic_exclusive_write: clean — no write asks for both .atomic and .withoutOverwriting."
